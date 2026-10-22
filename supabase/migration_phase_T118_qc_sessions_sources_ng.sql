-- T118 STAGING ONLY jcjbleugnclzsghfpmvk. Additive; no old history backfill.
begin;
alter table public.duc_ipqc_checkpoint add column if not exists session_started_at timestamptz;
alter table public.duc_ipqc_checkpoint add column if not exists session_completed_at timestamptz;
create table if not exists public.duc_ipqc_inspection_session(
 checkpoint_id text primary key references public.duc_ipqc_checkpoint(id_checkpoint),
 owner_id uuid not null references auth.users(id), started_at timestamptz not null default clock_timestamp(),
 completed_at timestamptz, machine text not null, product_code text not null, job_id text,
 submission_at timestamptz, check(completed_at is null or completed_at>=started_at)
);
alter table public.duc_ipqc_inspection_session enable row level security;
revoke all on public.duc_ipqc_inspection_session from anon,authenticated;
grant select on public.duc_ipqc_inspection_session to authenticated;
drop policy if exists "inspect own session" on public.duc_ipqc_inspection_session;
create policy "inspect own session" on public.duc_ipqc_inspection_session for select to authenticated
using(owner_id=auth.uid() or public.has_role('admin','qc_manager'));
create or replace function public.duc_ipqc_session(p_checkpoint text,p_start boolean default false)
returns jsonb language plpgsql security definer set search_path=public as $q$
declare cp public.duc_ipqc_checkpoint%rowtype; s public.duc_ipqc_inspection_session%rowtype;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 select * into cp from duc_ipqc_checkpoint where id_checkpoint=p_checkpoint for update;
 if not found then raise exception 'Không tìm thấy đúng điểm kiểm';end if;
 select * into s from duc_ipqc_inspection_session where checkpoint_id=p_checkpoint;
 if found and s.owner_id<>auth.uid() then raise exception 'Phiên kiểm đang thuộc người kiểm khác';end if;
 if s.checkpoint_id is null and p_start then
   if not public.has_role('admin','ipqc','qc_manager') then raise exception 'Tài khoản không có quyền bắt đầu kiểm IPQC';end if;
   if cp.trang_thai<>'cho_kiem' then raise exception 'Điểm kiểm không còn chờ kiểm';end if;
   insert into duc_ipqc_inspection_session(checkpoint_id,owner_id,machine,product_code,job_id)
   values(p_checkpoint,auth.uid(),cp.ma_may,cp.ma_sp,cp.id_dong) returning * into s;
 end if;
 return jsonb_build_object('session',case when s.checkpoint_id is null then null else to_jsonb(s) end,'server_now',clock_timestamp());
end $q$;
-- Capture the server time at the validated Submit click, before evidence upload.
create or replace function public.duc_ipqc_session_submit_time(p_checkpoint text,p_clear boolean default false)
returns jsonb language plpgsql security definer set search_path=public as $q$
declare s public.duc_ipqc_inspection_session%rowtype;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 perform 1 from duc_ipqc_checkpoint where id_checkpoint=p_checkpoint and trang_thai='cho_kiem' for update;
 if not found then raise exception 'Điểm kiểm không còn chờ kiểm';end if;
 update duc_ipqc_inspection_session set submission_at=case when p_clear then null else clock_timestamp() end
 where checkpoint_id=p_checkpoint and owner_id=auth.uid() and completed_at is null returning * into s;
 if not found then raise exception 'Hãy bấm Bắt đầu kiểm tra cho đúng phiên';end if;
 return to_jsonb(s);
