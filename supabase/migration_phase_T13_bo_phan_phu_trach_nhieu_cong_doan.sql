-- ============================================================================
-- Phase T13 — Quản lý bộ phận có thể phụ trách NHIỀU công đoạn cùng lúc.
--
-- Thực tế: quản lý Gia Công và Sơn là CÙNG 1 người. bo_phan_phu_trach (thêm
-- ở migration_phase_T11) đang là 1 giá trị text đơn — đổi sang mảng text[]
-- để 1 tài khoản quan_ly_bo_phan có thể chọn >1 công đoạn (VD ['Gia Công',
-- 'Sơn']). Trưởng phòng QLSX vẫn kiểm tra TẤT CẢ công đoạn như cũ (không có
-- bo_phan_phu_trach, không cần đổi gì ở role đó).
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent) —
-- trừ bước đổi kiểu cột chỉ chạy khi cột còn đang là text (không phải mảng).
-- ============================================================================

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'user_roles'
      and column_name = 'bo_phan_phu_trach' and data_type <> 'ARRAY'
  ) then
    alter table public.user_roles drop constraint if exists user_roles_bo_phan_phu_trach_check;
    alter table public.user_roles
      alter column bo_phan_phu_trach type text[]
      using (case when bo_phan_phu_trach is null or bo_phan_phu_trach = '' then null else array[bo_phan_phu_trach] end);
  end if;
end $$;

alter table public.user_roles drop constraint if exists user_roles_bo_phan_phu_trach_check;
alter table public.user_roles add constraint user_roles_bo_phan_phu_trach_check check (
  bo_phan_phu_trach is null or bo_phan_phu_trach <@ array['Đúc','Bavia','Gia Công','Sơn','OQC']::text[]
);

-- RPC khsx_duyet/khsx_tu_choi (migration_phase_T11) — đổi điều kiện so khớp
-- bộ phận từ "=" (1 giá trị) sang "= ANY(...)" (nằm trong mảng phụ trách).
create or replace function khsx_duyet(p_tuan date, p_cong_doan text, p_user text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text; v_bp text[]; v_trang_thai text; v_buoc text; v_moi text;
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
    if not (v_role = 'admin' or (v_role = 'quan_ly_bo_phan' and p_cong_doan = any(v_bp))) then
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

create or replace function khsx_tu_choi(p_tuan date, p_cong_doan text, p_ly_do text, p_user text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text; v_bp text[]; v_trang_thai text;
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
    if not (v_role = 'admin' or (v_role = 'quan_ly_bo_phan' and p_cong_doan = any(v_bp))) then
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
