-- ============================================================================
-- Phase T11 — Quy trình phê duyệt KHSX tuần.
--
-- Lộ trình (tách riêng theo TỪNG CÔNG ĐOẠN — Đúc/Bavia/Gia Công/Sơn/OQC mỗi
-- công đoạn có trạng thái duyệt độc lập, không chờ nhau):
--   nhap (nháp, nhân viên QLSX tự sửa thoải mái)
--   -> cho_truong_phong   (Trưởng phòng QLSX kiểm tra)
--   -> cho_quan_ly_bo_phan (Quản lý ĐÚNG bộ phận đó kiểm tra)
--   -> cho_giam_doc        (Giám đốc sản xuất duyệt)
--   -> da_duyet
-- Mỗi bước có thể "Từ chối" kèm lý do bắt buộc -> quay về 'nhap'.
-- Sửa 1 dòng bất kỳ khi trạng thái đã qua 'nhap' (đang chờ duyệt hoặc đã
-- duyệt xong) -> BẮT BUỘC nhập lý do, tự quay về 'cho_truong_phong' (duyệt
-- lại từ đầu lộ trình). Sửa khi đang 'nhap' thì không bắt buộc lý do.
--
-- Vai trò MỚI (user_roles.role): qlsx_nhan_vien, qlsx_truong_phong,
-- quan_ly_bo_phan (cần user_roles.bo_phan_phu_trach = đúng 1 trong 5 công
-- đoạn), giam_doc_sx. 'admin' luôn được phép ở mọi bước (đúng pattern gate
-- theo has_role() đã dùng cho các trang quản trị khác).
-- ============================================================================

-- 1) Mở rộng vai trò + thêm cột "bộ phận phụ trách" -------------------------
alter table public.user_roles add column if not exists bo_phan_phu_trach text;

alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check (
  role in (
    'admin','truong_ca','ipqc','qc_manager','kho_nvl','ke_hoach',
    'qlsx_nhan_vien','qlsx_truong_phong','quan_ly_bo_phan','giam_doc_sx'
  )
);

alter table public.user_roles drop constraint if exists user_roles_bo_phan_phu_trach_check;
alter table public.user_roles add constraint user_roles_bo_phan_phu_trach_check check (
  bo_phan_phu_trach is null or bo_phan_phu_trach in ('Đúc','Bavia','Gia Công','Sơn','OQC')
);

-- 2) Trạng thái duyệt theo (tuần, công đoạn) ---------------------------------
create table if not exists khsx_duyet (
  id            bigserial primary key,
  tuan_bat_dau  date not null,
  cong_doan     text not null check (cong_doan in ('Đúc','Bavia','Gia Công','Sơn','OQC')),
  trang_thai    text not null default 'nhap' check (
    trang_thai in ('nhap','cho_truong_phong','cho_quan_ly_bo_phan','cho_giam_doc','da_duyet')
  ),
  updated_by    text default '',
  updated_at    timestamptz not null default now(),
  unique (tuan_bat_dau, cong_doan)
);

alter table khsx_duyet enable row level security;
drop policy if exists "khsx_duyet public read" on khsx_duyet;
create policy "khsx_duyet public read" on khsx_duyet for select using (true);
-- KHÔNG cấp insert/update/delete trực tiếp cho authenticated — mọi thay đổi
-- trạng thái PHẢI đi qua các hàm RPC bên dưới (security definer) để ép đúng
-- vai trò từng bước, tránh 1 tài khoản tự sửa thẳng bảng để "tự duyệt".

-- 3) Lịch sử thay đổi + duyệt/từ chối ---------------------------------------
create table if not exists khsx_thay_doi_log (
  id              bigserial primary key,
  tuan_bat_dau    date not null,
  cong_doan       text not null,
  loai_su_kien    text not null check (loai_su_kien in (
    'them_moi','sua','xoa','gui_duyet',
    'duyet_truong_phong','duyet_quan_ly_bo_phan','duyet_giam_doc','tu_choi'
  )),
  vi_tri          text default '',   -- VD "Máy DC6 — Mã SP OKA-01" / "Mã SP OKA-01"
  gia_tri_cu      text default '',
  gia_tri_moi     text default '',
  ly_do           text default '',
  nguoi_thuc_hien text default '',
  thoi_diem       timestamptz not null default now()
);
create index if not exists idx_khsx_log_tuan_cd on khsx_thay_doi_log (tuan_bat_dau, cong_doan, thoi_diem desc);

