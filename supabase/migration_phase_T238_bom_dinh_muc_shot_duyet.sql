-- ============================================================================
-- T238 (10/11/2026) — BOM Giai đoạn 1: làm đúng dữ liệu
--   1) Danh mục MÁC vật liệu (ADC12, ADC6, HD2, EZDA3…). NVL = mác + nhà cung cấp →
--      BOM chọn MÁC, không khoá 1 nhà cung cấp. NVL có thêm nhóm vật tư
--      (kim loại / bao bì / sơn-hoá chất / linh kiện / khác).
--   2) Định mức kim loại tính theo SHOT: trọng lượng SP, cavity, trọng lượng shot
--      (gồm runner/biscuit/overflow), % hao hụt nấu → hiệu suất kim loại, hồi liệu,
--      định mức gross kg/pcs (cột cũ dinh_muc_nhom_kg_moi_pcs = định mức áp dụng).
--   3) Phiên bản không giới hạn (bỏ cứng V1–V3) + vòng đời Nháp → Chờ duyệt → Hiệu lực
--      → Hết hiệu lực. Lập: Admin hoặc bộ phận Kỹ thuật. Duyệt: chức danh Giám đốc SX /
--      Tổng giám đốc. Bản đã gửi/duyệt không sửa được — muốn đổi thì tạo phiên bản mới.
--      Mỗi mã: tối đa 1 bản Hiệu lực + 1 bản đang soạn (Nháp/Chờ duyệt).
--   4) Vật tư (linh kiện, bao bì, sơn…) gắn với CÔNG ĐOẠN trong lưu trình Danh mục SP.
--   5) Lịch sử thao tác BOM (bom_lich_su). Nạp hàng loạt từ Excel vào bản Nháp.
--   6) Dọn dữ liệu: xoá V2/V3 rỗng do T208 tự tạo (chỉ xoá bản không có định mức,
--      ghi chú, linh kiện). Mã SP mới chỉ tự có 1 bản Nháp.
--   7) View v_bom_hieu_luc (security_invoker) — nguồn định mức cho Giai đoạn 2.
-- An toàn chạy lại. Trạng thái: ĐÃ CHẠY STAGING + PROD 10/11/2026 (prod: còn 84 bản Nháp, 83 mã có mác).
-- ============================================================================

-- ── 1. Mác vật liệu + nhóm vật tư ─────────────────────────────────────────
create table if not exists public.vat_lieu_mac (
  ma_mac        text primary key check (ma_mac = upper(btrim(ma_mac)) and ma_mac <> ''),
  loai_kim_loai text not null check (loai_kim_loai in ('nhom', 'kem')),
  ten           text,
  ghi_chu       text,
  thu_tu        int not null default 0
);
insert into public.vat_lieu_mac (ma_mac, loai_kim_loai, ten, thu_tu) values
  ('ADC12', 'nhom', 'Nhôm ADC12', 1),
  ('ADC6',  'nhom', 'Nhôm ADC6', 2),
  ('HD2',   'nhom', 'Nhôm HD2 (BS1)', 3),
  ('EZDA3', 'kem',  'Kẽm EZDA3 (ZDC)', 4)
on conflict (ma_mac) do nothing;
alter table public.vat_lieu_mac enable row level security;
drop policy if exists vat_lieu_mac_doc on public.vat_lieu_mac;
drop policy if exists vat_lieu_mac_admin on public.vat_lieu_mac;
create policy vat_lieu_mac_doc on public.vat_lieu_mac for select to authenticated using (true);
create policy vat_lieu_mac_admin on public.vat_lieu_mac for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));
revoke all on public.vat_lieu_mac from anon;
grant select, insert, update, delete on public.vat_lieu_mac to authenticated;

alter table public.nvl_materials
  add column if not exists nhom_vat_tu text not null default 'kim_loai',
  add column if not exists ma_mac text references public.vat_lieu_mac(ma_mac);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'nvl_materials_nhom_vat_tu_check') then
    alter table public.nvl_materials add constraint nvl_materials_nhom_vat_tu_check
      check (nhom_vat_tu in ('kim_loai', 'bao_bi', 'son_hoa_chat', 'linh_kien', 'khac'));
  end if;
end $$;

