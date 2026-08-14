-- ============================================================================
-- In Tem Đúc — thêm cột "số khuôn (gợi ý)" vào master_products, song song với
-- nguyen_lieu đã thêm ở migration_phase_S5. Chạy TRƯỚC file
-- migration_phase_S6_data_nguyenlieu_sokhuon.sql (nạp dữ liệu thật).
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

alter table public.master_products add column if not exists so_khuon text;
