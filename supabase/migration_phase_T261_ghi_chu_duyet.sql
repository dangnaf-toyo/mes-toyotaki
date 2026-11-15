-- T261: Mọi màn phê duyệt có ô ghi chú cho người duyệt.
-- Hàm đã lưu được ghi chú khi duyệt (không đổi): bom_duyet (p_ly_do → lịch sử), duc_khuon_bd_xu_ly_duyet (p_ly_do → log),
--   duc_ncp_approve_root_cause / duc_ncp_approve_scrap (p_ghi_chu), duc_khuon_ct_duyet (p_ly_do → nhật ký),
--   dcr_approve_step / dcr_confirm (p_y_kien), duc_ipqc_decide_continue_request / duc_ipqc_decide_ng (p_note).
-- Ở đây: thêm tham số / cột cho các hàm chưa nhận ghi chú khi duyệt.

-- 1) KHSX tuần: khsx_duyet(+p_ghi_chu) → khsx_thay_doi_log.ly_do
drop function if exists public.khsx_duyet(date, text, text);
create function public.khsx_duyet(p_tuan date, p_cong_doan text, p_user text, p_ghi_chu text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role text; v_bp text[]; v_trang_thai text; v_buoc text; v_moi text;
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
    if not (coalesce(v_role,'') = 'quan_ly_bo_phan' and p_cong_doan = any(coalesce(v_bp, '{}'))) then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Quản lý bộ phận ' || p_cong_doan || ' được duyệt bước này');
    end if;
    v_buoc := 'duyet_quan_ly_bo_phan'; v_moi := 'cho_giam_doc';
  elsif v_trang_thai = 'cho_giam_doc' then
    if coalesce(v_role,'') <> 'giam_doc_sx' and not public.has_role('giam_doc_sx') then   -- T211
      return jsonb_build_object('ok', false, 'error', 'Chỉ Giám đốc sản xuất được duyệt bước này');
    end if;
    v_buoc := 'duyet_giam_doc'; v_moi := 'da_duyet';
  else
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch không ở trạng thái chờ duyệt (' || v_trang_thai || ')');
  end if;

  update khsx_duyet set trang_thai = v_moi, updated_by = p_user, updated_at = now()
  where tuan_bat_dau = p_tuan and cong_doan = p_cong_doan;

  insert into khsx_thay_doi_log (tuan_bat_dau, cong_doan, loai_su_kien, ly_do, nguoi_thuc_hien)
  values (p_tuan, p_cong_doan, v_buoc, nullif(btrim(coalesce(p_ghi_chu, '')), ''), p_user);   -- T261

  return jsonb_build_object('ok', true, 'trang_thai_moi', v_moi);
end;
$$;
revoke all on function public.khsx_duyet(date, text, text, text) from public, anon;
grant execute on function public.khsx_duyet(date, text, text, text) to authenticated, service_role;

-- 2) Giao việc: cv_duyet(+p_ghi_chu) → lịch sử + thông báo người làm
drop function if exists public.cv_duyet(bigint);
create function public.cv_duyet(p_id bigint, p_ghi_chu text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v cv_cong_viec; v_gc text := nullif(btrim(coalesce(p_ghi_chu, '')), '');
begin
  v := cv_lay_viec(p_id);
  if not cv_quyen_giao(v.nguoi_giao) then raise exception 'Chỉ người giao việc hoặc Ban giám đốc mới được duyệt.'; end if;
  if v.trang_thai <> 'cho_duyet' then raise exception 'Việc này không ở trạng thái Chờ duyệt.'; end if;
  update cv_cong_viec set trang_thai = 'hoan_thanh', hoan_thanh_luc = now(),
    dung_han = (coalesce(bao_xong_luc, now()) <= han), gia_han_den = null, gia_han_ly_do = null, updated_at = now()
  where id = p_id;
  perform cv_ghi_ls(p_id, 'duyet', cv_ten_nguoi(auth.uid()) || ' đã duyệt hoàn thành ('
                    || case when coalesce(v.bao_xong_luc, now()) <= v.han then 'đúng hạn' else 'trễ hạn' end || ').'
                    || coalesce(' Ghi chú: ' || v_gc, ''));
  perform cv_gui_tb(cv_nguoi_lam_va_ph(p_id), 'hoan_thanh', p_id, null,
                    cv_ten_nguoi(auth.uid()) || ' đã duyệt hoàn thành: ' || v.tieu_de || coalesce(' — ' || v_gc, ''), false);
  perform cv_xong_tb(p_id, null, null);   -- việc đã đóng: hết mọi việc cần xử lý
end;
$$;
revoke all on function public.cv_duyet(bigint, text) from public, anon;
grant execute on function public.cv_duyet(bigint, text) to authenticated, service_role;

-- 3) Giao việc: cv_tra_loi_gia_han(+p_ghi_chu)
drop function if exists public.cv_tra_loi_gia_han(bigint, boolean);
create function public.cv_tra_loi_gia_han(p_id bigint, p_dong_y boolean, p_ghi_chu text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v cv_cong_viec; v_gc text := nullif(btrim(coalesce(p_ghi_chu, '')), '');
begin
  v := cv_lay_viec(p_id);
  if not cv_quyen_giao(v.nguoi_giao) then raise exception 'Chỉ người giao việc hoặc Ban giám đốc mới trả lời gia hạn được.'; end if;
  if v.gia_han_den is null then raise exception 'Không có yêu cầu gia hạn nào đang chờ.'; end if;
  if p_dong_y is null then raise exception 'Hãy chọn đồng ý hoặc không đồng ý.'; end if;
  update cv_cong_viec set han = case when p_dong_y then v.gia_han_den else han end,
    gia_han_den = null, gia_han_ly_do = null, updated_at = now()
  where id = p_id;
  perform cv_ghi_ls(p_id, 'tra_loi_gia_han', cv_ten_nguoi(auth.uid())
                    || case when p_dong_y then ' đồng ý gia hạn đến ' || cv_fmt(v.gia_han_den) || '.'
                            else ' không đồng ý gia hạn, giữ hạn ' || cv_fmt(v.han) || '.' end
                    || coalesce(' Ghi chú: ' || v_gc, ''));
  perform cv_gui_tb(array[v.nguoi_lam], 'tra_loi_gia_han', p_id, null,
                    cv_ten_nguoi(auth.uid()) || case when p_dong_y then ' đồng ý gia hạn "' || v.tieu_de || '" đến ' || cv_fmt(v.gia_han_den)
                                                     else ' không đồng ý gia hạn "' || v.tieu_de || '", hạn vẫn là ' || cv_fmt(v.han) end
                    || coalesce(' — ' || v_gc, ''), false);
  perform cv_xong_tb(p_id, case when p_dong_y then array['xin_gia_han','qua_han'] else array['xin_gia_han'] end, null);
end;
$$;
revoke all on function public.cv_tra_loi_gia_han(bigint, boolean, text) from public, anon;
grant execute on function public.cv_tra_loi_gia_han(bigint, boolean, text) to authenticated, service_role;

-- 4) Tài liệu hệ thống: document_versions.ghi_chu_duyet + doc_approve_version(+p_ghi_chu)
alter table public.document_versions add column if not exists ghi_chu_duyet text;
drop function if exists public.doc_approve_version(uuid);
create function public.doc_approve_version(p_version_id uuid, p_ghi_chu text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_document_id uuid; v_category_id uuid;
begin
  select dv.document_id, d.category_id into v_document_id, v_category_id
  from public.document_versions dv
  join public.documents d on d.id = dv.document_id
  where dv.id = p_version_id;

  if v_document_id is null then
    raise exception 'Không tìm thấy phiên bản tài liệu';
  end if;
  if not public.has_doc_permission(v_category_id, 'write') then
    raise exception 'Không có quyền duyệt tài liệu này';
  end if;

  update public.document_versions set trang_thai = 'da_duyet',
    approved_by = auth.uid(), approved_at = now(),
    ghi_chu_duyet = nullif(btrim(coalesce(p_ghi_chu, '')), '')   -- T261
  where id = p_version_id;

  update public.documents set current_version_id = p_version_id where id = v_document_id;
end;
$$;
revoke all on function public.doc_approve_version(uuid, text) from public, anon;
grant execute on function public.doc_approve_version(uuid, text) to authenticated, service_role;

-- 5) Tài liệu bên ngoài: cột ghi chú khi duyệt / từ chối (trang cập nhật thẳng bảng)
alter table public.external_documents add column if not exists ghi_chu_duyet text;