-- Phân nhóm + mác cho mã đang có (chỉ điền chỗ còn trống / mặc định).
update public.nvl_materials set nhom_vat_tu = case
    when ma_nvl ilike 'OUTER%' or ten_nvl ilike '%outer%' or ten_nvl ilike '%thùng%' then 'bao_bi'
    when ma_nvl ilike 'S-%' or ten_nvl ilike '%sơn%' then 'son_hoa_chat'
    when ma_nvl ilike 'C-%' then 'linh_kien'
    when ma_nvl ~* '^(ADC|HD2|EZDA|K-NHN|K-KEN)' or ten_nvl ~* '^(nhôm|kẽm)' then 'kim_loai'
    else 'khac' end
where nhom_vat_tu = 'kim_loai';
update public.nvl_materials set ma_mac = case
    when ma_nvl ~* '^ADC12' or ma_nvl ~* '^K-NHN-12' then 'ADC12'
    when ma_nvl ~* '^ADC6'  or ma_nvl ~* '^K-NHN-06' then 'ADC6'
    when ma_nvl ~* '^HD2' then 'HD2'
    when ma_nvl ~* '^EZDA3' or ma_nvl ~* '^K-KEN-A3' then 'EZDA3' end
where ma_mac is null and nhom_vat_tu = 'kim_loai';

-- ── 2. Quyền BOM ──────────────────────────────────────────────────────────
create or replace function public.bom_quyen_lap() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (public.has_role('admin') or 'Kỹ thuật' = any(public.current_user_bo_phan()));
$$;
create or replace function public.bom_quyen_duyet() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (
    select 1 from public.user_roles where user_id = auth.uid() and chuc_danh in ('giam_doc_sx', 'tong_giam_doc'));
$$;
create or replace function public.bom_quyen_xem() returns boolean
language sql stable security definer set search_path = public as $$
  select public.bom_quyen_lap() or public.bom_quyen_duyet()
      or public.has_role('qlsx_truong_phong', 'kho_nvl', 'qc_manager', 'iatf_admin');
$$;
create or replace function public.bom_quyen_cua_toi() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('xem', public.bom_quyen_xem(), 'lap', public.bom_quyen_lap(), 'duyet', public.bom_quyen_duyet());
$$;
revoke all on function public.bom_quyen_lap(), public.bom_quyen_duyet(), public.bom_quyen_xem(), public.bom_quyen_cua_toi() from public, anon;
grant execute on function public.bom_quyen_lap(), public.bom_quyen_duyet(), public.bom_quyen_xem(), public.bom_quyen_cua_toi() to authenticated;

-- ── 3. Bảng BOM: cột mới ──────────────────────────────────────────────────
do $$ declare c text; begin
  for c in select conname from pg_constraint
    where conrelid = 'public.bom_versions'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%version_no%'
  loop execute format('alter table public.bom_versions drop constraint %I', c); end loop;
end $$;
alter table public.bom_versions add constraint bom_versions_version_no_check check (version_no >= 1);

alter table public.bom_versions
  add column if not exists trang_thai text not null default 'nhap',
  add column if not exists ma_mac text references public.vat_lieu_mac(ma_mac),
  add column if not exists trong_luong_sp_kg numeric,
  add column if not exists cavity smallint,
  add column if not exists trong_luong_shot_kg numeric,
  add column if not exists ty_le_hao_hut_nau numeric,
  add column if not exists so_khuon text,
  add column if not exists rev_ban_ve text,
  add column if not exists ngay_hieu_luc date,
  add column if not exists ly_do_thay_doi text,
  add column if not exists nguoi_lap text,
  add column if not exists nguoi_lap_uid uuid,
  add column if not exists gui_duyet_luc timestamptz,
  add column if not exists nguoi_duyet text,
  add column if not exists nguoi_duyet_uid uuid,
  add column if not exists duyet_luc timestamptz,
  add column if not exists ly_do_tra_lai text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'bom_versions_trang_thai_check') then
    alter table public.bom_versions
      add constraint bom_versions_trang_thai_check check (trang_thai in ('nhap', 'cho_duyet', 'da_duyet', 'het_hieu_luc')),
      add constraint bom_versions_shot_check check (
        (trong_luong_sp_kg is null or trong_luong_sp_kg > 0) and (trong_luong_shot_kg is null or trong_luong_shot_kg > 0)
        and (cavity is null or cavity between 1 and 64) and (ty_le_hao_hut_nau is null or ty_le_hao_hut_nau between 0 and 30)
        and (trong_luong_sp_kg is null or cavity is null or trong_luong_shot_kg is null
             or trong_luong_shot_kg >= trong_luong_sp_kg * cavity));
  end if;
