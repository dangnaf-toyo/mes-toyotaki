-- ============================================================================
-- T34 — Bổ sung 3 cột bị thiếu trên duc_ncp mà duc_ncp_open_case /
-- duc_ncp_update_root_cause (migration_phase4_step6_ncp.sql) đã ghi/đọc từ
-- đầu nhưng CHƯA bao giờ có migration ALTER TABLE thêm vào bảng thật —
-- create table if not exists ở schema_duc.sql/step6 không tạo lại cột cho
-- bảng đã tồn tại. Lỗi thực tế khi mở phiếu NCP mới: 'column "ten_sp" of
-- relation "duc_ncp" does not exist'.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

alter table duc_ncp add column if not exists ten_sp text;
alter table duc_ncp add column if not exists so_luong_ng_du_kien numeric;
alter table duc_ncp add column if not exists nguoi_dam_nhiem_doi_sach text;
