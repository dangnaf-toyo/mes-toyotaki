-- ĐÃ ÁP DỤNG PROD 09/11/2026 (gộp theo mảng, bỏ phiên bản hàm trung gian; bản cuối các hàm đã sửa xem T230).
-- Independent attachments; no changes to NCP business fields or approval RPCs.
begin;

create table public.ncp_hinh_anh (
 id uuid primary key default gen_random_uuid(),
 id_ncp text not null references public.duc_ncp(id_ncp),
 storage_path text unique,
 legacy_url text,
 ten_file text not null,
 mime_type text,
 dung_luong bigint,
 nguoi_them uuid,
 them_luc timestamptz,
 nhap_tu_du_lieu_cu boolean not null default false,
 xoa_luc timestamptz,
 nguoi_xoa uuid,
 unique(id_ncp,legacy_url),
 check ((storage_path is not null)::integer + (legacy_url is not null)::integer = 1),
 check (storage_path is null or (mime_type='image/jpeg' and dung_luong between 1 and 5242880))
);
create index on public.ncp_hinh_anh(id_ncp);
create table public.ncp_hinh_anh_lich_su (
 id bigint generated always as identity primary key,
 id_anh uuid not null references public.ncp_hinh_anh(id),
 id_ncp text not null references public.duc_ncp(id_ncp),
 thao_tac text not null check(thao_tac in ('them','xoa')),
 nguoi_thuc_hien uuid not null,
 ten_nguoi text,
 thoi_diem timestamptz not null default clock_timestamp(),
 ten_file text not null
);
create index on public.ncp_hinh_anh_lich_su(id_ncp,thoi_diem);
create table public.ncp_mo_phieu_yeu_cau (
 request_id uuid primary key,
 nguoi_mo uuid not null,
 id_ncp text not null references public.duc_ncp(id_ncp),
 noi_dung jsonb not null
);

-- Preserve all original URLs and case fields. Imported photos have no invented actor/time.
insert into public.ncp_hinh_anh(id_ncp,legacy_url,ten_file,nhap_tu_du_lieu_cu)
 select distinct c.id_ncp,img,'Ảnh đã đính kèm',true
 from public.duc_ncp c cross join lateral jsonb_array_elements_text(coalesce(c.source_images,'[]')) img
 where img is not null and img<>'';

alter table public.ncp_hinh_anh enable row level security;
alter table public.ncp_hinh_anh_lich_su enable row level security;
alter table public.ncp_mo_phieu_yeu_cau enable row level security;
revoke all on public.ncp_hinh_anh,public.ncp_hinh_anh_lich_su,public.ncp_mo_phieu_yeu_cau from anon,authenticated;
grant select on public.ncp_hinh_anh,public.ncp_hinh_anh_lich_su to authenticated;
create policy ncp_anh_doc on public.ncp_hinh_anh for select to authenticated using(true);
create policy ncp_anh_lich_su_doc on public.ncp_hinh_anh_lich_su for select to authenticated using(true);

create function public.ncp_anh_duoc_sua(p_id_ncp text default null) returns boolean
language sql stable security definer set search_path=public as $$
 select auth.uid() is not null and exists(select 1 from user_roles where user_id=auth.uid() and role<>'chi_xem')
 and case when p_id_ncp is null then true
 else exists(select 1 from duc_ncp c where c.id_ncp=p_id_ncp and (
  has_role('admin','qc_manager','giam_doc_sx','ipqc') or auth.uid()=c.nguoi_mo_uid
  or auth.uid()=any(cv_pd_ds_ten(c.nguoi_dam_nhiem)||cv_pd_ds_ten(c.nguoi_dam_nhiem_doi_sach)))) end;
$$;
revoke all on function public.ncp_anh_duoc_sua(text) from public,anon;
grant execute on function public.ncp_anh_duoc_sua(text) to authenticated;

