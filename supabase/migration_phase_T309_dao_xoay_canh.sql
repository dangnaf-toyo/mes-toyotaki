-- T309 (22/11/2026): mảnh dao xoay cạnh (máy tiện) — Việc 1 trong SPEC_Quan_ly_thay_dao_MES.md.
--   * gc_dao_cu.so_canh: số cạnh dùng được của mảnh (mặc định 1 = dao thường).
--   * gc_dao_tren_may.canh: cạnh đang dùng. Xoay cạnh = đóng dòng hiện tại (xu_ly_cu = 'xoay', ghi số CT
--     thực tế của cạnh đó) + mở dòng mới cạnh +1, số chi tiết từ 0. KHÔNG đổi tồn kho.
--   * Tuổi thọ chuẩn của mảnh = tuổi thọ MỖI CẠNH. Báo cáo chi phí chia thêm số cạnh.
--   * gc_dao_lap thêm p_canh (dao có sẵn trên máy đang ở cạnh nào).
-- Trạng thái: Đã chạy STAGING + PROD 22/11/2026.
-- An toàn chạy lại. Chạy 4 phần: a (cột), b (view), c (gc_dao_cu_luu + gc_dao_lap), d (gc_dao_xoay_canh).

-- ===== Phần a =====
alter table public.gc_dao_cu add column if not exists so_canh integer not null default 1;
alter table public.gc_dao_cu drop constraint if exists gc_dao_cu_so_canh_check;
alter table public.gc_dao_cu add constraint gc_dao_cu_so_canh_check check (so_canh between 1 and 20);
alter table public.gc_dao_tren_may add column if not exists canh integer not null default 1;
alter table public.gc_dao_tren_may drop constraint if exists gc_dao_tren_may_canh_check;
alter table public.gc_dao_tren_may add constraint gc_dao_tren_may_canh_check check (canh between 1 and 20);
alter table public.gc_dao_tren_may drop constraint if exists gc_dao_tren_may_xu_ly_cu_check;
alter table public.gc_dao_tren_may add constraint gc_dao_tren_may_xu_ly_cu_check
  check (xu_ly_cu is null or xu_ly_cu in ('mai','bo','tra','xoay'));

-- ===== Phần b: view thêm so_canh (t.* có thêm cột canh) =====
drop view if exists public.gc_dao_tren_may_v;
create view public.gc_dao_tren_may_v with (security_invoker = true) as
select t.*, d.ten_chuan, d.tuoi_tho_theo, d.ton_moi, d.so_canh,
  coalesce(bo.tuoi_tho_chuan, d.tuoi_tho_chuan) as tuoi_tho,
  coalesce(bo.so_lan_ct, 1) as so_lan_ct,
  t.so_ct_dau + gc_dao_so_ct(t.ma_may, t.lap_luc, t.thao_luc) as so_ct,
  t.so_ct_dau * coalesce(bo.so_lan_ct, 1)
    + gc_dao_so_dung(t.ma_may, t.vi_tri, t.id_dao, t.lap_luc, t.thao_luc, coalesce(bo.so_lan_ct, 1)) as so_dung
from gc_dao_tren_may t
join gc_dao_cu d on d.id = t.id_dao
left join gc_bo_dao bo on bo.ma_sp = t.ma_sp and bo.buoc = t.buoc and bo.vi_tri = t.vi_tri and bo.id_dao = t.id_dao;
revoke all on public.gc_dao_tren_may_v from anon;
grant select on public.gc_dao_tren_may_v to authenticated;

