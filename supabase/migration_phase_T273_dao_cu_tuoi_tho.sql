-- T273: Kho dao cụ Gia công — Đợt 2: bộ dao chuẩn + dao trên máy + tự đếm số chi tiết + thay dao.
-- User chốt 15/11/2026:
--   * Bộ dao chuẩn khai theo MÃ SP + BƯỚC gia công (master_cnc_routing; mã chưa khai = bước 1):
--     vị trí T01, T02… → mã dao, số lượng lắp, tuổi thọ chuẩn (chi tiết, hoặc lỗ ren nếu dao tính theo lỗ ren),
--     số lỗ ren / chi tiết (dao taro…).
--   * Số chi tiết dao đã chạy = số đầu (khai lúc lắp) + tổng SL ra các thùng bấm Xong trên máy
--     kể từ lúc lắp đến lúc tháo. Tính trực tiếp từ gc_tem_buoc nên "Huỷ xong" tự trừ lại.
--   * Thay dao: lý do + xử lý dao cũ hỏi mỗi lần (Chờ mài → NG · Bỏ → ra khỏi tồn · Trả tủ → Mới);
--     dao mới lấy từ tủ thì tự trừ tồn Mới (phiếu xuất). Lắp dao đã có sẵn trên máy (khai lần đầu)
--     không đổi tồn.
--   * Quyền: thay / lắp / tháo = trưởng ca trở lên (như phiếu xuất Đợt 1); khai bộ dao chuẩn = quản lý.
-- An toàn chạy lại. Chạy theo 3 phần (a: bảng + view, b: gc_dao_cu_ghi thêm loại 'bo', c: RPC mới).
-- Trạng thái: Đã chạy STAGING + PROD 15/11/2026.

-- ===== Phần a =====
alter table public.gc_dao_cu_giao_dich drop constraint if exists gc_dao_cu_giao_dich_loai_check;
alter table public.gc_dao_cu_giao_dich add constraint gc_dao_cu_giao_dich_loai_check
  check (loai in ('nhap','xuat','tra','ng','mai','huy_ng','kiem_ke','ton_dau','bo'));

create table if not exists public.gc_bo_dao (
  id bigserial primary key,
  ma_sp text not null,
  buoc integer not null default 1 check (buoc >= 1),
  vi_tri text not null,
  id_dao bigint not null references public.gc_dao_cu(id),
  so_luong numeric not null default 1 check (so_luong > 0),
  tuoi_tho_chuan integer check (tuoi_tho_chuan is null or tuoi_tho_chuan > 0),
  so_lan_ct numeric not null default 1 check (so_lan_ct > 0),
  ghi_chu text not null default '',
  updated_at timestamptz not null default now(),
  updated_by text not null default '',
  unique (ma_sp, buoc, vi_tri)
);

create table if not exists public.gc_dao_tren_may (
  id bigserial primary key,
  ma_may text not null,
  vi_tri text not null,
  id_dao bigint not null references public.gc_dao_cu(id),
  ma_dao text not null,
  so_luong numeric not null default 1 check (so_luong > 0),
  ma_sp text not null default '',
  buoc integer not null default 1,
  nguon text not null default 'tu' check (nguon in ('tu','may')),
  so_ct_dau numeric not null default 0 check (so_ct_dau >= 0),
  lap_luc timestamptz not null default now(),
  lap_boi text not null default '',
  thao_luc timestamptz,
  thao_boi text,
  ly_do_thao text,
  xu_ly_cu text check (xu_ly_cu is null or xu_ly_cu in ('mai','bo','tra')),
  so_ct_thuc_te numeric,
  tuoi_tho_luc_thao integer,
  ghi_chu text not null default ''
);
create unique index if not exists ux_gc_dao_tren_may_dang_lap on public.gc_dao_tren_may (ma_may, vi_tri) where thao_luc is null;
create index if not exists idx_gc_dao_tren_may_thao on public.gc_dao_tren_may (thao_luc desc) where thao_luc is not null;
create index if not exists idx_gc_tem_buoc_may_xong on public.gc_tem_buoc (ma_may, xong_luc) where xong_luc is not null and bo_luc is null;

