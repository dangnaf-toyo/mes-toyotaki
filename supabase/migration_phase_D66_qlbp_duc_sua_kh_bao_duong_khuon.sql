-- ============================================================================
-- D66 — Quản lý bộ phận Đúc được lập / sửa / gửi duyệt kế hoạch bảo dưỡng
-- khuôn tuần (như nhân viên bảo dưỡng khuôn), giữ tách người lập / kiểm tra.
--
-- Yêu cầu (user 2026-10-12): cho tài khoản Lê Văn Giang (QLBP Đúc, người KIỂM
-- TRA ở luồng T75 Lập → Kiểm tra → Duyệt) sửa kế hoạch. Prod chưa có tài
-- khoản nhan_vien_bao_duong_khuon nào; Giang là QLBP Đúc duy nhất.
--
--   - duc_khuon_bd_truoc_khi_sua / duc_khuon_bd_gui_duyet: thêm QLBP Đúc.
--   - duc_khuon_bd_xu_ly_duyet bước KIỂM TRA:
--       * QLBP Đúc KHÔNG được kiểm tra kế hoạch tuần mà chính mình đã thêm /
--         sửa / xoá / gửi duyệt (duc_khuon_bd_duyet_log.nguoi = tên mình).
--       * Khi đó admin được kiểm tra thay (chỉ trường hợp kế hoạch tuần có
--         QLBP Đúc tham gia lập/sửa — còn lại admin vẫn không duyệt hộ như T75).
--     Bước PHÊ DUYỆT giữ nguyên (chỉ giam_doc_sx).
--
-- Chạy trên CẢ 2 project. Idempotent (create or replace).
-- ============================================================================

create or replace function duc_khuon_bd_la_nguoi_lap(p_role text, p_bo_phan text[])
returns boolean
language sql
immutable
as $$
  select coalesce(p_role, '') in ('nhan_vien_bao_duong_khuon', 'admin')
      or (p_role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(p_bo_phan, '{}')));
$$;
revoke execute on function duc_khuon_bd_la_nguoi_lap(text, text[]) from public, anon, authenticated;

create or replace function public.duc_khuon_bd_truoc_khi_sua(p_tuan date, p_ly_do text, out o_loi text, out o_ten text)
returns record
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_me record; v_tt text;
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  o_ten := coalesce(v_me.o_ten, '');
  if not duc_khuon_bd_la_nguoi_lap(v_me.o_role, v_me.o_bo_phan) then
    o_loi := 'Chỉ nhân viên bảo dưỡng khuôn / Quản lý bộ phận Đúc được sửa kế hoạch bảo dưỡng'; return;
  end if;
  select trang_thai into v_tt from duc_khuon_bd_duyet where tuan_bat_dau = p_tuan for update;
  if coalesce(v_tt, 'nhap') <> 'nhap' then
    if coalesce(trim(p_ly_do), '') = '' then
      o_loi := 'Kế hoạch đã gửi duyệt — bắt buộc nhập lý do sửa (kế hoạch sẽ phải kiểm tra & duyệt lại)'; return;
    end if;
    update duc_khuon_bd_duyet set trang_thai = 'cho_kiem_tra',
      nguoi_kiem_tra = '', thoi_diem_kiem_tra = null, nguoi_phe_duyet = '', thoi_diem_phe_duyet = null,
      updated_at = now()
    where tuan_bat_dau = p_tuan;
  end if;
end;
$function$;

create or replace function public.duc_khuon_bd_gui_duyet(p_tuan date)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_me record; v_tt text;
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  if not duc_khuon_bd_la_nguoi_lap(v_me.o_role, v_me.o_bo_phan) then
    return jsonb_build_object('ok', false, 'error', 'Chỉ nhân viên bảo dưỡng khuôn / Quản lý bộ phận Đúc (người lập) được gửi duyệt');
  end if;
  if not exists (select 1 from duc_khuon_bd_kh_tuan where tuan_bat_dau = p_tuan) then
    return jsonb_build_object('ok', false, 'error', 'Tuần này chưa có lịch bảo dưỡng nào để gửi duyệt');
  end if;
  insert into duc_khuon_bd_duyet (tuan_bat_dau) values (p_tuan) on conflict do nothing;
  select trang_thai into v_tt from duc_khuon_bd_duyet where tuan_bat_dau = p_tuan for update;
  if v_tt <> 'nhap' then
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch đã gửi duyệt rồi');
  end if;
  update duc_khuon_bd_duyet set trang_thai = 'cho_kiem_tra',
    nguoi_lap = v_me.o_ten, thoi_diem_lap = now(),
    nguoi_kiem_tra = '', thoi_diem_kiem_tra = null, nguoi_phe_duyet = '', thoi_diem_phe_duyet = null,
    nguoi_tu_choi = '', thoi_diem_tu_choi = null, ly_do_tu_choi = '', updated_at = now()
  where tuan_bat_dau = p_tuan;
  insert into duc_khuon_bd_duyet_log (tuan_bat_dau, su_kien, nguoi) values (p_tuan, 'gui_duyet', v_me.o_ten);
  return jsonb_build_object('ok', true, 'trang_thai_moi', 'cho_kiem_tra');
