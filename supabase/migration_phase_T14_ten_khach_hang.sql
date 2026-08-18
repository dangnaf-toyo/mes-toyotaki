-- ============================================================================
-- Thêm trường "Tên khách hàng" vào master_products.
-- Mục đích: tên khách hàng sẽ xuất hiện trên tem thành phẩm bán cho khách.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

alter table public.master_products add column if not exists ten_khach_hang text;
