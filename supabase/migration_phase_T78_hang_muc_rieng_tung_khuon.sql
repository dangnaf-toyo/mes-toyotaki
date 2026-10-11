-- ============================================================================
-- T78 — Hạng mục check sheet bảo dưỡng RIÊNG cho từng khuôn.
--
-- - duc_khuon_cs_mau.ma_khuon: NULL = hạng mục chung (mọi khuôn), có giá trị =
--   hạng mục đặc thù chỉ của khuôn đó.
-- - duc_khuon_cs_mau_bo (ma_khuon, id_mau): hạng mục CHUNG bị bỏ (không áp dụng)
--   cho một khuôn.
-- - Check sheet mở mới của khuôn X = hạng mục chung đang dùng (trừ các mục bị bỏ
--   cho X) + hạng mục riêng đang dùng của X, sắp theo thu_tu.
-- - Quyền sửa giống T76: Quản lý bộ phận Đúc / admin (duc_khuon_cs_sua_mau_duoc).
--
-- Chạy trên CẢ 2 project (production + staging). Idempotent. Chạy sau T76.
-- ============================================================================

alter table duc_khuon_cs_mau add column if not exists ma_khuon text;
create index if not exists idx_duc_khuon_cs_mau_ma_khuon on duc_khuon_cs_mau (ma_khuon);

create table if not exists duc_khuon_cs_mau_bo (
  ma_khuon    text not null,
  id_mau      bigint not null references duc_khuon_cs_mau(id) on delete cascade,
  updated_at  timestamptz not null default now(),
  primary key (ma_khuon, id_mau)
);

alter table duc_khuon_cs_mau_bo enable row level security;
drop policy if exists "cs_mau_bo public read" on duc_khuon_cs_mau_bo;
create policy "cs_mau_bo public read" on duc_khuon_cs_mau_bo for select using (true);
drop policy if exists "cs_mau_bo write" on duc_khuon_cs_mau_bo;
create policy "cs_mau_bo write" on duc_khuon_cs_mau_bo for all
  using (duc_khuon_cs_sua_mau_duoc()) with check (duc_khuon_cs_sua_mau_duoc());
grant select on duc_khuon_cs_mau_bo to anon, authenticated;
grant insert, update, delete on duc_khuon_cs_mau_bo to authenticated;
