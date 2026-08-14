-- ============================================================================
-- Nhóm 1 / Mục 1 — Quản lý tài khoản & phân quyền.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
--
-- Thêm bảng public.user_roles ánh xạ auth.users -> vai trò nghiệp vụ, cùng 2
-- hàm helper (current_role_of / has_role) để RLS của CÁC BẢNG KHÁC dùng dần
-- (chưa đổi RLS của các module hiện có ở đây — làm khi có thời gian, tránh
-- khoá ghi hàng loạt cùng lúc).
-- ============================================================================

create table if not exists public.user_roles (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  email       text not null,
  full_name   text,
  role        text not null check (role in ('admin','truong_ca','ipqc','qc_manager','kho_nvl','ke_hoach')),
  created_at  timestamptz not null default now(),
  created_by  uuid references auth.users(id),
  updated_at  timestamptz not null default now()
);

-- Hàm lấy vai trò của 1 user — security definer để tránh đệ quy RLS khi các
-- policy khác (kể cả policy của chính bảng user_roles) gọi has_role().
create or replace function public.current_role_of(uid uuid default auth.uid())
returns text
language sql
security definer
stable
set search_path = public
as $$
  select role from public.user_roles where user_id = uid;
$$;

create or replace function public.has_role(variadic allowed_roles text[])
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role = any(allowed_roles)
  );
$$;

alter table public.user_roles enable row level security;

drop policy if exists "self or admin read user_roles" on public.user_roles;
create policy "self or admin read user_roles" on public.user_roles
  for select using (user_id = auth.uid() or public.has_role('admin'));

drop policy if exists "admin insert user_roles" on public.user_roles;
create policy "admin insert user_roles" on public.user_roles
  for insert with check (public.has_role('admin'));

drop policy if exists "admin update user_roles" on public.user_roles;
create policy "admin update user_roles" on public.user_roles
  for update using (public.has_role('admin')) with check (public.has_role('admin'));

drop policy if exists "admin delete user_roles" on public.user_roles;
create policy "admin delete user_roles" on public.user_roles
  for delete using (public.has_role('admin'));

-- ── BOOTSTRAP (chạy 1 LẦN, thủ công, sau khi đã có ít nhất 1 tài khoản đăng
-- nhập được) — gán admin đầu tiên. Không có bước này thì không ai gọi được
-- Edge Function admin-create-user (chỉ admin mới gọi được) lẫn không sửa
-- được bảng user_roles qua trang web (RLS chỉ cho admin ghi).
--
--   insert into public.user_roles (user_id, email, role)
--   select id, email, 'admin' from auth.users where email = 'THAY_EMAIL_ADMIN@vidu.com'
--   on conflict (user_id) do update set role = 'admin';
