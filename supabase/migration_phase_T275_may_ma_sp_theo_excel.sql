-- ============================================================================
-- T275 (15/11/2026): Danh mục máy → "Dùng cho mã SP" theo file Excel
--   "Excel file/Dữ liệu mã - máy.xlsx" (máy Đúc DC 3–11, Kẽm 160T/190T; máy
--   Gia công Phay 01–17, Tiện 01–12, Chuốt 01).
--   * Máy Đúc: ghi mới (trước đây trống). DC 9 không có trong file → để trống.
--     Bỏ FCC TEST-01/02 (chưa có mã); OKA-GMN-04 → OKA-GMN-06 (user chốt).
--   * Máy Gia công: thay bằng danh sách Excel; Tiện 11 "MOT-03" = TTI-MOT-03;
--     Tiện 10 "Chưa chạy gì" → trống. 14 mã file không nhắc tới (BPH-SHO, IWT,
--     EXE-PLY-02/03/04, QTL-FOT, TTI-HSG) GIỮ ở máy đang có (trừ Tiện 10).
--   * Sao lưu danh sách cũ: t275_may_sao_luu.
--   Chỉ dữ liệu, chạy lại được. Trạng thái: Đã chạy STAGING + PROD 15/11/2026.
-- ============================================================================
create table if not exists public.t275_may_sao_luu as
  select ma_may, ma_sp_dung, now() luc from public.master_machines where false;
insert into public.t275_may_sao_luu
  select ma_may, ma_sp_dung, now() from public.master_machines m
  where not exists (select 1 from public.t275_may_sao_luu s where s.ma_may = m.ma_may);
alter table public.t275_may_sao_luu enable row level security;
revoke all on public.t275_may_sao_luu from anon, authenticated;

