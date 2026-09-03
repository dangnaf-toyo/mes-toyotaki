-- ============================================================================
-- Phase T32 — Bỏ RPC duc_tem_sua_ngay_gio_ghi_nhan (tạo ở T31).
--
-- T31 thêm RPC này để sửa "Ngày giờ SX thực tế" bằng nút ✎ từng dòng trên
-- tra-cuu-tem.html. Theo yêu cầu, việc sửa được chuyển vào form "Chi tiết"
-- (intem.html, tab Tra cứu Tem) — form đó vốn đã update thẳng bảng duc_tem
-- qua policy "duc_tem authenticated update" (migration_phase4_step11_intem_write),
-- chỉ cần thêm cột ngay_gio_ghi_nhan vào patch. RPC T31 không còn nơi gọi.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

drop function if exists duc_tem_sua_ngay_gio_ghi_nhan(text, timestamptz);
