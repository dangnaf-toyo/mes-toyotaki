-- T294: BOM chọn thẳng mã NVL kim loại (bom_versions.ma_nhom = nvl_materials.ma_nvl); mác tự lấy theo NVL.
-- Excel cũ (chỉ gửi ma_mac) vẫn chạy: giữ NVL cũ nếu cùng mác, khác mác thì bỏ NVL.
-- Gửi duyệt BOM có công đoạn Đúc bắt buộc có NVL kim loại.
begin;

create or replace function public.bom_ghi_dau(p_id bigint, p_data jsonb, p_chi_dien_trong boolean default false)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  b public.bom_versions%rowtype;
  v_mac text := upper(nullif(btrim(p_data->>'ma_mac'), ''));
  v_nvl text := nullif(btrim(p_data->>'ma_nvl'), '');
  v_mac_nvl text;
  v_sp numeric := nullif(p_data->>'trong_luong_sp_kg', '')::numeric;
  v_cav smallint := nullif(p_data->>'cavity', '')::smallint;
  v_shot numeric := nullif(p_data->>'trong_luong_shot_kg', '')::numeric;
  v_hh numeric := nullif(p_data->>'ty_le_hao_hut_nau', '')::numeric;
  v_dm_tay numeric := nullif(p_data->>'dinh_muc_nhom_kg_moi_pcs', '')::numeric;
  v_ngay date := nullif(p_data->>'ngay_hieu_luc', '')::date;
begin
  select * into b from public.bom_versions where id = p_id for update;

  if p_data ? 'ma_nvl' then
    -- Màn BOM: chọn NVL, mác theo NVL.
    if v_nvl is not null then
      select ma_mac into v_mac_nvl from public.nvl_materials where ma_nvl = v_nvl and nhom_vat_tu = 'kim_loai';
      if not found then raise exception 'NVL % không phải kim loại trong danh mục NVL', v_nvl; end if;
      if v_mac_nvl is null then raise exception 'NVL % chưa gắn mác vật liệu — sửa ở tab Danh mục NVL', v_nvl; end if;
      v_mac := v_mac_nvl;
    else
      v_mac := null;
    end if;
  else
    -- Excel / luồng cũ chỉ có mác: giữ NVL cũ nếu cùng mác.
    v_nvl := b.ma_nhom;
    if v_mac is not null and v_nvl is not null
       and v_mac is distinct from (select ma_mac from public.nvl_materials where ma_nvl = v_nvl) then
      v_nvl := null;
    end if;
  end if;

  if v_mac is not null and not exists (select 1 from public.vat_lieu_mac where ma_mac = v_mac) then
    raise exception 'Mác vật liệu % chưa có trong danh mục mác', v_mac;
  end if;
  if p_chi_dien_trong then
    v_mac := coalesce(v_mac, b.ma_mac);
    if p_data ? 'ma_nvl' then v_nvl := coalesce(v_nvl, b.ma_nhom); end if;
    v_sp := coalesce(v_sp, b.trong_luong_sp_kg); v_cav := coalesce(v_cav, b.cavity);
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
    ma_nhom = v_nvl,
    trong_luong_sp_kg = v_sp, cavity = v_cav, trong_luong_shot_kg = v_shot, ty_le_hao_hut_nau = v_hh,
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
end $function$;

create or replace function public.bom_gui_duyet(p_id bigint)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare b public.bom_versions%rowtype; v_duc boolean; v_loi text[] := '{}';
begin
  if not public.bom_quyen_lap() then raise exception 'Chỉ Admin hoặc bộ phận Kỹ thuật được gửi duyệt BOM'; end if;
  select * into b from public.bom_versions where id = p_id for update;
  if not found or b.trang_thai <> 'nhap' then raise exception 'Chỉ gửi duyệt được bản Nháp'; end if;
  select coalesce(p.quy_trinh_cong_doan, '') ilike '%Đúc%' into v_duc from public.master_products p where p.ma_sp = b.ma_sp;
  if b.ngay_hieu_luc is null then v_loi := array_append(v_loi, 'ngày hiệu lực'::text); end if;
  if b.version_no > 1 and b.ly_do_thay_doi is null then v_loi := array_append(v_loi, 'lý do thay đổi so với bản trước'::text); end if;
  if v_duc then
    if b.ma_nhom is null or b.ma_mac is null then v_loi := array_append(v_loi, 'NVL kim loại'::text); end if;
    if b.trong_luong_sp_kg is null then v_loi := array_append(v_loi, 'trọng lượng sản phẩm'::text); end if;
    if b.cavity is null then v_loi := array_append(v_loi, 'cavity'::text); end if;
    if b.trong_luong_shot_kg is null then v_loi := array_append(v_loi, 'trọng lượng shot'::text); end if;
    if b.ty_le_hao_hut_nau is null then v_loi := array_append(v_loi, '% hao hụt nấu'::text); end if;
  end if;
  if cardinality(v_loi) > 0 then raise exception 'Chưa gửi duyệt được — còn thiếu: %', array_to_string(v_loi, ', '); end if;
  update public.bom_versions set trang_thai = 'cho_duyet', gui_duyet_luc = now(), ly_do_tra_lai = null where id = p_id;
  perform public.bom_ghi_lich_su(p_id, 'gui_duyet', null);
end $function$;

-- bom_ghi_dau chỉ gọi nội bộ (bom_luu_nhap / bom_nap_excel kiểm bom_quyen_lap); bom_gui_duyet kiểm bom_quyen_lap.
revoke execute on function public.bom_ghi_dau(bigint, jsonb, boolean) from public, anon, authenticated;
revoke execute on function public.bom_gui_duyet(bigint) from public, anon;
grant execute on function public.bom_gui_duyet(bigint) to authenticated;

notify pgrst, 'reload schema';
commit;
