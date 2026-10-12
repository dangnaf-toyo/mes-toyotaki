-- ============================================================================
-- D67 — QLBP Đúc được KIỂM TRA cả kế hoạch bảo dưỡng khuôn tuần do chính mình
-- lập / sửa (user 2026-10-12 chọn bỏ chặn "người lập không tự kiểm tra" của
-- D66: Lê Văn Giang vừa lập vừa kiểm tra; Giám đốc SX phê duyệt độc lập).
--
-- Bước kiểm tra trở lại đúng quy tắc T75: chỉ Quản lý bộ phận Đúc (bỏ ngoại
-- lệ "admin kiểm tra thay" của D66 vì không còn trường hợp bị chặn) → bỏ hàm
-- trợ giúp duc_khuon_bd_qlbp_da_lap. Quyền lập / sửa / gửi của QLBP Đúc (D66)
-- giữ nguyên. Phê duyệt vẫn chỉ giam_doc_sx.
--
-- Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

create or replace function public.duc_khuon_bd_xu_ly_duyet(p_tuan date, p_dong_y boolean, p_ly_do text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_me record; v_tt text; v_moi text;
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  select trang_thai into v_tt from duc_khuon_bd_duyet where tuan_bat_dau = p_tuan for update;
  if v_tt is null or v_tt not in ('cho_kiem_tra', 'cho_phe_duyet') then
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch không ở trạng thái chờ kiểm tra/phê duyệt');
  end if;
  if v_tt = 'cho_kiem_tra' and not (coalesce(v_me.o_role, '') = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(v_me.o_bo_phan, '{}'))) then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Quản lý bộ phận Đúc được kiểm tra bước này');
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

drop function if exists duc_khuon_bd_qlbp_da_lap(date);
