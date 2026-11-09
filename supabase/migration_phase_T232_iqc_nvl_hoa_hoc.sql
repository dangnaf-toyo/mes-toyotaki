-- IQC NVL / chemical analysis. Apply to STAGING only for this change; no production execution.
begin;

-- Classification references the existing BOM/inventory master; it is not a second material catalog.
create table public.iqc_nvl_phan_loai (
 ma_nvl text primary key references public.nvl_materials(ma_nvl),
 nhom text not null check(nhom in ('nhom','kem','khac')),
 mac_vat_lieu text,
 cap_nhat_luc timestamptz not null default clock_timestamp(),
 cap_nhat_boi uuid not null,
 check(nhom='khac' or nullif(trim(mac_vat_lieu),'') is not null)
);
create table public.iqc_lich_su (
 id bigint generated always as identity primary key,
 loai text not null,
 khoa text not null,
 du_lieu_cu jsonb,
 du_lieu_moi jsonb,
 nguoi_uid uuid,
 nguoi text,
 thoi_diem timestamptz not null default clock_timestamp()
);
alter table public.iqc_nvl_phan_loai enable row level security;
alter table public.iqc_lich_su enable row level security;
revoke all on public.iqc_nvl_phan_loai,public.iqc_lich_su from public,anon,authenticated;
grant select on public.iqc_nvl_phan_loai,public.iqc_lich_su to authenticated;
create policy iqc_phan_loai_doc on public.iqc_nvl_phan_loai for select to authenticated using(true);
create policy iqc_lich_su_doc on public.iqc_lich_su for select to authenticated using(has_role('admin','qc_manager','iqc','giam_doc_sx'));

alter table public.ipqc_btk add column ma_nvl text references public.nvl_materials(ma_nvl),add column mac_vat_lieu text,add column nhom_vat_lieu text;
alter table public.ipqc_btk drop constraint ipqc_btk_cong_doan_check;
alter table public.ipqc_btk add constraint ipqc_btk_cong_doan_check check(cong_doan in('duc','gia_cong','iqc_hoa_hoc'));
alter table public.ipqc_btk drop constraint ipqc_btk_trang_thai_check;
alter table public.ipqc_btk add constraint ipqc_btk_trang_thai_check check(trang_thai in('cho_kiem_tra','cho_phe_duyet','tra_lai','da_duyet') or (cong_doan in('gia_cong','iqc_hoa_hoc') and trang_thai='ban_nhap'));
alter table public.ipqc_btk add constraint iqc_tieu_chuan_nvl_check check(cong_doan<>'iqc_hoa_hoc' or
 (ma_nvl is not null and ma_sp=ma_nvl and nhom_vat_lieu in('nhom','kem') and nullif(trim(mac_vat_lieu),'') is not null));

create or replace function public.ipqc_cd_ten(p_cd text) returns text language sql immutable as $$
 select case p_cd when 'gia_cong' then 'Gia công' when 'iqc_hoa_hoc' then 'IQC thành phần hóa học' else 'Đúc' end;
$$;

alter table public.iqc_lots
 add column doi_tuong text not null default 'san_pham' check(doi_tuong in('san_pham','nvl')),
 add column ma_nvl text references public.nvl_materials(ma_nvl),
 add column phuong_thuc text not null default 'ngoai_quan' check(phuong_thuc in('ngoai_quan','hoa_hoc')),
 add column nhom_vat_lieu text,
 add column mac_vat_lieu text,
 add column ngay_kiem date,
 add column ca_kiem text,
 add column id_tieu_chuan bigint references public.ipqc_btk(id),
 add column hoa_hoc_json jsonb,
 add column nguoi_tao_uid uuid,
 add column da_luu_tru boolean not null default false,
 add column request_id uuid unique;
alter table public.iqc_lots add constraint iqc_nvl_identity_check check((doi_tuong='nvl')=(ma_nvl is not null));
alter table public.iqc_lots add constraint iqc_hoa_hoc_pcs_check check(phuong_thuc<>'hoa_hoc' or
 (doi_tuong='nvl' and coalesce(lot_qty,0)=0 and coalesce(sample_qty,0)=0 and coalesce(ok_qty,0)=0 and coalesce(ng_qty,0)=0));
