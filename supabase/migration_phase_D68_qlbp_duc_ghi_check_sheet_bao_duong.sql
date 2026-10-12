-- ============================================================================
-- D68 — Quản lý bộ phận Đúc được ghi / lưu nháp / hoàn thành check sheet bảo
-- dưỡng khuôn và tải ảnh trước / sau (user 2026-10-12, tài khoản Lê Văn Giang;
-- prod chưa có tài khoản nhan_vien_bao_duong_khuon).
--
--   - duc_khuon_cs_luu: điều kiện vai trò dùng duc_khuon_bd_la_nguoi_lap (D66:
--     NV bảo dưỡng khuôn / QLBP Đúc / admin) — chèn vào thân hàm đang có (không
--     chép lại cả hàm). Các ràng buộc khác giữ nguyên (đã hoàn thành thì không
--     sửa được, đủ hạng mục, ảnh, người thực hiện...).
--   - Storage bucket khuon-bao-duong: chính sách upload thêm QLBP Đúc.
--   (Hạng mục mẫu check sheet: QLBP Đúc vốn đã sửa được — RLS T78.)
--
-- Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

do $$
declare
  v_def text;
  v_cu text := E'  if coalesce(v_me.o_role, \'\') not in (\'nhan_vien_bao_duong_khuon\', \'admin\') then\n    return jsonb_build_object(\'ok\', false, \'error\', \'Chỉ nhân viên bảo dưỡng khuôn được ghi check sheet\');';
  v_moi text := E'  if not duc_khuon_bd_la_nguoi_lap(v_me.o_role, v_me.o_bo_phan) then  -- D68\n    return jsonb_build_object(\'ok\', false, \'error\', \'Chỉ nhân viên bảo dưỡng khuôn / Quản lý bộ phận Đúc được ghi check sheet\');';
begin
  v_def := pg_get_functiondef('duc_khuon_cs_luu'::regproc);
  if position('-- D68' in v_def) = 0 then
    if position(v_cu in v_def) = 0 then raise exception 'D68: không tìm thấy điều kiện vai trò trong duc_khuon_cs_luu'; end if;
    execute replace(v_def, v_cu, v_moi);
  end if;
end $$;

drop policy if exists "bd khuon upload khuon-bao-duong" on storage.objects;
create policy "bd khuon upload khuon-bao-duong" on storage.objects for insert
with check (
  bucket_id = 'khuon-bao-duong'
  and exists (select 1 from public.user_roles u
              where u.user_id = auth.uid()
                and (u.role in ('nhan_vien_bao_duong_khuon', 'admin')
                     or (u.role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(u.bo_phan_phu_trach, '{}')))))
);
