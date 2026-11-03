-- ============================================================================
-- T208 — Đưa BOM lên production (gộp T61 + phần cột của T70b) + sửa theo review 03/11/2026.
--
-- Review trước prod (user duyệt "sửa hết rồi đẩy", chỉ Admin xem BOM):
--   1) KHÔNG nạp 25 mã NVL mẫu của T70b (K-NHN-12-001…) — prod đang dùng danh mục NVL
--      thật (ADC12-CHT, ADC12-DAK… có giao dịch/tem kho NVL). Chỉ thêm 4 cột mới.
--   2) bom_save_version: tên người cập nhật lấy theo tài khoản đăng nhập
--      (duc_su_co_nguoi_hien_tai), bỏ qua p_updated_by trình duyệt gửi; thu hồi quyền
--      public/anon. Luồng công đoạn KHÔNG khai trong BOM nữa (lấy từ Danh mục SP) —
--      tham số p_quy_trinh_cong_doan giữ chữ ký cũ nhưng bỏ qua.
--   3) Chỉ Admin đọc bom_versions / bom_components (RLS).
--   4) Mã nhôm khởi đầu chỉ chép từ master_products.nguyen_lieu khi mã đó có trong
--      danh mục NVL (prod có 'ADC12', 'NVL TEST' không có trong danh mục → để trống).
--   5) nvl_catalog_delete: mã đã dùng ở kho NVL thì báo câu dễ hiểu thay vì lỗi khoá ngoại.
-- An toàn chạy lại (idempotent). Chạy được trên staging (đã có T61/T70b) và prod (chưa có).
-- Trạng thái: Đã chạy STAGING + PROD 03/11/2026.
-- ============================================================================

-- ── Bảng BOM (T61) ──────────────────────────────────────────────────────────
create table if not exists public.bom_versions (
  id                          bigserial primary key,
  ma_sp                       text not null references public.master_products(ma_sp) on delete cascade,
  version_no                  smallint not null check (version_no between 1 and 3),
  ma_nhom                     text,
  dinh_muc_nhom_kg_moi_pcs     numeric check (dinh_muc_nhom_kg_moi_pcs is null or dinh_muc_nhom_kg_moi_pcs >= 0),
  quy_trinh_cong_doan         text[] not null default array['Đúc','Bavia','Gia công CNC','Sơn'],  -- không dùng nữa (lấy từ Danh mục SP)
  ghi_chu                     text,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  updated_by                  text,
  unique (ma_sp, version_no)
);

create table if not exists public.bom_components (
  id                          bigserial primary key,
  bom_version_id              bigint not null references public.bom_versions(id) on delete cascade,
  ma_linh_kien                text not null,
  ten_linh_kien               text,
  dinh_muc_moi_pcs            numeric not null default 1 check (dinh_muc_moi_pcs >= 0),
  don_vi_tinh                 text not null default 'pcs',
  ghi_chu                     text,
  unique (bom_version_id, ma_linh_kien)
);

create or replace function public.bom_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_bom_versions_updated_at on public.bom_versions;
create trigger trg_bom_versions_updated_at before update on public.bom_versions
for each row execute function public.bom_set_updated_at();

-- Mỗi sản phẩm mới tự có 3 phiên bản BOM trống.
create or replace function public.bom_create_default_versions()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.bom_versions (ma_sp, version_no)
  values (new.ma_sp, 1), (new.ma_sp, 2), (new.ma_sp, 3)
  on conflict (ma_sp, version_no) do nothing;
  return new;
end $$;
revoke execute on function public.bom_create_default_versions() from public, anon, authenticated;

drop trigger if exists trg_master_products_bom_versions on public.master_products;
create trigger trg_master_products_bom_versions after insert on public.master_products
for each row execute function public.bom_create_default_versions();

insert into public.bom_versions (ma_sp, version_no)
select p.ma_sp, v.version_no
from public.master_products p
cross join (values (1::smallint), (2::smallint), (3::smallint)) as v(version_no)
on conflict (ma_sp, version_no) do nothing;

update public.bom_versions b
set ma_nhom = p.nguyen_lieu
from public.master_products p
where p.ma_sp = b.ma_sp
  and b.ma_nhom is null
  and exists (select 1 from public.nvl_materials n where n.ma_nvl = p.nguyen_lieu);

-- ── RLS: chỉ Admin đọc; ghi chỉ qua RPC ────────────────────────────────────
alter table public.bom_versions enable row level security;
alter table public.bom_components enable row level security;
drop policy if exists "public read bom_versions" on public.bom_versions;
drop policy if exists "public read bom_components" on public.bom_components;
drop policy if exists bom_versions_admin_doc on public.bom_versions;
drop policy if exists bom_components_admin_doc on public.bom_components;
create policy bom_versions_admin_doc on public.bom_versions for select to authenticated using (public.has_role('admin'));
create policy bom_components_admin_doc on public.bom_components for select to authenticated using (public.has_role('admin'));
revoke all on public.bom_versions, public.bom_components from anon;
revoke insert, update, delete on public.bom_versions, public.bom_components from authenticated;
grant select on public.bom_versions, public.bom_components to authenticated;

