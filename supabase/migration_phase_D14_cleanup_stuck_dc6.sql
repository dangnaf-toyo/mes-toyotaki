-- ============================================================================
-- Dọn dẹp 1 lần — đóng 2 sự cố cũ bị bỏ quên trên DC6 (ca 13/08, Ca 2), chưa
-- bao giờ được đóng lẫn "Kết ca". Vì dòng mới nhất (row_seq lớn nhất) của
-- DC6 vẫn còn sự cố mở, hệ thống coi DC6 là "còn hoạt động" mãi mãi — khiến
-- thanh "Máy đang chạy" trên Dashboard Đúc hiện sai (0/1) và IPQC vẫn xếp
-- DC6 vào hàng đợi kiểm tra dù không còn máy nào chạy thật.
--
-- Đây là dữ liệu bỏ sót (không phải downtime thật cần báo cáo), nên đóng với
-- giờ trở lại = đúng giờ phát sinh (0 phút dừng) để không làm sai lệch số
-- liệu Pareto sự cố. Ghi chú rõ trong noi_dung_xu_ly để phân biệt với sự cố
-- thật khi tra cứu lịch sử sau này.
--
-- Chạy 1 LẦN trong Supabase SQL Editor (không cần chạy lại).
-- ============================================================================

select duc_resolve_incident(
  '13082026_Ca2_DC6_EXE-OUT-01',
  '2026-08-13T09:40:00+00:00'::timestamptz,
  '[Dọn dẹp hệ thống] Sự cố bị bỏ sót, không đóng khi kết thúc ca — đóng bù, không tính thời gian dừng.',
  'system-cleanup',
  'system-cleanup'
);

select duc_resolve_incident(
  '13082026_Ca2_DC6_EXE-CEN-01',
  '2026-08-13T08:48:11+00:00'::timestamptz,
  '[Dọn dẹp hệ thống] Sự cố bị bỏ sót, không đóng khi kết thúc ca — đóng bù, không tính thời gian dừng.',
  'system-cleanup',
  'system-cleanup'
);

-- Đánh dấu ca 13/08 - Ca 2 đã "kết thúc" để mọi dòng còn sót lại của ca này
-- (không chỉ DC6) không còn bị tính là "đang hoạt động" nữa. An toàn nếu đã
-- có sẵn (on conflict do nothing).
insert into duc_bao_cao_ca (id_bao_cao, ngay, ca, thoi_diem_ket_ca, ghi_chu)
values ('13082026_Ca2', '2026-08-13', 'Ca 2', now(), '[Dọn dẹp hệ thống] Kết ca bù — ca này không được kết ca đúng lúc, dữ liệu tổng hợp (KH/TT/OEE...) không đầy đủ.')
on conflict (id_bao_cao) do nothing;
