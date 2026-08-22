-- ============================================================================
-- Phase T20 — Bảng tổng hợp vấn đề & hành động đối ứng, đính kèm cuối trang
-- bao-cao-tuan.html (báo cáo sản xuất tuần khối Đúc).
--
-- Trang bao-cao-tuan.html tự tính TOÀN BỘ nội dung báo cáo (KPI, diễn biến
-- ngày, so sánh Ca 1/Ca 2, đổi khuôn theo trưởng ca, dừng máy theo máy/loại
-- vấn đề/mã SP...) trực tiếp từ dữ liệu sẵn có (duc_bao_cao_ca/duc_su_co_log/
-- duc_lich_su_san_xuat) — KHÔNG lưu lại các số này ở đâu, xem tuần nào thì
-- tính lại tuần đó, luôn khớp dữ liệu gốc.
--
-- Bảng dưới đây CHỈ lưu phần con người tự biên tập: bảng "Tổng hợp vấn đề và
-- hành động đối ứng" ở cuối trang — mỗi dòng ban đầu được gợi ý tự động từ
-- top vấn đề (theo mã lỗi) của đúng tuần đó, nhưng người dùng sửa/thêm/xoá rồi
-- lưu lại thì đây là bản đã lưu, hiển thị lại y nguyên khi mở lại tuần đó
-- (không tự tính lại gợi ý nữa một khi đã có bản lưu).
--
-- Khoá theo (tuan_bat_dau, stt) — cùng quy ước "tuan_bat_dau = Thứ 2 đầu tuần"
-- như cd_khsx_tuan_plan/duc_khsx_tuan_plan. RLS đọc công khai/ghi cần đăng
-- nhập, cùng pattern đã dùng cho cd_khsx_tuan_plan (migration_phase_T8).
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create table if not exists duc_bao_cao_tuan_van_de (
  id               bigserial primary key,
  tuan_bat_dau     date not null,        -- Thứ 2 đầu tuần báo cáo
  stt              smallint not null,
  van_de           text default '',
  so_phut_dung     numeric default 0,
  ty_le_phan_tram  numeric default 0,    -- % trên tổng phút dừng cả tuần, lưu dạng 0-100
  nguyen_nhan      text default '',
  doi_sach         text default '',
  dam_nhiem        text default '',
  thoi_han         date,
  updated_by       text default '',
  updated_at       timestamptz not null default now(),
  unique (tuan_bat_dau, stt)
);

create index if not exists idx_duc_bcttvd_tuan on duc_bao_cao_tuan_van_de (tuan_bat_dau);

alter table duc_bao_cao_tuan_van_de enable row level security;

drop policy if exists "duc_bcttvd public read" on duc_bao_cao_tuan_van_de;
create policy "duc_bcttvd public read" on duc_bao_cao_tuan_van_de
  for select using (true);

drop policy if exists "duc_bcttvd authenticated write" on duc_bao_cao_tuan_van_de;
create policy "duc_bcttvd authenticated write" on duc_bao_cao_tuan_van_de
  for insert with check (auth.role() = 'authenticated');

drop policy if exists "duc_bcttvd authenticated update" on duc_bao_cao_tuan_van_de;
create policy "duc_bcttvd authenticated update" on duc_bao_cao_tuan_van_de
  for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "duc_bcttvd authenticated delete" on duc_bao_cao_tuan_van_de;
create policy "duc_bcttvd authenticated delete" on duc_bao_cao_tuan_van_de
  for delete using (auth.role() = 'authenticated');
