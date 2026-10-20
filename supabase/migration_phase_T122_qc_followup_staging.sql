-- T122 STAGING ONLY: jcjbleugnclzsghfpmvk. Requires T118/T120. No backfill.
begin;
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
   ended:=clock_timestamp();
   new.session_started_at:=s.started_at;new.session_completed_at:=ended;
   new.thoi_gian_kiem_giay:=greatest(0,extract(epoch from ended-s.started_at));
   update duc_ipqc_inspection_session set completed_at=ended where checkpoint_id=new.id_checkpoint;
 end if;
 return new;
end $q$;
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
 if jsonb_typeof(p_checklist) is distinct from 'array' or jsonb_array_length(p_checklist)=0 then raise exception 'Xác nhận đầy đủ tất cả hạng mục kiểm';end if;
 if exists(select 1 from jsonb_array_elements(p_checklist) x where jsonb_typeof(x->'dat') is distinct from 'boolean') then raise exception 'Xác nhận đầy đủ tất cả hạng mục kiểm';end if;
 result:=public.duc_submit_ipqc_check(p_id_checkpoint,p_checklist,p_ket_qua,p_anh_urls,p_ghi_chu,null,p_nguoi_kiem);
 if coalesce((result->>'ok')::boolean,false)=false then raise exception '%',coalesce(result->>'error','Không lưu được kết quả');end if;
 return result;
end $q$;

-- Missing hours/norms are explicit NULL, never a valid zero-person plan.
-- No existing plan is re-rated or linked by this migration.
alter table public.oqc_capacity_day alter column hours_per_person drop not null;
alter table public.oqc_capacity_plan alter column standard_version_id drop not null;
alter table public.oqc_capacity_plan alter column seconds_per_piece drop not null;
alter table public.oqc_capacity_plan add column if not exists source_kind text check(source_kind in ('manual','machining','oqc'));
alter table public.oqc_capacity_plan add column if not exists source_plan_id bigint references public.cd_khsx_tuan_plan(id) on delete set null;
alter table public.oqc_capacity_plan add column if not exists oqc_plan_id bigint references public.cd_khsx_tuan_plan(id) on delete set null;
create unique index if not exists qc_plan_oqc_day_link on public.oqc_capacity_plan(oqc_plan_id,work_date) where oqc_plan_id is not null;

create or replace function public.qc_save_linked_plan(p_data jsonb)
returns integer language plpgsql security definer set search_path=public as $$
declare d date:=(p_data->>'date')::date; code text:=p_data->>'product'; qty numeric; hrs numeric;
 mon date; col text; dayrow oqc_capacity_day%rowtype; oldplan oqc_capacity_plan%rowtype;
 src cd_khsx_tuan_plan%rowtype; target cd_khsx_tuan_plan%rowtype; norm oqc_work_standard_version%rowtype;
 kind text:=p_data->>'source_kind'; sourceid bigint:=nullif(p_data->>'source_id','')::bigint;
 requested_version bigint:=nullif(p_data->>'standard_version_id','')::bigint; actor text; logged jsonb; beforedata jsonb; total numeric;
