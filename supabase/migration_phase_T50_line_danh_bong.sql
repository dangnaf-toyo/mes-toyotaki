-- ============================================================================
-- Phase T50 — "Line 1"/"Line 2" cho công đoạn Đánh bóng, theo đúng mô hình
-- "Line Mode" đã có sẵn cho Bavia (cong-doan-dashboard.html, CD_TO_BO_PHAN):
-- danh mục cố định trong master_machines (bo_phan='Đánh bóng') thay vì trạm
-- tự do gõ tên tay mỗi ca. Hiện tại chỉ chạy Line 1 (sản lượng chưa cần Line
-- 2) — Line 2 vẫn khai báo sẵn trong danh mục để bật dùng ngay khi cần,
-- không phải sửa lại danh mục lúc đó.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

insert into master_machines (ma_may, bo_phan, kanban) values
  ('Line 1', 'Đánh bóng', false),
  ('Line 2', 'Đánh bóng', false)
on conflict (ma_may) do update set bo_phan = excluded.bo_phan;
