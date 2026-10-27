-- T173 (27/10/2026): thêm bộ phận 'Thiết bị' cho user_roles.bo_phan_phu_trach;
-- Quản lý bộ phận Thiết bị được kết thúc sự cố khi IPQC chưa OK (cùng quyền vượt T172 với admin / QC Manager).
alter table public.user_roles drop constraint user_roles_bo_phan_phu_trach_check;
alter table public.user_roles add constraint user_roles_bo_phan_phu_trach_check check (
  bo_phan_phu_trach is null
  or bo_phan_phu_trach <@ array['Đúc', 'Bavia', 'Gia Công', 'Cắt viền', 'Đánh bóng Kẽm', 'Sơn', 'OQC', 'Kỹ thuật', 'QA', 'Thiết bị']::text[]
);

do $$
declare d text; d0 text;
begin
  d := pg_get_functiondef('public.duc_resolve_incident'::regproc);
  d0 := d;
  d := replace(d, '                 and public.has_role(''admin'', ''qc_manager'');',
'                 and (public.has_role(''admin'', ''qc_manager'')
                      or exists (select 1 from public.user_roles ur      -- T173: QLBP Thiết bị
                                 where ur.user_id = auth.uid() and ur.role = ''quan_ly_bo_phan''
                                   and ''Thiết bị'' = any(coalesce(ur.bo_phan_phu_trach, ''{}''))));');
  if d = d0 then raise exception 'T173: không tìm thấy khối T172 trong duc_resolve_incident'; end if;
  execute d;
end $$;