create table public.iqc_yeu_cau_luu(request_id uuid primary key,nguoi_uid uuid not null,id_lot bigint not null references public.iqc_lots(id),du_lieu jsonb not null);
alter table public.iqc_yeu_cau_luu enable row level security;
revoke all on public.iqc_yeu_cau_luu from public,anon,authenticated;

-- Chemical writes must go through the validating RPC. Existing visual IQC policies are retained.
create policy iqc_hoa_hoc_insert_guard on public.iqc_lots as restrictive for insert to authenticated with check(phuong_thuc<>'hoa_hoc');
create policy iqc_hoa_hoc_update_guard on public.iqc_lots as restrictive for update to authenticated using(phuong_thuc<>'hoa_hoc') with check(phuong_thuc<>'hoa_hoc');
create policy iqc_hoa_hoc_delete_guard on public.iqc_lots as restrictive for delete to authenticated using(phuong_thuc<>'hoa_hoc');
create policy iqc_hoa_hoc_read_guard on public.iqc_lots as restrictive for select to public using(phuong_thuc<>'hoa_hoc' or auth.uid() is not null);
create policy iqc_hoa_hoc_defect_insert on public.iqc_defects as restrictive for insert to authenticated with check(
 exists(select 1 from public.iqc_lots l where l.id=lot_id and l.phuong_thuc<>'hoa_hoc'));
create policy iqc_hoa_hoc_defect_update on public.iqc_defects as restrictive for update to authenticated using(
 exists(select 1 from public.iqc_lots l where l.id=lot_id and l.phuong_thuc<>'hoa_hoc')) with check(
 exists(select 1 from public.iqc_lots l where l.id=lot_id and l.phuong_thuc<>'hoa_hoc'));

create or replace function public.iqc_nvl_guard() returns trigger language plpgsql set search_path=public as $$
declare n nvl_materials%rowtype;c iqc_nvl_phan_loai%rowtype;
begin
 if new.doi_tuong='nvl' then
  select * into n from nvl_materials where ma_nvl=new.ma_nvl;
  if not found or new.product_code is distinct from n.ma_nvl then raise exception 'Chọn đúng định danh NVL trong danh mục BOM';end if;
  select * into c from iqc_nvl_phan_loai where ma_nvl=new.ma_nvl;
  if new.phuong_thuc='ngoai_quan' and c.nhom is null and (tg_op='INSERT' or new.ma_nvl is distinct from old.ma_nvl) then
   raise exception 'Phân loại NVL tại Quản lý tiêu chuẩn trước khi lưu kiểm tra';end if;
  if new.phuong_thuc='ngoai_quan' and c.nhom in('nhom','kem') and
   (tg_op='INSERT' or new.ma_nvl is distinct from old.ma_nvl or new.phuong_thuc is distinct from old.phuong_thuc) then
   raise exception 'NVL Nhôm/Kẽm phải nhập kiểm tra thành phần hóa học';
  end if;
  new.product_name:=n.ten_nvl;
  if new.phuong_thuc='ngoai_quan' then new.nhom_vat_lieu:=c.nhom;new.mac_vat_lieu:=c.mac_vat_lieu;end if;
 end if;
 return new;
end $$;
revoke all on function public.iqc_nvl_guard() from public,anon,authenticated;
create trigger iqc_nvl_guard before insert or update on public.iqc_lots for each row execute function public.iqc_nvl_guard();

