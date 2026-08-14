-- ============================================================================
-- Schema pilot migrate: khối Dashboard Đúc + IPQC + In tem (module lớn nhất,
-- migrate cùng 1 khối — xem nhận xét mục 9.1 kế hoạch migrate).
-- Cột lấy đúng 100% từ `D:\Project\MES\Dashboard Đúc\Config.js` (các hằng
-- COL_CHT/COL_BGSC/COL_BC/COL_SK/COL_SM/COL_TC/COL_VDK/COL_LSSX/COL_IPQC_CP/
-- COL_IPQC_TC/COL_NCP) — đây là NGUỒN ĐÚNG NHẤT, ưu tiên hơn tài liệu cũ.
-- Chạy toàn bộ file này trong Supabase SQL Editor.
-- ============================================================================

-- ── Danh mục dùng chung (từ file KHSX Master, sheet "Master") ──────────────
-- Master lưu nhiều danh sách SONG SONG theo cột (không phải 1 bảng chuẩn hoá):
--   C7:D = mã SP + tên SP · G7:G = cavity khuôn (cùng hàng với C:D)
--   I7:I = cycle time giây (cùng hàng với C:D) · Q7:Q = danh sách máy
--   R7:R = danh sách nhân sự · AE7:AE = danh sách trưởng ca
-- Import script tách theo cột (vị trí, không theo header) thành 3 bảng sau.
create table if not exists master_products (
  ma_sp        text primary key,
  ten_sp       text,
  cavity       numeric,
  cycle_time_s numeric
);
create table if not exists master_machines (
  ma_may text primary key
);
create table if not exists master_employees (
  ten_nhan_vien text primary key,
  vai_tro       text check (vai_tro in ('nhan_vien', 'truong_ca'))
);

-- ── Sheet "Ca_hien_tai" (COL_CHT, 37 cột) — bảng STATE, không phải lịch sử ──
create table if not exists duc_ca_hien_tai (
  id_dong                text primary key,
  ngay                   date,
  ca                     text,
  phuong_an_ca           text,
  tuan_sx                text,
  ma_may                 text references master_machines (ma_may),
  ma_sp                  text,
  ten_sp                 text,
  so_khuon               text,
  kh_ca                  numeric,
  kh_tuan                numeric,
  tt_ca                  numeric,
  tt_tuan                numeric,
  ty_le_hoan_thanh       numeric,
  nv_ca_ngay             text,
  nv_ca_dem              text,
  open_loai_su_co        text,
  open_gio_phat_sinh     timestamptz,
  open_van_de            text,
  open_noi_dung_xu_ly    text,
  open_dam_nhiem         text,
  trang_thai             text,
  ghi_chu                text,
  editing_lock_user      text,
  editing_lock_at        timestamptz,
  version                bigint,
  last_updated_by        text,
  last_updated_at        timestamptz,
  so_shot_nong_khuon     numeric,
  so_luong_ng            numeric,
  phan_loai_ng           text,
  sp_start_time          timestamptz,
  sp_end_time            timestamptz,
  so_shot_khuon_snapshot numeric,
  so_shot_dau_ca         numeric,
  so_shot_cuoi_ca        numeric,
  khuon_kep_voi          text
);

-- ── Sheet "BanGhi_SuCo" (COL_BGSC, 19 cột) — lịch sử sự cố, append-only ────
create table if not exists duc_su_co_log (
  id_ban_ghi          text primary key,
  ngay                date,
  ca                  text,
  tuan_sx             text,
  ma_may              text,
  ma_sp               text,
  ten_sp              text,
  so_khuon            text,
  loai_su_co          text,
  gio_phat_sinh       timestamptz,
  gio_tro_lai         timestamptz,
  thoi_gian_dung_phut numeric,
  van_de              text,
  noi_dung_xu_ly      text,
  dam_nhiem           text,
  ghi_chu             text,
  truong_ca           text,
  thoi_diem_luu       timestamptz,
  van_de_edited       text
);

-- ── Sheet "BaoCao_Ca" (COL_BC, 24 cột) — tổng kết mỗi ca ───────────────────
create table if not exists duc_bao_cao_ca (
  id_bao_cao              text primary key,
  ngay                    date,
  ca                      text,
  phuong_an_ca            text,
  tuan_sx                 text,
  truong_ca               text,
  so_may_co_kh            numeric,
  so_may_hoan_thanh_kh    numeric,
  tong_kh_ca              numeric,
  tong_tt_ca              numeric,
  ty_le_hoan_thanh_ca     numeric,
  so_su_co_ca             numeric,
  tong_phut_dung_ca       numeric,
  url_gdoc_bao_cao        text,
  thoi_diem_ket_ca        timestamptz,
  ghi_chu                 text,
  oee_ca                  numeric,
  availability_ca         numeric,
  performance_ca          numeric,
  quality_ca              numeric,
  tong_ng_ca              numeric,
  tong_shot_nong_khuon_ca numeric,
  comment_truong_ca       text,
  nv_ca_bao_cao           text
);

