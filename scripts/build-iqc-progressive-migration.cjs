// Derive the few replacement functions from the deployed IQC migration.
const fs = require('node:fs');
const src = fs.readFileSync('supabase/migration_iqc_multiday.sql','utf8').replace(/\r\n/g,'\n');
function fn(name){const i=src.indexOf(`create or replace function public.${name}(`);const j=src.indexOf('\nend $$;',i);if(i<0||j<0)throw Error('Missing '+name);return src.slice(i,j+8);}
function replaceOnce(s,a,b){if(!s.includes(a))throw Error('Missing source: '+a);return s.replace(a,b);}
let sql=`-- Staging only. Existing LOTs and inspection history remain unchanged.
begin;
alter table public.iqc_lan_kiem add column bat_dau_luc timestamptz, add column ket_thuc_luc timestamptz;
alter table public.iqc_lots add column iqc_khoi_luong_hoa_hoc numeric, add column iqc_don_vi_hoa_hoc text;
create table public.iqc_lan_kiem_nhap (
 id uuid primary key, lot_id bigint references public.iqc_lots(id), nguoi_uid uuid not null,
 bat_dau_luc timestamptz not null default clock_timestamp(), lan_kiem_id bigint references public.iqc_lan_kiem(id)
);
create table public.iqc_aql_ke_hoach (
 lot_id bigint primary key references public.iqc_lots(id), mau_yeu_cau bigint not null check(mau_yeu_cau>0),
 ac bigint not null check(ac>=0), re bigint not null check(re>ac), nguon text not null check(length(trim(nguon))>0),
 cap_do text not null default 'II', aql text not null default '1.0', nguoi_duyet uuid not null, duyet_luc timestamptz not null default clock_timestamp()
);
alter table public.iqc_aql_ke_hoach enable row level security;
revoke all on public.iqc_aql_ke_hoach from public,anon,authenticated;
grant select on public.iqc_aql_ke_hoach to authenticated;
create policy iqc_aql_ke_hoach_doc on public.iqc_aql_ke_hoach for select to authenticated using(true);
alter table public.iqc_lan_kiem_nhap enable row level security;
revoke all on public.iqc_lan_kiem_nhap from public,anon,authenticated;
create or replace function public.iqc_bat_dau_lan_kiem(p_id uuid,p_lot_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d iqc_lan_kiem_nhap%rowtype; l iqc_lots%rowtype;
begin
 if auth.uid() is null or not has_role('admin','qc_manager','iqc') then raise exception 'Không có quyền bắt đầu kiểm'; end if;
 if p_id is null then raise exception 'Thiếu mã lần kiểm'; end if;
 perform pg_advisory_xact_lock(hashtextextended('iqc-draft:'||p_id,0));
 select * into d from iqc_lan_kiem_nhap where id=p_id;
 if found then
  if d.nguoi_uid<>auth.uid() or d.lot_id is distinct from p_lot_id or d.lan_kiem_id is not null then raise exception 'Lần kiểm không còn khả dụng'; end if;
  return jsonb_build_object('id',d.id,'bat_dau_luc',d.bat_dau_luc);
 end if;
 if p_lot_id is not null then
  select * into l from iqc_lots where id=p_lot_id;
  if not found or l.da_luu_tru or l.phuong_thuc<>'ngoai_quan' or l.iqc_tam_dung then raise exception 'LOT không thể bắt đầu kiểm'; end if;
 end if;
 insert into iqc_lan_kiem_nhap(id,lot_id,nguoi_uid) values(p_id,p_lot_id,auth.uid()) returning * into d;
 return jsonb_build_object('id',d.id,'bat_dau_luc',d.bat_dau_luc);
end $$;
revoke all on function public.iqc_bat_dau_lan_kiem(uuid,bigint) from public,anon;
grant execute on function public.iqc_bat_dau_lan_kiem(uuid,bigint) to authenticated;

create or replace function public.iqc_tranh_trung_lot_hoa_hoc() returns trigger language plpgsql set search_path=public as $$
begin
 if new.phuong_thuc='hoa_hoc' and not new.da_luu_tru and nullif(trim(new.lot_no),'') is not null and nullif(trim(new.product_code),'') is not null and nullif(trim(coalesce(new.supplier,'')),'') is not null then
  if tg_op='UPDATE' and new.lot_no is not distinct from old.lot_no and new.product_code is not distinct from old.product_code and new.supplier is not distinct from old.supplier and new.da_luu_tru is not distinct from old.da_luu_tru and new.phuong_thuc is not distinct from old.phuong_thuc then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('iqc-chem-lot:'||lower(trim(new.supplier))||':'||lower(trim(new.product_code))||':'||lower(trim(new.lot_no)),0));
  if exists(select 1 from iqc_lots x where x.id is distinct from new.id and x.phuong_thuc='hoa_hoc' and not x.da_luu_tru and lower(trim(coalesce(x.supplier,'')))=lower(trim(new.supplier)) and lower(trim(x.product_code))=lower(trim(new.product_code)) and lower(trim(x.lot_no))=lower(trim(new.lot_no))) then raise exception 'LOT hóa học đã tồn tại; mở LOT cũ để phân tích'; end if;
 end if;
 return new;
end $$;
revoke all on function public.iqc_tranh_trung_lot_hoa_hoc() from public,anon,authenticated;
create trigger iqc_tranh_trung_lot_hoa_hoc before insert or update on public.iqc_lots for each row execute function public.iqc_tranh_trung_lot_hoa_hoc();

create or replace function public.iqc_dang_ky_lot_hoa_hoc(p_request_id uuid,p_ma_nvl text,p_lot_no text,p_supplier text,p_so_luong numeric,p_don_vi text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare n nvl_materials%rowtype; c iqc_nvl_phan_loai%rowtype; existing iqc_yeu_cau_luu%rowtype; v_id bigint;
 body jsonb:=jsonb_build_object('loai','dang_ky_hoa_hoc','ma_nvl',p_ma_nvl,'lot_no',p_lot_no,'supplier',p_supplier,'so_luong',p_so_luong,'don_vi',p_don_vi);
begin
 if auth.uid() is null or not has_role('admin','qc_manager','iqc') then raise exception 'Chỉ IQC hoặc quản lý QC được đăng ký LOT'; end if;
 if p_request_id is null then raise exception 'Thiếu mã yêu cầu'; end if;
 perform pg_advisory_xact_lock(hashtextextended('iqc-report:'||p_request_id,0));
 select * into existing from iqc_yeu_cau_luu where request_id=p_request_id;
 if found then
  if existing.nguoi_uid<>auth.uid() or existing.du_lieu<>body then raise exception 'Yêu cầu đã dùng với dữ liệu khác'; end if;
  return jsonb_build_object('id',existing.id_lot,'existing',true);
 end if;
 select * into n from nvl_materials where ma_nvl=trim(p_ma_nvl);
 select * into c from iqc_phan_loai_tu_danh_muc(n.ma_nvl);
 if n.ma_nvl is null or c.nhom is null or c.nhom not in('nhom','kem') or nullif(trim(p_lot_no),'') is null or nullif(trim(p_supplier),'') is null or p_so_luong is null or p_so_luong::text in ('NaN','Infinity','-Infinity') or p_so_luong<=0 or nullif(trim(p_don_vi),'') is null then raise exception 'Nhập mã Nhôm/Kẽm, LOT, nhà cung cấp, số lượng và đơn vị'; end if;
 perform pg_advisory_xact_lock(hashtextextended('iqc-chem-lot:'||lower(trim(p_supplier))||':'||lower(trim(p_ma_nvl))||':'||lower(trim(p_lot_no)),0));
 if exists(select 1 from iqc_lots where phuong_thuc='hoa_hoc' and not da_luu_tru and lower(trim(coalesce(supplier,'')))=lower(trim(p_supplier)) and lower(trim(product_code))=lower(trim(p_ma_nvl)) and lower(trim(lot_no))=lower(trim(p_lot_no))) then raise exception 'LOT hóa học đã tồn tại; mở LOT cũ để phân tích'; end if;
 insert into iqc_lots(doi_tuong,ma_nvl,phuong_thuc,nhom_vat_lieu,mac_vat_lieu,nguoi_tao_uid,request_id,received_at,supplier,product_code,product_name,lot_no,lot_qty,inspection_type,sample_qty,ok_qty,ng_qty,ok_pct,ng_pct,pham_vi,status,result,iqc_khoi_luong_hoa_hoc,iqc_don_vi_hoa_hoc)
 values('nvl',n.ma_nvl,'hoa_hoc',c.nhom,c.mac_vat_lieu,auth.uid(),p_request_id,clock_timestamp(),trim(p_supplier),n.ma_nvl,n.ten_nvl,trim(p_lot_no),0,'Kiểm tra thành phần hóa học',0,0,0,0,0,'Nguyên vật liệu','Chưa lấy hàng','',p_so_luong,trim(p_don_vi)) returning id into v_id;
 insert into iqc_yeu_cau_luu values(p_request_id,auth.uid(),v_id,body);
 insert into iqc_lich_su(loai,khoa,du_lieu_moi,nguoi_uid,nguoi) values('dang_ky_lot_hoa_hoc',v_id::text,(select to_jsonb(l) from iqc_lots l where id=v_id),auth.uid(),duc_ten_nguoi_hien_tai());
 return jsonb_build_object('id',v_id);
end $$;
revoke all on function public.iqc_dang_ky_lot_hoa_hoc(uuid,text,text,text,numeric,text) from public,anon;
grant execute on function public.iqc_dang_ky_lot_hoa_hoc(uuid,text,text,text,numeric,text) to authenticated;
`;
let save=fn('iqc_luu_lan_kiem');
save=replaceOnce(save,'checked bigint; ok bigint; ng bigint; already bigint; answer jsonb; v_lot_id bigint;','checked bigint; ok bigint; ng bigint; already bigint; answer jsonb; v_lot_id bigint; draft iqc_lan_kiem_nhap%rowtype;');
save=replaceOnce(save," or nullif(p_lan->>'ngay_kiem','') is null",'');
save=replaceOnce(save," or nullif(p_lot->>'received_at','') is null",'');
save=replaceOnce(save,"values ((p_lot->>'received_at')::timestamptz,trim(p_lot->>'supplier')","values (clock_timestamp(),trim(p_lot->>'supplier')");
save=replaceOnce(save,'phuong_thuc,inspection_type,inspector,nguoi_kiem_id','phuong_thuc,inspection_type,aql,inspector,nguoi_kiem_id');
save=replaceOnce(save,"coalesce(nullif(p_lot->>'inspection_type',''),'Kiểm tra 100%'),trim(coalesce(p_lan->>'nguoi_kiem'","coalesce(nullif(p_lot->>'inspection_type',''),'Kiểm tra 100%'),case when p_lot->>'inspection_type'='Kiểm tra AQL' then nullif(trim(p_lot->>'aql'),'') else null end,trim(coalesce(p_lan->>'nguoi_kiem'");
save=replaceOnce(save,"insert into iqc_lan_kiem(lot_id,ngay_kiem,nguoi_kiem,so_kiem,so_ok,so_ng,nguoi_tao)\n values(l.id,(p_lan->>'ngay_kiem')::date,trim(p_lan->>'nguoi_kiem'),checked,ok,ng,auth.uid()) returning * into r;",`select * into draft from iqc_lan_kiem_nhap where id=(p_lan->>'bat_dau_id')::uuid for update;
 if draft.id is null or draft.nguoi_uid<>auth.uid() or draft.lot_id is distinct from p_lot_id or draft.lan_kiem_id is not null then raise exception 'Lần kiểm chưa được bắt đầu hoặc đã hoàn thành'; end if;
 insert into iqc_lan_kiem(lot_id,ngay_kiem,nguoi_kiem,so_kiem,so_ok,so_ng,nguoi_tao,bat_dau_luc,ket_thuc_luc)
 values(l.id,(draft.bat_dau_luc at time zone 'Asia/Ho_Chi_Minh')::date,trim(p_lan->>'nguoi_kiem'),checked,ok,ng,auth.uid(),draft.bat_dau_luc,clock_timestamp()) returning * into r;
 update iqc_lan_kiem_nhap set lan_kiem_id=r.id where id=draft.id;`);