end $q$;
create or replace function public.duc_ipqc_session_complete_trigger()
returns trigger language plpgsql security definer set search_path=public as $q$
declare s public.duc_ipqc_inspection_session%rowtype; ended timestamptz;
begin
 if old.trang_thai='da_kiem' and old.ket_qua='NG' and new.ket_qua is distinct from old.ket_qua then raise exception 'Không sửa kết quả NG gốc';end if;
 select * into s from duc_ipqc_inspection_session where checkpoint_id=new.id_checkpoint for update;
 if not found then return new;end if; -- legacy clients/history retain their original fields
 if old.trang_thai='da_kiem' then
   if new.ket_qua is distinct from old.ket_qua or new.thoi_gian_kiem_giay is distinct from old.thoi_gian_kiem_giay then raise exception 'Không sửa kết quả/thời gian phiên đã hoàn tất';end if;
   return new;
 end if;
 if new.trang_thai='da_kiem' then
   if s.owner_id is distinct from auth.uid() then raise exception 'Chỉ người bắt đầu phiên được hoàn tất';end if;
   if row(s.machine,s.product_code,s.job_id) is distinct from row(new.ma_may,new.ma_sp,new.id_dong) then raise exception 'Máy/model/phiên sản xuất đã thay đổi';end if;
   if s.completed_at is not null or s.submission_at is null then raise exception 'Phiên kiểm chưa xác nhận hoàn tất';end if;
   ended:=s.submission_at;
   new.session_started_at:=s.started_at;new.session_completed_at:=ended;
   new.thoi_gian_kiem_giay:=greatest(0,extract(epoch from ended-s.started_at));
   update duc_ipqc_inspection_session set completed_at=ended where checkpoint_id=new.id_checkpoint;
 end if;
 return new;
end $q$;
drop trigger if exists trg_ipqc_session_complete on public.duc_ipqc_checkpoint;
create trigger trg_ipqc_session_complete before update of trang_thai,ket_qua,thoi_gian_kiem_giay on public.duc_ipqc_checkpoint
for each row execute function public.duc_ipqc_session_complete_trigger();
create or replace function public.duc_submit_ipqc_session(p_id_checkpoint text,p_checklist jsonb,p_ket_qua text,p_anh_urls jsonb,p_ghi_chu text,p_thoi_gian_kiem_giay numeric,p_nguoi_kiem text)
returns jsonb language plpgsql security definer set search_path=public as $q$
declare s public.duc_ipqc_inspection_session%rowtype; result jsonb;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 perform 1 from duc_ipqc_checkpoint where id_checkpoint=p_id_checkpoint for update;
 select * into s from duc_ipqc_inspection_session where checkpoint_id=p_id_checkpoint and owner_id=auth.uid() for update;
 if not found then raise exception 'Hãy bấm Bắt đầu kiểm tra';end if;
 if s.completed_at is not null then
   if exists(select 1 from duc_ipqc_checkpoint where id_checkpoint=p_id_checkpoint and ket_qua=p_ket_qua and trang_thai='da_kiem') then return jsonb_build_object('ok',true,'existing',true);end if;
   raise exception 'Phiên đã lưu kết quả khác';
 end if;
 result:=public.duc_submit_ipqc_check(p_id_checkpoint,p_checklist,p_ket_qua,p_anh_urls,p_ghi_chu,null,p_nguoi_kiem);
 if coalesce((result->>'ok')::boolean,false)=false then raise exception '%',coalesce(result->>'error','Không lưu được kết quả');end if;
 return result;
