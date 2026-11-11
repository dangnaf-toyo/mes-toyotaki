-- T242: IPQC — hàng đợi hiện trạng thái "Chờ kiểm / Đang kiểm: ai, từ mấy giờ";
--       người khác bấm Bắt đầu khi đã có người kiểm → cảnh báo, hỏi "kiểm thay?",
--       đồng ý thì chuyển phiên sang người mới và ghi log để điều tra sau.
-- Trạng thái: ĐÃ chạy staging jcjbleugnclzsghfpmvk 11/11/2026 (test 2 tài khoản giả lập đạt); CHƯA chạy prod fgghikpzcxjqzahfiiil.
-- Phụ thuộc: T118 (duc_ipqc_inspection_session, duc_ipqc_session).
-- Hoàn tác: supabase/rollback_T242_ipqc_dang_kiem_kiem_thay.sql
begin;

-- 1. Log kiểm thay ----------------------------------------------------------
create table if not exists public.duc_ipqc_phien_kiem_thay_log (
  id            bigserial primary key,
  checkpoint_id text not null,
  ma_may        text,
  ma_sp         text,
  id_dong       text,
  owner_cu      uuid,
  ten_cu        text,
  started_at_cu timestamptz,
  owner_moi     uuid not null,
  ten_moi       text,
  thoi_diem     timestamptz not null default clock_timestamp()
);
create index if not exists idx_ipqc_kiem_thay_log_cp on public.duc_ipqc_phien_kiem_thay_log(checkpoint_id);
alter table public.duc_ipqc_phien_kiem_thay_log enable row level security;
revoke all on public.duc_ipqc_phien_kiem_thay_log from anon, authenticated;
grant select on public.duc_ipqc_phien_kiem_thay_log to authenticated;
drop policy if exists "xem log kiem thay" on public.duc_ipqc_phien_kiem_thay_log;
create policy "xem log kiem thay" on public.duc_ipqc_phien_kiem_thay_log for select to authenticated
  using (owner_cu = auth.uid() or owner_moi = auth.uid() or public.has_role('admin','qc_manager'));

-- 2. Tên hiển thị người dùng (helper nội bộ, không cấp execute ra ngoài) ----
create or replace function public.duc_ipqc_ten_nguoi(p_uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select case when nullif(trim(r.username),'') is not null and nullif(trim(r.full_name),'') is not null
                 then trim(r.username) || '_' || trim(r.full_name)
                 else coalesce(nullif(trim(r.username),''), nullif(trim(r.full_name),''), r.email) end
       from user_roles r where r.user_id = p_uid limit 1),
    (select u.email from auth.users u where u.id = p_uid),
    p_uid::text);
$$;
revoke execute on function public.duc_ipqc_ten_nguoi(uuid) from public, anon, authenticated;

-- 3. Danh sách phiên đang kiểm (cho hàng đợi) -----------------------------
create or replace function public.duc_ipqc_phien_dang_kiem()
returns table (checkpoint_id text, owner_id uuid, ten_nguoi text, started_at timestamptz, la_toi boolean)
language sql stable security definer set search_path = public as $$
  select s.checkpoint_id, s.owner_id, public.duc_ipqc_ten_nguoi(s.owner_id), s.started_at, s.owner_id = auth.uid()
    from duc_ipqc_inspection_session s
    join duc_ipqc_checkpoint cp on cp.id_checkpoint = s.checkpoint_id
   where auth.uid() is not null and s.completed_at is null and cp.trang_thai = 'cho_kiem';
$$;
revoke execute on function public.duc_ipqc_phien_dang_kiem() from public, anon;
grant execute on function public.duc_ipqc_phien_dang_kiem() to authenticated;

