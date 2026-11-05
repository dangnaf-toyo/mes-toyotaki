-- T211 — 04/11/2026: tài khoản 260201 (Hồ Văn Đảng — GĐSX + người phát triển chính MES) có TOÀN QUYỀN ADMIN mà vẫn giữ
-- vai trò Giám đốc SX. Hệ thống 1 role / tài khoản → lưu role = 'admin' + chuc_danh = 'giam_doc_sx' (giống T196 Tổng giám đốc).
--   - has_role() và cv_pd_ds_role() tính cả chuc_danh → mọi bước duyệt / chuông dành cho giam_doc_sx vẫn tới.
--   - 3 hàm so cứng role = 'giam_doc_sx' (duyệt KH bảo dưỡng khuôn tuần, KHSX tuần duyệt / từ chối) thêm has_role('giam_doc_sx').
--   - Phân cấp can thiệp khuôn: nhãn người duyệt hiện "Giám đốc SX" thay vì "Admin".
alter table public.user_roles drop constraint if exists user_roles_chuc_danh_check;
alter table public.user_roles add constraint user_roles_chuc_danh_check
  check (chuc_danh is null or (chuc_danh in ('tong_giam_doc', 'giam_doc_sx') and role = 'admin'));

create or replace function public.has_role(variadic allowed_roles text[]) returns boolean
language sql stable security definer set search_path to 'public' as $$
  -- T211: chức danh (admin kiêm GĐSX) cũng tính như vai trò
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and (role = any(allowed_roles) or chuc_danh = any(allowed_roles))
  );
$$;

create or replace function public.cv_pd_ds_role(p_roles text[], p_bo_phan text default null) returns uuid[]
language sql stable security definer set search_path to 'public' as $$
  select coalesce(array_agg(distinct u.user_id), '{}')
  from user_roles u
  where (u.role = any(coalesce(p_roles, '{}')) or u.chuc_danh = any(coalesce(p_roles, '{}')))   -- T211
    and (p_bo_phan is null or p_bo_phan = any(coalesce(u.bo_phan_phu_trach, '{}')));
$$;

do $p$
declare d text; n text;
begin
  d := pg_get_functiondef('duc_khuon_bd_xu_ly_duyet'::regproc);
  if position('T211' in d) = 0 then
    n := replace(d, 'if v_tt = ''cho_phe_duyet'' and coalesce(v_me.o_role, '''') <> ''giam_doc_sx'' then',
                    'if v_tt = ''cho_phe_duyet'' and coalesce(v_me.o_role, '''') <> ''giam_doc_sx'' and not public.has_role(''giam_doc_sx'') then   -- T211');
    if n = d then raise exception 'T211: không vá được duc_khuon_bd_xu_ly_duyet'; end if;
    execute n;
  end if;
  d := pg_get_functiondef('khsx_duyet'::regproc);
  if position('T211' in d) = 0 then
    n := replace(d, 'if coalesce(v_role,'''') <> ''giam_doc_sx'' then', 'if coalesce(v_role,'''') <> ''giam_doc_sx'' and not public.has_role(''giam_doc_sx'') then   -- T211');
    if n = d then raise exception 'T211: không vá được khsx_duyet'; end if;
    execute n;
  end if;
  d := pg_get_functiondef('khsx_tu_choi'::regproc);
  if position('T211' in d) = 0 then
    n := replace(d, 'if coalesce(v_role,'''') <> ''giam_doc_sx'' then', 'if coalesce(v_role,'''') <> ''giam_doc_sx'' and not public.has_role(''giam_doc_sx'') then   -- T211');
    if n = d then raise exception 'T211: không vá được khsx_tu_choi'; end if;
    execute n;
  end if;
end $p$;

create or replace function public.duc_khuon_ct_quyen_duyet(p_cap int) returns text
language sql stable security definer set search_path to 'public' as $$
  select case
    when u.chuc_danh = 'giam_doc_sx' then 'Giám đốc SX'   -- T211: admin kiêm GĐSX
    when u.role = 'admin' then 'Admin'
    when u.role = 'giam_doc_sx' then 'Giám đốc SX'
    when u.role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(u.bo_phan_phu_trach, '{}')) and p_cap <= 2 then 'QLBP Đúc'
    when u.role = 'to_truong_khuon' and p_cap <= 1 then 'Tổ trưởng khuôn'
    when u.role = 'truong_ca' and p_cap <= 1 then 'Trưởng ca chỉ thị (cấp 1)'
    when u.role = 'truong_ca' and p_cap <= 2 and duc_khuon_ct_la_ca_dem() then 'Trưởng ca (duyệt thay ca đêm)'
  end
  from user_roles u where u.user_id = auth.uid();
$$;
revoke execute on function public.duc_khuon_ct_quyen_duyet(int) from public, anon, authenticated;

-- Tài khoản 260201: admin kiêm GĐSX
update public.user_roles set role = 'admin', chuc_danh = 'giam_doc_sx', updated_at = now()
where email = '260201@mes.local';
