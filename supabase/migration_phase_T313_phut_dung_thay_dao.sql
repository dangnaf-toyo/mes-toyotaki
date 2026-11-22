-- T313 (22/11/2026): thời gian thay dao (Việc 5 SPEC thay dao).
-- Hộp Thay / Xoay cạnh nhập số phút dừng máy; ghi vào dòng dao cũ (dòng bị tháo).
-- Báo cáo Kho dao cụ cộng phút dừng theo máy.

alter table public.gc_dao_tren_may add column if not exists phut_dung integer
  check (phut_dung is null or phut_dung between 0 and 600);

drop function if exists public.gc_dao_thay(bigint, text, text, bigint, numeric, text, integer, text);
create or replace function public.gc_dao_thay(p_id_lap bigint, p_ly_do text, p_xu_ly_cu text, p_id_dao_moi bigint,
  p_so_luong_moi numeric, p_ma_sp text, p_buoc integer, p_ghi_chu text default null, p_phut_dung integer default null)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_me record; t gc_dao_tren_may%rowtype; v_ct numeric; v_dung numeric; v_tt int; v_kq jsonb; v_ld text := trim(coalesce(p_ly_do, ''));
  v_id_moi bigint;
begin
  select * into v_me from gc_dao_cu_nguoi('dung');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if v_ld = '' then return jsonb_build_object('ok', false, 'error', 'Chọn lý do thay'); end if;
  if coalesce(p_xu_ly_cu, '') not in ('mai','bo','tra') then return jsonb_build_object('ok', false, 'error', 'Chọn cách xử lý dao cũ'); end if;
  if p_phut_dung is not null and (p_phut_dung < 0 or p_phut_dung > 600) then
    return jsonb_build_object('ok', false, 'error', 'Số phút dừng 0–600'); end if;
  select * into t from gc_dao_tren_may where id = p_id_lap for update;
  if not found or t.thao_luc is not null then return jsonb_build_object('ok', false, 'error', 'Dao này đã được tháo — tải lại trang'); end if;
  select so_ct, so_dung, tuoi_tho into v_ct, v_dung, v_tt from gc_dao_tren_may_v where id = p_id_lap;
  update gc_dao_tren_may set thao_luc = now(), thao_boi = v_me.o_ten, ly_do_thao = v_ld, xu_ly_cu = p_xu_ly_cu,
    so_ct_thuc_te = v_ct, so_dung_thuc_te = v_dung, tuoi_tho_luc_thao = v_tt, phut_dung = p_phut_dung,
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
end $function$;
revoke execute on function public.gc_dao_thay(bigint, text, text, bigint, numeric, text, integer, text, integer) from public, anon;
grant execute on function public.gc_dao_thay(bigint, text, text, bigint, numeric, text, integer, text, integer) to authenticated;

drop function if exists public.gc_dao_xoay_canh(bigint, text, text);
create or replace function public.gc_dao_xoay_canh(p_id_lap bigint, p_ly_do text, p_ghi_chu text default null, p_phut_dung integer default null)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_me record; t gc_dao_tren_may%rowtype; v_so_canh int; v_ct numeric; v_dung numeric; v_tt int;
  v_ld text := trim(coalesce(p_ly_do, '')); v_now timestamptz := now(); v_id bigint;
begin
  select * into v_me from gc_dao_cu_nguoi('dung');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if v_ld = '' then return jsonb_build_object('ok', false, 'error', 'Chọn lý do xoay'); end if;
  if p_phut_dung is not null and (p_phut_dung < 0 or p_phut_dung > 600) then
    return jsonb_build_object('ok', false, 'error', 'Số phút dừng 0–600'); end if;
  select * into t from gc_dao_tren_may where id = p_id_lap for update;
  if not found or t.thao_luc is not null then return jsonb_build_object('ok', false, 'error', 'Dao này đã được tháo — tải lại trang'); end if;
  select so_canh into v_so_canh from gc_dao_cu where id = t.id_dao;
  if t.canh >= coalesce(v_so_canh, 1) then
    return jsonb_build_object('ok', false, 'error', 'Đã hết cạnh (' || t.canh || '/' || coalesce(v_so_canh, 1) || ') — bấm Thay');
  end if;
  select so_ct, so_dung, tuoi_tho into v_ct, v_dung, v_tt from gc_dao_tren_may_v where id = p_id_lap;
  update gc_dao_tren_may set thao_luc = v_now, thao_boi = v_me.o_ten, ly_do_thao = v_ld, xu_ly_cu = 'xoay',
    so_ct_thuc_te = v_ct, so_dung_thuc_te = v_dung, tuoi_tho_luc_thao = v_tt, phut_dung = p_phut_dung,
    ghi_chu = trim(both ' · ' from ghi_chu || ' · ' || trim(coalesce(p_ghi_chu, '')))
  where id = p_id_lap;
  insert into gc_dao_tren_may (ma_may, vi_tri, id_dao, ma_dao, so_luong, ma_sp, buoc, nguon, so_ct_dau, lap_luc, lap_boi, canh, ghi_chu)
  values (t.ma_may, t.vi_tri, t.id_dao, t.ma_dao, t.so_luong, t.ma_sp, t.buoc, 'tu', 0, v_now, v_me.o_ten, t.canh + 1, '')
  returning id into v_id;
  perform gc_thung_dau_gan(t.ma_may, 'Xoay cạnh ' || t.vi_tri, v_me.o_ten);
  return jsonb_build_object('ok', true, 'so_ct', v_ct, 'so_dung', v_dung, 'tuoi_tho', v_tt, 'canh', t.canh + 1,
    'so_canh', v_so_canh, 'id_moi', v_id);
end $function$;
revoke execute on function public.gc_dao_xoay_canh(bigint, text, text, integer) from public, anon;
grant execute on function public.gc_dao_xoay_canh(bigint, text, text, integer) to authenticated;

-- View thêm cột phut_dung (cuối danh sách cột).
create or replace view public.gc_dao_tren_may_v with (security_invoker = true) as
 SELECT t.id, t.ma_may, t.vi_tri, t.id_dao, t.ma_dao, t.so_luong, t.ma_sp, t.buoc, t.nguon, t.so_ct_dau, t.lap_luc, t.lap_boi,
    t.thao_luc, t.thao_boi, t.ly_do_thao, t.xu_ly_cu, t.so_ct_thuc_te, t.tuoi_tho_luc_thao, t.ghi_chu, t.so_dung_thuc_te, t.canh,
    d.ten_chuan, d.tuoi_tho_theo, d.ton_moi, d.so_canh,
    COALESCE(bo.tuoi_tho_chuan, d.tuoi_tho_chuan) AS tuoi_tho,
    COALESCE(bo.so_lan_ct, (1)::numeric) AS so_lan_ct,
    (t.so_ct_dau + gc_dao_so_ct(t.ma_may, t.lap_luc, t.thao_luc)) AS so_ct,
    ((t.so_ct_dau * COALESCE(bo.so_lan_ct, (1)::numeric)) + gc_dao_so_dung(t.ma_may, t.vi_tri, t.id_dao, t.lap_luc, t.thao_luc, COALESCE(bo.so_lan_ct, (1)::numeric))) AS so_dung,
    t.phut_dung
   FROM gc_dao_tren_may t
     JOIN gc_dao_cu d ON d.id = t.id_dao
     LEFT JOIN gc_bo_dao bo ON bo.ma_sp = t.ma_sp AND bo.buoc = t.buoc AND bo.vi_tri = t.vi_tri AND bo.id_dao = t.id_dao;
