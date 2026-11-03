-- =============================================================================
-- T206 — Danh mục máy bộ phận Gia công (nguồn: Excel file/Danh mục máy gia công.xlsx)
--
--   master_machines thêm 3 cột (để trống với máy Đúc/Bavia/Đánh bóng):
--     loai_may      text    'Phay CNC' | 'Tiện CNC' | 'Chuốt'
--     so_truc       int     số trục (phay 3/4 trục, tiện 2 trục)
--     ma_sp_dung    text[]  các mã SP máy dùng được (theo file Excel)
--
--   Nạp 30 máy, bo_phan = 'Gia công - Sơn' (đúng tên bộ phận đang dùng ở nhân sự):
--     Phay 01..17  (máy 8,10,16,17 = 4 trục; còn lại 3 trục)
--     Tiện 01..12  (2 trục)
--     Chuốt 01
--   Số máy trùng nhau giữa phay/tiện nên mã máy kèm tiền tố loại máy.
--
--   Các màn Đúc lọc bo_phan='Đúc' nên không thấy máy mới; cong-doan-dashboard
--   chưa ánh xạ 'Gia Công' sang bộ phận nên vẫn chạy kiểu trạm tự do như cũ.
--   An toàn chạy lại (idempotent).
-- =============================================================================

alter table public.master_machines
  add column if not exists loai_may   text,
  add column if not exists so_truc    int,
  add column if not exists ma_sp_dung text[];

with ds(ma_may, loai_may, so_truc, ma_sp_dung) as (
  -- Phay CNC 4 trục: máy 8, 10, 16, 17
  select 'Phay ' || lpad(n::text, 2, '0'), 'Phay CNC', 4,
         array['TTI-PUM-01','TTI-PUM-02','TTI-PUM-03','SVP-LOC-01','TTI-HSG-01']
  from unnest(array[8, 10, 16, 17]) n
  union all
  -- Phay CNC 3 trục: máy 1–7, 9, 11–15
  select 'Phay ' || lpad(n::text, 2, '0'), 'Phay CNC', 3,
         array['SVP-BAL-01','IWT-114-01','IWT-115-01','IWT-116-01','IWT-118-01','IWT-119-01',
               'EXE-CEN-01','EXE-OUT-01','BPH-SHO-01','BPH-SHO-02','BPH-SHO-03',
               'TTI-MOT-04','TTI-MOT-05','TTI-MOT-01','TTI-MOT-02','TTI-MOT-03',
               'QTL-FOT-01','QTL-FOT-02']
  from unnest(array[1, 2, 3, 4, 5, 6, 7, 9, 11, 12, 13, 14, 15]) n
  union all
  -- Tiện CNC 2 trục: máy 1–12
  select 'Tiện ' || lpad(n::text, 2, '0'), 'Tiện CNC', 2,
         array['EXE-CEN-01','EXE-PLT-01','EXE-OUT-01','EXE-PLY-01','EXE-PLY-02','EXE-PLY-03',
               'EXE-PLY-04','TTI-MOT-01','TTI-MOT-02','TTI-MOT-03','IWT-118-01','IWT-119-01']
  from generate_series(1, 12) n
  union all
  -- Máy chuốt
  select 'Chuốt 01', 'Chuốt', null::int, array['EXE-CEN-01']
)
insert into public.master_machines (ma_may, kanban, bo_phan, loai_may, so_truc, ma_sp_dung)
select ma_may, false, 'Gia công - Sơn', loai_may, so_truc, ma_sp_dung from ds
on conflict (ma_may) do update
  set bo_phan    = excluded.bo_phan,
      loai_may   = excluded.loai_may,
      so_truc    = excluded.so_truc,
      ma_sp_dung = excluded.ma_sp_dung;

-- Kiểm tra nhanh
-- select loai_may, so_truc, count(*) from master_machines
--  where bo_phan = 'Gia công - Sơn' group by 1, 2 order by 1, 2;
