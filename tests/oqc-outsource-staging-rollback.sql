-- Chỉ chạy project staging jcjbleugnclzsghfpmvk. Mọi dữ liệu thử đều rollback.
begin;
do $$
declare actor uuid;src oqc_daily_inspection%rowtype;saved oqc_daily_inspection%rowtype;
 base jsonb;p jsonb;proc text;report_id bigint;legacy_id bigint;failed boolean;
begin
 select user_id into actor from user_roles where role='admin' order by user_id limit 1;
 select r.* into src from oqc_daily_inspection r join master_products m on m.ma_sp=r.product_code
  where not r.da_xoa
  order by r.id limit 1;
 if actor is null or src.id is null then raise exception 'Missing staging admin/reference OQC report';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 base:=to_jsonb(src)||jsonb_build_object('inspection_date',(now() at time zone 'Asia/Ho_Chi_Minh')::date,
  'total_qty',11,'defects','[]'::jsonb,'labor','[]'::jsonb,'images','[]'::jsonb,'so_nguoi_kiem',1,
  'inspection_hours',null,'scope','POST_OUTSOURCED_MACHINING','note','Rollback OQC subprocess test',
  'inspector_code',(select coalesce(nullif(username,''),user_id::text) from user_roles where user_id=actor),
  'request_id',gen_random_uuid(),'expected_updated_at',null);
 foreach proc in array array['ma','in','anode'] loop
  p:=base||jsonb_build_object('request_id',gen_random_uuid(),'cong_doan_gia_cong_ngoai',proc);
  report_id:=oqc_save_daily_report(null,p);
  if oqc_save_daily_report(null,p)<>report_id then raise exception 'Retry duplicated report';end if;
  select * into saved from oqc_daily_inspection where id=report_id;
  if saved.cong_doan_gia_cong_ngoai is distinct from proc then raise exception 'Subprocess not persisted: %',proc;end if;
  if not exists(select 1 from oqc_inspection_context where inspection_id=report_id
   and inspection_scope='POST_OUTSOURCED_MACHINING') then raise exception 'Scope not persisted';end if;
  if saved.ok_qty<>11 or saved.ng_qty<>0 then raise exception 'Incorrect saved OK/NG';end if;
  if current_setting('mes.oqc_dashboard_write',true)=txid_current()::text then raise exception 'Writer guard leaked';end if;
  failed:=false;
  begin update oqc_daily_inspection set note='Unauthorized legacy update' where id=report_id;
  exception when others then failed:=true;end;
  if not failed then raise exception 'Legacy writer guard was disabled';end if;
  p:=p||jsonb_build_object('request_id',gen_random_uuid(),'expected_updated_at',saved.updated_at,'note','Reopened correction');
  if oqc_save_daily_report(report_id,p)<>report_id then raise exception 'Edit created another report';end if;
  select * into saved from oqc_daily_inspection where id=report_id;
  if saved.cong_doan_gia_cong_ngoai is distinct from proc then raise exception 'Reopen/edit changed subprocess';end if;
  failed:=false;
  begin perform oqc_save_daily_report(report_id,p||jsonb_build_object(
   'request_id',gen_random_uuid(),'expected_updated_at',saved.updated_at,'cong_doan_gia_cong_ngoai',null));
  exception when others then failed:=true;end;
  if not failed then raise exception 'Classified report allowed clearing subprocess';end if;
 end loop;
 foreach proc in array array['','other','ma,in'] loop
  failed:=false;
  begin perform oqc_save_daily_report(null,base||jsonb_build_object(
   'request_id',gen_random_uuid(),'cong_doan_gia_cong_ngoai',proc));
  exception when others then failed:=true;end;
  if not failed then raise exception 'Invalid/missing/multiple subprocess accepted: %',proc;end if;
 end loop;
 -- Isolated historical-style NULL fixture; do not alter an existing report.
 legacy_id:=oqc_save_daily_report(null,base||jsonb_build_object(
  'request_id',gen_random_uuid(),'scope','FULL_POST_MACHINING','cong_doan_gia_cong_ngoai',null));
 update oqc_inspection_context set inspection_scope='POST_OUTSOURCED_MACHINING' where inspection_id=legacy_id;
 select * into saved from oqc_daily_inspection where id=legacy_id;
 perform oqc_save_daily_report(legacy_id,base||jsonb_build_object(
  'request_id',gen_random_uuid(),'expected_updated_at',saved.updated_at,'cong_doan_gia_cong_ngoai',null));
 if (select cong_doan_gia_cong_ngoai from oqc_daily_inspection where id=legacy_id)is not null
  then raise exception 'Legacy NULL was automatically classified';end if;
 if has_function_privilege('anon','public.oqc_save_daily_report(bigint,jsonb)','EXECUTE') then
  raise exception 'Anonymous writer is exposed';end if;
end $$;
rollback;
select 'PASS staging save/reload/edit Ma/In/Anode, reject missing/invalid/multiple choice, retain legacy NULL; all test writes rolled back' as result,
 count(*) as remaining_reports,md5(coalesce(jsonb_agg(to_jsonb(r) order by r.id)::text,'')) as report_checksum
from oqc_daily_inspection r;
