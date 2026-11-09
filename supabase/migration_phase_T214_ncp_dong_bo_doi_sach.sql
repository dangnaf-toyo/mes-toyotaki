-- T214: tích hợp đối sách cũ/mới; đã áp dụng STAGING 04/11/2026.
begin;
alter table public.ncp_doi_sach add column da_luu_tru boolean not null default false;
alter table public.ncp_doi_sach drop constraint ncp_doi_sach_id_ncp_nhom_cu_vi_tri_cu_key;
alter table public.ncp_doi_sach add constraint ncp_doi_sach_vi_tri_key
 unique(id_ncp,nhom_cu,vi_tri_cu) deferrable initially deferred;

-- Bỏ khỏi danh sách đang theo dõi, vẫn giữ bản ghi và toàn bộ lịch sử.
create or replace view public.ncp_doi_sach_theo_doi with(security_invoker=true) as
select d.id,d.id_ncp,d.loai,d.van_de,d.nguoi_phu_trach,d.noi_dung_tra_loi,
 d.han_tra_loi,d.tao_luc,d.tra_loi_luc,d.cap_nhat_luc,d.nguoi_tao_uid,
 d.nguoi_cap_nhat_uid,d.nhom_cu,d.vi_tri_cu,
 case when nullif(trim(d.noi_dung_tra_loi),'') is not null then 'da_tra_loi'
 when d.han_tra_loi<clock_timestamp() then 'qua_han' else 'chua_tra_loi' end as trang_thai,
 (d.tra_loi_luc>d.han_tra_loi) as tra_loi_muon
from public.ncp_doi_sach d where not d.da_luu_tru;

create or replace function public.ncp_ds_dong_bo_cu()
returns trigger language plpgsql security definer set search_path=public as $$
declare g record;e record;d ncp_doi_sach%rowtype;v uuid;kept uuid[];oldpos integer;
begin
 for g in select * from (values
 ('ps_tam_thoi',new.doi_sach_ps_tam_thoi_json,old.doi_sach_ps_tam_thoi_json),
 ('ps_lau_dai',new.doi_sach_ps_lau_dai_json,old.doi_sach_ps_lau_dai_json),
 ('lx_tam_thoi',new.doi_sach_lx_tam_thoi_json,old.doi_sach_lx_tam_thoi_json),
 ('lx_lau_dai',new.doi_sach_lx_lau_dai_json,old.doi_sach_lx_lau_dai_json))x(key,items,olditems) loop
  if g.items is not distinct from g.olditems then continue;end if;
  kept:='{}';
  for e in select value as v,ordinality::integer as ord
   from jsonb_array_elements(coalesce(g.items,'[]'))with ordinality loop
   v:=nullif(e.v->>'id_doi_sach','')::uuid;
   if v is null then
    -- Tương thích client cũ: ưu tiên nội dung cũ khi đổi thứ tự; sửa nội dung dùng vị trí cũ.
    select ordinality::integer into oldpos from jsonb_array_elements(coalesce(g.olditems,'[]'))with ordinality
     where value-'id_doi_sach'=e.v-'id_doi_sach'
     and exists(select 1 from ncp_doi_sach x where x.id_ncp=new.id_ncp and x.nhom_cu=g.key
      and x.vi_tri_cu=ordinality and not x.da_luu_tru and not(x.id=any(kept))) limit 1;
    select id into v from ncp_doi_sach where id_ncp=new.id_ncp and nhom_cu=g.key
     and vi_tri_cu=coalesce(oldpos,e.ord) and not da_luu_tru and not(id=any(kept));
   end if;
   v:=coalesce(v,gen_random_uuid());
   if v=any(kept) then raise exception 'Mỗi dòng đối sách phải có mã riêng';end if;
   select * into d from ncp_doi_sach where id=v;
   if found and (d.id_ncp<>new.id_ncp or d.nhom_cu is distinct from g.key) then
    raise exception 'Dòng đối sách không thuộc phiếu này';
   end if;
   if d.id is null then
    insert into ncp_doi_sach(id,id_ncp,van_de,nguoi_phu_trach,noi_dung_tra_loi,nhom_cu,vi_tri_cu)
    values(v,new.id_ncp,coalesce(new.mo_ta_loi,''),
     coalesce(nullif(e.v->>'nguoi_thuc_hien',''),new.nguoi_dam_nhiem_doi_sach),
     nullif(e.v->>'noi_dung',''),g.key,e.ord);
   else
    update ncp_doi_sach set vi_tri_cu=e.ord,da_luu_tru=false,
     noi_dung_tra_loi=nullif(e.v->>'noi_dung',''),
     nguoi_phu_trach=coalesce(nullif(e.v->>'nguoi_thuc_hien',''),new.nguoi_dam_nhiem_doi_sach)
    where id=v and (vi_tri_cu is distinct from e.ord or da_luu_tru
     or noi_dung_tra_loi is distinct from nullif(e.v->>'noi_dung','')
     or nguoi_phu_trach is distinct from coalesce(nullif(e.v->>'nguoi_thuc_hien',''),new.nguoi_dam_nhiem_doi_sach));
   end if;
   kept:=array_append(kept,v);
  end loop;
  update ncp_doi_sach set da_luu_tru=true,vi_tri_cu=null
   where id_ncp=new.id_ncp and nhom_cu=g.key and not da_luu_tru and not(id=any(kept));
 end loop;
 return new;
