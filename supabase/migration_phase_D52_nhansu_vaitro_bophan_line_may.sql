-- =============================================================================
-- D52 — Danh mục nhân sự (quan-ly-danh-muc.html, tab Nhân sự)
--
--   (1) Vai trò (ca sản xuất): ngoài nhan_vien / truong_ca, cho phép thêm
--       pho_ca, ipqc, oqc, iqc, bao_duong_khuon, thong_ke, kho.
--   (2) Bộ phận (cột tự do): gợi ý mới = Đúc, Bavia, Gia công - Sơn, QC, OQC,
--       Kho, QLSX, Thiết Bị. Đổi tên dữ liệu đang có cho khớp:
--         IPQC     -> QC        (IPQC nằm trong QC)
--         Bảo trì  -> Thiết Bị
--         Kho NVL  -> Kho
--         Kế hoạch -> QLSX
--   (3) Thêm cột line_may text[]: các mã máy / line trong master_machines mà
--       nhân sự này thao tác được (chọn nhiều trên form).
-- =============================================================================

-- (1) Mở rộng danh sách vai trò hợp lệ ----------------------------------------
alter table public.master_employees
  drop constraint if exists master_employees_vai_tro_check;

alter table public.master_employees
  add constraint master_employees_vai_tro_check
  check (vai_tro in (
    'nhan_vien', 'truong_ca', 'pho_ca',
    'ipqc', 'oqc', 'iqc',
    'bao_duong_khuon', 'thong_ke', 'kho'
  ));

-- (3) Cột Line (Máy) --------------------------------------------------------
alter table public.master_employees
  add column if not exists line_may text[];

-- (2) Đổi tên bộ phận trên dữ liệu hiện có ----------------------------------
update public.master_employees set bo_phan = 'QC'       where bo_phan = 'IPQC';
update public.master_employees set bo_phan = 'Thiết Bị' where bo_phan = 'Bảo trì';
update public.master_employees set bo_phan = 'Kho'      where bo_phan = 'Kho NVL';
update public.master_employees set bo_phan = 'QLSX'     where bo_phan = 'Kế hoạch';

-- Kiểm tra nhanh
-- select ten_nhan_vien, vai_tro, bo_phan, line_may from public.master_employees order by ten_nhan_vien;
