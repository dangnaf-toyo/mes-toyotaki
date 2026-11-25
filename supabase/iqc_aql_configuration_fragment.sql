-- Approved, versioned product-group sampling configurations; no standard table is seeded.
create table public.iqc_aql_cau_hinh (
 id bigint generated always as identity primary key,
 nhom text not null, phien_ban text not null, nguon text not null,
 cap_do text not null, aql text not null, phuong_an text not null,
 bang jsonb not null, san_pham text[] not null,
 da_duyet boolean not null default false, nguoi_duyet uuid, duyet_luc timestamptz,
 unique(nhom,phien_ban)
);
alter table public.iqc_aql_cau_hinh enable row level security;
revoke all on public.iqc_aql_cau_hinh from public,anon,authenticated;
grant select on public.iqc_aql_cau_hinh to authenticated;
create policy iqc_aql_cau_hinh_doc on public.iqc_aql_cau_hinh for select to authenticated using(true);

-- An approved configuration is immutable. Later editions use a new version.
create or replace function public.iqc_luu_cau_hinh_aql(p_nhom text,p_phien_ban text,p_nguon text,p_cap_do text,p_aql text,p_phuong_an text,p_bang jsonb,p_san_pham text[],p_duyet boolean)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_id bigint;
begin
 if auth.uid() is null or not has_role('admin','qc_manager') then raise exception 'Chỉ quản lý QC được cấu hình AQL'; end if;
 if nullif(trim(p_nhom),'') is null or nullif(trim(p_phien_ban),'') is null or nullif(trim(p_nguon),'') is null or nullif(trim(p_cap_do),'') is null or nullif(trim(p_aql),'') is null or nullif(trim(p_phuong_an),'') is null or jsonb_typeof(p_bang)<>'object' or jsonb_typeof(p_bang->'lotRanges')<>'array' or jsonb_typeof(p_bang->'plans')<>'object' or coalesce(cardinality(p_san_pham),0)=0 or exists(select 1 from unnest(p_san_pham) x where nullif(trim(x),'') is null) then raise exception 'Thiếu thông tin cấu hình AQL'; end if;
 perform pg_advisory_xact_lock(hashtextextended('iqc-aql-config',0));
 if p_duyet and exists(select 1 from iqc_aql_cau_hinh c where c.da_duyet and c.nhom<>trim(p_nhom) and c.san_pham && p_san_pham) then raise exception 'Mã đã thuộc nhóm AQL được duyệt khác'; end if;
 if p_duyet then
  insert into iqc_lich_su(loai,khoa,du_lieu_cu,du_lieu_moi,nguoi_uid,nguoi)
   select 'ngung_cau_hinh_aql',id::text,to_jsonb(c),jsonb_build_object('thay_bang_phien_ban',trim(p_phien_ban)),auth.uid(),duc_ten_nguoi_hien_tai() from iqc_aql_cau_hinh c where da_duyet and nhom=trim(p_nhom);
  update iqc_aql_cau_hinh set da_duyet=false where da_duyet and nhom=trim(p_nhom);
 end if;
 insert into iqc_aql_cau_hinh(nhom,phien_ban,nguon,cap_do,aql,phuong_an,bang,san_pham,da_duyet,nguoi_duyet,duyet_luc)
 values(trim(p_nhom),trim(p_phien_ban),trim(p_nguon),trim(p_cap_do),trim(p_aql),trim(p_phuong_an),p_bang,p_san_pham,coalesce(p_duyet,false),case when p_duyet then auth.uid() end,case when p_duyet then clock_timestamp() end) returning id into v_id;
 insert into iqc_lich_su(loai,khoa,du_lieu_moi,nguoi_uid,nguoi) values('cau_hinh_aql',v_id::text,(select to_jsonb(c) from iqc_aql_cau_hinh c where c.id=v_id),auth.uid(),duc_ten_nguoi_hien_tai());
 return v_id;
end $$;
revoke all on function public.iqc_luu_cau_hinh_aql(text,text,text,text,text,text,jsonb,text[],boolean) from public,anon;
grant execute on function public.iqc_luu_cau_hinh_aql(text,text,text,text,text,text,jsonb,text[],boolean) to authenticated;

create or replace function public.iqc_tra_ke_hoach_aql(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare l iqc_lots%rowtype; c iqc_aql_cau_hinh%rowtype; rng jsonb; plan jsonb; code text; first_code text; seen text[]:='{}'; n bigint; ac bigint; re bigint; matches int;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập'; end if;
 select * into l from iqc_lots where id=p_id;
 if not found or l.inspection_type<>'Kiểm tra AQL' then return null; end if;
 select count(*) into matches from iqc_aql_cau_hinh where da_duyet and l.product_code=any(san_pham);
 if matches<>1 then return null; end if;
 select * into c from iqc_aql_cau_hinh where da_duyet and l.product_code=any(san_pham);
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
revoke all on function public.iqc_tra_ke_hoach_aql(bigint) from public,anon;
grant execute on function public.iqc_tra_ke_hoach_aql(bigint) to authenticated;
