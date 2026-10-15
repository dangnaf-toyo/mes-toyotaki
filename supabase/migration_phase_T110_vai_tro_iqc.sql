-- ============================================================================
-- T110 — Vai trò mới "IQC" (kiểm tra đầu vào) — user 2026-10-15.
--   Màn hình IQC: ô Người kiểm chỉ cho chọn tài khoản vai trò IQC / QC Manager
--   (lọc ở client qua qc_danh_sach_tai_khoan — đã trả kèm role).
--   Edge function admin-create-user thêm 'iqc' vào danh sách vai trò (deploy lại).
--
-- Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check (
  role in (
    'admin','truong_ca','ipqc','qc_manager','kho_nvl','ke_hoach',
    'qlsx_nhan_vien','qlsx_truong_phong','quan_ly_bo_phan','giam_doc_sx',
    'nhan_vien_duc','nhan_vien_bavia','nhan_vien_gia_cong','nhan_vien_danh_bong',
    'nhan_vien_oqc','nhan_vien_son','iatf_admin','nhan_vien_bao_duong_khuon',
    'nhan_vien_thong_ke','iqc'
  )
);
