-- T286 (R29): bỏ so cứng role 'giam_doc_sx' / đọc thẳng user_roles.role → has_role() (tính cả chuc_danh).
-- Không đổi hành vi với dữ liệu hiện tại (GĐSX = admin có chuc_danh giam_doc_sx); chỉ để sau này
-- người có chuc_danh (không phải admin) cũng được nhận đúng quyền.
-- Cách làm: thay đúng đoạn trong định nghĩa hàm hiện có; đoạn nào không thấy → dừng cả khối.
do $$
declare
  r record; v_def text; v_oid regprocedure;
begin
  for r in select * from (values
    ('cv_la_bgd()',
     $a$select exists (select 1 from user_roles where user_id = auth.uid() and role in ('admin', 'giam_doc_sx'));$a$,
     $b$select public.has_role('admin', 'giam_doc_sx');$b$),
    ('cv_viet_binh_luan(bigint,bigint,text,text,uuid[])',
     $a$r.role in ('admin', 'giam_doc_sx')))$a$,
     $b$(r.role in ('admin', 'giam_doc_sx') or r.chuc_danh = 'giam_doc_sx')))$b$),
    ('duc_khuon_ct_cho_duyet()',
     $a$(u.role in ('admin', 'giam_doc_sx')$a$,
     $b$(u.role in ('admin', 'giam_doc_sx') or u.chuc_danh = 'giam_doc_sx'$b$),
    ('duc_khuon_ct_qlbp_xac_nhan(bigint,text)',
     $a$(u.role in ('admin', 'giam_doc_sx')$a$,
     $b$(u.role in ('admin', 'giam_doc_sx') or u.chuc_danh = 'giam_doc_sx'$b$),
    ('duc_khuon_ct_khong_tac_dong(text,text)',
     $a$(u.role in ('truong_ca', 'admin', 'giam_doc_sx')$a$,
     $b$(u.role in ('truong_ca', 'admin', 'giam_doc_sx') or u.chuc_danh = 'giam_doc_sx'$b$),
    ('duc_khuon_ct_lay(text,text)',
     $a$(u.role in ('truong_ca', 'admin', 'giam_doc_sx')$a$,
     $b$(u.role in ('truong_ca', 'admin', 'giam_doc_sx') or u.chuc_danh = 'giam_doc_sx'$b$),
    ('duc_khuon_ct_duoc_khai(text)',
     $a$or u.role = 'giam_doc_sx'$a$,
     $b$or u.role = 'giam_doc_sx' or u.chuc_danh = 'giam_doc_sx'$b$),
    ('forecast_luu(integer,jsonb,text)',
     $a$if coalesce(v_role, '') not in ('admin', 'ke_hoach', 'qlsx_truong_phong', 'giam_doc_sx') then$a$,
     $b$if not public.has_role('admin', 'ke_hoach', 'qlsx_truong_phong', 'giam_doc_sx') then$b$),
    ('khsx_gui_duyet(date,text,text)',
     $a$if v_role is null or v_role not in ('qlsx_nhan_vien','qlsx_truong_phong','admin') then$a$,
     $b$if not public.has_role('qlsx_nhan_vien','qlsx_truong_phong','admin') then$b$),
    ('khsx_duyet(date,text,text,text)',
     $a$if coalesce(v_role,'') <> 'qlsx_truong_phong' then$a$,
     $b$if not public.has_role('qlsx_truong_phong') then$b$),
    ('khsx_duyet(date,text,text,text)',
     $a$if not (coalesce(v_role,'') = 'quan_ly_bo_phan' and$a$,
     $b$if not (public.has_role('quan_ly_bo_phan') and$b$),
    ('khsx_duyet(date,text,text,text)',
     $a$if coalesce(v_role,'') <> 'giam_doc_sx' and not public.has_role('giam_doc_sx') then$a$,
     $b$if not public.has_role('giam_doc_sx') then$b$),
    ('khsx_tu_choi(date,text,text,text)',
     $a$if coalesce(v_role,'') <> 'qlsx_truong_phong' then$a$,
     $b$if not public.has_role('qlsx_truong_phong') then$b$),
    ('khsx_tu_choi(date,text,text,text)',
     $a$if not (coalesce(v_role,'') = 'quan_ly_bo_phan' and$a$,
     $b$if not (public.has_role('quan_ly_bo_phan') and$b$),
    ('khsx_tu_choi(date,text,text,text)',
     $a$if coalesce(v_role,'') <> 'giam_doc_sx' and not public.has_role('giam_doc_sx') then$a$,
     $b$if not public.has_role('giam_doc_sx') then$b$),
    ('duc_khuon_cs_luu(bigint,jsonb,boolean)',
     $a$and coalesce(v_me.o_role, '') <> 'giam_doc_sx' then$a$,
     $b$and not public.has_role('giam_doc_sx') then$b$),
    ('duc_khuon_xlbt_luu(text,text,text,text,timestamptz,timestamptz,text)',
     $a$and coalesce(v_me.o_role, '') <> 'giam_doc_sx' then$a$,
     $b$and not public.has_role('giam_doc_sx') then$b$),
    ('duc_khuon_bd_xu_ly_duyet(date,boolean,text)',
     $a$v_gd := coalesce(v_me.o_role, '') = 'giam_doc_sx' or public.has_role('giam_doc_sx');$a$,
     $b$v_gd := public.has_role('giam_doc_sx');$b$)
  ) t(fn, cu, moi)
  loop
    v_oid := ('public.' || r.fn)::regprocedure;
    v_def := pg_get_functiondef(v_oid);
    if position(r.cu in v_def) = 0 then
      raise exception 'T286: không thấy đoạn cần thay trong % : %', r.fn, r.cu;
    end if;
    execute replace(v_def, r.cu, r.moi);
  end loop;
end $$;
