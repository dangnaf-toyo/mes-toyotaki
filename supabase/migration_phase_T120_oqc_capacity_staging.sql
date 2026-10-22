-- T120. STAGING ONLY: jcjbleugnclzsghfpmvk. Requires T67 + T73; independent of T118.
-- Additive sidecar data. No UPDATE/DELETE/backfill of existing OQC records or masters.
begin;
do $$begin
 if to_regprocedure('public.oqc_save_daily_inspection_qc_v2(bigint,jsonb,text)') is null then
   raise exception 'Cần T73 OQC trước T120';
 end if;
end$$;
create table if not exists public.oqc_work_standard_version(
 id bigserial primary key, product_code text not null references public.master_products(ma_sp),
 effective_from date not null, steps jsonb not null, seconds_per_piece numeric not null check(seconds_per_piece>0 and seconds_per_piece<1e9),
 created_by uuid not null references auth.users(id), created_by_name text not null, created_at timestamptz not null default now()
);
create index if not exists oqc_standard_effective on public.oqc_work_standard_version(product_code,effective_from desc,id desc);
create table if not exists public.oqc_capacity_day(
 work_date date primary key, hours_per_person numeric not null check(hours_per_person>0 and hours_per_person<=24),
 revision integer not null default 1, updated_by uuid not null references auth.users(id), updated_at timestamptz not null default now()
);
create table if not exists public.oqc_capacity_plan(
 work_date date not null references public.oqc_capacity_day(work_date), product_code text not null references public.master_products(ma_sp),
 planned_qty numeric not null check(planned_qty>0 and planned_qty=trunc(planned_qty) and planned_qty<1e12),
 standard_version_id bigint not null references public.oqc_work_standard_version(id), seconds_per_piece numeric not null check(seconds_per_piece>0 and seconds_per_piece<1e9),
 updated_by uuid not null references auth.users(id), updated_at timestamptz not null default now(), primary key(work_date,product_code)
);
create table if not exists public.oqc_capacity_labor(
 work_date date primary key, groups jsonb not null, labor_seconds numeric not null check(labor_seconds>0 and labor_seconds<1e12),
 confirmed_by uuid not null references auth.users(id), confirmed_by_name text not null, confirmed_at timestamptz not null default now()
);
create table if not exists public.oqc_inspection_context(
 inspection_id bigint primary key references public.oqc_daily_inspection(id),
 inspection_scope text check(inspection_scope in ('FULL_POST_MACHINING','SAMPLING','OTHER')),
 source_date date not null, source_product_code text not null,
 standard_version_id bigint references public.oqc_work_standard_version(id), seconds_per_piece numeric,
 updated_by uuid not null references auth.users(id), updated_at timestamptz not null default now(),
 check((standard_version_id is null and seconds_per_piece is null) or (standard_version_id is not null and seconds_per_piece>0 and seconds_per_piece<1e9))
);
create table if not exists public.oqc_capacity_audit(
 id bigserial primary key, entity text not null, record_key text not null, before_data jsonb, after_data jsonb,
 actor_id uuid not null references auth.users(id), actor_name text not null, changed_at timestamptz not null default now()
);
do $$declare t text;begin
 foreach t in array array['oqc_work_standard_version','oqc_capacity_day','oqc_capacity_plan','oqc_capacity_labor','oqc_inspection_context','oqc_capacity_audit'] loop
   execute format('alter table public.%I enable row level security',t);
   execute format('revoke all on public.%I from anon,authenticated',t);
   execute format('grant select on public.%I to authenticated',t);
   execute format('drop policy if exists "oqc capacity read" on public.%I',t);
   execute format('create policy "oqc capacity read" on public.%I for select to authenticated using(auth.uid() is not null)',t);
 end loop;
end$$;
create or replace function public.oqc_capacity_immutable() returns trigger language plpgsql as $$begin
 raise exception 'Phiên bản định mức và lịch sử không được sửa/xóa. Hãy lưu phiên bản mới.';
end$$;
drop trigger if exists oqc_standard_immutable on public.oqc_work_standard_version;
create trigger oqc_standard_immutable before update or delete on public.oqc_work_standard_version for each row execute function public.oqc_capacity_immutable();
drop trigger if exists oqc_capacity_audit_immutable on public.oqc_capacity_audit;
create trigger oqc_capacity_audit_immutable before update or delete on public.oqc_capacity_audit for each row execute function public.oqc_capacity_immutable();