-- ===== Phần c1: gc_dao_cu_luu lưu so_canh =====
create or replace function public.gc_dao_cu_luu(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me record; v_id bigint := nullif(p->>'id', '')::bigint; v_ma text := upper(trim(coalesce(p->>'ma_dao', '')));
  v_ten text := trim(coalesce(p->>'ten_chuan', '')); v_canh int := coalesce(nullif(p->>'so_canh', '')::int, 1);
begin
  select * into v_me from gc_dao_cu_nguoi('quan_ly');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if v_ma = '' then return jsonb_build_object('ok', false, 'error', 'Nhập mã dao'); end if;
  if v_ten = '' then return jsonb_build_object('ok', false, 'error', 'Nhập tên chuẩn'); end if;
  if v_canh < 1 or v_canh > 20 then return jsonb_build_object('ok', false, 'error', 'Số cạnh từ 1 đến 20'); end if;
  if exists (select 1 from gc_dao_cu where upper(ma_dao) = v_ma and id is distinct from v_id) then
    return jsonb_build_object('ok', false, 'error', 'Mã đã có: ' || v_ma);
  end if;
  if v_id is null then
    insert into gc_dao_cu (ma_dao, ten_chuan, nhom, quy_cach, hang, ma_sp_dung, dvt, quan_ly, tuoi_tho_theo,
      tuoi_tho_chuan, ton_toi_thieu, don_gia, vi_tri, ghi_chu, dang_dung, so_canh)
    values (v_ma, v_ten, coalesce(nullif(p->>'nhom', ''), left(v_ma, 1)), trim(coalesce(p->>'quy_cach', '')),
      trim(coalesce(p->>'hang', '')), trim(coalesce(p->>'ma_sp_dung', '')), coalesce(nullif(trim(p->>'dvt'), ''), 'Cái'),
      coalesce(nullif(p->>'quan_ly', ''), 'so_luong'), coalesce(nullif(p->>'tuoi_tho_theo', ''), 'chi_tiet'),
      nullif(p->>'tuoi_tho_chuan', '')::int, coalesce(nullif(p->>'ton_toi_thieu', '')::numeric, 0),
      nullif(p->>'don_gia', '')::numeric, trim(coalesce(p->>'vi_tri', '')), trim(coalesce(p->>'ghi_chu', '')),
      coalesce((p->>'dang_dung')::boolean, true), v_canh)
    returning id into v_id;
  else
    if exists (select 1 from gc_dao_cu_giao_dich where id_dao = v_id) and exists (select 1 from gc_dao_cu where id = v_id and ma_dao <> v_ma) then
      return jsonb_build_object('ok', false, 'error', 'Mã đã có giao dịch — không đổi mã');
    end if;
    if exists (select 1 from gc_dao_tren_may where id_dao = v_id and thao_luc is null and canh > v_canh) then
      return jsonb_build_object('ok', false, 'error', 'Có mảnh đang dùng cạnh lớn hơn ' || v_canh || ' trên máy');
    end if;
    update gc_dao_cu set ma_dao = v_ma, ten_chuan = v_ten, nhom = coalesce(nullif(p->>'nhom', ''), left(v_ma, 1)),
      quy_cach = trim(coalesce(p->>'quy_cach', '')), hang = trim(coalesce(p->>'hang', '')),
      ma_sp_dung = trim(coalesce(p->>'ma_sp_dung', '')), dvt = coalesce(nullif(trim(p->>'dvt'), ''), 'Cái'),
      quan_ly = coalesce(nullif(p->>'quan_ly', ''), 'so_luong'), tuoi_tho_theo = coalesce(nullif(p->>'tuoi_tho_theo', ''), 'chi_tiet'),
      tuoi_tho_chuan = nullif(p->>'tuoi_tho_chuan', '')::int, ton_toi_thieu = coalesce(nullif(p->>'ton_toi_thieu', '')::numeric, 0),
      don_gia = nullif(p->>'don_gia', '')::numeric, vi_tri = trim(coalesce(p->>'vi_tri', '')),
      ghi_chu = trim(coalesce(p->>'ghi_chu', '')), dang_dung = coalesce((p->>'dang_dung')::boolean, true),
      so_canh = v_canh, updated_at = now()
    where id = v_id;
    if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy mã dao'); end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
exception when check_violation then
  return jsonb_build_object('ok', false, 'error', 'Giá trị không hợp lệ (nhóm / tuổi thọ / tồn tối thiểu / giá / số cạnh)');
end $$;

-- ===== Phần c2: gc_dao_lap thêm p_canh (đổi danh sách tham số → drop bản cũ) =====
drop function if exists public.gc_dao_lap(text, text, bigint, numeric, text, numeric, text, integer, text);
create or replace function public.gc_dao_lap(p_ma_may text, p_vi_tri text, p_id_dao bigint, p_so_luong numeric,
  p_nguon text, p_so_ct_dau numeric, p_ma_sp text, p_buoc integer, p_ghi_chu text default null, p_canh integer default 1)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me record; v_kq jsonb; v_canh int := coalesce(p_canh, 1); v_so_canh int;
begin
  select * into v_me from gc_dao_cu_nguoi('dung');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if not exists (select 1 from master_machines where ma_may = p_ma_may and bo_phan = 'Gia công - Sơn') then
    return jsonb_build_object('ok', false, 'error', coalesce(p_ma_may, '?') || ' không có trong danh mục máy Gia công');
  end if;
  select so_canh into v_so_canh from gc_dao_cu where id = p_id_dao;
  if coalesce(p_nguon, 'tu') <> 'may' then v_canh := 1; end if;
  if v_canh < 1 or v_canh > coalesce(v_so_canh, 1) then
    return jsonb_build_object('ok', false, 'error', 'Cạnh phải từ 1 đến ' || coalesce(v_so_canh, 1));
  end if;
  v_kq := gc_dao_lap_mot(p_ma_may, p_vi_tri, p_id_dao, p_so_luong, p_nguon, p_so_ct_dau, p_ma_sp, p_buoc, p_ghi_chu, v_me.o_ten);
  if not (v_kq->>'ok')::boolean then raise exception using message = 'NV:' || (v_kq->>'error'); end if;
  if v_canh > 1 then update gc_dao_tren_may set canh = v_canh where id = (v_kq->>'id')::bigint; end if;
  return v_kq;
exception when raise_exception then
  if sqlerrm like 'NV:%' then return jsonb_build_object('ok', false, 'error', substr(sqlerrm, 4)); end if;
  raise;
end $$;
revoke execute on function public.gc_dao_lap(text, text, bigint, numeric, text, numeric, text, integer, text, integer) from public, anon;
grant execute on function public.gc_dao_lap(text, text, bigint, numeric, text, numeric, text, integer, text, integer) to authenticated;

-- ===== Phần d: xoay cạnh =====
create or replace function public.gc_dao_xoay_canh(p_id_lap bigint, p_ly_do text, p_ghi_chu text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me record; t gc_dao_tren_may%rowtype; v_so_canh int; v_ct numeric; v_dung numeric; v_tt int;
  v_ld text := trim(coalesce(p_ly_do, '')); v_now timestamptz := now(); v_id bigint;
begin
  select * into v_me from gc_dao_cu_nguoi('dung');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if v_ld = '' then return jsonb_build_object('ok', false, 'error', 'Chọn lý do xoay'); end if;
  select * into t from gc_dao_tren_may where id = p_id_lap for update;
  if not found or t.thao_luc is not null then return jsonb_build_object('ok', false, 'error', 'Dao này đã được tháo — tải lại trang'); end if;
  select so_canh into v_so_canh from gc_dao_cu where id = t.id_dao;
  if t.canh >= coalesce(v_so_canh, 1) then
    return jsonb_build_object('ok', false, 'error', 'Đã hết cạnh (' || t.canh || '/' || coalesce(v_so_canh, 1) || ') — bấm Thay');
  end if;
  select so_ct, so_dung, tuoi_tho into v_ct, v_dung, v_tt from gc_dao_tren_may_v where id = p_id_lap;
  update gc_dao_tren_may set thao_luc = v_now, thao_boi = v_me.o_ten, ly_do_thao = v_ld, xu_ly_cu = 'xoay',
    so_ct_thuc_te = v_ct, so_dung_thuc_te = v_dung, tuoi_tho_luc_thao = v_tt,
    ghi_chu = trim(both ' · ' from ghi_chu || ' · ' || trim(coalesce(p_ghi_chu, '')))
  where id = p_id_lap;
  insert into gc_dao_tren_may (ma_may, vi_tri, id_dao, ma_dao, so_luong, ma_sp, buoc, nguon, so_ct_dau, lap_luc, lap_boi, canh, ghi_chu)
  values (t.ma_may, t.vi_tri, t.id_dao, t.ma_dao, t.so_luong, t.ma_sp, t.buoc, 'tu', 0, v_now, v_me.o_ten, t.canh + 1, '')
  returning id into v_id;
  return jsonb_build_object('ok', true, 'so_ct', v_ct, 'so_dung', v_dung, 'tuoi_tho', v_tt, 'canh', t.canh + 1,
    'so_canh', v_so_canh, 'id_moi', v_id);
end $$;
revoke execute on function public.gc_dao_xoay_canh(bigint, text, text) from public, anon;
grant execute on function public.gc_dao_xoay_canh(bigint, text, text) to authenticated;
