-- ============================================================================
-- Phase T21 — Thêm công đoạn mới "Cắt viền" (chạy trên máy gia công CNC, tại
-- bộ phận Gia Công, nhưng là 1 bước RIÊNG trong quy trình — SP có cả Cắt viền
-- và Gia Công sẽ đến bộ phận Gia Công 2 lần, ở 2 thời điểm khác nhau trong
-- luồng sản xuất, nên cần 2 nhãn công đoạn khác nhau để chuyencongdoan.html/
-- cong-doan-dashboard.html phân biệt đúng "đang ở lượt nào").
--
-- Việc thêm công đoạn này chủ yếu là thay đổi ở tầng FRONTEND (các mảng
-- CONG_DOAN_LIST/BO_PHAN_LIST trong quan-ly-danh-muc.html, khsx-tuan.html,
-- cong-doan-bao-cao-ca.html, chuyencongdoan.html, cong-doan-dashboard.html,
-- quan-ly-tai-khoan.html, index.html, chatluong-supabase.html — không cần
-- SQL vì cong_doan/quy_trinh_cong_doan là cột text tự do KHÔNG có CHECK
-- constraint ở hầu hết các bảng liên quan (cd_bao_cao_ca, cd_tram_hien_tai,
-- cd_khsx_tuan_plan, master_products.quy_trinh_cong_doan)).
--
-- CHỈ 2 nơi có CHECK constraint cứng danh sách 5 công đoạn cũ (migration
-- T11/T13) — nếu không mở rộng thì gửi duyệt KHSX tuần cho Cắt viền / gán
-- "Quản lý bộ phận" phụ trách Cắt viền sẽ bị Postgres từ chối:
--   1) khsx_duyet.cong_doan (T11)
--   2) user_roles.bo_phan_phu_trach (T13, mảng text[])
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

alter table khsx_duyet drop constraint if exists khsx_duyet_cong_doan_check;
alter table khsx_duyet add constraint khsx_duyet_cong_doan_check
  check (cong_doan in ('Đúc','Bavia','Gia Công','Cắt viền','Sơn','OQC'));

alter table public.user_roles drop constraint if exists user_roles_bo_phan_phu_trach_check;
alter table public.user_roles add constraint user_roles_bo_phan_phu_trach_check check (
  bo_phan_phu_trach is null or bo_phan_phu_trach <@ array['Đúc','Bavia','Gia Công','Cắt viền','Sơn','OQC']::text[]
);
