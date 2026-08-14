-- ============================================================================
-- Phase 4, bước con 2 (cutover ghi) — module In tem công đoạn Đúc
-- Bổ sung cho supabase/schema_duc.sql (đã chạy trước đó, có dữ liệu duc_tem).
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
--
-- Mục đích: thay thế _genTagNo() (Intem QR/Code.gs:254-277 — quét toàn cột A
-- tìm số lớn nhất trong ngày theo tiền tố TKD/D-TKD, dưới LockService) bằng
-- 1 hàm Postgres sinh TagNo nguyên tử, giữ đúng format "{prefix}{yyyyMMdd}-
-- {seq 4 chữ số}", reset về 1 mỗi ngày MỚI THEO TỪNG PREFIX (hàng loạt và
-- phát triển đếm riêng, đúng hành vi cũ vì pre = prefix + ngày).
-- ============================================================================

create table if not exists duc_tag_no_counter (
  prefix_ngay text primary key,   -- VD "TKD20260813" hoặc "D-TKD20260813"
  last_seq    int not null default 0
);

create or replace function duc_next_tag_no(p_loai_sp text)
returns text
language plpgsql
security definer
as $$
declare
  d date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  prefix text := case when p_loai_sp = 'phattrien' then 'D-TKD' else 'TKD' end;
  d_str text := to_char(d, 'YYYYMMDD');
  key text := prefix || d_str;
  next_seq int;
begin
  insert into duc_tag_no_counter (prefix_ngay, last_seq)
  values (key, 1)
  on conflict (prefix_ngay) do update set last_seq = duc_tag_no_counter.last_seq + 1
  returning last_seq into next_seq;

  return prefix || d_str || '-' || lpad(next_seq::text, 4, '0');
end;
$$;

-- Ghi 1 tem mới — gói trọn "sinh TagNo + insert duc_tem" trong 1 lệnh gọi RPC.
-- Business logic giữ nguyên như WA_InTem/_ghiDUC (Intem QR/Code.gs:92-119,
-- 279-295) — Apps Script vẫn build QR string, chỉ đổi bước ghi cuối cùng.
create or replace function duc_ghi_tem(
  p_loai_sp text, p_ten_sp text, p_ma_sp text, p_so_luong numeric,
  p_ngay date, p_lot text, p_so_khuon text, p_nguyen_lieu text, p_may_duc text,
  p_ghi_chu text, p_ngay_gio_in timestamptz, p_nguoi_tt text
)
returns text
language plpgsql
security definer
as $$
declare
  v_tag_no text := duc_next_tag_no(p_loai_sp);
begin
  insert into duc_tem (
    tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
    may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
    nguoi_tt, ngay_gio_xuat, nguoi_nhan, trang_thai, ghi_chu2, ng, ghi_chu_sl
  ) values (
    v_tag_no, p_ten_sp, p_ma_sp, p_so_luong, p_ngay, coalesce(p_lot, p_ngay::text), p_so_khuon, p_nguyen_lieu,
    p_may_duc, p_ghi_chu, p_ngay_gio_in, p_so_khuon, p_so_luong, p_may_duc,
    p_nguoi_tt, null, null, 'Đã đúc', null, null, 'Chờ chốt sản lượng'
  );
  return v_tag_no;
end;
$$;

-- RPC/insert/update/delete chạy qua service_role key (Apps Script) — không
-- cần policy INSERT/UPDATE/DELETE riêng cho anon vì service_role bỏ qua RLS.
