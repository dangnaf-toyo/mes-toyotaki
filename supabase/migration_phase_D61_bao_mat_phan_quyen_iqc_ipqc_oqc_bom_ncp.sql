-- D61: Vá bảo mật + phân quyền cho các chức năng IQC / Duyệt tiếp tục SX IPQC
-- / OQC kiểm tra xuất hàng / BOM / cách ly NCP (các file T66, T67, T68, T69,
-- S9, T61 — trước đây T36/T38/supabase/migrations/…, đã đổi số).
--
-- 1) Mọi hàm "security definer" của các chức năng trên mặc định được PUBLIC
--    EXECUTE → gọi được qua /rest/v1/rpc/... khi CHƯA đăng nhập (đã thử thật
--    trên staging với duc_ipqc_refresh_continue_request). Thu hồi quyền của
--    public/anon, chỉ cấp cho authenticated. Chạy dạng vòng lặp theo tên hàm
--    nên không cần chép tay chữ ký; hàm nào chưa tồn tại trên project này (VD
--    BOM chưa chạy T61) thì tự bỏ qua.
-- 2) duc_ipqc_decide_continue_request: trước chỉ kiểm tra đã đăng nhập → ai
--    cũng duyệt được mọi bước, kể cả "Phê duyệt trực tiếp". Nay theo vai trò:
--      B1 QL Chất lượng           : qc_manager
--      B2 KHSX                     : ke_hoach, qlsx_truong_phong
--      B3 QL Đúc/Bộ phận sản xuất  : quan_ly_bo_phan, truong_ca
--      B4 GĐ Sản xuất              : giam_doc_sx
--      Phê duyệt trực tiếp         : giam_doc_sx
--      admin duyệt được mọi bước. Tên người duyệt lấy từ user_roles theo tài
--      khoản đang đăng nhập, không tin tên do trình duyệt gửi lên.
-- 3) duc_ipqc_cancel_continue_request: chỉ người tạo yêu cầu, qc_manager,
--    giam_doc_sx hoặc admin được huỷ (trước: ai đăng nhập cũng huỷ được).
-- 4) IQC: chỉ admin/qc_manager được XOÁ LOT/lỗi IQC (trước: ai đăng nhập cũng xoá được).
--
-- Chạy trên CẢ 2 project (production + staging) — trên production chỉ có tác
-- dụng sau khi đã chạy các file T66-T69/S9/T61; chạy trước cũng không lỗi.

-- ── 1) Thu hồi quyền gọi hàm khi chưa đăng nhập ─────────────────────────────
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and p.prorettype <> 'trigger'::regtype
      and p.proname = any (array[
        'duc_ipqc_create_continue_request','duc_ipqc_decide_continue_request',
        'duc_ipqc_refresh_continue_request','duc_ipqc_update_continue_production',
        'duc_ipqc_cancel_continue_request','duc_ipqc_can_continue',
        'oqc_save_daily_inspection','bom_save_version',
        'duc_ncp_cach_ly_tem','duc_ncp_giai_toa_tem','duc_ncp_giai_toa_tem_v2',
        'duc_ncp_xac_nhan_task','duc_ncp_cach_ly_task',
        'oqc_them_tem_vao_pallet','cd_xac_nhan_chuyen','oqc_dong_pallet',
        'oqc_pallet_nhap_kho','duc_ghi_nhan_tem_kanban'
      ])
  loop
    execute format('revoke execute on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end $$;

-- ── 2) Duyệt theo vai trò ────────────────────────────────────────────────────
create or replace function public.duc_ipqc_step_roles(p_step integer)
returns text[] language sql immutable as $$
  select case p_step
    when 1 then array['qc_manager']
    when 2 then array['ke_hoach','qlsx_truong_phong']
    when 3 then array['quan_ly_bo_phan','truong_ca']
    when 4 then array['giam_doc_sx']
    else array[]::text[] end;
$$;

create or replace function public.duc_ipqc_current_user_name()
returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(trim(full_name), ''), email)
  from user_roles where user_id = auth.uid();
$$;
revoke execute on function public.duc_ipqc_current_user_name() from public, anon;

