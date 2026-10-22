-- STAGING ONLY: jcjbleugnclzsghfpmvk. Requires OQC dashboard 20261021.
-- Additive RPC; no table/column changes, data updates, deletes or history backfill.
begin;
create or replace function public.oqc_save_daily_report(p_id bigint,p_data jsonb)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_data jsonb:=p_data;v_ng numeric:=0;v_qty numeric;v_item jsonb;
 v_defects jsonb:=coalesce(p_data->'defects','[]');v_labor jsonb:=coalesce(p_data->'labor','[]');
 v_primary text:=p_data->>'inspector_code';v_hours numeric;
begin
 if auth.uid() is null or not has_role('admin','qc_manager','nhan_vien_oqc') then raise exception 'Không có quyền lưu báo cáo OQC';end if;
 if jsonb_typeof(v_defects) is distinct from 'array' then raise exception 'Danh sách lỗi không hợp lệ';end if;
 for v_item in select * from jsonb_array_elements(v_defects) loop
  v_qty:=oqc_capacity_number(v_item->>'qty',true);
  if v_qty<>trunc(v_qty) then raise exception 'Số lượng từng lỗi phải là số nguyên, không âm';end if;
  v_ng:=v_ng+v_qty;
 end loop;
 if p_id is null then
  if v_ng>oqc_capacity_number(p_data->>'total_qty') then raise exception 'Tổng NG không được lớn hơn số đã kiểm. Mỗi sản phẩm NG chỉ ghi một loại lỗi chính.';end if;
 else
  -- Historical NG is authoritative, including reports where defect counts overlap.
  select ng_qty into v_ng from oqc_daily_inspection where id=p_id for update;
  if not found then raise exception 'Không tìm thấy báo cáo gốc';end if;
 end if;
 v_data:=jsonb_set(v_data,'{ng_qty}',to_jsonb(v_ng));
 if jsonb_typeof(v_labor) is distinct from 'array' then raise exception 'Danh sách giờ công không hợp lệ';end if;
 if exists(select 1 from jsonb_array_elements(v_labor) l group by lower(l->>'employee_code') having count(*)>1) then raise exception 'Mỗi người kiểm chỉ có một dòng giờ công';end if;
 if p_data ? 'inspection_hours' then
  -- This is one person's allocated time; never multiply by employee count.
  select coalesce(jsonb_agg(l),'[]') into v_labor from jsonb_array_elements(v_labor) l where lower(l->>'employee_code') is distinct from lower(v_primary);
  if nullif(trim(p_data->>'inspection_hours'),'') is not null then
   v_hours:=oqc_capacity_number(replace(trim(p_data->>'inspection_hours'),',','.'));
   if v_hours>24 then raise exception 'Số giờ kiểm tra phải lớn hơn 0 và không vượt 24 giờ';end if;
   v_labor:=v_labor||jsonb_build_array(jsonb_build_object('employee_code',v_primary,'hours',v_hours));
  end if;
 end if;
 v_data:=jsonb_set(v_data,'{labor}',v_labor);
 -- Existing writer retains CAS, retry protection, staff validation, immutable CAPA,
 -- per-day hour limits, original IDs, photos, permissions and both audit trails.
 return oqc_save_dashboard_inspection(p_id,v_data);
end$$;
revoke all on function public.oqc_save_daily_report(bigint,jsonb) from public,anon;
grant execute on function public.oqc_save_daily_report(bigint,jsonb) to authenticated;
create or replace function public.oqc_dashboard_info() returns jsonb language plpgsql stable security definer set search_path=public as $$begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 return jsonb_build_object('version','oqc-dashboard-20261021','report_input_version',1,'planning_hours',7,'target_efficiency',.9,'can_standard',has_role('admin','qc_manager'),'can_actual',has_role('admin','qc_manager','nhan_vien_oqc'));
end$$;
revoke all on function public.oqc_dashboard_info() from public,anon;
grant execute on function public.oqc_dashboard_info() to authenticated;
notify pgrst,'reload schema';
commit;
