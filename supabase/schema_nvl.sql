-- ============================================================================
-- Schema pilot migrate: module Quản lý tồn kho NVL (Ton-kho-NVL)
-- Nguồn gốc: Google Apps Script Web App (KHÔNG publish CSV), backend code.js,
-- Sheet ID 1sFRigbmMAKdKX2spRrq6IPjPeNA3hDaOECobqaXMa-8, 6 tab.
-- Khảo sát thực tế qua GAS_URL (curl) 2026-08-12 — xem mục 9.5 kế hoạch migrate.
-- Chạy toàn bộ file này trong Supabase SQL Editor.
--
-- Khác biệt quan trọng so với module Sản lượng:
--   - Đơn vị lưu trữ chuẩn hoá = KG (không phải tấn). Sheet gốc "Tồn Đầu Kỳ",
--     "Cài Đặt", "Giao Dịch", "Tồn Hiện Tại" hiện lưu bằng TẤN (xác nhận qua
--     curl: openingStock=21.113, quantity=3.979 ... khớp UI hiển thị "tấn"),
--     riêng "Kế Hoạch" (nhap/tieuHao/tonDuKien) đã lưu sẵn bằng KG (comment
--     trong code.js xác nhận, giá trị hàng nghìn khớp thực tế). Script import
--     (import-nvl.mjs) sẽ nhân 1000 cho các nguồn đang là tấn, giữ nguyên cho
--     Kế Hoạch — mọi bảng bên dưới đều tính bằng kg.
--   - 1 bảng danh mục nvl_materials dùng chung, đồng bộ từ getMasterMaterials
--     (KHSX Master cột V:W) — nguồn "rộng" hơn mảng MATERIALS cứng (7 mã) hiện
--     tại. Xác nhận thực tế qua curl: Master trả về 8 mã, có thêm "OUTER- S"
--     không tồn tại trong Tồn Đầu Kỳ/Cài Đặt/Tồn Hiện Tại — đúng như rủi ro #2
--     đã ghi trong kế hoạch mục 9.5.
--   - Không tạo bảng nvl_ton_hien_tai — thay bằng VIEW nvl_v_ton_hien_tai cộng
--     dồn từ nvl_ton_dau_ky + SUM(nvl_giao_dich) kể từ ngày đầu kỳ, đúng logic
--     comment gốc trong code.js ("V2 ... Tồn thực tế = Tồn Đầu Kỳ + Σ(Nhập -
--     Xuất) từ ngày đầu kỳ").
-- ============================================================================

-- Danh mục NVL dùng chung (nguồn: getMasterMaterials — KHSX Master cột V:W).
-- Mọi bảng khác tham chiếu khoá ngoại tới đây, giải quyết rủi ro 2 nguồn danh
-- mục lệch nhau (MATERIALS cứng trong code.js vs KHSX Master).
create table if not exists nvl_materials (
  ma_nvl  text primary key,
  ten_nvl text not null
);

-- Tab "Tồn Đầu Kỳ": A=Mã, B=NgàyĐầuKỳ, C=TồnĐầuKỳ (nguồn: getOpening, đơn vị gốc = tấn)
create table if not exists nvl_ton_dau_ky (
  ma_nvl        text primary key references nvl_materials (ma_nvl),
  ngay_dau_ky   date,
  ton_dau_ky_kg numeric
);

-- Tab "Kế Hoạch": dạng dài — 1 dòng = 1 mã + 1 ngày (thay vì 1 mã × 30 cột ngày
-- như sheet gốc). Nguồn: getPlanDaily, đơn vị đã sẵn là kg.
create table if not exists nvl_ke_hoach_ngay (
  ma_nvl          text not null references nvl_materials (ma_nvl),
  ngay            date not null,
  nhap_kg         numeric,
  tieu_hao_kg     numeric,
  ton_du_kien_kg  numeric,
  primary key (ma_nvl, ngay)
);

-- Tab "Giao Dịch": A-G Ngày,Loại,Mã,SốLượng,GhiChú,TồnSau,Timestamp (append-only).
-- Nguồn: getTransactions, đơn vị gốc = tấn. Sheet gốc KHÔNG có khoá tự nhiên
-- (không id, timestamp có thể trùng khi ghi nhiều dòng cùng lúc qua
-- processMultiTransaction) — dùng sheet_row (vị trí dòng vật lý trong sheet,
-- append-only nên ổn định) làm khoá để import idempotent (upsert lặp lại
-- không tạo trùng).
create table if not exists nvl_giao_dich (
  sheet_row     bigint primary key,
  ngay          date,
  loai          text not null check (loai in ('IN', 'OUT')),
  ma_nvl        text not null references nvl_materials (ma_nvl),
  so_luong_kg   numeric,
  ghi_chu       text,
  ton_sau_kg    numeric,
  ts_goc        timestamptz
);
create index if not exists idx_nvl_giao_dich_ma_ngay on nvl_giao_dich (ma_nvl, ngay);

