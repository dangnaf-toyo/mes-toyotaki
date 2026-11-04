-- Đã áp dụng STAGING 04/11/2026. Giữ nguyên dữ liệu lịch sử.
begin;
alter table public.duc_ncp add column if not exists nguoi_cap_nhat_uid uuid;
create table public.ncp_doi_sach (
 id uuid primary key default gen_random_uuid(),id_ncp text not null references public.duc_ncp(id_ncp),
 loai text check(loai in ('noi_bo','khach_hang')),van_de text not null,nguoi_phu_trach text,
 noi_dung_tra_loi text,han_tra_loi timestamptz,tao_luc timestamptz,tra_loi_luc timestamptz,
 cap_nhat_luc timestamptz,nguoi_tao_uid uuid,nguoi_cap_nhat_uid uuid,
 nhom_cu text,vi_tri_cu integer,unique(id_ncp,nhom_cu,vi_tri_cu)
);
create table public.ncp_doi_sach_lich_su (
 id bigint generated always as identity primary key,id_doi_sach uuid references public.ncp_doi_sach(id),
 id_ncp text not null,nguoi_uid uuid,thoi_diem timestamptz not null default clock_timestamp(),
 nguoi_thuc_hien text,du_lieu_cu jsonb,du_lieu_moi jsonb
);
create table public.ncp_lich_su_han (
 id bigint generated always as identity primary key,id_ncp text not null,
 han_cu date,han_moi date,nguoi_uid uuid,nguoi_thuc_hien text,thoi_diem timestamptz not null default clock_timestamp()
);
-- Nội dung có sẵn được giữ nguyên; thời điểm trả lời/loại cũ chưa biết giữ NULL.
insert into public.ncp_doi_sach(id_ncp,van_de,nguoi_phu_trach,noi_dung_tra_loi,nhom_cu,vi_tri_cu)
select r.id_ncp,coalesce(r.mo_ta_loi,''),coalesce(nullif(e.v->>'nguoi_thuc_hien',''),r.nguoi_dam_nhiem_doi_sach),
 nullif(e.v->>'noi_dung',''),g.key,e.ord::integer
from public.duc_ncp r cross join lateral (values
 ('ps_tam_thoi',r.doi_sach_ps_tam_thoi_json),('ps_lau_dai',r.doi_sach_ps_lau_dai_json),
 ('lx_tam_thoi',r.doi_sach_lx_tam_thoi_json),('lx_lau_dai',r.doi_sach_lx_lau_dai_json))g(key,items)
cross join lateral jsonb_array_elements(coalesce(g.items,'[]')) with ordinality e(v,ord);
alter table public.ncp_doi_sach enable row level security;
alter table public.ncp_doi_sach_lich_su enable row level security;
alter table public.ncp_lich_su_han enable row level security;
create policy ncp_ds_doc on public.ncp_doi_sach for select to authenticated using(true);
create policy ncp_ds_ls_doc on public.ncp_doi_sach_lich_su for select to authenticated using(true);
create policy ncp_han_ls_doc on public.ncp_lich_su_han for select to authenticated using(true);
revoke all on public.ncp_doi_sach,public.ncp_doi_sach_lich_su,public.ncp_lich_su_han from anon,authenticated;
grant select on public.ncp_doi_sach,public.ncp_doi_sach_lich_su,public.ncp_lich_su_han to authenticated;