end $$;
revoke all on function public.ncp_ds_dong_bo_cu() from public,anon,authenticated;

alter function public.ncp_luu_doi_sach(uuid,jsonb) rename to ncp_luu_doi_sach_t212;
revoke all on function public.ncp_luu_doi_sach_t212(uuid,jsonb) from public,anon,authenticated;
create or replace function public.ncp_luu_doi_sach(p_id uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare d ncp_doi_sach%rowtype;r duc_ncp%rowtype;v uuid;items jsonb;field text;caseid text;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 if p_id is null then caseid:=p_data->>'id_ncp';
 else select id_ncp into caseid from ncp_doi_sach where id=p_id;end if;
 -- Cùng thứ tự khóa với luồng lưu phiếu cũ, tránh khóa chéo phiếu/đối sách.
 select * into r from duc_ncp where id_ncp=caseid for update;
 if p_id is not null then
  select * into d from ncp_doi_sach where id=p_id for update;
  if d.da_luu_tru then raise exception 'Dòng này đã bỏ khỏi phiếu; hãy tải lại';end if;
 end if;
 v:=ncp_luu_doi_sach_t212(p_id,p_data);
 if d.nhom_cu is not null then
  field:='doi_sach_'||d.nhom_cu||'_json';
  select jsonb_agg(case when ordinality=d.vi_tri_cu then value||jsonb_build_object(
   'id_doi_sach',v,'noi_dung',coalesce(p_data->>'noi_dung_tra_loi',''),
   'nguoi_thuc_hien',coalesce(p_data->>'nguoi_phu_trach','')) else value end order by ordinality)
   into items from jsonb_array_elements(to_jsonb(r)->field)with ordinality;
  execute format('update public.duc_ncp set %I=$1 where id_ncp=$2',field) using items,r.id_ncp;
 end if;
 return v;
end $$;
revoke all on function public.ncp_luu_doi_sach(uuid,jsonb) from public,anon;
grant execute on function public.ncp_luu_doi_sach(uuid,jsonb) to authenticated;

-- Trạng thái đã trả lời tách biệt khỏi việc phê duyệt đối sách.
-- Khi có nhiều dòng đang theo dõi, chỉ hoàn tất trả lời khi tất cả đều có nội dung.
create or replace function public.ncp_da_tra_loi(r public.duc_ncp)
returns boolean language sql stable set search_path=public as $$
 select case when exists(select 1 from ncp_doi_sach d where d.id_ncp=r.id_ncp and not d.da_luu_tru)
 then not exists(select 1 from ncp_doi_sach d where d.id_ncp=r.id_ncp and not d.da_luu_tru
  and nullif(trim(d.noi_dung_tra_loi),'') is null)
 else coalesce(r.rc_trang_thai_duyet in ('cho_duyet','da_duyet'),false) and exists(
  select 1 from jsonb_array_elements(coalesce(r.doi_sach_ps_tam_thoi_json,'[]')||
   coalesce(r.doi_sach_ps_lau_dai_json,'[]')||coalesce(r.doi_sach_lx_tam_thoi_json,'[]')||
   coalesce(r.doi_sach_lx_lau_dai_json,'[]')) e where nullif(trim(e->>'noi_dung'),'') is not null) end
$$;
revoke all on function public.ncp_da_tra_loi(public.duc_ncp) from public,anon;
grant execute on function public.ncp_da_tra_loi(public.duc_ncp) to authenticated;

create or replace function public.ncp_ds_hoan_tat_nhac_han()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if exists(select 1 from duc_ncp r where r.id_ncp=new.id_ncp and ncp_da_tra_loi(r)) then
  perform cv_pd_xong('ncp-han:'||new.id_ncp||':',true);
 end if;
 return new;
end $$;
revoke all on function public.ncp_ds_hoan_tat_nhac_han() from public,anon,authenticated;
create trigger ncp_ds_hoan_tat_nhac_han after insert or update on public.ncp_doi_sach
 for each row execute function public.ncp_ds_hoan_tat_nhac_han();
commit;
