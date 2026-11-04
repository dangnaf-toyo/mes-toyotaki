-- T212 — Rà soát toàn hệ thống 04/11/2026, ĐỢT 1 (bảo mật & toàn vẹn dữ liệu): R1–R7 trong VIEC_CON_TREO.md mục R.
--   R1  Hàm SECURITY DEFINER nhóm A (duyệt / phát hành / kho / KH / sửa-xoá dữ liệu đã chốt) kiểm vai trò bằng has_role;
--       tên người thao tác lấy từ tài khoản đăng nhập (không tin p_user / p_nguoi do trình duyệt gửi).
--       auth.uid() null (cron / hàm nội bộ) vẫn được chạy — anon không có quyền EXECUTE nên không lợi dụng được.
--       Nhóm B (thao tác xưởng thường ngày: quét tem, Bavia, công đoạn, in tem) để đợt sau.
--   R2  Thu hồi EXECUTE của authenticated trên các hàm chỉ gọi nội bộ (gồm duc_submit_ipqc_check — lách T170).
--   R3  6 bucket: bỏ quyền LIỆT KÊ / đọc qua API cho anon (chỉ authenticated). URL /object/public/ đã lưu vẫn mở được.
--   R4  RLS ghi theo vai trò: KHSX tuần, báo cáo tuần vấn đề, IQC, tài liệu bên ngoài.
--   R5  Sửa / xoá sự cố + kết ca theo vai trò; ca đã có báo cáo chỉ QLBP / TP QLSX / admin sửa-xoá; thời gian dừng ≤ 14 giờ.
--   R6  Vai trò 'chi_xem' cho tài khoản màn hình TV.
--   R7  2 view security_invoker; thu hồi quyền thừa của anon.

-- ── Tên người thao tác chuẩn "mã_Họ tên" theo tài khoản đăng nhập ─────────────
create or replace function public.duc_ten_nguoi_hien_tai(p_du_phong text default null) returns text
language sql stable security definer set search_path to 'public' as $$
  select case when auth.uid() is null then p_du_phong else coalesce(
    (select coalesce(nullif(trim(username), '') || '_' || nullif(trim(full_name), ''), nullif(trim(full_name), ''), email)
       from user_roles where user_id = auth.uid()),
    nullif(auth.jwt()->>'email', ''), p_du_phong) end;
$$;
grant execute on function public.duc_ten_nguoi_hien_tai(text) to authenticated;
revoke execute on function public.duc_ten_nguoi_hien_tai(text) from public, anon;

