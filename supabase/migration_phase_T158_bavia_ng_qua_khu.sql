-- ============================================================================
-- Phase T158 — Dữ liệu NG Bavia QUÁ KHỨ (T01 → 18/10/2026) từ file Excel
-- "Thống kê hàng NG các bộ phận" (sheet BAVIA) của phòng QC.
--
-- Không ghi vào cd_ng_khai_bao vì bảng đó bắt buộc gắn tem Đúc thật (FK duc_tem),
-- còn số liệu cũ chỉ có theo ngày × mã × lỗi. Lưu 2 bảng riêng, chỉ đọc:
--   bavia_ng_qua_khu  — SL NG theo ngày / mã / lỗi (tên lỗi đã đổi theo 24 lỗi A–X
--                       của Bavia, loai_ng_goc giữ đúng tên trong Excel)
--   bavia_sx_qua_khu  — SL sản xuất Bavia theo ngày / mã (để tính tỷ lệ NG)
-- Mã cũ → mã MES theo file "Link mã sp MES vs mã cũ.xlsx" (+ K09 → FCC-OUT-01,
-- ID9001..3 → TTI-MOT-01..03, P PLLY SLD → EXE-PLY-01; mã ghế/mã lẻ không có
-- mã MES đã bỏ — user chốt 23/10/2026).
--
-- Dữ liệu nạp bằng script ngoài repo (upsert theo khoá duy nhất, chạy lại được).
-- An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create table if not exists public.bavia_ng_qua_khu (
  id bigserial primary key,
  ngay date not null,
  ma_sp text not null references master_products(ma_sp),
  ma_cu text not null,
  loai_ng text not null,
  loai_ng_goc text not null,
  so_luong numeric not null check (so_luong > 0),
  nguon text,
  unique (ngay, ma_cu, loai_ng_goc)
);
create index if not exists idx_bavia_ng_qua_khu_ngay on public.bavia_ng_qua_khu (ngay);
create index if not exists idx_bavia_ng_qua_khu_ma_sp on public.bavia_ng_qua_khu (ma_sp, ngay);

create table if not exists public.bavia_sx_qua_khu (
  ngay date not null,
  ma_cu text not null,
  ma_sp text not null references master_products(ma_sp),
  so_luong numeric not null check (so_luong > 0),
  nguon text,
  primary key (ngay, ma_cu)
);
create index if not exists idx_bavia_sx_qua_khu_ma_sp on public.bavia_sx_qua_khu (ma_sp, ngay);

alter table public.bavia_ng_qua_khu enable row level security;
alter table public.bavia_sx_qua_khu enable row level security;
drop policy if exists bavia_ng_qua_khu_select on public.bavia_ng_qua_khu;
create policy bavia_ng_qua_khu_select on public.bavia_ng_qua_khu for select to authenticated using (true);
drop policy if exists bavia_sx_qua_khu_select on public.bavia_sx_qua_khu;
create policy bavia_sx_qua_khu_select on public.bavia_sx_qua_khu for select to authenticated using (true);
revoke insert, update, delete on public.bavia_ng_qua_khu, public.bavia_sx_qua_khu from anon, authenticated;
