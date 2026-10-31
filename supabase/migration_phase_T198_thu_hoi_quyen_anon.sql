-- ============================================================================
-- T198 — Toàn bộ MES bắt buộc đăng nhập: thu hồi MỌI quyền của role anon
-- (khoá publishable nằm công khai trong mã nguồn → trước đây ai cũng đọc
-- thẳng được ~140 bảng + gọi ~90 RPC qua API mà không cần đăng nhập).
--
-- Giữ lại cho anon DUY NHẤT: resolve_login_email (trang đăng nhập tra mã NV
-- trước khi có phiên). Quyền của authenticated giữ y như cũ: hàm nào trước
-- đây authenticated gọi được (kể cả chỉ qua PUBLIC) thì cấp lại tường minh;
-- hàm nội bộ đã revoke khỏi authenticated thì vẫn không có.
-- Apps Script / Edge Function dùng service_role — không ảnh hưởng.
-- Storage bucket công khai KHÔNG đổi ở đây (link ảnh /object/public/ vẫn mở được).
--
-- Chạy: staging jcjbleugnclzsghfpmvk trước, rồi production fgghikpzcxjqzahfiiil.
-- Hoàn tác: supabase/rollback_T198_thu_hoi_quyen_anon.sql
-- ============================================================================
begin;

-- 0. Sao lưu quyền anon hiện có (để hoàn tác đúng từng project). Schema riêng, không mở ra API.
create schema if not exists sao_luu;
revoke all on schema sao_luu from public, anon, authenticated;
create table if not exists sao_luu.t198_quyen_anon as
select format('grant %s on table public.%I to anon', string_agg(privilege_type, ', '), table_name) as stmt
  from information_schema.role_table_grants
 where grantee = 'anon' and table_schema = 'public' group by table_name
union all
select format('grant usage on sequence public.%I to anon', object_name)
  from information_schema.role_usage_grants
 where grantee = 'anon' and object_schema = 'public' and object_type = 'SEQUENCE'
union all
select format('grant execute on function public.%I(%s) to anon', p.proname, pg_get_function_identity_arguments(p.oid))
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prokind in ('f', 'p') and has_function_privilege('anon', p.oid, 'EXECUTE');

-- 1. Bảng / view / sequence
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

-- 2. Hàm
do $$
declare r record;
begin
  for r in
    select p.oid, p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind in ('f', 'p')
      and p.proname <> 'resolve_login_email'
      and has_function_privilege('anon', p.oid, 'EXECUTE')
  loop
    if has_function_privilege('authenticated', r.oid, 'EXECUTE') then
      execute format('grant execute on function %s to authenticated', r.sig);
    end if;
    execute format('grant execute on function %s to service_role', r.sig);
    execute format('revoke execute on function %s from public, anon', r.sig);
  end loop;
end $$;

-- 3. Đối tượng tạo SAU NÀY cũng không tự cấp cho anon
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke execute on functions from public, anon;

commit;

-- Kiểm tra (kỳ vọng: 0 bảng, chỉ còn resolve_login_email):
-- select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
--  where n.nspname='public' and c.relkind in ('r','v','m','p') and has_table_privilege('anon',c.oid,'SELECT');
-- select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--  where n.nspname='public' and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon',p.oid,'EXECUTE');