end $q$;
-- Source metadata is nullable on existing NCPs. Existing processing/closing RPCs unchanged.
alter table public.duc_ncp add column if not exists source_type text check(source_type in ('machine','department','customer'));
alter table public.duc_ncp add column if not exists source_department text;
alter table public.duc_ncp add column if not exists source_customer_code text;
alter table public.duc_ncp add column if not exists source_customer_name text;
alter table public.duc_ncp add column if not exists source_images jsonb;
alter table public.duc_ncp add column if not exists source_request_id uuid;
create unique index if not exists uq_ncp_source_request on public.duc_ncp(source_request_id) where source_request_id is not null;
create or replace function public.duc_ncp_open_source(p_data jsonb)
returns jsonb language plpgsql security definer set search_path=public as $q$
declare product public.master_products%rowtype; result jsonb; existing text; actor text; assignee text; response_owner text; source text:=p_data->>'source_type'; customer_code text; customer_name text;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 if source is null or source not in ('machine','department','customer') then raise exception 'Chọn nguồn phát sinh';end if;
 if coalesce(p_data->>'quantity','') !~ '^[0-9]+([.][0-9]+)?$' or coalesce(p_data->>'ng_quantity','0') !~ '^[0-9]+([.][0-9]+)?$' then raise exception 'Số lượng phải là số hữu hạn không âm';end if;
 if nullif(p_data->>'request_id','') is null then raise exception 'Thiếu mã phiên tạo phiếu';end if;
 perform pg_advisory_xact_lock(hashtextextended('ncp-source:'||(p_data->>'request_id'),0));
 select id_ncp into existing from duc_ncp where source_request_id=(p_data->>'request_id')::uuid;
 if found then return jsonb_build_object('ok',true,'id_ncp',existing,'existing',true);end if;
 select * into product from master_products where ma_sp=p_data->>'product_code';if not found then raise exception 'Chọn sản phẩm từ danh mục';end if;
 if source='machine' and (nullif(trim(p_data->>'machine'),'') is null or nullif(trim(p_data->>'mold'),'') is null) then raise exception 'Nguồn máy đúc cần máy và số khuôn';end if;
 if source='machine' and not exists(select 1 from master_machines where ma_may=p_data->>'machine') then raise exception 'Máy không có trong danh mục';end if;
 if source='department' and nullif(trim(p_data->>'department'),'') is null then raise exception 'Chọn bộ phận/công đoạn';end if;
 if source='customer' then
   select ma_khach_hang,ten_khach_hang into customer_code,customer_name from master_products
   where coalesce(nullif(ma_khach_hang,''),ten_khach_hang)=p_data->>'customer' limit 1;
   if not found then raise exception 'Chọn khách hàng từ danh mục hiện có';end if;
 end if;
 select coalesce(full_name,username,email) into actor from user_roles where user_id=auth.uid();
 select coalesce(full_name,username) into assignee from user_roles where username=p_data->>'assignee';
 if not found then raise exception 'Chọn người đảm nhiệm từ tài khoản trung tâm';end if;
 select coalesce(full_name,username) into response_owner from user_roles where username=p_data->>'response_owner';
 if not found then raise exception 'Chọn người trả lời đối sách từ tài khoản trung tâm';end if;
 if nullif(trim(p_data->>'description'),'') is null or nullif(trim(p_data->>'location'),'') is null then raise exception 'Nhập mô tả và vị trí cách ly';end if;
 if p_data ? 'images' and jsonb_typeof(p_data->'images')<>'array' then raise exception 'Ảnh không hợp lệ';end if;
 if jsonb_array_length(coalesce(p_data->'images','[]'))>10 then raise exception 'Tối đa 10 ảnh';end if;
 if exists(select 1 from jsonb_array_elements_text(coalesce(p_data->'images','[]')) img where img is null or img !~ '^https://[^ ]+$') then raise exception 'Liên kết ảnh không hợp lệ';end if;
 result:=duc_ncp_open_case(null,case when source='machine' then p_data->>'machine' else '' end,product.ma_sp,product.ten_sp,case when source='machine' then p_data->>'mold' else '' end,p_data->>'description',(p_data->>'quantity')::numeric,coalesce((p_data->>'ng_quantity')::numeric,0),p_data->>'location',assignee,response_owner,coalesce(actor,'MES'));
 if coalesce((result->>'ok')::boolean,false)=false then raise exception '%',result->>'error';end if;
 update duc_ncp set source_type=source,source_department=nullif(trim(p_data->>'department'),''),source_customer_code=customer_code,source_customer_name=customer_name,source_images=coalesce(p_data->'images','[]'),source_request_id=(p_data->>'request_id')::uuid where id_ncp=result->>'id_ncp';
 return result;
