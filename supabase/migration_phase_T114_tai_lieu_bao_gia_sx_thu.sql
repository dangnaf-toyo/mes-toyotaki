-- ============================================================================
-- T114 — Tài liệu kỹ thuật: thêm 2 loại "Dữ liệu tính toán báo giá"
-- (du_lieu_bao_gia) và "Kết quả sản xuất thử" (ket_qua_sx_thu), đứng ngay sau
-- "Bản vẽ sản phẩm"; các loại kỹ thuật còn lại lùi thứ tự.
-- Chưa có document_permissions cho 2 loại mới (admin cấp ở Cấu hình tài liệu).
-- An toàn chạy lại nhiều lần.
-- ============================================================================

insert into doc_categories (ma, ten, thu_tu, cap) values
  ('du_lieu_bao_gia', 'Dữ liệu tính toán báo giá', 2, 'ky_thuat'),
  ('ket_qua_sx_thu',  'Kết quả sản xuất thử',      3, 'ky_thuat')
on conflict (ma) do update set ten = excluded.ten, cap = excluded.cap;

update doc_categories d set thu_tu = v.thu_tu
from (values
  ('ban_ve_sp', 1), ('du_lieu_bao_gia', 2), ('ket_qua_sx_thu', 3),
  ('ban_ve_khuon', 4), ('ban_ve_jig', 5), ('ban_ve_lk_khuon', 6),
  ('duong_kiem', 7), ('qcp', 8), ('tc_kiem_tra', 9), ('tc_thao_tac', 10)
) v(ma, thu_tu)
where d.ma = v.ma;
