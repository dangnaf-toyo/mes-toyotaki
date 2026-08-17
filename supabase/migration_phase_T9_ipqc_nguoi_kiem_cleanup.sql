-- ============================================================================
-- Phase T9 — Dọn dữ liệu "Người kiểm" IPQC cũ:
--   1) Xoá các bản ghi duc_ipqc_checkpoint do tài khoản dangnaf@gmail.com tạo
--      (dùng để test logic hệ thống, không phải dữ liệu thật).
--   2) Chuẩn hoá các bản ghi CÒN LẠI đang lưu "Người kiểm" = email đăng nhập
--      sang dạng "MãNV_TênNV" (username_full_name) — cùng định dạng mà
--      ipqc.html:getNguoiKiemIdentity() dùng cho các lượt kiểm mới từ
--      migration_phase_T9 trở đi (xem ipqc.html, hàm submitCheck()).
--
-- Chạy 1 lần trên Supabase SQL Editor. Thứ tự bên trong file này CỐ Ý:
-- xoá dữ liệu test TRƯỚC khi backfill, vì backfill sẽ đổi luôn giá trị email
-- thành username_full_name — nếu đảo ngược thứ tự sẽ mất chuỗi 'dangnaf@
-- gmail.com' để tìm đúng các dòng cần xoá.
-- ============================================================================

-- 1) Xoá bản ghi test của dangnaf@gmail.com --------------------------------
-- Gỡ liên kết trước (nếu có) từ duc_ncp.id_checkpoint_goc trỏ tới các
-- checkpoint sắp xoá, tránh vi phạm khoá ngoại (duc_ncp.id_checkpoint_goc
-- references duc_ipqc_checkpoint.id_checkpoint, không có on delete cascade).
update duc_ncp set id_checkpoint_goc = null
where id_checkpoint_goc in (
  select id_checkpoint from duc_ipqc_checkpoint where nguoi_kiem = 'dangnaf@gmail.com'
);

delete from duc_ipqc_checkpoint where nguoi_kiem = 'dangnaf@gmail.com';

-- 2) Chuẩn hoá các bản ghi cũ còn lại ---------------------------------------
-- Chỉ đổi dòng đang lưu dạng email (còn ký tự '@') — dòng đã ở định dạng mới
-- (không có '@') thì bỏ qua, script chạy lại nhiều lần vẫn an toàn.
update duc_ipqc_checkpoint cp
set nguoi_kiem = case
  when ur.username is not null and ur.username <> '' and ur.full_name is not null and ur.full_name <> ''
    then ur.username || '_' || ur.full_name
  when ur.username is not null and ur.username <> '' then ur.username
  when ur.full_name is not null and ur.full_name <> '' then ur.full_name
  else cp.nguoi_kiem
end
from user_roles ur
where ur.email = cp.nguoi_kiem
  and cp.nguoi_kiem like '%@%';
