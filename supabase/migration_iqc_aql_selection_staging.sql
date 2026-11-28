-- IQC release step 3. Adds per-LOT AQL selection. Production execution pending.
begin;
create table public.iqc_aql_lua_chon (
 lot_id bigint primary key references public.iqc_lots(id), cap_do text not null, aql text not null, che_do text not null,
 nguoi_chon uuid not null, chon_luc timestamptz not null default clock_timestamp()
);
alter table public.iqc_aql_lua_chon enable row level security;
revoke all on public.iqc_aql_lua_chon from public,anon,authenticated;
grant select on public.iqc_aql_lua_chon to authenticated;
create policy iqc_aql_lua_chon_doc on public.iqc_aql_lua_chon for select to authenticated using(true);
alter table public.iqc_aql_cau_hinh drop constraint iqc_aql_cau_hinh_nhom_phien_ban_key;
alter table public.iqc_aql_cau_hinh add constraint iqc_aql_cau_hinh_phien_ban_tuy_chon_key unique(nhom,phien_ban,cap_do,aql,phuong_an);

create or replace function public.iqc_chon_aql(p_id bigint,p_cap_do text,p_aql text,p_che_do text,p_ly_do text,p_updated_at timestamptz)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l iqc_lots%rowtype; old_choice iqc_aql_lua_chon%rowtype; result iqc_aql_lua_chon%rowtype; old_plan jsonb; changed boolean;
begin
 if auth.uid() is null or not has_role('admin','qc_manager','iqc') then raise exception 'Không có quyền chọn kế hoạch'; end if;
 if p_cap_do is null or p_che_do is null or p_cap_do not in ('I','II','III','S-1','S-2','S-3','S-4') or nullif(trim(p_aql),'') is null or p_che_do not in ('Normal','Tightened','Reduced') then raise exception 'Lựa chọn AQL không hợp lệ'; end if;
 select * into l from iqc_lots where id=p_id for update;
 if not found or l.da_luu_tru or l.phuong_thuc<>'ngoai_quan' or l.inspection_type<>'Kiểm tra AQL' then raise exception 'Chọn LOT kiểm AQL'; end if;
 if l.updated_at is distinct from p_updated_at then raise exception 'LOT đã thay đổi; tải lại'; end if;
 select * into old_choice from iqc_aql_lua_chon where lot_id=p_id;
 changed:=old_choice.lot_id is null or (old_choice.cap_do,old_choice.aql,old_choice.che_do) is distinct from (p_cap_do,trim(p_aql),p_che_do);
 if not changed then return to_jsonb(old_choice); end if;
 if (exists(select 1 from iqc_lan_kiem where lot_id=p_id) or exists(select 1 from iqc_aql_ke_hoach where lot_id=p_id)) and (not has_role('admin','qc_manager') or nullif(trim(p_ly_do),'') is null) then raise exception 'Chỉ quản lý QC được đổi kế hoạch đã dùng và phải ghi lý do'; end if;
 select to_jsonb(k) into old_plan from iqc_aql_ke_hoach k where lot_id=p_id;
 delete from iqc_aql_ke_hoach where lot_id=p_id;
 if l.iqc_ket_luan is not null then
  perform set_config('iqc.quality_lot',p_id::text,true); update iqc_lots set iqc_ket_luan=null where id=p_id; perform set_config('iqc.quality_lot','',true);
 end if;
 insert into iqc_aql_lua_chon(lot_id,cap_do,aql,che_do,nguoi_chon) values(p_id,p_cap_do,trim(p_aql),p_che_do,auth.uid())
 on conflict(lot_id) do update set cap_do=excluded.cap_do,aql=excluded.aql,che_do=excluded.che_do,nguoi_chon=auth.uid(),chon_luc=clock_timestamp() returning * into result;
 perform iqc_tinh_tong_lot(p_id);
 insert into iqc_lich_su(loai,khoa,du_lieu_cu,du_lieu_moi,nguoi_uid,nguoi) values('chon_aql',p_id::text,jsonb_build_object('lua_chon',to_jsonb(old_choice),'ke_hoach',old_plan,'ket_luan',l.iqc_ket_luan),to_jsonb(result)||jsonb_build_object('ly_do',p_ly_do),auth.uid(),duc_ten_nguoi_hien_tai());
 return to_jsonb(result);
end $$;
revoke all on function public.iqc_chon_aql(bigint,text,text,text,text,timestamptz) from public,anon;
grant execute on function public.iqc_chon_aql(bigint,text,text,text,text,timestamptz) to authenticated;