-- A tab opened before deployment can still call the old source RPC. Preserve those photos too.
create function public.ncp_anh_dong_bo_cu() returns trigger
language plpgsql security definer set search_path=public as $$
declare url text;a uuid;
begin
 for url in select distinct value from jsonb_array_elements_text(coalesce(new.source_images,'[]')) where value is not null and value<>'' loop
  insert into ncp_hinh_anh(id_ncp,legacy_url,ten_file,nguoi_them,them_luc,nhap_tu_du_lieu_cu)
   values(new.id_ncp,url,'Ảnh đã đính kèm',auth.uid(),clock_timestamp(),true)
   on conflict(id_ncp,legacy_url) do nothing returning id into a;
  if found and auth.uid() is not null then
   insert into ncp_hinh_anh_lich_su(id_anh,id_ncp,thao_tac,nguoi_thuc_hien,ten_nguoi,ten_file)
    values(a,new.id_ncp,'them',auth.uid(),duc_ten_nguoi_hien_tai(),'Ảnh đã đính kèm');
  end if;
 end loop;
 return new;
end $$;
revoke all on function public.ncp_anh_dong_bo_cu() from public,anon,authenticated;
create trigger ncp_anh_dong_bo_cu after insert or update of source_images on public.duc_ncp
 for each row execute function public.ncp_anh_dong_bo_cu();

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('ncp-hinh-anh','ncp-hinh-anh',false,5242880,array['image/jpeg']);
-- The browser decodes/re-encodes allowed raster inputs into inert JPEGs; originals aren't stored.
create policy ncp_anh_upload on storage.objects for insert to authenticated with check(
 bucket_id='ncp-hinh-anh' and (storage.foldername(name))[1]=auth.uid()::text
 and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.]jpg$'
 and public.ncp_anh_duoc_sua());
create policy ncp_anh_storage_doc on storage.objects for select to authenticated using(
 bucket_id='ncp-hinh-anh' and (
  (storage.foldername(name))[1]=auth.uid()::text or exists(
   select 1 from public.ncp_hinh_anh a where a.storage_path=name and a.xoa_luc is null)));
-- No client UPDATE/DELETE policy: immutable objects remain available for audit after soft deletion.

create function public.ncp_anh_them(p_id_ncp text,p_images jsonb) returns void
language plpgsql security definer set search_path=public as $$
declare x jsonb;o storage.objects%rowtype;a uuid;n integer;
begin
 if not public.ncp_anh_duoc_sua(p_id_ncp) then raise exception 'Bạn không có quyền sửa hình ảnh phiếu này';end if;
 perform 1 from duc_ncp where id_ncp=p_id_ncp for update;
 if not found then raise exception 'Không tìm thấy phiếu';end if;
 if p_images is null or jsonb_typeof(p_images)<>'array' or jsonb_array_length(p_images)>10 then raise exception 'Tối đa 10 ảnh mỗi phiếu';end if;
 select count(*) into n from ncp_hinh_anh where id_ncp=p_id_ncp and xoa_luc is null;
 for x in select value from jsonb_array_elements(p_images) loop
  if exists(select 1 from ncp_hinh_anh where storage_path=x->>'path' and id_ncp=p_id_ncp and xoa_luc is null) then continue;end if;
  if n>=10 then raise exception 'Tối đa 10 ảnh mỗi phiếu';end if;
  if coalesce(x->>'path','') !~ ('^'||auth.uid()::text||'/[0-9a-f-]{36}/[0-9a-f-]{36}[.]jpg$')
   or coalesce(length(trim(x->>'name')),0) not between 1 and 255 then raise exception 'Thông tin ảnh không hợp lệ';end if;
  select * into o from storage.objects where bucket_id='ncp-hinh-anh' and name=x->>'path';
  if not found or o.owner_id is distinct from auth.uid()::text
   or o.metadata->>'mimetype' is distinct from 'image/jpeg'
   or coalesce(o.metadata->>'size','') !~ '^[0-9]+$'
   or (o.metadata->>'size')::bigint not between 1 and 5242880 then raise exception 'Ảnh chưa tải lên hoặc không hợp lệ';end if;
  insert into ncp_hinh_anh(id_ncp,storage_path,ten_file,mime_type,dung_luong,nguoi_them,them_luc)
   values(p_id_ncp,o.name,x->>'name','image/jpeg',(o.metadata->>'size')::bigint,auth.uid(),clock_timestamp()) returning id into a;
  insert into ncp_hinh_anh_lich_su(id_anh,id_ncp,thao_tac,nguoi_thuc_hien,ten_nguoi,ten_file)
   values(a,p_id_ncp,'them',auth.uid(),duc_ten_nguoi_hien_tai(),x->>'name');
  n:=n+1;
 end loop;
