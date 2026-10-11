-- ============================================================================
-- T74 — Kế hoạch bảo dưỡng khuôn tuần (bao-duong-khuon-tuan.html) dạng lưới
-- giống KHSX tuần: mỗi dòng = 1 khuôn được lên lịch vào 1 NGÀY, kèm loại
-- công việc + người thao tác chịu trách nhiệm.
--
-- Trước đây trang chỉ tự tính "khuôn cần chú ý" + đề xuất ngày rảnh, không
-- lưu gì. Nay lưu kế hoạch thật; phần tự tính vẫn giữ làm gợi ý.
--
-- "Đã làm" KHÔNG lưu ở đây — trang tự đối chiếu với duc_khuon_bao_duong_log
-- (ghi nhận thực tế vẫn ở duc-dashboard.html → Quản lý khuôn, D15), tránh 2
-- nơi ghi trạng thái lệch nhau.
--
-- Người phụ trách = tên trong master_employees (gợi ý vai_tro
-- 'bao_duong_khuon'), lưu text giống nguoi_thuc_hien của log.
--
-- Đọc công khai; ghi chỉ admin / trưởng ca / kế hoạch / QLSX / quản lý.
-- Chạy trên CẢ 2 project (production + staging). Idempotent.
-- ============================================================================

create table if not exists duc_khuon_bd_kh_tuan (
  id               bigserial primary key,
  tuan_bat_dau     date not null,          -- Thứ 2 đầu tuần
  ngay             date not null,          -- ngày dự kiến bảo dưỡng
  ma_khuon         text not null,
  loai             text not null default 'Bảo dưỡng định kỳ',
  nguoi_phu_trach  text not null default '',
  ghi_chu          text not null default '',
  updated_by       text not null default '',
  updated_at       timestamptz not null default now(),
  constraint duc_khuon_bd_kh_tuan_loai_check
    check (loai in ('Bảo dưỡng định kỳ', 'Sửa chữa', 'Thay khuôn mới', 'Kiểm tra')),
  constraint duc_khuon_bd_kh_tuan_ngay_trong_tuan
    check (ngay between tuan_bat_dau and tuan_bat_dau + 6),
  constraint duc_khuon_bd_kh_tuan_uniq unique (ma_khuon, ngay)
);
create index if not exists idx_duc_khuon_bd_kh_tuan_tuan on duc_khuon_bd_kh_tuan (tuan_bat_dau);

alter table duc_khuon_bd_kh_tuan enable row level security;

drop policy if exists "bd_kh_tuan public read" on duc_khuon_bd_kh_tuan;
create policy "bd_kh_tuan public read" on duc_khuon_bd_kh_tuan for select using (true);

drop policy if exists "bd_kh_tuan role insert" on duc_khuon_bd_kh_tuan;
create policy "bd_kh_tuan role insert" on duc_khuon_bd_kh_tuan for insert
  with check (public.has_role('admin','truong_ca','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong','quan_ly_bo_phan','giam_doc_sx'));

drop policy if exists "bd_kh_tuan role update" on duc_khuon_bd_kh_tuan;
create policy "bd_kh_tuan role update" on duc_khuon_bd_kh_tuan for update
  using (public.has_role('admin','truong_ca','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong','quan_ly_bo_phan','giam_doc_sx'))
  with check (public.has_role('admin','truong_ca','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong','quan_ly_bo_phan','giam_doc_sx'));

drop policy if exists "bd_kh_tuan role delete" on duc_khuon_bd_kh_tuan;
create policy "bd_kh_tuan role delete" on duc_khuon_bd_kh_tuan for delete
  using (public.has_role('admin','truong_ca','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong','quan_ly_bo_phan','giam_doc_sx'));

grant select on duc_khuon_bd_kh_tuan to anon, authenticated;
grant insert, update, delete on duc_khuon_bd_kh_tuan to authenticated;
grant usage, select on sequence duc_khuon_bd_kh_tuan_id_seq to authenticated;
