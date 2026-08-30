-- =============================================================================
-- D53 — Danh mục Máy-Line (quan-ly-danh-muc.html, tab "Máy-Line")
--
--   Trước đây danh mục máy chỉ phục vụ khối Đúc (máy đúc + máy dập). Thêm cột
--   bo_phan để khai báo mỗi máy/line thuộc bộ phận nào; các bộ phận dùng:
--   Đúc, Bavia, Gia công - Sơn, OQC (ô tự do, chưa ràng buộc cứng).
--
--   Toàn bộ máy hiện có -> bộ phận "Đúc".
-- =============================================================================

alter table public.master_machines
  add column if not exists bo_phan text;

update public.master_machines
  set bo_phan = 'Đúc'
  where bo_phan is null or btrim(bo_phan) = '';

-- Kiểm tra nhanh
-- select ma_may, bo_phan, kanban from public.master_machines order by bo_phan, ma_may;
