-- ============================================================================
-- Phase T40 — Tem Thành Phẩm (60pcs/thùng, công đoạn Đánh bóng): in trước lô
-- tem (giống Kanban Đúc) + quét ghi nhận thùng, tự động trừ FIFO từ các tem
-- Đúc đang có mặt tại công đoạn (qua cd_v_vi_tri_hien_tai), ghi lineage vào
-- cd_tem_nguon — dùng LẠI đúng cơ chế của cd_dong_goi_lai (T2/T6), chỉ khác
-- chỗ nguồn được chọn TỰ ĐỘNG (FIFO theo thời điểm chuyển công đoạn) thay vì
-- người dùng quét tay từng tem nguồn — vì tem thành phẩm in trước, người thao
-- tác chỉ quét 1 lần khi thùng đầy, không quét lại từng tem Đúc.
--
-- Bố cục tem đã duyệt qua Artifact (không liên quan SQL) — xem field mới bên
-- dưới: Mã SP tại khách hàng (mới, khác "Mã khách hàng" của T17 — đó là mã
-- ĐỊNH DANH KHÁCH HÀNG, còn đây là SỐ SKU sản phẩm phía khách hàng).
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- 1) Danh mục SP — thêm "Mã SP tại khách hàng"
alter table public.master_products add column if not exists ma_sp_khach_hang text;

-- 2) duc_tem — đóng vai trò bảng chứa CẢ tem thành phẩm (giống cách
--    cd_dong_goi_lai/duc_tao_lo_kanban đều ghi vào duc_tem) — thêm 2 cột đông
--    lạnh Mã SP tại KH / Tên khách hàng tại thời điểm in (khớp danh mục lúc
--    đó, không đổi theo nếu sau này danh mục sửa).
alter table public.duc_tem add column if not exists ma_sp_khach_hang text;
alter table public.duc_tem add column if not exists ten_khach_hang text;

-- 3) Sinh Tag No tem thành phẩm — prefix "TP", cùng cơ chế duc_tag_no_counter
--    dùng chung với TKD/D-TKD/PK (duc_next_tag_no, cd_next_tag_no_dong_goi).
create or replace function cd_next_tag_no_thanh_pham()
returns text
language plpgsql
security definer
as $$
declare
  d date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  key text := 'TP' || to_char(d, 'YYYYMMDD');
  next_seq int;
begin
  insert into duc_tag_no_counter (prefix_ngay, last_seq)
  values (key, 1)
  on conflict (prefix_ngay) do update set last_seq = duc_tag_no_counter.last_seq + 1
  returning last_seq into next_seq;

  return key || '-' || lpad(next_seq::text, 4, '0');
end;
$$;

