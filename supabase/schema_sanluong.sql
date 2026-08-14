-- ============================================================================
-- Schema pilot migrate: module Sản lượng & Giao hàng (sanluong.html)
-- Nguồn gốc: Google Sheet publish-to-web CSV, 6 tab: GiaoHang, KHSX, Capacity,
-- Forecast, Comments, Config — cột lấy đúng từ header CSV thật (khảo sát 2026-08-12).
-- Chạy toàn bộ file này trong Supabase SQL Editor.
-- ============================================================================

-- Tab "GiaoHang": Thang,KeHoach,ThucTe,NG_TraVe,NG_Huy
create table if not exists sl_giao_hang (
  thang       smallint primary key check (thang between 1 and 12),
  ke_hoach    numeric,
  thuc_te     numeric,
  ng_tra_ve   numeric,
  ng_huy      numeric
);

-- Tab "KHSX": Thang,Duc_KH,Duc_TT,Bavia_KH,Bavia_TT,GiaCong_KH,GiaCong_TT,Son_KH,Son_TT
create table if not exists sl_khsx (
  thang        smallint primary key check (thang between 1 and 12),
  duc_kh       numeric,
  duc_tt       numeric,
  bavia_kh     numeric,
  bavia_tt     numeric,
  gia_cong_kh  numeric,
  gia_cong_tt  numeric,
  son_kh       numeric,
  son_tt       numeric
);

-- Tab "Capacity": Thang,Capa350,Capa850,CapaGC,Loai (Loai = ThucTe/KeHoach...)
create table if not exists sl_capacity (
  thang    smallint check (thang between 1 and 12),
  capa350  numeric,
  capa850  numeric,
  capa_gc  numeric,
  loai     text not null,
  primary key (thang, loai)
);

-- Tab "Forecast": Thang,Loai,FCC,Exedy,Astemo,TTI,Khac
create table if not exists sl_forecast (
  thang   smallint check (thang between 1 and 12),
  loai    text not null,
  fcc     numeric,
  exedy   numeric,
  astemo  numeric,
  tti     numeric,
  khac    numeric,
  primary key (thang, loai)
);

-- Tab "Comments": Key,NoiDung
create table if not exists sl_comments (
  key        text primary key,
  noi_dung   text,
  updated_at timestamptz not null default now()
);

-- Tab "Config": Key,Value
create table if not exists sl_config (
  key   text primary key,
  value text
);

-- ----------------------------------------------------------------------------
-- Row Level Security: cho phép đọc công khai (giống CSV publish-to-web hiện tại),
-- chặn ghi trừ khi có quyền (comments sẽ mở ghi có kiểm soát ở bước sau, khi
-- chuyển Apps Script backend sang gọi Supabase thay vì Sheet).
-- ----------------------------------------------------------------------------
alter table sl_giao_hang enable row level security;
alter table sl_khsx      enable row level security;
alter table sl_capacity  enable row level security;
alter table sl_forecast  enable row level security;
alter table sl_comments  enable row level security;
alter table sl_config    enable row level security;

create policy "public read" on sl_giao_hang for select using (true);
create policy "public read" on sl_khsx      for select using (true);
create policy "public read" on sl_capacity  for select using (true);
create policy "public read" on sl_forecast  for select using (true);
create policy "public read" on sl_comments  for select using (true);
create policy "public read" on sl_config    for select using (true);