-- ── Sheet "Shot_Khuon" (COL_SK, 10 cột) ────────────────────────────────────
create table if not exists duc_shot_khuon (
  ma_khuon                        text primary key,
  ten_sp_gan_nhat                 text,
  tong_shot_luy_ke                numeric,
  nguong_bao_duong                numeric,
  nguong_lam_moi                  numeric,
  lan_bao_duong_gan_nhat          date,
  shot_tai_lan_bao_duong_gan_nhat numeric,
  trang_thai_khuon                text,
  ghi_chu                         text,
  last_updated_at                 timestamptz
);

-- ── Sheet "Shot_May" (COL_SM, 3 cột) — mới phát hiện 2026-08-12 ───────────
create table if not exists duc_shot_may (
  ma_may                    text primary key references master_machines (ma_may),
  so_shot_cuoi_ca_gan_nhat  numeric,
  last_updated_at           timestamptz
);

-- ── Sheet "TangCa_Log" (COL_TC, 12 cột) ────────────────────────────────────
create table if not exists duc_tangca_log (
  id_log            text primary key,
  id_dong           text,
  ngay              date,
  ca                text,
  ma_may            text,
  ma_sp             text,
  gio_ket_thuc_cu   text,
  gio_ket_thuc_moi  text,
  so_phut_them      numeric,
  ly_do             text,
  nguoi_duyet       text,
  thoi_diem_ghi     timestamptz
);

-- ── Sheet "Van_De_Khuon" (COL_VDK, 18 cột) ─────────────────────────────────
create table if not exists duc_van_de_khuon (
  id_van_de        text primary key,
  ma_khuon         text,
  ngay_phat_hien   date,
  ca_phat_hien     text,
  ma_may           text,
  ma_sp            text,
  mo_ta            text,
  nguoi_phat_hien  text,
  trang_thai       text,   -- 'Mở' | 'Chờ xác nhận' | 'Đã đóng'
  noi_dung_xu_ly   text,
  nguoi_xu_ly      text,
  ngay_xu_ly       date,
  lan_tai_phat     numeric,
  ngay_xac_nhan    date,
  nguoi_xac_nhan   text,
  ket_qua_xac_nhan text,   -- 'OK' | 'Tái phát'
  ghi_chu          text,
  last_updated_at  timestamptz
);

-- ── Sheet "Lich_Su_SanXuat" (COL_LSSX, 11 cột) — không có PK tự nhiên ─────
-- 1 dòng/(ngày,ca,máy,SP) ghi khi kết ca — dùng khoá tổng hợp cho upsert.
create table if not exists duc_lich_su_san_xuat (
  id             bigserial primary key,
  ngay           date,
  ca             text,
  phuong_an_ca   text,
  tuan_sx        text,
  ma_may         text,
  ma_sp          text,
  ten_sp         text,
  kh_ca          numeric,
  tt_ca          numeric,
  so_luong_ng    numeric,
  thoi_diem_ghi  timestamptz,
  unique (ngay, ca, ma_may, ma_sp)
);

-- ── Sheet "IPQC_Checkpoint" (COL_IPQC_CP, 21 cột — đã có id_ncp_lien_quan) ─
create table if not exists duc_ipqc_checkpoint (
  id_checkpoint          text primary key,
  id_dong                text,
  ma_may                 text,
  ma_sp                  text,
  ngay                   date,
  ca                     text,
  phuong_an_ca           text,
  loai_kiem              text,   -- 'dinh_ky' | 'sau_su_co' | 'doi_khuon'
  id_su_co_goc           text,
  thoi_diem_tao          timestamptz,
  han_kiem               timestamptz,
  trang_thai             text,   -- 'cho_kiem' | 'da_kiem' | 'het_hieu_luc'
  thoi_diem_kiem_thuc_te timestamptz,
  nguoi_kiem             text,
  ket_qua                text,   -- 'OK' | 'NG' | 'CANH_BAO'
  checklist_json         jsonb,
  anh_bang_chung_url     jsonb,  -- mảng URL Drive (nhiều ảnh)
  ghi_chu                text,
  id_van_de_lien_quan    text,
  thoi_gian_kiem_giay    numeric,
  id_ncp_lien_quan       text
);

-- ── Sheet "IPQC_TieuChuan" (COL_IPQC_TC, 5 cột) ────────────────────────────
create table if not exists duc_ipqc_tieuchuan (
  ma_sp                    text primary key,
  danh_sach_muc_kiem_json  jsonb,
  file_pdf_url             text,
  cap_nhat_lan_cuoi_boi    text,
  thoi_diem_cap_nhat       timestamptz
);