end $$;
revoke all on function public.ncp_anh_them(text,jsonb) from public,anon;
grant execute on function public.ncp_anh_them(text,jsonb) to authenticated;

create function public.ncp_anh_xoa(p_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare a ncp_hinh_anh%rowtype;
begin
 select * into a from ncp_hinh_anh where id=p_id;
 if not found then raise exception 'Không tìm thấy ảnh';end if;
 if not public.ncp_anh_duoc_sua(a.id_ncp) then raise exception 'Bạn không có quyền xóa hình ảnh phiếu này';end if;
 perform 1 from duc_ncp where id_ncp=a.id_ncp for update;
 update ncp_hinh_anh set xoa_luc=clock_timestamp(),nguoi_xoa=auth.uid() where id=p_id and xoa_luc is null;
 if found then
  insert into ncp_hinh_anh_lich_su(id_anh,id_ncp,thao_tac,nguoi_thuc_hien,ten_nguoi,ten_file)
   values(a.id,a.id_ncp,'xoa',auth.uid(),duc_ten_nguoi_hien_tai(),a.ten_file);
 end if;
end $$;
revoke all on function public.ncp_anh_xoa(uuid) from public,anon;
grant execute on function public.ncp_anh_xoa(uuid) to authenticated;

-- Wrap, don't replace, the existing creation routines. Retry cannot create a second case.
create function public.ncp_mo_phieu_co_anh(p_request_id uuid,p_mode text,p_data jsonb,p_images jsonb default '[]') returns jsonb
language plpgsql security definer set search_path=public as $$
declare r jsonb;v ncp_mo_phieu_yeu_cau%rowtype;body jsonb:=jsonb_build_object('mode',p_mode,'data',p_data,'images',p_images);
begin
 if auth.uid() is null or p_request_id is null then raise exception 'Cần đăng nhập và mã yêu cầu';end if;
 if p_images is null or jsonb_typeof(p_images)<>'array' then raise exception 'Ảnh không hợp lệ';end if;
 if jsonb_array_length(p_images)>0 and not public.ncp_anh_duoc_sua() then raise exception 'Bạn không có quyền thêm ảnh';end if;
 perform pg_advisory_xact_lock(hashtextextended('ncp-images:'||p_request_id::text,0));
 select * into v from ncp_mo_phieu_yeu_cau where request_id=p_request_id;
 if found then
  if v.nguoi_mo<>auth.uid() or v.noi_dung<>body then raise exception 'Yêu cầu đã lưu; mở lại phiếu để bổ sung hoặc chỉnh sửa';end if;
  return jsonb_build_object('ok',true,'id_ncp',v.id_ncp,'existing',true);
 end if;
 if p_mode='source' then
  r:=duc_ncp_open_source(p_data||jsonb_build_object('request_id',p_request_id,'images','[]'::jsonb));
 elsif p_mode='ng' then
  -- Serialize the checkpoint too; the old routine itself doesn't lock it.
  perform 1 from duc_ipqc_checkpoint where id_checkpoint=p_data->>'p_id_checkpoint_goc' for update;
  r:=duc_ncp_open_case(p_data->>'p_id_checkpoint_goc',p_data->>'p_ma_may',p_data->>'p_ma_sp',p_data->>'p_ten_sp',p_data->>'p_so_khuon',
   p_data->>'p_mo_ta_loi',(p_data->>'p_so_luong_nghi_van')::numeric,(p_data->>'p_so_luong_ng_du_kien')::numeric,
   p_data->>'p_vi_tri_cach_ly',p_data->>'p_nguoi_dam_nhiem',p_data->>'p_nguoi_dam_nhiem_doi_sach',null,
   nullif(p_data->>'p_han_tra_loi_doi_sach','')::date);
 else raise exception 'Nguồn phiếu không hợp lệ';end if;
 if coalesce((r->>'ok')::boolean,false)=false then raise exception '%',r->>'error';end if;
 if jsonb_array_length(p_images)>0 then perform public.ncp_anh_them(r->>'id_ncp',p_images);end if;
 insert into ncp_mo_phieu_yeu_cau values(p_request_id,auth.uid(),r->>'id_ncp',body);
 return r;
end $$;
revoke all on function public.ncp_mo_phieu_co_anh(uuid,text,jsonb,jsonb) from public,anon;
grant execute on function public.ncp_mo_phieu_co_anh(uuid,text,jsonb,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
