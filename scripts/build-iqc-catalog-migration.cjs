// Build the migration from the deployed T232 function definitions, changing only
// their classification source. Run from the repository root.
const fs = require('node:fs');
const source = fs.readFileSync('supabase/migration_phase_T232_iqc_nvl_hoa_hoc.sql', 'utf8');
function definition(name) {
  const start = source.indexOf(`create or replace function public.${name}(`);
  const end = source.indexOf('\nend $$;', start);
  if (start < 0 || end < 0) throw Error(`Missing function ${name}`);
  return source.slice(start, end + '\nend $$;'.length);
}
let sql = `-- IQC lấy phân loại Nhôm/Kẽm + mác vật liệu từ danh mục NVL (nvl_materials + vat_lieu_mac). Đã chạy staging + prod 20/11/2026.
begin;
create or replace function public.iqc_phan_loai_tu_danh_muc(p_ma_nvl text)
returns public.iqc_nvl_phan_loai language sql stable security definer set search_path=public as $$
 select n.ma_nvl,
   case when n.nhom_vat_tu <> 'kim_loai' then 'khac' else coalesce(m.loai_kim_loai,'khac') end,
   n.ma_mac, now(), null::uuid
 from nvl_materials n left join vat_lieu_mac m on m.ma_mac=n.ma_mac
 where n.ma_nvl=p_ma_nvl;
$$;
revoke all on function public.iqc_phan_loai_tu_danh_muc(text) from public,anon;
grant execute on function public.iqc_phan_loai_tu_danh_muc(text) to authenticated;

create or replace function public.iqc_nvl_danh_muc() returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object(
 'san_pham',coalesce((select jsonb_agg(jsonb_build_object('code',ma_sp,'name',ten_sp) order by ma_sp) from master_products),'[]'),
 'nvl',coalesce((select jsonb_agg(jsonb_build_object('code',n.ma_nvl,'name',n.ten_nvl,'supplier',n.nha_cung_cap,'supplierCode',n.ma_nvl_ncc,'group',c.nhom,'grade',c.mac_vat_lieu) order by n.ma_nvl)
 from nvl_materials n left join lateral iqc_phan_loai_tu_danh_muc(n.ma_nvl) c on true),'[]')) where auth.uid() is not null;
$$;

create or replace function public.iqc_tc_hoa_hoc(p_ma_nvl text,p_ngay date) returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('phan_loai',to_jsonb(c),'tieu_chuan',to_jsonb(b),
 'nguyen_to',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('bat_buoc',coalesce((m.nguon_nhan_dien->>'bat_buoc')::boolean,true)) order by muc_no) from ipqc_btk_muc m where m.id_btk=b.id),'[]'))
 from iqc_phan_loai_tu_danh_muc(p_ma_nvl) c left join lateral(
 select * from ipqc_btk v where v.cong_doan='iqc_hoa_hoc' and v.ma_nvl=c.ma_nvl and v.mac_vat_lieu=c.mac_vat_lieu and v.nhom_vat_lieu=c.nhom
 and v.trang_thai='da_duyet' and v.ngay_hieu_luc<=p_ngay order by v.ngay_hieu_luc desc,v.phe_duyet_luc desc,v.id desc limit 1
 ) b on true where auth.uid() is not null;
$$;
`;
for (const name of ['iqc_nvl_guard', 'iqc_tc_luu_hoa_hoc', 'iqc_luu_hoa_hoc']) {
  let fn = definition(name);
  const before = fn;
  fn = fn.replace('from iqc_nvl_phan_loai where ma_nvl=new.ma_nvl', 'from iqc_phan_loai_tu_danh_muc(new.ma_nvl)');
  fn = fn.replace("from iqc_nvl_phan_loai where ma_nvl=p_data->>'ma_nvl'", "from iqc_phan_loai_tu_danh_muc(p_data->>'ma_nvl')");
  fn = fn.replace('from iqc_nvl_phan_loai where ma_nvl=n.ma_nvl', 'from iqc_phan_loai_tu_danh_muc(n.ma_nvl)');
  if (fn === before) throw Error(`Classification substitution failed: ${name}`);
  sql += '\n' + fn + '\n';
}
let lotGuard = definition('iqc_kiem_tra_thong_tin_lot');
const supplierRule = "new.supplier not in('BRV','HANIN','VIỆT PHÁP','ASAHI','MINGANN')";
if (!lotGuard.includes(supplierRule)) throw Error('Missing supplier validation');
lotGuard = lotGuard.replace(supplierRule, "(new.supplier not in('BRV','HANIN','VIỆT PHÁP','ASAHI','MINGANN') and not (new.doi_tuong='nvl' and exists(select 1 from nvl_materials n where n.ma_nvl=new.ma_nvl and n.nha_cung_cap=new.supplier)))");
sql += '\n' + lotGuard + '\n';
sql += `
-- The obsolete IQC classification editor cannot write a conflicting source.
revoke execute on function public.iqc_nvl_luu_phan_loai(text,text,text) from authenticated;
notify pgrst,'reload schema';
commit;
`;
fs.writeFileSync('supabase/migration_iqc_catalog_source.sql', sql);
