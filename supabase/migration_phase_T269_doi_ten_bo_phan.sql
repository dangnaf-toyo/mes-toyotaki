-- T269: Danh sách bộ phận (cv_bo_phan — dùng ở Giao việc và Kho NVL xuất kho)
-- Bỏ "Ban giám đốc" (việc đang gắn chuyển sang "Phát triển sản phẩm"),
-- gộp "Gia công CNC" + "Sơn" → "Gia công – Sơn", "Bavia" → "Bavia – Đánh bóng",
-- "Kế hoạch" → "QLSX", "Bảo trì" → "Thiết bị", "Kỹ thuật" → "Phát triển sản phẩm".
-- cv_du_an / cv_cong_viec có FK ON UPDATE CASCADE; nvl_giao_dich.bo_phan_nhan không FK → cập nhật tay.
begin;

-- Đổi tên (FK tự cascade)
update cv_bo_phan set ten = 'Phát triển sản phẩm' where ten = 'Kỹ thuật';
update cv_bo_phan set ten = 'QLSX'                where ten = 'Kế hoạch';
update cv_bo_phan set ten = 'Thiết bị'            where ten = 'Bảo trì';
update cv_bo_phan set ten = 'Bavia – Đánh bóng'   where ten = 'Bavia';
update cv_bo_phan set ten = 'Gia công – Sơn'      where ten = 'Gia công CNC';
update nvl_giao_dich set bo_phan_nhan = 'Phát triển sản phẩm' where bo_phan_nhan = 'Kỹ thuật';
update nvl_giao_dich set bo_phan_nhan = 'QLSX'                where bo_phan_nhan = 'Kế hoạch';
update nvl_giao_dich set bo_phan_nhan = 'Thiết bị'            where bo_phan_nhan = 'Bảo trì';
update nvl_giao_dich set bo_phan_nhan = 'Bavia – Đánh bóng'   where bo_phan_nhan = 'Bavia';
update nvl_giao_dich set bo_phan_nhan = 'Gia công – Sơn'      where bo_phan_nhan in ('Gia công CNC', 'Sơn');

-- Gộp Sơn vào Gia công – Sơn
update cv_du_an     set bo_phan = 'Gia công – Sơn' where bo_phan = 'Sơn';
update cv_cong_viec set bo_phan = 'Gia công – Sơn' where bo_phan = 'Sơn';
delete from cv_bo_phan where ten = 'Sơn';

-- Bỏ Ban giám đốc: việc/dự án chuyển sang Phát triển sản phẩm
update cv_du_an     set bo_phan = 'Phát triển sản phẩm' where bo_phan = 'Ban giám đốc';
update cv_cong_viec set bo_phan = 'Phát triển sản phẩm' where bo_phan = 'Ban giám đốc';
update nvl_giao_dich set bo_phan_nhan = 'Phát triển sản phẩm' where bo_phan_nhan = 'Ban giám đốc';
delete from cv_bo_phan where ten = 'Ban giám đốc';

-- Thứ tự hiển thị
update cv_bo_phan set thu_tu = v.n from (values
  ('Đúc', 1), ('Bavia – Đánh bóng', 2), ('Gia công – Sơn', 3), ('Chất lượng (QC)', 4),
  ('Kho', 5), ('QLSX', 6), ('Thiết bị', 7), ('Phát triển sản phẩm', 8),
  ('Hành chính – Nhân sự', 9), ('Kinh doanh', 10), ('Mua hàng', 11)
) v(t, n) where cv_bo_phan.ten = v.t;

commit;
