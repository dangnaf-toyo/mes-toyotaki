-- T210e — User 04/11/2026: việc CẤP 1 do trưởng ca đúc chỉ thị thì không cần duyệt thêm, bất kể giờ:
--   trưởng ca khai cấp 1 → đã duyệt ngay; trưởng ca duyệt được cấp 1 của tổ khuôn mọi lúc.
--   Cấp 2 giữ: trưởng ca chỉ duyệt thay 22:00–08:00 (QLBP xác nhận sau). Cờ duyet_thay_ca_dem chỉ cho cấp 2.
create or replace function public.duc_khuon_ct_quyen_duyet(p_cap int) returns text
language sql stable security definer set search_path to 'public' as $$
  select case
    when u.role = 'admin' then 'Admin'
    when u.role = 'giam_doc_sx' then 'Giám đốc SX'
    when u.role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(u.bo_phan_phu_trach, '{}')) and p_cap <= 2 then 'QLBP Đúc'
    when u.role = 'to_truong_khuon' and p_cap <= 1 then 'Tổ trưởng khuôn'
    when u.role = 'truong_ca' and p_cap <= 1 then 'Trưởng ca chỉ thị (cấp 1)'
    when u.role = 'truong_ca' and p_cap <= 2 and duc_khuon_ct_la_ca_dem() then 'Trưởng ca (duyệt thay ca đêm)'
  end
  from user_roles u where u.user_id = auth.uid();
$$;
create or replace function public.duc_khuon_ct_tc_chi_thi(p_cap int) returns boolean
language sql stable security definer set search_path to 'public' as $$
  select p_cap <= 1 and exists (select 1 from user_roles u where u.user_id = auth.uid() and u.role = 'truong_ca');
$$;
create or replace function public.duc_khuon_ct_quyen_phieu(p_cap int, p_de_nghi_uid uuid) returns text
language sql stable security definer set search_path to 'public' as $$
  select case when p_de_nghi_uid = auth.uid() and not duc_khuon_ct_tu_duyet_duoc() and not duc_khuon_ct_tc_chi_thi(p_cap) then null
              else duc_khuon_ct_quyen_duyet(p_cap) end;
$$;
revoke execute on function public.duc_khuon_ct_tc_chi_thi(int), public.duc_khuon_ct_quyen_duyet(int), public.duc_khuon_ct_quyen_phieu(int, uuid) from public, anon, authenticated;
do $p$
declare d text; n text;
begin
  d := pg_get_functiondef('public.duc_khuon_ct_luu(text,text,text[],boolean,text)'::regprocedure);
  if position('duc_khuon_ct_tc_chi_thi' in d) = 0 then
    n := replace(d, 'if v_quyen is not null and not duc_khuon_ct_tu_duyet_duoc() then v_quyen := null; end if;',
                    'if v_quyen is not null and not duc_khuon_ct_tu_duyet_duoc() and not duc_khuon_ct_tc_chi_thi(v_cap) then v_quyen := null; end if;   -- T210e');
    n := replace(n, 'v_dem := v_tt = ''da_duyet'' and not v_giu_duyet and v_cap > 0 and v_quyen like ''Trưởng ca%'';',
                    'v_dem := v_tt = ''da_duyet'' and not v_giu_duyet and v_cap > 0 and v_quyen like ''Trưởng ca (duyệt thay%'';');
    execute n;
  end if;
  d := pg_get_functiondef('public.duc_khuon_ct_duyet(bigint,boolean,text,timestamptz)'::regprocedure);
  if position('duc_khuon_ct_tc_chi_thi' in d) = 0 then
    n := replace(d, 'if c.de_nghi_uid = auth.uid() and not duc_khuon_ct_tu_duyet_duoc() then',
                    'if c.de_nghi_uid = auth.uid() and not duc_khuon_ct_tu_duyet_duoc() and not duc_khuon_ct_tc_chi_thi(c.cap) then   -- T210e');
    n := replace(n, 'v_dem := p_dong_y and v_quyen like ''Trưởng ca%'';', 'v_dem := p_dong_y and v_quyen like ''Trưởng ca (duyệt thay%'';');
    n := replace(n, 'case c.cap when 1 then ''Tổ trưởng khuôn''', 'case c.cap when 1 then ''Tổ trưởng khuôn / trưởng ca''');
    execute n;
  end if;
end $p$;
