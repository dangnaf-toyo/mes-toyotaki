-- ============================================================================
-- T153: OQC "Kiểm tra sau Sơn" — ghi "Lần sơn" trên phiếu thay cho mã có đuôi -1
-- Trạng thái: Đã chạy STAGING 23/10/2026. Đã chạy PROD 23/10/2026.
-- (Lúc chạy trên Supabase ghi tên migration phase_T152_oqc_lan_son; đổi số T153 vì T152 đã dùng cho Bavia.)
--
-- Một mã sản phẩm cho mọi lần sơn; lần sơn lưu ở oqc_inspection_context.lan_son:
--   1 = hàng sơn mới, 2 = sơn lại hàng NG lần 1, 3+ = sơn lại tiếp. Chỉ có ở phạm vi POST_PAINTING.
-- Dùng để tính: NG lần 1, tỷ lệ OK ngay lần đầu (FPY), tỷ lệ sơn lại cứu được, tỷ lệ đạt cuối.
--
-- 1. Thêm cột lan_son (+ ràng buộc chỉ cho phạm vi sau sơn, 1..9).
-- 2. Phiếu sau sơn đã có: lan_son = 1.
-- 3. Dữ liệu import từ GSheet NHAP_GHE (ghi chú "[GSheet NHAP_GHE #...]"):
--    - mã có đuôi -1 → đổi về mã gốc, lan_son = 2, ghi chú giữ mã cũ;
--    - 6 dòng tên "Size … - S" nhưng mã không có -1 (STT 54, 94, 105, 199, 200, 220) → lan_son = 2
--      (chủ dự án xác nhận 23/10/2026 là hàng sơn lại).
--    Không có dữ liệu này (VD staging) thì bước 3 không làm gì.
-- 4. oqc_save_dashboard_inspection nhận p_data.lan_son. Thiếu khoá lan_son khi sửa phiếu sau sơn
--    → giữ lần sơn đã lưu (trình duyệt còn bản cũ không làm mất lần 2); phiếu mới thiếu → 1.
-- Chạy lại nhiều lần không sao.
-- ============================================================================
begin;

alter table public.oqc_inspection_context add column if not exists lan_son smallint;
alter table public.oqc_inspection_context drop constraint if exists oqc_inspection_context_lan_son_check;
alter table public.oqc_inspection_context add constraint oqc_inspection_context_lan_son_check
  check (lan_son is null or (inspection_scope = 'POST_PAINTING' and lan_son between 1 and 9));
comment on column public.oqc_inspection_context.lan_son is
  'Lần sơn (phạm vi POST_PAINTING): 1 = sơn mới, 2 = sơn lại hàng NG lần 1, 3+ = sơn lại tiếp';

update public.oqc_inspection_context set lan_son = 1
where inspection_scope = 'POST_PAINTING' and lan_son is null;

-- 3a. Mã -1 → mã gốc + lần 2 (ghi audit để truy vết)
with doi as (
  select i.id, i.product_code as ma_cu, regexp_replace(i.product_code, '-1$', '') as ma_moi
  from public.oqc_daily_inspection i
  where i.note like '[GSheet NHAP_GHE #%' and i.product_code ~ '-1$'
),
cu as (
  select d.*, to_jsonb(i) as old_data
  from doi d join public.oqc_daily_inspection i on i.id = d.id
),
sua as (
  update public.oqc_daily_inspection i
  set product_code = cu.ma_moi,
      product_name = coalesce(mp.ten_sp, i.product_name),
      note = i.note || ' (mã cũ ' || cu.ma_cu || ' = sơn lại)',
      updated_at = clock_timestamp()
  from cu left join public.master_products mp on mp.ma_sp = cu.ma_moi
  where i.id = cu.id
  returning i.id, to_jsonb(i) as new_data
)
insert into public.oqc_daily_inspection_audit (inspection_id, actor_id, actor_name, old_data, new_data)
select sua.id, '1dc89582-3bd7-459a-b8af-da9a7b76e5c0', 'Migration T153 (lần sơn)', cu.old_data, sua.new_data
from sua join cu on cu.id = sua.id;