-- ── Sheet "SP_Khong_Phu_Hop" (COL_NCP, 48 cột) — mới phát hiện 2026-08-12 ──
create table if not exists duc_ncp (
  id_ncp                     text primary key,
  id_checkpoint_goc          text references duc_ipqc_checkpoint (id_checkpoint),
  ngay_tao                   date,
  ma_may                     text,
  ma_sp                      text,
  so_khuon                   text,
  mo_ta_loi                  text,
  so_luong_nghi_van          numeric,
  vi_tri_cach_ly             text,
  nguoi_mo_case              text,
  so_luong_da_loc            numeric,
  so_luong_loc_ok            numeric,
  so_luong_loc_ng            numeric,
  nguoi_loc                  text,
  thoi_diem_loc              timestamptz,
  phuong_an_ng                text,   -- '' | 'sua' | 'bao_phe'
  mo_ta_phuong_an_sua         text,
  so_luong_sua_ok             numeric,
  so_luong_sua_khong_duoc     numeric,
  nguoi_sua                   text,
  thoi_diem_sua                timestamptz,
  so_phieu_phe                text,
  so_luong_de_nghi_phe        numeric,
  ly_do_phe                   text,
  nguoi_de_nghi_phe           text,
  thoi_diem_de_nghi_phe       timestamptz,
  nguoi_duyet_phe             text,
  thoi_diem_duyet_phe         timestamptz,
  ket_qua_duyet_phe           text,   -- 'Duyet' | 'Tu_choi'
  so_luong_phe_da_duyet       numeric,
  trang_thai                  text,   -- 'da_cach_ly'|'dang_loc'|'cho_quyet_dinh'|'dang_sua'|'cho_duyet_phe'|'dong'
  ghi_chu                     text,
  last_updated_at             timestamptz,
  nguoi_dam_nhiem             text,
  nguyen_nhan_phat_sinh       text,
  nguyen_nhan_luu_xuat        text,
  doi_sach_ps_tam_thoi_json   jsonb,
  doi_sach_ps_lau_dai_json    jsonb,
  doi_sach_lx_tam_thoi_json   jsonb,
  doi_sach_lx_lau_dai_json    jsonb,
  hinh_anh_phat_sinh_json     jsonb,
  hinh_anh_luu_xuat_json      jsonb,
  rc_trang_thai_duyet         text,   -- 'nhap' | 'cho_duyet' | 'da_duyet' | 'tu_choi'
  rc_nguoi_gui_duyet          text,
  rc_thoi_diem_gui_duyet      timestamptz,
  rc_nguoi_duyet              text,
  rc_thoi_diem_duyet          timestamptz,
  rc_ghi_chu_duyet            text
);

-- ── File Diecast: log sản lượng theo phút (tab đầu tiên của file Diecast) ─
-- Cột theo Config.js: DIECAST_PRODUCT_COL=C, DATETIME_COL=K, QUANTITY_COL=M,
-- MACHINE_COL=N, dữ liệu bắt đầu từ dòng 4 (DIECAST_DATA_START_ROW).
create table if not exists duc_diecast_log (
  id            bigserial primary key,
  thoi_diem     timestamptz not null,
  ma_may        text not null,
  ma_sp         text,
  so_luong      numeric,
  unique (thoi_diem, ma_may)
);
create index if not exists idx_duc_diecast_log_may_time on duc_diecast_log (ma_may, thoi_diem);

-- ── File Diecast, tab "DUC" (In tem công đoạn Đúc, 21 cột — xem mục 9.2) ──
create table if not exists duc_tem (
  tag_no         text primary key,   -- "TKD{yyyyMMdd}-{seq}" hoặc "D-TKD{...}" (SP đang phát triển)
  ten_sp         text,
  ma_sp          text,
  so_luong       numeric,
  ngay           date,
  lot            text,
  so_khuon       text,
  nguyen_lieu    text,
  may_duc_chi_thi text,
  ghi_chu        text,
  ngay_gio_in    timestamptz,
  so_khuon_tt    text,
  so_luong_tt    numeric,
  may_tt         text,
  nguoi_tt       text,
  ngay_gio_xuat  timestamptz,
  nguoi_nhan     text,
  trang_thai     text,
  ghi_chu2       text,
  ng             numeric,
  ghi_chu_sl     text
);

-- ----------------------------------------------------------------------------
-- Row Level Security: đọc công khai, chưa mở ghi trực tiếp (giai đoạn pilot
-- vẫn ghi qua Apps Script — dashboard Đúc/IPQC/In tem không đổi luồng ghi).
-- ----------------------------------------------------------------------------
do $$
declare t text;
begin
  for t in select unnest(array[
    'master_products','master_machines','master_employees',
    'duc_ca_hien_tai','duc_su_co_log','duc_bao_cao_ca','duc_shot_khuon',
    'duc_shot_may','duc_tangca_log','duc_van_de_khuon','duc_lich_su_san_xuat',
    'duc_ipqc_checkpoint','duc_ipqc_tieuchuan','duc_ncp',
    'duc_diecast_log','duc_tem'
  ])
  loop
    execute format('alter table %I enable row level security;', t);
    execute format('create policy "public read" on %I for select using (true);', t);
  end loop;
end $$;