begin
 if auth.uid() is null or not has_role('admin','qc_manager','nhan_vien_oqc','ke_hoach','qlsx_truong_phong') then raise exception 'Không có quyền lập kế hoạch kiểm tra';end if;
 if d is null or code is null or kind is null or kind not in ('manual','machining','oqc') then raise exception 'Chọn ngày, model và nguồn kế hoạch';end if;
 qty:=oqc_capacity_number(p_data->>'quantity');hrs:=oqc_capacity_number(p_data->>'hours');
 if qty<>trunc(qty) or hrs>24 then raise exception 'Số lượng PCS nguyên, giờ/người trong khoảng (0,24]';end if;
 if not exists(select 1 from master_products where ma_sp=code) then raise exception 'Chọn model trong danh mục';end if;
 mon:=d-(extract(isodow from d)::int-1);col:=(array['t2','t3','t4','t5','t6','t7','cn'])[extract(isodow from d)::int];
 perform pg_advisory_xact_lock(hashtextextended('qc-week:'||mon::text,0));
 perform pg_advisory_xact_lock(hashtextextended('oqc-plan:'||d::text,0));
 select * into dayrow from oqc_capacity_day where work_date=d for update;
 if coalesce((p_data->>'revision')::integer,-1)<>coalesce(dayrow.revision,0) then raise exception 'Kế hoạch đã thay đổi. Tải lại trước khi lưu.';end if;
 select * into oldplan from oqc_capacity_plan where work_date=d and product_code=code for update;
 beforedata:=jsonb_build_object('plan',case when oldplan.work_date is null then null else to_jsonb(oldplan) end,'day',case when dayrow.work_date is null then null else to_jsonb(dayrow) end);
 if kind<>'manual' then
  select * into src from cd_khsx_tuan_plan where id=sourceid for update;
  if not found or src.tuan_bat_dau<>mon or src.ma_sp<>code or src.cong_doan<>(case when kind='oqc' then 'OQC' else 'Gia Công' end) then raise exception 'Nguồn không khớp đúng ngày/model/công đoạn. Nạp lại nguồn.';end if;
  if coalesce((to_jsonb(src)->>col)::numeric,0)<=0 then raise exception 'Nguồn không có số lượng tại ngày đã chọn';end if;
 elsif sourceid is not null then raise exception 'Kế hoạch tự thêm không có ID nguồn';end if;
 if requested_version is not null then
  select * into norm from oqc_work_standard_version where id=requested_version and product_code=code and effective_from<=d;
  if not found then raise exception 'Phiên bản định mức không thuộc model/ngày kế hoạch';end if;
 elsif oldplan.standard_version_id is not null then
  select * into norm from oqc_work_standard_version where id=oldplan.standard_version_id;
 else
  select * into norm from oqc_work_standard_version where product_code=code and effective_from<=d order by effective_from desc,id desc limit 1;
 end if;
 if norm.id is null then raise exception 'Chưa đủ dữ liệu tính nhân lực: thiếu định mức hiệu lực';end if;
 select * into target from cd_khsx_tuan_plan where tuan_bat_dau=mon and cong_doan='OQC' and ma_sp=code for update;
 if kind='oqc' and target.id is distinct from sourceid then raise exception 'Dòng nguồn OQC đã thay đổi; không tạo dòng thay thế';end if;
 actor:=oqc_capacity_actor();
 logged:=khsx_ghi_log_sua(mon,'OQC',case when target.id is null then 'them_moi' else 'sua' end,'Kế hoạch kiểm tra '||d||' / '||code,coalesce(to_jsonb(target)::text,''),p_data::text,coalesce(p_data->>'reason',''),actor);
 if coalesce((logged->>'ok')::boolean,false)=false then raise exception '%',logged->>'error';end if;
 perform set_config('mes.qc_plan_origin','linked_rpc',true);
 if target.id is null then
  insert into cd_khsx_tuan_plan(tuan_bat_dau,cong_doan,ma_sp,ten_sp,updated_by) select mon,'OQC',code,ten_sp,actor from master_products where ma_sp=code returning * into target;
 end if;
 total:=coalesce(target.t2,0)+coalesce(target.t3,0)+coalesce(target.t4,0)+coalesce(target.t5,0)+coalesce(target.t6,0)+coalesce(target.t7,0)+coalesce(target.cn,0)-coalesce((to_jsonb(target)->>col)::numeric,0)+qty;
 execute format('update cd_khsx_tuan_plan set %I=$1,kh_tuan=$2,updated_by=$3,updated_at=clock_timestamp() where id=$4',col) using qty,total,actor,target.id;
 insert into oqc_capacity_day(work_date,hours_per_person,updated_by) values(d,hrs,auth.uid()) on conflict(work_date) do update set hours_per_person=excluded.hours_per_person,revision=oqc_capacity_day.revision+1,updated_by=auth.uid(),updated_at=clock_timestamp() returning * into dayrow;
 insert into oqc_capacity_plan(work_date,product_code,planned_qty,standard_version_id,seconds_per_piece,updated_by,source_kind,source_plan_id,oqc_plan_id)
 values(d,code,qty,norm.id,norm.seconds_per_piece,auth.uid(),kind,sourceid,target.id)
 on conflict(work_date,product_code) do update set planned_qty=excluded.planned_qty,standard_version_id=excluded.standard_version_id,seconds_per_piece=excluded.seconds_per_piece,updated_by=auth.uid(),updated_at=clock_timestamp(),source_kind=excluded.source_kind,source_plan_id=excluded.source_plan_id,oqc_plan_id=excluded.oqc_plan_id;
 insert into oqc_capacity_audit(entity,record_key,before_data,after_data,actor_id,actor_name) values('plan',d||':'||code,beforedata,jsonb_build_object('plan',(select to_jsonb(p) from oqc_capacity_plan p where work_date=d and product_code=code),'hours',hrs),auth.uid(),actor);
 perform set_config('mes.qc_plan_origin','',true);
 return dayrow.revision;
end$$;

