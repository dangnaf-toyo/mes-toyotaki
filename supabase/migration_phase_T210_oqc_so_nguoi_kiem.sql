-- T210: STAGING, chưa chạy. Không backfill số người hoặc thời gian lịch sử.
begin;
alter table public.oqc_daily_inspection add column if not exists so_nguoi_kiem integer check(so_nguoi_kiem>=1);
alter table public.oqc_daily_inspection add column if not exists gio_kiem_thuc_te numeric check(gio_kiem_thuc_te>0 and gio_kiem_thuc_te<=24);
CREATE OR REPLACE FUNCTION public.oqc_save_daily_report(p_id bigint, p_data jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_data jsonb:=p_data;v_ng numeric:=0;v_qty numeric;v_item jsonb;
 v_defects jsonb:=coalesce(p_data->'defects','[]');v_labor jsonb:=coalesce(p_data->'labor','[]');
 v_id bigint; v_before public.oqc_daily_inspection%rowtype;
 v_count integer; v_elapsed numeric;
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

 if p_data ? 'so_nguoi_kiem' then
  if coalesce(p_data->>'so_nguoi_kiem','') !~ '^[1-9][0-9]*$' then raise exception 'Số người kiểm tra phải là số nguyên dương'; end if;
  v_count:=(p_data->>'so_nguoi_kiem')::integer;
  if v_count<jsonb_array_length(v_labor) then raise exception 'Số người kiểm tra không được ít hơn số người đã ghi giờ riêng'; end if;
 end if;
 if nullif(p_data->>'inspection_hours','') is not null then v_elapsed:=oqc_capacity_number(p_data->>'inspection_hours'); end if;
 if p_id is not null then select * into v_before from oqc_daily_inspection where id=p_id; end if;
 v_id:=oqc_save_dashboard_inspection(p_id,v_data);
 update oqc_daily_inspection set
  so_nguoi_kiem=case when p_data ? 'so_nguoi_kiem' then v_count else so_nguoi_kiem end,
  gio_kiem_thuc_te=case when p_data ? 'inspection_hours' then v_elapsed else gio_kiem_thuc_te end
 where id=v_id and (so_nguoi_kiem is distinct from case when p_data ? 'so_nguoi_kiem' then v_count else so_nguoi_kiem end
 or gio_kiem_thuc_te is distinct from case when p_data ? 'inspection_hours' then v_elapsed else gio_kiem_thuc_te end);
 if found then
  insert into oqc_daily_inspection_audit(inspection_id,actor_id,actor_name,old_data,new_data)
  values(v_id,auth.uid(),oqc_capacity_actor(),to_jsonb(v_before),(select to_jsonb(r) from oqc_daily_inspection r where id=v_id));
 end if;
 return v_id;
end$function$
;
revoke all on function public.oqc_save_daily_report(bigint,jsonb) from public,anon;
grant execute on function public.oqc_save_daily_report(bigint,jsonb) to authenticated;
commit;
