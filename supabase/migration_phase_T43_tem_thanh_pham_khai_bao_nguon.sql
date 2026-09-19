-- ============================================================================
-- Phase T43 — Khai báo tường minh "tem Đúc đang dùng" ở cuối chuyền, thay cho
-- FIFO ngầm hoàn toàn tự động (T40/T41). Theo đúng yêu cầu thực tế: dây
-- chuyền Đánh bóng lấy 5-7 thùng Đúc về 1 lúc, người ở cuối chuyền đọc tem
-- thùng đang đánh, khi thùng đó hết thì hệ thống báo & bắt đọc tem thùng kế
-- tiếp trước khi trừ nguồn tiếp — KHÔNG cho hệ thống tự nhảy sang 1 tem Đúc
-- khác mà người vận hành không biết. Tem Đúc đã dùng hết KHÔNG được khai báo
-- lại (chặn đọc nhầm tem cũ).
--
-- Cách làm: thêm 1 cột mốc thời gian "bắt đầu dùng" trên duc_tem — set 1 lần
-- khi khai báo (giữ nguyên nếu khai báo lại tem đang dùng dở, không dời thứ
-- tự). cd_ghi_nhan_tem_thanh_pham đổi nguồn hợp lệ từ "mọi tem đã chuyển công
-- đoạn, mới nhất trước" (T40) sang "CHỈ tem đã được khai báo đang dùng, theo
-- đúng thứ tự khai báo" — vẫn giữ nguyên khả năng 1 tem thành phẩm lấy từ 2
-- tem Đúc (150/60 không chia hết, không tránh được), chỉ khác là thứ tự dùng
-- do người vận hành chủ động khai báo, không phải hệ thống tự chọn ngầm.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

alter table public.duc_tem add column if not exists thoi_diem_bat_dau_dung timestamptz;

-- Khai báo 1 tem Đúc là "đang dùng" tại 1 công đoạn — gọi mỗi khi người vận
-- hành đọc tem thùng đang đánh ở cuối chuyền.
create or replace function cd_khai_bao_nguon_dang_dung(
  p_tag_no text,
  p_cong_doan text,
  p_nguoi text
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_tem duc_tem%rowtype;
  v_vi_tri text;
begin
  if p_tag_no is null or trim(p_tag_no) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu Tag No');
  end if;
  if p_cong_doan is null or trim(p_cong_doan) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu công đoạn');
  end if;

  select * into v_tem from duc_tem where tag_no = trim(p_tag_no) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || p_tag_no);
  end if;

  if coalesce(v_tem.so_luong, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error',
      'Tem ' || p_tag_no || ' đã dùng hết — không thể khai báo lại', 'da_het', true);
  end if;

  select cong_doan_nhan into v_vi_tri
  from cd_chuyen_cong_doan_log
  where tag_no = v_tem.tag_no and trang_thai_xac_nhan = 'Đã xác nhận chuyển công đoạn'
  order by thoi_gian_chuyen desc limit 1;

  if v_vi_tri is distinct from p_cong_doan then
    return jsonb_build_object('ok', false, 'error',
      'Tem ' || p_tag_no || ' chưa được Chuyển công đoạn (đã xác nhận) tới ' || p_cong_doan
      || coalesce(' — hiện đang ở ' || v_vi_tri, ' — chưa chuyển tới đâu'));
  end if;

  update duc_tem set thoi_diem_bat_dau_dung = coalesce(thoi_diem_bat_dau_dung, now())
  where tag_no = v_tem.tag_no
  returning * into v_tem;

  return jsonb_build_object(
    'ok', true, 'tag_no', v_tem.tag_no, 'ma_sp', v_tem.ma_sp, 'ten_sp', v_tem.ten_sp,
    'so_luong_con_lai', v_tem.so_luong,
    'da_khai_bao_truoc_do', v_tem.thoi_diem_bat_dau_dung is not null
  );
end;
$$;

