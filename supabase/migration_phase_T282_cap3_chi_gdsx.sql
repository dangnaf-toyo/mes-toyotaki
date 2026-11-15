-- T282 (R24) — 15/11/2026: Can thiệp khuôn cấp 3 chỉ Giám đốc SX duyệt.
-- Trước: mọi Admin duyệt được cấp 3. Nay Admin (không mang chức danh GĐSX) chỉ duyệt cấp 1–2.
-- Giữ nguyên 8 tài khoản Admin. Chuông cấp 3 vốn chỉ gửi GĐSX (duc_khuon_ct_nguoi_duyet_ds) — không đổi.
create or replace function public.duc_khuon_ct_quyen_duyet(p_cap int) returns text
language sql stable security definer set search_path to 'public' as $$
  select case
    when u.chuc_danh = 'giam_doc_sx' then 'Giám đốc SX'   -- T211: admin kiêm GĐSX
    when u.role = 'giam_doc_sx' then 'Giám đốc SX'
    when u.role = 'admin' and p_cap <= 2 then 'Admin'      -- T282: cấp 3 chỉ GĐSX
    when u.role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(u.bo_phan_phu_trach, '{}')) and p_cap <= 2 then 'QLBP Đúc'
    when u.role = 'to_truong_khuon' and p_cap <= 1 then 'Tổ trưởng khuôn'
    when u.role = 'truong_ca' and p_cap <= 1 then 'Trưởng ca chỉ thị (cấp 1)'
    when u.role = 'truong_ca' and p_cap <= 2 and duc_khuon_ct_la_ca_dem() then 'Trưởng ca (duyệt thay ca đêm)'
  end
  from user_roles u where u.user_id = auth.uid();
$$;
revoke execute on function public.duc_khuon_ct_quyen_duyet(int) from public, anon, authenticated;
