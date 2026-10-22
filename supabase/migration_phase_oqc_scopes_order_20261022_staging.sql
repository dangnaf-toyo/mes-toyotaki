-- STAGING ONLY jcjbleugnclzsghfpmvk. No business-data/catalog UPDATE/DELETE/backfill.
begin;
set local lock_timeout='5s';
alter table public.oqc_inspection_context drop constraint if exists oqc_inspection_context_inspection_scope_check;
alter table public.oqc_inspection_context add constraint oqc_inspection_context_inspection_scope_check check(inspection_scope in ('FULL_POST_MACHINING','POST_PAINTING','POST_OUTSOURCED_MACHINING','SAMPLING','OTHER'));
create table if not exists public.oqc_defect_order_version(
 id bigserial primary key,defect_codes text[] not null check(cardinality(defect_codes) between 1 and 200),
 created_by uuid not null references auth.users(id),created_by_name text not null,created_at timestamptz not null default clock_timestamp()
);
alter table public.oqc_defect_order_version enable row level security;
revoke all on public.oqc_defect_order_version from anon,authenticated;
grant select on public.oqc_defect_order_version to authenticated;
drop policy if exists "oqc defect order read" on public.oqc_defect_order_version;
create policy "oqc defect order read" on public.oqc_defect_order_version for select to authenticated using(auth.uid() is not null);
drop trigger if exists oqc_defect_order_immutable on public.oqc_defect_order_version;
create trigger oqc_defect_order_immutable before update or delete on public.oqc_defect_order_version for each row execute function public.oqc_capacity_immutable();
create or replace function public.oqc_save_defect_order(p_codes text[],p_expected_id bigint default null)
returns bigint language plpgsql security definer set search_path=public as $$
declare latest bigint;v_id bigint;expected text[];
begin
 if auth.uid() is null or not has_role('admin','qc_manager') then raise exception 'Không có quyền chỉnh thứ tự lỗi OQC';end if;
 if p_codes is null or cardinality(p_codes)<1 or cardinality(p_codes)>200 or cardinality(p_codes)<>(select count(distinct x) from unnest(p_codes) x) or array_position(p_codes,null) is not null then raise exception 'Danh sách thứ tự lỗi không hợp lệ';end if;
 select array_agg(code order by code) into expected from quality_defect_catalog where is_active and 'OQC'=any(processes) and defect_group='NG ngoại quan' and code<>'iqc_7f55011aff5e';
 if (select array_agg(x order by x) from unnest(p_codes) x) is distinct from expected then raise exception 'Danh mục lỗi đã thay đổi; tải lại trước khi lưu thứ tự';end if;
 perform pg_advisory_xact_lock(hashtextextended('oqc-defect-order',0));
 select id into latest from oqc_defect_order_version order by id desc limit 1;
 if latest is distinct from p_expected_id then raise exception 'Thứ tự đã thay đổi; tải lại trước khi lưu';end if;
 insert into oqc_defect_order_version(defect_codes,created_by,created_by_name) values(p_codes,auth.uid(),oqc_capacity_actor()) returning id into v_id;
 return v_id;
end$$;
create or replace function public.oqc_save_dashboard_inspection(p_id bigint,p_data jsonb)
returns bigint language plpgsql security definer set search_path=public as $$
declare d date:=(p_data->>'inspection_date')::date;code text:=p_data->>'product_code';total numeric;ng numeric;
 request uuid:=(p_data->>'request_id')::uuid;prior oqc_dashboard_write_request%rowtype; oldrow oqc_daily_inspection%rowtype;work oqc_inspection_work%rowtype;ctx oqc_inspection_context%rowtype;norm oqc_work_standard_version%rowtype;
 labor jsonb:=coalesce(p_data->'labor','[]'); normalized_labor jsonb:='[]';images jsonb:=coalesce(p_data->'images','[]');v_defects jsonb:=coalesce(p_data->'defects','[]');
 item jsonb;hours numeric;emp text;employee_name text;names text[]:='{}';primary_code text:=p_data->>'inspector_code';primary_name text;v_product_name text;actor text;scopevalue text:=nullif(p_data->>'scope','');v_id bigint;beforedata jsonb;allocated numeric;day date;mon date;col text;sourceid bigint;cfg public.oqc_planning_config_version%rowtype;cfg_id bigint;cfg_hours numeric;cfg_target numeric;