-- ── Lưu 1 phiên bản BOM (chỉ Admin) ────────────────────────────────────────
create or replace function public.bom_save_version(
  p_id bigint,
  p_ma_nhom text,
  p_dinh_muc_nhom_kg_moi_pcs numeric,
  p_quy_trinh_cong_doan text[],   -- bỏ qua (luồng công đoạn lấy từ Danh mục SP)
  p_ghi_chu text,
  p_components jsonb,
  p_updated_by text               -- bỏ qua (lấy theo tài khoản đăng nhập)
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_component jsonb;
begin
  if auth.uid() is null or not public.has_role('admin') then
    raise exception 'Chỉ Admin được cập nhật BOM';
  end if;
  if not exists (select 1 from public.bom_versions where id = p_id) then
    raise exception 'Không tìm thấy phiên bản BOM';
  end if;
  if p_dinh_muc_nhom_kg_moi_pcs is not null and p_dinh_muc_nhom_kg_moi_pcs < 0 then
    raise exception 'Định mức nhôm/pcs không được âm';
  end if;
  if nullif(trim(p_ma_nhom), '') is not null
     and not exists (select 1 from public.nvl_materials where ma_nvl = trim(p_ma_nhom)) then
    raise exception 'Mã nguyên vật liệu % chưa có trong Danh mục NVL', trim(p_ma_nhom);
  end if;

  update public.bom_versions
  set ma_nhom = nullif(trim(p_ma_nhom), ''),
      dinh_muc_nhom_kg_moi_pcs = p_dinh_muc_nhom_kg_moi_pcs,
      ghi_chu = nullif(trim(p_ghi_chu), ''),
      updated_by = public.duc_su_co_nguoi_hien_tai()
  where id = p_id;

  delete from public.bom_components where bom_version_id = p_id;
  for v_component in select value from jsonb_array_elements(coalesce(p_components, '[]'::jsonb))
  loop
    if nullif(trim(v_component->>'ma_linh_kien'), '') is null then
      raise exception 'Mã linh kiện không được để trống';
    end if;
    if coalesce((v_component->>'dinh_muc_moi_pcs')::numeric, -1) < 0 then
      raise exception 'Định mức linh kiện/pcs không được âm';
    end if;
    insert into public.bom_components (bom_version_id, ma_linh_kien, ten_linh_kien, dinh_muc_moi_pcs, don_vi_tinh, ghi_chu)
    values (
      p_id,
      trim(v_component->>'ma_linh_kien'),
      nullif(trim(v_component->>'ten_linh_kien'), ''),
      coalesce((v_component->>'dinh_muc_moi_pcs')::numeric, 1),
      coalesce(nullif(trim(v_component->>'don_vi_tinh'), ''), 'pcs'),
      nullif(trim(v_component->>'ghi_chu'), '')
    );
  end loop;
end $$;
revoke execute on function public.bom_save_version(bigint, text, numeric, text[], text, jsonb, text) from public, anon;
grant execute on function public.bom_save_version(bigint, text, numeric, text[], text, jsonb, text) to authenticated;

-- ── Danh mục NVL dùng chung BOM + kho NVL (T70b, KHÔNG nạp mã mẫu) ─────────
alter table public.nvl_materials
  add column if not exists nha_cung_cap text,
  add column if not exists ma_nvl_ncc text,
  add column if not exists khach_hang text,
  add column if not exists san_pham text;

create or replace function public.nvl_catalog_upsert(
  p_ma_nvl text, p_ten_nvl text, p_nha_cung_cap text, p_ma_nvl_ncc text, p_khach_hang text, p_san_pham text
) returns jsonb
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null or not public.has_role('admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Admin được cập nhật danh mục NVL');
  end if;
  if nullif(trim(p_ma_nvl), '') is null then
    return jsonb_build_object('ok', false, 'error', 'Thiếu mã NVL Toyotaki');
  end if;
  insert into public.nvl_materials (ma_nvl, ten_nvl, nha_cung_cap, ma_nvl_ncc, khach_hang, san_pham)
  values (trim(p_ma_nvl), coalesce(nullif(trim(p_ten_nvl), ''), trim(p_ma_nvl)),
     nullif(trim(p_nha_cung_cap), ''), nullif(trim(p_ma_nvl_ncc), ''),
     nullif(trim(p_khach_hang), ''), nullif(trim(p_san_pham), ''))
  on conflict (ma_nvl) do update set
    ten_nvl = excluded.ten_nvl, nha_cung_cap = excluded.nha_cung_cap, ma_nvl_ncc = excluded.ma_nvl_ncc,
    khach_hang = excluded.khach_hang, san_pham = excluded.san_pham;
  return jsonb_build_object('ok', true, 'ma_nvl', trim(p_ma_nvl));
end $$;

create or replace function public.nvl_catalog_delete(p_ma_nvl text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null or not public.has_role('admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Admin được xóa danh mục NVL');
  end if;
  if exists (select 1 from public.bom_versions where ma_nhom = p_ma_nvl) then
    return jsonb_build_object('ok', false, 'error', 'Mã ' || p_ma_nvl || ' đang dùng trong BOM, không xoá được');
  end if;
  begin
    delete from public.nvl_materials where ma_nvl = p_ma_nvl;
  exception when foreign_key_violation then
    return jsonb_build_object('ok', false, 'error', 'Mã ' || p_ma_nvl || ' đã có tồn kho / giao dịch / tem ở kho NVL, không xoá được');
  end;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy mã NVL');
  end if;
  return jsonb_build_object('ok', true, 'ma_nvl', p_ma_nvl);
end $$;

revoke execute on function public.nvl_catalog_upsert(text, text, text, text, text, text) from public, anon;
grant execute on function public.nvl_catalog_upsert(text, text, text, text, text, text) to authenticated;
revoke execute on function public.nvl_catalog_delete(text) from public, anon;
grant execute on function public.nvl_catalog_delete(text) to authenticated;
