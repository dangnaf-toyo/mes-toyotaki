-- ============================================================================
-- T112 — Vai trò mới "Tổ trưởng khuôn" (to_truong_khuon), user 2026-10-16.
--
--   Được: lập / sửa / gửi kiểm tra KH bảo dưỡng khuôn (kéo theo ghi check sheet
--   + xử lý bất thường, cùng hàm duc_khuon_bd_la_nguoi_lap); thêm bớt hạng mục
--   check sheet (duc_khuon_cs_sua_mau_duoc); khai báo danh mục + nhập / xuất /
--   kiểm kê linh kiện dự phòng & vật tư tiêu hao (khuon_lk_nguoi quan_ly + thay);
--   upload ảnh bucket khuon-bao-duong.
--   KHÔNG được: Kiểm tra (QLBP Đúc), Phê duyệt (GĐSX), cho phép chạy tạm, sửa khuôn.
--
-- Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check (role = any (array[
  'admin','truong_ca','ipqc','qc_manager','kho_nvl','ke_hoach','qlsx_nhan_vien','qlsx_truong_phong',
  'quan_ly_bo_phan','giam_doc_sx','nhan_vien_duc','nhan_vien_bavia','nhan_vien_gia_cong',
  'nhan_vien_danh_bong','nhan_vien_oqc','nhan_vien_son','iatf_admin','nhan_vien_bao_duong_khuon',
  'nhan_vien_thong_ke','iqc','to_truong_khuon']));

create or replace function public.duc_khuon_bd_la_nguoi_lap(p_role text, p_bo_phan text[])
returns boolean language sql immutable as $$
  select coalesce(p_role, '') in ('nhan_vien_bao_duong_khuon', 'to_truong_khuon', 'admin')
      or (p_role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(p_bo_phan, '{}')));
$$;

create or replace function public.duc_khuon_cs_sua_mau_duoc()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid()
      and (role in ('admin', 'to_truong_khuon') or (role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(bo_phan_phu_trach, '{}'))))
  );
$$;

create or replace function public.khuon_lk_nguoi(p_quyen text, out o_loi text, out o_ten text, out o_role text)
returns record language plpgsql stable security definer set search_path = public as $$
declare
  v_role text; v_ten text;
begin
  select role, coalesce(nullif(trim(full_name), ''), nullif(trim(username), ''), email, '')
    into v_role, v_ten from public.user_roles where user_id = auth.uid();
  o_role := coalesce(v_role, ''); o_ten := coalesce(v_ten, '');
  if v_role is null then o_loi := 'Cần đăng nhập'; return; end if;
  if p_quyen = 'quan_ly' and v_role not in ('nhan_vien_thong_ke', 'to_truong_khuon', 'admin') then
    o_loi := 'Chỉ tổ trưởng khuôn / nhân viên thống kê / admin được thao tác'; return;
  end if;
  if p_quyen = 'thay' and v_role not in ('nhan_vien_thong_ke', 'nhan_vien_bao_duong_khuon', 'to_truong_khuon', 'admin') then
    o_loi := 'Chỉ tổ trưởng khuôn / nhân viên bảo dưỡng khuôn / thống kê / admin được ghi thay linh kiện'; return;
  end if;
end $$;

drop policy if exists "bd khuon upload khuon-bao-duong" on storage.objects;
create policy "bd khuon upload khuon-bao-duong" on storage.objects for insert to public
with check (bucket_id = 'khuon-bao-duong' and exists (
  select 1 from public.user_roles u where u.user_id = auth.uid()
    and (u.role in ('nhan_vien_bao_duong_khuon', 'to_truong_khuon', 'admin')
         or (u.role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(u.bo_phan_phu_trach, '{}'))))));