begin
 if auth.uid() is null or not has_role('admin','qc_manager','nhan_vien_oqc') then raise exception 'Không có quyền lưu báo cáo OQC';end if;
 if p_id is null and (scopevalue is null or scopevalue not in ('FULL_POST_MACHINING','POST_PAINTING','POST_OUTSOURCED_MACHINING')) then raise exception 'Chọn một trong ba phạm vi kiểm OQC';end if;
 if request is null then raise exception 'Thiếu mã lần gửi';end if;
 perform pg_advisory_xact_lock(hashtextextended('oqc-report:'||request::text,0));
 select * into prior from oqc_dashboard_write_request where request_id=request;
 if found then
  if prior.actor_id<>auth.uid() or prior.payload_hash<>md5(p_data::text) then raise exception 'Mã gửi đã được sử dụng cho nội dung khác';end if;
  return prior.inspection_id;
 end if;
 if d is null or nullif(trim(primary_code),'') is null or scopevalue is not null and scopevalue not in ('FULL_POST_MACHINING','POST_PAINTING','POST_OUTSOURCED_MACHINING','SAMPLING','OTHER') then raise exception 'Chọn ngày kiểm, người kiểm và phạm vi hợp lệ';end if;
 total:=oqc_capacity_number(p_data->>'total_qty');ng:=oqc_capacity_number(p_data->>'ng_qty',true);
 if total<>trunc(total) or ng<>trunc(ng) or ng>total then raise exception 'PCS đã kiểm và PCS NG phải là số nguyên; NG không vượt số đã kiểm';end if;
 select ten_sp into v_product_name from master_products where ma_sp=code;if not found then raise exception 'Chọn model từ danh mục trung tâm';end if;
 if p_id is not null then
  select * into oldrow from oqc_daily_inspection where oqc_daily_inspection.id=p_id for update;if not found then raise exception 'Không tìm thấy báo cáo gốc';end if;
  select * into work from oqc_inspection_work where inspection_id=p_id;
  select * into ctx from oqc_inspection_context where inspection_id=p_id;
 end if;
 begin primary_name:=oqc_dashboard_employee(primary_code);exception when raise_exception then if oldrow.id is not null and lower(primary_code)=lower(oldrow.inspector_code) then primary_name:=oldrow.inspector_name;else raise;end if;end;
 actor:=oqc_capacity_actor();
 if jsonb_typeof(v_defects) is distinct from 'array' or jsonb_array_length(v_defects)>200 then raise exception 'Danh sách lỗi không hợp lệ';end if;
 for item in select * from jsonb_array_elements(v_defects) loop
  allocated:=oqc_capacity_number(item->>'qty',true);
  if allocated<>trunc(allocated) or allocated>ng or nullif(trim(coalesce(item->>'label',item->>'code')),'') is null then raise exception 'Số PCS mắc từng lỗi phải nguyên, không âm và không vượt PCS NG';end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(v_defects) x group by coalesce(nullif(x->>'code',''),x->>'label') having sum((x->>'qty')::numeric)>ng) then raise exception 'Một loại lỗi không được có tổng PCS mắc lỗi vượt PCS NG';end if;
 if jsonb_typeof(images) is distinct from 'array' or jsonb_array_length(images)>10 or exists(select 1 from jsonb_array_elements_text(images) u where u is null or u !~ '^https://[^ ]+$') then raise exception 'Tối đa 10 ảnh, dùng liên kết HTTPS hợp lệ';end if;
 if p_id is not null then
  select * into oldrow from oqc_daily_inspection where oqc_daily_inspection.id=p_id for update;if not found then raise exception 'Không tìm thấy báo cáo gốc';end if;
  if nullif(p_data->>'expected_updated_at','') is null or (p_data->>'expected_updated_at')::timestamptz is distinct from oldrow.updated_at then raise exception 'Báo cáo đã thay đổi; tải lại trước khi sửa';end if;
  select * into work from oqc_inspection_work where inspection_id=p_id;
  select * into ctx from oqc_inspection_context where inspection_id=p_id;
  if (ctx.inspection_id is null or ctx.inspection_scope is null) and scopevalue is not null then raise exception 'Báo cáo cũ chưa xác định phạm vi; không tự gán sang kiểm 100%%';end if;
  beforedata:=jsonb_build_object('record',to_jsonb(oldrow),'work',case when work.inspection_id is null then null else to_jsonb(work) end,'context',case when ctx.inspection_id is null then null else to_jsonb(ctx) end);
 end if;
 for day in select distinct v from unnest(array[d,coalesce(oldrow.inspection_date,d)]) v order by v loop perform pg_advisory_xact_lock(hashtextextended('oqc-labor-day:'||day::text,0));end loop;
 if jsonb_typeof(labor) is distinct from 'array' or jsonb_array_length(labor)>100 then raise exception 'Danh sách giờ công không hợp lệ';end if;
 for item in select * from jsonb_array_elements(labor) loop
  emp:=trim(item->>'employee_code');if nullif(emp,'') is null or lower(emp)=any(names) then raise exception 'Chọn nhân viên trung tâm, mỗi người chỉ một dòng trong báo cáo';end if;
  hours:=oqc_capacity_number(item->>'hours');if hours>24 then raise exception 'Giờ thực tế/người không vượt 24 giờ/ngày';end if;
  names:=array_append(names,lower(emp));
  select coalesce(sum((l->>'hours')::numeric),0) into allocated from oqc_inspection_work w join oqc_daily_inspection r on r.id=w.inspection_id and r.inspection_date=w.source_date and r.product_code=w.source_product_code cross join lateral jsonb_array_elements(w.labor) l where w.source_date=d and (p_id is null or w.inspection_id<>p_id) and lower(l->>'employee_code')=lower(emp);
  if allocated+hours>24 then raise exception 'Nhân viên % đã phân bổ % giờ ngày này; tổng mới vượt 24 giờ. Chỉ nhập giờ riêng cho model này',emp,allocated;end if;
  begin employee_name:=oqc_dashboard_employee(emp);exception when raise_exception then select l->>'employee_name' into employee_name from jsonb_array_elements(coalesce(work.labor,'[]')) l where lower(l->>'employee_code')=lower(emp) limit 1;if employee_name is null then raise;end if;end;
  normalized_labor:=normalized_labor||jsonb_build_array(jsonb_build_object('employee_code',emp,'employee_name',employee_name,'hours',hours));
 end loop;
 if jsonb_array_length(labor)>0 and not lower(primary_code)=any(names) then raise exception 'Bổ sung giờ thực tế của người kiểm chính trong phân bổ giờ công';end if;
 if scopevalue='FULL_POST_MACHINING' then
  if work.inspection_id is not null and work.source_date=d and work.source_product_code=code and ctx.inspection_scope=scopevalue then norm.id:=work.standard_version_id;norm.seconds_per_piece:=work.seconds_per_piece;
  elsif p_id is not null and ctx.inspection_id is not null and ctx.source_date=d and ctx.source_product_code=code and ctx.inspection_scope=scopevalue then norm.id:=ctx.standard_version_id;norm.seconds_per_piece:=ctx.seconds_per_piece;
  else select * into norm from oqc_work_standard_version where product_code=code and effective_from<=d order by effective_from desc,id desc limit 1;end if;
 end if;
 if work.inspection_id is not null and work.source_date=d and work.source_product_code=code and ctx.inspection_scope is not distinct from scopevalue then
  cfg_id:=work.planning_config_version_id;cfg_hours:=work.planning_hours;cfg_target:=work.target_efficiency;
 elsif p_id is null then
  select * into cfg from oqc_planning_config_version where effective_from<=d order by effective_from desc,id desc limit 1;
  cfg_id:=cfg.id;cfg_hours:=cfg.planning_hours;cfg_target:=cfg.target_efficiency;
 end if;
 perform set_config('mes.oqc_dashboard_write',txid_current()::text,true);
 if p_id is null then
  insert into oqc_daily_inspection(inspection_date,shift,product_code,product_name,inspector_code,inspector_name,total_qty,ok_qty,ng_qty,defects,note,inspection_time,customer_code,customer_name,lot_no,task_no)
  values(d,p_data->>'shift',code,v_product_name,primary_code,primary_name,total,total-ng,ng,v_defects,p_data->>'note',nullif(p_data->>'inspection_time','')::time,p_data->>'customer_code',p_data->>'customer_name',p_data->>'lot_no',p_data->>'task_no') returning oqc_daily_inspection.id into v_id;
 else
  update oqc_daily_inspection set inspection_date=d,shift=p_data->>'shift',product_code=code,product_name=v_product_name,inspector_code=primary_code,inspector_name=primary_name,total_qty=total,ok_qty=total-ng,ng_qty=ng,defects=v_defects,note=p_data->>'note',inspection_time=case when p_data ? 'inspection_time' then nullif(p_data->>'inspection_time','')::time else oldrow.inspection_time end,customer_code=p_data->>'customer_code',customer_name=p_data->>'customer_name',lot_no=p_data->>'lot_no',task_no=p_data->>'task_no',updated_at=clock_timestamp() where oqc_daily_inspection.id=p_id returning oqc_daily_inspection.id into v_id;
  insert into oqc_daily_inspection_audit(inspection_id,actor_id,actor_name,old_data,new_data) values(v_id,auth.uid(),actor,to_jsonb(oldrow),(select to_jsonb(r) from oqc_daily_inspection r where r.id=v_id));
 end if;
 insert into oqc_inspection_context(inspection_id,inspection_scope,source_date,source_product_code,standard_version_id,seconds_per_piece,updated_by) values(v_id,scopevalue,d,code,norm.id,norm.seconds_per_piece,auth.uid()) on conflict(inspection_id) do update set inspection_scope=excluded.inspection_scope,source_date=d,source_product_code=code,standard_version_id=norm.id,seconds_per_piece=norm.seconds_per_piece,updated_by=auth.uid(),updated_at=clock_timestamp();
 insert into oqc_inspection_work(inspection_id,source_date,source_product_code,standard_version_id,seconds_per_piece,labor,images,updated_by,planning_config_version_id,planning_hours,target_efficiency) values(v_id,d,code,norm.id,norm.seconds_per_piece,normalized_labor,images,auth.uid(),cfg_id,cfg_hours,cfg_target) on conflict(inspection_id) do update set source_date=d,source_product_code=code,standard_version_id=norm.id,seconds_per_piece=norm.seconds_per_piece,labor=normalized_labor,images=excluded.images,planning_config_version_id=excluded.planning_config_version_id,planning_hours=excluded.planning_hours,target_efficiency=excluded.target_efficiency,updated_by=auth.uid(),updated_at=clock_timestamp();
 if scopevalue='FULL_POST_MACHINING' then
  mon:=d-(extract(isodow from d)::int-1);col:=(array['t2','t3','t4','t5','t6','t7','cn'])[extract(isodow from d)::int];
  select p.id into sourceid from cd_khsx_tuan_plan p where p.tuan_bat_dau=mon and p.cong_doan='OQC' and p.ma_sp=code and coalesce((to_jsonb(p)->>col)::numeric,0)>0;
  if sourceid is not null then insert into oqc_dashboard_plan_basis(work_date,product_code,source_plan_id,standard_version_id,seconds_per_piece,captured_by,planning_config_version_id,planning_hours,target_efficiency) values(d,code,sourceid,norm.id,norm.seconds_per_piece,auth.uid(),cfg_id,cfg_hours,cfg_target) on conflict(work_date,product_code) do nothing;end if;
 end if;
 insert into oqc_dashboard_audit(inspection_id,entity,actor_id,actor_name,before_data,after_data) values(v_id,'inspection',auth.uid(),actor,beforedata,jsonb_build_object('record',(select to_jsonb(r) from oqc_daily_inspection r where r.id=v_id),'work',(select to_jsonb(w) from oqc_inspection_work w where w.inspection_id=v_id),'context',(select to_jsonb(c) from oqc_inspection_context c where c.inspection_id=v_id)));
 insert into oqc_dashboard_write_request(request_id,inspection_id,actor_id,payload_hash) values(request,v_id,auth.uid(),md5(p_data::text));
 perform set_config('mes.oqc_dashboard_write','',true);
 return v_id;
end$$;
create or replace function public.oqc_dashboard_info() returns jsonb language plpgsql stable security definer set search_path=public as $$begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 return jsonb_build_object('version','oqc-dashboard-20261021','report_input_version',1,'planning_config_version',1,'inspection_scope_version',2,'can_standard',has_role('admin','qc_manager'),'can_actual',has_role('admin','qc_manager','nhan_vien_oqc'));
end$$;
revoke all on function public.oqc_save_defect_order(text[],bigint),public.oqc_dashboard_info() from public,anon;
grant execute on function public.oqc_save_defect_order(text[],bigint),public.oqc_dashboard_info() to authenticated;
notify pgrst,'reload schema';
commit;
