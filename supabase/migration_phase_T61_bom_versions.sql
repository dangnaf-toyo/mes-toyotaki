-- ============================================================================
-- T61 — BOM theo model, 3 phiên bản/model
-- Chạy file này trong Supabase SQL Editor (Production và Staging nếu dùng cả 2).
-- ============================================================================

create table if not exists public.bom_versions (
  id                          bigserial primary key,
  ma_sp                       text not null references public.master_products(ma_sp) on delete cascade,
  version_no                  smallint not null check (version_no between 1 and 3),
  ma_nhom                     text,
  dinh_muc_nhom_kg_moi_pcs     numeric check (dinh_muc_nhom_kg_moi_pcs is null or dinh_muc_nhom_kg_moi_pcs >= 0),
  quy_trinh_cong_doan         text[] not null default array['Đúc','Bavia','Gia công CNC','Sơn'],
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

-- Mỗi model mới tự có ba phiên bản BOM trống.
create or replace function public.bom_create_default_versions()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.bom_versions (ma_sp, version_no)
  values (new.ma_sp, 1), (new.ma_sp, 2), (new.ma_sp, 3)
  on conflict (ma_sp, version_no) do nothing;
  return new;
end $$;

drop trigger if exists trg_master_products_bom_versions on public.master_products;
create trigger trg_master_products_bom_versions after insert on public.master_products
for each row execute function public.bom_create_default_versions();

-- Tạo ba phiên bản cho toàn bộ model đã có.
insert into public.bom_versions (ma_sp, version_no)
select p.ma_sp, v.version_no
from public.master_products p
cross join (values (1::smallint), (2::smallint), (3::smallint)) as v(version_no)
on conflict (ma_sp, version_no) do nothing;

-- Kế thừa mã nhôm hiện có trong Master để cả ba BOM có dữ liệu khởi đầu;
-- định mức và linh kiện vẫn để người dùng khai báo theo từng phiên bản.
update public.bom_versions b
set ma_nhom = p.nguyen_lieu
from public.master_products p
where p.ma_sp = b.ma_sp
  and b.ma_nhom is null
  and nullif(trim(p.nguyen_lieu), '') is not null;

alter table public.bom_versions enable row level security;
alter table public.bom_components enable row level security;

drop policy if exists "public read bom_versions" on public.bom_versions;
create policy "public read bom_versions" on public.bom_versions for select using (true);
drop policy if exists "public read bom_components" on public.bom_components;
create policy "public read bom_components" on public.bom_components for select using (true);

-- Chỉ Admin cập nhật BOM. Trang bom.html gọi RPC dưới đây để lưu phần đầu BOM
-- và danh sách linh kiện trong một giao dịch duy nhất.
create or replace function public.bom_save_version(
  p_id bigint,
  p_ma_nhom text,
  p_dinh_muc_nhom_kg_moi_pcs numeric,
  p_quy_trinh_cong_doan text[],
  p_ghi_chu text,
  p_components jsonb,
  p_updated_by text
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

  update public.bom_versions
  set ma_nhom = nullif(trim(p_ma_nhom), ''),
      dinh_muc_nhom_kg_moi_pcs = p_dinh_muc_nhom_kg_moi_pcs,
      quy_trinh_cong_doan = coalesce(nullif(p_quy_trinh_cong_doan, array[]::text[]), array['Đúc','Bavia','Gia công CNC','Sơn']),
      ghi_chu = nullif(trim(p_ghi_chu), ''),
      updated_by = nullif(trim(p_updated_by), '')
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

grant execute on function public.bom_save_version(bigint, text, numeric, text[], text, jsonb, text) to authenticated;
