-- ============================================================================
-- Schema pilot migrate: module QR Chuyển công đoạn
-- Nguồn gốc: Google Sheet riêng (ID 1r6tq_LWBhqpWollry2LeBQmlWoxKsiXi4R-UGG6G0Xk),
-- tab "ChuyenCongDoan" (nhật ký, append-only) — publish-to-web CSV.
-- Header thật lấy từ CSV publish-to-web thật (2026-08-12) — 19 cột, thêm cột
-- "Ngày giờ xác nhận" so với `_ensureTransferSheet()` trong `ChuyenCongDoan.gs`
-- (cột này do `XacNhanChuyenCongDoan.gs` — luồng xác nhận riêng — bổ sung sau).
-- CSV thật là nguồn đúng nhất, ưu tiên hơn code/tài liệu cũ khi có sai khác.
-- Chạy toàn bộ file này trong Supabase SQL Editor.
--
-- KHÔNG tạo bảng cho tab "ViTriHienTai" — thay bằng VIEW cd_v_vi_tri_hien_tai
-- cộng dồn từ chính log (đúng đề xuất mục 9.3 của kế hoạch): loại bỏ hẳn cơ
-- chế upsert quét toàn sheet hiện tại (tốn 1 vòng lặp mỗi lần ghi).
-- ============================================================================

create table if not exists cd_chuyen_cong_doan_log (
  id_phieu            text primary key,               -- "CD{yyyyMMdd}-{seq}"
  thoi_gian_chuyen     timestamptz not null,
  tag_no              text not null,
  ma_sp               text,
  ten_sp              text,
  sl_tren_tem         numeric,
  sl_thuc_chuyen      numeric,
  chenh_lech          numeric,                        -- sl_tren_tem - sl_thuc_chuyen (hao hụt)
  lot_no              text,
  so_khuon            text,
  nguyen_lieu         text,
  may_duc             text,
  ngay_duc            text,                            -- giữ nguyên text như sheet gốc (định dạng không thuần nhất)
  cong_doan_giao      text not null,
  cong_doan_nhan      text not null,
  nguoi_giao          text,                            -- có thể rỗng (công đoạn nhận lấy hàng trước, giao xác nhận sau)
  nguoi_nhan          text not null,
  trang_thai_xac_nhan text,                            -- "Chờ công đoạn trước xác nhận" / "Đã xác nhận chuyển công đoạn"
  ngay_gio_xac_nhan   text                              -- giữ nguyên text — dữ liệu thật hay để trống dù đã xác nhận, không ép kiểu timestamp
);
create index if not exists idx_cd_log_tag_no on cd_chuyen_cong_doan_log (tag_no, thoi_gian_chuyen);

-- Thay thế tab "ViTriHienTai": vị trí hiện tại = công đoạn nhận của lượt
-- chuyển gần nhất theo từng Tag No. Không cần bảng riêng, không cần logic
-- upsert quét toàn sheet như code Apps Script hiện tại.
create or replace view cd_v_vi_tri_hien_tai as
select distinct on (tag_no)
  tag_no,
  cong_doan_nhan as vi_tri_hien_tai,
  thoi_gian_chuyen
from cd_chuyen_cong_doan_log
order by tag_no, thoi_gian_chuyen desc;

-- ----------------------------------------------------------------------------
-- Row Level Security: đọc công khai (giống các module trước), chưa mở ghi
-- trực tiếp — giai đoạn pilot vẫn ghi qua Apps Script (WA_ChuyenCongDoan).
-- ----------------------------------------------------------------------------
alter table cd_chuyen_cong_doan_log enable row level security;
create policy "public read" on cd_chuyen_cong_doan_log for select using (true);
-- VIEW kế thừa RLS của bảng gốc, không cần policy riêng.