with moi(ma_may, ds) as (values
  ('DC 3', array['IWT-118-01','IWT-119-01','FMC-PNL-01','FCC-CEN-01']),
  ('DC 4', array['FMC-PNL-01','FMC-PNH-01','TTI-MOT-02','TTI-MOT-04','TTI-MOT-05','TTI-MOT-01','TTI-MOT-03','TTI-PUM-01','MIK-389-01','MIK-389-02','TTI-PUM-02','TTI-PUM-03','EXE-PLY-01','SOJ-LIG-01','IWT-118-01','IWT-119-01','IWT-114-01','IWT-115-01','IWT-116-01','AST-PAN-01']),
  ('DC 5', array['AST-PAN-01']),
  ('DC 6', array['FCC-KPH-01','FCC-KPH-02','FCC-OUT-01','MIK-MT5-01','FMC-PNL-01','MIK-399-01','MIK-398-01','MIK-389-01','MIK-389-02','COS-GZ5-01','COS-CVR-01','COS-GZ5-02','SOJ-LIG-01','SVP-LOC-01','EXE-PLY-01','EXE-OUT-01','EXE-CEN-01','EXE-PLT-01']),
  ('DC 7', array['FCC-OUT-01','SOJ-LIG-01','FCC-KPH-01','EXE-PLY-01','MIK-399-01','MIK-398-01','MIK-389-01','MIK-389-02','COS-GZ5-01','COS-CVR-01','COS-GZ5-02','FMC-PNL-01','TTI-MOT-05','TTI-MOT-01','TTI-MOT-03','FCC-KPH-02']),
  ('DC 8', array['MIK-399-01','MIK-398-01','MIK-389-01','MIK-389-02','MIK-MT6-01','MIK-MT7-01','MIK-MT7-02','MIK-MT5-01','MIK-MT4-01','SOJ-LIG-01','IWT-114-01','IWT-115-01','IWT-116-01','IWT-118-01','IWT-119-01','SVP-LOC-01','EXE-PLY-01','EXE-PLY-02','EXE-PLY-03','EXE-PLT-01','FCC-KPH-02','TTI-MOT-03','PRE-W99-01','TTI-MOT-05','TTI-MOT-01','FCC-KPH-01','COS-GZ5-01','COS-CVR-01','COS-GZ5-02','FCC-KFM-01','FCC-CEN-01','FMC-PNL-01']),
  ('DC 9', '{}'::text[]),
  ('DC 10', array['SUM-DH3-01','OKA-GWI-01','OKA-GWI-02','OKA-GWI-03','OKA-GWI-04','OKA-GWI-05','OKA-GWI-06','OKA-GJT-01','OKA-GJT-02','OKA-GJT-03','OKA-GJT-04','OKA-GMN-01','OKA-GMN-02','OKA-GJT-05','OKA-GJT-06','OKA-GMN-03','OKA-GMN-06','OKA-GJT-07','OKA-GJT-08']),
  ('DC 11', array['FCC-KPH-02','FCC-OUT-01','MIK-MT5-01','SVP-BAL-01','SVP-LOC-01','COS-GZ5-01','COS-CVR-01','COS-GZ5-02','SOJ-LIG-01','FMC-PNH-01','FMC-PNL-01','MIK-399-01','MIK-398-01','MIK-389-01','MIK-389-02','IWT-114-01','IWT-115-01','IWT-116-01','EXE-OUT-01','EXE-CEN-01','EXE-PLY-02','EXE-PLY-03','EXE-PLT-01','TTI-MOT-01','TTI-MOT-02','TTI-MOT-05','TTI-MOT-03','TTI-PUM-01','PRE-W99-01','EXE-PLY-01','FCC-KPH-01']),
  ('Kẽm 160T', array['EXE-SHO-01','YHS-HAN-01','EXE-SHO-02','BPH-SHO-01','BPH-SHO-03']),
  ('Kẽm 190T', array['EXE-SHO-01','BPH-SHO-01','BPH-SHO-03','BPH-SHO-02','YHS-HAN-01']),
  ('Phay 01', array['PRE-W99-01','TTI-MOT-05','TTI-MOT-04']),
  ('Phay 02', array['PRE-W99-01','TTI-MOT-05','TTI-MOT-04']),
  ('Phay 03', array['EXE-CEN-01']),
  ('Phay 04', array['EXE-OUT-01']),
  ('Phay 05', array['TTI-MOT-05','TTI-MOT-04','PRE-W99-01']),
  ('Phay 06', array['TTI-MOT-05','TTI-MOT-04','PRE-W99-01']),
  ('Phay 07', array['TTI-MOT-05','TTI-MOT-04']),
  ('Phay 08', array['TTI-MOT-05','TTI-MOT-04','TTI-PUM-01','TTI-PUM-02','TTI-PUM-03','SVP-LOC-01','SVP-BAL-01']),
  ('Phay 09', array['TTI-MOT-05','TTI-MOT-04','PRE-W99-01']),
  ('Phay 10', array['TTI-MOT-05','TTI-MOT-04','TTI-PUM-01','TTI-PUM-02','TTI-PUM-03','SVP-LOC-01','SVP-BAL-01']),
  ('Phay 11', array['TTI-MOT-05','TTI-MOT-04']),
  ('Phay 12', array['TTI-MOT-05','TTI-MOT-04']),
  ('Phay 13', array['TTI-MOT-05','TTI-MOT-02']),
  ('Phay 14', array['TTI-MOT-05','TTI-MOT-02']),
  ('Phay 15', array['SVP-BAL-01','TTI-MOT-05','TTI-MOT-02','MIK-389-01','MIK-389-02','MIK-398-01','MIK-399-01']),
  ('Phay 16', array['TTI-MOT-05','TTI-MOT-04','TTI-PUM-01','TTI-PUM-02','TTI-PUM-03','SVP-LOC-01','SVP-BAL-01']),
  ('Phay 17', array['TTI-MOT-05','TTI-MOT-04','TTI-PUM-01','TTI-PUM-02','TTI-PUM-03','SVP-LOC-01','SVP-BAL-01']),
  ('Tiện 01', array['EXE-CEN-01']),
  ('Tiện 02', array['EXE-CEN-01']),
  ('Tiện 03', array['TTI-MOT-01','TTI-MOT-02','TTI-MOT-03']),
  ('Tiện 04', array['EXE-PLT-01']),
  ('Tiện 05', array['TTI-MOT-01','TTI-MOT-02','TTI-MOT-03','MIK-389-01','MIK-389-02','MIK-398-01','MIK-399-01']),
  ('Tiện 06', array['EXE-OUT-01','EXE-PLY-01']),
  ('Tiện 07', array['TTI-MOT-01','TTI-MOT-02','TTI-MOT-03']),
  ('Tiện 08', array['EXE-PLY-01']),
  ('Tiện 09', array['TTI-MOT-01','TTI-MOT-02','TTI-MOT-03']),
  ('Tiện 10', '{}'::text[]),
  ('Tiện 11', array['TTI-MOT-03','MIK-389-01','MIK-389-02','MIK-398-01','MIK-399-01']),
  ('Tiện 12', array['EXE-OUT-01']),
  ('Chuốt 01', array['EXE-CEN-01'])
), giu(x) as (select unnest(array['BPH-SHO-01','BPH-SHO-02','BPH-SHO-03','IWT-114-01','IWT-115-01','IWT-116-01','IWT-118-01','IWT-119-01','EXE-PLY-02','EXE-PLY-03','EXE-PLY-04','QTL-FOT-01','QTL-FOT-02','TTI-HSG-01']))
update public.master_machines m
set ma_sp_dung = nullif(array(
      select x from (
        select x, 1 t, ord from unnest(moi.ds) with ordinality u(x, ord)
        union all
        select c.x, 2, ord from public.t275_may_sao_luu s,
          unnest(s.ma_sp_dung) with ordinality c(x, ord)
        where s.ma_may = m.ma_may and m.bo_phan = 'Gia công - Sơn' and m.ma_may <> 'Tiện 10'
          and c.x in (select x from giu) and not (c.x = any(moi.ds))
      ) z order by t, ord), '{}')
from moi
where m.ma_may = moi.ma_may;