create or replace function public.oqc_capacity_number(p_value text,p_zero boolean default false)
returns numeric language plpgsql immutable as $$declare n numeric;begin
 if p_value is null or length(p_value)>24 or p_value !~ '^[0-9]+([.][0-9]+)?$' then raise exception 'Giá trị phải là số hữu hạn hợp lệ';end if;
 n:=p_value::numeric;if (p_zero and n<0) or (not p_zero and n<=0) or n>=1e12 then raise exception 'Giá trị phải lớn hơn 0 và trong giới hạn cho phép';end if;return n;
end$$;
create or replace function public.oqc_capacity_actor() returns text language sql stable security definer set search_path=public as $$
 select coalesce((select coalesce(full_name,username) from user_roles where user_id=auth.uid() limit 1),auth.uid()::text)
$$;
create or replace function public.oqc_capacity_info() returns jsonb language plpgsql stable security definer set search_path=public as $$begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 return jsonb_build_object('version',120,'can_standard',has_role('admin','qc_manager'),'can_plan',has_role('admin','qc_manager','nhan_vien_oqc','ke_hoach','qlsx_truong_phong'),'can_actual',has_role('admin','qc_manager','nhan_vien_oqc'));
end$$;
create or replace function public.oqc_save_work_standard(p_product text,p_effective date,p_steps jsonb)
returns bigint language plpgsql security definer set search_path=public as $$declare step jsonb;total numeric:=0;v_id bigint;begin
 if auth.uid() is null or not has_role('admin','qc_manager') then raise exception 'Không có quyền sửa định mức OQC';end if;
 if p_effective is null or not exists(select 1 from master_products where ma_sp=p_product) then raise exception 'Chọn model từ danh mục và ngày hiệu lực';end if;
 if jsonb_typeof(p_steps) is distinct from 'array' or jsonb_array_length(p_steps)=0 or jsonb_array_length(p_steps)>100 then raise exception 'Cần từ 1 đến 100 bước kiểm';end if;
 for step in select value from jsonb_array_elements(p_steps) loop
   if jsonb_typeof(step) is distinct from 'object' or nullif(trim(step->>'name'),'') is null or length(step->>'name')>200 then raise exception 'Nhập tên cho từng bước kiểm';end if;
   total:=total+oqc_capacity_number(step->>'seconds');
 end loop;
 if total>=1e9 then raise exception 'Tổng giây/PCS vượt giới hạn';end if;
 insert into oqc_work_standard_version(product_code,effective_from,steps,seconds_per_piece,created_by,created_by_name)
 values(p_product,p_effective,p_steps,total,auth.uid(),oqc_capacity_actor()) returning id into v_id;
 insert into oqc_capacity_audit(entity,record_key,after_data,actor_id,actor_name) values('standard',v_id::text,(select to_jsonb(v) from oqc_work_standard_version v where id=v_id),auth.uid(),oqc_capacity_actor());
 return v_id;
