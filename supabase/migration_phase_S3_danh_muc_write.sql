-- ============================================================================
-- Nhóm 1 / Mục 4 — Quản lý danh mục tập trung.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
--
-- master_products/master_machines/master_employees/duc_shot_khuon hiện chỉ
-- đọc công khai (xem schema_duc.sql dòng ~323), CHƯA có policy ghi nào — mọi
-- sửa đổi trước giờ phải làm thủ công trong Supabase Dashboard. Thêm policy
-- ghi giới hạn role admin (dùng has_role() từ migration_phase_S1) để trang
-- quan-ly-danh-muc.html ghi được qua client bình thường.
--
-- Không ảnh hưởng các RPC ghi các bảng này hiện có (duc_end_shift,
-- duc_upsert_plan...) vì chúng đều "security definer" nên bỏ qua RLS.
-- ============================================================================

do $$
declare t text;
begin
  for t in select unnest(array['master_products','master_machines','master_employees','duc_shot_khuon'])
  loop
    execute format('drop policy if exists "admin insert %1$s" on %1$s;', t);
    execute format('create policy "admin insert %1$s" on %1$s for insert with check (public.has_role(''admin''));', t);

    execute format('drop policy if exists "admin update %1$s" on %1$s;', t);
    execute format('create policy "admin update %1$s" on %1$s for update using (public.has_role(''admin'')) with check (public.has_role(''admin''));', t);

    execute format('drop policy if exists "admin delete %1$s" on %1$s;', t);
    execute format('create policy "admin delete %1$s" on %1$s for delete using (public.has_role(''admin''));', t);
  end loop;
end $$;
