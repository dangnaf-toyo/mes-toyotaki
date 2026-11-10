-- ============================================================================
-- T239 (10/11/2026) — BOM Giai đoạn 2: dùng định mức BOM cho sản xuất
--   1) bom_phien_ban_tai(ma_sp, ngay): phiên bản BOM ĐÃ DUYỆT có hiệu lực vào ngày đó
--      (kể cả bản nay đã "Hết hiệu lực" nếu ngày nằm trong thời gian nó còn hiệu lực).
--   2) duc_lich_su_san_xuat.bom_version_id — trigger tự ghi khi kết ca (không bao giờ
--      chặn kết ca: lỗi tra cứu → để trống). Đổi BOM sau này không làm sai số liệu cũ.
--   3) bom_kim_loai_tieu_hao(tu, den): tiêu hao CHUẨN = sản lượng máy đúc × định mức
--      BOM hiệu lực, so với THỰC XUẤT kho NVL (nvl_giao_dich OUT) theo mác vật liệu.
--      Chỉ tính máy đúc (DC…, Kẽm…) — bỏ Cắt gate / Dập (cùng bộ phận Đúc nhưng không
--      tiêu hao kim loại, nếu cộng sẽ tính trùng).
--   4) bom_kim_loai_nhu_cau(tuan): nhu cầu kim loại từ KHSX tuần Đúc (duc_khsx_tuan_plan)
--      × định mức hiện hành, so với tồn kho NVL theo mác → số ngày đủ dùng.
-- Quyền: người xem BOM (bom_quyen_xem). Trạng thái: ĐÃ CHẠY STAGING + PROD 10/11/2026.
-- ============================================================================

create or replace function public.bom_la_may_duc(p_ma_may text) returns boolean
language sql immutable as $$
  select coalesce(p_ma_may ~* '^(DC|Kẽm)\s*\d', false);
$$;

create or replace function public.bom_phien_ban_tai(p_ma_sp text, p_ngay date) returns bigint
language sql stable security definer set search_path = public as $$
  select b.id from public.bom_versions b
  where b.ma_sp = p_ma_sp and b.trang_thai in ('da_duyet', 'het_hieu_luc') and b.duyet_luc is not null
    and b.ngay_hieu_luc <= p_ngay
  order by b.ngay_hieu_luc desc, b.version_no desc limit 1;
$$;
revoke all on function public.bom_phien_ban_tai(text, date) from public, anon;
grant execute on function public.bom_phien_ban_tai(text, date) to authenticated;

-- ── Ghi phiên bản BOM vào lịch sử sản xuất ───────────────────────────────
alter table public.duc_lich_su_san_xuat add column if not exists bom_version_id bigint;

create or replace function public.duc_lssx_gan_bom() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.ma_sp is distinct from old.ma_sp or new.ngay is distinct from old.ngay or new.bom_version_id is null then
    begin
      new.bom_version_id := public.bom_phien_ban_tai(new.ma_sp, new.ngay);
    exception when others then
      new.bom_version_id := null;   -- không bao giờ chặn kết ca vì BOM
    end;
  end if;
  return new;
end $$;
revoke all on function public.duc_lssx_gan_bom() from public, anon, authenticated;
drop trigger if exists trg_duc_lssx_gan_bom on public.duc_lich_su_san_xuat;
create trigger trg_duc_lssx_gan_bom before insert or update on public.duc_lich_su_san_xuat
for each row execute function public.duc_lssx_gan_bom();

-- Duyệt BOM có ngày hiệu lực lùi về quá khứ → gắn lại cho các ca chưa có BOM từ ngày đó.
create or replace function public.bom_gan_lai_lich_su() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.trang_thai = 'da_duyet' and old.trang_thai is distinct from 'da_duyet' and new.ngay_hieu_luc <= current_date then
    update public.duc_lich_su_san_xuat h set bom_version_id = public.bom_phien_ban_tai(h.ma_sp, h.ngay)
    where h.ma_sp = new.ma_sp and h.ngay >= new.ngay_hieu_luc;
  end if;
  return new;
end $$;
revoke all on function public.bom_gan_lai_lich_su() from public, anon, authenticated;
drop trigger if exists trg_bom_gan_lai_lich_su on public.bom_versions;
create trigger trg_bom_gan_lai_lich_su after update of trang_thai on public.bom_versions
for each row execute function public.bom_gan_lai_lich_su();