alter table khsx_thay_doi_log enable row level security;
drop policy if exists "khsx_log public read" on khsx_thay_doi_log;
create policy "khsx_log public read" on khsx_thay_doi_log for select using (true);
-- Cũng KHÔNG cấp ghi trực tiếp — chỉ ghi qua RPC, để log luôn khớp đúng hành
-- động thật đã xảy ra (không ai tự chèn log giả).

-- 4) RPC: Gửi duyệt (nhân viên QLSX / trưởng phòng / admin) -----------------
create or replace function khsx_gui_duyet(p_tuan date, p_cong_doan text, p_user text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_trang_thai text;
begin
  select role into v_role from public.user_roles where user_id = auth.uid();
  if v_role is null or v_role not in ('qlsx_nhan_vien','qlsx_truong_phong','admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Nhân viên QLSX (hoặc Trưởng phòng/Admin) được gửi duyệt');
  end if;

  insert into khsx_duyet (tuan_bat_dau, cong_doan, trang_thai, updated_by, updated_at)
  values (p_tuan, p_cong_doan, 'cho_truong_phong', p_user, now())
  on conflict (tuan_bat_dau, cong_doan) do update
    set trang_thai = case when khsx_duyet.trang_thai = 'nhap' then 'cho_truong_phong' else khsx_duyet.trang_thai end,
        updated_by = p_user, updated_at = now()
  returning trang_thai into v_trang_thai;

  if v_trang_thai <> 'cho_truong_phong' then
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch đã gửi duyệt rồi (trạng thái hiện tại: ' || v_trang_thai || ')');
  end if;

  insert into khsx_thay_doi_log (tuan_bat_dau, cong_doan, loai_su_kien, nguoi_thuc_hien)
  values (p_tuan, p_cong_doan, 'gui_duyet', p_user);

  return jsonb_build_object('ok', true, 'trang_thai_moi', v_trang_thai);
end;
$$;
revoke execute on function khsx_gui_duyet(date, text, text) from anon;
grant execute on function khsx_gui_duyet(date, text, text) to authenticated;

-- 5) RPC: Duyệt bước hiện tại (đúng vai trò của đúng bước mới được duyệt) ---
create or replace function khsx_duyet(p_tuan date, p_cong_doan text, p_user text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text; v_bp text; v_trang_thai text; v_buoc text; v_moi text;
begin
  select role, bo_phan_phu_trach into v_role, v_bp from public.user_roles where user_id = auth.uid();
  select trang_thai into v_trang_thai from khsx_duyet where tuan_bat_dau = p_tuan and cong_doan = p_cong_doan;
  if v_trang_thai is null then
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch chưa được gửi duyệt');
  end if;

  if v_trang_thai = 'cho_truong_phong' then
    if coalesce(v_role,'') not in ('qlsx_truong_phong','admin') then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Trưởng phòng QLSX được duyệt bước này');
    end if;
    v_buoc := 'duyet_truong_phong'; v_moi := 'cho_quan_ly_bo_phan';
  elsif v_trang_thai = 'cho_quan_ly_bo_phan' then
    if not (v_role = 'admin' or (v_role = 'quan_ly_bo_phan' and v_bp = p_cong_doan)) then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Quản lý bộ phận ' || p_cong_doan || ' được duyệt bước này');
    end if;
    v_buoc := 'duyet_quan_ly_bo_phan'; v_moi := 'cho_giam_doc';
  elsif v_trang_thai = 'cho_giam_doc' then
    if coalesce(v_role,'') not in ('giam_doc_sx','admin') then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Giám đốc sản xuất được duyệt bước này');
    end if;
    v_buoc := 'duyet_giam_doc'; v_moi := 'da_duyet';
  else
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch không ở trạng thái chờ duyệt (' || v_trang_thai || ')');
  end if;

  update khsx_duyet set trang_thai = v_moi, updated_by = p_user, updated_at = now()
  where tuan_bat_dau = p_tuan and cong_doan = p_cong_doan;

  insert into khsx_thay_doi_log (tuan_bat_dau, cong_doan, loai_su_kien, nguoi_thuc_hien)
  values (p_tuan, p_cong_doan, v_buoc, p_user);

  return jsonb_build_object('ok', true, 'trang_thai_moi', v_moi);
end;
$$;
revoke execute on function khsx_duyet(date, text, text) from anon;
grant execute on function khsx_duyet(date, text, text) to authenticated;

-- 6) RPC: Từ chối bước hiện tại (bắt buộc lý do) -> quay về 'nhap' ----------
create or replace function khsx_tu_choi(p_tuan date, p_cong_doan text, p_ly_do text, p_user text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text; v_bp text; v_trang_thai text;
begin
  if p_ly_do is null or trim(p_ly_do) = '' then
    return jsonb_build_object('ok', false, 'error', 'Cần nhập lý do từ chối');
  end if;

  select role, bo_phan_phu_trach into v_role, v_bp from public.user_roles where user_id = auth.uid();
  select trang_thai into v_trang_thai from khsx_duyet where tuan_bat_dau = p_tuan and cong_doan = p_cong_doan;
  if v_trang_thai is null then
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch chưa được gửi duyệt');
  end if;

  if v_trang_thai = 'cho_truong_phong' then
    if coalesce(v_role,'') not in ('qlsx_truong_phong','admin') then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Trưởng phòng QLSX được từ chối bước này');
    end if;
  elsif v_trang_thai = 'cho_quan_ly_bo_phan' then
    if not (v_role = 'admin' or (v_role = 'quan_ly_bo_phan' and v_bp = p_cong_doan)) then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Quản lý bộ phận ' || p_cong_doan || ' được từ chối bước này');
    end if;
  elsif v_trang_thai = 'cho_giam_doc' then
    if coalesce(v_role,'') not in ('giam_doc_sx','admin') then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Giám đốc sản xuất được từ chối bước này');
    end if;
  else
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch không ở trạng thái chờ duyệt (' || v_trang_thai || ')');
  end if;

  update khsx_duyet set trang_thai = 'nhap', updated_by = p_user, updated_at = now()
  where tuan_bat_dau = p_tuan and cong_doan = p_cong_doan;

  insert into khsx_thay_doi_log (tuan_bat_dau, cong_doan, loai_su_kien, ly_do, nguoi_thuc_hien)
  values (p_tuan, p_cong_doan, 'tu_choi', p_ly_do, p_user);

  return jsonb_build_object('ok', true, 'trang_thai_moi', 'nhap');
end;
$$;
revoke execute on function khsx_tu_choi(date, text, text, text) from anon;
grant execute on function khsx_tu_choi(date, text, text, text) to authenticated;

-- 7) RPC: Ghi log 1 lần sửa (thêm/sửa/xoá dòng KHSX) + tự quay về đầu lộ
--    trình nếu kế hoạch đã gửi duyệt/đã duyệt xong (bắt buộc lý do lúc đó).
create or replace function khsx_ghi_log_sua(
  p_tuan date, p_cong_doan text, p_loai text, p_vi_tri text,
  p_gia_tri_cu text, p_gia_tri_moi text, p_ly_do text, p_user text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trang_thai text;
  v_reset boolean := false;
begin
  if p_loai not in ('them_moi','sua','xoa') then
    return jsonb_build_object('ok', false, 'error', 'Loại thay đổi không hợp lệ: ' || p_loai);
  end if;

  select trang_thai into v_trang_thai from khsx_duyet where tuan_bat_dau = p_tuan and cong_doan = p_cong_doan;

  if v_trang_thai is not null and v_trang_thai <> 'nhap' then
    if p_ly_do is null or trim(p_ly_do) = '' then
      return jsonb_build_object('ok', false, 'error', 'Kế hoạch đã gửi duyệt/đã duyệt — bắt buộc nhập lý do khi sửa');
    end if;
    update khsx_duyet set trang_thai = 'cho_truong_phong', updated_by = p_user, updated_at = now()
    where tuan_bat_dau = p_tuan and cong_doan = p_cong_doan;
    v_reset := true;
  end if;

  insert into khsx_thay_doi_log (tuan_bat_dau, cong_doan, loai_su_kien, vi_tri, gia_tri_cu, gia_tri_moi, ly_do, nguoi_thuc_hien)
  values (p_tuan, p_cong_doan, p_loai, coalesce(p_vi_tri,''), coalesce(p_gia_tri_cu,''), coalesce(p_gia_tri_moi,''), coalesce(p_ly_do,''), p_user);

  return jsonb_build_object('ok', true, 'reset_ve_dau', v_reset);
end;
$$;
revoke execute on function khsx_ghi_log_sua(date, text, text, text, text, text, text, text) from anon;
grant execute on function khsx_ghi_log_sua(date, text, text, text, text, text, text, text) to authenticated;
