-- T346c (25/11/2026): trừ phần máy Dập khỏi tổng các ca ĐÃ kết (duc_bao_cao_ca), chuyển sang cột *_dap.
-- quality_ca tính lại theo TT/NG mới; oee_ca đổi theo tỉ lệ quality (A, P giữ nguyên — không tính lại được).
-- Chạy lại an toàn: chỉ sửa ca chưa có số dập.
with d as (
  select ngay, ca,
         sum(kh_ca) kh, sum(tt_ca) tt, sum(so_luong_ng) ng,
         count(distinct ma_may) so_may,
         count(distinct ma_may) filter (where coalesce(tt_ca, 0) >= coalesce(kh_ca, 0)) so_dat
  from duc_lich_su_san_xuat where duc_la_may_dap(ma_may) group by ngay, ca
), n as (
  select b.id_bao_cao, d.*,
         greatest(0, b.tong_kh_ca - d.kh) kh_moi, greatest(0, b.tong_tt_ca - d.tt) tt_moi, greatest(0, b.tong_ng_ca - d.ng) ng_moi,
         b.quality_ca q_cu
  from duc_bao_cao_ca b join d on d.ngay = b.ngay and d.ca = b.ca
  where b.tong_kh_dap = 0 and b.tong_tt_dap = 0 and b.tong_ng_dap = 0
)
update duc_bao_cao_ca b set
  tong_kh_dap = n.kh, tong_tt_dap = n.tt, tong_ng_dap = n.ng,
  tong_kh_ca = n.kh_moi, tong_tt_ca = n.tt_moi, tong_ng_ca = n.ng_moi,
  ty_le_hoan_thanh_ca = case when n.kh_moi > 0 then n.tt_moi / n.kh_moi else 0 end,
  so_may_co_kh = greatest(0, b.so_may_co_kh - n.so_may),
  so_may_hoan_thanh_kh = greatest(0, b.so_may_hoan_thanh_kh - n.so_dat),
  quality_ca = case when n.tt_moi + n.ng_moi > 0 then n.tt_moi / (n.tt_moi + n.ng_moi) else 1.0 end,
  oee_ca = case when coalesce(n.q_cu, 0) > 0
                then b.oee_ca / n.q_cu * (case when n.tt_moi + n.ng_moi > 0 then n.tt_moi / (n.tt_moi + n.ng_moi) else 1.0 end)
                else b.oee_ca end
from n where n.id_bao_cao = b.id_bao_cao;
