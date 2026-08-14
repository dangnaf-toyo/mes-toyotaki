-- ============================================================================
-- In Tem Đúc — thêm cột "nguyên liệu" vào master_products để intem.html tự
-- điền theo mã SP thay vì phải gõ tay mỗi lần in tem.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

alter table public.master_products add column if not exists nguyen_lieu text;
