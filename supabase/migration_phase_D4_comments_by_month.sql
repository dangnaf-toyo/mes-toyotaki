-- ============================================================================
-- Giai đoạn 4 (bỏ Google) — Comment theo từng tháng, không còn ghi đè chung.
--
-- Trước: sl_comments / cl_comments khoá theo mỗi "key" (vd 'giaohang', 'duc') —
-- MỌI tháng dùng chung 1 ô, gõ comment tháng này là mất luôn comment tháng
-- trước. Nay thêm cột "thang" (1-12), khoá theo (key, thang) — mỗi tháng có
-- ô comment riêng, xem lại được comment của bất kỳ tháng nào đã lưu.
--
-- Dữ liệu cũ (chỉ có key, chưa có tháng) được gán vào THÁNG HIỆN TẠI (lúc
-- chạy migration này) để không mất nội dung đã gõ trước đó.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ---------- sl_comments (Dashboard Sản Lượng) ----------
alter table sl_comments add column if not exists thang smallint;

update sl_comments
  set thang = extract(month from now())::smallint
  where thang is null;

alter table sl_comments drop constraint if exists sl_comments_thang_check;
alter table sl_comments add constraint sl_comments_thang_check check (thang between 1 and 12);

alter table sl_comments drop constraint if exists sl_comments_pkey;
alter table sl_comments alter column thang set not null;
alter table sl_comments add primary key (key, thang);

-- ---------- cl_comments (Dashboard Chất Lượng) ----------
alter table cl_comments add column if not exists thang smallint;

update cl_comments
  set thang = extract(month from now())::smallint
  where thang is null;

alter table cl_comments drop constraint if exists cl_comments_thang_check;
alter table cl_comments add constraint cl_comments_thang_check check (thang between 1 and 12);

alter table cl_comments drop constraint if exists cl_comments_pkey;
alter table cl_comments alter column thang set not null;
alter table cl_comments add primary key (key, thang);
