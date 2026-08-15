-- ============================================================================
-- Dọn dẹp dữ liệu test — 7 dòng "mồ côi" trong duc_ca_hien_tai (2026-08-15).
--
-- Đây là các dòng thuộc ngày/ca CŨ (trước hôm nay) nhưng CHƯA từng được
-- trưởng ca "Kết ca" (không có bản ghi tương ứng trong duc_bao_cao_ca) — nên
-- sau khi đổi logic "máy đang chạy" sang đúng tín hiệu Kết ca
-- (migration_phase_D8), các dòng này vẫn bị coi là "đang hoạt động" dù thực
-- chất là dữ liệu test bỏ dở, không có sản lượng thực tế nào (tt_ca = 0).
--
-- Mỗi dòng dưới đây đã được kiểm tra trước khi xoá: tt_ca = 0 (không có sản
-- lượng thực), không có sự cố đang mở, ngày < hôm nay (15/08/2026) — an toàn
-- xoá theo đúng quy tắc mà duc_delete_plan() cũng dùng (chặn xoá nếu đã có
-- sản lượng thực tế).
--
-- KHÔNG đụng đến DC 6 (dòng 15082026_Ca1_DC6_AST-PAN-01) — đây là dòng đang
-- test thật hôm nay, chưa kết ca nhưng vẫn cần giữ lại.
--
-- Chạy trong Supabase SQL Editor. Chỉ chạy 1 lần (các dòng này sẽ không còn
-- sau khi xoá — chạy lại lần 2 sẽ không xoá được gì thêm, vẫn an toàn).
-- ============================================================================

delete from duc_ca_hien_tai
where id_dong in (
  '13082026_Ca2_DC10_OKA-GJT-04',
  '13082026_Ca2_DC11_FCC-KPH-01',
  '14082026_Cangay_DC3_AST-PAN-01',
  '13082026_Ca2_DC4_TTI-PUM-02',
  '13082026_Ca2_DC5_AST-PAN-01',
  '13082026_Ca2_DC7_FCC-OUT-01',
  '13082026_Ca2_DC8_FCC-KFM-01'
)
and coalesce(tt_ca, 0) = 0
and open_gio_phat_sinh is null;
