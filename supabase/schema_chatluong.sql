-- ============================================================================
-- Schema pilot migrate: module Chất lượng (chatluong.html)
-- Nguồn gốc: Google Sheet publish-to-web CSV, 13 tab: tongHop, theoKhachHang,
-- theoCongDoan, qcDaily, qcRepaint, targets, comments, config, batThuongThang,
-- batThuongKH, batThuongNB, batThuongChuaTraLoi, ngLan1 — cột lấy đúng từ header
-- CSV thật (khảo sát 2026-08-12). Tiền tố bảng: cl_ (module Chất lượng).
-- Chạy toàn bộ file này trong Supabase SQL Editor.
-- ============================================================================

-- Tab "tongHop": Thang,SanLuongNoiBoTong,BaoPheNoiBoTong,GiaoHangTong,TraVeTong,DiemThuongPhat
create table if not exists cl_tong_hop (
  thang                  smallint primary key check (thang between 1 and 12),
  san_luong_noi_bo_tong  numeric,
  bao_phe_noi_bo_tong    numeric,
  giao_hang_tong         numeric,
  tra_ve_tong            numeric,
  diem_thuong_phat       numeric
);

-- Tab "theoKhachHang": Thang,KhachHang,SanLuong,BaoPhe,GiaoHang,TraVe
create table if not exists cl_theo_khach_hang (
  thang       smallint check (thang between 1 and 12),
  khach_hang  text not null,
  san_luong   numeric,
  bao_phe     numeric,
  giao_hang   numeric,
  tra_ve      numeric,
  primary key (thang, khach_hang)
);

-- Tab "theoCongDoan": Thang,CongDoan,SanLuong,BaoPhe,<cột rác text hướng dẫn, bỏ qua>
create table if not exists cl_theo_cong_doan (
  thang      smallint check (thang between 1 and 12),
  cong_doan  text not null,
  san_luong  numeric,
  bao_phe    numeric,
  primary key (thang, cong_doan)
);

-- Tab "qcDaily": Ngay,SoLuongNG,TyLeNG,<cột rác> — Ngay là text "dd/MM" KHÔNG có năm,
-- giữ nguyên là text (giới hạn giống hệt Sheet gốc, không tự ý thêm năm).
create table if not exists cl_qc_daily (
  ngay        text primary key,
  so_luong_ng numeric,
  ty_le_ng    numeric
);

-- Tab "qcRepaint": Loai,TyLeNG,<cột rác> — chỉ có 2 dòng "Son lan 1"/"Son lai".
create table if not exists cl_qc_repaint (
  loai     text primary key,
  ty_le_ng numeric
);

-- Tab "targets": Loai,Ten,MucTieuNoiBo,MucTieuTraVe,TheoDoiTraVe
create table if not exists cl_targets (
  loai            text not null,
  ten             text not null,
  muc_tieu_noi_bo numeric,
  muc_tieu_tra_ve numeric,
  theo_doi_tra_ve text,
  primary key (loai, ten)
);

-- Tab "comments": Key,NoiDung — NoiDung chứa HTML rich-text thật (bold/color/div lồng
-- nhau), lưu nguyên vào cột text, KHÔNG xử lý/strip HTML.
create table if not exists cl_comments (
  key        text primary key,
  noi_dung   text,
  updated_at timestamptz not null default now()
);

-- Tab "config": Key,Value
create table if not exists cl_config (
  key   text primary key,
  value text
);

-- Tab "batThuongThang": Thang,KH_TongSo,KH_DaDoiSach,NB_TongSo,NB_DaDoiSach
create table if not exists cl_bat_thuong_thang (
  thang         smallint primary key check (thang between 1 and 12),
  kh_tong_so    numeric,
  kh_da_doi_sach numeric,
  nb_tong_so    numeric,
  nb_da_doi_sach numeric
);

-- Tab "batThuongKH": Thang,Duc,Bavia,GiaCong,Son
create table if not exists cl_bat_thuong_kh (
  thang     smallint primary key check (thang between 1 and 12),
  duc       numeric,
  bavia     numeric,
  gia_cong  numeric,
  son       numeric
);

-- Tab "batThuongNB": Thang,Duc,Bavia,GiaCong,Son
create table if not exists cl_bat_thuong_nb (
  thang     smallint primary key check (thang between 1 and 12),
  duc       numeric,
  bavia     numeric,
  gia_cong  numeric,
  son       numeric
);

-- Tab "batThuongChuaTraLoi": CongDoan,SoVu
create table if not exists cl_bat_thuong_chua_tra_loi (
  cong_doan text primary key,
  so_vu     numeric
);

-- Tab "ngLan1": Thang,Duc,Bavia,GiaCong,Son — nhiều dòng giá trị rỗng, chấp nhận null.
create table if not exists cl_ng_lan1 (
  thang     smallint primary key check (thang between 1 and 12),
  duc       numeric,
  bavia     numeric,
  gia_cong  numeric,
  son       numeric
);

-- ----------------------------------------------------------------------------
-- Row Level Security: cho phép đọc công khai (giống CSV publish-to-web hiện tại),
-- chặn ghi trừ khi có quyền (comments sẽ mở ghi có kiểm soát ở bước sau, khi
-- chuyển Apps Script backend sang gọi Supabase thay vì Sheet).
-- ----------------------------------------------------------------------------
alter table cl_tong_hop                enable row level security;
alter table cl_theo_khach_hang         enable row level security;
alter table cl_theo_cong_doan          enable row level security;
alter table cl_qc_daily                enable row level security;
alter table cl_qc_repaint              enable row level security;
alter table cl_targets                 enable row level security;
alter table cl_comments                enable row level security;
alter table cl_config                  enable row level security;
alter table cl_bat_thuong_thang        enable row level security;
alter table cl_bat_thuong_kh           enable row level security;
alter table cl_bat_thuong_nb           enable row level security;
alter table cl_bat_thuong_chua_tra_loi enable row level security;
alter table cl_ng_lan1                 enable row level security;

create policy "public read" on cl_tong_hop                for select using (true);
create policy "public read" on cl_theo_khach_hang         for select using (true);
create policy "public read" on cl_theo_cong_doan          for select using (true);
create policy "public read" on cl_qc_daily                for select using (true);
create policy "public read" on cl_qc_repaint               for select using (true);
create policy "public read" on cl_targets                 for select using (true);
create policy "public read" on cl_comments                for select using (true);
create policy "public read" on cl_config                  for select using (true);
create policy "public read" on cl_bat_thuong_thang        for select using (true);
create policy "public read" on cl_bat_thuong_kh            for select using (true);
create policy "public read" on cl_bat_thuong_nb            for select using (true);
create policy "public read" on cl_bat_thuong_chua_tra_loi  for select using (true);
create policy "public read" on cl_ng_lan1                  for select using (true);
