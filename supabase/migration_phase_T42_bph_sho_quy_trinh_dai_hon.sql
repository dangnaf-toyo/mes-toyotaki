-- ============================================================================
-- Phase T42 — BPH-SHO-01/02/03 đổi quy trình dài hơn EXE-SHO: Đúc → Đánh bóng
-- → Gia Công → OQC → Nhập kho → Xuất hàng (EXE-SHO KHÔNG đổi, vẫn Đúc→Đánh
-- bóng→Nhập kho→Xuất hàng như T38/T39).
--
-- Từ Đúc tới TRƯỚC OQC vẫn đóng thùng nhựa 150pcs/thùng (chuyển công đoạn
-- bình thường qua Đánh bóng rồi Gia Công, KHÔNG đóng gói lại/không dùng Tem
-- Thành Phẩm ở 2 bước này nữa cho riêng nhóm mã này) — chỉ tới OQC mới gộp
-- lại về 60pcs/thùng qua Tem Thành Phẩm (in trước + quét ghi nhận tự FIFO
-- trừ nguồn, giống hệt cơ chế đã làm cho Đánh bóng ở T40/T41, dùng LẠI toàn
-- bộ RPC cũ — không cần SQL mới cho phần này, chỉ cần đổi quy_trinh_cong_doan
-- + intem.html/ghi-nhan-tem-thanh-pham.html thêm "OQC" vào danh sách công
-- đoạn có Tem Thành Phẩm, đã sửa trong cùng commit).
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

update public.master_products
  set quy_trinh_cong_doan = 'Đúc,Đánh bóng,Gia Công,OQC,Nhập kho,Xuất hàng'
  where ma_sp in ('BPH-SHO-01','BPH-SHO-02','BPH-SHO-03');
