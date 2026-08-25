-- ============================================================================
-- D34 — Thêm "Ma Thị Thảo" vào master_employees.
--
-- Lý do: tên gõ tay vào duc_ca_hien_tai.nv_ca_ngay/nv_ca_dem là text tự do,
-- không đồng bộ vào master_employees (ensurePersonnelInMaster_ đã bị bỏ chủ
-- đích khi migrate — xem ghi chú đầu file duc-dashboard.html). Ô "Người thao
-- tác" trên intem.html là <select> chỉ lấy từ master_employees, nên tên
-- không có trong master sẽ không tự điền được khi bấm nút 🖨 từ dashboard
-- (gán .value cho <select> không khớp option nào → âm thầm để trống).
-- ============================================================================

insert into master_employees (ten_nhan_vien, vai_tro)
values ('Ma Thị Thảo', 'nhan_vien')
on conflict (ten_nhan_vien) do nothing;
