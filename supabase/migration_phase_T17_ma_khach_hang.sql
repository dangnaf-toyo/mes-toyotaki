-- ============================================================================
-- Thêm trường "Mã khách hàng" vào master_products.
-- Mục đích: cùng "Tên khách hàng" (T14), xuất hiện trên tem thành phẩm bán
-- cho khách. Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần.
-- ============================================================================

alter table public.master_products add column if not exists ma_khach_hang text;
