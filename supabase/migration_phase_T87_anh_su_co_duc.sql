-- ============================================================================
-- T87 — Ảnh sự cố Đúc: ảnh HIỆN TRẠNG lúc phát sinh (truoc) và ảnh SAU XỬ LÝ
-- (sau), dùng ở duc-dashboard.html + mobile.html (shared/su-co-anh.js).
--
-- - Bucket "su-co-duc" (public read như ipqc-evidence, 5MB, chỉ ảnh). Ai đã
--   đăng nhập cũng tải lên được (giống quyền báo sự cố).
-- - duc_su_co_anh gắn theo id_su_co (mã sự cố cố định: open_id_su_co khi đang
--   mở, duc_su_co_log.id_su_co khi đã đóng) — không sửa RPC sự cố hiện có.
-- - Ghi qua RPC: duc_su_co_them_anh (tối đa 10 ảnh mỗi loại / sự cố, chỉ URL
--   của bucket này, sự cố phải tồn tại), duc_su_co_xoa_anh (người tải / admin /
--   trưởng ca / quản lý bộ phận).
--
-- Chạy trên CẢ 2 project (production + staging). Idempotent.
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('su-co-duc', 'su-co-duc', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "public read su-co-duc" on storage.objects;
create policy "public read su-co-duc" on storage.objects
  for select using (bucket_id = 'su-co-duc');
drop policy if exists "auth upload su-co-duc" on storage.objects;
create policy "auth upload su-co-duc" on storage.objects
  for insert to authenticated with check (bucket_id = 'su-co-duc');

create table if not exists duc_su_co_anh (
  id          bigserial primary key,
  id_su_co    text not null,
  loai        text not null check (loai in ('truoc', 'sau')),
  url         text not null,
  nguoi       text not null default '',
  nguoi_id    uuid,
  thoi_diem   timestamptz not null default now()
);
create index if not exists idx_duc_su_co_anh_id on duc_su_co_anh (id_su_co);

alter table duc_su_co_anh enable row level security;
drop policy if exists "su_co_anh public read" on duc_su_co_anh;
create policy "su_co_anh public read" on duc_su_co_anh for select using (true);
revoke insert, update, delete on duc_su_co_anh from anon, authenticated;
grant select on duc_su_co_anh to anon, authenticated;

create or replace function duc_su_co_them_anh(p_id_su_co text, p_loai text, p_urls text[])
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text := trim(coalesce(p_id_su_co, '')); v_ten text; v_co int; u text; n int := 0;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if p_loai not in ('truoc', 'sau') then return jsonb_build_object('ok', false, 'error', 'Loại ảnh không hợp lệ'); end if;
  if v_id = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã sự cố'); end if;
  if coalesce(cardinality(p_urls), 0) = 0 then return jsonb_build_object('ok', false, 'error', 'Chưa có ảnh'); end if;
  if not exists (select 1 from duc_ca_hien_tai where open_id_su_co = v_id)
     and not exists (select 1 from duc_su_co_log where id_su_co = v_id) then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố ' || v_id);
  end if;
  if exists (select 1 from unnest(p_urls) x where x not like '%/storage/v1/object/public/su-co-duc/%') then
    return jsonb_build_object('ok', false, 'error', 'Link ảnh không hợp lệ');
  end if;
  select count(*) into v_co from duc_su_co_anh where id_su_co = v_id and loai = p_loai;
  if v_co + cardinality(p_urls) > 10 then
    return jsonb_build_object('ok', false, 'error', 'Tối đa 10 ảnh ' || case p_loai when 'truoc' then 'hiện trạng' else 'sau xử lý' end || ' cho 1 sự cố (đã có ' || v_co || ')');
  end if;

  select coalesce(nullif(trim(full_name), ''), nullif(trim(username), ''), email, '') into v_ten
    from user_roles where user_id = auth.uid();
  foreach u in array p_urls loop
    insert into duc_su_co_anh (id_su_co, loai, url, nguoi, nguoi_id) values (v_id, p_loai, u, coalesce(v_ten, ''), auth.uid());
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'so_anh', n);
end;
$$;
revoke execute on function duc_su_co_them_anh(text, text, text[]) from public, anon;
grant execute on function duc_su_co_them_anh(text, text, text[]) to authenticated;

create or replace function duc_su_co_xoa_anh(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_row duc_su_co_anh; v_role text;
begin
  select * into v_row from duc_su_co_anh where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy ảnh'); end if;
  select role into v_role from user_roles where user_id = auth.uid();
  if not (v_row.nguoi_id = auth.uid() or coalesce(v_role, '') in ('admin', 'truong_ca', 'quan_ly_bo_phan')) then
    return jsonb_build_object('ok', false, 'error', 'Chỉ người tải ảnh / trưởng ca / quản lý / admin được xoá ảnh');
  end if;
  delete from duc_su_co_anh where id = p_id;
  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function duc_su_co_xoa_anh(bigint) from public, anon;
grant execute on function duc_su_co_xoa_anh(bigint) to authenticated;
