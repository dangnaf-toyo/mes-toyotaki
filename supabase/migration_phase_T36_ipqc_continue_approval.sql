-- IPQC: yêu cầu tiếp tục sản xuất có điều kiện và audit bất biến.
-- Giai đoạn này mọi tài khoản authenticated được thao tác; phân vai trò sẽ bổ sung sau.
create table if not exists public.duc_ipqc_continue_request (
  id bigserial primary key,
  request_code text not null unique default ('IPQC-' || to_char(now(),'YYYYMMDD-HH24MISS') || '-' || substr(md5(random()::text),1,4)),
  checkpoint_id text references public.duc_ipqc_checkpoint(id_checkpoint),
  machine text not null, process text, product_code text not null, lot_no text,
  warning_content text not null, actual_value text, standard_min text, standard_max text,
  warning_level text not null default 'NG' check (warning_level in ('NG','RISK','EARLY_WARNING')),
  reason_type text not null check (reason_type in ('TIME','PLAN_QTY','DOWNSTREAM_REWORK','EARLY_WARNING')),
  reason_detail text not null,
  allowed_until timestamptz, allowed_hours numeric, allowed_qty numeric,
  produced_at_request numeric not null default 0, produced_current numeric not null default 0,
  repair_department text, treatment_content text, treatment_deadline timestamptz,
  requester_id uuid not null default auth.uid(), requester_name text not null,
  status text not null default 'Chờ duyệt' check (status in ('Chờ duyệt','Đang duyệt','Đã duyệt','Đang có hiệu lực','Hết hiệu lực','Từ chối','Đã hủy')),
  current_step integer not null default 1,
  approved_scope text, effective_at timestamptz, expired_at timestamptz,
  is_override boolean not null default false, override_reason text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (reason_type <> 'TIME' or allowed_until is not null or allowed_hours > 0),
  check (reason_type <> 'PLAN_QTY' or allowed_qty > 0),
  check (reason_type <> 'DOWNSTREAM_REWORK' or (allowed_qty > 0 and nullif(trim(repair_department),'') is not null and nullif(trim(treatment_content),'') is not null and treatment_deadline is not null))
);

create table if not exists public.duc_ipqc_continue_approval (
  id bigserial primary key, request_id bigint not null references public.duc_ipqc_continue_request(id),
  step_no integer not null check(step_no between 1 and 4),
  approval_level text not null check(approval_level in ('QL Chất lượng','KHSX','QL Đúc/Bộ phận sản xuất','GĐ Sản xuất')),
  decision text check(decision in ('Duyệt','Từ chối','Bỏ qua bởi GĐ Sản xuất')),
  decided_by uuid, decided_by_name text, decided_at timestamptz, note text,
  unique(request_id,step_no)
);