-- 6) Tiêu chuẩn IPQC (bảng tuần kiểm + checklist): ghi chú khi kiểm tra / phê duyệt (p_ly_do cũ chỉ dùng cho trả lại)
alter table public.ipqc_btk add column if not exists ghi_chu_kiem_tra text, add column if not exists ghi_chu_phe_duyet text;
alter table public.duc_ipqc_tieuchuan_de_xuat add column if not exists ghi_chu_kiem_tra text, add column if not exists ghi_chu_phe_duyet text;

-- Vá chèn (không chép cả thân hàm): staging có bản cho phép admin, prod thì không — giữ nguyên khác biệt đó.
do $$
declare d text; n int;
begin
  select pg_get_functiondef('public.ipqc_tc_duyet(text,bigint,text,text,text)'::regprocedure) into d;
  if position('ghi_chu_kiem_tra' in d) > 0 then return; end if;   -- đã vá
  n := (length(d) - length(replace(d, 'kiem_tra_luc = case when p_hanh_dong = ''kiem_tra'' then now() else kiem_tra_luc end,', ''))) / length('kiem_tra_luc = case when p_hanh_dong = ''kiem_tra'' then now() else kiem_tra_luc end,');
  if n <> 2 then raise exception 'ipqc_tc_duyet: không tìm thấy đúng 2 chỗ chèn (thấy %)', n; end if;
  d := replace(d, 'kiem_tra_luc = case when p_hanh_dong = ''kiem_tra'' then now() else kiem_tra_luc end,',
    'kiem_tra_luc = case when p_hanh_dong = ''kiem_tra'' then now() else kiem_tra_luc end,' || chr(10) ||
    '      ghi_chu_kiem_tra = case when p_hanh_dong = ''kiem_tra'' then v_ly_do else ghi_chu_kiem_tra end,   -- T261');
  d := replace(d, 'phe_duyet_luc = case when p_hanh_dong = ''phe_duyet'' then now() else phe_duyet_luc end,',
    'phe_duyet_luc = case when p_hanh_dong = ''phe_duyet'' then now() else phe_duyet_luc end,' || chr(10) ||
    '      ghi_chu_phe_duyet = case when p_hanh_dong = ''phe_duyet'' then v_ly_do else ghi_chu_phe_duyet end,   -- T261');
  execute d;
end $$;
