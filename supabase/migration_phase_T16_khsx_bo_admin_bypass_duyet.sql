-- ============================================================================
-- Phase T16 — Bỏ quyền "admin luôn được duyệt" khỏi khsx_duyet/khsx_tu_choi.
--
-- Trước đây (T11) admin được coi là bypass mọi bước duyệt KHSX tuần, theo
-- đúng pattern chung "admin luôn được phép" dùng ở các trang quản trị khác.
-- User yêu cầu THU HẸP lại riêng cho việc DUYỆT/TỪ CHỐI kế hoạch: chỉ đúng
-- vai trò kiểm tra của từng bước (Trưởng phòng QLSX / Quản lý bộ phận /
-- Giám đốc sản xuất) mới được duyệt — admin không còn tự duyệt hộ được nữa.
--
-- KHÔNG đụng khsx_gui_duyet (Gửi duyệt) — đó là hành động của nhân viên/
-- trưởng phòng QLSX, không phải bước "kiểm tra", admin vẫn được gửi hộ khi
-- cần như trước.
-- ============================================================================

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
    if coalesce(v_role,'') <> 'qlsx_truong_phong' then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Trưởng phòng QLSX được duyệt bước này');
    end if;
    v_buoc := 'duyet_truong_phong'; v_moi := 'cho_quan_ly_bo_phan';
  elsif v_trang_thai = 'cho_quan_ly_bo_phan' then
    if not (v_role = 'quan_ly_bo_phan' and v_bp = p_cong_doan) then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Quản lý bộ phận ' || p_cong_doan || ' được duyệt bước này');
    end if;
    v_buoc := 'duyet_quan_ly_bo_phan'; v_moi := 'cho_giam_doc';
  elsif v_trang_thai = 'cho_giam_doc' then
    if coalesce(v_role,'') <> 'giam_doc_sx' then
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
    if coalesce(v_role,'') <> 'qlsx_truong_phong' then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Trưởng phòng QLSX được từ chối bước này');
    end if;
  elsif v_trang_thai = 'cho_quan_ly_bo_phan' then
    if not (v_role = 'quan_ly_bo_phan' and v_bp = p_cong_doan) then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Quản lý bộ phận ' || p_cong_doan || ' được từ chối bước này');
    end if;
  elsif v_trang_thai = 'cho_giam_doc' then
    if coalesce(v_role,'') <> 'giam_doc_sx' then
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
