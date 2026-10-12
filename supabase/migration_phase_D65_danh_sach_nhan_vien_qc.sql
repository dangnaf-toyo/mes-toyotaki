-- ============================================================================
-- D65 — Danh sách nhân viên cho các ô chọn người kiểm QC (OQC / IQC / QC
-- Manager / NCP) không phụ thuộc quyền đọc user_roles.
--
-- Lỗi: shared/qc02-data.js ghép danh sách từ master_employees (ai cũng đọc
-- được) + user_roles. RLS user_roles = "chính mình hoặc admin" → chỉ admin
-- thấy các tài khoản nhan_vien_oqc; QC manager mở OQC kiểm tra xuất hàng thì
-- ô "Mã nhân viên kiểm tra" trống (prod chưa ai khai vai trò OQC ở Nhân sự).
--
-- Sửa: RPC chỉ đọc trả về mã NV (username), họ tên, vai trò, bộ phận của các
-- tài khoản có username — KHÔNG trả email / user_id. Chỉ người đã đăng nhập
-- gọi được. RLS user_roles giữ nguyên.
--
-- Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

create or replace function qc_danh_sach_tai_khoan()
returns table (username text, full_name text, role text, bo_phan_phu_trach text[])
language sql
stable
security definer
set search_path = public
as $$
  select u.username, u.full_name, u.role, u.bo_phan_phu_trach
  from public.user_roles u
  where auth.uid() is not null
    and nullif(trim(u.username), '') is not null
  order by u.username;
$$;

revoke execute on function qc_danh_sach_tai_khoan() from public, anon;
grant execute on function qc_danh_sach_tai_khoan() to authenticated;
