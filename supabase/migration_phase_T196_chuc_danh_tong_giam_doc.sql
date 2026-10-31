-- T196: chức danh "Tổng giám đốc" cho tài khoản (2026-10-31).
-- Tổng giám đốc toàn quyền như Admin → KHÔNG thêm role mới (quyền admin đang được
-- kiểm tra ở ~50 hàm/policy + ~40 chỗ giao diện). Lưu role = 'admin' và thêm cột
-- chuc_danh chỉ để hiển thị (quan-ly-tai-khoan.html hiện "Tổng giám đốc").
alter table public.user_roles add column if not exists chuc_danh text;

alter table public.user_roles drop constraint if exists user_roles_chuc_danh_check;
alter table public.user_roles add constraint user_roles_chuc_danh_check check (
  chuc_danh is null or (chuc_danh = 'tong_giam_doc' and role = 'admin')
);

update public.user_roles set chuc_danh = 'tong_giam_doc' where username = '220101';
