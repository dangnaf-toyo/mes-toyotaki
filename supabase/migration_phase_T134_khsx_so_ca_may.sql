-- ============================================================================
-- Phase T134 — Số ca làm việc của TỪNG MÁY khai báo trên KHSX tuần (tab Đúc).
--
-- Trước đây duc-dashboard.html chia KH ngày của máy cho số ca của phương án
-- ca (luôn 2) → máy chỉ chạy ca ngày (DC 10, Kẽm 190T...) vẫn bị gợi ý KH ca
-- = KH ngày / 2. Nay bộ phận kế hoạch khai báo số ca theo (tuần, máy, ngày):
--   2 = chạy cả 2 ca, 1 = chỉ ca đầu (Ca ngày / Ca 1), 0 = máy nghỉ ngày đó.
-- Dashboard: năng lực ca = KH ngày máy / số ca; ca thứ 2 của máy 1 ca → KH 0,
-- Kết ca không tự tick tiếp tục sang ca nghỉ.
-- Máy chưa khai báo tuần này → lấy tuần gần nhất trước đó đã khai báo, không
-- có thì mặc định 2 (giữ hành vi cũ) — logic ở client (khsx-tuan + dashboard).
-- ============================================================================

create table if not exists duc_khsx_tuan_so_ca (
  tuan_bat_dau date not null,        -- Thứ 2 đầu tuần
  ma_may text not null,
  t2 smallint not null default 2 check (t2 between 0 and 2),
  t3 smallint not null default 2 check (t3 between 0 and 2),
  t4 smallint not null default 2 check (t4 between 0 and 2),
  t5 smallint not null default 2 check (t5 between 0 and 2),
  t6 smallint not null default 2 check (t6 between 0 and 2),
  t7 smallint not null default 2 check (t7 between 0 and 2),
  cn smallint not null default 2 check (cn between 0 and 2),
  updated_by text default '',
  updated_at timestamptz not null default now(),
  primary key (tuan_bat_dau, ma_may)
);

create index if not exists idx_duc_khsx_tuan_so_ca_may on duc_khsx_tuan_so_ca (ma_may, tuan_bat_dau desc);

alter table duc_khsx_tuan_so_ca enable row level security;

drop policy if exists "khsx_so_ca public read" on duc_khsx_tuan_so_ca;
create policy "khsx_so_ca public read" on duc_khsx_tuan_so_ca
  for select using (true);

drop policy if exists "khsx_so_ca authenticated write" on duc_khsx_tuan_so_ca;
create policy "khsx_so_ca authenticated write" on duc_khsx_tuan_so_ca
  for insert with check (auth.role() = 'authenticated');

drop policy if exists "khsx_so_ca authenticated update" on duc_khsx_tuan_so_ca;
create policy "khsx_so_ca authenticated update" on duc_khsx_tuan_so_ca
  for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "khsx_so_ca authenticated delete" on duc_khsx_tuan_so_ca;
create policy "khsx_so_ca authenticated delete" on duc_khsx_tuan_so_ca
  for delete using (auth.role() = 'authenticated');

grant select on duc_khsx_tuan_so_ca to anon, authenticated;
grant insert, update, delete on duc_khsx_tuan_so_ca to authenticated;
