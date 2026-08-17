-- ============================================================================
-- Phase T8 — Kế hoạch sản xuất tuần cho khối NGOÀI Đúc (Bavia/Gia công/Sơn/OQC).
--
-- KHÁC với duc_khsx_tuan_plan (khoá theo máy cố định): 4 công đoạn này không
-- có danh mục máy/trạm cố định — trạm (cd_tram_hien_tai) là tên tự do, tạo
-- tạm mỗi ca (quyết định kiến trúc ở migration_phase_T3_cong_doan_dashboard.sql,
-- KHÔNG đổi). Nên kế hoạch tuần ở đây khoá theo (tuần, công đoạn, mã SP) —
-- không gắn trạm/line cụ thể, chỉ để bộ phận kế hoạch biết công đoạn nào cần
-- làm SP gì/số lượng bao nhiêu mỗi ngày, trưởng ca tự đối chiếu khi tạo trạm.
-- KHÔNG liên kết tự động vào cong-doan-dashboard.html ở bước này (theo yêu
-- cầu người dùng khi lập kế hoạch tính năng — chỉ cần trang nhập/xem độc lập
-- trước, giống khsx-tuan.html).
-- ============================================================================

create table if not exists cd_khsx_tuan_plan (
  id bigserial primary key,
  tuan_bat_dau date not null,        -- Thứ 2 đầu tuần áp dụng (khoá theo tuần)
  cong_doan text not null,           -- 'Bavia' | 'Gia Công' | 'Sơn' | 'OQC'
  ma_sp text not null,
  ten_sp text default '',
  kh_tuan numeric default 0,         -- tự tính = tổng 7 cột ngày (client tính, ghi kèm)
  t2 numeric default 0,
  t3 numeric default 0,
  t4 numeric default 0,
  t5 numeric default 0,
  t6 numeric default 0,
  t7 numeric default 0,
  cn numeric default 0,
  ghi_chu text default '',
  updated_by text default '',
  updated_at timestamptz not null default now(),
  unique (tuan_bat_dau, cong_doan, ma_sp)
);

create index if not exists idx_cd_khsx_tuan_plan_tuan on cd_khsx_tuan_plan (tuan_bat_dau, cong_doan);

alter table cd_khsx_tuan_plan enable row level security;

drop policy if exists "cd_khsx_tuan public read" on cd_khsx_tuan_plan;
create policy "cd_khsx_tuan public read" on cd_khsx_tuan_plan
  for select using (true);

drop policy if exists "cd_khsx_tuan authenticated write" on cd_khsx_tuan_plan;
create policy "cd_khsx_tuan authenticated write" on cd_khsx_tuan_plan
  for insert with check (auth.role() = 'authenticated');

drop policy if exists "cd_khsx_tuan authenticated update" on cd_khsx_tuan_plan;
create policy "cd_khsx_tuan authenticated update" on cd_khsx_tuan_plan
  for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "cd_khsx_tuan authenticated delete" on cd_khsx_tuan_plan;
create policy "cd_khsx_tuan authenticated delete" on cd_khsx_tuan_plan
  for delete using (auth.role() = 'authenticated');
