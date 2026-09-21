-- D55: dọn 2 báo cáo "ma" (phantom) trùng dữ liệu với 21092026_Cangay đã gộp
-- ở D53/D54, và bổ sung 13 sự cố thật của DC4/DC5/DC6/DC8 vào đúng Ca ngày
-- 21/09 + tính lại Availability/Performance cho khớp (OEE không đổi vì công
-- thức OEE = Ideal/PPT không phụ thuộc cách chia downtime).
--
-- BỐI CẢNH: khi đóng backlog trưa nay, 5 máy DC4-8 bị đóng 2 lần liên tiếp
-- chỉ cách nhau 3 phút (20092026_Cangay lúc 12:39, 20092026_Cadem lúc 12:42)
-- — không có sản lượng/thời gian thực nào phát sinh giữa 2 lần đó (cùng
-- TT ca = 8216 pcs). Đây thực chất là 1 lần catch-up bị tách thành 2 báo
-- cáo "ma", và toàn bộ sản lượng + 13 sự cố thật đó xảy ra trong khung giờ
-- 06:00-18:00 ngày 21/09 (giờ VN) — đúng là Ca ngày 21/09 mà D53/D54 đã gộp
-- vào 21092026_Cangay. Nếu để nguyên, báo cáo tuần/tháng cộng dồn sẽ đếm
-- trùng sản lượng DC4-8 tới 2-3 lần.
--
-- Chạy 1 lần trên Supabase project PRODUCTION.

begin;

-- 1) Chuyển 13 sự cố thật của DC4/DC5/DC6/DC8 (đang gắn nhầm ngày 20/09) về
--    đúng ngày 21/09 — ca vẫn là "Ca ngày" (khung giờ sự cố nằm trọn trong
--    06:00-18:00 21/09 giờ VN).
update duc_su_co_log
set ngay = '2026-09-21'
where ngay = '2026-09-20' and ca = 'Ca ngày' and ma_may in ('DC 4', 'DC 5', 'DC 6', 'DC 8');

-- 2) Xoá 2 báo cáo "ma" trùng dữ liệu (không đại diện ca thật nào).
delete from duc_bao_cao_ca where id_bao_cao in ('20092026_Cangay', '20092026_Cadem');

-- 3) Xoá dòng chi tiết máy gắn với 2 báo cáo "ma" đó (duc_lich_su_san_xuat
--    ngày 20/09, cả Ca ngày lẫn Ca đêm, của DC4-8 — bao gồm cả 1 dòng
--    EXE-CEN-01 trên DC6 chưa chạy, kh=2100/tt=0, không còn ý nghĩa báo cáo).
delete from duc_lich_su_san_xuat where ngay = '2026-09-20' and ma_may in ('DC 4', 'DC 5', 'DC 6', 'DC 7', 'DC 8');

-- 4) Cập nhật lại 21092026_Cangay: cộng 13 sự cố / 953 phút dừng của DC4-8,
--    tính lại Availability/Performance có tính downtime (trước đó D53 giả
--    định DC4-8 không có sự cố nào — sai, vì sự cố lúc đó đang gắn nhầm
--    ngày 20/09 nên không thấy). OEE giữ nguyên (= Ideal/PPT, không đổi khi
--    downtime dịch chuyển giữa các máy).
update duc_bao_cao_ca set
  so_su_co_ca       = 17,
  tong_phut_dung_ca = 1352,
  availability_ca   = 0.7529238032551144,
  performance_ca    = 0.9544425035238818,
  ghi_chu           = 'Gộp thủ công D53-D55: cộng thêm 5 máy DC4-8 (kẹt ở Ca ngày 20/09, đóng backlog trễ; đã dọn 2 báo cáo "ma" 20092026_Cangay/Cadem trùng dữ liệu + chuyển 13 sự cố về đúng ngày). OEE/Availability/Performance là ước lượng weighted theo sản lượng, không phải tính chính xác từng dòng.'
where id_bao_cao = '21092026_Cangay';

commit;
