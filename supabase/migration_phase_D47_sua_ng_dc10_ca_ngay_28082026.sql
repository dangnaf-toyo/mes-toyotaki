-- ============================================================================
-- D47 — DC 10 / OKA-GMN-01, Ca ngày 28/08/2026: sửa số NG.
--
-- Sau D46 + kết ca, dòng lịch sử ghi so_luong_ng = 151 (nhiều hơn cả 126 pcs
-- OK). User xác nhận thực tế chỉ có **5 pcs NG** (phân loại "5D"). 151 là số
-- rác nằm sẵn trên dòng duc_ca_hien_tai (tạo tay, gắn nhầm ca — xem D46) và
-- bị duc_end_shift chốt vào lịch sử.
--
-- Phân loại NG ("5D") KHÔNG lưu được ở đâu trong lịch sử ca — duc_lich_su_san_xuat
-- và duc_bao_cao_ca đều không có cột phan_loai_ng (chỉ duc_ca_hien_tai có, mà
-- dòng đó đã bị xoá khi kết ca). Đây là giới hạn sẵn có, không sửa ở migration
-- này — chỉ sửa SỐ LƯỢNG.
--
-- Sửa:
--   1. duc_lich_su_san_xuat: so_luong_ng 151 -> 5 (dòng DC 10 Ca ngày 28/08).
--   2. duc_bao_cao_ca (28082026_Cangay): đồng bộ lại tong_ng_ca = tổng
--      so_luong_ng các dòng lịch sử cùng ca (đúng cách duc_end_shift tính),
--      và tính lại quality_ca / oee_ca theo tong_ng_ca mới (availability_ca,
--      performance_ca không phụ thuộc NG nên giữ nguyên).
--
-- An toàn chạy lại nhiều lần (idempotent — dùng giá trị tuyệt đối, không cộng/trừ).
-- ============================================================================

update duc_lich_su_san_xuat
set so_luong_ng = 5
where ngay = '2026-08-28' and ca = 'Ca ngày'
  and ma_may = 'DC 10' and ma_sp = 'OKA-GMN-01'
  and so_luong_ng is distinct from 5;

update duc_bao_cao_ca b
set tong_ng_ca = s.sum_ng,
    quality_ca = case when (coalesce(b.tong_tt_ca, 0) + s.sum_ng) > 0
                      then coalesce(b.tong_tt_ca, 0) / (coalesce(b.tong_tt_ca, 0) + s.sum_ng)
                      else 1.0 end,
    oee_ca = coalesce(b.availability_ca, 0) * coalesce(b.performance_ca, 0) *
             (case when (coalesce(b.tong_tt_ca, 0) + s.sum_ng) > 0
                   then coalesce(b.tong_tt_ca, 0) / (coalesce(b.tong_tt_ca, 0) + s.sum_ng)
                   else 1.0 end)
from (
  select coalesce(sum(coalesce(so_luong_ng, 0)), 0) as sum_ng
  from duc_lich_su_san_xuat
  where ngay = '2026-08-28' and ca = 'Ca ngày'
) s
where b.id_bao_cao = '28082026_Cangay';

-- ── Kiểm tra ─────────────────────────────────────────────────────────────
select 'lich_su' as bang, ma_may, ma_sp, kh_ca, tt_ca, so_luong_ng
from duc_lich_su_san_xuat
where ngay = '2026-08-28' and ca = 'Ca ngày' and ma_may in ('DC 10','Kẽm 190T')
union all
select 'bao_cao_ca', id_bao_cao, null, tong_kh_ca, tong_tt_ca, tong_ng_ca
from duc_bao_cao_ca where id_bao_cao = '28082026_Cangay';
