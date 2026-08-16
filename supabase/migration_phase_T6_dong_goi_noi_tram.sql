-- ============================================================================
-- Phase T6 — Nối "Đóng gói lại" với trạm/line/máy đang hoạt động trên
-- cong-doan-dashboard.html: 1 lần nhập, đúng cả 2 nơi.
--
-- Trước đây (T2/T3): 2 lớp CỐ Ý tách biệt — lớp tem/QR (chuyencongdoan.html)
-- và lớp trạm/sản lượng (cong-doan-dashboard.html) không link cứng. Người
-- dùng phản hồi thực tế: (1) NG phát sinh khi đóng gói làm số lượng ra/vào
-- không khớp — cần khai NG ngay lúc đóng gói, KHÔNG để tồn lơ lửng trên tem
-- nguồn; (2) mỗi tem mới cần biết rõ ai/trạm nào/lúc nào làm ra nó. Quyết
-- định mới: ĐÓNG GÓI LẠI giờ chọn 1 trạm đang hoạt động — người thao tác/
-- ngày/ca tự điền theo trạm đó, NG khai lúc đóng gói tự cộng vào đúng trạm.
--
-- 3 phần:
--   1) duc_tem thêm cột tram_cong_doan/thoi_diem_san_xuat — thông tin SẢN
--      XUẤT TẠI CÔNG ĐOẠN HIỆN TẠI (khác nguoi_tt/ngay_gio_in cũ vốn là dấu
--      vết ai/lúc nào BẤM NÚT tạo tem trên hệ thống — nay nguoi_tt vẫn giữ
--      nguyên ý nghĩa đó, thêm 2 cột mới cho đúng ý "ai/lúc nào sản xuất
--      thực tế ra sản phẩm này").
--   2) cd_dong_goi_lai — thêm tham số p_id_tram (optional), p_tram (tên tự
--      do nếu không gắn trạm có sẵn), p_nguoi_thao_tac, p_thoi_diem_sx,
--      p_ng_hao_hut. NG hao hụt trừ thẳng vào tem nguồn (như 1 "đơn vị đầu
--      ra" nhưng KHÔNG tạo tem mới) và cộng vào cd_bao_cao_ca — nếu có
--      p_id_tram thì cộng thẳng vào so_luong_ng của đúng trạm đó
--      (cd_tram_nhap_sanluong), không thì cộng trực tiếp cd_bao_cao_ca theo
--      ngày/ca/công đoạn/mã SP người dùng chọn tay.
--
-- Phải DROP rồi tạo lại cd_dong_goi_lai vì đổi tham số (đổi identity hàm).
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

alter table duc_tem add column if not exists tram_cong_doan text;
alter table duc_tem add column if not exists thoi_diem_san_xuat timestamptz;

drop function if exists cd_dong_goi_lai(text, text[], numeric[], text);
create or replace function cd_dong_goi_lai(
  p_cong_doan text, p_tag_no_nguon text[], p_so_luong_moi numeric[],
  p_id_tram text, p_tram text, p_nguoi_thao_tac text, p_thoi_diem_sx timestamptz,
  p_ng_hao_hut numeric, p_ngay date, p_ca text,
  p_nguoi text
)
returns table(tag_no_moi text, so_luong numeric, ma_sp text, ten_sp text, ngay date, lot text, so_khuon text, nguyen_lieu text, may_duc text)
language plpgsql
security definer
as $$
declare
  v_src duc_tem%rowtype;
  v_ma_sp text;
  v_ten_sp text;
  v_ngay_moi date;
  v_lot_moi text[] := array[]::text[];
  v_so_khuon_moi text[] := array[]::text[];
  v_nl_moi text[] := array[]::text[];
  v_may_moi text[] := array[]::text[];
  v_remaining numeric[];
  v_total_available numeric := 0;
  v_total_requested numeric := 0;
  v_n_src int;
  v_n_out int;
  i int;
  j int;
  v_need numeric;
  v_take numeric;
  v_new_tag text;
  v_now timestamptz := now();
  v_sx_time timestamptz := coalesce(p_thoi_diem_sx, now());
  v_ng numeric := coalesce(p_ng_hao_hut, 0);
  v_tram_ten text;
begin
  if p_cong_doan is null or trim(p_cong_doan) = '' then
    raise exception 'Thiếu công đoạn';
  end if;
  if p_tag_no_nguon is null or array_length(p_tag_no_nguon, 1) is null then
    raise exception 'Chưa quét tem nguồn nào';
  end if;
  if (p_so_luong_moi is null or array_length(p_so_luong_moi, 1) is null) and v_ng <= 0 then
    raise exception 'Chưa nhập đơn vị đóng gói mới nào (hoặc NG hao hụt)';
  end if;
  if (select count(*) from unnest(p_tag_no_nguon) t) <> (select count(distinct t) from unnest(p_tag_no_nguon) t) then
    raise exception 'Có tem nguồn bị quét trùng lặp';
  end if;

  -- Trạm gắn sẵn (nếu có) — lấy tên trạm thật để lưu lên tem cho dễ đọc, và
  -- để biết chắc trạm đó cùng công đoạn (tránh gán nhầm trạm công đoạn khác).
  if p_id_tram is not null and trim(p_id_tram) <> '' then
    select ten_tram into v_tram_ten from cd_tram_hien_tai where id_tram = p_id_tram;
    if not found then raise exception 'Không tìm thấy trạm: %', p_id_tram; end if;
  else
    v_tram_ten := nullif(trim(coalesce(p_tram, '')), '');
  end if;

  v_n_src := array_length(p_tag_no_nguon, 1);
  v_n_out := coalesce(array_length(p_so_luong_moi, 1), 0);
  v_remaining := array_fill(0::numeric, array[v_n_src]);

  for i in 1 .. v_n_src loop
    select * into v_src from duc_tem where tag_no = p_tag_no_nguon[i] for update;
    if not found then
      raise exception 'Không tìm thấy tem %', p_tag_no_nguon[i];
    end if;
    if coalesce(v_src.so_luong, 0) <= 0 then
      raise exception 'Tem % đã hết số lượng, không dùng làm nguồn được', p_tag_no_nguon[i];
    end if;

    if v_ma_sp is null then
      v_ma_sp := v_src.ma_sp; v_ten_sp := v_src.ten_sp;
    elsif v_ma_sp <> v_src.ma_sp then
      raise exception 'Các tem nguồn không cùng mã SP (% và %)', v_ma_sp, v_src.ma_sp;
    end if;

    if v_ngay_moi is null or (v_src.ngay is not null and v_src.ngay < v_ngay_moi) then
      v_ngay_moi := v_src.ngay;
    end if;
    if v_src.lot is not null and v_src.lot <> '' and not (v_src.lot = any(v_lot_moi)) then v_lot_moi := array_append(v_lot_moi, v_src.lot); end if;
    if v_src.so_khuon is not null and v_src.so_khuon <> '' and not (v_src.so_khuon = any(v_so_khuon_moi)) then v_so_khuon_moi := array_append(v_so_khuon_moi, v_src.so_khuon); end if;
    if v_src.nguyen_lieu is not null and v_src.nguyen_lieu <> '' and not (v_src.nguyen_lieu = any(v_nl_moi)) then v_nl_moi := array_append(v_nl_moi, v_src.nguyen_lieu); end if;
    if v_src.may_duc_chi_thi is not null and v_src.may_duc_chi_thi <> '' and not (v_src.may_duc_chi_thi = any(v_may_moi)) then v_may_moi := array_append(v_may_moi, v_src.may_duc_chi_thi); end if;

    v_remaining[i] := v_src.so_luong;
    v_total_available := v_total_available + v_src.so_luong;
  end loop;

  for j in 1 .. v_n_out loop
    if p_so_luong_moi[j] is null or p_so_luong_moi[j] <= 0 then
      raise exception 'Số lượng đơn vị đóng gói thứ % không hợp lệ', j;
    end if;
    v_total_requested := v_total_requested + p_so_luong_moi[j];
  end loop;
  v_total_requested := v_total_requested + v_ng;

  if v_total_requested > v_total_available then
    raise exception 'Tổng số lượng đóng gói + NG (%) vượt quá tổng số lượng tem nguồn (%)', v_total_requested, v_total_available;
  end if;

  i := 1;
  for j in 1 .. v_n_out loop
    v_new_tag := cd_next_tag_no_dong_goi();

    insert into duc_tem (
      tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
      may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
      nguoi_tt, trang_thai, ghi_chu_sl, tram_cong_doan, thoi_diem_san_xuat
    ) values (
      v_new_tag, v_ten_sp, v_ma_sp, p_so_luong_moi[j], v_ngay_moi,
      array_to_string(v_lot_moi, ', '), array_to_string(v_so_khuon_moi, ', '), array_to_string(v_nl_moi, ', '),
      array_to_string(v_may_moi, ', '), 'Đóng gói lại tại ' || p_cong_doan, v_now,
      array_to_string(v_so_khuon_moi, ', '), p_so_luong_moi[j], array_to_string(v_may_moi, ', '),
      coalesce(nullif(trim(p_nguoi_thao_tac), ''), p_nguoi), 'Đóng gói lại', 'Đóng gói tại ' || p_cong_doan,
      v_tram_ten, v_sx_time
    );

    insert into cd_chuyen_cong_doan_log (
      id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
      lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan,
      nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan
    ) values (
      cd_next_transfer_id(), v_now, v_new_tag, v_ma_sp, v_ten_sp, p_so_luong_moi[j], p_so_luong_moi[j], 0,
      array_to_string(v_lot_moi, ', '), array_to_string(v_so_khuon_moi, ', '), array_to_string(v_nl_moi, ', '),
      array_to_string(v_may_moi, ', '), coalesce(v_ngay_moi::text, ''), p_cong_doan, p_cong_doan,
      p_nguoi, p_nguoi, 'Đã xác nhận chuyển công đoạn', to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
    );

    v_need := p_so_luong_moi[j];
    while v_need > 0 loop
      if i > v_n_src then raise exception 'Lỗi phân bổ số lượng nguồn cho tem % — liên hệ kỹ thuật', v_new_tag; end if;
      if v_remaining[i] > 0 then
        v_take := least(v_need, v_remaining[i]);
        v_remaining[i] := v_remaining[i] - v_take;
        v_need := v_need - v_take;
        insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay)
        values (v_new_tag, p_tag_no_nguon[i], v_take)
        on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
      end if;
      if v_remaining[i] <= 0 then i := i + 1; end if;
    end loop;

    tag_no_moi := v_new_tag; so_luong := p_so_luong_moi[j]; ma_sp := v_ma_sp; ten_sp := v_ten_sp;
    ngay := v_ngay_moi; lot := array_to_string(v_lot_moi, ', '); so_khuon := array_to_string(v_so_khuon_moi, ', ');
    nguyen_lieu := array_to_string(v_nl_moi, ', '); may_duc := array_to_string(v_may_moi, ', ');
    return next;
  end loop;

  -- NG hao hụt — trừ thẳng vào tem nguồn (KHÔNG tạo tem mới), rồi cộng vào
  -- đúng trạm nếu có (real-time), hoặc thẳng vào cd_bao_cao_ca theo ngày/ca
  -- người dùng chọn tay nếu đóng gói không gắn trạm.
  if v_ng > 0 then
    v_need := v_ng;
    while v_need > 0 loop
      if i > v_n_src then raise exception 'Lỗi phân bổ NG hao hụt — vượt quá tem nguồn còn lại'; end if;
      if v_remaining[i] > 0 then
        v_take := least(v_need, v_remaining[i]);
        v_remaining[i] := v_remaining[i] - v_take;
        v_need := v_need - v_take;
      end if;
      if v_remaining[i] <= 0 then i := i + 1; end if;
    end loop;

    if p_id_tram is not null and trim(p_id_tram) <> '' then
      perform cd_tram_nhap_sanluong(p_id_tram, 0, v_ng, 'NG phát hiện lúc đóng gói lại tem ' || array_to_string(p_tag_no_nguon, ', '), p_nguoi);
    elsif p_ngay is not null and p_ca is not null and trim(coalesce(p_ca, '')) <> '' then
      perform cd_gop_tally_vao_bao_cao(p_ngay, p_ca, p_cong_doan, v_ma_sp, v_ten_sp, coalesce(v_tram_ten, ''), 0, v_ng, 'NG phát hiện lúc đóng gói lại');
    else
      raise exception 'Có NG hao hụt nhưng chưa chọn trạm hoặc chưa chọn ngày/ca để ghi vào báo cáo';
    end if;
  end if;

  for i in 1 .. v_n_src loop
    update duc_tem set so_luong = v_remaining[i] where tag_no = p_tag_no_nguon[i];
  end loop;

  return;
end;
$$;
revoke execute on function cd_dong_goi_lai(text, text[], numeric[], text, text, text, timestamptz, numeric, date, text, text) from anon;
grant execute on function cd_dong_goi_lai(text, text[], numeric[], text, text, text, timestamptz, numeric, date, text, text) to authenticated;