create or replace function public.duc_ipqc_decide_continue_request(p_request_id bigint, p_decision text, p_actor text, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
declare
  r duc_ipqc_continue_request%rowtype;
  v_scope text; v_until timestamptz;
  v_actor text;
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
  v_actor := coalesce(duc_ipqc_current_user_name(), p_actor);

  select * into r from duc_ipqc_continue_request where id = p_request_id for update;
  if not found then raise exception 'Không tìm thấy yêu cầu %', p_request_id; end if;
  if r.status in ('Từ chối','Đã hủy','Đang có hiệu lực','Hết hiệu lực') then raise exception 'Yêu cầu không còn ở trạng thái có thể duyệt'; end if;

  if p_decision = 'Phê duyệt trực tiếp' then
    if not has_role('admin','giam_doc_sx') then
      raise exception 'Chỉ GĐ Sản xuất được Phê duyệt trực tiếp';
    end if;
  elsif p_decision in ('Duyệt','Từ chối') then
    if not has_role(variadic (array['admin'] || duc_ipqc_step_roles(r.current_step))) then
      raise exception 'Tài khoản của bạn không có quyền duyệt bước % (%)', r.current_step,
        (select approval_level from duc_ipqc_continue_approval where request_id = r.id and step_no = r.current_step);
    end if;
  else
    raise exception 'Quyết định không hợp lệ';
  end if;

  v_until := coalesce(r.allowed_until, case when r.allowed_hours > 0 then now() + make_interval(secs => (r.allowed_hours * 3600)::int) end);
  v_scope := case r.reason_type
    when 'TIME' then 'Được phép chạy đến ' || to_char(v_until at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
    when 'PLAN_QTY' then 'Được phép chạy thêm ' || r.allowed_qty || ' pcs'
    when 'DOWNSTREAM_REWORK' then 'Được phép chạy ' || r.allowed_qty || ' pcs để ' || r.repair_department || ' sửa/lựa'
    else 'Cảnh báo sớm: điều chỉnh máy/khuôn/thông số' end;

  if p_decision = 'Từ chối' then
    update duc_ipqc_continue_approval set decision = 'Từ chối', decided_by = auth.uid(), decided_by_name = v_actor, decided_at = now(), note = p_note
      where request_id = r.id and step_no = r.current_step;
    update duc_ipqc_continue_request set status = 'Từ chối' where id = r.id;
  elsif p_decision = 'Phê duyệt trực tiếp' then
    if nullif(trim(p_note), '') is null then raise exception 'Phê duyệt trực tiếp bắt buộc nhập lý do'; end if;
    update duc_ipqc_continue_approval set decision = case when step_no = 4 then 'Duyệt' else 'Bỏ qua bởi GĐ Sản xuất' end,
      decided_by = auth.uid(), decided_by_name = v_actor, decided_at = now(), note = p_note
      where request_id = r.id and decision is null;
    update duc_ipqc_continue_request set status = 'Đang có hiệu lực', current_step = 4, is_override = true, override_reason = p_note,
      effective_at = now(), expired_at = v_until, approved_scope = v_scope where id = r.id;
  else -- Duyệt
    update duc_ipqc_continue_approval set decision = 'Duyệt', decided_by = auth.uid(), decided_by_name = v_actor, decided_at = now(), note = p_note
      where request_id = r.id and step_no = r.current_step;
    if r.current_step < 4 then
      update duc_ipqc_continue_request set status = 'Đang duyệt', current_step = r.current_step + 1 where id = r.id;
    else
      update duc_ipqc_continue_request set status = 'Đang có hiệu lực', current_step = 4, effective_at = now(),
        expired_at = v_until, approved_scope = v_scope where id = r.id;
    end if;
  end if;

  insert into duc_ipqc_continue_audit(request_id, action, actor_id, actor_name, detail)
  values (r.id, upper(p_decision), auth.uid(), v_actor, jsonb_build_object('step', r.current_step, 'note', p_note));
end $$;

-- ── 3) Huỷ yêu cầu: chỉ người tạo / QL chất lượng / GĐ SX / admin ───────────
create or replace function public.duc_ipqc_cancel_continue_request(p_request_id bigint, p_actor text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_requester uuid; v_actor text;
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'Bắt buộc nhập lý do hủy'; end if;
  select requester_id into v_requester from duc_ipqc_continue_request where id = p_request_id;
  if v_requester is distinct from auth.uid() and not has_role('admin','qc_manager','giam_doc_sx') then
    raise exception 'Chỉ người tạo yêu cầu, QL Chất lượng hoặc GĐ Sản xuất được hủy';
  end if;
  v_actor := coalesce(duc_ipqc_current_user_name(), p_actor);
  update duc_ipqc_continue_request set status = 'Đã hủy' where id = p_request_id and status in ('Chờ duyệt','Đang duyệt','Đã duyệt');
  if not found then raise exception 'Yêu cầu không thể hủy ở trạng thái hiện tại'; end if;
  insert into duc_ipqc_continue_audit(request_id, action, actor_id, actor_name, detail)
  values (p_request_id, 'HỦY YÊU CẦU', auth.uid(), v_actor, jsonb_build_object('reason', p_reason));
end $$;

revoke execute on function public.duc_ipqc_decide_continue_request(bigint,text,text,text) from public, anon;
grant execute on function public.duc_ipqc_decide_continue_request(bigint,text,text,text) to authenticated;
revoke execute on function public.duc_ipqc_cancel_continue_request(bigint,text,text) from public, anon;
grant execute on function public.duc_ipqc_cancel_continue_request(bigint,text,text) to authenticated;

-- ── 4) IQC: chỉ admin / QL chất lượng được xoá ──────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['iqc_lots','iqc_defects','iqc_appearance_defects'] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop policy if exists "authenticated delete %1$s" on public.%1$s', t);
      execute format('drop policy if exists "qc delete %1$s" on public.%1$s', t);
      execute format('create policy "qc delete %1$s" on public.%1$s for delete using (public.has_role(''admin'',''qc_manager''))', t);
    end if;
  end loop;
end $$;
