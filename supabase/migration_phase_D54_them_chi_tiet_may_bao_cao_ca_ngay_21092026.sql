-- D54: bổ sung nối tiếp D53 — trang "Báo cáo Ca" (bao-cao-ca.html) lấy danh
-- sách "Sản lượng từng máy" từ duc_lich_su_san_xuat (snapshot chi tiết lúc
-- kết ca), KHÔNG phải từ các cột tổng ở duc_bao_cao_ca mà D53 đã sửa. Thêm
-- 5 dòng DC4-8 (dữ liệu thật của đúng Ca ngày 21/09, lấy từ dòng
-- 21092026_Cangay_DC{4..8}_... trong duc_ca_hien_tai trước khi bị đè bởi
-- Ca đêm 21/09) để bảng chi tiết khớp với số tổng đã gộp ở D53.
--
-- Chạy 1 lần trên Supabase project PRODUCTION.

insert into duc_lich_su_san_xuat (ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, kh_ca, tt_ca, so_luong_ng, thoi_diem_ghi)
values
  ('2026-09-21', 'Ca ngày', '2 ca 12h', 'W39_2026', 'DC 4', 'COS-GZ5-01', 'GZ54',      600,  572, 0, '2026-09-21T12:42:37+00:00'),
  ('2026-09-21', 'Ca ngày', '2 ca 12h', 'W39_2026', 'DC 5', 'AST-PAN-01', 'Panel FR',  1110, 440, 0, '2026-09-21T12:42:37+00:00'),
  ('2026-09-21', 'Ca ngày', '2 ca 12h', 'W39_2026', 'DC 6', 'EXE-OUT-01', 'CL OUTER',  1800, 1570, 0, '2026-09-21T12:42:37+00:00'),
  ('2026-09-21', 'Ca ngày', '2 ca 12h', 'W39_2026', 'DC 7', 'FCC-OUT-01', 'Outer K09', 2250, 2234, 0, '2026-09-21T12:42:37+00:00'),
  ('2026-09-21', 'Ca ngày', '2 ca 12h', 'W39_2026', 'DC 8', 'FCC-KFM-01', 'KFM',       4000, 3400, 0, '2026-09-21T12:42:37+00:00')
on conflict (ngay, ca, ma_may, ma_sp) do update set
  kh_ca = excluded.kh_ca, tt_ca = excluded.tt_ca, so_luong_ng = excluded.so_luong_ng;