-- Preserve the old seven scopes / five suppliers for visual reports. Chemical reports use the BOM supplier.
create or replace function public.iqc_kiem_tra_thong_tin_lot() returns trigger language plpgsql set search_path=public as $$
begin
 if new.phuong_thuc='hoa_hoc' then
  if new.pham_vi is distinct from 'Nguyên vật liệu' then raise exception 'Phạm vi hóa học phải là Nguyên vật liệu';end if;
  return new;
 end if;
 if tg_op='INSERT' or new.pham_vi is distinct from old.pham_vi then
  if new.pham_vi is null or new.pham_vi not in('Bán thành phẩm','Linh kiện đầu vào','Mạ','In','Anode','Đúc','Thành phẩm') then
   raise exception 'Phạm vi IQC bắt buộc, phải thuộc danh sách 7 phạm vi';end if;
 end if;
 if tg_op='INSERT' or new.supplier is distinct from old.supplier then
  if new.supplier is null or new.supplier not in('BRV','HANIN','VIỆT PHÁP','ASAHI','MINGANN') then raise exception 'Nhà cung cấp IQC phải thuộc danh sách 5 nhà cung cấp';end if;
 end if;
 return new;
end $$;
revoke all on function public.iqc_kiem_tra_thong_tin_lot() from public,anon,authenticated;

create or replace function public.iqc_nvl_danh_muc() returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object(
 'san_pham',coalesce((select jsonb_agg(jsonb_build_object('code',ma_sp,'name',ten_sp) order by ma_sp) from master_products),'[]'),
 'nvl',coalesce((select jsonb_agg(jsonb_build_object('code',n.ma_nvl,'name',n.ten_nvl,'supplier',n.nha_cung_cap,'group',c.nhom,'grade',c.mac_vat_lieu) order by n.ma_nvl)
  from nvl_materials n left join iqc_nvl_phan_loai c on c.ma_nvl=n.ma_nvl),'[]')) where auth.uid() is not null;
$$;
revoke all on function public.iqc_nvl_danh_muc() from public,anon;
grant execute on function public.iqc_nvl_danh_muc() to authenticated;

create or replace function public.iqc_nvl_luu_phan_loai(p_ma_nvl text,p_nhom text,p_mac text) returns void language plpgsql security definer set search_path=public as $$
declare before jsonb;after jsonb;
begin
 if auth.uid() is null or not has_role('admin','qc_manager','iqc') then raise exception 'Chỉ IQC hoặc quản lý QC được phân loại NVL';end if;
 if not exists(select 1 from nvl_materials where ma_nvl=p_ma_nvl) then raise exception 'Chọn mã NVL hiện có trong BOM';end if;
 if p_nhom is null or p_nhom not in('nhom','kem','khac') or (p_nhom<>'khac' and nullif(trim(p_mac),'') is null) then raise exception 'Chọn nhóm vật liệu và nhập mác cho Nhôm/Kẽm';end if;
 perform pg_advisory_xact_lock(hashtextextended('iqc-nvl:'||p_ma_nvl,0));
 select to_jsonb(c) into before from iqc_nvl_phan_loai c where ma_nvl=p_ma_nvl for update;
 insert into iqc_nvl_phan_loai(ma_nvl,nhom,mac_vat_lieu,cap_nhat_boi) values(p_ma_nvl,p_nhom,nullif(trim(p_mac),''),auth.uid())
 on conflict(ma_nvl) do update set nhom=excluded.nhom,mac_vat_lieu=excluded.mac_vat_lieu,cap_nhat_luc=clock_timestamp(),cap_nhat_boi=auth.uid()
 returning to_jsonb(iqc_nvl_phan_loai.*) into after;
 insert into iqc_lich_su(loai,khoa,du_lieu_cu,du_lieu_moi,nguoi_uid,nguoi) values('phan_loai',p_ma_nvl,before,after,auth.uid(),duc_ten_nguoi_hien_tai());
end $$;
revoke all on function public.iqc_nvl_luu_phan_loai(text,text,text) from public,anon;
grant execute on function public.iqc_nvl_luu_phan_loai(text,text,text) to authenticated;

