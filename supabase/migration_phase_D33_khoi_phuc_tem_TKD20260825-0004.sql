-- ============================================================================
-- D33 — Khôi phục tem TKD20260825-0004 bị xóa nhầm qua intem.html.
--
-- Tem gốc (đọc từ QR user cung cấp), in lúc 05:30 ngày 25/08/2026 (thuộc
-- khung Ca đêm 18h-06h, KHÔNG phải Ca ngày):
--   Tag No      : TKD20260825-0004
--   Tên SP      : Panel FR
--   Mã SP       : AST-PAN-01
--   Số lượng    : 384
--   Ngày        : 2026-08-25
--   Lô          : 2026-08-24
--   Số khuôn    : PAN #FR25
--   Nguyên liệu : HD2-HDT
--   Máy đúc     : DC 5
--
-- Insert thẳng lại đúng ngay_gio_in = 05:30 25/08/2026 (giờ VN) — KHÔNG dùng
-- now() — để tem tính đúng vào Ca đêm, không lệch sang Ca ngày như nếu nhập
-- lại qua giao diện intem.html (giao diện luôn lấy giờ hiện tại lúc bấm).
--
-- Chưa biết người thao tác (nguoi_tt) lúc in — để NULL, sửa lại bằng tay
-- trong duc_tem nếu nhớ ra sau (không ảnh hưởng tính tt_ca/tt_tuan).
--
-- Tag No không đụng tới bộ đếm duc_tag_no_counter (bộ đếm không lùi lại khi
-- tem bị xóa) nên insert thẳng bằng tag_no gốc không gây trùng/lệch số thứ
-- tự tem mới sinh sau này trong ngày.
-- An toàn chạy lại nhiều lần (idempotent — on conflict do nothing).
-- ============================================================================

insert into duc_tem (
  tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
  may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
  nguoi_tt, ngay_gio_xuat, nguoi_nhan, trang_thai, ghi_chu2, ng, ghi_chu_sl
) values (
  'TKD20260825-0004', 'Panel FR', 'AST-PAN-01', 384, date '2026-08-25', '2026-08-24', 'PAN #FR25', 'HD2-HDT',
  'DC 5', null, timestamptz '2026-08-25 05:30:00+07', 'PAN #FR25', 384, 'DC 5',
  null, null, null, 'Đã đúc', null, null, 'Chờ chốt sản lượng'
)
on conflict (tag_no) do nothing;

-- Tính lại tt_ca/tt_tuan của DC 5 / AST-PAN-01 để cộng lại đúng số lượng vừa khôi phục.
select duc_recompute_tt_ca('DC 5', 'AST-PAN-01');
