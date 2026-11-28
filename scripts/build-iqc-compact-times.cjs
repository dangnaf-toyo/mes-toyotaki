const fs=require('fs');const src=fs.readFileSync('supabase/migration_iqc_progressive.sql','utf8').replace(/\r\n/g,'\n');
function fn(name){let i=src.indexOf(`create or replace function public.${name}(`),j=src.indexOf('\nend $$;',i);if(i<0||j<0)throw Error(name);return src.slice(i,j+8)}
function rep(s,a,b){if(!s.includes(a))throw Error('missing '+a);return s.replace(a,b)}
let save=fn('iqc_luu_lan_kiem');save=rep(save,'draft iqc_lan_kiem_nhap%rowtype;', 'draft iqc_lan_kiem_nhap%rowtype; start_at timestamptz; end_at timestamptz; target bigint;');
const old=` insert into iqc_lan_kiem(lot_id,ngay_kiem,nguoi_kiem,so_kiem,so_ok,so_ng,nguoi_tao,bat_dau_luc,ket_thuc_luc)
 values(l.id,(draft.bat_dau_luc at time zone 'Asia/Ho_Chi_Minh')::date,trim(p_lan->>'nguoi_kiem'),checked,ok,ng,auth.uid(),draft.bat_dau_luc,clock_timestamp()) returning * into r;`;
const repl=` start_at:=coalesce(nullif(p_lan->>'bat_dau_luc','')::timestamptz,draft.bat_dau_luc);
 end_at:=coalesce(nullif(p_lan->>'ket_thuc_luc','')::timestamptz,clock_timestamp());
 if start_at>end_at or end_at>clock_timestamp() then raise exception 'Thời gian không hợp lệ'; end if;
 if nullif(p_lan->>'ket_thuc_luc','') is not null then
  if l.inspection_type='Kiểm tra AQL' then select mau_yeu_cau into target from iqc_aql_ke_hoach where lot_id=l.id; else target:=l.lot_qty; end if;
  if target is null or already+checked<target then raise exception 'LOT chưa đủ số lượng để ghi giờ hoàn thành'; end if;
  if exists(select 1 from iqc_lan_kiem where lot_id=l.id and bat_dau_luc>end_at) then raise exception 'Giờ hoàn thành trước lần kiểm trước đó'; end if;
 end if;
 insert into iqc_lan_kiem(lot_id,ngay_kiem,nguoi_kiem,so_kiem,so_ok,so_ng,nguoi_tao,bat_dau_luc,ket_thuc_luc)
 values(l.id,(start_at at time zone 'Asia/Ho_Chi_Minh')::date,trim(p_lan->>'nguoi_kiem'),checked,ok,ng,auth.uid(),start_at,end_at) returning * into r;`;
save=rep(save,old,repl);
let edit=fn('iqc_sua_lan_kiem');edit=rep(edit,'other_checked bigint;', 'other_checked bigint; start_at timestamptz; end_at timestamptz; target bigint;');
const oldEdit=" update iqc_lan_kiem set ngay_kiem=oldrow.ngay_kiem,nguoi_kiem=trim(p_lan->>'nguoi_kiem'),so_kiem=checked,so_ok=ok,so_ng=ng,sua_luc=clock_timestamp() where id=p_id returning * into newrow;";
const newEdit=` start_at:=coalesce(nullif(p_lan->>'bat_dau_luc','')::timestamptz,oldrow.bat_dau_luc);end_at:=coalesce(nullif(p_lan->>'ket_thuc_luc','')::timestamptz,oldrow.ket_thuc_luc);
 if (start_at is distinct from oldrow.bat_dau_luc or end_at is distinct from oldrow.ket_thuc_luc) and (not has_role('admin','qc_manager') or nullif(trim(p_lan->>'ly_do_thoi_gian'),'') is null) then raise exception 'Quản lý QC cần ghi lý do sửa thời gian'; end if;
 if nullif(p_lan->>'ket_thuc_luc','') is not null then
  if l.inspection_type='Kiểm tra AQL' then select mau_yeu_cau into target from iqc_aql_ke_hoach where lot_id=l.id; else target:=l.lot_qty; end if;
  if target is null or other_checked+checked<target then raise exception 'LOT chưa đủ số lượng để ghi giờ hoàn thành'; end if;
  if exists(select 1 from iqc_lan_kiem where lot_id=l.id and id<>p_id and bat_dau_luc>end_at) then raise exception 'Giờ hoàn thành trước lần kiểm trước đó'; end if;
 end if;
 if start_at is not null and end_at is not null and (start_at>end_at or end_at>clock_timestamp()) then raise exception 'Thời gian không hợp lệ'; end if;
 update iqc_lan_kiem set ngay_kiem=case when start_at is distinct from oldrow.bat_dau_luc then (start_at at time zone 'Asia/Ho_Chi_Minh')::date else oldrow.ngay_kiem end,bat_dau_luc=start_at,ket_thuc_luc=end_at,nguoi_kiem=trim(p_lan->>'nguoi_kiem'),so_kiem=checked,so_ok=ok,so_ng=ng,sua_luc=clock_timestamp() where id=p_id returning * into newrow;`;
edit=rep(edit,oldEdit,newEdit);
edit=rep(edit,"to_jsonb(newrow)||jsonb_build_object('loi',p_lan->'loi')","to_jsonb(newrow)||jsonb_build_object('loi',p_lan->'loi','ly_do_thoi_gian',p_lan->>'ly_do_thoi_gian')");
fs.writeFileSync('supabase/migration_iqc_compact_times.sql',`-- STAGING ONLY. Does not update historical LOT or inspection rows.\nbegin;\n${save}\n\n${edit}\nnotify pgrst,'reload schema';\ncommit;\n`);
