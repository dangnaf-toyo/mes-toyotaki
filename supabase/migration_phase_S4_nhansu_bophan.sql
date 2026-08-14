-- ============================================================================
-- Nhóm 1 / Mục 4 (tiếp) — Thêm cột "bộ phận" cho master_employees.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

alter table public.master_employees add column if not exists bo_phan text;
