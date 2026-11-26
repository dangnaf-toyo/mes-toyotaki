-- T351: Vai trò mới "Kỹ thuật đúc" (role = 'ky_thuat_duc')
--   • Phiếu điều kiện đúc: được lập / sửa / gửi / lần mới / sửa Thực tế (như bộ phận Kỹ thuật); QLBP Đúc kiểm, GĐSX vẫn duyệt cuối.
--   • Điểm thay đổi (điều chỉnh điều kiện đúc): được ghi + "Đã chỉnh" như trưởng ca, và duyệt thay nhóm Kỹ thuật.
--   • Người Kỹ thuật đúc không tự duyệt điểm thay đổi do chính mình ghi.

-- 1) Cho phép giá trị role mới
alter table public.user_roles drop constraint user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check (role = any (array[
  'admin','truong_ca','ipqc','qc_manager','kho_nvl','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong',
  'quan_ly_bo_phan','giam_doc_sx','nhan_vien_duc','nhan_vien_bavia','nhan_vien_gia_cong','nhan_vien_danh_bong',
  'nhan_vien_oqc','nhan_vien_son','iatf_admin','nhan_vien_bao_duong_khuon','nhan_vien_thong_ke','iqc',
  'to_truong_khuon','chi_xem','ky_thuat_duc']::text[]));

-- 2) Lập phiếu điều kiện đúc
create or replace function public.duc_dk_la_ky_thuat()
returns boolean language sql stable security definer set search_path to 'public' as $$
  select has_role('admin', 'ky_thuat_duc') or auth.uid() = any(cv_pd_ds_bo_phan('Kỹ thuật'));
$$;

-- 3) Duyệt điểm thay đổi nhóm Kỹ thuật
create or replace function public.duc_td_ds_duyet(p_nhom text)
returns uuid[] language sql stable security definer set search_path to 'public' as $$
  select coalesce(array_agg(distinct u), '{}') from unnest(
    (case p_nhom
       when 'ky_thuat'        then cv_pd_ds_role(array['quan_ly_bo_phan'], 'Kỹ thuật') || cv_pd_ds_role(array['ky_thuat_duc'], null)
       when 'thiet_bi'        then cv_pd_ds_role(array['quan_ly_bo_phan'], 'Thiết bị')
       when 'to_truong_khuon' then cv_pd_ds_role(array['to_truong_khuon'], null)
       when 'qlbp_duc'        then cv_pd_ds_role(array['quan_ly_bo_phan'], 'Đúc')
       when 'qa'              then cv_pd_ds_role(array['qc_manager'], null)
       else '{}'::uuid[] end)
    || cv_pd_ds_role(array['giam_doc_sx'], null)) u;
$$;

-- 4) Ghi điểm thay đổi
create or replace function public.duc_td_quyen()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'ghi', public.has_role('truong_ca', 'admin', 'ky_thuat_duc'),
    'duyet', coalesce((select jsonb_agg(n) from unnest(array['ky_thuat', 'thiet_bi', 'to_truong_khuon', 'qlbp_duc', 'qa']) n
                       where auth.uid() = any(public.duc_td_ds_duyet(n))), '[]'),
    'huy_moi', public.has_role('admin') or auth.uid() = any(cv_pd_ds_role(array['quan_ly_bo_phan'], 'Đúc')));
$$;

-- 5) Sửa tại chỗ các hàm dài (giữ nguyên phần còn lại)
do $$
declare d text;
begin
  -- duc_td_ghi, duc_td_da_chinh: + ky_thuat_duc
  for d in select pg_get_functiondef(p.oid) from pg_proc p
           where p.pronamespace = 'public'::regnamespace and p.proname in ('duc_td_ghi', 'duc_td_da_chinh') loop
    if position('has_role(''truong_ca'', ''admin'')' in d) = 0 then raise exception 'T351: không thấy mốc truong_ca'; end if;
    execute replace(d, 'has_role(''truong_ca'', ''admin'')', 'has_role(''truong_ca'', ''admin'', ''ky_thuat_duc'')');
  end loop;

  -- duc_td_duyet: Kỹ thuật đúc không tự duyệt phiếu mình ghi
  d := pg_get_functiondef('public.duc_td_duyet(bigint,boolean,text)'::regprocedure);
  if position('if cardinality(v_cua_toi) = 0 then' in d) = 0 then raise exception 'T351: không thấy mốc duc_td_duyet'; end if;
  execute replace(d, 'if cardinality(v_cua_toi) = 0 then',
    'if auth.uid() = v.nguoi_ghi_id and public.has_role(''ky_thuat_duc'') and not public.has_role(''admin'') then' || E'\n' ||
    '    raise exception ''⛔ Người ghi không tự duyệt phiếu của mình.'' using errcode = ''42501'';' || E'\n' ||
    '  end if;' || E'\n  ' ||
    'if cardinality(v_cua_toi) = 0 then');

  -- duc_dk_danh_dau_cap_nhat: chuông "cập nhật phiếu" gửi cả Kỹ thuật đúc
  for d in select pg_get_functiondef(p.oid) from pg_proc p
           where p.pronamespace = 'public'::regnamespace and p.proname = 'duc_dk_danh_dau_cap_nhat' loop
    if position('cv_pd_ds_bo_phan(''Kỹ thuật'') || array[p.nguoi_lap]' in d) = 0 then raise exception 'T351: không thấy mốc danh_dau'; end if;
    execute replace(d, 'cv_pd_ds_bo_phan(''Kỹ thuật'') || array[p.nguoi_lap]',
                       'cv_pd_ds_bo_phan(''Kỹ thuật'') || cv_pd_ds_role(array[''ky_thuat_duc''], null) || array[p.nguoi_lap]');
  end loop;
end $$;
