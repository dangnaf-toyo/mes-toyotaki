-- ============================================================================
-- Phase T39 — Khai báo quy trình công đoạn "Đúc,Đánh bóng,Nhập kho,Xuất hàng"
-- cho BPH-SHO-01/02/03 (Kẽm 190T), cùng quy cách đóng gói như EXE-SHO-01/02/03
-- (T38): Đúc 150pcs/thùng → Đánh bóng gộp lại 60pcs/thùng (định mức 60 khai
-- trong chuyencongdoan.html CONFIG.PACKAGING, không phải cột DB, đã có sẵn từ
-- T38 — không cần sửa gì thêm ở tầng frontend cho phase này).
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

update public.master_products
  set quy_trinh_cong_doan = 'Đúc,Đánh bóng,Nhập kho,Xuất hàng',
      sl_dong_goi_chuan = 150
  where ma_sp in ('BPH-SHO-01','BPH-SHO-02','BPH-SHO-03');