create function public.ncp_dau_thoi_gian()returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_table_name='duc_ncp' then
  if tg_op='INSERT' then new.ngay_tao:=clock_timestamp();new.nguoi_mo_uid:=auth.uid();
  else
   new.ngay_tao:=old.ngay_tao;
   if new.han_tra_loi_doi_sach is distinct from old.han_tra_loi_doi_sach then
    insert into ncp_lich_su_han(id_ncp,han_cu,han_moi,nguoi_uid,nguoi_thuc_hien)
    values(new.id_ncp,old.han_tra_loi_doi_sach,new.han_tra_loi_doi_sach,auth.uid(),(select coalesce(nullif(full_name,''),username) from user_roles where user_id=auth.uid()));
   end if;
  end if;
  new.last_updated_at:=clock_timestamp();new.nguoi_cap_nhat_uid:=auth.uid();
 else
  if tg_op='INSERT' then new.tao_luc:=clock_timestamp();new.nguoi_tao_uid:=auth.uid();
   new.tra_loi_luc:=case when nullif(trim(new.noi_dung_tra_loi),'') is not null then clock_timestamp() end;
  else
   new.tao_luc:=old.tao_luc;new.nguoi_tao_uid:=old.nguoi_tao_uid;
   new.tra_loi_luc:=case when nullif(trim(new.noi_dung_tra_loi),'') is null then null
    when nullif(trim(old.noi_dung_tra_loi),'') is null then clock_timestamp() else old.tra_loi_luc end;
  end if;
  new.cap_nhat_luc:=clock_timestamp();new.nguoi_cap_nhat_uid:=auth.uid();
 end if;
 return new;
end $$;
revoke all on function public.ncp_dau_thoi_gian() from public,anon,authenticated;
create trigger ncp_dau_thoi_gian before insert or update on public.duc_ncp for each row execute function public.ncp_dau_thoi_gian();
create trigger ncp_dau_thoi_gian before insert or update on public.ncp_doi_sach for each row execute function public.ncp_dau_thoi_gian();
create function public.ncp_ds_ghi_lich_su()returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into ncp_doi_sach_lich_su(id_doi_sach,id_ncp,nguoi_uid,nguoi_thuc_hien,du_lieu_cu,du_lieu_moi)
 values(new.id,new.id_ncp,auth.uid(),(select coalesce(nullif(full_name,''),username) from user_roles where user_id=auth.uid()),case when tg_op='UPDATE' then to_jsonb(old) end,to_jsonb(new));
 return new;
end $$;
revoke all on function public.ncp_ds_ghi_lich_su() from public,anon,authenticated;
create trigger ncp_ds_ghi_lich_su after insert or update on public.ncp_doi_sach for each row execute function public.ncp_ds_ghi_lich_su();

create view public.ncp_doi_sach_theo_doi with(security_invoker=true) as
select d.*,case when nullif(trim(d.noi_dung_tra_loi),'') is not null then 'da_tra_loi'
 when d.han_tra_loi<clock_timestamp() then 'qua_han' else 'chua_tra_loi' end as trang_thai,
 (d.tra_loi_luc>d.han_tra_loi) as tra_loi_muon from public.ncp_doi_sach d;
revoke all on public.ncp_doi_sach_theo_doi from public,anon;
grant select on public.ncp_doi_sach_theo_doi to authenticated;

