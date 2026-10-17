-- ============================================================================
-- D72 — user_roles.bo_phan_phu_trach: thêm 'Kỹ thuật', 'QA'.
--
-- T62 (tài liệu kỹ thuật) đã thêm 2 bộ phận này vào BO_PHAN_LIST của
-- quan-ly-tai-khoan.html + edge function admin-create-user nhưng QUÊN mở rộng
-- check constraint → tạo/sửa tài khoản có tích "Kỹ thuật"/"QA" lỗi
-- "violates check constraint user_roles_bo_phan_phu_trach_check".
-- Danh sách phải khớp BO_PHAN_LIST ở 2 chỗ trên. An toàn chạy lại nhiều lần.
-- ============================================================================

alter table public.user_roles drop constraint if exists user_roles_bo_phan_phu_trach_check;
alter table public.user_roles add constraint user_roles_bo_phan_phu_trach_check check (
  bo_phan_phu_trach is null
  or bo_phan_phu_trach <@ array['Đúc', 'Bavia', 'Gia Công', 'Cắt viền', 'Đánh bóng Kẽm', 'Sơn', 'OQC', 'Kỹ thuật', 'QA']::text[]
);
