-- ============================================================================
-- T334: Nguyên liệu của sản phẩm (master_products.nguyen_lieu) tự lấy theo BOM.
--   - Mã SP có BOM hiệu lực (bom_phien_ban_tai hôm nay, giờ VN) và BOM có NVL
--     kim loại (ma_nhom) → nguyen_lieu = ma_nhom. Tem / QR vẫn đọc nguyen_lieu
--     nên các màn in tem không phải sửa.
--   - Đồng bộ khi: thêm/sửa/duyệt BOM (trigger), sửa tay sản phẩm (trigger giữ
--     theo BOM), và 00:05 giờ VN hằng ngày (BOM có ngày hiệu lực tương lai).
--   - Mã SP chưa có BOM hiệu lực: giữ ô gõ tay như cũ.
-- ============================================================================

create or replace function public.bom_nguyen_lieu_hien_hanh(p_ma_sp text) returns text
language sql stable security definer set search_path = public as $$
  select nullif(btrim(b.ma_nhom), '') from public.bom_versions b
  where b.id = public.bom_phien_ban_tai(p_ma_sp, (now() at time zone 'Asia/Ho_Chi_Minh')::date);
$$;
revoke all on function public.bom_nguyen_lieu_hien_hanh(text) from public, anon, authenticated;

-- Đồng bộ (p_ma_sp null = tất cả). Trả số mã đã đổi.
create or replace function public.bom_dong_bo_nguyen_lieu(p_ma_sp text default null) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  update public.master_products p set nguyen_lieu = x.nl
  from (select m.ma_sp, public.bom_nguyen_lieu_hien_hanh(m.ma_sp) nl
        from public.master_products m where p_ma_sp is null or m.ma_sp = p_ma_sp) x
  where p.ma_sp = x.ma_sp and x.nl is not null and p.nguyen_lieu is distinct from x.nl;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.bom_dong_bo_nguyen_lieu(text) from public, anon, authenticated;

-- BOM đổi → đồng bộ mã SP đó.
create or replace function public.bom_versions_dong_bo_nl() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    perform public.bom_dong_bo_nguyen_lieu(new.ma_sp);
  exception when others then null;   -- không bao giờ chặn thao tác BOM
  end;
  return null;
end $$;
revoke all on function public.bom_versions_dong_bo_nl() from public, anon, authenticated;
drop trigger if exists trg_bom_versions_dong_bo_nl on public.bom_versions;
create trigger trg_bom_versions_dong_bo_nl
after insert or update of ma_nhom, trang_thai, ngay_hieu_luc, duyet_luc on public.bom_versions
for each row execute function public.bom_versions_dong_bo_nl();

-- Sửa tay sản phẩm → nếu có BOM hiệu lực thì giữ theo BOM.
create or replace function public.master_products_nl_theo_bom() returns trigger
language plpgsql security definer set search_path = public as $$
declare v text;
begin
  if new.nguyen_lieu is distinct from old.nguyen_lieu then
    v := public.bom_nguyen_lieu_hien_hanh(new.ma_sp);
    if v is not null then new.nguyen_lieu := v; end if;
  end if;
  return new;
end $$;
revoke all on function public.master_products_nl_theo_bom() from public, anon, authenticated;
drop trigger if exists trg_master_products_nl_theo_bom on public.master_products;
create trigger trg_master_products_nl_theo_bom before update of nguyen_lieu on public.master_products
for each row execute function public.master_products_nl_theo_bom();

-- Cho tab Sản phẩm biết mã nào đang khoá theo BOM.
create or replace function public.sp_nguyen_lieu_theo_bom() returns setof text
language sql stable security definer set search_path = public as $$
  select m.ma_sp from public.master_products m where public.bom_nguyen_lieu_hien_hanh(m.ma_sp) is not null;
$$;
revoke all on function public.sp_nguyen_lieu_theo_bom() from public, anon;
grant execute on function public.sp_nguyen_lieu_theo_bom() to authenticated;

-- Hằng ngày 00:05 giờ VN (17:05 UTC).
select cron.unschedule('bom_dong_bo_nguyen_lieu') where exists (select 1 from cron.job where jobname = 'bom_dong_bo_nguyen_lieu');
select cron.schedule('bom_dong_bo_nguyen_lieu', '5 17 * * *', 'select public.bom_dong_bo_nguyen_lieu();');

-- Đồng bộ lần đầu.
select public.bom_dong_bo_nguyen_lieu();
