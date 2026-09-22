-- ============================================================================
-- T64 — Vai trò "IATF admin": CHỈ tài khoản có role này (hoặc 'admin') mới
-- được GHI (upload phiên bản mới, tạo/sửa/huỷ, duyệt/thu hồi phiên bản) trên
-- TÀI LIỆU KỸ THUẬT (doc_categories.cap = 'ky_thuat' — 8 loại: bản vẽ SP,
-- bản vẽ khuôn, bản vẽ jig, đồ gá, dưỡng kiểm, QCP, tiêu chuẩn kiểm tra,
-- tiêu chuẩn thao tác). Ma trận "Phân quyền tài liệu" (document_permissions)
-- theo bộ phận KHÔNG còn cấp được quyền Ghi cho nhóm tài liệu kỹ thuật nữa —
-- chỉ còn dùng để cấp quyền ĐỌC và TẢI BẢN GỐC theo bộ phận như cũ.
--
-- Tài liệu HỆ THỐNG (cấp 1-4: QM/QP/WI/Biểu mẫu) KHÔNG bị ảnh hưởng — vẫn
-- theo đúng ma trận bộ phận + luồng Phiếu thay đổi tài liệu (T63) như trước.
--
-- Chạy trong Supabase SQL Editor SAU migration_phase_T63. An toàn chạy lại
-- nhiều lần. Chạy trên CẢ 2 project.
-- ============================================================================

alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check (
  role in (
    'admin','truong_ca','ipqc','qc_manager','kho_nvl','ke_hoach',
    'qlsx_nhan_vien','qlsx_truong_phong','quan_ly_bo_phan','giam_doc_sx',
    'nhan_vien_duc','nhan_vien_bavia','nhan_vien_gia_cong','nhan_vien_danh_bong',
    'nhan_vien_oqc','nhan_vien_son','iatf_admin'
  )
);

create or replace function public.has_doc_permission(p_category_id uuid, p_quyen text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select case
    when p_quyen = 'write' and exists (
      select 1 from public.doc_categories c where c.id = p_category_id and c.cap = 'ky_thuat'
    ) then public.has_role('admin', 'iatf_admin')
    else
      public.has_role('admin') or exists (
        select 1 from public.document_permissions dp
        where dp.category_id = p_category_id
          and dp.quyen = p_quyen
          and dp.bo_phan = any(public.current_user_bo_phan())
      )
  end;
$$;

-- ============================================================================
-- Sau khi chạy: vào quan-ly-tai-khoan.html gán role "IATF admin" cho (các)
-- tài khoản phụ trách tài liệu kỹ thuật. Các ô "Ghi" đã tick sẵn trong ma
-- trận Phân quyền tài liệu (quan-ly-danh-muc.html) cho 8 loại tài liệu kỹ
-- thuật giờ KHÔNG còn hiệu lực nữa (hàm has_doc_permission bỏ qua chúng) —
-- không cần xoá thủ công, chỉ là chúng không còn tác dụng.
-- ============================================================================