-- Forward-only sync for user edits of OQC weekly quantities. Never sums imported quantities.
create or replace function public.qc_sync_oqc_week()
returns trigger language plpgsql security definer set search_path=public as $$
declare i integer; d date; qty numeric; prevqty numeric; col text; p oqc_capacity_plan%rowtype; norm oqc_work_standard_version%rowtype; beforedata jsonb;
begin
 if current_setting('mes.qc_plan_origin',true)='linked_rpc' then return new;end if;
 if tg_op='UPDATE' and old.cong_doan='OQC' and new.cong_doan<>'OQC' and exists(select 1 from oqc_capacity_plan where oqc_plan_id=old.id) then raise exception 'Dòng đang liên kết kế hoạch kiểm tra OQC; không chuyển công đoạn của dòng này';end if;
 if new.cong_doan<>'OQC' then return new;end if;
 if auth.uid() is null then raise exception 'Cần đăng nhập để sửa kế hoạch OQC liên kết';end if;
 if tg_op='UPDATE' and new.tuan_bat_dau is distinct from old.tuan_bat_dau and exists(select 1 from oqc_capacity_plan where oqc_plan_id=old.id) then raise exception 'Dòng OQC đã liên kết kế hoạch kiểm tra; tạo dòng riêng cho tuần khác để bảo toàn ngày lịch sử';end if;
 for i in 1..7 loop
  col:=(array['t2','t3','t4','t5','t6','t7','cn'])[i];d:=new.tuan_bat_dau+i-1;qty:=coalesce((to_jsonb(new)->>col)::numeric,0);prevqty:=case when tg_op='INSERT' then 0 else coalesce((to_jsonb(old)->>col)::numeric,0) end;
  if tg_op='UPDATE' and qty=prevqty and new.ma_sp is not distinct from old.ma_sp then continue;end if;
  if qty<0 or qty<>trunc(qty) then raise exception 'Số lượng kế hoạch OQC phải là số PCS nguyên không âm';end if;
  perform pg_advisory_xact_lock(hashtextextended('oqc-plan:'||d::text,0));
  select * into p from oqc_capacity_plan where work_date=d and product_code=(case when tg_op='UPDATE' and new.ma_sp is distinct from old.ma_sp then old.ma_sp else new.ma_sp end) for update;
  if p.oqc_plan_id is not null and p.oqc_plan_id<>new.id then raise exception 'Ngày/model đã liên kết dòng OQC khác';end if;
  beforedata:=case when p.work_date is null then null else to_jsonb(p) end;
  if qty=0 then
   if p.oqc_plan_id=new.id then delete from oqc_capacity_plan where work_date=d and product_code=p.product_code;else continue;end if;
  else
   norm:=null;
   if p.work_date is null or (tg_op='UPDATE' and new.ma_sp is distinct from old.ma_sp) then select * into norm from oqc_work_standard_version where product_code=new.ma_sp and effective_from<=d order by effective_from desc,id desc limit 1;
   else norm.id:=p.standard_version_id;norm.seconds_per_piece:=p.seconds_per_piece;end if;
   if p.work_date is not null and p.product_code<>new.ma_sp then
    if exists(select 1 from oqc_capacity_plan where work_date=d and product_code=new.ma_sp) then raise exception 'Model mới đã có kế hoạch ngày này; không gộp hoặc ghi đè tự động';end if;
    update oqc_capacity_plan set product_code=new.ma_sp,standard_version_id=norm.id,seconds_per_piece=norm.seconds_per_piece,source_kind='oqc',source_plan_id=new.id where work_date=d and product_code=p.product_code;
   end if;
   insert into oqc_capacity_day(work_date,hours_per_person,updated_by) values(d,null,auth.uid()) on conflict(work_date) do nothing;
   insert into oqc_capacity_plan(work_date,product_code,planned_qty,standard_version_id,seconds_per_piece,updated_by,source_kind,source_plan_id,oqc_plan_id)
   values(d,new.ma_sp,qty,norm.id,norm.seconds_per_piece,auth.uid(),'oqc',new.id,new.id)
   on conflict(work_date,product_code) do update set planned_qty=excluded.planned_qty,oqc_plan_id=new.id,updated_by=auth.uid(),updated_at=clock_timestamp();
  end if;
  update oqc_capacity_day set revision=revision+1,updated_by=auth.uid(),updated_at=clock_timestamp() where work_date=d;
  insert into oqc_capacity_audit(entity,record_key,before_data,after_data,actor_id,actor_name) values('plan',d||':'||new.ma_sp,beforedata,(select to_jsonb(x) from oqc_capacity_plan x where work_date=d and product_code=new.ma_sp),auth.uid(),oqc_capacity_actor());
 end loop;
 return new;
end$$;
drop trigger if exists qc_sync_oqc_week on public.cd_khsx_tuan_plan;
create trigger qc_sync_oqc_week after insert or update on public.cd_khsx_tuan_plan for each row execute function public.qc_sync_oqc_week();

