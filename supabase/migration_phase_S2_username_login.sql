-- ============================================================================
-- Nhóm 1 / Mục 1 (tiếp) — Đăng nhập bằng mã nhân viên (username) thay vì
-- email cho công nhân không có email thật.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
--
-- Cách hoạt động: mỗi tài khoản không-có-email-thật vẫn có 1 email "giả"
-- dạng <username>@mes.local trong auth.users (Supabase Auth bắt buộc phải
-- có email) — người dùng KHÔNG cần biết email này, chỉ gõ mã nhân viên.
-- Trang login tra email tương ứng qua hàm resolve_login_email() rồi mới gọi
-- signInWithPassword như cũ.
-- ============================================================================

alter table public.user_roles add column if not exists username text unique;

-- Cho phép tra "username -> email đăng nhập" MÀ KHÔNG CẦN đăng nhập trước
-- (đây là bước xảy ra trước khi biết mật khẩu đúng hay sai) — security
-- definer + chỉ trả về đúng 1 cột email, không lộ vai trò/họ tên/dữ liệu
-- khác của user đó.
create or replace function public.resolve_login_email(p_username text)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select email from public.user_roles where username = lower(trim(p_username));
$$;

grant execute on function public.resolve_login_email(text) to anon, authenticated;