-- 4) In trước 1 lô tem thành phẩm — giống hệt duc_tao_lo_kanban nhưng:
--      - trang_thai riêng 'Chờ đóng gói TP' (phân biệt với Kanban 'Chờ sản
--        xuất' — 2 luồng ghi nhận RPC khác nhau, không lẫn tem giữa 2 màn).
--      - so_luong = quy cách đóng gói công đoạn (p_sl_thung — Đánh bóng = 60,
--        KHÔNG lấy từ master_products.sl_dong_goi_chuan vì cột đó đang giữ
--        quy cách của Đúc/150 — xem CONFIG.PACKAGING trong chuyencongdoan.html).
--      - "Người kiểm tra" (p_nguoi_kiem) IN SẴN lên tem/QR ngay từ lúc tạo lô
--        (khác Kanban, nơi người thao tác chỉ biết lúc quét) — vì tem thành
--        phẩm chỉ cần quét 1 lần, không nhập gì thêm lúc quét.
create or replace function cd_tao_lo_tem_thanh_pham(
  p_cong_doan text,
  p_ma_sp text,
  p_ngay date,
  p_so_thung int,
  p_sl_thung numeric,
  p_sl_thung_cuoi numeric,
  p_nguoi_kiem text,
  p_nguoi text
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_ten_sp text;
  v_ma_kh text;
  v_ten_kh text;
  v_lo text;
  v_tag text;
  v_sl numeric;
  v_tems jsonb := '[]'::jsonb;
  i int;
begin
  if p_cong_doan is null or trim(p_cong_doan) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu công đoạn');
  end if;
  if p_ma_sp is null or trim(p_ma_sp) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu mã SP');
  end if;
  if p_ngay is null then
    return jsonb_build_object('ok', false, 'error', 'Thiếu ngày sản xuất');
  end if;
  if coalesce(p_so_thung, 0) < 1 then
    return jsonb_build_object('ok', false, 'error', 'Số thùng phải >= 1');
  end if;
  if p_so_thung > 500 then
    return jsonb_build_object('ok', false, 'error', 'Tối đa 500 tem/lô');
  end if;
  if coalesce(p_sl_thung, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Thiếu quy cách SL/thùng của công đoạn ' || p_cong_doan);
  end if;
  if p_nguoi_kiem is null or trim(p_nguoi_kiem) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu người kiểm tra');
  end if;

  select ten_sp, ma_sp_khach_hang, ten_khach_hang into v_ten_sp, v_ma_kh, v_ten_kh
  from master_products where ma_sp = p_ma_sp;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Mã SP không có trong danh mục: ' || p_ma_sp);
  end if;

  v_lo := 'TP' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYYMMDDHH24MISS')
          || '_' || regexp_replace(p_cong_doan, '\s+', '', 'g');

  for i in 1..p_so_thung loop
    v_tag := cd_next_tag_no_thanh_pham();
    if i = p_so_thung and coalesce(p_sl_thung_cuoi, 0) > 0 then
      v_sl := p_sl_thung_cuoi;
    else
      v_sl := p_sl_thung;
    end if;

    insert into duc_tem (
      tag_no, ten_sp, ma_sp, so_luong, ngay, lot,
      ma_sp_khach_hang, ten_khach_hang,
      may_duc_chi_thi, ghi_chu, ngay_gio_in, nguoi_tt,
      trang_thai, ghi_chu_sl, tram_cong_doan,
      id_lo_chi_thi, so_thung_stt
    ) values (
      v_tag, v_ten_sp, p_ma_sp, v_sl, p_ngay, p_ngay::text,
      v_ma_kh, v_ten_kh,
      null, 'Tem thành phẩm ' || p_cong_doan || ' — ngày ' || to_char(p_ngay, 'DD/MM/YYYY') || ' — thùng ' || i || '/' || p_so_thung,
      now(), p_nguoi_kiem,
      'Chờ đóng gói TP', 'Chờ ghi nhận thành phẩm', p_cong_doan,
      v_lo, i
    );

    v_tems := v_tems || jsonb_build_array(jsonb_build_object(
      'tag_no', v_tag, 'ma_sp', p_ma_sp, 'ten_sp', v_ten_sp, 'so_luong', v_sl,
      'ma_sp_khach_hang', v_ma_kh, 'ten_khach_hang', v_ten_kh,
      'nguoi_kiem', p_nguoi_kiem, 'ngay', p_ngay, 'so_thung_stt', i, 'tong_so_thung', p_so_thung
    ));
  end loop;

  return jsonb_build_object('ok', true, 'id_lo_chi_thi', v_lo, 'so_tem', p_so_thung, 'tems', v_tems);
end;
$$;

-- 5) Quét ghi nhận thùng thành phẩm — tự trừ FIFO từ các tem Đúc đang ở đúng
--    công đoạn (theo cd_chuyen_cong_doan_log, lượt chuyển GẦN NHẤT của mỗi
--    tem, ĐÃ xác nhận), cùng mã SP, còn số lượng > 0 — y hệt phần phân bổ
--    nguồn của cd_dong_goi_lai (T6) nhưng chọn nguồn tự động thay vì theo
--    mảng tag_no người dùng quét tay.
create or replace function cd_ghi_nhan_tem_thanh_pham(
  p_tag_no text,
  p_id_tram text,
  p_nguoi text
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
begin
  if p_tag_no is null or trim(p_tag_no) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu Tag No');
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
          || to_char(v_tem.ngay_gio_ghi_nhan at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'),
        'da_ghi_nhan', true
      );
    end if;
    return jsonb_build_object('ok', false, 'error', 'Tem ' || p_tag_no || ' không phải tem thành phẩm chờ đóng gói');
  end if;

  v_need := v_tem.so_luong;

  for v_src in
    with latest as (
      select distinct on (tag_no) tag_no, cong_doan_nhan, trang_thai_xac_nhan, thoi_gian_chuyen
      from cd_chuyen_cong_doan_log
      order by tag_no, thoi_gian_chuyen desc
    )
    select t.tag_no, t.so_luong
    from duc_tem t
    join latest l on l.tag_no = t.tag_no
    where l.cong_doan_nhan = v_tem.tram_cong_doan
      and l.trang_thai_xac_nhan = 'Đã xác nhận chuyển công đoạn'
      and t.ma_sp = v_tem.ma_sp
      and t.so_luong > 0
    order by l.thoi_gian_chuyen asc
    for update of t
  loop
    exit when v_need <= 0;
    v_take := least(v_need, v_src.so_luong);
    update duc_tem set so_luong = so_luong - v_take where tag_no = v_src.tag_no;
    insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay)
    values (v_tem.tag_no, v_src.tag_no, v_take)
    on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
    v_used := v_used || jsonb_build_array(jsonb_build_object('tag_no', v_src.tag_no, 'so_luong_lay', v_take));
    v_need := v_need - v_take;
  end loop;

  if v_need > 0 then
    raise exception 'Không đủ tem Đúc khả dụng tại % cho mã SP % (còn thiếu % pcs) — kiểm tra đã "Chuyển công đoạn" đủ chưa',
      v_tem.tram_cong_doan, v_tem.ma_sp, v_need;
  end if;

  update duc_tem set
    so_luong_tt = so_luong,
    trang_thai = 'Đã đóng gói TP',
    ghi_chu_sl = 'Đã ghi nhận thành phẩm',
    ngay_gio_ghi_nhan = now(),
    ngay_gio_xuat = now()
  where tag_no = v_tem.tag_no;

  if p_id_tram is not null and trim(p_id_tram) <> '' then
    perform cd_tram_nhap_sanluong(p_id_tram, v_tem.so_luong, 0, 'Ghi nhận tem thành phẩm ' || v_tem.tag_no, p_nguoi);
  end if;

  return jsonb_build_object(
    'ok', true,
    'tag_no', v_tem.tag_no,
    'ma_sp', v_tem.ma_sp,
    'ten_sp', v_tem.ten_sp,
    'so_luong', v_tem.so_luong,
    'so_thung_stt', v_tem.so_thung_stt,
    'nguon', v_used,
    'ngay_gio_ghi_nhan', now()
  );
end;
$$;

revoke execute on function cd_next_tag_no_thanh_pham() from anon;
grant  execute on function cd_next_tag_no_thanh_pham() to authenticated;

revoke execute on function cd_tao_lo_tem_thanh_pham(text, text, date, int, numeric, numeric, text, text) from anon;
grant  execute on function cd_tao_lo_tem_thanh_pham(text, text, date, int, numeric, numeric, text, text) to authenticated;

revoke execute on function cd_ghi_nhan_tem_thanh_pham(text, text, text) from anon;
grant  execute on function cd_ghi_nhan_tem_thanh_pham(text, text, text) to authenticated;