create or replace function public.iqc_tc_hoa_hoc(p_ma_nvl text,p_ngay date) returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('phan_loai',to_jsonb(c),'tieu_chuan',to_jsonb(b),
 'nguyen_to',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('bat_buoc',coalesce((m.nguon_nhan_dien->>'bat_buoc')::boolean,true)) order by muc_no) from ipqc_btk_muc m where m.id_btk=b.id),'[]'))
 from iqc_nvl_phan_loai c left join lateral(
  select * from ipqc_btk v where v.cong_doan='iqc_hoa_hoc' and v.ma_nvl=c.ma_nvl and v.mac_vat_lieu=c.mac_vat_lieu and v.nhom_vat_lieu=c.nhom
   and v.trang_thai='da_duyet' and v.ngay_hieu_luc<=p_ngay order by v.ngay_hieu_luc desc,v.phe_duyet_luc desc,v.id desc limit 1
 ) b on true where c.ma_nvl=p_ma_nvl and auth.uid() is not null;
$$;
revoke all on function public.iqc_tc_hoa_hoc(text,date) from public,anon;
grant execute on function public.iqc_tc_hoa_hoc(text,date) to authenticated;

create or replace function public.iqc_so(p text) returns numeric language plpgsql immutable set search_path=public as $$
declare v text:=replace(trim(p),',','.');
begin
 if v is null or v='' then return null;end if;
 if v like '.%' then v:='0'||v;elsif v like '+.%' then v:='+0'||substr(v,2);end if;
 if length(v)>64 or v !~ '^[+]?[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$' then raise exception 'Giá trị hàm lượng phải là số hữu hạn không âm';end if;
 if v ~ '[eE]' and abs(split_part(lower(v),'e',2)::integer)>30 then raise exception 'Số mũ hàm lượng vượt giới hạn';end if;
 return v::numeric;
end $$;
revoke all on function public.iqc_so(text) from public,anon,authenticated;
create or replace function public.iqc_nguyen_to_hop_le(p text) returns boolean language sql immutable set search_path=public as $$
 select coalesce(p=any(string_to_array('H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe Cs Ba La Ce Pr Nd Pm Sm Eu Gd Tb Dy Ho Er Tm Yb Lu Hf Ta W Re Os Ir Pt Au Hg Tl Pb Bi Po At Rn Fr Ra Ac Th Pa U Np Pu Am Cm Bk Cf Es Fm Md No Lr Rf Db Sg Bh Hs Mt Ds Rg Cn Nh Fl Mc Lv Ts Og',' ')),false);
$$;
revoke all on function public.iqc_nguyen_to_hop_le(text) from public,anon,authenticated;