end $$;
-- Số liệu tính ra từ shot (cột sinh tự động, không nhập tay).
alter table public.bom_versions
  add column if not exists hieu_suat_kim_loai_pct numeric generated always as
    (round(trong_luong_sp_kg * cavity / nullif(trong_luong_shot_kg, 0) * 100, 1)) stored,
  add column if not exists hoi_lieu_kg_moi_pcs numeric generated always as
    (round((trong_luong_shot_kg - trong_luong_sp_kg * cavity) / nullif(cavity, 0), 5)) stored,
  add column if not exists dinh_muc_tinh_kg_moi_pcs numeric generated always as
    (round(trong_luong_shot_kg / nullif(cavity, 0) * (1 + coalesce(ty_le_hao_hut_nau, 0) / 100), 5)) stored;

alter table public.bom_components add column if not exists cong_doan text;

-- Dọn bản rỗng T208 tự tạo (V2/V3 không có dữ liệu riêng).
delete from public.bom_versions b
where b.version_no > 1 and b.dinh_muc_nhom_kg_moi_pcs is null and b.ghi_chu is null
  and b.trang_thai = 'nhap' and b.trong_luong_shot_kg is null
  and not exists (select 1 from public.bom_components c where c.bom_version_id = b.id);

-- Điền sẵn mác / cavity / số khuôn từ Danh mục SP cho bản Nháp còn trống.
update public.bom_versions b set
  ma_mac = coalesce(b.ma_mac,
    (select n.ma_mac from public.nvl_materials n where n.ma_nvl = coalesce(b.ma_nhom, p.nguyen_lieu)),
    (select m.ma_mac from public.vat_lieu_mac m where m.ma_mac = upper(btrim(p.nguyen_lieu)))),
  cavity = coalesce(b.cavity, case when p.cavity between 1 and 64 then p.cavity::smallint end),
  so_khuon = coalesce(b.so_khuon, nullif(btrim(p.so_khuon), ''))
from public.master_products p
where p.ma_sp = b.ma_sp and b.trang_thai = 'nhap';

-- Mã còn nhiều bản Nháp có dữ liệu (dữ liệu thử staging): giữ bản số lớn nhất, bản cũ → Hết hiệu lực.
update public.bom_versions b set trang_thai = 'het_hieu_luc'
where b.trang_thai = 'nhap' and exists (
  select 1 from public.bom_versions x where x.ma_sp = b.ma_sp and x.trang_thai = 'nhap' and x.version_no > b.version_no);

create unique index if not exists bom_versions_1_hieu_luc on public.bom_versions (ma_sp) where trang_thai = 'da_duyet';
create unique index if not exists bom_versions_1_dang_soan on public.bom_versions (ma_sp) where trang_thai in ('nhap', 'cho_duyet');

-- Mã SP mới: chỉ 1 bản Nháp (thay 3 bản rỗng của T208).
create or replace function public.bom_create_default_versions()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.bom_versions (ma_sp, version_no, cavity, so_khuon)
  values (new.ma_sp, 1, case when new.cavity between 1 and 64 then new.cavity::smallint end, nullif(btrim(new.so_khuon), ''))
  on conflict (ma_sp, version_no) do nothing;
  return new;
end $$;
revoke execute on function public.bom_create_default_versions() from public, anon, authenticated;

-- ── 4. Lịch sử ────────────────────────────────────────────────────────────
create table if not exists public.bom_lich_su (
  id             bigint generated always as identity primary key,
  bom_version_id bigint references public.bom_versions(id) on delete set null,
  ma_sp          text not null,
  version_no     smallint,
  hanh_dong      text not null,
  ghi_chu        text,
  du_lieu        jsonb,
  nguoi          text,
  nguoi_uid      uuid,
  luc            timestamptz not null default now()
);
create index if not exists bom_lich_su_sp on public.bom_lich_su (ma_sp, luc desc);
alter table public.bom_lich_su enable row level security;
drop policy if exists bom_lich_su_doc on public.bom_lich_su;
create policy bom_lich_su_doc on public.bom_lich_su for select to authenticated using (public.bom_quyen_xem());
revoke all on public.bom_lich_su from public, anon, authenticated;
grant select on public.bom_lich_su to authenticated;