end$$;
create or replace function public.oqc_save_capacity_plan(p_date date,p_product text,p_qty text,p_hours text,p_revision integer)
returns integer language plpgsql security definer set search_path=public as $$
declare dayrow oqc_capacity_day%rowtype; item oqc_capacity_plan%rowtype; standard oqc_work_standard_version%rowtype;qty numeric;hours numeric;beforeday jsonb;beforeitem jsonb;begin
 if auth.uid() is null or not has_role('admin','qc_manager','nhan_vien_oqc','ke_hoach','qlsx_truong_phong') then raise exception 'Không có quyền lập kế hoạch OQC';end if;
 qty:=oqc_capacity_number(p_qty);hours:=oqc_capacity_number(p_hours);
 if p_date is null or qty<>trunc(qty) or hours>24 then raise exception 'Chọn ngày, số lượng PCS nguyên và giờ/người trong khoảng (0,24]';end if;
 perform pg_advisory_xact_lock(hashtextextended('oqc-plan:'||p_date::text,0));
 select * into dayrow from oqc_capacity_day where work_date=p_date for update;
 if coalesce(p_revision,-1)<>coalesce(dayrow.revision,0) then raise exception 'Kế hoạch đã thay đổi. Tải lại trước khi lưu.';end if;
 beforeday:=case when dayrow.work_date is null then null else to_jsonb(dayrow) end;
 select * into item from oqc_capacity_plan where work_date=p_date and product_code=p_product;
 if found then standard.id:=item.standard_version_id;standard.seconds_per_piece:=item.seconds_per_piece;beforeitem:=to_jsonb(item);
 else select * into standard from oqc_work_standard_version where product_code=p_product and effective_from<=p_date order by effective_from desc,id desc limit 1;end if;
 if standard.id is null then raise exception 'Model chưa có định mức hiệu lực tại ngày kế hoạch';end if;
 insert into oqc_capacity_day(work_date,hours_per_person,updated_by) values(p_date,hours,auth.uid())
 on conflict(work_date) do update set hours_per_person=excluded.hours_per_person,revision=oqc_capacity_day.revision+1,updated_by=auth.uid(),updated_at=now() returning * into dayrow;
 insert into oqc_capacity_plan(work_date,product_code,planned_qty,standard_version_id,seconds_per_piece,updated_by) values(p_date,p_product,qty,standard.id,standard.seconds_per_piece,auth.uid())
 on conflict(work_date,product_code) do update set planned_qty=excluded.planned_qty,updated_by=auth.uid(),updated_at=now();
 insert into oqc_capacity_audit(entity,record_key,before_data,after_data,actor_id,actor_name) values('plan',p_date||':'||p_product,jsonb_build_object('day',beforeday,'item',beforeitem),jsonb_build_object('day',to_jsonb(dayrow),'item',(select to_jsonb(v) from oqc_capacity_plan v where work_date=p_date and product_code=p_product)),auth.uid(),oqc_capacity_actor());
 return dayrow.revision;
end$$;
create or replace function public.oqc_save_capacity_labor(p_date date,p_groups jsonb)
returns void language plpgsql security definer set search_path=public as $$declare g jsonb;secs numeric:=0;people numeric;hours numeric;beforedata jsonb;begin
 if auth.uid() is null or not has_role('admin','qc_manager','nhan_vien_oqc') then raise exception 'Không có quyền xác nhận nhân lực thực tế OQC';end if;
 if p_date is null or jsonb_typeof(p_groups) is distinct from 'array' or jsonb_array_length(p_groups)=0 or jsonb_array_length(p_groups)>100 then raise exception 'Nhập ít nhất một nhóm nhân lực thực tế';end if;
 for g in select value from jsonb_array_elements(p_groups) loop
   people:=oqc_capacity_number(g->>'people');hours:=oqc_capacity_number(g->>'hours');
   if hours>24 or people>10000 then raise exception 'Kiểm tra lại số người và giờ thực tế';end if;
   secs:=secs+people*hours*3600;
 end loop;
 perform pg_advisory_xact_lock(hashtextextended('oqc-labor:'||p_date::text,0));
 select to_jsonb(v) into beforedata from oqc_capacity_labor v where work_date=p_date for update;
 insert into oqc_capacity_labor(work_date,groups,labor_seconds,confirmed_by,confirmed_by_name) values(p_date,p_groups,secs,auth.uid(),oqc_capacity_actor())
 on conflict(work_date) do update set groups=excluded.groups,labor_seconds=excluded.labor_seconds,confirmed_by=auth.uid(),confirmed_by_name=oqc_capacity_actor(),confirmed_at=now();
 insert into oqc_capacity_audit(entity,record_key,before_data,after_data,actor_id,actor_name) values('labor',p_date::text,beforedata,(select to_jsonb(v) from oqc_capacity_labor v where work_date=p_date),auth.uid(),oqc_capacity_actor());