create or replace function public.iqc_tc_luu_hoa_hoc(p_id bigint,p_data jsonb,p_gui boolean default false) returns bigint
language plpgsql security definer set search_path=public as $$
declare b ipqc_btk%rowtype;c iqc_nvl_phan_loai%rowtype;r jsonb;i int:=0;v bigint;before jsonb;symbol text;lo numeric;hi numeric;unit text;
begin
 if auth.uid() is null or not has_role('admin','qc_manager','iqc') then raise exception 'Chỉ IQC hoặc quản lý QC được soạn tiêu chuẩn hóa học';end if;
 select * into c from iqc_nvl_phan_loai where ma_nvl=p_data->>'ma_nvl';
 if c.nhom is null or c.nhom not in('nhom','kem') then raise exception 'Phân loại Nhôm/Kẽm và mác vật liệu trước khi soạn tiêu chuẩn';end if;
 if nullif(trim(p_data->>'phien_ban'),'') is null or nullif(trim(p_data->>'noi_dung_sua_doi'),'') is null or nullif(p_data->>'ngay_hieu_luc','') is null then raise exception 'Nhập Revision, ngày hiệu lực và nội dung sửa đổi';end if;
 if jsonb_typeof(p_data->'nguyen_to') is distinct from 'array' or jsonb_array_length(p_data->'nguyen_to')=0 then raise exception 'Nhập ít nhất một nguyên tố theo tiêu chuẩn vật liệu';end if;
 if not exists(select 1 from jsonb_array_elements(p_data->'nguyen_to') x where coalesce((x->>'required')::boolean,true)) then raise exception 'Tiêu chuẩn phải có nguyên tố bắt buộc';end if;
 if (select count(*)<>count(distinct x->>'element') from jsonb_array_elements(p_data->'nguyen_to') x) then raise exception 'Không được trùng nguyên tố';end if;
 perform pg_advisory_xact_lock(hashtextextended('iqc-tc:'||c.ma_nvl,0));
 if exists(select 1 from ipqc_btk where cong_doan='iqc_hoa_hoc' and ma_sp=c.ma_nvl and phien_ban=trim(p_data->>'phien_ban') and id is distinct from p_id) then raise exception 'Revision đã tồn tại; chọn mã phiên bản mới';end if;
 if p_id is not null then
  select * into b from ipqc_btk where id=p_id for update;
  if b.id is null or b.cong_doan<>'iqc_hoa_hoc' or b.ma_nvl<>c.ma_nvl or b.trang_thai not in('ban_nhap','tra_lai') then raise exception 'Chỉ sửa bản nháp/trả lại của đúng NVL';end if;
  if b.nguoi_lap_uid is distinct from auth.uid() and not has_role('admin','qc_manager') then raise exception 'Chỉ người soạn hoặc quản lý QC được sửa bản nháp';end if;
  before:=to_jsonb(b);
  update ipqc_btk set phien_ban=trim(p_data->>'phien_ban'),ngay_hieu_luc=(p_data->>'ngay_hieu_luc')::date,
   noi_dung_sua_doi=trim(p_data->>'noi_dung_sua_doi'),nhom_vat_lieu=c.nhom,mac_vat_lieu=c.mac_vat_lieu,
   trang_thai=case when p_gui then 'cho_kiem_tra' else 'ban_nhap' end,gui_luc=case when p_gui then now() end where id=p_id;
  v:=p_id;delete from ipqc_btk_muc where id_btk=v;
 else
  insert into ipqc_btk(ma_sp,ma_nvl,cong_doan,phien_ban,ngay_hieu_luc,nhom_vat_lieu,mac_vat_lieu,noi_dung_sua_doi,nguoi_lap,nguoi_lap_uid,trang_thai,dang_dung,gui_luc)
   values(c.ma_nvl,c.ma_nvl,'iqc_hoa_hoc',trim(p_data->>'phien_ban'),(p_data->>'ngay_hieu_luc')::date,c.nhom,c.mac_vat_lieu,
   trim(p_data->>'noi_dung_sua_doi'),duc_ten_nguoi_hien_tai(),auth.uid(),case when p_gui then 'cho_kiem_tra' else 'ban_nhap' end,false,case when p_gui then now() end) returning id into v;
 end if;
 for r in select value from jsonb_array_elements(p_data->'nguyen_to') loop
  symbol:=r->>'element';unit:=r->>'unit';lo:=iqc_so(r->>'min');hi:=iqc_so(r->>'max');
  if not iqc_nguyen_to_hop_le(symbol) or unit is null or unit not in('%','ppm','mg/kg') or (lo is null and hi is null)
   or (lo is not null and hi is not null and lo>hi) or (unit='%' and greatest(coalesce(lo,0),coalesce(hi,0))>100) then raise exception 'Kiểm tra nguyên tố, đơn vị và giới hạn Min/Max theo tiêu chuẩn';end if;
  i:=i+1;
  insert into ipqc_btk_muc(id_btk,muc_no,hang_muc,ma_dac_tinh,kieu,lsl,usl,don_vi,nguon_nhan_dien,xac_nhan_boi,xac_nhan_luc)
   values(v,i,symbol,symbol,'so',lo,hi,unit,jsonb_build_object('bat_buoc',coalesce((r->>'required')::boolean,true)),auth.uid(),now());
 end loop;
 insert into iqc_lich_su(loai,khoa,du_lieu_cu,du_lieu_moi,nguoi_uid,nguoi) values('tieu_chuan',v::text,before,
  jsonb_build_object('header',(select to_jsonb(x) from ipqc_btk x where id=v),'nguyen_to',p_data->'nguyen_to'),auth.uid(),duc_ten_nguoi_hien_tai());
 return v;
