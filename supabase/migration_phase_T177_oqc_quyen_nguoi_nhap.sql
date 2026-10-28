-- T177 — Đã chạy STAGING 28/10/2026; chưa chạy production.
-- Owner/Admin edit + audited logical deletion of OQC reports.
-- No historical ownership backfill. Existing reports and audit rows are preserved.
begin;
alter table public.oqc_daily_inspection add column if not exists da_xoa boolean not null default false;
alter table public.oqc_daily_inspection add column if not exists ngay_xoa timestamptz;
alter table public.oqc_daily_inspection add column if not exists nguoi_xoa uuid;

create or replace function public.oqc_quyen_bao_cao() returns jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('version',177,'user_id',auth.uid(),'is_admin',has_role('admin'),
 'can_actual',auth.uid() is not null and has_role('admin','qc_manager','nhan_vien_oqc'))
 where auth.uid() is not null;
$$;
revoke all on function public.oqc_quyen_bao_cao() from public,anon;
grant execute on function public.oqc_quyen_bao_cao() to authenticated;

create or replace function public.oqc_bao_ve_nguoi_nhap() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if tg_op='DELETE' then raise exception 'Không xóa vĩnh viễn báo cáo OQC; dùng chức năng Xóa báo cáo';end if;
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 if tg_op='INSERT' then
  if new.created_by is not null and new.created_by<>auth.uid() then raise exception 'Không được giả mạo người nhập OQC';end if;
  new.created_by:=auth.uid();
  if new.da_xoa or new.ngay_xoa is not null or new.nguoi_xoa is not null then raise exception 'Thông tin xóa không hợp lệ';end if;
 else
  if not has_role('admin') and old.created_by is distinct from auth.uid() then raise exception 'Chỉ người nhập báo cáo hoặc Admin được sửa/xóa';end if;
  if old.da_xoa then raise exception 'Báo cáo OQC đã bị xóa';end if;
  if new.created_by is distinct from old.created_by then raise exception 'Không được thay đổi người nhập OQC';end if;
  if (new.da_xoa,new.ngay_xoa,new.nguoi_xoa) is distinct from (old.da_xoa,old.ngay_xoa,old.nguoi_xoa)
    and current_setting('mes.oqc_delete',true) is distinct from txid_current()::text then
    raise exception 'Dùng chức năng Xóa báo cáo OQC';
  end if;
 end if;
 return new;
end $$;
revoke all on function public.oqc_bao_ve_nguoi_nhap() from public,anon;
grant execute on function public.oqc_bao_ve_nguoi_nhap() to authenticated;
drop trigger if exists oqc_nguoi_nhap_guard on public.oqc_daily_inspection;
create trigger oqc_nguoi_nhap_guard before insert or update or delete on public.oqc_daily_inspection
for each row execute function public.oqc_bao_ve_nguoi_nhap();

drop policy if exists oqc_an_bao_cao_da_xoa on public.oqc_daily_inspection;
create policy oqc_an_bao_cao_da_xoa on public.oqc_daily_inspection as restrictive
for select to authenticated using(not da_xoa);

create or replace function public.oqc_xoa_bao_cao(p_id bigint,p_expected_updated_at timestamptz)
returns boolean language plpgsql security definer set search_path=public as $$
declare r public.oqc_daily_inspection; beforedata jsonb;
begin
 if auth.uid() is null or not has_role('admin','qc_manager','nhan_vien_oqc') then raise exception 'Không có quyền xóa báo cáo OQC';end if;
 select * into r from oqc_daily_inspection where id=p_id for update;
 if not found then raise exception 'Không tìm thấy báo cáo OQC';end if;
 if not has_role('admin') and r.created_by is distinct from auth.uid() then raise exception 'Chỉ người nhập báo cáo hoặc Admin được sửa/xóa';end if;
 if r.da_xoa then return true;end if;
 if p_expected_updated_at is null or p_expected_updated_at is distinct from r.updated_at then raise exception 'Báo cáo đã thay đổi; tải lại trước khi xóa';end if;
 beforedata:=jsonb_build_object('record',to_jsonb(r),'work',(select to_jsonb(w) from oqc_inspection_work w where inspection_id=p_id),'context',(select to_jsonb(c) from oqc_inspection_context c where inspection_id=p_id));
 perform set_config('mes.oqc_dashboard_write',txid_current()::text,true);
 perform set_config('mes.oqc_delete',txid_current()::text,true);
 update oqc_daily_inspection set da_xoa=true,ngay_xoa=clock_timestamp(),nguoi_xoa=auth.uid(),updated_at=clock_timestamp() where id=p_id;
 insert into oqc_dashboard_audit(inspection_id,entity,actor_id,actor_name,before_data,after_data)
 values(p_id,'inspection_delete',auth.uid(),oqc_capacity_actor(),beforedata,
 jsonb_build_object('record',(select to_jsonb(x) from oqc_daily_inspection x where id=p_id)));
 return true;
end $$;
revoke all on function public.oqc_xoa_bao_cao(bigint,timestamptz) from public,anon;
grant execute on function public.oqc_xoa_bao_cao(bigint,timestamptz) to authenticated;

-- Existing SECURITY DEFINER readers bypass RLS. Filter only their OQC source;
-- preserve all other totals, plans, thresholds, scopes and business rules.
do $$declare proc regprocedure; source text; updated text; name text;
begin
 foreach name in array array['oqc_capacity_report(date)','tong_quan_hom_nay(text)','wallboard_pchart(text)'] loop
  proc:=to_regprocedure('public.'||name);if proc is null then continue;end if;
  select pg_get_functiondef(proc) into source;
  if source like '%where not da_xoa%' then continue;end if;
  updated:=regexp_replace(source,'from\s+(public\.)?oqc_daily_inspection\s','from (select * from public.oqc_daily_inspection where not da_xoa) ','gi');
  if updated=source then raise exception 'Không nhận diện được nguồn OQC của %',name;end if;
  execute updated;
 end loop;
 proc:='public.oqc_save_dashboard_inspection(bigint,jsonb)'::regprocedure;
 select pg_get_functiondef(proc) into source;
 if source not like '%where not da_xoa%' then
  updated:=replace(source,'join oqc_daily_inspection r on','join (select * from public.oqc_daily_inspection where not da_xoa) r on');
  if updated=source then raise exception 'Không nhận diện được truy vấn giờ công OQC';end if;
  execute updated;
 end if;
end $$;
notify pgrst,'reload schema';
commit;