-- ── Tiêu hao chuẩn vs thực xuất ──────────────────────────────────────────
create or replace function public.bom_kim_loai_tieu_hao(p_tu date, p_den date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if not public.bom_quyen_xem() then raise exception 'Bạn chưa có quyền xem BOM'; end if;
  if p_tu is null or p_den is null or p_den < p_tu or p_den - p_tu > 186 then raise exception 'Chọn khoảng ngày hợp lệ (tối đa 6 tháng)'; end if;
  with sx as (
    select h.ngay, h.ma_sp, h.ma_may, h.tt_ca::numeric sl,
           coalesce(h.bom_version_id, public.bom_phien_ban_tai(h.ma_sp, h.ngay)) vid
    from public.duc_lich_su_san_xuat h
    where h.ngay between p_tu and p_den and public.bom_la_may_duc(h.ma_may) and coalesce(h.tt_ca, 0) > 0
  ), sx2 as (
    select sx.*, b.version_no, b.ma_mac, b.dinh_muc_nhom_kg_moi_pcs dm, b.hoi_lieu_kg_moi_pcs hl,
           p.ten_sp, coalesce(b.ma_mac, mp.ma_mac) mac
    from sx left join public.bom_versions b on b.id = sx.vid
    left join public.master_products p on p.ma_sp = sx.ma_sp
    left join lateral (select v.ma_mac from public.bom_versions v where v.ma_sp = sx.ma_sp and v.ma_mac is not null
                       order by v.version_no desc limit 1) mp on true
  ), xuat as (
    select n.ma_mac mac, g.ngay, sum(g.so_luong_kg) kg
    from public.nvl_giao_dich g join public.nvl_materials n on n.ma_nvl = g.ma_nvl
    where g.loai = 'OUT' and g.ngay between p_tu and p_den and n.nhom_vat_tu = 'kim_loai'
    group by 1, 2
  ), theo_mac as (
    select coalesce(m.mac, x.mac) mac, m.sl, m.sl_co_bom, m.chuan, m.hoi_lieu, x.thuc
    from (select mac, sum(sl) sl, sum(sl) filter (where dm is not null) sl_co_bom,
                 sum(sl * dm) chuan, sum(sl * hl) hoi_lieu from sx2 group by mac) m
    full join (select mac, sum(kg) thuc from xuat group by mac) x on coalesce(x.mac, '') = coalesce(m.mac, '')
  )
  select jsonb_build_object(
    'tu', p_tu, 'den', p_den,
    'tong', (select jsonb_build_object('sl', coalesce(sum(sl), 0), 'sl_co_bom', coalesce(sum(sl) filter (where dm is not null), 0),
              'chuan_kg', round(coalesce(sum(sl * dm), 0), 1), 'hoi_lieu_kg', round(coalesce(sum(sl * hl), 0), 1),
              'so_ma', count(distinct ma_sp), 'so_ma_co_bom', count(distinct ma_sp) filter (where dm is not null)) from sx2),
    'thuc_kg', (select round(coalesce(sum(kg), 0), 1) from xuat),
    'kho_gd_cuoi', (select max(ngay) from public.nvl_giao_dich),
    'theo_mac', coalesce((select jsonb_agg(jsonb_build_object('mac', mac, 'sl', coalesce(sl, 0), 'sl_co_bom', coalesce(sl_co_bom, 0),
              'chuan_kg', round(chuan, 1), 'hoi_lieu_kg', round(hoi_lieu, 1), 'thuc_kg', round(thuc, 1)) order by coalesce(chuan, 0) desc) from theo_mac), '[]'),
    'theo_sp', coalesce((select jsonb_agg(r order by (r->>'chuan_kg')::numeric desc nulls last, (r->>'sl')::numeric desc) from (
              select jsonb_build_object('ma_sp', ma_sp, 'ten_sp', max(ten_sp), 'mac', max(mac), 'sl', sum(sl),
                'sl_co_bom', coalesce(sum(sl) filter (where dm is not null), 0),
                'phien_ban', (select string_agg(distinct 'V' || version_no, ', ') from sx2 z where z.ma_sp = s.ma_sp and z.version_no is not null),
                'dm', max(dm), 'chuan_kg', round(sum(sl * dm), 1), 'may', string_agg(distinct ma_may, ', ')) r
              from sx2 s group by ma_sp) q), '[]'),
    'theo_ngay', coalesce((select jsonb_agg(jsonb_build_object('ngay', d.ngay, 'chuan_kg', round(d.chuan, 1), 'thuc_kg', round(coalesce(x.kg, 0), 1)) order by d.ngay)
              from (select ngay, sum(sl * dm) chuan from sx2 group by ngay) d
              left join (select ngay, sum(kg) kg from xuat group by ngay) x on x.ngay = d.ngay), '[]')
  ) into v;
  return v;
end $$;
revoke all on function public.bom_kim_loai_tieu_hao(date, date) from public, anon;
grant execute on function public.bom_kim_loai_tieu_hao(date, date) to authenticated;

-- ── Nhu cầu kim loại theo KHSX tuần Đúc ──────────────────────────────────
create or replace function public.bom_kim_loai_nhu_cau(p_tuan date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb; v_tuan date := date_trunc('week', coalesce(p_tuan, current_date))::date;
begin
  if not public.bom_quyen_xem() then raise exception 'Bạn chưa có quyền xem BOM'; end if;
  with kh as (
    select k.tuan_bat_dau tuan, k.ma_sp, k.ma_may,
           coalesce(nullif(coalesce(k.t2,0)+coalesce(k.t3,0)+coalesce(k.t4,0)+coalesce(k.t5,0)+coalesce(k.t6,0)+coalesce(k.t7,0)+coalesce(k.cn,0), 0), k.kh_tuan, 0) sl,
           -- phần kế hoạch còn lại của tuần hiện tại (từ hôm nay)
           case when k.tuan_bat_dau = date_trunc('week', current_date)::date then
             (case when current_date <= k.tuan_bat_dau     then coalesce(k.t2,0) else 0 end) +
             (case when current_date <= k.tuan_bat_dau + 1 then coalesce(k.t3,0) else 0 end) +
             (case when current_date <= k.tuan_bat_dau + 2 then coalesce(k.t4,0) else 0 end) +
             (case when current_date <= k.tuan_bat_dau + 3 then coalesce(k.t5,0) else 0 end) +
             (case when current_date <= k.tuan_bat_dau + 4 then coalesce(k.t6,0) else 0 end) +
             (case when current_date <= k.tuan_bat_dau + 5 then coalesce(k.t7,0) else 0 end) +
             (case when current_date <= k.tuan_bat_dau + 6 then coalesce(k.cn,0) else 0 end)
           end sl_con_lai
    from public.duc_khsx_tuan_plan k
    where k.tuan_bat_dau between v_tuan and v_tuan + 7 and public.bom_la_may_duc(k.ma_may)
  ), kh2 as (
    select kh.*, b.id vid, b.version_no, b.dinh_muc_nhom_kg_moi_pcs dm,
           coalesce(b.ma_mac, (select v.ma_mac from public.bom_versions v where v.ma_sp = kh.ma_sp and v.ma_mac is not null order by v.version_no desc limit 1)) mac
    from kh left join public.bom_versions b on b.ma_sp = kh.ma_sp and b.trang_thai = 'da_duyet'
  ), ton as (
    select n.ma_mac mac, sum(t.ton_hien_tai_kg) kg
    from public.nvl_v_ton_hien_tai t join public.nvl_materials n on n.ma_nvl = t.ma_nvl
    where n.nhom_vat_tu = 'kim_loai' group by 1
  )
  select jsonb_build_object(
    'tuan', v_tuan, 'tuan_sau', v_tuan + 7, 'hom_nay', current_date,
    'kho_gd_cuoi', (select max(ngay) from public.nvl_giao_dich),
    'theo_mac', coalesce((select jsonb_agg(jsonb_build_object('mac', m.mac,
        'kg_tuan', round(m.kg_tuan, 1), 'kg_con_lai', round(m.kg_con_lai, 1), 'kg_tuan_sau', round(m.kg_tuan_sau, 1),
        'sl_thieu_bom', m.sl_thieu_bom, 'ton_kg', round(t.kg, 1)) order by coalesce(m.kg_tuan, 0) + coalesce(m.kg_tuan_sau, 0) desc)
      from (select mac,
              sum(sl * dm) filter (where tuan = v_tuan) kg_tuan,
              sum(coalesce(sl_con_lai, 0) * dm) filter (where tuan = v_tuan) kg_con_lai,
              sum(sl * dm) filter (where tuan = v_tuan + 7) kg_tuan_sau,
              coalesce(sum(sl) filter (where dm is null), 0) sl_thieu_bom
            from kh2 group by mac) m
      left join ton t on t.mac is not distinct from m.mac), '[]'),
    'theo_sp', coalesce((select jsonb_agg(jsonb_build_object('ma_sp', ma_sp, 'mac', mac, 'phien_ban', case when version_no is not null then 'V' || version_no end,
        'dm', dm, 'sl_tuan', sl_tuan, 'sl_tuan_sau', sl_tuan_sau, 'kg_tuan', round(sl_tuan * dm, 1), 'kg_tuan_sau', round(sl_tuan_sau * dm, 1))
        order by coalesce(sl_tuan, 0) + coalesce(sl_tuan_sau, 0) desc)
      from (select ma_sp, max(mac) mac, max(version_no) version_no, max(dm) dm,
              coalesce(sum(sl) filter (where tuan = v_tuan), 0) sl_tuan, coalesce(sum(sl) filter (where tuan = v_tuan + 7), 0) sl_tuan_sau
            from kh2 group by ma_sp) s), '[]')
  ) into v;
  return v;
end $$;
revoke all on function public.bom_kim_loai_nhu_cau(date) from public, anon;
grant execute on function public.bom_kim_loai_nhu_cau(date) to authenticated;

notify pgrst, 'reload schema';
