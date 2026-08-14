-- ============================================================================
-- Phase 3 (cutover ghi) — module Chuyển công đoạn
-- Bổ sung cho supabase/schema_chuyencongdoan.sql (đã chạy trước đó, có dữ liệu).
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
--
-- Mục đích: thay thế `_genTransferId()` (ChuyenCongDoan.gs:231-253 — quét toàn
-- cột A tìm số lớn nhất trong ngày, dưới LockService) bằng 1 hàm Postgres sinh
-- ID nguyên tử, giữ đúng format "CD{yyyyMMdd}-{seq 4 chữ số}", reset về 1 mỗi
-- ngày mới — không cần khoá ở tầng Apps Script nữa cho việc sinh ID.
-- ============================================================================

-- Bảng đếm theo ngày (không phải bảng nghiệp vụ — chỉ giữ counter).
create table if not exists cd_transfer_id_counter (
  ngay date primary key,
  last_seq int not null default 0
);

-- Sinh ID kế tiếp, atomic dưới concurrency (upsert giữ row lock trong lúc update).
-- Trả về đúng format cũ: "CD20260813-0007".
create or replace function cd_next_transfer_id()
returns text
language plpgsql
security definer
as $$
declare
  d date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  next_seq int;
begin
  insert into cd_transfer_id_counter (ngay, last_seq)
  values (d, 1)
  on conflict (ngay) do update set last_seq = cd_transfer_id_counter.last_seq + 1
  returning last_seq into next_seq;

  return 'CD' || to_char(d, 'YYYYMMDD') || '-' || lpad(next_seq::text, 4, '0');
end;
$$;

-- Ghi 1 lượt chuyển công đoạn — gói trọn "append log" trong 1 lệnh gọi RPC.
-- KHÔNG cần ghi ViTriHienTai nữa — cd_v_vi_tri_hien_tai (đã có trong schema
-- gốc) tự suy ra vị trí hiện tại từ chính bảng log này.
-- Business logic giữ nguyên như WA_ChuyenCongDoan (ChuyenCongDoan.gs:256-293)
-- — Apps Script vẫn validate input, chỉ đổi hàm ghi cuối cùng.
create or replace function cd_ghi_chuyen_cong_doan(
  p_tag_no text, p_ma_sp text, p_ten_sp text,
  p_sl_tren_tem numeric, p_sl_thuc_chuyen numeric,
  p_lot_no text, p_so_khuon text, p_nguyen_lieu text, p_may_duc text, p_ngay_duc text,
  p_cong_doan_giao text, p_cong_doan_nhan text,
  p_nguoi_giao text, p_nguoi_nhan text
)
returns table(id_phieu text, thoi_gian_chuyen timestamptz, chenh_lech numeric)
language plpgsql
security definer
as $$
declare
  v_id text := cd_next_transfer_id();
  v_now timestamptz := now();
  v_chenh_lech numeric := p_sl_tren_tem - p_sl_thuc_chuyen;
begin
  insert into cd_chuyen_cong_doan_log (
    id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp,
    sl_tren_tem, sl_thuc_chuyen, chenh_lech,
    lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc,
    cong_doan_giao, cong_doan_nhan, nguoi_giao, nguoi_nhan,
    trang_thai_xac_nhan
  ) values (
    v_id, v_now, p_tag_no, p_ma_sp, p_ten_sp,
    p_sl_tren_tem, p_sl_thuc_chuyen, v_chenh_lech,
    p_lot_no, p_so_khuon, p_nguyen_lieu, p_may_duc, p_ngay_duc,
    p_cong_doan_giao, p_cong_doan_nhan, p_nguoi_giao, p_nguoi_nhan,
    'Chờ công đoạn trước xác nhận'
  );
  return query select v_id, v_now, v_chenh_lech;
end;
$$;

-- Xác nhận lượt chuyển (thay 3 setValue trong XacNhanChuyenCongDoan.gs:88-142).
create or replace function cd_xac_nhan_chuyen(
  p_id_phieu text, p_nguoi_giao text, p_ngay_gio_xac_nhan text
)
returns void
language sql
security definer
as $$
  update cd_chuyen_cong_doan_log
  set nguoi_giao = p_nguoi_giao,
      trang_thai_xac_nhan = 'Đã xác nhận chuyển công đoạn',
      ngay_gio_xac_nhan = p_ngay_gio_xac_nhan
  where id_phieu = p_id_phieu;
$$;

-- RPC chạy qua service_role key (Apps Script) — không cần policy INSERT/UPDATE
-- riêng cho anon vì service_role bỏ qua RLS mặc định.