end $q$;
-- Serializing on the exact NG checkpoint prevents duplicate forwards across devices.
create or replace function public.duc_ipqc_forward_ng(p_checkpoint text)
returns bigint language plpgsql security definer set search_path=public as $q$
declare cp public.duc_ipqc_checkpoint%rowtype; existing bigint; actor text; data jsonb; job jsonb;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 if not public.has_role('admin','ipqc','qc_manager') then raise exception 'Tài khoản không có quyền chuyển NG';end if;
 select * into cp from duc_ipqc_checkpoint where id_checkpoint=p_checkpoint for update;
 if not found or cp.ket_qua<>'NG' or cp.trang_thai<>'da_kiem' then raise exception 'Chọn đúng lần kiểm NG đã lưu';end if;
 select id into existing from duc_ipqc_continue_request where checkpoint_id=p_checkpoint order by id desc limit 1;
 if found then return existing;end if;
 select coalesce(full_name,username,email) into actor from user_roles where user_id=auth.uid();
 select to_jsonb(j) into job from duc_ca_hien_tai j where j.id_dong=cp.id_dong and j.ma_may=cp.ma_may and j.ma_sp=cp.ma_sp;
 data:=jsonb_build_object('checkpoint_id',cp.id_checkpoint,'machine',cp.ma_may,'product_code',cp.ma_sp,'process',coalesce(to_jsonb(cp)->>'cong_doan',job->>'cong_doan','Đúc'),'task_no',coalesce(job->>'tag_no',job->>'task_no'),'lot_no',coalesce(job->>'lot',job->>'lot_no'),'warning_content',coalesce(cp.ghi_chu,''),'warning_level','NG','reason_type','EARLY_WARNING','reason_detail','Xem xét kết quả NG gốc: '||cp.id_checkpoint,'inspection_by',cp.nguoi_kiem,'inspection_at',coalesce(cp.session_completed_at,cp.thoi_diem_kiem_thuc_te),'inspection_started_at',cp.session_started_at,'inspection_duration_seconds',cp.thoi_gian_kiem_giay,'inspection_checklist',cp.checklist_json,'inspection_evidence_urls',cp.anh_bang_chung_url,'id_dong',cp.id_dong);
 return duc_ipqc_create_continue_request(data,coalesce(actor,'MES'));
end $q$;
-- Lock/validate NG links even when an older client uses the existing creation RPC.
create or replace function public.duc_ipqc_guard_ng_link()
returns trigger language plpgsql security definer set search_path=public as $q$
declare cp public.duc_ipqc_checkpoint%rowtype;
begin
 if new.checkpoint_id is null then return new;end if;
 select * into cp from duc_ipqc_checkpoint where id_checkpoint=new.checkpoint_id for update;
 if cp.ket_qua='NG' then
   if exists(select 1 from duc_ipqc_continue_request where checkpoint_id=cp.id_checkpoint and status in ('Chờ duyệt','Đang duyệt','Đã duyệt','Đang có hiệu lực')) then raise exception 'NG này đã có yêu cầu đang xử lý';end if;
   new.machine:=cp.ma_may;new.product_code:=cp.ma_sp;new.warning_content:=coalesce(cp.ghi_chu,'');new.warning_level:='NG';
 end if;
 return new;
