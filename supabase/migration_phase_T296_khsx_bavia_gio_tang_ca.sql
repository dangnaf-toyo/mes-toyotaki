-- T296: KHSX tuần Bavia — dòng "Giờ tăng ca dự kiến" mỗi ngày (giống Số ca làm việc của Đúc).
-- Bảng khoá (tuần, công đoạn) để sau dùng được cho công đoạn khác; giao diện hiện chỉ bật ở tab Bavia.
create table if not exists public.cd_khsx_tuan_tang_ca (
  tuan_bat_dau date not null,
  cong_doan    text not null,
  t2 numeric(4,1) not null default 0 check (t2 between 0 and 24),
  t3 numeric(4,1) not null default 0 check (t3 between 0 and 24),
  t4 numeric(4,1) not null default 0 check (t4 between 0 and 24),
  t5 numeric(4,1) not null default 0 check (t5 between 0 and 24),
  t6 numeric(4,1) not null default 0 check (t6 between 0 and 24),
  t7 numeric(4,1) not null default 0 check (t7 between 0 and 24),
  cn numeric(4,1) not null default 0 check (cn between 0 and 24),
  updated_by text default '',
  updated_at timestamptz not null default now(),
  primary key (tuan_bat_dau, cong_doan)
);

alter table public.cd_khsx_tuan_tang_ca enable row level security;
revoke all on public.cd_khsx_tuan_tang_ca from anon;
grant select on public.cd_khsx_tuan_tang_ca to anon;
grant select, insert, update, delete on public.cd_khsx_tuan_tang_ca to authenticated;

drop policy if exists "khsx_tang_ca read" on public.cd_khsx_tuan_tang_ca;
create policy "khsx_tang_ca read" on public.cd_khsx_tuan_tang_ca for select to public using (true);

drop policy if exists "khsx_tang_ca write" on public.cd_khsx_tuan_tang_ca;
create policy "khsx_tang_ca write" on public.cd_khsx_tuan_tang_ca for insert to authenticated
  with check (has_role(variadic array['admin','giam_doc_sx','qlsx_nhan_vien','qlsx_truong_phong','ke_hoach','quan_ly_bo_phan']));

drop policy if exists "khsx_tang_ca update" on public.cd_khsx_tuan_tang_ca;
create policy "khsx_tang_ca update" on public.cd_khsx_tuan_tang_ca for update to authenticated
  using (has_role(variadic array['admin','giam_doc_sx','qlsx_nhan_vien','qlsx_truong_phong','ke_hoach','quan_ly_bo_phan']))
  with check (has_role(variadic array['admin','giam_doc_sx','qlsx_nhan_vien','qlsx_truong_phong','ke_hoach','quan_ly_bo_phan']));

drop policy if exists "khsx_tang_ca delete" on public.cd_khsx_tuan_tang_ca;
create policy "khsx_tang_ca delete" on public.cd_khsx_tuan_tang_ca for delete to authenticated
  using (has_role(variadic array['admin','giam_doc_sx','qlsx_nhan_vien','qlsx_truong_phong','ke_hoach','quan_ly_bo_phan']));