create or replace function public.bom_ghi_lich_su(p_id bigint, p_hanh_dong text, p_ghi_chu text)
returns void language sql security definer set search_path = public as $$
  insert into public.bom_lich_su (bom_version_id, ma_sp, version_no, hanh_dong, ghi_chu, du_lieu, nguoi, nguoi_uid)
  select b.id, b.ma_sp, b.version_no, p_hanh_dong, p_ghi_chu,
         to_jsonb(b) || jsonb_build_object('linh_kien',
           (select coalesce(jsonb_agg(to_jsonb(c) - 'id' - 'bom_version_id' order by c.id), '[]') from public.bom_components c where c.bom_version_id = b.id)),
         public.duc_su_co_nguoi_hien_tai(), auth.uid()
  from public.bom_versions b where b.id = p_id;
$$;
revoke all on function public.bom_ghi_lich_su(bigint, text, text) from public, anon, authenticated;

-- ── 5. RLS đọc BOM: người lập / duyệt / kế hoạch / kho / QC ───────────────
drop policy if exists bom_versions_admin_doc on public.bom_versions;
drop policy if exists bom_components_admin_doc on public.bom_components;
drop policy if exists bom_versions_doc on public.bom_versions;
drop policy if exists bom_components_doc on public.bom_components;
create policy bom_versions_doc on public.bom_versions for select to authenticated using (public.bom_quyen_xem());
create policy bom_components_doc on public.bom_components for select to authenticated using (public.bom_quyen_xem());

-- ── 6. RPC ────────────────────────────────────────────────────────────────
drop function if exists public.bom_save_version(bigint, text, numeric, text[], text, jsonb, text);