end$$;
create or replace function public.oqc_save_scoped_inspection(p_id bigint,p_data jsonb,p_actor text,p_scope text)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_id bigint;ctx oqc_inspection_context%rowtype;standard oqc_work_standard_version%rowtype;oldctx jsonb;scopevalue text:=nullif(p_scope,'');begin
 if auth.uid() is null or not has_role('admin','qc_manager','nhan_vien_oqc') then raise exception 'Không có quyền nhập kết quả OQC theo phạm vi';end if;
 if scopevalue is not null and scopevalue not in ('FULL_POST_MACHINING','SAMPLING','OTHER') then raise exception 'Phạm vi kiểm không hợp lệ';end if;
 if p_id is not null then
   perform 1 from oqc_daily_inspection where id=p_id for update;
   select * into ctx from oqc_inspection_context where inspection_id=p_id;
   if not found and scopevalue is not null then raise exception 'Dữ liệu cũ chưa xác định phạm vi. Không tự gán phạm vi hoặc định mức.';end if;
   oldctx:=case when ctx.inspection_id is null then null else to_jsonb(ctx) end;
 end if;
 if ctx.inspection_id is not null and ctx.source_date=(p_data->>'inspection_date')::date and ctx.source_product_code=p_data->>'product_code' and ctx.inspection_scope is not distinct from scopevalue then
   standard.id:=ctx.standard_version_id;standard.seconds_per_piece:=ctx.seconds_per_piece;
 elsif scopevalue='FULL_POST_MACHINING' then
   select * into standard from oqc_work_standard_version where product_code=p_data->>'product_code' and effective_from<=(p_data->>'inspection_date')::date order by effective_from desc,id desc limit 1;
 end if;
 v_id:=oqc_save_daily_inspection_qc_v2(p_id,p_data,p_actor);
 insert into oqc_inspection_context(inspection_id,inspection_scope,source_date,source_product_code,standard_version_id,seconds_per_piece,updated_by)
 values(v_id,scopevalue,(p_data->>'inspection_date')::date,p_data->>'product_code',standard.id,standard.seconds_per_piece,auth.uid())
 on conflict(inspection_id) do update set inspection_scope=excluded.inspection_scope,source_date=excluded.source_date,source_product_code=excluded.source_product_code,standard_version_id=excluded.standard_version_id,seconds_per_piece=excluded.seconds_per_piece,updated_by=auth.uid(),updated_at=now();
 insert into oqc_capacity_audit(entity,record_key,before_data,after_data,actor_id,actor_name) values('inspection_scope',v_id::text,oldctx,(select to_jsonb(v) from oqc_inspection_context v where inspection_id=v_id),auth.uid(),oqc_capacity_actor());
 return v_id;
end$$;
create or replace function public.oqc_capacity_report(p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$declare result jsonb;begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 select jsonb_build_object('date',p_date,'day',(select to_jsonb(d) from oqc_capacity_day d where work_date=p_date),
 'plans',coalesce((select jsonb_agg(to_jsonb(p) order by product_code) from oqc_capacity_plan p where work_date=p_date),'[]'::jsonb),
 'labor',(select to_jsonb(l) from oqc_capacity_labor l where work_date=p_date),
 'results',coalesce((select jsonb_agg(to_jsonb(s)) from (
   select o.product_code,sum(o.ok_qty+o.ng_qty) as checked_qty,
   sum((o.ok_qty+o.ng_qty)*c.seconds_per_piece) as earned_seconds,
   count(*) filter(where c.standard_version_id is null) as unrated_records,
   jsonb_agg(distinct c.standard_version_id) as standard_versions
   from oqc_daily_inspection o join oqc_inspection_context c on c.inspection_id=o.id and c.source_date=o.inspection_date and c.source_product_code=o.product_code
   where o.inspection_date=p_date and c.inspection_scope='FULL_POST_MACHINING' group by o.product_code
 )s),'[]'::jsonb),
 'unclassified_records',(select count(*) from oqc_daily_inspection o left join oqc_inspection_context c on c.inspection_id=o.id and c.source_date=o.inspection_date and c.source_product_code=o.product_code where o.inspection_date=p_date and c.inspection_scope is null),
 'other_scope_records',(select count(*) from oqc_daily_inspection o join oqc_inspection_context c on c.inspection_id=o.id and c.source_date=o.inspection_date and c.source_product_code=o.product_code where o.inspection_date=p_date and c.inspection_scope in ('SAMPLING','OTHER'))
 ) into result;return result;
end$$;
-- Existing RPC bodies, grants, roles, routing, connection settings and old data remain unchanged.
do $$declare p record;begin
 for p in select oid::regprocedure as sig,proname from pg_proc where pronamespace='public'::regnamespace and proname in ('oqc_capacity_immutable','oqc_capacity_number','oqc_capacity_actor','oqc_capacity_info','oqc_save_work_standard','oqc_save_capacity_plan','oqc_save_capacity_labor','oqc_save_scoped_inspection','oqc_capacity_report') loop
   execute format('revoke all on function %s from public,anon,authenticated',p.sig);
   if p.proname in ('oqc_capacity_info','oqc_save_work_standard','oqc_save_capacity_plan','oqc_save_capacity_labor','oqc_save_scoped_inspection','oqc_capacity_report') then execute format('grant execute on function %s to authenticated',p.sig);end if;
 end loop;
end$$;
commit;
