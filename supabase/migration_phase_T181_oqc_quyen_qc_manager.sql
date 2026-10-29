-- T181 (29/10/2026, sửa theo review trước khi lên prod — chạy SAU T177):
-- QC Manager được sửa / xoá MỌI báo cáo OQC như Admin. Lý do: 876/967 báo cáo cũ trên prod (10/6→20/10/2026)
-- không ghi người nhập (created_by null) → theo T177 chỉ Admin sửa được, QC Manager mất quyền sửa sai sót cũ.
-- Người nhập (nhan_vien_oqc) vẫn chỉ sửa / xoá báo cáo của chính mình.

create or replace function public.oqc_quyen_bao_cao() returns jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('version',177,'user_id',auth.uid(),'is_admin',has_role('admin'),
 'quan_ly_tat_ca',has_role('admin','qc_manager'),
 'can_actual',auth.uid() is not null and has_role('admin','qc_manager','nhan_vien_oqc'))
 where auth.uid() is not null;
$$;
revoke all on function public.oqc_quyen_bao_cao() from public,anon;
grant execute on function public.oqc_quyen_bao_cao() to authenticated;

do $$
declare d text;
begin
  d := pg_get_functiondef('public.oqc_bao_ve_nguoi_nhap()'::regprocedure);
  if strpos(d, 'T181') = 0 then
    d := replace(d,
      $r$if not has_role('admin') and old.created_by is distinct from auth.uid() then raise exception 'Chỉ người nhập báo cáo hoặc Admin được sửa/xóa';end if;$r$,
      $r$if not has_role('admin','qc_manager') and old.created_by is distinct from auth.uid() then raise exception 'Chỉ người nhập báo cáo, QC Manager hoặc Admin được sửa/xóa';end if; -- T181$r$);
    if strpos(d, 'T181') = 0 then raise exception 'T181: không vá được oqc_bao_ve_nguoi_nhap'; end if;
    execute d;
  end if;

  d := pg_get_functiondef('public.oqc_xoa_bao_cao(bigint,timestamptz)'::regprocedure);
  if strpos(d, 'T181') = 0 then
    d := replace(d,
      $r$if not has_role('admin') and r.created_by is distinct from auth.uid() then raise exception 'Chỉ người nhập báo cáo hoặc Admin được sửa/xóa';end if;$r$,
      $r$if not has_role('admin','qc_manager') and r.created_by is distinct from auth.uid() then raise exception 'Chỉ người nhập báo cáo, QC Manager hoặc Admin được sửa/xóa';end if; -- T181$r$);
    if strpos(d, 'T181') = 0 then raise exception 'T181: không vá được oqc_xoa_bao_cao'; end if;
    execute d;
  end if;
end $$;
revoke execute on function public.oqc_bao_ve_nguoi_nhap() from public, anon, authenticated;