end $$;
revoke all on function public.iqc_tc_luu_hoa_hoc(bigint,jsonb,boolean) from public,anon;
grant execute on function public.iqc_tc_luu_hoa_hoc(bigint,jsonb,boolean) to authenticated;

create or replace function public.iqc_tc_audit() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if old.cong_doan='iqc_hoa_hoc' and old.trang_thai is distinct from new.trang_thai then
  insert into iqc_lich_su(loai,khoa,du_lieu_cu,du_lieu_moi,nguoi_uid,nguoi) values('duyet_tieu_chuan',new.id::text,to_jsonb(old),to_jsonb(new),auth.uid(),duc_ten_nguoi_hien_tai());
 end if;return new;
end $$;
revoke all on function public.iqc_tc_audit() from public,anon,authenticated;
create trigger iqc_tc_audit after update on public.ipqc_btk for each row execute function public.iqc_tc_audit();

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('iqc-phan-tich','iqc-phan-tich',false,20971520,
 array['application/pdf','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.ms-excel','image/jpeg','image/png']);
create policy iqc_file_doc on storage.objects for select to authenticated using(bucket_id='iqc-phan-tich' and has_role('admin','qc_manager','iqc','giam_doc_sx'));
create policy iqc_file_them on storage.objects for insert to authenticated with check(bucket_id='iqc-phan-tich' and has_role('admin','qc_manager','iqc')
 and (storage.foldername(name))[1]=auth.uid()::text and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.](pdf|xlsx|xls|jpg|png)$');