sql+='\n'+save+'\n';
let edit=fn('iqc_sua_lan_kiem');
edit=replaceOnce(edit," or nullif(p_lan->>'ngay_kiem','') is null",'');
edit=replaceOnce(edit,"set ngay_kiem=(p_lan->>'ngay_kiem')::date,nguoi_kiem=","set ngay_kiem=oldrow.ngay_kiem,nguoi_kiem=");
sql+='\n'+edit+'\n';
let editLot=fn('iqc_sua_thong_tin_lot');
editLot=replaceOnce(editLot," or nullif(p_lot->>'received_at','') is null",'');
editLot=replaceOnce(editLot,"set received_at=(p_lot->>'received_at')::timestamptz,lot_qty=v_qty","set received_at=before_row.received_at,lot_qty=v_qty");
editLot=replaceOnce(editLot,"if nullif(trim(p_lot->>'supplier'),'') is null then", "if exists(select 1 from iqc_aql_ke_hoach where lot_id=p_id and mau_yeu_cau>v_qty) then raise exception 'Số LOT nhỏ hơn cỡ mẫu AQL đã duyệt'; end if;\n if nullif(trim(p_lot->>'supplier'),'') is null then");
sql+='\n'+editLot+'\n';
let guard=fn('iqc_bao_ve_tong_lan_kiem');
guard=replaceOnce(guard,'new.sample_qty is distinct from old.sample_qty',"(new.sample_qty is distinct from old.sample_qty and (current_setting('iqc.aql_plan',true) is distinct from old.id::text or current_user <> pg_get_userbyid((select proowner from pg_proc where oid='public.iqc_duyet_ke_hoach_aql(bigint,bigint,bigint,bigint,text,timestamptz)'::regprocedure))))");
sql+='\n'+guard+'\n';
let totals=fn('iqc_tinh_tong_lot');
totals=replaceOnce(totals,"q_result:=case when ngs>0 or legacy_ng then 'NG' else coalesce(l.iqc_ket_luan,'') end;","q_result:=coalesce(l.iqc_ket_luan,case when legacy_ng then 'NG' else '' end);");
sql+='\n'+totals+'\n';
sql+=`
-- Historical time corrections are explicitly authorised and audited.
create or replace function public.iqc_sua_thoi_gian_lan_kiem(p_id bigint,p_bat_dau timestamptz,p_ket_thuc timestamptz,p_sua_luc timestamptz,p_ly_do text)
returns void language plpgsql security definer set search_path=public as $$
declare oldrow iqc_lan_kiem%rowtype; newrow iqc_lan_kiem%rowtype; l iqc_lots%rowtype;
begin
 if auth.uid() is null or not has_role('admin','qc_manager') then raise exception 'Chỉ quản lý QC được sửa thời gian'; end if;
 if p_bat_dau is null or p_ket_thuc is null or p_bat_dau>p_ket_thuc or p_ket_thuc>clock_timestamp() or nullif(trim(p_ly_do),'') is null then raise exception 'Thời gian hoặc lý do không hợp lệ'; end if;
 select * into oldrow from iqc_lan_kiem where id=p_id;
 if not found then raise exception 'Không tìm thấy lần kiểm'; end if;
 select * into l from iqc_lots where id=oldrow.lot_id for update;
 select * into oldrow from iqc_lan_kiem where id=p_id for update;
 if l.da_luu_tru or oldrow.loai='so_du_cu' or oldrow.sua_luc is distinct from p_sua_luc then raise exception 'Lần kiểm không thể sửa hoặc đã thay đổi'; end if;
 update iqc_lan_kiem set bat_dau_luc=p_bat_dau,ket_thuc_luc=p_ket_thuc,ngay_kiem=(p_bat_dau at time zone 'Asia/Ho_Chi_Minh')::date,sua_luc=clock_timestamp() where id=p_id returning * into newrow;
 insert into iqc_lich_su(loai,khoa,du_lieu_cu,du_lieu_moi,nguoi_uid,nguoi) values('sua_thoi_gian_lan_kiem',p_id::text,to_jsonb(oldrow),to_jsonb(newrow)||jsonb_build_object('ly_do',p_ly_do),auth.uid(),duc_ten_nguoi_hien_tai());
end $$;
revoke all on function public.iqc_sua_thoi_gian_lan_kiem(bigint,timestamptz,timestamptz,timestamptz,text) from public,anon;
grant execute on function public.iqc_sua_thoi_gian_lan_kiem(bigint,timestamptz,timestamptz,timestamptz,text) to authenticated;

-- Require a recorded management decision. AQL needs an approved Ac/Re plan.
revoke execute on function public.iqc_danh_gia_lot(bigint,text,timestamptz) from authenticated;
create or replace function public.iqc_phan_quyet_lot(p_id bigint,p_ket_luan text,p_updated_at timestamptz,p_ly_do text)
returns void language plpgsql security definer set search_path=public as $$
declare l iqc_lots%rowtype; checked bigint; ng bigint; plan iqc_aql_ke_hoach%rowtype;
begin
 if auth.uid() is null or not has_role('admin','qc_manager') then raise exception 'Chỉ quản lý QC được kết luận LOT'; end if;
 if p_ket_luan is not null and p_ket_luan not in ('OK','NG') then raise exception 'Kết luận không hợp lệ'; end if;
 if nullif(trim(p_ly_do),'') is null then raise exception 'Nhập căn cứ kết luận'; end if;
 select * into l from iqc_lots where id=p_id for update;
 if not found or l.da_luu_tru or l.phuong_thuc<>'ngoai_quan' then raise exception 'Không tìm thấy LOT ngoại quan'; end if;
 if l.updated_at is distinct from p_updated_at then raise exception 'LOT đã thay đổi; tải lại trước khi kết luận'; end if;
 if p_ket_luan='OK' and l.iqc_tam_dung then raise exception 'LOT đang chờ xử lý; xử lý trước khi kết luận PASS'; end if;
 select coalesce(sum(so_kiem),0),coalesce(sum(so_ng),0) into checked,ng from iqc_lan_kiem where lot_id=p_id;
 if p_ket_luan='OK' and l.inspection_type='Kiểm tra AQL' then
  select * into plan from iqc_aql_ke_hoach where lot_id=p_id;
  if not found then raise exception 'Chưa có cỡ mẫu và Ac/Re AQL được phê duyệt cho LOT'; end if;
  if checked<>plan.mau_yeu_cau or ng>plan.ac then raise exception 'Số đã kiểm phải đúng cỡ mẫu và không vượt số chấp nhận AQL'; end if;
 elsif p_ket_luan='OK' and checked<>l.lot_qty then raise exception 'LOT kiểm toàn bộ chưa kiểm hết'; end if;
 perform set_config('iqc.quality_lot',p_id::text,true);
 update iqc_lots set iqc_ket_luan=p_ket_luan where id=p_id;
 perform set_config('iqc.quality_lot','',true);
 perform iqc_tinh_tong_lot(p_id);
 insert into iqc_lich_su(loai,khoa,du_lieu_cu,du_lieu_moi,nguoi_uid,nguoi) values('ket_luan_lot',p_id::text,jsonb_build_object('ket_luan',l.iqc_ket_luan),jsonb_build_object('ket_luan',p_ket_luan,'can_cu',p_ly_do),auth.uid(),duc_ten_nguoi_hien_tai());
end $$;
revoke all on function public.iqc_phan_quyet_lot(bigint,text,timestamptz,text) from public,anon;
grant execute on function public.iqc_phan_quyet_lot(bigint,text,timestamptz,text) to authenticated;

create or replace function public.iqc_duyet_ke_hoach_aql(p_id bigint,p_mau bigint,p_ac bigint,p_re bigint,p_nguon text,p_updated_at timestamptz)
returns void language plpgsql security definer set search_path=public as $$
declare l iqc_lots%rowtype; previous jsonb; after_plan jsonb; suggested jsonb;
begin
 if auth.uid() is null or not has_role('admin','qc_manager') then raise exception 'Chỉ quản lý QC được duyệt kế hoạch AQL'; end if;
 select * into l from iqc_lots where id=p_id for update;
 if not found or l.da_luu_tru or l.phuong_thuc<>'ngoai_quan' or l.inspection_type<>'Kiểm tra AQL' then raise exception 'Chọn LOT kiểm AQL'; end if;
 suggested:=iqc_tra_ke_hoach_aql(p_id);
 if suggested is null then raise exception 'Chưa có kế hoạch lấy mẫu'; end if;
 if l.aql is not null and l.aql<>suggested->>'aql' then raise exception 'AQL của LOT không khớp cấu hình đã duyệt'; end if;
 if p_mau is distinct from (suggested->>'mau_yeu_cau')::bigint or p_ac is distinct from (suggested->>'ac')::bigint or p_re is distinct from (suggested->>'re')::bigint then raise exception 'Kế hoạch khác cấu hình đã duyệt'; end if;
 if l.updated_at is distinct from p_updated_at then raise exception 'LOT đã thay đổi; tải lại'; end if;
 if p_mau is null or p_mau<1 or p_mau>l.lot_qty or p_ac is null or p_ac<0 or p_ac>=p_mau or p_re is null or p_re<>p_ac+1 or nullif(trim(p_nguon),'') is null then raise exception 'Cỡ mẫu, Ac/Re hoặc nguồn tiêu chuẩn không hợp lệ'; end if;
 select to_jsonb(x) into previous from iqc_aql_ke_hoach x where lot_id=p_id;
 insert into iqc_aql_ke_hoach(lot_id,mau_yeu_cau,ac,re,nguon,nguoi_duyet,cap_do,aql,phien_ban,ma_chu,cau_hinh_id) values(p_id,p_mau,p_ac,p_re,suggested->>'nguon',auth.uid(),suggested->>'cap_do',suggested->>'aql',suggested->>'phien_ban',suggested->>'ma_chu',(suggested->>'cau_hinh_id')::bigint)
 on conflict(lot_id) do update set mau_yeu_cau=excluded.mau_yeu_cau,ac=excluded.ac,re=excluded.re,nguon=excluded.nguon,cap_do=excluded.cap_do,aql=excluded.aql,phien_ban=excluded.phien_ban,ma_chu=excluded.ma_chu,cau_hinh_id=excluded.cau_hinh_id,nguoi_duyet=auth.uid(),duyet_luc=clock_timestamp()
 returning to_jsonb(iqc_aql_ke_hoach.*) into after_plan;
 if l.iqc_ket_luan is not null then
  perform set_config('iqc.quality_lot',p_id::text,true);update iqc_lots set iqc_ket_luan=null where id=p_id;perform set_config('iqc.quality_lot','',true);
 end if;
 perform set_config('iqc.aql_plan',p_id::text,true);
 update iqc_lots set sample_qty=p_mau where id=p_id;
 perform set_config('iqc.aql_plan','',true);
 perform iqc_tinh_tong_lot(p_id);
 insert into iqc_lich_su(loai,khoa,du_lieu_cu,du_lieu_moi,nguoi_uid,nguoi) values('duyet_ke_hoach_aql',p_id::text,previous,after_plan,auth.uid(),duc_ten_nguoi_hien_tai());
end $$;
revoke all on function public.iqc_duyet_ke_hoach_aql(bigint,bigint,bigint,bigint,text,timestamptz) from public,anon;
grant execute on function public.iqc_duyet_ke_hoach_aql(bigint,bigint,bigint,bigint,text,timestamptz) to authenticated;

-- Registration time is server-generated; historical received timestamps stay intact.
notify pgrst,'reload schema';
commit;
`;
sql=sql.replace('-- Require a recorded management decision.', () => fs.readFileSync('supabase/iqc_aql_configuration_fragment.sql','utf8').replace(/^\uFEFF/,'')+'\nalter table public.iqc_aql_ke_hoach add column phien_ban text, add column ma_chu text, add column cau_hinh_id bigint references public.iqc_aql_cau_hinh(id);\n-- Require a recorded management decision.');
fs.writeFileSync('supabase/migration_iqc_progressive.sql',sql);
