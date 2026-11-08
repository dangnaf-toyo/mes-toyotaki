-- ============================================================================
-- T226: Chi phí phế phẩm — đổi mã sản phẩm cũ (file Excel "Chi phi bao phe 2026.xlsx")
-- sang mã MES (master_products.ma_sp) khi hiển thị trên Dashboard chất lượng.
--
-- Dữ liệu tháng vẫn nạp NGUYÊN mã trong Excel vào cl_bao_phe_chi_tiet.ma_san_pham (không
-- sửa file nguồn). View cl_bao_phe_chi_tiet_mes tự đổi mã, theo thứ tự:
--   1. bảng ánh xạ cl_bao_phe_ma_anh_xa (so khớp bỏ khoảng trắng, không phân biệt hoa thường)
--   2. đã là mã MES (master_products.ma_sp)
--   3. trùng DUY NHẤT 1 master_products.ma_sp_khach_hang (bỏ khoảng trắng)
--   4. không khớp → giữ mã cũ, ma_sp = null → dashboard liệt kê "mã chưa gán mã MES"
-- Mã mới xuất hiện trong Excel tháng sau: thêm 1 dòng vào cl_bao_phe_ma_anh_xa (xem cuối file).
-- Nguồn ánh xạ: master_products (ma_sp_khach_hang, ten_sp), bảng mã cũ Bavia quá khứ (T158),
-- user xác nhận 08/11/2026: ghế OKAYA AR = CT, EVA = ĐM; 3B54 = EXE-SHO-01; 351708 = YHS-HAN-01.
-- ============================================================================

create table if not exists cl_bao_phe_ma_anh_xa (
  ma_cu    text primary key,
  ma_sp    text,            -- null = đã biết nhưng chưa có mã MES
  ghi_chu  text
);
create unique index if not exists cl_bao_phe_ma_anh_xa_khoa on cl_bao_phe_ma_anh_xa (lower(regexp_replace(ma_cu, '\s', '', 'g')));
alter table cl_bao_phe_ma_anh_xa enable row level security;
drop policy if exists "auth read" on cl_bao_phe_ma_anh_xa;
create policy "auth read" on cl_bao_phe_ma_anh_xa for select to authenticated using (true);
revoke all on cl_bao_phe_ma_anh_xa from anon;
grant select on cl_bao_phe_ma_anh_xa to authenticated;