end $q$;
drop trigger if exists trg_ng_source_link on public.duc_ipqc_continue_request;
create trigger trg_ng_source_link before insert on public.duc_ipqc_continue_request for each row execute function public.duc_ipqc_guard_ng_link();
alter table public.duc_ipqc_continue_request add column if not exists ng_handling jsonb;
create or replace function public.duc_ipqc_decide_ng(p_request_id bigint,p_decision text,p_actor text,p_note text,p_conditions jsonb)
returns void language plpgsql security definer set search_path=public as $q$
declare r public.duc_ipqc_continue_request%rowtype; cp public.duc_ipqc_checkpoint%rowtype; actor text; ncp_before jsonb;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 select * into r from duc_ipqc_continue_request where id=p_request_id for update;if not found then raise exception 'Không tìm thấy yêu cầu';end if;
 select * into cp from duc_ipqc_checkpoint where id_checkpoint=r.checkpoint_id;
 if cp.ket_qua<>'NG' or cp.id_checkpoint is null then raise exception 'Yêu cầu không liên kết NG gốc';end if;
 if p_decision in ('Duyệt','Phê duyệt trực tiếp') then
   if nullif(trim(p_conditions->>'reason'),'') is null or nullif(trim(p_conditions->>'scope'),'') is null or nullif(trim(p_conditions->>'next_process'),'') is null or nullif(trim(p_conditions->>'responsible'),'') is null then raise exception 'NG cần lý do, phạm vi, công đoạn tiếp và bộ phận/người chịu trách nhiệm';end if;
   if p_conditions->>'mode'='TIME' and coalesce(p_conditions->>'hours','') ~ '^[0-9]+([.][0-9]+)?$' and coalesce((p_conditions->>'hours')::numeric,0)>0 then
     update duc_ipqc_continue_request set reason_type='TIME',allowed_hours=(p_conditions->>'hours')::numeric,allowed_until=null where id=r.id;
   elsif p_conditions->>'mode'='PLAN_QTY' and coalesce(p_conditions->>'quantity','') ~ '^[0-9]+([.][0-9]+)?$' and coalesce((p_conditions->>'quantity')::numeric,0)>0 then
     update duc_ipqc_continue_request set reason_type='PLAN_QTY',allowed_qty=(p_conditions->>'quantity')::numeric where id=r.id;
   else raise exception 'Chọn giới hạn giờ hoặc số lượng chạy thêm';end if;
   select coalesce(full_name,username,email) into actor from user_roles where user_id=auth.uid();
   update duc_ipqc_continue_request set ng_handling=jsonb_build_object('reason',p_conditions->>'reason','scope',p_conditions->>'scope','next_process',p_conditions->>'next_process','responsible',p_conditions->>'responsible','decided_by',actor,'decided_at',clock_timestamp(),'decision_tx',txid_current()::text) where id=r.id;
 end if;
 select coalesce(jsonb_object_agg(id_ncp,trang_thai),'{}'::jsonb) into ncp_before from duc_ncp where id_checkpoint_goc=r.checkpoint_id;
 perform duc_ipqc_decide_continue_request(p_request_id,p_decision,p_actor,p_note);
 if exists(select 1 from duc_ncp n join jsonb_each_text(ncp_before) b on b.key=n.id_ncp where b.value<>'dong' and n.trang_thai='dong') then raise exception 'Duyệt chạy tiếp không được tự đóng phiếu NCP';end if;
 insert into duc_ipqc_continue_audit(request_id,action,actor_id,actor_name,detail) values(r.id,'XỬ LÝ NG',auth.uid(),coalesce(actor,p_actor),coalesce(p_conditions,'{}'));
end $q$;
-- The original decision RPC cannot bypass the mandatory NG handling fields.
create or replace function public.duc_ipqc_guard_ng_approval()
returns trigger language plpgsql security definer set search_path=public as $q$
begin
 if (new.current_step>old.current_step or (new.status='Đang có hiệu lực' and old.status is distinct from new.status)) and exists(select 1 from duc_ipqc_checkpoint where id_checkpoint=new.checkpoint_id and ket_qua='NG') then
   if new.ng_handling->>'decision_tx' is distinct from txid_current()::text then raise exception 'Duyệt NG phải ghi đủ điều kiện và trách nhiệm xử lý';end if;
 end if;
 return new;
end $q$;
drop trigger if exists trg_guard_ng_approval on public.duc_ipqc_continue_request;
create trigger trg_guard_ng_approval before update of status,current_step on public.duc_ipqc_continue_request for each row execute function public.duc_ipqc_guard_ng_approval();
-- Grants only these new entry points. Existing grants/RLS are left intact.
do $q$ declare f regprocedure;begin
 foreach f in array array['public.duc_ipqc_session(text,boolean)'::regprocedure,'public.duc_ipqc_session_submit_time(text,boolean)'::regprocedure,'public.duc_submit_ipqc_session(text,jsonb,text,jsonb,text,numeric,text)'::regprocedure,'public.duc_ncp_open_source(jsonb)'::regprocedure,'public.duc_ipqc_forward_ng(text)'::regprocedure,'public.duc_ipqc_decide_ng(bigint,text,text,text,jsonb)'::regprocedure] loop
 execute format('revoke all on function %s from public,anon',f);execute format('grant execute on function %s to authenticated',f);
 end loop;
 foreach f in array array['public.duc_ipqc_session_complete_trigger()'::regprocedure,'public.duc_ipqc_guard_ng_approval()'::regprocedure,'public.duc_ipqc_guard_ng_link()'::regprocedure] loop execute format('revoke all on function %s from public,anon,authenticated',f);end loop;
end $q$;
commit;