alter table public.gc_bo_dao enable row level security;
alter table public.gc_dao_tren_may enable row level security;
drop policy if exists "auth read" on public.gc_bo_dao;
create policy "auth read" on public.gc_bo_dao for select to authenticated using (true);
drop policy if exists "auth read" on public.gc_dao_tren_may;
create policy "auth read" on public.gc_dao_tren_may for select to authenticated using (true);
revoke all on public.gc_bo_dao, public.gc_dao_tren_may from anon;
revoke insert, update, delete on public.gc_bo_dao, public.gc_dao_tren_may from authenticated;
grant select on public.gc_bo_dao, public.gc_dao_tren_may to authenticated;

-- Số chi tiết đã chạy của 1 lần lắp (số đầu + SL ra các thùng Xong trên máy trong khoảng lắp–tháo)
create or replace function public.gc_dao_so_ct(p_ma_may text, p_tu timestamptz, p_den timestamptz)
returns numeric language sql stable security definer set search_path to 'public' as $$
  select coalesce(sum(coalesce(b.sl_ra, 0)), 0) from gc_tem_buoc b
  where b.ma_may = p_ma_may and b.xong_luc is not null and b.bo_luc is null
    and b.xong_luc >= p_tu and (p_den is null or b.xong_luc < p_den);
$$;
revoke execute on function public.gc_dao_so_ct(text, timestamptz, timestamptz) from public, anon;
grant execute on function public.gc_dao_so_ct(text, timestamptz, timestamptz) to authenticated;

-- Tuổi thọ chuẩn + số lỗ ren/chi tiết áp cho 1 lần lắp: bộ chuẩn (đúng SP, bước, vị trí, mã) → danh mục dao
create or replace view public.gc_dao_tren_may_v with (security_invoker = true) as
select t.*, d.ten_chuan, d.tuoi_tho_theo, d.ton_moi,
  coalesce(bo.tuoi_tho_chuan, d.tuoi_tho_chuan) as tuoi_tho,
  coalesce(bo.so_lan_ct, 1) as so_lan_ct,
  t.so_ct_dau + gc_dao_so_ct(t.ma_may, t.lap_luc, t.thao_luc) as so_ct
from gc_dao_tren_may t
join gc_dao_cu d on d.id = t.id_dao
left join gc_bo_dao bo on bo.ma_sp = t.ma_sp and bo.buoc = t.buoc and bo.vi_tri = t.vi_tri and bo.id_dao = t.id_dao;
revoke all on public.gc_dao_tren_may_v from anon;
grant select on public.gc_dao_tren_may_v to authenticated;

