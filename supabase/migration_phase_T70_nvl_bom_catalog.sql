-- Share the managed NVL catalog with BOM and inventory across browsers/devices.
-- Run in Supabase SQL Editor for each environment.

alter table public.nvl_materials
  add column if not exists nha_cung_cap text,
  add column if not exists ma_nvl_ncc text,
  add column if not exists khach_hang text,
  add column if not exists san_pham text;

-- Preserve the catalog entries previously seeded in quan-ly-danh-muc.html.
insert into public.nvl_materials
  (ma_nvl, ten_nvl, nha_cung_cap, ma_nvl_ncc, khach_hang, san_pham)
values
  ('K-NHN-12-001', 'Nhôm', 'Daikin', 'HD2- ADC12', 'FCC', 'K09,HPH,KFM,Pressure'),
  ('K-NHN-12-002', 'Nhôm', 'Chiến thắng', 'ADC 12', 'Exedy,Ghế okaya,TTI', 'Center/plat/pply/ outer'),
  ('K-NHN-12-003', 'Nhôm', 'Tân Quang', 'ADC 12', 'Khác', '9001/9002/8001/8002....'),
  ('K-NHN-S1-001', 'Nhôm', 'Honda trading', 'HD2- BS1', 'ASTEMO, Fomeco', 'Fr'),
  ('K-NHN-12-004', 'Nhôm', 'Nhôm thái lan', 'ADC 12', 'Exedy', 'Center/plat/pply/ outer'),
  ('K-NHN-06-001', 'Nhôm', 'Honda trading', 'ADC 6', 'Iwatani', '118,119'),
  ('K-KEN-A3-001', 'Kẽm', 'Honda trading', 'EZDA3', 'Exedy', '3B54,53,69'),
  ('K-KEN-A3-002', 'Kẽm', 'Metal', 'EZDA3-Metal', 'Bảo Phương', '3B54,53,69'),
  ('C-PIN-39-001', 'Pin Brake', 'Astemo', '008-D39-117', 'Astemo', 'Fr'),
  ('C-BAC-19-001', 'Sleev Brake', 'Astemo', '008-D19-126', 'Astemo', 'Fr'),
  ('C-ONN-OS-001', 'Ống nhôm phía ngoài S', 'Việt pháp', '27L024 - 002P01', 'Ghế okaya', 'Ghế okaya'),
  ('C-ONN-OL-001', 'Ống nhôm phía ngoài L', 'Việt pháp', '27L025 - 001P01', 'Ghế okaya', 'Ghế okaya'),
  ('C-ONN-LL-001', 'Ống nhôm phía ngoài LL', 'Việt pháp', '27L026 - 001P01', 'Ghế okaya', 'Ghế okaya'),
  ('C-ONN-SS-001', 'Ống nhôm phía ngoài SS', 'Việt pháp', '27L031 - 003P01', 'Ghế okaya', 'Ghế okaya'),
  ('C-ONN-OS-002', 'Ống nhôm phía ngoài S (Không đục lỗ)', 'Việt pháp', '27L024 - 002P01A', 'Ghế okaya', 'Nòng khuôn'),
  ('C-ONN-OL-002', 'Ống nhôm phía ngoài L (Không đục lỗ)', 'Việt pháp', '27L025 - 001P01A', 'Ghế okaya', 'Nòng khuôn'),
  ('C-ONN-LL-002', 'Ống nhôm phía ngoài LL (Không đục lỗ)', 'Việt pháp', '27L026 - 001P01A', 'Ghế okaya', 'Nòng khuôn'),
  ('C-ONN-SS-002', 'Ống nhôm phía ngoài SS (Không đục lỗ)', 'Việt pháp', '27L031 - 002P01A', 'Ghế okaya', 'Nòng khuôn'),
  ('C-ONT-OS-001', 'Ống nhôm phía Trong S', 'Việt pháp', '0395049-249', 'Ghế okaya', 'Ghế okaya'),
  ('C-ONT-OL-001', 'Ống nhôm phía Trong L', 'Việt pháp', '0395049-250', 'Ghế okaya', 'Ghế okaya'),
  ('C-ONT-LL-001', 'Ống nhôm phía Trong LL', 'Việt pháp', '0395049-251', 'Ghế okaya', 'Ghế okaya'),
  ('C-CKL-29-001', 'Chốt kim loại', 'BRT/Ming ann', '0395049-229', 'Ghế okaya', 'Xuất khẩu'),
  ('S-BOT-TR-002', 'Sơn bột tĩnh điện', 'Thời Đại', 'EA212-80', 'Ghế okaya', 'Ghế okaya'),
  ('S-BOT-TR-001', 'Sơn bột tĩnh điện', 'Thời Đại', 'EA11129', 'SVP', 'Lock, Bản lề, đinh vít'),
  ('S-BOT-CA-001', 'Sơn bột tĩnh điện', 'Thời Đại', 'ME010V', 'Iwatani', '114')
on conflict (ma_nvl) do update set
  ten_nvl = coalesce(nullif(public.nvl_materials.ten_nvl, ''), excluded.ten_nvl),
  nha_cung_cap = coalesce(public.nvl_materials.nha_cung_cap, excluded.nha_cung_cap),
  ma_nvl_ncc = coalesce(public.nvl_materials.ma_nvl_ncc, excluded.ma_nvl_ncc),
  khach_hang = coalesce(public.nvl_materials.khach_hang, excluded.khach_hang),
  san_pham = coalesce(public.nvl_materials.san_pham, excluded.san_pham);

create or replace function public.nvl_catalog_upsert(
  p_ma_nvl text,
  p_ten_nvl text,
  p_nha_cung_cap text,
  p_ma_nvl_ncc text,
  p_khach_hang text,
  p_san_pham text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.has_role('admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Admin được cập nhật danh mục NVL');
  end if;
  if nullif(trim(p_ma_nvl), '') is null then
    return jsonb_build_object('ok', false, 'error', 'Thiếu mã NVL Toyotaki');
  end if;

  insert into public.nvl_materials
    (ma_nvl, ten_nvl, nha_cung_cap, ma_nvl_ncc, khach_hang, san_pham)
  values
    (trim(p_ma_nvl), coalesce(nullif(trim(p_ten_nvl), ''), trim(p_ma_nvl)),
     nullif(trim(p_nha_cung_cap), ''), nullif(trim(p_ma_nvl_ncc), ''),
     nullif(trim(p_khach_hang), ''), nullif(trim(p_san_pham), ''))
  on conflict (ma_nvl) do update set
    ten_nvl = excluded.ten_nvl,
    nha_cung_cap = excluded.nha_cung_cap,
    ma_nvl_ncc = excluded.ma_nvl_ncc,
    khach_hang = excluded.khach_hang,
    san_pham = excluded.san_pham;
  return jsonb_build_object('ok', true, 'ma_nvl', trim(p_ma_nvl));
end;
$$;

create or replace function public.nvl_catalog_delete(p_ma_nvl text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.has_role('admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Admin được xóa danh mục NVL');
  end if;
  delete from public.nvl_materials where ma_nvl = p_ma_nvl;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy mã NVL');
  end if;
  return jsonb_build_object('ok', true, 'ma_nvl', p_ma_nvl);
end;
$$;

revoke execute on function public.nvl_catalog_upsert(text, text, text, text, text, text) from public, anon;
grant execute on function public.nvl_catalog_upsert(text, text, text, text, text, text) to authenticated;
revoke execute on function public.nvl_catalog_delete(text) from public, anon;
grant execute on function public.nvl_catalog_delete(text) to authenticated;