update public.oqc_inspection_context c
set source_product_code = i.product_code, lan_son = 2, updated_at = clock_timestamp()
from public.oqc_daily_inspection i
where c.inspection_id = i.id and c.inspection_scope = 'POST_PAINTING'
  and i.note like '[GSheet NHAP_GHE #%(mã cũ %-1 = sơn lại)%';

-- 3b. Tên "… - S" nhưng mã không có -1
update public.oqc_inspection_context c
set lan_son = 2, updated_at = clock_timestamp()
from public.oqc_daily_inspection i
where c.inspection_id = i.id and c.inspection_scope = 'POST_PAINTING'
  and substring(i.note from '^\[GSheet NHAP_GHE #(\d+)\]') in ('54', '94', '105', '199', '200', '220');

-- 4. Hàm lưu báo cáo OQC: thêm lan_son (phần còn lại giữ nguyên bản đang chạy 23/10/2026)
CREATE OR REPLACE FUNCTION public.oqc_save_dashboard_inspection(p_id bigint, p_data jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d date:=(p_data->>'inspection_date')::date;code text:=p_data->>'product_code';total numeric;ng numeric;
 request uuid:=(p_data->>'request_id')::uuid;prior oqc_dashboard_write_request%rowtype; oldrow oqc_daily_inspection%rowtype;work oqc_inspection_work%rowtype;ctx oqc_inspection_context%rowtype;norm oqc_work_standard_version%rowtype;
 labor jsonb:=coalesce(p_data->'labor','[]'); normalized_labor jsonb:='[]';images jsonb:=coalesce(p_data->'images','[]');v_defects jsonb:=coalesce(p_data->'defects','[]');
 item jsonb;hours numeric;emp text;employee_name text;names text[]:='{}';primary_code text:=p_data->>'inspector_code';primary_name text;v_product_name text;actor text;scopevalue text:=nullif(p_data->>'scope','');v_id bigint;beforedata jsonb;allocated numeric;day date;mon date;col text;sourceid bigint;cfg public.oqc_planning_config_version%rowtype;cfg_id bigint;cfg_hours numeric;cfg_target numeric;
 v_lan_son smallint; -- T153
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
 -- T153: lần sơn chỉ cho phạm vi sau sơn, 1..9
 if nullif(p_data->>'lan_son','') is not null and (p_data->>'lan_son' !~ '^[1-9]$' or scopevalue is distinct from 'POST_PAINTING') then raise exception 'Lần sơn chỉ chọn 1–9 và chỉ dùng cho phạm vi Kiểm tra sau Sơn';end if;
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
 -- T153: thiếu lan_son khi sửa phiếu sau sơn → giữ lần đã lưu; phiếu mới → 1
 v_lan_son:=case when scopevalue='POST_PAINTING' then coalesce(nullif(p_data->>'lan_son','')::smallint,case when ctx.inspection_scope='POST_PAINTING' then ctx.lan_son end,1) end;
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
 insert into oqc_inspection_context(inspection_id,inspection_scope,source_date,source_product_code,standard_version_id,seconds_per_piece,updated_by,lan_son) values(v_id,scopevalue,d,code,norm.id,norm.seconds_per_piece,auth.uid(),v_lan_son) on conflict(inspection_id) do update set inspection_scope=excluded.inspection_scope,source_date=d,source_product_code=code,standard_version_id=norm.id,seconds_per_piece=norm.seconds_per_piece,updated_by=auth.uid(),updated_at=clock_timestamp(),lan_son=excluded.lan_son;
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
end$function$;

revoke execute on function public.oqc_save_dashboard_inspection(bigint, jsonb) from public, anon;
grant execute on function public.oqc_save_dashboard_inspection(bigint, jsonb) to authenticated;

commit;
