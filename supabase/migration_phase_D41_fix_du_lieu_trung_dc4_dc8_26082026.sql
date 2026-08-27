-- ============================================================================
-- D41 — Sửa dữ liệu sản lượng DC 4 / DC 8 ngày 26/08 bị đếm trùng Ca ngày =
-- Ca đêm (cùng gốc lỗi D39/D40 — máy kẹt sai phương án ca khiến sp_start_time/
-- sp_end_time của dòng chồng lấn giữa 2 ca, duc_recompute_tt_ca đếm tem 2 lần
-- vào cả 2 dòng lịch sử). Số thực tế do user xác nhận trực tiếp với xưởng.
--
-- DC4/TTI-MOT-02: 142 (ngày) + 1224 (đêm) = 1366 — khớp chính xác con số bị
-- trùng trước đó, xác nhận đúng là lỗi cộng dồn 1 lần thành 2.
-- DC8: Ca ngày chỉ chạy TTI-MOT-05 (2270), KHÔNG chạy FCC-KFM-01 — dòng
-- FCC-KFM-01 gắn nhầm vào Ca ngày (thực ra chỉ chạy Ca đêm, đã đúng sẵn ở đó)
-- bị xoá; DC8/TTI-MOT-05 thiếu hẳn cả 2 dòng, thêm mới.
-- ============================================================================

-- DC4 / TTI-MOT-02: 1366 (trùng) → 142 (ngày) / 1224 (đêm)
update duc_lich_su_san_xuat set tt_ca = 142, thoi_diem_ghi = now()
where ngay = '2026-08-26' and ca = 'Ca ngày' and ma_may = 'DC 4' and ma_sp = 'TTI-MOT-02';

update duc_lich_su_san_xuat set tt_ca = 1224, thoi_diem_ghi = now()
where ngay = '2026-08-26' and ca = 'Ca đêm' and ma_may = 'DC 4' and ma_sp = 'TTI-MOT-02';

-- DC4 / TTI-PUM-03: 0 → 150 (Ca ngày)
update duc_lich_su_san_xuat set tt_ca = 150, thoi_diem_ghi = now()
where ngay = '2026-08-26' and ca = 'Ca ngày' and ma_may = 'DC 4' and ma_sp = 'TTI-PUM-03';

-- DC8 / FCC-KFM-01: dòng Ca ngày gắn nhầm (thực tế không chạy SP này ở Ca ngày) — xoá.
-- Dòng Ca đêm (kh=2100, tt=2000) giữ nguyên — đúng với xác nhận của user.
delete from duc_lich_su_san_xuat
where ngay = '2026-08-26' and ca = 'Ca ngày' and ma_may = 'DC 8' and ma_sp = 'FCC-KFM-01';

-- DC8 / TTI-MOT-05: thiếu hẳn — thêm cả 2 ca (KH theo xác nhận của user: 2100/500)
insert into duc_lich_su_san_xuat (ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, kh_ca, tt_ca, so_luong_ng, thoi_diem_ghi)
select '2026-08-26', 'Ca ngày', '2 ca 12h', duc_iso_week('2026-08-26'), 'DC 8', 'TTI-MOT-05', coalesce(ten_sp, ''), 2100, 2270, 0, now()
from master_products where ma_sp = 'TTI-MOT-05'
on conflict (ngay, ca, ma_may, ma_sp) do update set kh_ca = excluded.kh_ca, tt_ca = excluded.tt_ca, thoi_diem_ghi = excluded.thoi_diem_ghi;

insert into duc_lich_su_san_xuat (ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, kh_ca, tt_ca, so_luong_ng, thoi_diem_ghi)
select '2026-08-26', 'Ca đêm', '2 ca 12h', duc_iso_week('2026-08-26'), 'DC 8', 'TTI-MOT-05', coalesce(ten_sp, ''), 500, 390, 0, now()
from master_products where ma_sp = 'TTI-MOT-05'
on conflict (ngay, ca, ma_may, ma_sp) do update set kh_ca = excluded.kh_ca, tt_ca = excluded.tt_ca, thoi_diem_ghi = excluded.thoi_diem_ghi;

-- ── Cập nhật lại tổng KH/TT ca trên báo cáo kết ca (bao-cao-ca.html) cho khớp
-- số vừa sửa. CHỈ recompute 2 số tổng đơn giản (sum trực tiếp) — KHÔNG đụng
-- oee_ca/availability_ca/performance_ca/quality_ca (tính từ downtime/cycle
-- time phức tạp hơn nhiều, rủi ro sai nếu tính lại thủ công ở đây) — 2 số đó
-- có thể vẫn chưa phản ánh đúng 100% sau khi sửa, chấp nhận hạn chế này.
update duc_bao_cao_ca b set
  tong_kh_ca = s.tong_kh, tong_tt_ca = s.tong_tt,
  ty_le_hoan_thanh_ca = case when s.tong_kh > 0 then s.tong_tt / s.tong_kh else 0 end,
  so_may_hoan_thanh_kh = s.so_hoan_thanh
from (
  select ca,
    sum(kh_ca) as tong_kh, sum(tt_ca) as tong_tt,
    count(*) filter (where tt_ca >= kh_ca) as so_hoan_thanh
  from duc_lich_su_san_xuat
  where ngay = '2026-08-26' and ca in ('Ca ngày', 'Ca đêm')
  group by ca
) s
where b.ngay = '2026-08-26' and b.ca = s.ca;
