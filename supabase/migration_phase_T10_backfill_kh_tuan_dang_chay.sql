-- ============================================================================
-- Phase T10 — Nạp bù "KH tuần" cho các máy Đúc ĐANG CHẠY, lấy từ KHSX tuần
-- (duc_khsx_tuan_plan), cho những dòng bị thiếu vì bug applyWeeklyPlanSuggestion_
-- (đã sửa ở commit 57760f1) — trước đó bấm "+" gán kế hoạch từ gợi ý KHSX tuần
-- chỉ điền KH ca, quên điền KH tuần, nên các máy gán kế hoạch qua đường này
-- trước bản sửa đang có kh_tuan = 0/rỗng dù KHSX tuần đã có số liệu.
--
-- duc_ca_hien_tai chỉ chứa dòng CÒN ĐANG CHẠY (dòng cũ bị xoá khi Kết ca —
-- xem submitEndShift() trong duc-dashboard.html), nên không cần lọc thêm gì
-- khác ngoài khớp đúng (máy, mã SP, tuần chứa ngày của dòng đó).
--
-- AN TOÀN: chỉ điền vào dòng đang kh_tuan = 0 hoặc rỗng — KHÔNG ghi đè dòng
-- nào trưởng ca đã tự sửa KH tuần tay khác 0. Chạy lại nhiều lần vô hại (dòng
-- đã được điền sẽ không còn kh_tuan = 0 nên tự bỏ qua ở lần chạy sau).
-- ============================================================================

update duc_ca_hien_tai cht
set kh_tuan = kp.kh_tuan
from duc_khsx_tuan_plan kp
where cht.ma_may = kp.ma_may
  and cht.ma_sp = kp.ma_sp
  and cht.ma_sp <> ''
  and kp.tuan_bat_dau = (cht.ngay - (extract(isodow from cht.ngay)::int - 1) * interval '1 day')::date
  and coalesce(cht.kh_tuan, 0) = 0
  and coalesce(kp.kh_tuan, 0) > 0;

-- Xem lại kết quả (không bắt buộc chạy, chỉ để kiểm tra):
-- select ma_may, ma_sp, ngay, ca, kh_ca, kh_tuan from duc_ca_hien_tai order by ma_may;