create function public.ncp_luu_doi_sach(p_id uuid,p_data jsonb)returns uuid language plpgsql security definer set search_path=public as $$
declare r duc_ncp%rowtype;d ncp_doi_sach%rowtype;v uuid;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 if p_id is null then select * into r from duc_ncp where id_ncp=p_data->>'id_ncp' for update;
 else select * into d from ncp_doi_sach where id=p_id for update;select * into r from duc_ncp where id_ncp=d.id_ncp for update;end if;
 if r.id_ncp is null then raise exception 'Không tìm thấy phiếu';end if;
 if not(has_role('admin','qc_manager','giam_doc_sx','ipqc') or auth.uid()=r.nguoi_mo_uid
  or auth.uid()=any(cv_pd_ds_ten(r.nguoi_dam_nhiem_doi_sach)||cv_pd_ds_ten(d.nguoi_phu_trach))) then raise exception 'Chỉ người phụ trách, người mở phiếu hoặc quản lý QC được sửa';end if;
 if p_data->>'loai' is null or p_data->>'loai' not in ('noi_bo','khach_hang') then raise exception 'Chọn loại đối sách nội bộ hoặc khách hàng';end if;
 if nullif(trim(p_data->>'van_de'),'') is null then raise exception 'Nhập nội dung vấn đề';end if;
 if nullif(trim(p_data->>'nguoi_phu_trach'),'') is not null and p_data->>'nguoi_phu_trach' is distinct from d.nguoi_phu_trach
  and coalesce(array_length(cv_pd_ds_ten(p_data->>'nguoi_phu_trach'),1),0)=0 then raise exception 'Chọn người phụ trách từ danh sách nhân sự';end if;
 if p_id is not null and nullif(p_data->>'cap_nhat_luc','')::timestamptz is distinct from d.cap_nhat_luc then raise exception 'Đối sách đã thay đổi; tải lại trước khi sửa';end if;
 if p_id is null then
  insert into ncp_doi_sach(id_ncp,loai,van_de,nguoi_phu_trach,han_tra_loi,noi_dung_tra_loi)
  values(r.id_ncp,p_data->>'loai',trim(p_data->>'van_de'),p_data->>'nguoi_phu_trach',nullif(p_data->>'han_tra_loi','')::timestamptz,p_data->>'noi_dung_tra_loi')returning id into v;
 else
  update ncp_doi_sach set loai=p_data->>'loai',van_de=trim(p_data->>'van_de'),nguoi_phu_trach=p_data->>'nguoi_phu_trach',
   han_tra_loi=nullif(p_data->>'han_tra_loi','')::timestamptz,noi_dung_tra_loi=p_data->>'noi_dung_tra_loi' where id=p_id returning id into v;
 end if;
 return v;
end $$;
revoke all on function public.ncp_luu_doi_sach(uuid,jsonb) from public,anon;
grant execute on function public.ncp_luu_doi_sach(uuid,jsonb) to authenticated;
create function public.ncp_ds_dong_bo_cu()returns trigger language plpgsql security definer set search_path=public as $$
declare g record;e record;prev jsonb;
begin
 for g in select * from (values
 ('ps_tam_thoi',new.doi_sach_ps_tam_thoi_json,old.doi_sach_ps_tam_thoi_json),('ps_lau_dai',new.doi_sach_ps_lau_dai_json,old.doi_sach_ps_lau_dai_json),
 ('lx_tam_thoi',new.doi_sach_lx_tam_thoi_json,old.doi_sach_lx_tam_thoi_json),('lx_lau_dai',new.doi_sach_lx_lau_dai_json,old.doi_sach_lx_lau_dai_json))x(key,items,olditems) loop
  for e in select v,ord from jsonb_array_elements(coalesce(g.items,'[]'))with ordinality x(v,ord) loop
   prev:=coalesce(g.olditems,'[]')->(e.ord::integer-1);
   if e.v is not distinct from prev then continue;end if;
   insert into ncp_doi_sach(id_ncp,van_de,nguoi_phu_trach,noi_dung_tra_loi,nhom_cu,vi_tri_cu)
   values(new.id_ncp,coalesce(new.mo_ta_loi,''),coalesce(nullif(e.v->>'nguoi_thuc_hien',''),new.nguoi_dam_nhiem_doi_sach),nullif(e.v->>'noi_dung',''),g.key,e.ord::integer)
   on conflict(id_ncp,nhom_cu,vi_tri_cu)do update set noi_dung_tra_loi=excluded.noi_dung_tra_loi,nguoi_phu_trach=excluded.nguoi_phu_trach;
  end loop;
 end loop;
 return new;