create table if not exists public.duc_ipqc_continue_audit (
  id bigserial primary key, request_id bigint not null references public.duc_ipqc_continue_request(id),
  action text not null, actor_id uuid, actor_name text not null, detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.duc_ipqc_continue_notification (
  id bigserial primary key, request_id bigint not null references public.duc_ipqc_continue_request(id),
  recipient_group text not null, content text not null, is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace function public.duc_ipqc_audit_immutable() returns trigger language plpgsql as $$
begin raise exception 'Lịch sử phê duyệt IPQC không được phép sửa hoặc xóa'; end $$;
drop trigger if exists trg_ipqc_audit_immutable on public.duc_ipqc_continue_audit;
create trigger trg_ipqc_audit_immutable before update or delete on public.duc_ipqc_continue_audit for each row execute function public.duc_ipqc_audit_immutable();

create or replace function public.duc_ipqc_audit_status_change() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status is distinct from old.status then
   insert into duc_ipqc_continue_audit(request_id,action,actor_id,actor_name,detail)
   values(new.id,'ĐỔI TRẠNG THÁI',auth.uid(),coalesce((select full_name from user_roles where user_id=auth.uid()),'Hệ thống'),jsonb_build_object('from',old.status,'to',new.status));
 end if;
 return new;
end $$;
drop trigger if exists trg_ipqc_continue_status_audit on public.duc_ipqc_continue_request;
create trigger trg_ipqc_continue_status_audit after update of status on public.duc_ipqc_continue_request for each row execute function public.duc_ipqc_audit_status_change();

create or replace function public.duc_ipqc_continue_touch() returns trigger language plpgsql as $$
begin new.updated_at=now(); return new; end $$;
drop trigger if exists trg_ipqc_continue_touch on public.duc_ipqc_continue_request;
create trigger trg_ipqc_continue_touch before update on public.duc_ipqc_continue_request for each row execute function public.duc_ipqc_continue_touch();

alter table public.duc_ipqc_continue_request enable row level security;
alter table public.duc_ipqc_continue_approval enable row level security;
alter table public.duc_ipqc_continue_audit enable row level security;
alter table public.duc_ipqc_continue_notification enable row level security;
drop policy if exists "authenticated manage continue request" on public.duc_ipqc_continue_request;
drop policy if exists "authenticated read continue request" on public.duc_ipqc_continue_request;
create policy "authenticated read continue request" on public.duc_ipqc_continue_request for select to authenticated using(true);
drop policy if exists "authenticated manage continue approval" on public.duc_ipqc_continue_approval;
drop policy if exists "authenticated read continue approval" on public.duc_ipqc_continue_approval;
create policy "authenticated read continue approval" on public.duc_ipqc_continue_approval for select to authenticated using(true);
drop policy if exists "authenticated read continue audit" on public.duc_ipqc_continue_audit;
create policy "authenticated read continue audit" on public.duc_ipqc_continue_audit for select to authenticated using(true);
drop policy if exists "authenticated read continue notification" on public.duc_ipqc_continue_notification;
create policy "authenticated read continue notification" on public.duc_ipqc_continue_notification for select to authenticated using(true);

-- Không cấp UPDATE/DELETE audit: lịch sử chỉ được ghi qua các RPC security definer.
revoke insert,update,delete on public.duc_ipqc_continue_audit from anon,authenticated;
revoke insert,update,delete on public.duc_ipqc_continue_request from anon,authenticated;
revoke insert,update,delete on public.duc_ipqc_continue_approval from anon,authenticated;
revoke insert,update,delete on public.duc_ipqc_continue_notification from anon,authenticated;

create or replace function public.duc_ipqc_create_continue_request(p_data jsonb, p_actor text)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_id bigint; v_step record; v_existing bigint;
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
  if nullif(p_data->>'checkpoint_id','') is not null then
    select id into v_existing from duc_ipqc_continue_request where checkpoint_id=p_data->>'checkpoint_id' and status in('Chờ duyệt','Đang duyệt','Đã duyệt','Đang có hiệu lực') order by created_at desc limit 1;
    if v_existing is not null then raise exception 'Lần kiểm IPQC này đã có yêu cầu đang xử lý'; end if;
  end if;
  insert into duc_ipqc_continue_request(checkpoint_id,machine,process,product_code,lot_no,warning_content,actual_value,standard_min,standard_max,warning_level,reason_type,reason_detail,allowed_until,allowed_hours,allowed_qty,produced_at_request,repair_department,treatment_content,treatment_deadline,requester_name)
  values(nullif(p_data->>'checkpoint_id',''),p_data->>'machine',p_data->>'process',p_data->>'product_code',p_data->>'lot_no',p_data->>'warning_content',p_data->>'actual_value',p_data->>'standard_min',p_data->>'standard_max',coalesce(p_data->>'warning_level','NG'),p_data->>'reason_type',p_data->>'reason_detail',nullif(p_data->>'allowed_until','')::timestamptz,nullif(p_data->>'allowed_hours','')::numeric,nullif(p_data->>'allowed_qty','')::numeric,coalesce(nullif(p_data->>'produced_current','')::numeric,0),p_data->>'repair_department',p_data->>'treatment_content',nullif(p_data->>'treatment_deadline','')::timestamptz,p_actor) returning id into v_id;
  for v_step in select * from (values (1,'QL Chất lượng'),(2,'KHSX'),(3,'QL Đúc/Bộ phận sản xuất'),(4,'GĐ Sản xuất')) s(n,l) loop
    insert into duc_ipqc_continue_approval(request_id,step_no,approval_level) values(v_id,v_step.n,v_step.l);
  end loop;
  insert into duc_ipqc_continue_audit(request_id,action,actor_id,actor_name,detail) values(v_id,'TẠO YÊU CẦU',auth.uid(),p_actor,p_data);
  if coalesce(p_data->>'warning_level','NG')='EARLY_WARNING' then
    insert into duc_ipqc_continue_notification(request_id,recipient_group,content)
    select v_id,x,'Cảnh báo sớm IPQC: '||(p_data->>'machine')||' / '||(p_data->>'product_code')||' — '||(p_data->>'warning_content')
    from unnest(array['Quản lý bộ phận','Tổ trưởng bộ phận','IPQC / Quản lý chất lượng']) x;
  end if;
  return v_id;
end $$;

create or replace function public.duc_ipqc_decide_continue_request(p_request_id bigint,p_decision text,p_actor text,p_note text default '')
returns void language plpgsql security definer set search_path=public as $$
declare r duc_ipqc_continue_request%rowtype; v_scope text; v_until timestamptz;
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
  select * into r from duc_ipqc_continue_request where id=p_request_id for update;
  if r.status in ('Từ chối','Đã hủy','Đang có hiệu lực','Hết hiệu lực') then raise exception 'Yêu cầu không còn ở trạng thái có thể duyệt'; end if;
  if p_decision='Từ chối' then
    update duc_ipqc_continue_approval set decision='Từ chối',decided_by=auth.uid(),decided_by_name=p_actor,decided_at=now(),note=p_note where request_id=r.id and step_no=r.current_step;
    update duc_ipqc_continue_request set status='Từ chối' where id=r.id;
  elsif p_decision='Phê duyệt trực tiếp' then
    if nullif(trim(p_note),'') is null then raise exception 'Phê duyệt trực tiếp bắt buộc nhập lý do'; end if;
    update duc_ipqc_continue_approval set decision=case when step_no=4 then 'Duyệt' else 'Bỏ qua bởi GĐ Sản xuất' end,decided_by=auth.uid(),decided_by_name=p_actor,decided_at=now(),note=p_note where request_id=r.id and decision is null;
    v_until=coalesce(r.allowed_until,case when r.allowed_hours>0 then now()+make_interval(secs=>(r.allowed_hours*3600)::int) end);
    v_scope=case r.reason_type when 'TIME' then 'Được phép chạy đến '||to_char(v_until at time zone 'Asia/Ho_Chi_Minh','DD/MM/YYYY HH24:MI') when 'PLAN_QTY' then 'Được phép chạy thêm '||r.allowed_qty||' pcs' when 'DOWNSTREAM_REWORK' then 'Được phép chạy '||r.allowed_qty||' pcs để '||r.repair_department||' sửa/lựa' else 'Cảnh báo sớm: điều chỉnh máy/khuôn/thông số' end;
    update duc_ipqc_continue_request set status='Đang có hiệu lực',current_step=4,is_override=true,override_reason=p_note,effective_at=now(),expired_at=v_until,approved_scope=v_scope where id=r.id;
  elsif p_decision='Duyệt' then
    update duc_ipqc_continue_approval set decision='Duyệt',decided_by=auth.uid(),decided_by_name=p_actor,decided_at=now(),note=p_note where request_id=r.id and step_no=r.current_step;
    if r.current_step<4 then update duc_ipqc_continue_request set status='Đang duyệt',current_step=r.current_step+1 where id=r.id;
    else
      v_until=coalesce(r.allowed_until,case when r.allowed_hours>0 then now()+make_interval(secs=>(r.allowed_hours*3600)::int) end);
      v_scope=case r.reason_type when 'TIME' then 'Được phép chạy đến '||to_char(v_until at time zone 'Asia/Ho_Chi_Minh','DD/MM/YYYY HH24:MI') when 'PLAN_QTY' then 'Được phép chạy thêm '||r.allowed_qty||' pcs' when 'DOWNSTREAM_REWORK' then 'Được phép chạy '||r.allowed_qty||' pcs để '||r.repair_department||' sửa/lựa' else 'Cảnh báo sớm: điều chỉnh máy/khuôn/thông số' end;
      update duc_ipqc_continue_request set status='Đang có hiệu lực',current_step=4,effective_at=now(),expired_at=v_until,approved_scope=v_scope where id=r.id;
    end if;
  else raise exception 'Quyết định không hợp lệ'; end if;
  insert into duc_ipqc_continue_audit(request_id,action,actor_id,actor_name,detail) values(r.id,upper(p_decision),auth.uid(),p_actor,jsonb_build_object('step',r.current_step,'note',p_note));
end $$;

create or replace function public.duc_ipqc_refresh_continue_request(p_request_id bigint default null)
returns void language plpgsql security definer set search_path=public as $$
begin
 update duc_ipqc_continue_request set status='Đang có hiệu lực',effective_at=coalesce(effective_at,now())
 where status='Đã duyệt' and (p_request_id is null or id=p_request_id);
 update duc_ipqc_continue_request set status='Hết hiệu lực'
 where status='Đang có hiệu lực' and (p_request_id is null or id=p_request_id)
 and ((expired_at is not null and now()>=expired_at) or (allowed_qty is not null and produced_current-produced_at_request>=allowed_qty));
end $$;

create or replace function public.duc_ipqc_update_continue_production(p_request_id bigint,p_produced_current numeric,p_actor text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
 update duc_ipqc_continue_request set produced_current=greatest(coalesce(p_produced_current,0),produced_at_request) where id=p_request_id;
 insert into duc_ipqc_continue_audit(request_id,action,actor_id,actor_name,detail) values(p_request_id,'CẬP NHẬT SẢN LƯỢNG',auth.uid(),p_actor,jsonb_build_object('produced_current',p_produced_current));
 perform duc_ipqc_refresh_continue_request(p_request_id);
end $$;

create or replace function public.duc_ipqc_cancel_continue_request(p_request_id bigint,p_actor text,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Bắt buộc nhập lý do hủy'; end if;
 update duc_ipqc_continue_request set status='Đã hủy' where id=p_request_id and status in('Chờ duyệt','Đang duyệt','Đã duyệt');
 if not found then raise exception 'Yêu cầu không thể hủy ở trạng thái hiện tại'; end if;
 insert into duc_ipqc_continue_audit(request_id,action,actor_id,actor_name,detail) values(p_request_id,'HỦY YÊU CẦU',auth.uid(),p_actor,jsonb_build_object('reason',p_reason));
end $$;

grant execute on function public.duc_ipqc_create_continue_request(jsonb,text) to authenticated;
grant execute on function public.duc_ipqc_decide_continue_request(bigint,text,text,text) to authenticated;
grant execute on function public.duc_ipqc_refresh_continue_request(bigint) to authenticated;
grant execute on function public.duc_ipqc_update_continue_production(bigint,numeric,text) to authenticated;
grant execute on function public.duc_ipqc_cancel_continue_request(bigint,text,text) to authenticated;

-- Hàm dùng chung cho các màn hình sản xuất: false nghĩa là phải khóa thao tác chạy.
create or replace function public.duc_ipqc_can_continue(p_machine text,p_product_code text)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_has_warning boolean; v_has_live boolean;
begin
 perform duc_ipqc_refresh_continue_request(null);
 select exists(select 1 from duc_ipqc_checkpoint where ma_may=p_machine and ma_sp=p_product_code and ket_qua in('NG','CANH_BAO') and thoi_diem_kiem_thuc_te>now()-interval '24 hours') into v_has_warning;
 select exists(select 1 from duc_ipqc_continue_request where machine=p_machine and product_code=p_product_code and status='Đang có hiệu lực') into v_has_live;
 return not v_has_warning or v_has_live;
end $$;
grant execute on function public.duc_ipqc_can_continue(text,text) to authenticated;