-- Ghi nhận thùng thành phẩm — CHỈ trừ từ tem Đúc ĐÃ KHAI BÁO đang dùng (cùng
-- công đoạn/mã SP), theo đúng thứ tự khai báo (không phải theo thời điểm
-- chuyển công đoạn nữa). Vẫn có thể chia 1 thùng thành phẩm lấy từ 2 tem Đúc
-- liền kề trong hàng đợi khai báo.
drop function if exists cd_ghi_nhan_tem_thanh_pham(text, text, text);
create or replace function cd_ghi_nhan_tem_thanh_pham(
  p_tag_no text,
  p_nguoi_kiem text,
  p_id_tram text
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_tem duc_tem%rowtype;
  v_need numeric;
  v_take numeric;
  v_src record;
  v_used jsonb := '[]'::jsonb;
  v_het jsonb := '[]'::jsonb;
begin
  if p_tag_no is null or trim(p_tag_no) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu Tag No');
  end if;
  if p_nguoi_kiem is null or trim(p_nguoi_kiem) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu người kiểm tra');
  end if;

  select * into v_tem from duc_tem where tag_no = trim(p_tag_no) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || p_tag_no);
  end if;
  if v_tem.trang_thai <> 'Chờ đóng gói TP' then
    if v_tem.trang_thai = 'Đã đóng gói TP' then
      return jsonb_build_object(
        'ok', false,
        'error', 'Tem ' || p_tag_no || ' đã được ghi nhận lúc '
          || to_char(v_tem.ngay_gio_ghi_nhan at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM')
          || ' bởi ' || coalesce(v_tem.nguoi_tt, '(không rõ)'),
        'da_ghi_nhan', true
      );
    end if;
    return jsonb_build_object('ok', false, 'error', 'Tem ' || p_tag_no || ' không phải tem thành phẩm chờ đóng gói');
  end if;

  v_need := v_tem.so_luong;

  for v_src in
    select tag_no, so_luong
    from duc_tem
    where ma_sp = v_tem.ma_sp
      and thoi_diem_bat_dau_dung is not null
      and so_luong > 0
    order by thoi_diem_bat_dau_dung asc
    for update
  loop
    exit when v_need <= 0;
    v_take := least(v_need, v_src.so_luong);
    update duc_tem set so_luong = so_luong - v_take where tag_no = v_src.tag_no;
    insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay)
    values (v_tem.tag_no, v_src.tag_no, v_take)
    on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
    v_used := v_used || jsonb_build_array(jsonb_build_object('tag_no', v_src.tag_no, 'so_luong_lay', v_take));
    if v_src.so_luong - v_take <= 0 then
      v_het := v_het || jsonb_build_array(v_src.tag_no);
    end if;
    v_need := v_need - v_take;
  end loop;

  if v_need > 0 then
    raise exception 'Chưa đủ nguồn từ tem Đúc ĐÃ KHAI BÁO đang dùng cho mã % (còn thiếu % pcs) — đọc tem thùng Đúc tiếp theo rồi ghi nhận lại',
      v_tem.ma_sp, v_need;
  end if;

  update duc_tem set
    so_luong_tt = so_luong,
    nguoi_tt = p_nguoi_kiem,
    trang_thai = 'Đã đóng gói TP',
    ghi_chu_sl = 'Đã ghi nhận thành phẩm',
    ngay_gio_ghi_nhan = now(),
    ngay_gio_xuat = now()
  where tag_no = v_tem.tag_no;

  if p_id_tram is not null and trim(p_id_tram) <> '' then
    perform cd_tram_nhap_sanluong(p_id_tram, v_tem.so_luong, 0, 'Ghi nhận tem thành phẩm ' || v_tem.tag_no, p_nguoi_kiem);
  end if;

  return jsonb_build_object(
    'ok', true,
    'tag_no', v_tem.tag_no,
    'ma_sp', v_tem.ma_sp,
    'ten_sp', v_tem.ten_sp,
    'so_luong', v_tem.so_luong,
    'so_thung_stt', v_tem.so_thung_stt,
    'nguoi_kiem', p_nguoi_kiem,
    'nguon', v_used,
    'nguon_vua_het', v_het,
    'ngay_gio_ghi_nhan', now()
  );
end;
$$;

revoke execute on function cd_khai_bao_nguon_dang_dung(text, text, text) from anon;
grant  execute on function cd_khai_bao_nguon_dang_dung(text, text, text) to authenticated;

revoke execute on function cd_ghi_nhan_tem_thanh_pham(text, text, text) from anon;
grant  execute on function cd_ghi_nhan_tem_thanh_pham(text, text, text) to authenticated;