insert into cl_bao_phe_ma_anh_xa (ma_cu, ma_sp, ghi_chu) values
  ('118-D02-126', 'AST-PAN-01', 'Panel FR'),
  ('1S9-5321-00', 'AST-PAN-02', 'Panel 1S9'),
  ('GRAP', 'AST-GRA-01', 'Rail, RR Grab'),
  ('3B54', 'EXE-SHO-01', 'CL SHOE 3B54 — user xác nhận EXEDY'),
  ('CL-Center', 'EXE-CEN-01', null),
  ('CL-Outer', 'EXE-OUT-01', null),
  ('PR Plat', 'EXE-PLT-01', null),
  ('P Plly', 'EXE-PLY-01', 'P PLLY SLD - BJJ (như dữ liệu Bavia quá khứ)'),
  ('Plly Fix', 'EXE-PLY-02', null),
  ('Plly SLD', 'EXE-PLY-03', null),
  ('K09-OUTER', 'FCC-OUT-01', null),
  ('CENTER KPH', 'FCC-KPH-01', null),
  ('Pressure KPH', 'FCC-KPH-02', null),
  ('Pressure KFM', 'FCC-KFM-01', null),
  ('panel H', 'FMC-PNH-01', null),
  ('Panel L', 'FMC-PNL-01', null),
  ('GZ10054', 'COS-GZ5-01', null),
  ('GZ10055', 'COS-GZ5-02', null),
  ('CFBV114', 'IWT-114-01', null),
  ('CFBV115', 'IWT-115-01', null),
  ('CFBV116', 'IWT-116-01', null),
  ('CFBV118', 'IWT-118-01', null),
  ('CFBV119', 'IWT-119-01', null),
  ('M3-003890-00', 'MIK-389-01', null),
  ('M3-003891-00', 'MIK-389-02', null),
  ('M3-003989-00', 'MIK-398-01', null),
  ('M3-003990-00', 'MIK-399-01', null),
  ('MT-45', 'MIK-MT4-01', null),
  ('MT-55', 'MIK-MT5-01', null),
  ('MT-66(DOM)', 'MIK-MT6-01', null),
  ('MT-77(DOM)', 'MIK-MT7-01', null),
  ('W-9904-0099R1', 'PRE-W99-01', null),
  ('Ligo', 'SOJ-LIG-01', null),
  ('DH 367 LGB', 'SUM-DH3-01', null),
  ('Bản lề', 'SVP-BAL-01', null),
  ('Lock', 'SVP-LOC-01', null),
  ('647724001', 'TTI-HSG-01', 'HOUSING 4001'),
  ('647119001', 'TTI-MOT-01', 'MOTOR 9001'),
  ('647119002', 'TTI-MOT-02', 'MOTOR 9002'),
  ('647119003', 'TTI-MOT-03', 'MOTOR 9003'),
  ('647118001', 'TTI-MOT-04', 'MOTOR 8001'),
  ('647118002', 'TTI-MOT-05', 'MOTOR 8002'),
  ('641801012', 'TTI-PUM-01', 'PUMP 1012'),
  ('641801014', 'TTI-PUM-02', 'PUMP 1014'),
  ('641801016', 'TTI-PUM-03', 'PUMP 1016'),
  ('351708', 'YHS-HAN-01', 'Handle — user xác nhận'),
  -- Ghế OKAYA: JS = JUST, MN = MINI, WI = wide; AR = CT, EVA = ĐM (user xác nhận)
  ('JS - SS - AR', 'OKA-GJT-01', null), ('JS - SS - EVA', 'OKA-GJT-02', null),
  ('JS - S - AR',  'OKA-GJT-03', null), ('JS - S - EVA',  'OKA-GJT-04', null),
  ('JS - L - AR',  'OKA-GJT-05', null), ('JS - L - EVA',  'OKA-GJT-06', null),
  ('JS - LL - AR', 'OKA-GJT-07', null), ('JS - LL - EVA', 'OKA-GJT-08', null),
  ('MN - S - AR',  'OKA-GMN-01', null), ('MN - S - EVA',  'OKA-GMN-02', null),
  ('MN - L - AR',  'OKA-GMN-03', null), ('MN - L - EVA',  'OKA-GMN-06', null),
  ('WI - S - AR',  'OKA-GWI-01', null), ('WI - S - EVA',  'OKA-GWI-02', null),
  ('WI - L - AR',  'OKA-GWI-03', null), ('WI - L - EVA',  'OKA-GWI-04', null),
  ('WI - LL - AR', 'OKA-GWI-05', null), ('WI - LL - EVA', 'OKA-GWI-06', null),
  -- Chưa có mã MES tương ứng (giữ mã cũ trên biểu đồ)
  ('12311-KWW-7400-H1', null, 'KWW — chưa có trong Danh mục sản phẩm'),
  ('945C57-01', null, 'Chưa có trong Danh mục sản phẩm'),
  ('988D39', null, 'Chưa có trong Danh mục sản phẩm'),
  ('988D40', null, 'Chưa có trong Danh mục sản phẩm'),
  ('CFAV 6032', null, 'Chưa có trong Danh mục sản phẩm'),
  ('CFAV 6052', null, 'Chưa có trong Danh mục sản phẩm'),
  ('CENTER KFM', null, 'Chưa rõ mã MES (chỉ T1–T2, chi phí 0)'),
  ('Foot', null, 'FOOT-L/R (QTL-FOT-01/02) — file gộp chung'),
  ('Ghế Size S (24)', null, 'Ghế cũ T1–T2'),
  ('Ghế Size L (25)', null, 'Ghế cũ T1–T2'),
  ('Ghế Size LL (26)', null, 'Ghế cũ T1–T2')
on conflict do nothing;

create or replace view cl_bao_phe_chi_tiet_mes with (security_invoker = true) as
select c.thang, c.ma_san_pham as ma_cu, c.cong_doan, c.don_gia, c.sl_bao_phe, c.thanh_tien,
       m.ma_sp, coalesce(m.ma_sp, c.ma_san_pham) as ma_hien_thi, p.ten_sp
from cl_bao_phe_chi_tiet c
left join lateral (
  select coalesce(
    (select a.ma_sp from cl_bao_phe_ma_anh_xa a
      where lower(regexp_replace(a.ma_cu, '\s', '', 'g')) = lower(regexp_replace(c.ma_san_pham, '\s', '', 'g'))),
    (select p1.ma_sp from master_products p1 where p1.ma_sp = c.ma_san_pham),
    (select min(p2.ma_sp) from master_products p2
      where lower(regexp_replace(p2.ma_sp_khach_hang, '\s', '', 'g')) = lower(regexp_replace(c.ma_san_pham, '\s', '', 'g'))
      having count(*) = 1)
  ) as ma_sp
) m on true
left join master_products p on p.ma_sp = m.ma_sp;
revoke all on cl_bao_phe_chi_tiet_mes from anon;
grant select on cl_bao_phe_chi_tiet_mes to authenticated;

-- ----------------------------------------------------------------------------
-- Bảo trì hàng tháng — sau khi nạp tháng mới, kiểm tra mã chưa gán:
--   select distinct ma_cu, sum(thanh_tien) from cl_bao_phe_chi_tiet_mes where ma_sp is null group by 1;
-- Gán mã mới:
--   insert into cl_bao_phe_ma_anh_xa (ma_cu, ma_sp, ghi_chu) values ('<mã trong Excel>', '<mã MES>', null);
-- (Dashboard cũng tự hiện dòng cảnh báo "mã chưa gán mã MES" dưới biểu đồ.)
-- ----------------------------------------------------------------------------
