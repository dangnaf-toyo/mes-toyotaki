-- ============================================================================
-- Phase T235 — NG Bavia theo từng tem Đúc (tab "NG theo tem Đúc" trong
-- bieu-do-chat-luong.html, shared/bavia-ng-tem.js).
--
-- Mỗi tem Đúc (TKD…) đã qua Bavia trong khoảng ngày [p_tu, p_den] (ngày Bavia):
--   ok   = Σ cd_tem_nguon.so_luong_lay của các thùng OK Bavia (bavia_thung) lấy từ tem
--   ng   = Σ cd_ng_khai_bao (cong_doan='Bavia') theo tag_no, kèm từng loại lỗi
--   sua  = Σ bavia_bao_ng_log (NG chờ sửa, không tính vào % NG)
--   giờ đúc ≈ duc_tem.ngay_gio_ghi_nhan (Đúc ghi nhận tem), không có thì ngay_gio_in
--   shot từ BD = shot đồng hồ khuôn tại giờ đúc − shot lúc BD gần nhất trước tem.
--     Đồng hồ chỉ biết tại các mốc: lần BD (duc_khuon_bao_duong_log.shot_tai_thoi_diem,
--     bỏ loại 'Sửa chữa') và số kết ca gần nhất (duc_shot_khuon). Giữa 2 mốc, shot phân
--     bổ theo tỷ lệ Σ so_luong_tt các tem Đúc (TKD…) cùng khuôn → khớp đồng hồ tại mốc.
--     Sau mốc cuối: Σ so_luong_tt / cavity (shot_dh = false). Chưa có BD: shot = null.
--     (Cộng thẳng SL tem / cavity lệch ~15% so với đồng hồ — K09 21/10→06/11.)
-- su_kien: sự cố A2 (khuôn) / C3 (đổi khuôn) / F1 (IPQC NG) + bảo dưỡng của các
--   khuôn trên, trong khoảng giờ đúc của các tem (±2 ngày) — để vẽ vạch trên trục thời gian.
-- ngay_co_ng: các ngày Bavia có ≥ 1 khai NG (trang mặc định chỉ hiện tem của các ngày
--   này — cùng quy tắc T233 của P-Chart).
--
-- Security definer (đọc nhiều bảng), chỉ authenticated gọi; tối đa 93 ngày/lần.
-- Đã chạy: prod + staging 10/11/2026. Idempotent.
-- ============================================================================

