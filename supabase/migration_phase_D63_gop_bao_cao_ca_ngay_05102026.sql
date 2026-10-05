-- D63: sửa báo cáo "Ca ngày 05/10/2026" — 7 máy DC4/5/6/7/8/10/11 bị kẹt ở
-- "Ca ngày 04/10" (Chủ nhật, không sản xuất — không có tem nào trong ngày
-- 04/10) nên khi trưởng ca kết ca "Ca ngày 05/10" lúc 18:10 chỉ có Kẽm 190T.
-- Sau đó trưởng ca kết nốt "Ca ngày 04/10" lúc 18:20 → báo cáo 04102026_Cangay
-- thực chất chứa TOÀN BỘ sản lượng/sự cố của ca ngày 05/10 (tem 12:21-17:53
-- ngày 05/10, sự cố 06:00-15:55 ngày 05/10).
--
-- Cách sửa (giống D53 nhưng CHÍNH XÁC, không ước lượng):
--   1. Chuyển duc_su_co_log + duc_lich_su_san_xuat của "Ca ngày 04/10" sang
--      "Ca ngày 05/10" (W41). Không đụng id_su_co (đã mang ngày 1005 đúng).
--   2. Gộp 2 báo cáo vào 05102026_Cangay. Các trường cộng dồn: cộng thẳng.
--      OEE: duc_end_shift tính avail = Σrun/Σppt, perf = min(1, Σideal/Σrun),
--      quality = Σok/(Σok+Σng) — các tổng Σ của báo cáo 04/10 được SUY NGƯỢC
--      chính xác từ chính báo cáo đó (Σideal tính lại từ lịch sử × cycle_time,
--      Σrun = Σideal/perf, Σppt = Σrun/avail — ra đúng 283.500s = 7 máy ×
--      40.500s), báo cáo 05/10 (Kẽm) tính lại khớp 100% với số đã lưu.
--   3. Xoá báo cáo 04102026_Cangay (Chủ nhật không sản xuất).
-- duc_ipqc_checkpoint của 7 máy vẫn mang ngay=04/10 + id_dong 04102026_… —
-- giữ nguyên, không đổi id_dong để tránh dính vào các dòng 05102026_Cangay_…
-- đang mở trong duc_ca_hien_tai.
--
-- Chạy 1 lần trên Supabase project PRODUCTION (staging không có dữ liệu này).

begin;

-- Σ của báo cáo 04/10 (suy ngược) và của báo cáo 05/10 (Kẽm), tính TRƯỚC khi dời dữ liệu.
create temp table d63_sum on commit drop as
with ideal as (
  select h.ngay, sum(mp.cycle_time_s * coalesce(h.tt_ca, 0)) as ideal
  from duc_lich_su_san_xuat h join master_products mp on mp.ma_sp = h.ma_sp
  where h.ca = 'Ca ngày' and h.ngay in ('2026-10-04', '2026-10-05') and mp.cycle_time_s > 0
  group by h.ngay
)
select b.ngay, i.ideal,
       i.ideal / b.performance_ca as run,
       i.ideal / b.performance_ca / b.availability_ca as ppt,
       b.tong_tt_ca as ok, b.tong_ng_ca as ng
from duc_bao_cao_ca b join ideal i on i.ngay = b.ngay
where b.id_bao_cao in ('04102026_Cangay', '05102026_Cangay');

update duc_su_co_log set ngay = '2026-10-05', tuan_sx = duc_iso_week('2026-10-05')
where ngay = '2026-10-04' and ca = 'Ca ngày';

update duc_lich_su_san_xuat set ngay = '2026-10-05', tuan_sx = duc_iso_week('2026-10-05')
where ngay = '2026-10-04' and ca = 'Ca ngày';

update duc_bao_cao_ca t set
  truong_ca               = a.truong_ca,
  so_may_co_kh            = x.so_may,
  so_may_hoan_thanh_kh    = x.so_may_dat,
  tong_kh_ca              = a.tong_kh_ca + t.tong_kh_ca,
  tong_tt_ca              = a.tong_tt_ca + t.tong_tt_ca,
  ty_le_hoan_thanh_ca     = (a.tong_tt_ca + t.tong_tt_ca) / nullif(a.tong_kh_ca + t.tong_kh_ca, 0),
  so_su_co_ca             = a.so_su_co_ca + t.so_su_co_ca,
  tong_phut_dung_ca       = a.tong_phut_dung_ca + t.tong_phut_dung_ca,
  availability_ca         = s.run / s.ppt,
  performance_ca          = least(1, s.ideal / s.run),
  quality_ca              = s.ok / nullif(s.ok + s.ng, 0),
  oee_ca                  = (s.run / s.ppt) * least(1, s.ideal / s.run) * (s.ok / nullif(s.ok + s.ng, 0)),
  tong_ng_ca              = a.tong_ng_ca + t.tong_ng_ca,
  tong_shot_nong_khuon_ca = a.tong_shot_nong_khuon_ca + t.tong_shot_nong_khuon_ca,
  nv_ca_bao_cao           = a.nv_ca_bao_cao || ', ' || t.nv_ca_bao_cao,
  ghi_chu                 = 'Gộp thủ công D63: cộng 7 máy DC4/5/6/7/8/10/11 bị kẹt ở Ca ngày 04/10 (CN, kết ca nhầm lúc 18:20 05/10). OEE tính chính xác từ tổng thành phần.'
from duc_bao_cao_ca a,
     (select sum(ideal) ideal, sum(run) run, sum(ppt) ppt, sum(ok) ok, sum(ng) ng from d63_sum) s,
     (select count(*) so_may, count(*) filter (where dat) so_may_dat
        from (select ma_may, bool_and(coalesce(tt_ca, 0) >= coalesce(kh_ca, 0)) dat
                from duc_lich_su_san_xuat where ngay = '2026-10-05' and ca = 'Ca ngày' group by ma_may) m) x
where t.id_bao_cao = '05102026_Cangay' and a.id_bao_cao = '04102026_Cangay';

delete from duc_bao_cao_ca where id_bao_cao = '04102026_Cangay';

commit;