create or replace function public.iqc_luu_hoa_hoc(p_id bigint,p_data jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare oldlot iqc_lots%rowtype;c iqc_nvl_phan_loai%rowtype;n nvl_materials%rowtype;tc jsonb;b jsonb;els jsonb;results jsonb:='[]';
 r jsonb;v numeric;raw text;missing boolean:=false;failed boolean:=false;confirmed boolean:=coalesce((p_data->>'xac_nhan')::boolean,false);
 conclusion text:='';actor text;file jsonb:=p_data->'file';obj storage.objects%rowtype;v_id bigint;request uuid:=(p_data->>'request_id')::uuid;
 previous_request iqc_yeu_cau_luu%rowtype;request_body jsonb:=jsonb_build_object('id',p_id,'data',p_data);
begin
 if auth.uid() is null or not has_role('admin','qc_manager','iqc') then raise exception 'Chỉ IQC hoặc quản lý QC được lưu báo cáo hóa học';end if;
 if request is null then raise exception 'Thiếu mã yêu cầu lưu';end if;
 perform pg_advisory_xact_lock(hashtextextended('iqc-report:'||request,0));
 select * into previous_request from iqc_yeu_cau_luu where request_id=request;
 if found then
  if previous_request.nguoi_uid<>auth.uid() or previous_request.du_lieu<>request_body then raise exception 'Yêu cầu này đã lưu; mở lại báo cáo để sửa';end if;
  return jsonb_build_object('id',previous_request.id_lot,'existing',true);
 end if;
 if p_id is not null then
  select * into oldlot from iqc_lots where iqc_lots.id=p_id for update;
  if oldlot.id is null or oldlot.phuong_thuc<>'hoa_hoc' or oldlot.da_luu_tru then raise exception 'Không tìm thấy báo cáo hóa học';end if;
  if nullif(p_data->>'updated_at','')::timestamptz is distinct from oldlot.updated_at then raise exception 'Báo cáo đã thay đổi; mở lại trước khi lưu';end if;
 end if;
 select * into n from nvl_materials where ma_nvl=p_data->>'ma_nvl';
 select * into c from iqc_nvl_phan_loai where ma_nvl=n.ma_nvl;
 if n.ma_nvl is null or c.nhom is null or c.nhom not in('nhom','kem') then raise exception 'Chọn NVL được phân loại Nhôm/Kẽm';end if;
 if nullif(trim(p_data->>'lot_no'),'') is null or nullif(p_data->>'ngay_kiem','') is null
  or coalesce(p_data->>'ca_kiem','') not in('Ca ngày','Ca đêm','Ca 1','Ca 2') then raise exception 'Nhập ngày kiểm, ca và số lô';end if;
 if not exists(select 1 from user_roles where username=p_data->>'inspector' and role in('iqc','qc_manager','admin')) then raise exception 'Chọn tài khoản IQC hoặc quản lý QC';end if;
 tc:=iqc_tc_hoa_hoc(n.ma_nvl,(p_data->>'ngay_kiem')::date);b:=tc->'tieu_chuan';els:=coalesce(tc->'nguyen_to','[]');
 if nullif(p_data->>'id_tieu_chuan','')::bigint is distinct from nullif(b->>'id','')::bigint then raise exception 'Tiêu chuẩn có hiệu lực đã thay đổi; tải lại trước khi lưu';end if;
 if b is null or b='null' or jsonb_array_length(els)=0 then missing:=true;end if;
 if jsonb_typeof(p_data->'results') is distinct from 'object' then raise exception 'Kết quả nguyên tố không hợp lệ';end if;
 for r in select value from jsonb_array_elements(els) loop
  raw:=nullif(trim(p_data->'results'->>(r->>'ma_dac_tinh')),'');v:=iqc_so(raw);
  if v is not null and (r->>'don_vi')='%' and v>100 then raise exception 'Hàm lượng phần trăm không được vượt 100';end if;
  if v is null and coalesce((r->>'bat_buoc')::boolean,true) then missing:=true;end if;
  failed:=failed or (v is not null and ((r->>'lsl' is not null and v<(r->>'lsl')::numeric) or (r->>'usl' is not null and v>(r->>'usl')::numeric)));
  results:=results||jsonb_build_array(jsonb_build_object('element',r->>'ma_dac_tinh','min',r->'lsl','max',r->'usl','unit',r->>'don_vi',
   'required',coalesce((r->>'bat_buoc')::boolean,true),'value',v,'result',case when v is null then 'Chưa nhận diện' when
    (r->>'lsl' is not null and v<(r->>'lsl')::numeric) or (r->>'usl' is not null and v>(r->>'usl')::numeric) then 'NG' else 'OK' end));
 end loop;
 if confirmed then conclusion:=case when failed then 'NG' when not missing then 'OK' else '' end;end if;
 if file is not null and file<>'null' then
  if file->>'bucket' is distinct from 'iqc-phan-tich' then raise exception 'Vùng lưu file không hợp lệ';end if;
  select * into obj from storage.objects where bucket_id='iqc-phan-tich' and name=file->>'path';
  if not found or (obj.owner_id is distinct from auth.uid()::text and oldlot.hoa_hoc_json->'file'->>'path' is distinct from obj.name)
   or coalesce(obj.metadata->>'size','') !~ '^[0-9]+$' or (obj.metadata->>'size')::bigint not between 1 and 20971520
   or coalesce(obj.metadata->>'mimetype','') not in('application/pdf','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.ms-excel','image/jpeg','image/png')
   then raise exception 'File chưa tải lên hoặc sai định dạng/chủ file/dung lượng';end if;
  file:=jsonb_build_object('bucket','iqc-phan-tich','path',obj.name,'name',left(file->>'name',255),'type',obj.metadata->>'mimetype','size',(obj.metadata->>'size')::bigint);
 end if;
 tc:=jsonb_build_object('tieu_chuan',b,'nguyen_to',results,'file',file,'xac_nhan',confirmed,'ket_luan',conclusion,'nguon',p_data->'nguon');
 actor:=duc_ten_nguoi_hien_tai();
 if p_id is null then
  insert into iqc_lots(doi_tuong,ma_nvl,phuong_thuc,nhom_vat_lieu,mac_vat_lieu,ngay_kiem,ca_kiem,id_tieu_chuan,hoa_hoc_json,nguoi_tao_uid,request_id,
   received_at,supplier,product_code,product_name,lot_no,lot_qty,inspection_type,sample_qty,ok_qty,ng_qty,ok_pct,ng_pct,pham_vi,status,result,inspector,nguoi_kiem_id,nguoi_kiem_ten,note)
  values('nvl',n.ma_nvl,'hoa_hoc',c.nhom,c.mac_vat_lieu,(p_data->>'ngay_kiem')::date,p_data->>'ca_kiem',nullif(b->>'id','')::bigint,tc,auth.uid(),request,
   ((p_data->>'ngay_kiem')::date::timestamp at time zone 'Asia/Ho_Chi_Minh'),nullif(trim(p_data->>'supplier'),''),n.ma_nvl,n.ten_nvl,trim(p_data->>'lot_no'),0,'Kiểm tra thành phần hóa học',0,0,0,0,0,
   'Nguyên vật liệu',case when conclusion='' then 'Đang kiểm tra' else 'Đã kiểm tra' end,conclusion,p_data->>'inspector',p_data->>'inspector',
   (select coalesce(full_name,username) from user_roles where username=p_data->>'inspector'),p_data->>'note') returning iqc_lots.id into v_id;
 else
  update iqc_lots set ma_nvl=n.ma_nvl,nhom_vat_lieu=c.nhom,mac_vat_lieu=c.mac_vat_lieu,ngay_kiem=(p_data->>'ngay_kiem')::date,ca_kiem=p_data->>'ca_kiem',
   received_at=((p_data->>'ngay_kiem')::date::timestamp at time zone 'Asia/Ho_Chi_Minh'),
   id_tieu_chuan=nullif(b->>'id','')::bigint,hoa_hoc_json=tc,supplier=nullif(trim(p_data->>'supplier'),''),product_code=n.ma_nvl,product_name=n.ten_nvl,
   lot_no=trim(p_data->>'lot_no'),status=case when conclusion='' then 'Đang kiểm tra' else 'Đã kiểm tra' end,result=conclusion,
   inspector=p_data->>'inspector',nguoi_kiem_id=p_data->>'inspector',nguoi_kiem_ten=(select coalesce(full_name,username) from user_roles where username=p_data->>'inspector'),note=p_data->>'note'
   where iqc_lots.id=p_id returning iqc_lots.id into v_id;
 end if;
 insert into iqc_lich_su(loai,khoa,du_lieu_cu,du_lieu_moi,nguoi_uid,nguoi) values('bao_cao',v_id::text,case when p_id is not null then to_jsonb(oldlot) end,
  (select to_jsonb(l) from iqc_lots l where l.id=v_id),auth.uid(),actor);
 insert into iqc_yeu_cau_luu values(request,auth.uid(),v_id,request_body);
 return jsonb_build_object('id',v_id,'result',conclusion);
end $$;
revoke all on function public.iqc_luu_hoa_hoc(bigint,jsonb) from public,anon;
grant execute on function public.iqc_luu_hoa_hoc(bigint,jsonb) to authenticated;
create or replace function public.iqc_luu_tru_hoa_hoc(p_id bigint) returns void language plpgsql security definer set search_path=public as $$
declare r iqc_lots%rowtype;
begin
 if auth.uid() is null or not has_role('admin','qc_manager') then raise exception 'Chỉ quản lý QC được lưu trữ báo cáo';end if;
 select * into r from iqc_lots where id=p_id and phuong_thuc='hoa_hoc' for update;
 if not found then raise exception 'Không tìm thấy báo cáo hóa học';end if;
 if r.da_luu_tru then return;end if;
 update iqc_lots set da_luu_tru=true where id=p_id;
 insert into iqc_lich_su(loai,khoa,du_lieu_cu,du_lieu_moi,nguoi_uid,nguoi) values('luu_tru_bao_cao',p_id::text,to_jsonb(r),null,auth.uid(),duc_ten_nguoi_hien_tai());
end $$;
revoke all on function public.iqc_luu_tru_hoa_hoc(bigint) from public,anon;
grant execute on function public.iqc_luu_tru_hoa_hoc(bigint) to authenticated;
notify pgrst,'reload schema';
commit;
