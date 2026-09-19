-- ============================================================================
-- Phase T38 — Thêm công đoạn mới "Đánh bóng" (dây chuyền thủ công, người cuối
-- chuyền kiêm kiểm OQC tại chỗ và đóng thùng 60pcs, không qua trạm OQC riêng).
-- Theo đúng tiền lệ T21 (thêm "Cắt viền"): thay đổi chủ yếu ở tầng FRONTEND
-- (CONG_DOAN_LIST/BO_PHAN_LIST trong quan-ly-danh-muc.html, khsx-tuan.html,
-- cong-doan-bao-cao-ca.html, chuyencongdoan.html, cong-doan-dashboard.html,
-- quan-ly-tai-khoan.html, admin-create-user/index.ts — đã sửa trong commit
-- này) — không cần SQL vì cong_doan/quy_trinh_cong_doan là cột text tự do
-- KHÔNG có CHECK constraint ở hầu hết bảng liên quan.
--
-- CHỈ 2 nơi có CHECK constraint cứng danh sách công đoạn (từ T11/T13, đã mở
-- rộng ở T21 cho Cắt viền) — nếu không mở rộng thì gửi duyệt KHSX tuần cho
-- Đánh bóng / gán "Quản lý bộ phận" phụ trách Đánh bóng sẽ bị Postgres từ
-- chối:
--   1) khsx_duyet.cong_doan
--   2) user_roles.bo_phan_phu_trach (mảng text[])
--
-- Đồng thời khai báo quy trình công đoạn + quy cách đóng gói Đúc cho 3 mã SP
-- đầu tiên đi qua Đánh bóng (Đúc 150pcs/thùng → Đánh bóng gộp lại 60pcs/thùng,
-- định mức 60pcs khai trong chuyencongdoan.html CONFIG.PACKAGING, không phải
-- cột DB) — không qua Bavia/Gia Công/Sơn/OQC, không cần "Lọc hàng".
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

alter table khsx_duyet drop constraint if exists khsx_duyet_cong_doan_check;
alter table khsx_duyet add constraint khsx_duyet_cong_doan_check
  check (cong_doan in ('Đúc','Bavia','Gia Công','Cắt viền','Đánh bóng','Sơn','OQC'));

alter table public.user_roles drop constraint if exists user_roles_bo_phan_phu_trach_check;
alter table public.user_roles add constraint user_roles_bo_phan_phu_trach_check check (
  bo_phan_phu_trach is null or bo_phan_phu_trach <@ array['Đúc','Bavia','Gia Công','Cắt viền','Đánh bóng','Sơn','OQC']::text[]
);

update public.master_products
  set quy_trinh_cong_doan = 'Đúc,Đánh bóng,Nhập kho,Xuất hàng',
      sl_dong_goi_chuan = 150
  where ma_sp in ('EXE-SHO-01','EXE-SHO-02','EXE-SHO-03');
