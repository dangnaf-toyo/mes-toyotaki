-- T37: Thêm vai trò "Nhân viên" cho từng bộ phận (Đúc, Bavia, Gia công,
-- Đánh bóng, OQC, Sơn) — tài khoản công nhân trực tiếp, phân biệt với vai
-- trò "Quản lý bộ phận" (duyệt bước 2 KHSX) đã có sẵn.

alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check (
  role in (
    'admin','truong_ca','ipqc','qc_manager','kho_nvl','ke_hoach',
    'qlsx_nhan_vien','qlsx_truong_phong','quan_ly_bo_phan','giam_doc_sx',
    'nhan_vien_duc','nhan_vien_bavia','nhan_vien_gia_cong','nhan_vien_danh_bong',
    'nhan_vien_oqc','nhan_vien_son'
  )
);