end;
$function$;

-- Kế hoạch tuần có QLBP Đúc tham gia lập/sửa → trả tên những người đó.
create or replace function duc_khuon_bd_qlbp_da_lap(p_tuan date)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(distinct l.nguoi), '{}')
  from duc_khuon_bd_duyet_log l
  join user_roles u on coalesce(nullif(trim(u.full_name), ''), nullif(trim(u.username), ''), u.email, '') = l.nguoi
  where l.tuan_bat_dau = p_tuan
    and l.su_kien in ('them', 'sua', 'xoa', 'gui_duyet')
    and u.role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(u.bo_phan_phu_trach, '{}'));
$$;
revoke execute on function duc_khuon_bd_qlbp_da_lap(date) from public, anon, authenticated;

create or replace function public.duc_khuon_bd_xu_ly_duyet(p_tuan date, p_dong_y boolean, p_ly_do text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_me record; v_tt text; v_moi text; v_qlbp_lap text[];
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  select trang_thai into v_tt from duc_khuon_bd_duyet where tuan_bat_dau = p_tuan for update;
  if v_tt is null or v_tt not in ('cho_kiem_tra', 'cho_phe_duyet') then
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch không ở trạng thái chờ kiểm tra/phê duyệt');
  end if;
  if v_tt = 'cho_kiem_tra' then
    v_qlbp_lap := duc_khuon_bd_qlbp_da_lap(p_tuan);
    if coalesce(v_me.o_role, '') = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(v_me.o_bo_phan, '{}')) then
      if v_me.o_ten = any(v_qlbp_lap) then
        return jsonb_build_object('ok', false, 'error', 'Bạn đã lập / sửa kế hoạch tuần này nên không tự kiểm tra được — admin kiểm tra thay');
      end if;
    elsif coalesce(v_me.o_role, '') = 'admin' then
      if cardinality(v_qlbp_lap) = 0 then
        return jsonb_build_object('ok', false, 'error', 'Chỉ Quản lý bộ phận Đúc được kiểm tra bước này');
      end if;
    else
      return jsonb_build_object('ok', false, 'error', 'Chỉ Quản lý bộ phận Đúc được kiểm tra bước này');
    end if;
  end if;
  if v_tt = 'cho_phe_duyet' and coalesce(v_me.o_role, '') <> 'giam_doc_sx' then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Giám đốc sản xuất được phê duyệt bước này');
  end if;

  if not p_dong_y then
    if coalesce(trim(p_ly_do), '') = '' then
      return jsonb_build_object('ok', false, 'error', 'Cần nhập lý do từ chối');
    end if;
    update duc_khuon_bd_duyet set trang_thai = 'nhap',
      nguoi_kiem_tra = '', thoi_diem_kiem_tra = null, nguoi_phe_duyet = '', thoi_diem_phe_duyet = null,
      nguoi_tu_choi = v_me.o_ten, thoi_diem_tu_choi = now(), ly_do_tu_choi = trim(p_ly_do), updated_at = now()
    where tuan_bat_dau = p_tuan;
    insert into duc_khuon_bd_duyet_log (tuan_bat_dau, su_kien, noi_dung, ly_do, nguoi)
    values (p_tuan, 'tu_choi', case when v_tt = 'cho_kiem_tra' then 'Bước kiểm tra' else 'Bước phê duyệt' end, trim(p_ly_do), v_me.o_ten);
    return jsonb_build_object('ok', true, 'trang_thai_moi', 'nhap');
  end if;

  if v_tt = 'cho_kiem_tra' then
    v_moi := 'cho_phe_duyet';
    update duc_khuon_bd_duyet set trang_thai = v_moi, nguoi_kiem_tra = v_me.o_ten, thoi_diem_kiem_tra = now(), updated_at = now()
    where tuan_bat_dau = p_tuan;
  else
    v_moi := 'da_duyet';
    update duc_khuon_bd_duyet set trang_thai = v_moi, nguoi_phe_duyet = v_me.o_ten, thoi_diem_phe_duyet = now(), updated_at = now()
    where tuan_bat_dau = p_tuan;
  end if;
  insert into duc_khuon_bd_duyet_log (tuan_bat_dau, su_kien, ly_do, nguoi)
  values (p_tuan, case when v_tt = 'cho_kiem_tra' then 'kiem_tra' else 'phe_duyet' end, coalesce(trim(p_ly_do), ''), v_me.o_ten);
  return jsonb_build_object('ok', true, 'trang_thai_moi', v_moi);
end;
$function$;
