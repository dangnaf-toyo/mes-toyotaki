-- ============================================================================
-- T62 — Module "Quản lý tài liệu kỹ thuật" (bản vẽ SP/khuôn/jig/đồ gá/dưỡng
-- kiểm, QCP, tiêu chuẩn kiểm tra, tiêu chuẩn thao tác), tách theo vòng đời
-- sản phẩm (báo giá / phát triển / sản xuất / line off), phân quyền
-- đọc/ghi/tải-bản-gốc theo (loại tài liệu × bộ phận), quản lý phiên bản,
-- xem view-only (không cho tải bản xem) qua Edge Function signed URL.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- Chạy trên CẢ 2 project: production (fgghikpzcxjqzahfiiil) và
-- staging (jcjbleugnclzsghfpmvk).
--
-- PHỤ THUỘC: migration_phase_S1_accounts_roles.sql đã chạy (cần has_role(),
-- current_role_of(), bảng user_roles với cột bo_phan_phu_trach text[]).
-- ============================================================================

-- ── 0. Mở rộng bo_phan_phu_trach cho MỌI role (trước đây chỉ dùng cho
-- quan_ly_bo_phan) — không cần đổi schema, cột đã là text[] nullable, chỉ
-- cần Edge Function admin-create-user/admin-reset-password và trang
-- quan-ly-tai-khoan.html cho phép set nó cho mọi role. Ghi chú lại đây để
-- không quên khi sửa 2 chỗ đó.
comment on column public.user_roles.bo_phan_phu_trach is
  'Bộ phận (1 hoặc nhiều) mà user thuộc về / phụ trách — dùng để check quyền '
  'tài liệu kỹ thuật (document_permissions) VÀ (khi role=quan_ly_bo_phan) các '
  'màn hình quản lý theo bộ phận hiện có. Áp dụng cho mọi role, không chỉ '
  'quan_ly_bo_phan.';

-- ── 1. Vòng đời sản phẩm trên master_products ──────────────────────────────
alter table public.master_products
  add column if not exists trang_thai_vong_doi text
    check (trang_thai_vong_doi in ('bao_gia','phat_trien','san_xuat','line_off'))
    default 'san_xuat';

create table if not exists public.document_lifecycle_history (
  id            uuid primary key default gen_random_uuid(),
  ma_sp         text not null references public.master_products(ma_sp),
  trang_thai_cu text,
  trang_thai_moi text not null,
  nguoi_chuyen  uuid references auth.users(id),
  thoi_gian     timestamptz not null default now()
);