-- 4. duc_ipqc_session: thêm p_kiem_thay ---------------------------------------
-- Bỏ bản 2 tham số để PostgREST không nhầm giữa 2 bản (gọi 2 tham số vẫn chạy nhờ default).
drop function if exists public.duc_ipqc_session(text, boolean);
create or replace function public.duc_ipqc_session(p_checkpoint text, p_start boolean default false, p_kiem_thay boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $q$
declare cp public.duc_ipqc_checkpoint%rowtype; s public.duc_ipqc_inspection_session%rowtype;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
 select * into cp from duc_ipqc_checkpoint where id_checkpoint = p_checkpoint for update;
 if not found then raise exception 'Không tìm thấy đúng điểm kiểm'; end if;
 select * into s from duc_ipqc_inspection_session where checkpoint_id = p_checkpoint;
 if found and s.owner_id <> auth.uid() then
   if s.completed_at is not null then raise exception 'Điểm kiểm đã được người khác hoàn tất'; end if;
   if not p_start then
     -- Chỉ xem: báo cho màn hình biết ai đang kiểm để hỏi "kiểm thay?".
     return jsonb_build_object('session', null,
       'nguoi_khac', jsonb_build_object('owner_id', s.owner_id, 'ten', public.duc_ipqc_ten_nguoi(s.owner_id), 'started_at', s.started_at),
       'server_now', clock_timestamp());
   end if;
   if not p_kiem_thay then raise exception 'Phiên kiểm đang thuộc người kiểm khác'; end if;
   if not public.has_role('admin','ipqc','qc_manager') then raise exception 'Tài khoản không có quyền bắt đầu kiểm IPQC'; end if;
   if cp.trang_thai <> 'cho_kiem' then raise exception 'Điểm kiểm không còn chờ kiểm'; end if;
   insert into duc_ipqc_phien_kiem_thay_log(checkpoint_id, ma_may, ma_sp, id_dong, owner_cu, ten_cu, started_at_cu, owner_moi, ten_moi)
   values (p_checkpoint, cp.ma_may, cp.ma_sp, cp.id_dong, s.owner_id, public.duc_ipqc_ten_nguoi(s.owner_id), s.started_at,
           auth.uid(), public.duc_ipqc_ten_nguoi(auth.uid()));
   -- Chuyển phiên: người mới sở hữu, tính giờ kiểm từ lúc kiểm thay.
   update duc_ipqc_inspection_session
      set owner_id = auth.uid(), started_at = clock_timestamp(), submission_at = null,
          machine = cp.ma_may, product_code = cp.ma_sp, job_id = cp.id_dong
    where checkpoint_id = p_checkpoint returning * into s;
   return jsonb_build_object('session', to_jsonb(s), 'kiem_thay', true, 'server_now', clock_timestamp());
 end if;
 if s.checkpoint_id is null and p_start then
   if not public.has_role('admin','ipqc','qc_manager') then raise exception 'Tài khoản không có quyền bắt đầu kiểm IPQC'; end if;
   if cp.trang_thai <> 'cho_kiem' then raise exception 'Điểm kiểm không còn chờ kiểm'; end if;
   insert into duc_ipqc_inspection_session(checkpoint_id, owner_id, machine, product_code, job_id)
   values (p_checkpoint, auth.uid(), cp.ma_may, cp.ma_sp, cp.id_dong) returning * into s;
 end if;
 return jsonb_build_object('session', case when s.checkpoint_id is null then null else to_jsonb(s) end, 'server_now', clock_timestamp());
end $q$;
revoke execute on function public.duc_ipqc_session(text, boolean, boolean) from public, anon;
grant execute on function public.duc_ipqc_session(text, boolean, boolean) to authenticated;

-- 5. Người bị kiểm thay bấm Lưu → báo rõ thay vì "Hãy bấm Bắt đầu kiểm tra cho đúng phiên".
create or replace function public.duc_ipqc_session_submit_time(p_checkpoint text, p_clear boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $q$
declare s public.duc_ipqc_inspection_session%rowtype; o public.duc_ipqc_inspection_session%rowtype;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
 perform 1 from duc_ipqc_checkpoint where id_checkpoint = p_checkpoint and trang_thai = 'cho_kiem' for update;
 if not found then raise exception 'Điểm kiểm không còn chờ kiểm'; end if;
 update duc_ipqc_inspection_session set submission_at = case when p_clear then null else clock_timestamp() end
  where checkpoint_id = p_checkpoint and owner_id = auth.uid() and completed_at is null returning * into s;
 if not found then
   select * into o from duc_ipqc_inspection_session where checkpoint_id = p_checkpoint and owner_id <> auth.uid();
   if found then raise exception 'Phiên kiểm này đã được % kiểm thay lúc %', public.duc_ipqc_ten_nguoi(o.owner_id), to_char(o.started_at at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'); end if;
   raise exception 'Hãy bấm Bắt đầu kiểm tra cho đúng phiên';
 end if;
 return to_jsonb(s);
end $q$;

commit;