create or replace function public.iqc_luu_cau_hinh_aql(p_nhom text,p_phien_ban text,p_nguon text,p_cap_do text,p_aql text,p_phuong_an text,p_bang jsonb,p_san_pham text[],p_duyet boolean)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_id bigint;
begin
 if auth.uid() is null or not has_role('admin','qc_manager') then raise exception 'Chỉ quản lý QC được cấu hình AQL'; end if;
 if nullif(trim(p_nhom),'') is null or nullif(trim(p_phien_ban),'') is null or nullif(trim(p_nguon),'') is null or nullif(trim(p_cap_do),'') is null or nullif(trim(p_aql),'') is null or nullif(trim(p_phuong_an),'') is null or jsonb_typeof(p_bang)<>'object' or jsonb_typeof(p_bang->'lotRanges')<>'array' or jsonb_typeof(p_bang->'plans')<>'object' or coalesce(cardinality(p_san_pham),0)=0 or exists(select 1 from unnest(p_san_pham) x where nullif(trim(x),'') is null) then raise exception 'Thiếu thông tin cấu hình AQL'; end if;
 perform pg_advisory_xact_lock(hashtextextended('iqc-aql-config',0));
 if p_duyet and exists(select 1 from iqc_aql_cau_hinh c where c.da_duyet and c.nhom<>trim(p_nhom) and c.cap_do=trim(p_cap_do) and c.aql=trim(p_aql) and c.phuong_an=trim(p_phuong_an) and c.san_pham && p_san_pham) then raise exception 'Mã đã thuộc nhóm AQL được duyệt khác'; end if;
 if p_duyet then
  insert into iqc_lich_su(loai,khoa,du_lieu_cu,du_lieu_moi,nguoi_uid,nguoi)
   select 'ngung_cau_hinh_aql',id::text,to_jsonb(c),jsonb_build_object('thay_bang_phien_ban',trim(p_phien_ban)),auth.uid(),duc_ten_nguoi_hien_tai() from iqc_aql_cau_hinh c where da_duyet and nhom=trim(p_nhom) and cap_do=trim(p_cap_do) and aql=trim(p_aql) and phuong_an=trim(p_phuong_an);
  update iqc_aql_cau_hinh set da_duyet=false where da_duyet and nhom=trim(p_nhom) and cap_do=trim(p_cap_do) and aql=trim(p_aql) and phuong_an=trim(p_phuong_an);
 end if;
 insert into iqc_aql_cau_hinh(nhom,phien_ban,nguon,cap_do,aql,phuong_an,bang,san_pham,da_duyet,nguoi_duyet,duyet_luc)
 values(trim(p_nhom),trim(p_phien_ban),trim(p_nguon),trim(p_cap_do),trim(p_aql),trim(p_phuong_an),p_bang,p_san_pham,coalesce(p_duyet,false),case when p_duyet then auth.uid() end,case when p_duyet then clock_timestamp() end) returning id into v_id;
 insert into iqc_lich_su(loai,khoa,du_lieu_moi,nguoi_uid,nguoi) values('cau_hinh_aql',v_id::text,(select to_jsonb(c) from iqc_aql_cau_hinh c where c.id=v_id),auth.uid(),duc_ten_nguoi_hien_tai());
 return v_id;
end $$;

create or replace function public.iqc_tra_ke_hoach_aql(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare l iqc_lots%rowtype; choice iqc_aql_lua_chon%rowtype; c iqc_aql_cau_hinh%rowtype; rng jsonb; plan jsonb; code text; first_code text; seen text[]:='{}'; n bigint; ac bigint; re bigint; matches int;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập'; end if;
 select * into l from iqc_lots where id=p_id;
 if not found or l.inspection_type<>'Kiểm tra AQL' then return null; end if;
 select * into choice from iqc_aql_lua_chon where lot_id=p_id;
 if not found then return null; end if;
 select count(*) into matches from iqc_aql_cau_hinh where da_duyet and l.product_code=any(san_pham) and cap_do=choice.cap_do and aql=choice.aql and phuong_an=choice.che_do;
 if matches<>1 then return null; end if;
 select * into c from iqc_aql_cau_hinh where da_duyet and l.product_code=any(san_pham) and cap_do=choice.cap_do and aql=choice.aql and phuong_an=choice.che_do;
 begin
  select count(*) into matches from jsonb_array_elements(c.bang->'lotRanges') x where (x->>'min')::bigint<=l.lot_qty and (x->>'max' is null or (x->>'max')::bigint>=l.lot_qty);
  if matches<>1 then return null; end if;
  select x into rng from jsonb_array_elements(c.bang->'lotRanges') x where (x->>'min')::bigint<=l.lot_qty and (x->>'max' is null or (x->>'max')::bigint>=l.lot_qty);
  code:=rng->>'code'; first_code:=code;
  loop
   if code is null or code=any(seen) then return null; end if;
   seen:=array_append(seen,code); plan:=c.bang->'plans'->code;
   if plan is null then return null; end if;
   if nullif(plan->>'use','') is not null then code:=plan->>'use'; continue; end if;
   n:=(plan->>'sample')::bigint; ac:=(plan->>'ac')::bigint; re:=(plan->>'re')::bigint;
   if n is null or ac is null or re is null or n<1 or n>l.lot_qty or ac<0 or ac>=n or re<>ac+1 then return null; end if;
   return jsonb_build_object('cau_hinh_id',c.id,'nhom',c.nhom,'phien_ban',c.phien_ban,'nguon',c.nguon,'cap_do',c.cap_do,'aql',c.aql,'phuong_an',c.phuong_an,'ma_chu',first_code,'ma_mau',code,'mau_yeu_cau',n,'ac',ac,'re',re);
  end loop;
 exception when invalid_text_representation or numeric_value_out_of_range then return null; end;
end $$;

create or replace function public.iqc_duyet_ke_hoach_aql(p_id bigint,p_mau bigint,p_ac bigint,p_re bigint,p_nguon text,p_updated_at timestamptz)
returns void language plpgsql security definer set search_path=public as $$
declare l iqc_lots%rowtype; previous jsonb; after_plan jsonb; suggested jsonb;
begin
 if auth.uid() is null or not has_role('admin','qc_manager') then raise exception 'Chỉ quản lý QC được duyệt kế hoạch AQL'; end if;
 select * into l from iqc_lots where id=p_id for update;
 if not found or l.da_luu_tru or l.phuong_thuc<>'ngoai_quan' or l.inspection_type<>'Kiểm tra AQL' then raise exception 'Chọn LOT kiểm AQL'; end if;
 suggested:=iqc_tra_ke_hoach_aql(p_id);
 if suggested is null then raise exception 'Chưa có kế hoạch lấy mẫu'; end if;
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
notify pgrst,'reload schema';
commit;