-- RPC duy nhất được phép đổi trang_thai_vong_doi (RLS update của
-- master_products hiện chỉ cho admin — xem migration_phase_S3 — nên dùng
-- security definer để cho thêm giam_doc_sx/qlsx_truong_phong mà không phải
-- nới lỏng quyền UPDATE toàn bộ bảng master_products cho họ).
create or replace function public.doc_set_product_lifecycle(p_ma_sp text, p_trang_thai_moi text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_cu text;
begin
  if not public.has_role('admin','giam_doc_sx','qlsx_truong_phong') then
    raise exception 'Không có quyền đổi trạng thái vòng đời sản phẩm';
  end if;
  if p_trang_thai_moi not in ('bao_gia','phat_trien','san_xuat','line_off') then
    raise exception 'Trạng thái không hợp lệ: %', p_trang_thai_moi;
  end if;

  select trang_thai_vong_doi into v_cu from public.master_products where ma_sp = p_ma_sp;
  if not found then
    raise exception 'Không tìm thấy mã sản phẩm: %', p_ma_sp;
  end if;

  update public.master_products set trang_thai_vong_doi = p_trang_thai_moi where ma_sp = p_ma_sp;

  insert into public.document_lifecycle_history (ma_sp, trang_thai_cu, trang_thai_moi, nguoi_chuyen)
  values (p_ma_sp, v_cu, p_trang_thai_moi, auth.uid());
end;
$$;

alter table public.document_lifecycle_history enable row level security;
drop policy if exists "read lifecycle history" on public.document_lifecycle_history;
create policy "read lifecycle history" on public.document_lifecycle_history
  for select using (auth.uid() is not null);
-- Không có policy insert/update/delete cho client — chỉ ghi được qua RPC
-- doc_set_product_lifecycle (security definer, bỏ qua RLS).

-- ── 2. Danh mục loại tài liệu ───────────────────────────────────────────────
create table if not exists public.doc_categories (
  id       uuid primary key default gen_random_uuid(),
  ma       text unique not null,
  ten      text not null,
  thu_tu   int not null default 0
);

insert into public.doc_categories (ma, ten, thu_tu) values
  ('ban_ve_sp',     'Bản vẽ sản phẩm',      1),
  ('ban_ve_khuon',  'Bản vẽ khuôn',         2),
  ('ban_ve_jig',    'Bản vẽ jig',           3),
  ('do_ga',         'Đồ gá',                4),
  ('duong_kiem',    'Dưỡng kiểm',           5),
  ('qcp',           'QCP',                  6),
  ('tc_kiem_tra',   'Tiêu chuẩn kiểm tra',  7),
  ('tc_thao_tac',   'Tiêu chuẩn thao tác',  8)
on conflict (ma) do nothing;

alter table public.doc_categories enable row level security;
drop policy if exists "read doc_categories" on public.doc_categories;
create policy "read doc_categories" on public.doc_categories
  for select using (auth.uid() is not null);
drop policy if exists "admin write doc_categories" on public.doc_categories;
create policy "admin write doc_categories" on public.doc_categories
  for all using (public.has_role('admin')) with check (public.has_role('admin'));

-- ── 3. Helper phân quyền theo (loại tài liệu × bộ phận) ────────────────────
create table if not exists public.document_permissions (
  id          uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.doc_categories(id) on delete cascade,
  bo_phan     text not null,
  quyen       text not null check (quyen in ('read','write','download_source')),
  created_by  uuid references auth.users(id),
  created_at  timestamptz not null default now(),
  unique (category_id, bo_phan, quyen)
);

alter table public.document_permissions enable row level security;
drop policy if exists "read document_permissions" on public.document_permissions;
create policy "read document_permissions" on public.document_permissions
  for select using (auth.uid() is not null);
drop policy if exists "admin write document_permissions" on public.document_permissions;
create policy "admin write document_permissions" on public.document_permissions
  for all using (public.has_role('admin')) with check (public.has_role('admin'));

create or replace function public.current_user_bo_phan()
returns text[]
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(bo_phan_phu_trach, array[]::text[])
  from public.user_roles where user_id = auth.uid();
$$;

-- p_quyen: 'read' | 'write' | 'download_source' — kiểm tra ĐÚNG quyền đó đã
-- được cấp cho 1 trong các bộ phận của user (không suy luận write=>read;
-- khi admin cấp write/download_source, UI phải tự động cấp kèm read).
create or replace function public.has_doc_permission(p_category_id uuid, p_quyen text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.has_role('admin') or exists (
    select 1 from public.document_permissions dp
    where dp.category_id = p_category_id
      and dp.quyen = p_quyen
      and dp.bo_phan = any(public.current_user_bo_phan())
  );
$$;

-- ── 4. Tài liệu + phiên bản ─────────────────────────────────────────────────
create table if not exists public.documents (
  id                 uuid primary key default gen_random_uuid(),
  ma_sp              text not null references public.master_products(ma_sp),
  category_id        uuid not null references public.doc_categories(id),
  ten_tai_lieu       text not null,
  current_version_id uuid,
  created_by         uuid references auth.users(id),
  created_at         timestamptz not null default now(),
  unique (ma_sp, category_id, ten_tai_lieu)
);

create table if not exists public.document_versions (
  id              uuid primary key default gen_random_uuid(),
  document_id     uuid not null references public.documents(id) on delete cascade,
  so_phien_ban    int not null,
  file_path_goc   text,           -- Storage path bản CAD gốc (nullable — không phải loại nào cũng có)
  file_path_view  text not null,  -- Storage path bản xem (PDF/ảnh), bắt buộc
  ghi_chu_thay_doi text,
  trang_thai      text not null default 'nhap' check (trang_thai in ('nhap','cho_duyet','da_duyet','thu_hoi')),
  uploaded_by     uuid references auth.users(id),
  uploaded_at     timestamptz not null default now(),
  approved_by     uuid references auth.users(id),
  approved_at     timestamptz,
  unique (document_id, so_phien_ban)
);

alter table public.documents
  add constraint documents_current_version_fk
  foreign key (current_version_id) references public.document_versions(id)
  deferrable initially deferred;

alter table public.documents enable row level security;
alter table public.document_versions enable row level security;

drop policy if exists "read documents by permission" on public.documents;
create policy "read documents by permission" on public.documents
  for select using (public.has_doc_permission(category_id, 'read'));

drop policy if exists "write documents by permission" on public.documents;
create policy "write documents by permission" on public.documents
  for insert with check (public.has_doc_permission(category_id, 'write'));

drop policy if exists "update documents by permission" on public.documents;
create policy "update documents by permission" on public.documents
  for update using (public.has_doc_permission(category_id, 'write'))
  with check (public.has_doc_permission(category_id, 'write'));

drop policy if exists "read document_versions by permission" on public.document_versions;
create policy "read document_versions by permission" on public.document_versions
  for select using (
    exists (
      select 1 from public.documents d
      where d.id = document_versions.document_id
        and public.has_doc_permission(d.category_id, 'read')
    )
  );

drop policy if exists "write document_versions by permission" on public.document_versions;
create policy "write document_versions by permission" on public.document_versions
  for insert with check (
    exists (
      select 1 from public.documents d
      where d.id = document_versions.document_id
        and public.has_doc_permission(d.category_id, 'write')
    )
  );

drop policy if exists "update document_versions by permission" on public.document_versions;
create policy "update document_versions by permission" on public.document_versions
  for update using (
    exists (
      select 1 from public.documents d
      where d.id = document_versions.document_id
        and public.has_doc_permission(d.category_id, 'write')
    )
  ) with check (
    exists (
      select 1 from public.documents d
      where d.id = document_versions.document_id
        and public.has_doc_permission(d.category_id, 'write')
    )
  );

-- Duyệt 1 phiên bản = phiên bản hiện hành (RPC vì cần sửa 2 bảng liền mạch:
-- document_versions.trang_thai + documents.current_version_id).
create or replace function public.doc_approve_version(p_version_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_document_id uuid; v_category_id uuid;
begin
  select dv.document_id, d.category_id into v_document_id, v_category_id
  from public.document_versions dv
  join public.documents d on d.id = dv.document_id
  where dv.id = p_version_id;

  if v_document_id is null then
    raise exception 'Không tìm thấy phiên bản tài liệu';
  end if;
  if not public.has_doc_permission(v_category_id, 'write') then
    raise exception 'Không có quyền duyệt tài liệu này';
  end if;

  update public.document_versions set trang_thai = 'da_duyet',
    approved_by = auth.uid(), approved_at = now()
  where id = p_version_id;

  update public.documents set current_version_id = p_version_id where id = v_document_id;
end;
$$;

-- Thu hồi 1 phiên bản (không xóa, chỉ đánh dấu; nếu đang là bản hiện hành thì gỡ).
create or replace function public.doc_revoke_version(p_version_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_document_id uuid; v_category_id uuid;
begin
  select dv.document_id, d.category_id into v_document_id, v_category_id
  from public.document_versions dv
  join public.documents d on d.id = dv.document_id
  where dv.id = p_version_id;

  if v_document_id is null then
    raise exception 'Không tìm thấy phiên bản tài liệu';
  end if;
  if not public.has_doc_permission(v_category_id, 'write') then
    raise exception 'Không có quyền thu hồi tài liệu này';
  end if;

  update public.document_versions set trang_thai = 'thu_hoi' where id = p_version_id;
  update public.documents set current_version_id = null
  where id = v_document_id and current_version_id = p_version_id;
end;
$$;

-- ── 5. Log lượt xem (audit — không cho tải nên cần biết ai xem gì lúc nào) ─
create table if not exists public.document_access_log (
  id                  uuid primary key default gen_random_uuid(),
  document_version_id uuid not null references public.document_versions(id) on delete cascade,
  user_id             uuid not null references auth.users(id),
  action              text not null check (action in ('view','view_attempt_blocked','download_source')),
  thoi_gian           timestamptz not null default now()
);

alter table public.document_access_log enable row level security;

drop policy if exists "insert own access log" on public.document_access_log;
create policy "insert own access log" on public.document_access_log
  for insert with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.document_versions dv
      join public.documents d on d.id = dv.document_id
      where dv.id = document_access_log.document_version_id
        and public.has_doc_permission(d.category_id, 'read')
    )
  );

drop policy if exists "read access log by write permission" on public.document_access_log;
create policy "read access log by write permission" on public.document_access_log
  for select using (
    public.has_role('admin') or exists (
      select 1 from public.document_versions dv
      join public.documents d on d.id = dv.document_id
      where dv.id = document_access_log.document_version_id
        and public.has_doc_permission(d.category_id, 'write')
    )
  );

-- ── 6. Storage bucket riêng, PRIVATE (không public URL) ────────────────────
-- Client KHÔNG được gọi thẳng storage.from('tech-documents') — chỉ truy cập
-- qua Edge Function get-document-view-url / get-document-source-url (dùng
-- service_role key để tạo signed URL ngắn hạn sau khi tự kiểm tra quyền).
insert into storage.buckets (id, name, public)
values ('tech-documents', 'tech-documents', false)
on conflict (id) do update set public = false;

-- Upload phiên bản mới đi THẲNG từ trình duyệt lên Storage (như report-files/
-- ipqc-evidence hiện có), nhưng bucket này PRIVATE nên cần policy insert rõ
-- ràng. Quy ước đường dẫn bắt buộc: {ma_sp}/{category_id}/{document_id}/v{n}/...
-- — kiểm tra quyền write bằng category_id nằm ở đoạn thứ 2 của path.
-- KHÔNG có policy update/delete/select cho client: phiên bản là bất biến sau
-- khi tạo, và đọc bắt buộc phải qua Edge Function get-document-view-url /
-- get-document-source-url (dùng service_role, tạo signed URL ngắn hạn) chứ
-- không lấy public URL trực tiếp.
drop policy if exists "write tech-documents by permission" on storage.objects;
create policy "write tech-documents by permission" on storage.objects
  for insert with check (
    bucket_id = 'tech-documents'
    and public.has_doc_permission(((storage.foldername(name))[2])::uuid, 'write')
  );

-- ============================================================================
-- Sau khi chạy xong, cần bootstrap dữ liệu phân quyền mẫu (KHÔNG tự chạy ở
-- đây vì phụ thuộc thực tế bộ phận nào được đọc/ghi loại tài liệu nào —
-- admin cấu hình qua trang quan-ly-tai-khoan.html sau khi UI xong, hoặc chạy
-- tay ví dụ:
--   insert into document_permissions (category_id, bo_phan, quyen)
--   select id, 'Đúc', 'read' from doc_categories where ma = 'qcp';
-- ============================================================================
