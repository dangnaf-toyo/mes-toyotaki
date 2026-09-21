-- T56: sửa 3 nhân sự bị gán nhầm bo_phan "Gia công - Sơn" (do datalist thiếu
-- "Đánh bóng Kẽm" khi thêm nhân sự) → phải là "Đánh bóng Kẽm" mới lọc đúng
-- trong ô "Người kiểm tra" (ghi-nhan-tem-thanh-pham.html) và line_may (Line 1).
-- Chỉ chạy 1 lần trên project PRODUCTION (dữ liệu nhân sự thật).

update master_employees
set bo_phan = 'Đánh bóng Kẽm'
where ten_nhan_vien in ('Nghiêm Thị Thu Giang', 'Nguyễn Thị Ngân', 'Sầm Văn Chinh')
  and bo_phan = 'Gia công - Sơn';
