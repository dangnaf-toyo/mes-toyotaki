-- Hoàn tác T242: về duc_ipqc_session / duc_ipqc_session_submit_time của T118. Giữ bảng log (chỉ là dữ liệu điều tra).
begin;
drop function if exists public.duc_ipqc_session(text, boolean, boolean);
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
grant execute on function public.duc_ipqc_session(text, boolean) to authenticated;
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
drop function if exists public.duc_ipqc_phien_dang_kiem();
drop function if exists public.duc_ipqc_ten_nguoi(uuid);
commit;