create or replace function public.qc_save_week_hours(p_week date,p_hours jsonb,p_reason text default '')
returns void language plpgsql security definer set search_path=public as $$
declare item record; d date; hrs numeric; beforedata jsonb; logged jsonb;
begin
 if auth.uid() is null or not has_role('admin','qc_manager','nhan_vien_oqc','ke_hoach','qlsx_truong_phong') then raise exception 'Không có quyền lưu giờ kế hoạch QC';end if;
 if extract(isodow from p_week)<>1 or jsonb_typeof(p_hours) is distinct from 'object' then raise exception 'Tuần/giờ không hợp lệ';end if;
 if p_hours<>'{}'::jsonb then
  logged:=khsx_ghi_log_sua(p_week,'OQC','sua','Giờ kế hoạch kiểm tra','',p_hours::text,coalesce(p_reason,''),oqc_capacity_actor());
  if coalesce((logged->>'ok')::boolean,false)=false then raise exception '%',logged->>'error';end if;
 end if;
 for item in select * from jsonb_each_text(p_hours) loop
  if item.key !~ '^[0-6]$' then raise exception 'Ngày trong tuần không hợp lệ';end if;
  d:=p_week+item.key::int;hrs:=oqc_capacity_number(item.value);if hrs>24 then raise exception 'Giờ/người không quá 24';end if;
  perform pg_advisory_xact_lock(hashtextextended('oqc-plan:'||d::text,0));
  select to_jsonb(x) into beforedata from oqc_capacity_day x where work_date=d for update;
  insert into oqc_capacity_day(work_date,hours_per_person,updated_by) values(d,hrs,auth.uid()) on conflict(work_date) do update set hours_per_person=hrs,revision=oqc_capacity_day.revision+1,updated_by=auth.uid(),updated_at=clock_timestamp();
  insert into oqc_capacity_audit(entity,record_key,before_data,after_data,actor_id,actor_name) values('plan',d||':hours',beforedata,(select to_jsonb(x) from oqc_capacity_day x where work_date=d),auth.uid(),oqc_capacity_actor());
 end loop;
end$$;

-- Invoker keeps existing weekly-table RLS. Quantity + hours save atomically.
create or replace function public.qc_save_oqc_week(p_id bigint,p_data jsonb,p_hours jsonb)
returns bigint language plpgsql security invoker set search_path=public as $$
declare v_id bigint; code text:=p_data->>'ma_sp'; mon date:=(p_data->>'tuan_bat_dau')::date;
begin
 if auth.uid() is null or (p_data->>'cong_doan') is distinct from 'OQC' then raise exception 'Chỉ dùng cho kế hoạch OQC đã đăng nhập';end if;
 perform pg_advisory_xact_lock(hashtextextended('qc-week:'||mon::text,0));
 if p_id is not null then
  update cd_khsx_tuan_plan set ma_sp=code,ten_sp=p_data->>'ten_sp',t2=(p_data->>'t2')::numeric,t3=(p_data->>'t3')::numeric,t4=(p_data->>'t4')::numeric,t5=(p_data->>'t5')::numeric,t6=(p_data->>'t6')::numeric,t7=(p_data->>'t7')::numeric,cn=(p_data->>'cn')::numeric,kh_tuan=(p_data->>'kh_tuan')::numeric,ghi_chu=p_data->>'ghi_chu',updated_by=p_data->>'updated_by',updated_at=clock_timestamp() where id=p_id and cong_doan='OQC' and tuan_bat_dau=mon returning id into v_id;
  if v_id is null then raise exception 'Không tìm thấy đúng dòng nguồn OQC';end if;
 else
  insert into cd_khsx_tuan_plan(tuan_bat_dau,cong_doan,ma_sp,ten_sp,t2,t3,t4,t5,t6,t7,cn,kh_tuan,ghi_chu,updated_by)
  values(mon,'OQC',code,p_data->>'ten_sp',(p_data->>'t2')::numeric,(p_data->>'t3')::numeric,(p_data->>'t4')::numeric,(p_data->>'t5')::numeric,(p_data->>'t6')::numeric,(p_data->>'t7')::numeric,(p_data->>'cn')::numeric,(p_data->>'kh_tuan')::numeric,p_data->>'ghi_chu',p_data->>'updated_by') returning id into v_id;
 end if;
 if p_hours<>'{}'::jsonb then perform qc_save_week_hours(mon,p_hours,p_data->>'qc_reason');end if;
 return v_id;
end$$;
revoke all on function public.qc_sync_oqc_week() from public,anon,authenticated;
revoke all on function public.qc_save_linked_plan(jsonb),public.qc_save_week_hours(date,jsonb,text),public.qc_save_oqc_week(bigint,jsonb,jsonb) from public,anon;
grant execute on function public.qc_save_linked_plan(jsonb),public.qc_save_week_hours(date,jsonb,text),public.qc_save_oqc_week(bigint,jsonb,jsonb) to authenticated;
commit;