-- ===== Phần b: gc_dao_cu_ghi thêm loại 'bo' (Đang dùng → bỏ, ví dụ dao gãy) =====
create or replace function public.gc_dao_cu_ghi(p_loai text, p_id_dao bigint, p_so_luong numeric,
  p_may text default null, p_ly_do text default null, p_ghi_chu text default null,
  p_moi numeric default null, p_dang_dung numeric default null, p_ng numeric default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me record; v_d gc_dao_cu%rowtype; v_sl numeric := coalesce(p_so_luong, 0);
  a numeric := 0; b numeric := 0; c numeric := 0; v_id bigint; v_ld text := trim(coalesce(p_ly_do, ''));
begin
  if p_loai not in ('nhap','xuat','tra','ng','mai','huy_ng','kiem_ke','bo') then
    return jsonb_build_object('ok', false, 'error', 'Loại phiếu không hợp lệ');
  end if;
  select * into v_me from gc_dao_cu_nguoi(case when p_loai in ('xuat','tra','ng','bo') then 'dung' else 'quan_ly' end);
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  select * into v_d from gc_dao_cu where id = p_id_dao for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy mã dao'); end if;
  if p_loai <> 'kiem_ke' and v_sl <= 0 then return jsonb_build_object('ok', false, 'error', 'Số lượng phải > 0'); end if;
  if p_loai in ('ng','huy_ng','kiem_ke','bo') and v_ld = '' then
    return jsonb_build_object('ok', false, 'error', case p_loai when 'ng' then 'Chọn lý do NG' when 'huy_ng' then 'Chọn nơi chuyển NG' when 'bo' then 'Chọn lý do bỏ' else 'Nhập lý do kiểm kê' end);
  end if;
  if p_loai = 'nhap' then a := v_sl;
  elsif p_loai = 'xuat' then a := -v_sl; b := v_sl;
  elsif p_loai = 'tra' then a := v_sl; b := -v_sl;
  elsif p_loai = 'ng' then b := -v_sl; c := v_sl;
  elsif p_loai = 'bo' then b := -v_sl;
  elsif p_loai = 'mai' then c := -v_sl; a := v_sl;
  elsif p_loai = 'huy_ng' then c := -v_sl;
  else
    if p_moi is null or p_dang_dung is null or p_ng is null or p_moi < 0 or p_dang_dung < 0 or p_ng < 0 then
      return jsonb_build_object('ok', false, 'error', 'Nhập đủ số thực tế Mới / Đang dùng / NG (≥ 0)');
    end if;
    a := p_moi - v_d.ton_moi; b := p_dang_dung - v_d.ton_dang_dung; c := p_ng - v_d.ton_ng;
    v_sl := abs(a) + abs(b) + abs(c);
  end if;
  if v_d.ton_moi + a < 0 then return jsonb_build_object('ok', false, 'error', 'Không đủ tồn Mới ' || v_d.ma_dao || ' (còn ' || v_d.ton_moi || ')'); end if;
  if v_d.ton_dang_dung + b < 0 then return jsonb_build_object('ok', false, 'error', 'Không đủ Đang dùng ' || v_d.ma_dao || ' (còn ' || v_d.ton_dang_dung || ')'); end if;
  if v_d.ton_ng + c < 0 then return jsonb_build_object('ok', false, 'error', 'Không đủ NG ' || v_d.ma_dao || ' (còn ' || v_d.ton_ng || ')'); end if;
  update gc_dao_cu set ton_moi = ton_moi + a, ton_dang_dung = ton_dang_dung + b, ton_ng = ton_ng + c, updated_at = now() where id = p_id_dao;
  insert into gc_dao_cu_giao_dich (loai, id_dao, ma_dao, so_luong, d_moi, d_dang_dung, d_ng, ton_moi_sau, ton_dang_dung_sau, ton_ng_sau,
    may, ly_do, ghi_chu, nguoi, nguoi_uid, vai_tro)
  values (p_loai, p_id_dao, v_d.ma_dao, v_sl, a, b, c, v_d.ton_moi + a, v_d.ton_dang_dung + b, v_d.ton_ng + c,
    trim(coalesce(p_may, '')), v_ld, trim(coalesce(p_ghi_chu, '')), v_me.o_ten, auth.uid(), v_me.o_role)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'ton_moi', v_d.ton_moi + a, 'ton_dang_dung', v_d.ton_dang_dung + b, 'ton_ng', v_d.ton_ng + c);
end $$;
revoke execute on function public.gc_dao_cu_ghi(text, bigint, numeric, text, text, text, numeric, numeric, numeric) from public, anon;
grant execute on function public.gc_dao_cu_ghi(text, bigint, numeric, text, text, text, numeric, numeric, numeric) to authenticated;

