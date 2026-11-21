-- T303: màn sửa danh sách nút chọn sự cố Đúc (Danh mục → tab "Sự cố Đúc") — chỉ admin được thêm / sửa / xoá.
grant insert, update, delete on public.duc_su_co_mau to authenticated;

drop policy if exists "su_co_mau admin insert" on public.duc_su_co_mau;
create policy "su_co_mau admin insert" on public.duc_su_co_mau for insert to authenticated
  with check (public.has_role(variadic array['admin']));
drop policy if exists "su_co_mau admin update" on public.duc_su_co_mau;
create policy "su_co_mau admin update" on public.duc_su_co_mau for update to authenticated
  using (public.has_role(variadic array['admin'])) with check (public.has_role(variadic array['admin']));
drop policy if exists "su_co_mau admin delete" on public.duc_su_co_mau;
create policy "su_co_mau admin delete" on public.duc_su_co_mau for delete to authenticated
  using (public.has_role(variadic array['admin']));

-- Ràng buộc nhẹ: có ít nhất 1 loại, vấn đề không trống.
alter table public.duc_su_co_mau drop constraint if exists duc_su_co_mau_loai_khong_rong;
alter table public.duc_su_co_mau add constraint duc_su_co_mau_loai_khong_rong check (cardinality(loai) > 0);
alter table public.duc_su_co_mau drop constraint if exists duc_su_co_mau_van_de_khong_rong;
alter table public.duc_su_co_mau add constraint duc_su_co_mau_van_de_khong_rong check (btrim(van_de) <> '');

-- Tự cập nhật updated_at + người sửa cuối.
alter table public.duc_su_co_mau add column if not exists nguoi_sua text;
create or replace function public.duc_su_co_mau_cham()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists trg_duc_su_co_mau_cham on public.duc_su_co_mau;
create trigger trg_duc_su_co_mau_cham before insert or update on public.duc_su_co_mau
  for each row execute function public.duc_su_co_mau_cham();
