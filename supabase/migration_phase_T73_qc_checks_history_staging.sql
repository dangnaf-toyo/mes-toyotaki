-- Đã chạy STAGING jcjbleugnclzsghfpmvk + PRODUCTION fgghikpzcxjqzahfiiil (2026-10-10, qua Supabase MCP).
-- QC requirements 09/10/2026. Nullable additions; no backfill of old inspection/LOT data.
-- Execute the complete transaction in the staging SQL Editor.
begin;

-- Preserve the live RPC body, SECURITY DEFINER settings and existing execute grants.
-- Only change the known evidence limit; abort the transaction if the live body differs.
do $qc$
declare source text; patched text; hits integer;
begin
  source:=pg_get_functiondef('public.duc_submit_ipqc_check(text,jsonb,text,jsonb,text,numeric,text)'::regprocedure);
  select count(*) into hits from regexp_matches(source,'jsonb_array_length\(p_anh_urls\)[[:space:]]*>[[:space:]]*6','gi');
  if hits=1 then
    patched:=regexp_replace(source,'jsonb_array_length\(p_anh_urls\)[[:space:]]*>[[:space:]]*6','jsonb_array_length(p_anh_urls) > 10','gi');
    patched:=replace(patched,'Tối đa 6 ảnh cho 1 lần kiểm tra','Tối đa 10 ảnh cho 1 lần kiểm tra');
    execute patched;
  elsif hits=0 and source ~* 'jsonb_array_length\(p_anh_urls\)[[:space:]]*>[[:space:]]*10' then
    null; -- already applied
  else
    raise exception 'Unknown live IPQC photo validator. Nothing changed; review function definition.';
  end if;
end $qc$;

alter table public.iqc_lots add column if not exists sampled_at timestamptz;
alter table public.oqc_daily_inspection add column if not exists inspection_time time without time zone;
alter table public.oqc_daily_inspection add column if not exists customer_code text;
alter table public.oqc_daily_inspection add column if not exists customer_name text;
alter table public.oqc_daily_inspection add column if not exists lot_no text;
alter table public.oqc_daily_inspection add column if not exists task_no text;
alter table public.quality_defect_catalog add column if not exists aliases text[];

do $qc$
declare current_label text;
begin
  select label into current_label from public.quality_defect_catalog where code='vat_c' for update;
  if current_label is null then raise exception 'Missing vat_c catalog code; review before applying.';end if;
  if current_label not in ('Vật C','Vát C') then raise exception 'vat_c was changed by another user; review label %',current_label;end if;
  update public.quality_defect_catalog set label='Vát C',aliases=case when 'Vật C'=any(coalesce(aliases,'{}'::text[])) then aliases else array_append(coalesce(aliases,'{}'::text[]),'Vật C') end where code='vat_c';
end $qc$;

-- Keep the existing save RPC and its validation/audit behavior untouched.
-- Versioned wrapper atomically adds the explicit event/source fields to NEW user saves.
create or replace function public.oqc_save_daily_inspection_qc_v2(p_id bigint,p_data jsonb,p_actor text)
returns bigint language plpgsql security definer set search_path=public as $qc$
declare v_id bigint; v_before jsonb; v_after jsonb;
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
  v_id:=public.oqc_save_daily_inspection(p_id,p_data,p_actor);
  select to_jsonb(r) into v_before from public.oqc_daily_inspection r where id=v_id for update;
  update public.oqc_daily_inspection set
    inspection_time=case when p_data ? 'inspection_time' then nullif(p_data->>'inspection_time','')::time else inspection_time end,
    customer_code=case when p_data ? 'customer_code' then nullif(p_data->>'customer_code','') else customer_code end,
    customer_name=case when p_data ? 'customer_name' then nullif(p_data->>'customer_name','') else customer_name end,
    lot_no=case when p_data ? 'lot_no' then nullif(p_data->>'lot_no','') else lot_no end,
    task_no=case when p_data ? 'task_no' then nullif(p_data->>'task_no','') else task_no end
  where id=v_id;
  select to_jsonb(r) into v_after from public.oqc_daily_inspection r where id=v_id;
  if p_id is not null and v_before is distinct from v_after then
    insert into public.oqc_daily_inspection_audit(inspection_id,actor_id,actor_name,old_data,new_data)
    values(v_id,auth.uid(),p_actor,v_before,v_after);
  end if;
  return v_id;
end $qc$;
revoke all on function public.oqc_save_daily_inspection_qc_v2(bigint,jsonb,text) from public,anon;
grant execute on function public.oqc_save_daily_inspection_qc_v2(bigint,jsonb,text) to authenticated;
commit;

-- Read-only verification. Nulls on existing records are intentional, never invented times.
select code,label,aliases from public.quality_defect_catalog where code='vat_c';
select column_name,data_type from information_schema.columns where table_schema='public'
  and ((table_name='iqc_lots' and column_name='sampled_at') or
       (table_name='oqc_daily_inspection' and column_name in ('inspection_time','customer_code','customer_name','lot_no','task_no')));
select pg_get_functiondef('public.duc_submit_ipqc_check(text,jsonb,text,jsonb,text,numeric,text)'::regprocedure)
  ~* 'jsonb_array_length\(p_anh_urls\)[[:space:]]*>[[:space:]]*10' as ipqc_accepts_10_photos;