-- Tab "Tem NVL": A-I TagNo,Mã,Tên,NgàyNhập,SốLượng,ĐơnVị,GhiChú,Timestamp,TrạngThái.
-- Nguồn: getTemList — LƯU Ý: action này chỉ trả về 100 tem mới nhất (giới hạn
-- cứng trong code.js, không có action lấy toàn bộ lịch sử tem), nên import
-- định kỳ chỉ đồng bộ được 100 tem gần nhất, không phải toàn bộ lịch sử.
-- so_luong giữ nguyên đơn vị gốc (kg hoặc pcs) — KHÔNG quy đổi, vì "pcs" không
-- có quy đổi kg hợp lệ (đây chính là nguồn gây lẫn lộn đơn vị trong Giao Dịch
-- hiện tại — xem nhận xét #4 kế hoạch).
create table if not exists nvl_tem (
  tag_no      text primary key,
  ma_nvl      text not null references nvl_materials (ma_nvl),
  ten_nvl     text,
  ngay_nhap   date,
  so_luong    numeric,
  don_vi      text check (don_vi in ('kg', 'pcs')),
  ghi_chu     text,
  ts_goc      timestamptz,
  trang_thai  text
);

-- Tab "Cài Đặt": A=Mã, B=Bề rộng (thực chất là ngưỡng USL/LSL cảnh báo tồn,
-- xem confirmMsg trong index.html). Nguồn: getSettings, đơn vị gốc = tấn.
create table if not exists nvl_cai_dat (
  ma_nvl    text primary key references nvl_materials (ma_nvl),
  be_rong_kg numeric
);

-- ----------------------------------------------------------------------------
-- VIEW thay thế tab "Tồn Hiện Tại": cộng dồn tồn đầu kỳ + giao dịch kể từ ngày
-- đầu kỳ (đúng logic comment gốc trong code.js) — không bao giờ lệch so với
-- lịch sử giao dịch gốc, khác với cách ghi đè thủ công hiện tại.
-- ----------------------------------------------------------------------------
create or replace view nvl_v_ton_hien_tai as
select
  o.ma_nvl,
  o.ton_dau_ky_kg
    + coalesce(sum(case when g.loai = 'IN' then g.so_luong_kg
                         when g.loai = 'OUT' then -g.so_luong_kg
                         else 0 end), 0) as ton_hien_tai_kg,
  now() as cap_nhat_luc
from nvl_ton_dau_ky o
left join nvl_giao_dich g
  on g.ma_nvl = o.ma_nvl
 and (o.ngay_dau_ky is null or g.ngay >= o.ngay_dau_ky)
group by o.ma_nvl, o.ton_dau_ky_kg;

-- ----------------------------------------------------------------------------
-- Row Level Security: cho phép đọc công khai (giống Web App GAS hiện tại,
-- ?action=getAllData không cần đăng nhập), chặn ghi trừ khi có quyền (giai
-- đoạn pilot vẫn ghi qua Apps Script/Sheet, chưa mở ghi trực tiếp Supabase).
-- ----------------------------------------------------------------------------
alter table nvl_materials    enable row level security;
alter table nvl_ton_dau_ky   enable row level security;
alter table nvl_ke_hoach_ngay enable row level security;
alter table nvl_giao_dich    enable row level security;
alter table nvl_tem          enable row level security;
alter table nvl_cai_dat      enable row level security;

create policy "public read" on nvl_materials     for select using (true);
create policy "public read" on nvl_ton_dau_ky    for select using (true);
create policy "public read" on nvl_ke_hoach_ngay for select using (true);
create policy "public read" on nvl_giao_dich     for select using (true);
create policy "public read" on nvl_tem           for select using (true);
create policy "public read" on nvl_cai_dat       for select using (true);
-- VIEW kế thừa RLS của bảng gốc (nvl_ton_dau_ky, nvl_giao_dich đã public read),
-- không cần policy riêng cho nvl_v_ton_hien_tai.
