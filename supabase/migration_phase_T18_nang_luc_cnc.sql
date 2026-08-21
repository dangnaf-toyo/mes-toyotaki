-- ============================================================================
-- Phase T18 — Tính năng lực máy gia công CNC (phay 3 trục / phay 4 trục /
-- tiện): quy trình CNC theo mã SP (nhiều bước, mỗi bước 1 loại máy + cycle
-- time), forecast sản lượng theo tháng, giả định năng lực (số ca/ngày,
-- giờ/ca, ngày làm/tháng, hiệu suất, số máy hiện có mỗi loại) — trang
-- nang-luc-cnc.html tự tính giờ máy cần / số máy cần mỗi tháng, so với số
-- máy hiện có để biết có cần đầu tư thêm không.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create table if not exists master_cnc_routing (
  id             bigserial primary key,
  ma_sp          text not null references master_products (ma_sp) on delete cascade,
  buoc           int not null default 1,
  loai_may       text not null check (loai_may in ('phay_3_truc', 'phay_4_truc', 'tien')),
  cycle_time_s   numeric not null check (cycle_time_s > 0),
  ghi_chu        text,
  unique (ma_sp, buoc)
);

create table if not exists cnc_forecast (
  id       bigserial primary key,
  ma_sp    text not null references master_products (ma_sp) on delete cascade,
  nam      int not null,
  thang    int not null check (thang between 1 and 12),
  so_luong numeric not null default 0,
  unique (ma_sp, nam, thang)
);

create table if not exists cnc_capacity_config (
  id                   int primary key default 1 check (id = 1),
  so_ca_ngay           numeric not null default 2,
  gio_ca               numeric not null default 8,
  ngay_lam_thang       numeric not null default 26,
  hieu_suat            numeric not null default 0.85,
  so_may_phay_3_truc   numeric not null default 14,
  so_may_phay_4_truc   numeric not null default 2,
  so_may_tien          numeric not null default 14,
  updated_at           timestamptz default now()
);
insert into cnc_capacity_config (id) values (1) on conflict (id) do nothing;

-- ── RLS: đọc công khai, ghi giới hạn role admin (giống migration_phase_S3) ──
do $$
declare t text;
begin
  for t in select unnest(array['master_cnc_routing', 'cnc_forecast', 'cnc_capacity_config'])
  loop
    execute format('alter table %I enable row level security;', t);

    execute format('drop policy if exists "public read" on %I;', t);
    execute format('create policy "public read" on %I for select using (true);', t);

    execute format('drop policy if exists "admin insert %1$s" on %1$s;', t);
    execute format('create policy "admin insert %1$s" on %1$s for insert with check (public.has_role(''admin''));', t);

    execute format('drop policy if exists "admin update %1$s" on %1$s;', t);
    execute format('create policy "admin update %1$s" on %1$s for update using (public.has_role(''admin'')) with check (public.has_role(''admin''));', t);

    execute format('drop policy if exists "admin delete %1$s" on %1$s;', t);
    execute format('create policy "admin delete %1$s" on %1$s for delete using (public.has_role(''admin''));', t);
  end loop;
end $$;
