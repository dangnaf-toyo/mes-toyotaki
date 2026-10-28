-- Run only against staging jcjbleugnclzsghfpmvk. All test writes roll back.
begin;
do $$
declare admin_id uuid; owner_id uuid; src public.oqc_daily_inspection; r public.oqc_daily_inspection;
 owner_report bigint:=-928102801; admin_report bigint:=-928102802; p jsonb;
begin
 select user_id into admin_id from public.user_roles where role='admin' order by user_id limit 1;
 select user_id into owner_id from public.user_roles where role='nhan_vien_oqc' order by user_id limit 1;
 if admin_id is null or owner_id is null then raise exception 'Missing existing staging test roles';end if;
 if exists(select 1 from oqc_daily_inspection where id in(owner_report,admin_report,owner_report-2)) then raise exception 'Test IDs already exist';end if;
 select o.* into src from oqc_daily_inspection o join master_products p on p.ma_sp=o.product_code where not o.da_xoa order by o.id limit 1;
 if src.id is null then raise exception 'Missing reference report';end if;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 insert into oqc_daily_inspection select (jsonb_populate_record(null::oqc_daily_inspection,to_jsonb(src)||jsonb_build_object('id',admin_report,'created_by',admin_id,'total_qty',10,'ok_qty',10,'ng_qty',0,'defects','[]'::jsonb,'note','Rollback Admin test','created_at',clock_timestamp(),'updated_at',clock_timestamp()))).*;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 insert into oqc_daily_inspection select (jsonb_populate_record(null::oqc_daily_inspection,to_jsonb(src)||jsonb_build_object('id',owner_report,'created_by',owner_id,'total_qty',10,'ok_qty',10,'ng_qty',0,'defects','[]'::jsonb,'note','Rollback owner test','created_at',clock_timestamp(),'updated_at',clock_timestamp()))).*;
 execute 'set local role authenticated';
 select * into r from oqc_daily_inspection where id=owner_report;
 p:=to_jsonb(r)||jsonb_build_object('scope',null,'labor','[]'::jsonb,'images','[]'::jsonb,'expected_updated_at',r.updated_at,'request_id',gen_random_uuid(),'note','Owner edit');
 perform oqc_save_dashboard_inspection(owner_report,p);
 select * into r from oqc_daily_inspection where id=admin_report;
 p:=to_jsonb(r)||jsonb_build_object('scope',null,'labor','[]'::jsonb,'images','[]'::jsonb,'expected_updated_at',r.updated_at,'request_id',gen_random_uuid());
 begin
  perform oqc_save_dashboard_inspection(admin_report,p);
  raise exception using errcode='ZX001',message='Other-owner edit accepted';
 exception when raise_exception then if sqlerrm not like '%người nhập%' then raise;end if;end;
 begin
  perform oqc_xoa_bao_cao(admin_report,r.updated_at);
  raise exception using errcode='ZX001',message='Other-owner delete accepted';
 exception when raise_exception then if sqlerrm not like '%người nhập%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 select * into r from oqc_daily_inspection where id=owner_report;
 p:=to_jsonb(r)||jsonb_build_object('scope',null,'labor','[]'::jsonb,'images','[]'::jsonb,'expected_updated_at',r.updated_at,'request_id',gen_random_uuid(),'note','Admin edit other owner');
 perform oqc_save_dashboard_inspection(owner_report,p);
 select * into r from oqc_daily_inspection where id=owner_report;
 if r.created_by<>owner_id then raise exception 'Creator changed by edit';end if;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 perform oqc_xoa_bao_cao(owner_report,r.updated_at);
 if exists(select 1 from oqc_daily_inspection where id=owner_report) then raise exception 'Deleted report still visible under RLS';end if;
 execute 'reset role';
 if not exists(select 1 from oqc_daily_inspection where id=owner_report and da_xoa and nguoi_xoa=owner_id) then raise exception 'Missing retained deletion record';end if;
 if not exists(select 1 from oqc_dashboard_audit where inspection_id=owner_report and entity='inspection_delete' and actor_id=owner_id) then raise exception 'Missing delete audit';end if;
 if not exists(select 1 from oqc_inspection_work where inspection_id=owner_report) then raise exception 'Historical work removed';end if;
 -- Admin can also remove someone else's report.
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 insert into oqc_daily_inspection select (jsonb_populate_record(null::oqc_daily_inspection,to_jsonb(src)||jsonb_build_object('id',owner_report-2,'created_by',owner_id,'total_qty',10,'ok_qty',10,'ng_qty',0,'defects','[]'::jsonb,'created_at',clock_timestamp(),'updated_at',clock_timestamp()))).*;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 execute 'set local role authenticated';
 select * into r from oqc_daily_inspection where id=owner_report-2;
 perform oqc_xoa_bao_cao(owner_report-2,r.updated_at);
 execute 'reset role';
end $$;
select 'PASS: owner edit/delete, foreign edit/delete denied, Admin edit, RLS deletion filter, retained record/work/audit; all writes rolled back' as result;
rollback;
