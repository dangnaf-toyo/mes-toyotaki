-- ============================================================================
-- D38 — Dọn dẹp các dòng "chưa kết ca" tồn đọng lâu ngày trong duc_ca_hien_tai
-- (bảng STATE, không phải lịch sử — xem ghi chú đầu file schema_duc.sql).
--
-- Phát hiện qua banner cảnh báo mới thêm ở duc-dashboard.html (xem
-- renderOpsWarnings()): quét toàn bảng thấy 62 dòng, nhưng chỉ 8 dòng (mới
-- nhất mỗi máy, ngày 26/08/2026) là đang thực sự chạy — 54 dòng còn lại là
-- rác tồn từ 29/07/2026 đến 24/08/2026, đã bị các ca sau đè lên (row_seq
-- cao hơn) từ lâu mà chưa bao giờ được dọn qua "Kết ca" — cùng loại lỗi đã
-- xử lý riêng lẻ cho DC 6 ở migration_phase_D14_cleanup_stuck_dc6, nay dọn
-- chung một lần cho mọi máy.
--
-- Đã hỏi và chốt với người dùng: XOÁ toàn bộ 54 dòng thừa, chỉ giữ lại đúng
-- 1 dòng có row_seq lớn nhất của mỗi máy.
--
-- KHÔNG đụng tới dữ liệu thật: sản lượng (duc_tem), sự cố (duc_su_co_log),
-- lịch sử sản xuất (duc_lich_su_san_xuat), báo cáo ca (duc_bao_cao_ca) —
-- những dòng chưa từng kết ca thì các tuần đó vốn dĩ ĐÃ THIẾU dữ liệu tổng
-- kết ca trong báo cáo tuần (không phải do migration này gây ra, và không
-- có cách khôi phục lại số KH ca đã mất vì chưa từng được kết ca).
--
-- Không có FK nào tham chiếu duc_ca_hien_tai(id_dong) nên xoá an toàn,
-- không cần dọn bảng khác. An toàn chạy lại nhiều lần (idempotent — sau khi
-- chạy lần đầu mỗi máy chỉ còn 1 dòng, chạy lại không xoá thêm gì).
-- ============================================================================

delete from duc_ca_hien_tai t
where exists (
  select 1 from duc_ca_hien_tai t2
  where t2.ma_may = t.ma_may and t2.row_seq > t.row_seq
);
