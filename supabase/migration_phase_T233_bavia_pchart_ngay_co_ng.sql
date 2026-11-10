-- ============================================================================
-- Phase T233 — P-Chart NG Bavia: chỉ tính ngày MES khi ngày đó có khai NG.
--
-- Bối cảnh (10/11/2026): Bavia bắt đầu dùng thử MES — mới quét tem thùng OK
-- (bavia_thung), chưa khai NG (cd_ng_khai_bao cong_doan='Bavia'). Hàm
-- bavia_ng_du_lieu (T159) lấy MES cho ngày > mốc Excel nên các ngày chỉ có tem OK
-- hiện 0% NG giả trên P-Chart.
-- User chọn: ngày MES nào CHƯA có lần khai NG Bavia nào thì không đưa vào
-- (cả SL sản xuất lẫn NG); có ≥ 1 lần khai NG trong ngày thì tính như cũ.
-- Ngày Excel (≤ mốc) không đổi.
--
-- Đã chạy: prod + staging 10/11/2026. Idempotent.
-- ============================================================================

create or replace function public.bavia_ng_du_lieu(p_tu date, p_den date)
returns jsonb
language sql
stable
set search_path to 'public'
as $function$
  with moc as (select coalesce(max(ngay), date '2000-01-01') m from bavia_sx_qua_khu),
  ng_mes as (
    select coalesce(t.ngay, (g.ngay_gio at time zone 'Asia/Ho_Chi_Minh')::date) ngay, g.ma_sp, g.loai_ng, g.so_luong, g.ghi_chu
    from cd_ng_khai_bao g left join cd_tram_hien_tai t on t.id_tram = g.id_tram
    where g.cong_doan = 'Bavia' and g.ngay_gio >= p_tu::timestamp - interval '2 day' and g.ngay_gio < p_den::timestamp + interval '3 day'
  ),
  ng_mes_k as (select n.* from ng_mes n, moc where n.ngay between p_tu and p_den and n.ngay > moc.m),
  -- T233: ngày MES hợp lệ = ngày có ít nhất 1 lần khai NG Bavia
  ngay_co_ng as (select distinct ngay from ng_mes_k),
  ok_mes as (
    select b.ngay, b.ma_sp, sum(b.so_luong) ok from bavia_thung b, moc
    where b.ngay between p_tu and p_den and b.ngay > moc.m
      and b.ngay in (select ngay from ngay_co_ng)
    group by 1, 2
  ),
  sx_mes as (
    select coalesce(o.ngay, n.ngay) ngay, coalesce(o.ma_sp, n.ma_sp) ma_sp, coalesce(o.ok, 0) + coalesce(n.ng, 0) n
    from ok_mes o full join (select ngay, ma_sp, sum(so_luong) ng from ng_mes_k group by 1, 2) n
      on n.ngay = o.ngay and n.ma_sp = o.ma_sp
  ),
  sx as (
    select ngay, ma_sp, sum(so_luong) n, 'excel' nguon from bavia_sx_qua_khu where ngay between p_tu and p_den group by 1, 2
    union all select ngay, ma_sp, n, 'mes' from sx_mes where n > 0
  ),
  ng as (
    select ngay, ma_sp, loai_ng, sum(so_luong) sl, string_agg(distinct nullif(loai_ng_goc, loai_ng), ', ') gc
      from bavia_ng_qua_khu where ngay between p_tu and p_den group by 1, 2, 3
    union all select ngay, ma_sp, loai_ng, sum(so_luong), string_agg(distinct ghi_chu, ', ') from ng_mes_k group by 1, 2, 3
  )
  select jsonb_build_object(
    'sx', coalesce((select jsonb_agg(jsonb_build_array(ngay, ma_sp, n, nguon)) from sx), '[]'::jsonb),
    'ng', coalesce((select jsonb_agg(jsonb_build_array(ngay, ma_sp, loai_ng, sl, gc)) from ng), '[]'::jsonb));
$function$;
