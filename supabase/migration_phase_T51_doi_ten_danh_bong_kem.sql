-- ============================================================================
-- Phase T51 — Đổi tên công đoạn "Đánh bóng" → "Đánh bóng Kẽm" (tên đầy đủ,
-- phân biệt rõ hơn với các công đoạn khác). Đổi TOÀN BỘ — cả dữ liệu lịch sử
-- lẫn dữ liệu hiện hành — để báo cáo/thống kê không bị chẻ làm 2 tên khác
-- nhau cho cùng 1 công đoạn.
--
-- 2 nơi có CHECK constraint cứng danh sách công đoạn (từ T11/T13/T21/T38) —
-- PHẢI sửa constraint TRƯỚC khi update dữ liệu, không thì update sẽ bị chặn:
--   1) khsx_duyet.cong_doan
--   2) user_roles.bo_phan_phu_trach (mảng text[])
-- Các bảng còn lại (cong_doan/tram_cong_doan/bo_phan) là cột text tự do,
-- không có CHECK constraint.
--
-- KHÔNG đổi slug vai trò đăng nhập 'nhan_vien_danh_bong' (user_roles.role) —
-- đó là mã nội bộ, chỉ nhãn hiển thị đổi ở tầng frontend (quan-ly-tai-khoan.html).
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent) —
-- các UPDATE dùng WHERE = 'Đánh bóng' nên chạy lại lần 2 sẽ không còn gì để
-- đổi (đã đổi hết ở lần 1).
-- ============================================================================

-- ── 1) Mở rộng 2 CHECK constraint để chấp nhận tên mới ─────────────────────
alter table khsx_duyet drop constraint if exists khsx_duyet_cong_doan_check;
alter table khsx_duyet add constraint khsx_duyet_cong_doan_check
  check (cong_doan in ('Đúc','Bavia','Gia Công','Cắt viền','Đánh bóng Kẽm','Sơn','OQC'));

alter table public.user_roles drop constraint if exists user_roles_bo_phan_phu_trach_check;
alter table public.user_roles add constraint user_roles_bo_phan_phu_trach_check check (
  bo_phan_phu_trach is null or bo_phan_phu_trach <@ array['Đúc','Bavia','Gia Công','Cắt viền','Đánh bóng Kẽm','Sơn','OQC']::text[]
);

-- ── 2) Đổi dữ liệu ở mọi bảng có lưu tên công đoạn "Đánh bóng" ─────────────
update khsx_duyet set cong_doan = 'Đánh bóng Kẽm' where cong_doan = 'Đánh bóng';
update khsx_thay_doi_log set cong_doan = 'Đánh bóng Kẽm' where cong_doan = 'Đánh bóng';

update user_roles set bo_phan_phu_trach = array_replace(bo_phan_phu_trach, 'Đánh bóng', 'Đánh bóng Kẽm')
  where bo_phan_phu_trach is not null and 'Đánh bóng' = any(bo_phan_phu_trach);

-- quy_trinh_cong_doan là chuỗi nối bằng dấu phẩy (VD 'Đúc,Đánh bóng,Nhập kho')
-- — REPLACE an toàn vì không công đoạn nào khác chứa chuỗi con "Đánh bóng".
update master_products set quy_trinh_cong_doan = replace(quy_trinh_cong_doan, 'Đánh bóng', 'Đánh bóng Kẽm')
  where quy_trinh_cong_doan like '%Đánh bóng%';

update master_employees set bo_phan = 'Đánh bóng Kẽm' where bo_phan = 'Đánh bóng';
update master_machines set bo_phan = 'Đánh bóng Kẽm' where bo_phan = 'Đánh bóng';

update cd_tram_hien_tai set cong_doan = 'Đánh bóng Kẽm' where cong_doan = 'Đánh bóng';
update cd_bao_cao_ca set cong_doan = 'Đánh bóng Kẽm' where cong_doan = 'Đánh bóng';
update cd_khsx_tuan_plan set cong_doan = 'Đánh bóng Kẽm' where cong_doan = 'Đánh bóng';
update cd_ng_khai_bao set cong_doan = 'Đánh bóng Kẽm' where cong_doan = 'Đánh bóng';

update cd_chuyen_cong_doan_log set cong_doan_giao = 'Đánh bóng Kẽm' where cong_doan_giao = 'Đánh bóng';
update cd_chuyen_cong_doan_log set cong_doan_nhan = 'Đánh bóng Kẽm' where cong_doan_nhan = 'Đánh bóng';

update duc_tem set tram_cong_doan = 'Đánh bóng Kẽm' where tram_cong_doan = 'Đánh bóng';