-- Kiểm tra + ghi phần đầu phiên bản (dùng chung cho lưu nháp và nạp Excel).
create or replace function public.bom_ghi_dau(p_id bigint, p_data jsonb, p_chi_dien_trong boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare
  b public.bom_versions%rowtype;
  v_mac text := upper(nullif(btrim(p_data->>'ma_mac'), ''));
  v_sp numeric := nullif(p_data->>'trong_luong_sp_kg', '')::numeric;
  v_cav smallint := nullif(p_data->>'cavity', '')::smallint;
  v_shot numeric := nullif(p_data->>'trong_luong_shot_kg', '')::numeric;
  v_hh numeric := nullif(p_data->>'ty_le_hao_hut_nau', '')::numeric;
  v_dm_tay numeric := nullif(p_data->>'dinh_muc_nhom_kg_moi_pcs', '')::numeric;
  v_ngay date := nullif(p_data->>'ngay_hieu_luc', '')::date;
begin
  select * into b from public.bom_versions where id = p_id for update;
  if v_mac is not null and not exists (select 1 from public.vat_lieu_mac where ma_mac = v_mac) then
    raise exception 'Mác vật liệu % chưa có trong danh mục mác', v_mac;
  end if;
  if p_chi_dien_trong then   -- nạp Excel: ô trống trong file thì giữ giá trị đang có
    v_mac := coalesce(v_mac, b.ma_mac); v_sp := coalesce(v_sp, b.trong_luong_sp_kg); v_cav := coalesce(v_cav, b.cavity);
    v_shot := coalesce(v_shot, b.trong_luong_shot_kg); v_hh := coalesce(v_hh, b.ty_le_hao_hut_nau);
    v_ngay := coalesce(v_ngay, b.ngay_hieu_luc);
  end if;
  if v_sp is not null and v_sp <= 0 or v_shot is not null and v_shot <= 0 then raise exception 'Trọng lượng phải lớn hơn 0'; end if;
  if v_cav is not null and (v_cav < 1 or v_cav > 64) then raise exception 'Cavity phải từ 1 đến 64'; end if;
  if v_hh is not null and (v_hh < 0 or v_hh > 30) then raise exception 'Hao hụt nấu phải từ 0 đến 30%%'; end if;
  if v_sp is not null and v_cav is not null and v_shot is not null and v_shot < v_sp * v_cav then
    raise exception 'Trọng lượng shot (% kg) nhỏ hơn trọng lượng SP × cavity (% kg) — kiểm tra lại', v_shot, v_sp * v_cav;
  end if;
  if v_dm_tay is not null and v_dm_tay < 0 then raise exception 'Định mức không được âm'; end if;
  update public.bom_versions set
    ma_mac = v_mac,
    trong_luong_sp_kg = v_sp, cavity = v_cav, trong_luong_shot_kg = v_shot, ty_le_hao_hut_nau = v_hh,
    -- Đủ số liệu shot → định mức áp dụng = định mức tính; chưa đủ → cho nhập tay (VD hàng nhập phôi).
    dinh_muc_nhom_kg_moi_pcs = case when v_shot is not null and v_cav is not null
      then round(v_shot / v_cav * (1 + coalesce(v_hh, 0) / 100), 5)
      else coalesce(v_dm_tay, case when p_chi_dien_trong then b.dinh_muc_nhom_kg_moi_pcs end) end,
    so_khuon = case when p_chi_dien_trong then coalesce(nullif(btrim(p_data->>'so_khuon'), ''), b.so_khuon) else nullif(btrim(p_data->>'so_khuon'), '') end,
    rev_ban_ve = case when p_chi_dien_trong then coalesce(nullif(btrim(p_data->>'rev_ban_ve'), ''), b.rev_ban_ve) else nullif(btrim(p_data->>'rev_ban_ve'), '') end,
    ngay_hieu_luc = v_ngay,
    ly_do_thay_doi = case when p_chi_dien_trong then coalesce(nullif(btrim(p_data->>'ly_do_thay_doi'), ''), b.ly_do_thay_doi) else nullif(btrim(p_data->>'ly_do_thay_doi'), '') end,
    ghi_chu = case when p_chi_dien_trong then coalesce(nullif(btrim(p_data->>'ghi_chu'), ''), b.ghi_chu) else nullif(btrim(p_data->>'ghi_chu'), '') end,
    nguoi_lap = public.duc_su_co_nguoi_hien_tai(), nguoi_lap_uid = auth.uid(),
    updated_by = public.duc_su_co_nguoi_hien_tai()
  where id = p_id;
end $$;
revoke all on function public.bom_ghi_dau(bigint, jsonb, boolean) from public, anon, authenticated;

create or replace function public.bom_luu_nhap(p_id bigint, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.bom_versions%rowtype; r jsonb; v_route text[]; v_cd text;
begin
  if not public.bom_quyen_lap() then raise exception 'Chỉ Admin hoặc bộ phận Kỹ thuật được lập BOM'; end if;
  select * into b from public.bom_versions where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiên bản BOM'; end if;
  if b.trang_thai <> 'nhap' then raise exception 'Chỉ sửa được bản Nháp. Bản đã gửi duyệt / hiệu lực muốn đổi thì tạo phiên bản mới.'; end if;
  if nullif(p_data->>'updated_at', '') is not null and (p_data->>'updated_at')::timestamptz is distinct from b.updated_at then
    raise exception 'BOM vừa được người khác sửa. Tải lại trang rồi nhập lại.';
  end if;
  perform public.bom_ghi_dau(p_id, p_data, false);
  select array_agg(btrim(x)) into v_route
  from public.master_products p, unnest(string_to_array(coalesce(p.quy_trinh_cong_doan, ''), ',')) x
  where p.ma_sp = b.ma_sp and btrim(x) <> '';
  delete from public.bom_components where bom_version_id = p_id;
  for r in select value from jsonb_array_elements(coalesce(p_data->'linh_kien', '[]'::jsonb)) loop
    if nullif(btrim(r->>'ma_linh_kien'), '') is null then continue; end if;
    if coalesce(nullif(r->>'dinh_muc_moi_pcs', '')::numeric, -1) < 0 then
      raise exception 'Định mức vật tư % phải là số không âm', r->>'ma_linh_kien';
    end if;
    v_cd := nullif(btrim(r->>'cong_doan'), '');
    if v_cd is not null and not (v_cd = any(coalesce(v_route, array[]::text[]))) then
      raise exception 'Công đoạn "%" không có trong lưu trình của mã %', v_cd, b.ma_sp;
    end if;
    insert into public.bom_components (bom_version_id, ma_linh_kien, ten_linh_kien, dinh_muc_moi_pcs, don_vi_tinh, ghi_chu, cong_doan)
    values (p_id, btrim(r->>'ma_linh_kien'), nullif(btrim(r->>'ten_linh_kien'), ''), (r->>'dinh_muc_moi_pcs')::numeric,
            coalesce(nullif(btrim(r->>'don_vi_tinh'), ''), 'pcs'), nullif(btrim(r->>'ghi_chu'), ''), v_cd)
    on conflict (bom_version_id, ma_linh_kien) do update set dinh_muc_moi_pcs = excluded.dinh_muc_moi_pcs;
  end loop;
  perform public.bom_ghi_lich_su(p_id, 'luu_nhap', null);
  return (select to_jsonb(x) from public.bom_versions x where id = p_id);
end $$;

create or replace function public.bom_gui_duyet(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare b public.bom_versions%rowtype; v_duc boolean; v_loi text[] := '{}';
begin
  if not public.bom_quyen_lap() then raise exception 'Chỉ Admin hoặc bộ phận Kỹ thuật được gửi duyệt BOM'; end if;
  select * into b from public.bom_versions where id = p_id for update;
  if not found or b.trang_thai <> 'nhap' then raise exception 'Chỉ gửi duyệt được bản Nháp'; end if;
  select coalesce(p.quy_trinh_cong_doan, '') ilike '%Đúc%' into v_duc from public.master_products p where p.ma_sp = b.ma_sp;
  if b.ngay_hieu_luc is null then v_loi := array_append(v_loi, 'ngày hiệu lực'::text); end if;
  if b.version_no > 1 and b.ly_do_thay_doi is null then v_loi := array_append(v_loi, 'lý do thay đổi so với bản trước'::text); end if;
  if v_duc then
    if b.ma_mac is null then v_loi := array_append(v_loi, 'mác vật liệu'::text); end if;
    if b.trong_luong_sp_kg is null then v_loi := array_append(v_loi, 'trọng lượng sản phẩm'::text); end if;
    if b.cavity is null then v_loi := array_append(v_loi, 'cavity'::text); end if;
    if b.trong_luong_shot_kg is null then v_loi := array_append(v_loi, 'trọng lượng shot'::text); end if;
    if b.ty_le_hao_hut_nau is null then v_loi := array_append(v_loi, '% hao hụt nấu'::text); end if;
  end if;
  if cardinality(v_loi) > 0 then raise exception 'Chưa gửi duyệt được — còn thiếu: %', array_to_string(v_loi, ', '); end if;
  update public.bom_versions set trang_thai = 'cho_duyet', gui_duyet_luc = now(), ly_do_tra_lai = null where id = p_id;
  perform public.bom_ghi_lich_su(p_id, 'gui_duyet', null);
end $$;

create or replace function public.bom_rut_lai(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.bom_quyen_lap() then raise exception 'Chỉ Admin hoặc bộ phận Kỹ thuật được rút lại BOM'; end if;
  update public.bom_versions set trang_thai = 'nhap', gui_duyet_luc = null where id = p_id and trang_thai = 'cho_duyet';
  if not found then raise exception 'Chỉ rút lại được bản đang chờ duyệt'; end if;
  perform public.bom_ghi_lich_su(p_id, 'rut_lai', null);
end $$;

create or replace function public.bom_duyet(p_id bigint, p_dong_y boolean, p_ly_do text default null)
returns void language plpgsql security definer set search_path = public as $$
declare b public.bom_versions%rowtype; v_cu bigint;
begin
  if not public.bom_quyen_duyet() then raise exception 'Chỉ Giám đốc sản xuất / Tổng giám đốc được duyệt BOM'; end if;
  select * into b from public.bom_versions where id = p_id for update;
  if not found or b.trang_thai <> 'cho_duyet' then raise exception 'Chỉ duyệt được bản đang chờ duyệt'; end if;
  if not p_dong_y then
    if nullif(btrim(p_ly_do), '') is null then raise exception 'Nhập lý do trả lại'; end if;
    update public.bom_versions set trang_thai = 'nhap', ly_do_tra_lai = btrim(p_ly_do) where id = p_id;
    perform public.bom_ghi_lich_su(p_id, 'tra_lai', btrim(p_ly_do));
    return;
  end if;
  select id into v_cu from public.bom_versions where ma_sp = b.ma_sp and trang_thai = 'da_duyet' for update;
  if v_cu is not null then
    update public.bom_versions set trang_thai = 'het_hieu_luc' where id = v_cu;
    perform public.bom_ghi_lich_su(v_cu, 'het_hieu_luc', 'Thay bằng V' || b.version_no);
  end if;
  update public.bom_versions set trang_thai = 'da_duyet', nguoi_duyet = public.duc_su_co_nguoi_hien_tai(),
    nguoi_duyet_uid = auth.uid(), duyet_luc = now(), ly_do_tra_lai = null where id = p_id;
  perform public.bom_ghi_lich_su(p_id, 'duyet', nullif(btrim(p_ly_do), ''));
end $$;

-- Tạo phiên bản mới (chép từ bản mới nhất) khi mã chưa có bản đang soạn.
create or replace function public.bom_tao_phien_ban(p_ma_sp text)
returns bigint language plpgsql security definer set search_path = public as $$
declare src public.bom_versions%rowtype; v_id bigint;
begin
  if not public.bom_quyen_lap() then raise exception 'Chỉ Admin hoặc bộ phận Kỹ thuật được tạo phiên bản BOM'; end if;
  if not exists (select 1 from public.master_products where ma_sp = p_ma_sp) then raise exception 'Không có mã SP %', p_ma_sp; end if;
  perform pg_advisory_xact_lock(hashtextextended('bom:' || p_ma_sp, 0));
  if exists (select 1 from public.bom_versions where ma_sp = p_ma_sp and trang_thai in ('nhap', 'cho_duyet')) then
    raise exception 'Mã % đang có bản Nháp / Chờ duyệt — hoàn tất bản đó trước', p_ma_sp;
  end if;
  select * into src from public.bom_versions where ma_sp = p_ma_sp order by version_no desc limit 1;
  insert into public.bom_versions (ma_sp, version_no, ma_nhom, ma_mac, dinh_muc_nhom_kg_moi_pcs, trong_luong_sp_kg, cavity,
      trong_luong_shot_kg, ty_le_hao_hut_nau, so_khuon, rev_ban_ve, ghi_chu, trang_thai, nguoi_lap, nguoi_lap_uid, updated_by)
  values (p_ma_sp, coalesce(src.version_no, 0) + 1, src.ma_nhom, src.ma_mac, src.dinh_muc_nhom_kg_moi_pcs, src.trong_luong_sp_kg,
      src.cavity, src.trong_luong_shot_kg, src.ty_le_hao_hut_nau, src.so_khuon, src.rev_ban_ve, src.ghi_chu, 'nhap',
      public.duc_su_co_nguoi_hien_tai(), auth.uid(), public.duc_su_co_nguoi_hien_tai())
  returning id into v_id;
  if src.id is not null then
    insert into public.bom_components (bom_version_id, ma_linh_kien, ten_linh_kien, dinh_muc_moi_pcs, don_vi_tinh, ghi_chu, cong_doan)
    select v_id, ma_linh_kien, ten_linh_kien, dinh_muc_moi_pcs, don_vi_tinh, ghi_chu, cong_doan
    from public.bom_components where bom_version_id = src.id;
  end if;
  perform public.bom_ghi_lich_su(v_id, 'tao_phien_ban', case when src.id is not null then 'Chép từ V' || src.version_no end);
  return v_id;
end $$;

-- Nạp hàng loạt từ Excel vào bản Nháp (ô trống giữ nguyên). Trả kết quả từng dòng.
create or replace function public.bom_nap_excel(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; v_id bigint; v_sp text; kq jsonb := '[]'; n_ok int := 0;
begin
  if not public.bom_quyen_lap() then raise exception 'Chỉ Admin hoặc bộ phận Kỹ thuật được nạp BOM'; end if;
  if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) > 500 then raise exception 'File phải có 1–500 dòng'; end if;
  for r in select value from jsonb_array_elements(p_rows) loop
    v_sp := btrim(r->>'ma_sp');
    begin
      if v_sp is null or v_sp = '' then raise exception 'Thiếu mã SP'; end if;
      select id into v_id from public.bom_versions where ma_sp = v_sp and trang_thai = 'nhap';
      if v_id is null then
        if exists (select 1 from public.bom_versions where ma_sp = v_sp and trang_thai = 'cho_duyet') then
          raise exception 'Đang chờ duyệt — rút lại trước khi nạp';
        end if;
        v_id := public.bom_tao_phien_ban(v_sp);
      end if;
      perform public.bom_ghi_dau(v_id, r, true);
      perform public.bom_ghi_lich_su(v_id, 'nap_excel', null);
      kq := kq || jsonb_build_object('ma_sp', v_sp, 'ok', true);
      n_ok := n_ok + 1;
    exception when others then
      kq := kq || jsonb_build_object('ma_sp', v_sp, 'ok', false, 'loi', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('so_ok', n_ok, 'so_dong', jsonb_array_length(p_rows), 'chi_tiet', kq);
end $$;

revoke all on function public.bom_luu_nhap(bigint, jsonb), public.bom_gui_duyet(bigint), public.bom_rut_lai(bigint),
  public.bom_duyet(bigint, boolean, text), public.bom_tao_phien_ban(text), public.bom_nap_excel(jsonb) from public, anon;
grant execute on function public.bom_luu_nhap(bigint, jsonb), public.bom_gui_duyet(bigint), public.bom_rut_lai(bigint),
  public.bom_duyet(bigint, boolean, text), public.bom_tao_phien_ban(text), public.bom_nap_excel(jsonb) to authenticated;

-- ── 7. Danh mục NVL: thêm nhóm vật tư + mác; Kỹ thuật được sửa ──────────────
drop function if exists public.nvl_catalog_upsert(text, text, text, text, text, text);
create or replace function public.nvl_catalog_upsert(
  p_ma_nvl text, p_ten_nvl text, p_nha_cung_cap text, p_ma_nvl_ncc text, p_khach_hang text, p_san_pham text,
  p_nhom_vat_tu text default null, p_ma_mac text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_nhom text := coalesce(nullif(btrim(p_nhom_vat_tu), ''), 'kim_loai'); v_mac text := upper(nullif(btrim(p_ma_mac), ''));
begin
  if not public.bom_quyen_lap() then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Admin hoặc bộ phận Kỹ thuật được cập nhật danh mục NVL');
  end if;
  if nullif(trim(p_ma_nvl), '') is null then return jsonb_build_object('ok', false, 'error', 'Thiếu mã NVL Toyotaki'); end if;
  if v_nhom not in ('kim_loai', 'bao_bi', 'son_hoa_chat', 'linh_kien', 'khac') then
    return jsonb_build_object('ok', false, 'error', 'Nhóm vật tư không hợp lệ');
  end if;
  if v_nhom = 'kim_loai' and v_mac is null then return jsonb_build_object('ok', false, 'error', 'NVL kim loại phải chọn mác vật liệu'); end if;
  if v_mac is not null and not exists (select 1 from public.vat_lieu_mac where ma_mac = v_mac) then
    return jsonb_build_object('ok', false, 'error', 'Mác ' || v_mac || ' chưa có trong danh mục mác');
  end if;
  insert into public.nvl_materials (ma_nvl, ten_nvl, nha_cung_cap, ma_nvl_ncc, khach_hang, san_pham, nhom_vat_tu, ma_mac)
  values (trim(p_ma_nvl), coalesce(nullif(trim(p_ten_nvl), ''), trim(p_ma_nvl)), nullif(trim(p_nha_cung_cap), ''),
          nullif(trim(p_ma_nvl_ncc), ''), nullif(trim(p_khach_hang), ''), nullif(trim(p_san_pham), ''), v_nhom,
          case when v_nhom = 'kim_loai' then v_mac end)
  on conflict (ma_nvl) do update set
    ten_nvl = excluded.ten_nvl, nha_cung_cap = excluded.nha_cung_cap, ma_nvl_ncc = excluded.ma_nvl_ncc,
    khach_hang = excluded.khach_hang, san_pham = excluded.san_pham, nhom_vat_tu = excluded.nhom_vat_tu, ma_mac = excluded.ma_mac;
  return jsonb_build_object('ok', true, 'ma_nvl', trim(p_ma_nvl));
end $$;
revoke execute on function public.nvl_catalog_upsert(text, text, text, text, text, text, text, text) from public, anon;
grant execute on function public.nvl_catalog_upsert(text, text, text, text, text, text, text, text) to authenticated;

-- ── 8. View định mức hiệu lực (Giai đoạn 2 dùng) ──────────────────────────
create or replace view public.v_bom_hieu_luc with (security_invoker = true) as
select b.ma_sp, b.version_no, b.id as bom_version_id, b.ma_mac, b.trong_luong_sp_kg, b.cavity, b.trong_luong_shot_kg,
       b.ty_le_hao_hut_nau, b.hieu_suat_kim_loai_pct, b.hoi_lieu_kg_moi_pcs, b.dinh_muc_nhom_kg_moi_pcs as dinh_muc_kg_moi_pcs,
       b.so_khuon, b.rev_ban_ve, b.ngay_hieu_luc, b.nguoi_duyet, b.duyet_luc
from public.bom_versions b where b.trang_thai = 'da_duyet';
revoke all on public.v_bom_hieu_luc from anon;
grant select on public.v_bom_hieu_luc to authenticated;

notify pgrst, 'reload schema';