create or replace function public.bavia_ng_theo_tem(p_tu date, p_den date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập'; end if;
  if p_tu is null or p_den is null or p_den < p_tu then raise exception 'Khoảng ngày không hợp lệ'; end if;
  if p_den - p_tu > 92 then raise exception 'Chọn tối đa 93 ngày'; end if;

  with ok as (
    select n.tag_no_nguon tag, sum(n.so_luong_lay) ok, max(b.ngay) d
    from cd_tem_nguon n join bavia_thung b on b.tag_tp = n.tag_no_moi
    where b.ngay between p_tu and p_den
    group by 1
  ),
  ngr as (
    select g.tag_no tag, coalesce(t.ngay, (g.ngay_gio at time zone 'Asia/Ho_Chi_Minh')::date) d,
           coalesce(nullif(trim(g.loai_ng), ''), 'Khác') loai, g.so_luong sl
    from cd_ng_khai_bao g left join cd_tram_hien_tai t on t.id_tram = g.id_tram
    where g.cong_doan = 'Bavia'
      and g.ngay_gio >= p_tu::timestamp - interval '2 day' and g.ngay_gio < p_den::timestamp + interval '3 day'
  ),
  ngk as (select * from ngr where d between p_tu and p_den),
  ngl as (select tag, loai, sum(sl) sl, max(d) d from ngk group by 1, 2),
  ng as (select tag, sum(sl) ng, max(d) d, jsonb_object_agg(loai, sl) loai from ngl group by 1),
  sua as (
    select tag_nguon tag, sum(so_luong) sua
    from bavia_bao_ng_log
    where (created_at at time zone 'Asia/Ho_Chi_Minh')::date between p_tu and p_den
    group by 1
  ),
  tags as (select tag from ok union select tag from ng union select tag from sua),
  tem as (
    select t.tag_no, t.ma_sp, coalesce(nullif(t.so_khuon_tt, ''), t.so_khuon) khuon,
           coalesce(nullif(t.may_tt, ''), t.may_duc_chi_thi) may, t.ngay,
           coalesce(t.ngay_gio_ghi_nhan, t.ngay_gio_in) tg, t.nguoi_tt, t.so_luong_tt, mp.cavity
    from duc_tem t join tags on tags.tag = t.tag_no
    left join master_products mp on mp.ma_sp = t.ma_sp
    where t.tag_no not ilike 'TP%'
  ),
  -- Mốc đồng hồ shot: lần BD trước tem (a, S_a) và mốc kế tiếp (b, S_b) = lần BD sau
  -- tem, không có thì số đồng hồ lúc kết ca gần nhất (duc_shot_khuon). Shot giữa 2 mốc
  -- phân bổ theo tỷ lệ sản lượng tem Đúc cùng khuôn (C) → khớp đúng đồng hồ tại các mốc.
  tem_a as (
    select tem.*, bd.thoi_diem_ghi bd_luc, bd.loai bd_loai, bd.shot_tai_thoi_diem s_a,
           coalesce(nx.thoi_diem_ghi, case when k.last_updated_at > tem.tg then k.last_updated_at end) b_luc,
           coalesce(nx.shot_tai_thoi_diem, case when k.last_updated_at > tem.tg then k.tong_shot_luy_ke end) s_b
    from tem
    left join lateral (
      select l.thoi_diem_ghi, l.loai, l.shot_tai_thoi_diem from duc_khuon_bao_duong_log l
      where l.ma_khuon = tem.khuon and l.loai <> 'Sửa chữa' and l.thoi_diem_ghi <= tem.tg
      order by l.thoi_diem_ghi desc limit 1
    ) bd on true
    left join lateral (
      select l.thoi_diem_ghi, l.shot_tai_thoi_diem from duc_khuon_bao_duong_log l
      where l.ma_khuon = tem.khuon and l.loai <> 'Sửa chữa' and l.thoi_diem_ghi > tem.tg
      order by l.thoi_diem_ghi limit 1
    ) nx on true
    left join duc_shot_khuon k on k.ma_khuon = tem.khuon
  ),
  tem_c as (
    select a.*,
      (select sum(coalesce(t2.so_luong_tt, 0)) from duc_tem t2
        where t2.tag_no ilike 'TKD%' and coalesce(nullif(t2.so_khuon_tt, ''), t2.so_khuon) = a.khuon
          and coalesce(t2.ngay_gio_ghi_nhan, t2.ngay_gio_in) > a.bd_luc
          and coalesce(t2.ngay_gio_ghi_nhan, t2.ngay_gio_in) <= a.tg) c_at,
      (select sum(coalesce(t2.so_luong_tt, 0)) from duc_tem t2
        where t2.tag_no ilike 'TKD%' and coalesce(nullif(t2.so_khuon_tt, ''), t2.so_khuon) = a.khuon
          and coalesce(t2.ngay_gio_ghi_nhan, t2.ngay_gio_in) > a.bd_luc
          and coalesce(t2.ngay_gio_ghi_nhan, t2.ngay_gio_in) <= a.b_luc) c_ab
    from tem_a a
  ),
  tem2 as (
    select c.*,
      case when c.bd_luc is null then null
           when c.s_b is not null and c.s_a is not null and coalesce(c.c_ab, 0) > 0
             then round((c.s_b - c.s_a) * coalesce(c.c_at, 0) / c.c_ab)
           when coalesce(c.cavity, 0) > 0 then floor(coalesce(c.c_at, 0) / c.cavity)
      end shot,
      (c.s_b is not null and c.s_a is not null and coalesce(c.c_ab, 0) > 0) shot_theo_dong_ho
    from tem_c c
  ),
  pham_vi as (select min(tg) - interval '2 day' a, max(tg) + interval '2 day' b from tem2),
  ds_khuon as (select distinct khuon from tem2 where khuon is not null),
  su_kien as (
    select s.gio_phat_sinh t, s.so_khuon k, s.ma_may may, left(s.loai_su_co, 2) loai,
           left(split_part(coalesce(s.noi_dung_xu_ly, ''), E'\n', 1), 90) nd, s.thoi_gian_dung_phut ph
    from duc_su_co_log s, pham_vi
    where s.so_khuon in (select khuon from ds_khuon)
      and left(s.loai_su_co, 2) in ('A2', 'C3', 'F1')
      and s.gio_phat_sinh between pham_vi.a and pham_vi.b
    union all
    select l.thoi_diem_ghi, l.ma_khuon, null, 'BD', l.loai || coalesce(' · shot ' || l.shot_tai_thoi_diem::bigint, ''), l.thoi_gian_dung_phut
    from duc_khuon_bao_duong_log l, pham_vi
    where l.ma_khuon in (select khuon from ds_khuon)
      and l.thoi_diem_ghi between pham_vi.a and pham_vi.b
  )
  select jsonb_build_object(
    'tem', coalesce((select jsonb_agg(jsonb_build_object(
        'tag', t.tag_no, 'sp', t.ma_sp, 'khuon', t.khuon, 'may', t.may, 'ngay', t.ngay, 'tg', t.tg,
        'nguoi', t.nguoi_tt, 'sl_tem', t.so_luong_tt,
        'ok', coalesce(o.ok, 0), 'ng', coalesce(n.ng, 0), 'sua', coalesce(s.sua, 0),
        'loai', coalesce(n.loai, '{}'::jsonb), 'd', greatest(o.d, n.d),
        'shot', t.shot, 'shot_dh', t.shot_theo_dong_ho, 'bd_luc', t.bd_luc, 'bd_loai', t.bd_loai) order by t.tg)
      from tem2 t left join ok o on o.tag = t.tag_no left join ng n on n.tag = t.tag_no left join sua s on s.tag = t.tag_no), '[]'::jsonb),
    'su_kien', coalesce((select jsonb_agg(jsonb_build_object('t', t, 'k', k, 'may', may, 'loai', loai, 'nd', nd, 'ph', ph) order by t) from su_kien), '[]'::jsonb),
    'ngay_co_ng', coalesce((select jsonb_agg(distinct d) from ngk), '[]'::jsonb)
  ) into v;
  return v;
end $$;

revoke execute on function public.bavia_ng_theo_tem(date, date) from public, anon;
grant execute on function public.bavia_ng_theo_tem(date, date) to authenticated;