-- ===== Phần c: RPC bộ dao chuẩn + lắp / thay =====
-- Lưu cả bộ dao chuẩn của 1 mã SP + bước (thay toàn bộ). p_ds = [{vi_tri, id_dao, so_luong, tuoi_tho_chuan, so_lan_ct, ghi_chu}]
create or replace function public.gc_bo_dao_luu(p_ma_sp text, p_buoc integer, p_ds jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me record; v_sp text := trim(coalesce(p_ma_sp, '')); r jsonb; v_vt text; v_n int := 0; v_seen text[] := '{}';
begin
  select * into v_me from gc_dao_cu_nguoi('quan_ly');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if not exists (select 1 from master_products where ma_sp = v_sp) then
    return jsonb_build_object('ok', false, 'error', 'Mã SP ' || v_sp || ' không có trong Danh mục SP');
  end if;
  if coalesce(p_buoc, 0) < 1 then return jsonb_build_object('ok', false, 'error', 'Bước không hợp lệ'); end if;
  if jsonb_typeof(coalesce(p_ds, '[]'::jsonb)) <> 'array' then return jsonb_build_object('ok', false, 'error', 'Dữ liệu không hợp lệ'); end if;
  for r in select * from jsonb_array_elements(coalesce(p_ds, '[]'::jsonb)) loop
    v_vt := upper(trim(coalesce(r->>'vi_tri', '')));
    if v_vt = '' then return jsonb_build_object('ok', false, 'error', 'Có dòng chưa nhập vị trí'); end if;
    if v_vt = any(v_seen) then return jsonb_build_object('ok', false, 'error', 'Vị trí ' || v_vt || ' bị trùng'); end if;
    v_seen := v_seen || v_vt;
    if not exists (select 1 from gc_dao_cu where id = nullif(r->>'id_dao', '')::bigint) then
      return jsonb_build_object('ok', false, 'error', 'Vị trí ' || v_vt || ': chưa chọn mã dao đúng danh mục');
    end if;
  end loop;
  delete from gc_bo_dao where ma_sp = v_sp and buoc = p_buoc;
  insert into gc_bo_dao (ma_sp, buoc, vi_tri, id_dao, so_luong, tuoi_tho_chuan, so_lan_ct, ghi_chu, updated_by)
  select v_sp, p_buoc, upper(trim(x->>'vi_tri')), (x->>'id_dao')::bigint,
    coalesce(nullif(x->>'so_luong', '')::numeric, 1), nullif(x->>'tuoi_tho_chuan', '')::int,
    coalesce(nullif(x->>'so_lan_ct', '')::numeric, 1), trim(coalesce(x->>'ghi_chu', '')), v_me.o_ten
  from jsonb_array_elements(coalesce(p_ds, '[]'::jsonb)) x;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'so_dong', v_n);
exception when check_violation then
  return jsonb_build_object('ok', false, 'error', 'Số lượng / tuổi thọ / số lỗ ren phải > 0');
end $$;