-- ── Bộ chèn kiểm quyền vào đầu thân hàm (sau dòng "begin" đầu tiên) ──────────
create or replace function pg_temp.t212_va(p_sig text, p_roles text[], p_nhan text, p_tham_so_nguoi text, p_them text default '')
returns text language plpgsql as $f$
declare d text; n text; v_inj text;
begin
  d := pg_get_functiondef(p_sig::regprocedure);
  if position('-- T212' in d) > 0 then return p_sig || ': đã vá trước'; end if;
  v_inj := E'  if auth.uid() is not null and not public.has_role(VARIADIC ARRAY['
    || (select string_agg(quote_literal(r), ', ') from unnest(p_roles) r)
    || E']) then\n    raise exception ''⛔ Tài khoản không có quyền thực hiện thao tác này — cần vai trò: %'', '
    || quote_literal(p_nhan) || E' using errcode = ''42501'';\n  end if;   -- T212\n'
    || case when coalesce(p_tham_so_nguoi, '') <> ''
            then '  ' || p_tham_so_nguoi || ' := public.duc_ten_nguoi_hien_tai(' || p_tham_so_nguoi || E');   -- T212: tên theo tài khoản\n'
            else '' end
    || coalesce(p_them, '');
  n := regexp_replace(d, E'(\\n[ \\t]*begin[ \\t]*\\r?\\n)', E'\\1' || replace(v_inj, '\', '\\'), 'i');
  if n = d then raise exception 'T212: không tìm được dòng begin trong %', p_sig; end if;
  execute n;
  execute 'alter function ' || p_sig || ' set search_path = public';
  return p_sig || ': ok';
end $f$;

-- ── R1 + R5: vá hàm ─────────────────────────────────────────────────────────
select pg_temp.t212_va(s, r, l, u, coalesce(t, '')) from (values
  -- NCP: duyệt / phế / giải toả / mở lại → QC Manager
  ('public.duc_ncp_approve_root_cause(text,text,text,text)', array['admin','qc_manager'], 'QC Manager', 'p_user', null),
  ('public.duc_ncp_approve_scrap(text,text,text,text)', array['admin','qc_manager'], 'QC Manager', 'p_user', null),
  ('public.duc_ncp_reopen_root_cause(text,text)', array['admin','qc_manager'], 'QC Manager', 'p_user', null),
  ('public.duc_ncp_giai_toa_tem_v2(text,text,text,text)', array['admin','qc_manager'], 'QC Manager', 'p_user', null),
  -- NCP: thao tác xử lý → QC + quản lý SX
  ('public.duc_ncp_record_sorting(text,numeric,numeric,text)', array['admin','qc_manager','ipqc','nhan_vien_oqc','iqc','quan_ly_bo_phan','truong_ca','qlsx_truong_phong'], 'QC / QLBP / trưởng ca', 'p_user', null),
  ('public.duc_ncp_record_repair(text,numeric,numeric,text)', array['admin','qc_manager','ipqc','nhan_vien_oqc','iqc','quan_ly_bo_phan','truong_ca','qlsx_truong_phong'], 'QC / QLBP / trưởng ca', 'p_user', null),
  ('public.duc_ncp_request_scrap(text,numeric,text,text)', array['admin','qc_manager','ipqc','nhan_vien_oqc','iqc','quan_ly_bo_phan','truong_ca','qlsx_truong_phong'], 'QC / QLBP / trưởng ca', 'p_user', null),
  ('public.duc_ncp_choose_sua(text,text,text)', array['admin','qc_manager','ipqc','nhan_vien_oqc','iqc','quan_ly_bo_phan','truong_ca','qlsx_truong_phong'], 'QC / QLBP / trưởng ca', 'p_user', null),
  ('public.duc_ncp_submit_root_cause_for_approval(text,text)', array['admin','qc_manager','ipqc','nhan_vien_oqc','iqc','quan_ly_bo_phan','truong_ca','qlsx_truong_phong'], 'QC / QLBP / trưởng ca', 'p_user', null),
  -- Tài liệu
  ('public.doc_revoke_version(uuid)', array['admin','iatf_admin'], 'IATF admin', null, null),
  -- NVL
  ('public.nvl_add_transaction(date,text,text,numeric,text,text)', array['admin','kho_nvl','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong'], 'Kho NVL / Kế hoạch / QLSX', 'p_user', null),
  ('public.nvl_create_tem(text,text,date,text,text,jsonb,text)', array['admin','kho_nvl','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong'], 'Kho NVL / Kế hoạch / QLSX', 'p_user', null),
  ('public.nvl_process_multi_transaction(text,jsonb,text)', array['admin','kho_nvl','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong'], 'Kho NVL / Kế hoạch / QLSX', 'p_user', null),
  ('public.nvl_recalc_all_plan_stock(text)', array['admin','kho_nvl','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong'], 'Kho NVL / Kế hoạch / QLSX', 'p_user', null),
  ('public.nvl_update_opening(text,date,numeric,text)', array['admin','kho_nvl','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong'], 'Kho NVL / Kế hoạch / QLSX', 'p_user', null),
  ('public.nvl_update_plan_nhap(text,jsonb,text)', array['admin','kho_nvl','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong'], 'Kho NVL / Kế hoạch / QLSX', 'p_user', null),
  ('public.nvl_update_settings(text,numeric,text)', array['admin','kho_nvl','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong'], 'Kho NVL / Kế hoạch / QLSX', 'p_user', null),
  ('public.nvl_upsert_material(text,text,text)', array['admin','kho_nvl','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong'], 'Kho NVL / Kế hoạch / QLSX', 'p_user', null),
  -- Kho thành phẩm
  ('public.kho_dong_phieu_xuat(text,text)', array['admin','kho_nvl','nhan_vien_oqc','qc_manager','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong'], 'Kho / OQC / Kế hoạch / QLSX', 'p_nguoi', null),
  ('public.kho_nhap_kho_tem(text,text)', array['admin','kho_nvl','nhan_vien_oqc','qc_manager','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong'], 'Kho / OQC / Kế hoạch / QLSX', 'p_nguoi', null),
  ('public.kho_tao_phieu_xuat(text,text,text)', array['admin','kho_nvl','nhan_vien_oqc','qc_manager','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong'], 'Kho / OQC / Kế hoạch / QLSX', 'p_nguoi', null),
  ('public.kho_them_vao_phieu_xuat(text,text,text)', array['admin','kho_nvl','nhan_vien_oqc','qc_manager','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong'], 'Kho / OQC / Kế hoạch / QLSX', 'p_nguoi', null),
  ('public.oqc_pallet_nhap_kho(text,text)', array['admin','kho_nvl','nhan_vien_oqc','qc_manager','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong'], 'Kho / OQC / Kế hoạch / QLSX', 'p_nguoi', null),
  -- OQC pallet
  ('public.oqc_tao_pallet(text)', array['admin','nhan_vien_oqc','qc_manager'], 'OQC / QC Manager', 'p_nguoi', null),
  ('public.oqc_them_tem_vao_pallet(text,text,numeric,text)', array['admin','nhan_vien_oqc','qc_manager'], 'OQC / QC Manager', 'p_nguoi', null),
  ('public.oqc_dong_pallet(text)', array['admin','nhan_vien_oqc','qc_manager'], 'OQC / QC Manager', null, null),
  -- Đúc: kế hoạch máy / ca
  ('public.duc_delete_plan(text,text,text)', array['admin','truong_ca','quan_ly_bo_phan','qlsx_nhan_vien','qlsx_truong_phong','ke_hoach'], 'Trưởng ca / QLBP / QLSX / Kế hoạch', 'p_user', null),
  ('public.duc_extend_machine_shift(text,timestamptz,text,text,text)', array['admin','truong_ca','quan_ly_bo_phan','qlsx_nhan_vien','qlsx_truong_phong','ke_hoach'], 'Trưởng ca / QLBP / QLSX / Kế hoạch', 'p_user', null),
  ('public.duc_doi_phuong_an_ca(text,text,text)', array['admin','truong_ca','quan_ly_bo_phan','qlsx_nhan_vien','qlsx_truong_phong','ke_hoach'], 'Trưởng ca / QLBP / QLSX / Kế hoạch', 'p_user', null),
  ('public.khsx_ghi_log_sua(date,text,text,text,text,text,text,text)', array['admin','qlsx_nhan_vien','qlsx_truong_phong','ke_hoach','quan_ly_bo_phan'], 'QLSX / Kế hoạch / QLBP', 'p_user', null),
  -- R5: kết ca, sửa / xoá sự cố
  ('public.duc_end_shift(date,text,text,text,jsonb,text,text)', array['admin','truong_ca','quan_ly_bo_phan','qlsx_truong_phong'], 'Trưởng ca / QLBP / TP QLSX', 'p_user', null),
  ('public.duc_edit_incident(text,text,timestamptz,timestamptz,text,text,text,text,text)', array['admin','truong_ca','quan_ly_bo_phan','qlsx_truong_phong'], 'Trưởng ca / QLBP / TP QLSX', 'p_user',
     E'  if auth.uid() is not null and not public.has_role(''admin'', ''quan_ly_bo_phan'', ''qlsx_truong_phong'')\n'
  || E'     and exists (select 1 from duc_su_co_log l join duc_bao_cao_ca b on b.ngay = l.ngay and b.ca = l.ca where l.id_ban_ghi = p_id_ban_ghi) then\n'
  || E'    raise exception ''⛔ Ca của sự cố này đã chốt báo cáo — chỉ QLBP / Trưởng phòng QLSX / admin được sửa'' using errcode = ''42501'';\n'
  || E'  end if;   -- T212\n'
  || E'  if p_gio_phat_sinh is not null and p_gio_tro_lai is not null and p_gio_tro_lai - p_gio_phat_sinh > interval ''14 hours'' then\n'
  || E'    raise exception ''⛔ Thời gian dừng một bản ghi không quá 14 giờ (1 ca) — kiểm tra lại giờ phát sinh / giờ trở lại'';\n'
  || E'  end if;   -- T212\n'),
  ('public.duc_delete_incident(text,text,text,text)', array['admin','truong_ca','quan_ly_bo_phan','qlsx_truong_phong','qc_manager','ipqc'], 'Trưởng ca / QLBP / TP QLSX / QC', 'p_user',
     E'  if p_mode = ''closed'' and auth.uid() is not null and not public.has_role(''admin'', ''quan_ly_bo_phan'', ''qlsx_truong_phong'')\n'
  || E'     and (not public.has_role(''truong_ca'')\n'
  || E'          or exists (select 1 from duc_su_co_log l join duc_bao_cao_ca b on b.ngay = l.ngay and b.ca = l.ca where l.id_ban_ghi = p_id_ban_ghi)) then\n'
  || E'    raise exception ''⛔ Chỉ trưởng ca (ca chưa chốt báo cáo) / QLBP / Trưởng phòng QLSX / admin được xoá sự cố đã đóng'' using errcode = ''42501'';\n'
  || E'  end if;   -- T212\n')
) v(s, r, l, u, t);

-- ── R2: hàm chỉ gọi nội bộ / cron — thu hồi gọi trực tiếp ───────────────────
revoke execute on function public.duc_submit_ipqc_check(text,jsonb,text,jsonb,text,numeric,text),
  public.dcr_issue(uuid), public.dcr_check_overdue_confirmations(),
  public.duc_ncp_cach_ly_tem(text,text,text), public.duc_ncp_giai_toa_tem(text,text,text),
  public.duc_set_last_machine_shot(text,numeric), public.duc_record_mold_maintenance(text,text,numeric,numeric,text),
  public.duc_update_mold_shots_from_shift(date,text), public.duc_bulk_update_actuals(jsonb),
  public.duc_auto_close_forgotten_shifts()
  from public, anon, authenticated;
do $x$ begin
  if to_regprocedure('public.rls_auto_enable()') is not null then   -- chỉ có trên prod
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end $x$;
revoke execute on function public.kho_xoa_khoi_phieu_xuat(text,text) from public, anon;
-- kho_xoa_khoi_phieu_xuat (SQL) → plpgsql có kiểm quyền
create or replace function public.kho_xoa_khoi_phieu_xuat(p_id_phieu text, p_ma text) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if auth.uid() is not null and not public.has_role('admin','kho_nvl','nhan_vien_oqc','qc_manager','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong') then
    raise exception '⛔ Tài khoản không có quyền thực hiện thao tác này — cần vai trò: Kho / OQC / Kế hoạch / QLSX' using errcode = '42501';
  end if;   -- T212
  delete from kho_phieu_xuat_item where id_phieu = p_id_phieu and ma = p_ma;
end $$;
grant execute on function public.kho_xoa_khoi_phieu_xuat(text,text) to authenticated;

-- ── R3: storage — bỏ đọc / liệt kê cho anon ─────────────────────────────────
do $s$
declare b text;
begin
  foreach b in array array['cong-viec','ipqc-ban-ve','ipqc-evidence','khuon-bao-duong','report-files','su-co-duc'] loop
    execute format('drop policy if exists %I on storage.objects', 'public read ' || b);
    execute format('drop policy if exists %I on storage.objects', 'auth read ' || b);
    execute format('create policy %I on storage.objects for select to authenticated using (bucket_id = %L)', 'auth read ' || b, b);
  end loop;
end $s$;

-- ── R4: RLS ghi theo vai trò ────────────────────────────────────────────────
do $r$
declare t text; k text; v_khsx text := 'public.has_role(''admin'',''giam_doc_sx'',''qlsx_nhan_vien'',''qlsx_truong_phong'',''ke_hoach'',''quan_ly_bo_phan'')';
begin
  foreach t in array array['duc_khsx_tuan_plan','duc_khsx_tuan_so_ca','cd_khsx_tuan_plan'] loop
    k := case t when 'duc_khsx_tuan_plan' then 'khsx_tuan' when 'duc_khsx_tuan_so_ca' then 'khsx_so_ca' else 'cd_khsx_tuan' end;
    execute format('drop policy if exists %I on public.%I', k || ' authenticated delete', t);
    execute format('drop policy if exists %I on public.%I', k || ' authenticated update', t);
    execute format('drop policy if exists %I on public.%I', k || ' authenticated write', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (%s)', k || ' khsx write', t, v_khsx);
    execute format('create policy %I on public.%I for update to authenticated using (%s) with check (%s)', k || ' khsx update', t, v_khsx, v_khsx);
    execute format('create policy %I on public.%I for delete to authenticated using (%s)', k || ' khsx delete', t, v_khsx);
  end loop;
end $r$;

drop policy if exists "duc_bcttvd authenticated delete" on public.duc_bao_cao_tuan_van_de;
drop policy if exists "duc_bcttvd authenticated update" on public.duc_bao_cao_tuan_van_de;
drop policy if exists "duc_bcttvd authenticated write" on public.duc_bao_cao_tuan_van_de;
create policy "duc_bcttvd ql write" on public.duc_bao_cao_tuan_van_de for insert to authenticated
  with check (public.has_role('admin','giam_doc_sx','qlsx_truong_phong','quan_ly_bo_phan','qc_manager'));
create policy "duc_bcttvd ql update" on public.duc_bao_cao_tuan_van_de for update to authenticated
  using (public.has_role('admin','giam_doc_sx','qlsx_truong_phong','quan_ly_bo_phan','qc_manager'))
  with check (public.has_role('admin','giam_doc_sx','qlsx_truong_phong','quan_ly_bo_phan','qc_manager'));
create policy "duc_bcttvd ql delete" on public.duc_bao_cao_tuan_van_de for delete to authenticated
  using (public.has_role('admin','giam_doc_sx','qlsx_truong_phong','quan_ly_bo_phan','qc_manager'));

do $i$
declare t text;
begin
  foreach t in array array['iqc_lots','iqc_defects','iqc_appearance_defects'] loop
    execute format('drop policy if exists %I on public.%I', 'authenticated insert ' || t, t);
    execute format('drop policy if exists %I on public.%I', 'authenticated update ' || t, t);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.has_role(''admin'',''qc_manager'',''iqc'',''ipqc''))', 'qc insert ' || t, t);
    execute format('create policy %I on public.%I for update to authenticated using (public.has_role(''admin'',''qc_manager'',''iqc'',''ipqc'')) with check (public.has_role(''admin'',''qc_manager'',''iqc'',''ipqc''))', 'qc update ' || t, t);
  end loop;
end $i$;

drop policy if exists "write external_documents" on public.external_documents;
drop policy if exists "update external_documents" on public.external_documents;
create policy "tl write external_documents" on public.external_documents for insert to authenticated
  with check (public.has_role('admin','iatf_admin','qc_manager','giam_doc_sx','ke_hoach','qlsx_truong_phong'));
create policy "tl update external_documents" on public.external_documents for update to authenticated
  using (public.has_role('admin','iatf_admin','qc_manager','giam_doc_sx','ke_hoach','qlsx_truong_phong'))
  with check (public.has_role('admin','iatf_admin','qc_manager','giam_doc_sx','ke_hoach','qlsx_truong_phong'));
drop policy if exists "write external_checklist" on public.external_document_checklist;
create policy "tl write external_checklist" on public.external_document_checklist for all to authenticated
  using (public.has_role('admin','iatf_admin','qc_manager','giam_doc_sx','ke_hoach','qlsx_truong_phong'))
  with check (public.has_role('admin','iatf_admin','qc_manager','giam_doc_sx','ke_hoach','qlsx_truong_phong'));
drop policy if exists "write external_provisions" on public.external_document_provisions;
create policy "tl write external_provisions" on public.external_document_provisions for insert to authenticated
  with check (public.has_role('admin','iatf_admin','qc_manager','giam_doc_sx','ke_hoach','qlsx_truong_phong'));

-- ── R6: vai trò chỉ xem ─────────────────────────────────────────────────────
alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check (role = any (array[
  'admin','truong_ca','ipqc','qc_manager','kho_nvl','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong','quan_ly_bo_phan',
  'giam_doc_sx','nhan_vien_duc','nhan_vien_bavia','nhan_vien_gia_cong','nhan_vien_danh_bong','nhan_vien_oqc','nhan_vien_son',
  'iatf_admin','nhan_vien_bao_duong_khuon','nhan_vien_thong_ke','iqc','to_truong_khuon','chi_xem']));
update public.user_roles set role = 'chi_xem', bo_phan_phu_trach = null, chuc_danh = null, updated_at = now()
where email = 'dashboard01@mes.local';

-- ── R7: view + quyền anon thừa ──────────────────────────────────────────────
alter view if exists public.nvl_v_ton_hien_tai set (security_invoker = on);
alter view if exists public.cd_v_vi_tri_hien_tai set (security_invoker = on);
do $a$ begin
  if to_regprocedure('public.bom_set_updated_at()') is not null then
    revoke execute on function public.bom_set_updated_at() from anon;
  end if;
end $a$;
