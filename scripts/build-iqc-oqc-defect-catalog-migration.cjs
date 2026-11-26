/* Generate the additive staging migration from the currently deployed IQC save functions. */
const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..');
const source=fs.readFileSync(path.join(root,'supabase','migration_iqc_compact_times_staging.sql'),'utf8');
const base=source.replace(/^--[^\n]*\r?\n/,'').replace(/^begin;\r?\n/,'').replace(/\r?\ncommit;\s*$/,'');
const columns='iqc_lan_kiem_loi(lan_kiem_id,ma_loi,ten_loi,nhom_loi,chi_tiet,so_luong)';
const values='values(%ID%,nullif(trim(coalesce(x->>\'ma_loi\',x->>\'code\')),\'\'),trim(x->>\'ten_loi\'),nullif(trim(x->>\'nhom_loi\'),\'\'),nullif(trim(x->>\'chi_tiet\'),\'\'),(x->>\'so_luong\')::bigint);';
let sql=base.replaceAll('iqc_lan_kiem_loi(lan_kiem_id,ten_loi,nhom_loi,chi_tiet,so_luong)',columns)
  .replace('values(r.id,trim(x->>\'ten_loi\'),nullif(trim(x->>\'nhom_loi\'),\'\'),nullif(trim(x->>\'chi_tiet\'),\'\'),(x->>\'so_luong\')::bigint);',values.replace('%ID%','r.id'))
  .replace('values(p_id,trim(x->>\'ten_loi\'),nullif(trim(x->>\'nhom_loi\'),\'\'),nullif(trim(x->>\'chi_tiet\'),\'\'),(x->>\'so_luong\')::bigint);',values.replace('%ID%','p_id'));
if(sql===base||!sql.includes('ma_loi'))throw Error('Không tạo được migration ma_loi từ hàm IQC hiện tại.');
sql=`-- STAGING only. Adds an immutable catalog-code snapshot to each new IQC round defect.\nbegin;\nalter table public.iqc_lan_kiem_loi add column if not exists ma_loi text;\ncreate index if not exists iqc_lan_kiem_loi_ma_loi_idx on public.iqc_lan_kiem_loi(ma_loi);\n\n${sql}\ncommit;\n`;
fs.writeFileSync(path.join(root,'supabase','migration_iqc_oqc_defect_catalog_staging.sql'),sql);
