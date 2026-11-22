-- T308 (22/11/2026): dao taro — số lỗ ren/chi tiết lấy theo MÃ SP + BƯỚC CỦA TỪNG THÙNG Xong,
-- không theo mã SP lúc lắp dao (máy đổi SP mà không bấm "Đổi mã" thì trước đây tính sai).
--   so_dung = so_ct_dau × lần/CT lúc lắp + Σ (SL ra thùng × lần/CT của bộ dao đúng SP + bước thùng đó)
--   Thùng có SP chưa khai báo bộ dao chứa dao này → dùng lần/CT lúc lắp (như cũ).
-- Dao thường (lần/CT = 1) không đổi kết quả. Thêm cột gc_dao_tren_may.so_dung_thuc_te (ghi lúc tháo).
-- An toàn chạy lại. Chạy 3 phần: a (cột + hàm), b (view), c (gc_dao_thay).

-- ===== Phần a =====
alter table public.gc_dao_tren_may add column if not exists so_dung_thuc_te numeric;

create or replace function public.gc_dao_so_dung(p_ma_may text, p_vi_tri text, p_id_dao bigint,
  p_tu timestamptz, p_den timestamptz, p_lan_mac_dinh numeric)
returns numeric language sql stable security definer set search_path to 'public' as $$
  select coalesce(sum(coalesce(b.sl_ra, 0) * coalesce(
      (select bo.so_lan_ct from gc_bo_dao bo
        where bo.ma_sp = b.ma_sp and bo.buoc = b.buoc and bo.vi_tri = p_vi_tri and bo.id_dao = p_id_dao limit 1),
      p_lan_mac_dinh, 1)), 0)
  from gc_tem_buoc b
  where b.ma_may = p_ma_may and b.xong_luc is not null and b.bo_luc is null
    and b.xong_luc >= p_tu and (p_den is null or b.xong_luc < p_den);
$$;
revoke execute on function public.gc_dao_so_dung(text, text, bigint, timestamptz, timestamptz, numeric) from public, anon;
grant execute on function public.gc_dao_so_dung(text, text, bigint, timestamptz, timestamptz, numeric) to authenticated;

-- ===== Phần b: view thêm cột so_dung (drop vì t.* có thêm cột mới) =====
drop view if exists public.gc_dao_tren_may_v;
create view public.gc_dao_tren_may_v with (security_invoker = true) as
select t.*, d.ten_chuan, d.tuoi_tho_theo, d.ton_moi,
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

-- ===== Phần c: gc_dao_thay ghi thêm so_dung_thuc_te =====
create or replace function public.gc_dao_thay(p_id_lap bigint, p_ly_do text, p_xu_ly_cu text, p_id_dao_moi bigint,
  p_so_luong_moi numeric, p_ma_sp text, p_buoc integer, p_ghi_chu text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me record; t gc_dao_tren_may%rowtype; v_ct numeric; v_dung numeric; v_tt int; v_kq jsonb; v_ld text := trim(coalesce(p_ly_do, ''));
  v_id_moi bigint;
begin
  select * into v_me from gc_dao_cu_nguoi('dung');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if v_ld = '' then return jsonb_build_object('ok', false, 'error', 'Chọn lý do thay'); end if;
  if coalesce(p_xu_ly_cu, '') not in ('mai','bo','tra') then return jsonb_build_object('ok', false, 'error', 'Chọn cách xử lý dao cũ'); end if;
  select * into t from gc_dao_tren_may where id = p_id_lap for update;
  if not found or t.thao_luc is not null then return jsonb_build_object('ok', false, 'error', 'Dao này đã được tháo — tải lại trang'); end if;
  select so_ct, so_dung, tuoi_tho into v_ct, v_dung, v_tt from gc_dao_tren_may_v where id = p_id_lap;
  update gc_dao_tren_may set thao_luc = now(), thao_boi = v_me.o_ten, ly_do_thao = v_ld, xu_ly_cu = p_xu_ly_cu,
    so_ct_thuc_te = v_ct, so_dung_thuc_te = v_dung, tuoi_tho_luc_thao = v_tt,
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
  return jsonb_build_object('ok', true, 'so_ct', v_ct, 'so_dung', v_dung, 'tuoi_tho', v_tt, 'id_moi', v_id_moi);
exception when raise_exception then
  if sqlerrm like 'NV:%' then return jsonb_build_object('ok', false, 'error', substr(sqlerrm, 4)); end if;
  raise;
end $$;

-- Bù cho lần tháo cũ (nếu có): giữ kết quả cũ = so_ct_thuc_te × lần/CT lúc lắp
update public.gc_dao_tren_may t set so_dung_thuc_te = t.so_ct_thuc_te * coalesce(
  (select bo.so_lan_ct from gc_bo_dao bo where bo.ma_sp = t.ma_sp and bo.buoc = t.buoc and bo.vi_tri = t.vi_tri and bo.id_dao = t.id_dao), 1)
where t.thao_luc is not null and t.so_dung_thuc_te is null and t.so_ct_thuc_te is not null;
