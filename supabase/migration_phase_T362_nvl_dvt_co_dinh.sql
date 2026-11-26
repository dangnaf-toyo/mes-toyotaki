-- T362: ĐVT cố định theo danh mục NVL (nvl_materials.dvt) — người dùng không sửa được.
-- Áp khi ghi mới tem NVL và dòng phiếu cấp; không sửa dữ liệu cũ.
create or replace function public.nvl_ep_dvt_theo_danh_muc()
returns trigger language plpgsql set search_path = public as $$
declare v text;
begin
  select dvt into v from nvl_materials where ma_nvl = new.ma_nvl;
  if v is not null then
    if tg_table_name = 'nvl_tem' then new.don_vi := v; else new.dvt := v; end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_nvl_tem_dvt on public.nvl_tem;
create trigger trg_nvl_tem_dvt before insert on public.nvl_tem
  for each row execute function public.nvl_ep_dvt_theo_danh_muc();

drop trigger if exists trg_nvl_pcd_dvt on public.nvl_phieu_cap_dong;
create trigger trg_nvl_pcd_dvt before insert or update of ma_nvl, dvt on public.nvl_phieu_cap_dong
  for each row execute function public.nvl_ep_dvt_theo_danh_muc();

revoke execute on function public.nvl_ep_dvt_theo_danh_muc() from public, anon, authenticated;