end $$;
revoke all on function public.ncp_ds_dong_bo_cu() from public,anon,authenticated;
create trigger ncp_ds_dong_bo_cu after update of doi_sach_ps_tam_thoi_json,doi_sach_ps_lau_dai_json,doi_sach_lx_tam_thoi_json,doi_sach_lx_lau_dai_json
on public.duc_ncp for each row execute function public.ncp_ds_dong_bo_cu();
CREATE OR REPLACE FUNCTION public.duc_ncp_open_case(p_id_checkpoint_goc text, p_ma_may text, p_ma_sp text, p_ten_sp text, p_so_khuon text, p_mo_ta_loi text, p_so_luong_nghi_van numeric, p_so_luong_ng_du_kien numeric, p_vi_tri_cach_ly text, p_nguoi_dam_nhiem text, p_nguoi_dam_nhiem_doi_sach text, p_user text, p_han_tra_loi_doi_sach date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id_ncp text;
  v_existing text;
  v_now timestamptz := now();
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
  select coalesce(nullif(trim(username),''),email) into p_user from user_roles where user_id=auth.uid();
  if p_so_luong_nghi_van is null or p_so_luong_nghi_van <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Số lượng nghi vấn phải là số dương');
  end if;
  if p_so_luong_ng_du_kien is null or p_so_luong_ng_du_kien < 0 then
    return jsonb_build_object('ok', false, 'error', 'Số lượng NG dự kiến không được âm');
  end if;
  if p_so_luong_ng_du_kien > p_so_luong_nghi_van then
    return jsonb_build_object('ok', false, 'error', 'Số lượng NG dự kiến không được vượt quá số lượng nghi vấn');
  end if;

  if p_id_checkpoint_goc is not null and p_id_checkpoint_goc <> '' then
    select id_ncp_lien_quan into v_existing from duc_ipqc_checkpoint where id_checkpoint = p_id_checkpoint_goc;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'Không tìm thấy điểm kiểm gốc: ' || p_id_checkpoint_goc);
    end if;
    if v_existing is not null and v_existing <> '' then
      return jsonb_build_object('ok', false, 'error', 'Điểm kiểm này đã có phiếu xử lý (' || v_existing || ') — không mở trùng.');
    end if;
  end if;

  v_id_ncp := duc_ncp_so_quan_ly_moi();

  insert into duc_ncp (
    id_ncp, id_checkpoint_goc, ngay_tao, ma_may, ma_sp, ten_sp, so_khuon, mo_ta_loi,
    so_luong_nghi_van, so_luong_ng_du_kien, vi_tri_cach_ly, nguoi_mo_case,
    nguoi_dam_nhiem, nguoi_dam_nhiem_doi_sach, han_tra_loi_doi_sach, nguoi_mo_uid,
    so_luong_da_loc, so_luong_loc_ok, so_luong_loc_ng, so_luong_sua_ok, so_luong_sua_khong_duoc,
    so_luong_de_nghi_phe, so_luong_phe_da_duyet, trang_thai, rc_trang_thai_duyet, ghi_chu, last_updated_at
  ) values (
    v_id_ncp, nullif(p_id_checkpoint_goc, ''), v_now, p_ma_may, p_ma_sp, p_ten_sp, p_so_khuon, trim(p_mo_ta_loi),
    p_so_luong_nghi_van, p_so_luong_ng_du_kien, trim(p_vi_tri_cach_ly), p_user,
    trim(p_nguoi_dam_nhiem), trim(p_nguoi_dam_nhiem_doi_sach), p_han_tra_loi_doi_sach, auth.uid(),
    0, 0, 0, 0, 0, 0, 0, 'da_cach_ly', 'nhap',
    '[' || to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM HH24:MI') || '] Mở phiếu, cách ly ' ||
      p_so_luong_nghi_van || ' SP tại "' || trim(p_vi_tri_cach_ly) || '" — bởi ' || p_user,
    v_now
  );

  if p_id_checkpoint_goc is not null and p_id_checkpoint_goc <> '' then
    update duc_ipqc_checkpoint set id_ncp_lien_quan = v_id_ncp where id_checkpoint = p_id_checkpoint_goc;
  end if;

  return jsonb_build_object('ok', true, 'id_ncp', v_id_ncp);
end;
$function$
;
revoke all on function public.duc_ncp_open_case(text,text,text,text,text,text,numeric,numeric,text,text,text,text,date) from public,anon;
grant execute on function public.duc_ncp_open_case(text,text,text,text,text,text,numeric,numeric,text,text,text,text,date) to authenticated;
commit;
