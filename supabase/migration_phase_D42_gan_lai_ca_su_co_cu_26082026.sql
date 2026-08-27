-- ============================================================================
-- D42 — Gán lại đúng ca cho 6 sự cố còn mang nhãn ca cũ "Ca 1"/"Ca 2" (thuộc
-- phương án "2 ca 8h" đã bỏ) ngày 26/08 — DC 11/EXE-PLY-01 (5 sự cố) và
-- DC 6/EXE-OUT-01 (1 sự cố). Giờ phát sinh thực tế của cả 6 đều rơi trong
-- khung 06:00-18:00 giờ VN 26/08 → đúng ra phải là "Ca ngày", không phải
-- "Ca 1"/"Ca 2". Vì 2 nhãn ca cũ này không khớp bất kỳ báo cáo kết ca nào
-- (chỉ có 26082026_Cangay/26082026_Cadem), 1.448 phút dừng của 6 sự cố này
-- trước đó hoàn toàn không được cộng vào báo cáo tuần.
-- ============================================================================

update duc_su_co_log set ca = 'Ca ngày'
where id_ban_ghi in (
  '26082026_Ca1_DC11_EXE-PLY-01_1', '26082026_Ca1_DC11_EXE-PLY-01_2', '26082026_Ca1_DC11_EXE-PLY-01_3',
  '26082026_Ca2_DC11_EXE-PLY-01_1', '26082026_Ca2_DC11_EXE-PLY-01_2',
  '26082026_Ca1_DC6_EXE-OUT-01_3'
);

-- Cộng bù 6 sự cố (1.448 phút) vào báo cáo Ca ngày 26/08 đã kết ca trước đó.
update duc_bao_cao_ca set
  so_su_co_ca = so_su_co_ca + 6,
  tong_phut_dung_ca = tong_phut_dung_ca + 1448
where id_bao_cao = '26082026_Cangay';

-- LƯU Ý CÒN LẠI (không xử lý tự động trong migration này): DC 11/EXE-PLY-01
-- không có dòng sản lượng (kh_ca/tt_ca) nào trong duc_lich_su_san_xuat ngày
-- 26/08 — máy này có vẻ chạy suốt từ "Ca 1"/"Ca 2" cũ sang thẳng ngày 27/08
-- (dòng hiện tại id_dong=27082026_Cangay_DC11_EXE-PLY-01, tt_tuan=4392) mà
-- CHƯA TỪNG được "Kết ca" cho giai đoạn Ca 1/Ca 2 hoặc Ca ngày 26/08 — sản
-- lượng thực tế của DC11 trong khoảng đó (nếu có) không lấy được từ DB,
-- không tự suy đoán số. Nếu user có số liệu thực tế (giống DC4/DC8 ở D41),
-- báo lại để bổ sung dòng duc_lich_su_san_xuat cho DC11/EXE-PLY-01 ngày
-- 26/08.
