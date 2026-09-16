-- ============================================================
-- Migration phase S9: IQC static page support
-- ============================================================
-- Mục tiêu:
-- 1) Tạo bảng lưu LOT IQC, lỗi IQC và danh mục lỗi mặc định.
-- 2) Mở RLS để trang tĩnh có thể đọc công khai.
-- 3) Cho phép authenticated user ghi dữ liệu từ static page.
-- ============================================================

create table if not exists public.iqc_lots (
  id bigserial primary key,
  received_at timestamptz,
  pickup_at timestamptz,
  completed_at timestamptz,
  supplier text,
  product_code text,
  product_name text,
  lot_no text,
  lot_qty numeric default 0,
  inspection_type text default 'Kiểm tra AQL',
  aql text,
  sample_qty numeric default 0,
  location text default 'Kho',
  status text default 'Chưa lấy hàng',
  result text,
  ok_qty numeric default 0,
  ng_qty numeric default 0,
  ok_pct numeric default 0,
  ng_pct numeric default 0,
  inspector text,
  note text,
  inspection_minutes integer default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.iqc_defects (
  id bigserial primary key,
  lot_id bigint not null references public.iqc_lots(id) on delete cascade,
  defect_type text default 'NG khác',
  defect_name text,
  defect_qty numeric default 0,
  defect_percent numeric default 0,
  note text,
  images text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.iqc_appearance_defects (
  id serial primary key,
  label text not null unique,
  sort_order integer not null default 100,
  created_at timestamptz not null default now()
);

create index if not exists idx_iqc_lots_created_at on public.iqc_lots (created_at desc);
create index if not exists idx_iqc_lots_status on public.iqc_lots (status);
create index if not exists idx_iqc_lots_result on public.iqc_lots (result);
create index if not exists idx_iqc_lots_product on public.iqc_lots (product_code, product_name, lot_no);
create index if not exists idx_iqc_defects_lot_id on public.iqc_defects (lot_id);
create index if not exists idx_iqc_defects_created_at on public.iqc_defects (created_at desc);

alter table public.iqc_lots enable row level security;
alter table public.iqc_defects enable row level security;
alter table public.iqc_appearance_defects enable row level security;

-- Cho phép đọc công khai để page tĩnh có thể render hiện thị.
drop policy if exists "public read iqc_lots" on public.iqc_lots;
create policy "public read iqc_lots" on public.iqc_lots
  for select using (true);

drop policy if exists "authenticated insert iqc_lots" on public.iqc_lots;
create policy "authenticated insert iqc_lots" on public.iqc_lots
  for insert with check (auth.uid() is not null);

drop policy if exists "authenticated update iqc_lots" on public.iqc_lots;
create policy "authenticated update iqc_lots" on public.iqc_lots
  for update using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists "authenticated delete iqc_lots" on public.iqc_lots;
create policy "authenticated delete iqc_lots" on public.iqc_lots
  for delete using (auth.uid() is not null);

-- Tương tự cho defects.
drop policy if exists "public read iqc_defects" on public.iqc_defects;
create policy "public read iqc_defects" on public.iqc_defects
  for select using (true);

drop policy if exists "authenticated insert iqc_defects" on public.iqc_defects;
create policy "authenticated insert iqc_defects" on public.iqc_defects
  for insert with check (auth.uid() is not null);

drop policy if exists "authenticated update iqc_defects" on public.iqc_defects;
create policy "authenticated update iqc_defects" on public.iqc_defects
  for update using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists "authenticated delete iqc_defects" on public.iqc_defects;
create policy "authenticated delete iqc_defects" on public.iqc_defects
  for delete using (auth.uid() is not null);

-- Mục lỗi mặc định để danh sách không rỗng khi page mới mở.
drop policy if exists "public read iqc_appearance_defects" on public.iqc_appearance_defects;
create policy "public read iqc_appearance_defects" on public.iqc_appearance_defects
  for select using (true);

drop policy if exists "authenticated insert iqc_appearance_defects" on public.iqc_appearance_defects;
create policy "authenticated insert iqc_appearance_defects" on public.iqc_appearance_defects
  for insert with check (auth.uid() is not null);

drop policy if exists "authenticated update iqc_appearance_defects" on public.iqc_appearance_defects;
create policy "authenticated update iqc_appearance_defects" on public.iqc_appearance_defects
  for update using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists "authenticated delete iqc_appearance_defects" on public.iqc_appearance_defects;
create policy "authenticated delete iqc_appearance_defects" on public.iqc_appearance_defects
  for delete using (auth.uid() is not null);

insert into public.iqc_appearance_defects (label, sort_order)
values
  ('Mặt xước', 1),
  ('Màu lệch', 2),
  ('Kích thước lệch', 3),
  ('Rãnh/co ngót', 4),
  ('Rỉ sét', 5),
  ('Vết bẩn', 6),
  ('Khác', 7)
on conflict (label) do nothing;

create or replace function public.touch_iqc_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_iqc_lots_touch_updated_at on public.iqc_lots;
create trigger trg_iqc_lots_touch_updated_at
before update on public.iqc_lots
for each row
execute function public.touch_iqc_updated_at();

drop trigger if exists trg_iqc_defects_touch_updated_at on public.iqc_defects;
create trigger trg_iqc_defects_touch_updated_at
before update on public.iqc_defects
for each row
execute function public.touch_iqc_updated_at();
