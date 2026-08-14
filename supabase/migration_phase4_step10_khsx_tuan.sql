-- ============================================================================
-- Phase 4, bước con 10 — thay thế Google Sheet "Tuan_Hien_Tai" (file KHSX
-- riêng của bộ phận kế hoạch) bằng 1 bảng Supabase, để hoàn toàn bỏ Google.
-- Khôi phục tính năng "⚡ Nạp kế hoạch từ KHSX tuần" trên duc-dashboard.html.
--
-- Bộ phận kế hoạch sẽ nhập/sửa kế hoạch tuần qua trang khsx-tuan.html (mới)
-- thay vì Google Sheet. Đọc công khai (trưởng ca cần đọc để gợi ý), ghi cần
-- đăng nhập (đơn giản: bất kỳ ai đăng nhập cũng ghi được, giống pattern
-- sl_comments/cl_comments — không phân quyền riêng theo bộ phận ở bước này).
-- ============================================================================

create table if not exists duc_khsx_tuan_plan (
  id bigserial primary key,
  tuan_bat_dau date not null,        -- Thứ 2 đầu tuần áp dụng (khoá theo tuần)
  ma_sp text not null,
  ten_sp text default '',
  ma_may text not null,
  so_ca_sx numeric default 0,
  kh_tuan numeric default 0,
  ct_giay numeric default 0,
  gio_cong numeric default 0,
  so_khuon text default '',
  t2 numeric default 0,
  t3 numeric default 0,
  t4 numeric default 0,
  t5 numeric default 0,
  t6 numeric default 0,
  t7 numeric default 0,
  cn numeric default 0,
  nhan_luc text default '',
  chu_ky text default '',
  ghi_chu text default '',
  updated_by text default '',
  updated_at timestamptz not null default now(),
  unique (tuan_bat_dau, ma_may, ma_sp)
);

create index if not exists idx_duc_khsx_tuan_plan_tuan on duc_khsx_tuan_plan (tuan_bat_dau);

alter table duc_khsx_tuan_plan enable row level security;

drop policy if exists "khsx_tuan public read" on duc_khsx_tuan_plan;
create policy "khsx_tuan public read" on duc_khsx_tuan_plan
  for select using (true);

drop policy if exists "khsx_tuan authenticated write" on duc_khsx_tuan_plan;
create policy "khsx_tuan authenticated write" on duc_khsx_tuan_plan
  for insert with check (auth.role() = 'authenticated');

drop policy if exists "khsx_tuan authenticated update" on duc_khsx_tuan_plan;
create policy "khsx_tuan authenticated update" on duc_khsx_tuan_plan
  for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "khsx_tuan authenticated delete" on duc_khsx_tuan_plan;
create policy "khsx_tuan authenticated delete" on duc_khsx_tuan_plan
  for delete using (auth.role() = 'authenticated');