-- Nội bộ: lắp 1 dao vào vị trí trống
create or replace function public.gc_dao_lap_mot(p_ma_may text, p_vi_tri text, p_id_dao bigint, p_so_luong numeric,
  p_nguon text, p_so_ct_dau numeric, p_ma_sp text, p_buoc integer, p_ghi_chu text, p_nguoi text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_d gc_dao_cu%rowtype; v_vt text := upper(trim(coalesce(p_vi_tri, ''))); v_sl numeric := coalesce(p_so_luong, 1);
  v_kq jsonb; v_id bigint;
begin
  if v_vt = '' then return jsonb_build_object('ok', false, 'error', 'Nhập vị trí (VD T01)'); end if;
  select * into v_d from gc_dao_cu where id = p_id_dao;
  if not found then return jsonb_build_object('ok', false, 'error', 'Chưa chọn mã dao đúng danh mục'); end if;
  if v_sl <= 0 then return jsonb_build_object('ok', false, 'error', 'Số lượng phải > 0'); end if;
  if coalesce(p_so_ct_dau, 0) < 0 then return jsonb_build_object('ok', false, 'error', 'Số chi tiết đã chạy phải ≥ 0'); end if;
  if exists (select 1 from gc_dao_tren_may where ma_may = p_ma_may and vi_tri = v_vt and thao_luc is null) then
    return jsonb_build_object('ok', false, 'error', p_ma_may || ' vị trí ' || v_vt || ' đang có dao — bấm Thay');
  end if;
  if coalesce(p_nguon, 'tu') = 'tu' then
    v_kq := gc_dao_cu_ghi('xuat', p_id_dao, v_sl, p_ma_may, 'Thay dao', v_vt);
    if not (v_kq->>'ok')::boolean then return v_kq; end if;
  end if;
  insert into gc_dao_tren_may (ma_may, vi_tri, id_dao, ma_dao, so_luong, ma_sp, buoc, nguon, so_ct_dau, lap_boi, ghi_chu)
  values (p_ma_may, v_vt, p_id_dao, v_d.ma_dao, v_sl, trim(coalesce(p_ma_sp, '')), coalesce(p_buoc, 1),
    case when p_nguon = 'may' then 'may' else 'tu' end,
    case when p_nguon = 'may' then coalesce(p_so_ct_dau, 0) else 0 end, coalesce(p_nguoi, ''), trim(coalesce(p_ghi_chu, '')))
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke execute on function public.gc_dao_lap_mot(text, text, bigint, numeric, text, numeric, text, integer, text, text) from public, anon, authenticated;

-- Lắp 1 dao (vị trí trống). p_nguon: 'tu' (lấy từ tủ, trừ Mới) / 'may' (đã có sẵn trên máy, không đổi tồn)
create or replace function public.gc_dao_lap(p_ma_may text, p_vi_tri text, p_id_dao bigint, p_so_luong numeric,
  p_nguon text, p_so_ct_dau numeric, p_ma_sp text, p_buoc integer, p_ghi_chu text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me record; v_kq jsonb;
begin
  select * into v_me from gc_dao_cu_nguoi('dung');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if not exists (select 1 from master_machines where ma_may = p_ma_may and bo_phan = 'Gia công - Sơn') then
    return jsonb_build_object('ok', false, 'error', coalesce(p_ma_may, '?') || ' không có trong danh mục máy Gia công');
  end if;
  v_kq := gc_dao_lap_mot(p_ma_may, p_vi_tri, p_id_dao, p_so_luong, p_nguon, p_so_ct_dau, p_ma_sp, p_buoc, p_ghi_chu, v_me.o_ten);
  if not (v_kq->>'ok')::boolean then raise exception using message = 'NV:' || (v_kq->>'error'); end if;
  return v_kq;
exception when raise_exception then
  if sqlerrm like 'NV:%' then return jsonb_build_object('ok', false, 'error', substr(sqlerrm, 4)); end if;
  raise;
end $$;

-- Lắp theo bộ dao chuẩn: mọi vị trí còn trống của máy
create or replace function public.gc_dao_lap_bo(p_ma_may text, p_ma_sp text, p_buoc integer, p_nguon text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me record; r record; v_kq jsonb; v_n int := 0;
begin
  select * into v_me from gc_dao_cu_nguoi('dung');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if not exists (select 1 from master_machines where ma_may = p_ma_may and bo_phan = 'Gia công - Sơn') then
    return jsonb_build_object('ok', false, 'error', coalesce(p_ma_may, '?') || ' không có trong danh mục máy Gia công');
  end if;
  for r in select bo.* from gc_bo_dao bo where bo.ma_sp = trim(coalesce(p_ma_sp, '')) and bo.buoc = coalesce(p_buoc, 1)
      and not exists (select 1 from gc_dao_tren_may t where t.ma_may = p_ma_may and t.vi_tri = bo.vi_tri and t.thao_luc is null)
      order by bo.vi_tri loop
    v_kq := gc_dao_lap_mot(p_ma_may, r.vi_tri, r.id_dao, r.so_luong, p_nguon, 0, p_ma_sp, p_buoc, null, v_me.o_ten);
    if not (v_kq->>'ok')::boolean then raise exception using message = 'NV:' || r.vi_tri || ': ' || (v_kq->>'error'); end if;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then return jsonb_build_object('ok', false, 'error', 'Không còn vị trí trống theo bộ dao chuẩn'); end if;
  return jsonb_build_object('ok', true, 'so_dao', v_n);
exception when raise_exception then
  if sqlerrm like 'NV:%' then return jsonb_build_object('ok', false, 'error', substr(sqlerrm, 4)); end if;
  raise;
end $$;

-- Thay / tháo dao. p_xu_ly_cu: 'mai' (Chờ mài → NG) / 'bo' (bỏ) / 'tra' (trả tủ → Mới).
-- p_id_dao_moi null = chỉ tháo. Dao mới lấy từ tủ (trừ Mới), lắp vào cùng vị trí, SP / bước theo p_ma_sp/p_buoc (trống = như dao cũ).
create or replace function public.gc_dao_thay(p_id_lap bigint, p_ly_do text, p_xu_ly_cu text, p_id_dao_moi bigint,
  p_so_luong_moi numeric, p_ma_sp text, p_buoc integer, p_ghi_chu text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me record; t gc_dao_tren_may%rowtype; v_ct numeric; v_tt int; v_kq jsonb; v_ld text := trim(coalesce(p_ly_do, ''));
  v_id_moi bigint;
begin
  select * into v_me from gc_dao_cu_nguoi('dung');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if v_ld = '' then return jsonb_build_object('ok', false, 'error', 'Chọn lý do thay'); end if;
  if coalesce(p_xu_ly_cu, '') not in ('mai','bo','tra') then return jsonb_build_object('ok', false, 'error', 'Chọn cách xử lý dao cũ'); end if;
  select * into t from gc_dao_tren_may where id = p_id_lap for update;
  if not found or t.thao_luc is not null then return jsonb_build_object('ok', false, 'error', 'Dao này đã được tháo — tải lại trang'); end if;
  select so_ct, tuoi_tho into v_ct, v_tt from gc_dao_tren_may_v where id = p_id_lap;
  update gc_dao_tren_may set thao_luc = now(), thao_boi = v_me.o_ten, ly_do_thao = v_ld, xu_ly_cu = p_xu_ly_cu,
    so_ct_thuc_te = v_ct, tuoi_tho_luc_thao = v_tt,
    ghi_chu = trim(both ' · ' from ghi_chu || ' · ' || trim(coalesce(p_ghi_chu, '')))
  where id = p_id_lap;
  v_kq := gc_dao_cu_ghi(case p_xu_ly_cu when 'mai' then 'ng' when 'bo' then 'bo' else 'tra' end, t.id_dao, t.so_luong,
    t.ma_may, v_ld, t.vi_tri || ' · chạy ' || v_ct || ' CT');
  if not (v_kq->>'ok')::boolean then raise exception using message = 'NV:' || (v_kq->>'error'); end if;
  if p_id_dao_moi is not null then
    v_kq := gc_dao_lap_mot(t.ma_may, t.vi_tri, p_id_dao_moi, coalesce(p_so_luong_moi, t.so_luong), 'tu', 0,
      coalesce(nullif(trim(coalesce(p_ma_sp, '')), ''), t.ma_sp), coalesce(p_buoc, t.buoc), null, v_me.o_ten);
    if not (v_kq->>'ok')::boolean then raise exception using message = 'NV:' || (v_kq->>'error'); end if;
    v_id_moi := (v_kq->>'id')::bigint;
  end if;
  return jsonb_build_object('ok', true, 'so_ct', v_ct, 'tuoi_tho', v_tt, 'id_moi', v_id_moi);
exception when raise_exception then
  if sqlerrm like 'NV:%' then return jsonb_build_object('ok', false, 'error', substr(sqlerrm, 4)); end if;
  raise;
end $$;

revoke execute on function public.gc_bo_dao_luu(text, integer, jsonb) from public, anon;
revoke execute on function public.gc_dao_lap(text, text, bigint, numeric, text, numeric, text, integer, text) from public, anon;
revoke execute on function public.gc_dao_lap_bo(text, text, integer, text) from public, anon;
revoke execute on function public.gc_dao_thay(bigint, text, text, bigint, numeric, text, integer, text) from public, anon;
grant execute on function public.gc_bo_dao_luu(text, integer, jsonb) to authenticated;
grant execute on function public.gc_dao_lap(text, text, bigint, numeric, text, numeric, text, integer, text) to authenticated;
grant execute on function public.gc_dao_lap_bo(text, text, integer, text) to authenticated;
grant execute on function public.gc_dao_thay(bigint, text, text, bigint, numeric, text, integer, text) to authenticated;
