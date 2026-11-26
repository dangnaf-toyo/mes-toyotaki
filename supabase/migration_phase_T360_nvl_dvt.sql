-- T360: Danh mục NVL thêm Đơn vị tính (kg/pcs). Là mặc định khi dùng NVL ở in tem, phiếu cấp.
alter table public.nvl_materials add column if not exists dvt text not null default 'kg';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'nvl_materials_dvt_check') then
    alter table public.nvl_materials add constraint nvl_materials_dvt_check check (dvt in ('kg', 'pcs'));
  end if;
end $$;
-- Mã có tem NCC (Astemo, đếm PCS) → pcs
update public.nvl_materials set dvt = 'pcs' where ma_tem_ncc is not null and dvt = 'kg';

drop function if exists public.nvl_catalog_upsert(text, text, text, text, text, text, text, text);
create or replace function public.nvl_catalog_upsert(
  p_ma_nvl text, p_ten_nvl text, p_nha_cung_cap text, p_ma_nvl_ncc text, p_khach_hang text, p_san_pham text,
  p_nhom_vat_tu text, p_ma_mac text, p_dvt text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_nhom text := coalesce(nullif(btrim(p_nhom_vat_tu), ''), 'kim_loai');
        v_mac text := upper(nullif(btrim(p_ma_mac), ''));
        v_dvt text := nullif(lower(trim(p_dvt)), '');
begin
  if not public.bom_quyen_lap() then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Admin hoặc bộ phận Kỹ thuật được cập nhật danh mục NVL');
  end if;
  if nullif(trim(p_ma_nvl), '') is null then return jsonb_build_object('ok', false, 'error', 'Thiếu mã NVL Toyotaki'); end if;
  if v_nhom not in ('kim_loai', 'bao_bi', 'son_hoa_chat', 'linh_kien', 'khac') then
    return jsonb_build_object('ok', false, 'error', 'Nhóm vật tư không hợp lệ');
  end if;
  if v_dvt is not null and v_dvt not in ('kg', 'pcs') then
    return jsonb_build_object('ok', false, 'error', 'Đơn vị tính chỉ nhận kg hoặc pcs');
  end if;
  if v_nhom = 'kim_loai' and v_mac is null then return jsonb_build_object('ok', false, 'error', 'NVL kim loại phải chọn mác vật liệu'); end if;
  if v_mac is not null and not exists (select 1 from public.vat_lieu_mac where ma_mac = v_mac) then
    return jsonb_build_object('ok', false, 'error', 'Mác ' || v_mac || ' chưa có trong danh mục mác');
  end if;
  insert into public.nvl_materials (ma_nvl, ten_nvl, nha_cung_cap, ma_nvl_ncc, khach_hang, san_pham, nhom_vat_tu, ma_mac, dvt)
  values (trim(p_ma_nvl), coalesce(nullif(trim(p_ten_nvl), ''), trim(p_ma_nvl)), nullif(trim(p_nha_cung_cap), ''),
          nullif(trim(p_ma_nvl_ncc), ''), nullif(trim(p_khach_hang), ''), nullif(trim(p_san_pham), ''), v_nhom,
          case when v_nhom = 'kim_loai' then v_mac end, coalesce(v_dvt, 'kg'))
  on conflict (ma_nvl) do update set
    ten_nvl = excluded.ten_nvl, nha_cung_cap = excluded.nha_cung_cap, ma_nvl_ncc = excluded.ma_nvl_ncc,
    khach_hang = excluded.khach_hang, san_pham = excluded.san_pham, nhom_vat_tu = excluded.nhom_vat_tu, ma_mac = excluded.ma_mac,
    dvt = coalesce(v_dvt, nvl_materials.dvt);
  return jsonb_build_object('ok', true, 'ma_nvl', trim(p_ma_nvl));
end $$;
revoke execute on function public.nvl_catalog_upsert(text, text, text, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.nvl_catalog_upsert(text, text, text, text, text, text, text, text, text) to authenticated;

notify pgrst, 'reload schema';
