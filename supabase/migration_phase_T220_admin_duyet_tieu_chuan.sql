-- T220: STAGING only. Admin can perform every existing standards approval step.
-- Preserve current approval/locking/effective dates/identity for every other role.
begin;
CREATE OR REPLACE FUNCTION public.ipqc_tc_duyet(p_loai text, p_id bigint, p_hanh_dong text, p_ly_do text, p_nguoi text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tt text;
  v_ma text;
  v_cd text;
  v_moi text;
  v_ly_do text := nullif(trim(coalesce(p_ly_do, '')), '');
  v_hom_nay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  b ipqc_btk%rowtype;
  c duc_ipqc_tieuchuan_de_xuat%rowtype;
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
  select coalesce(nullif(full_name,''),username) into p_nguoi from user_roles where user_id=auth.uid();
  if p_loai = 'btk' then
    select * into b from ipqc_btk where id = p_id for update;
    v_tt := b.trang_thai; v_ma := b.ma_sp; v_cd := b.cong_doan;
  elsif p_loai = 'checklist' then
    select * into c from duc_ipqc_tieuchuan_de_xuat where id = p_id for update;
    v_tt := c.trang_thai; v_ma := c.ma_sp; v_cd := c.cong_doan;
  else
    return jsonb_build_object('ok', false, 'error', 'Loại tiêu chuẩn không hợp lệ');
  end if;
  if v_ma is null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy bản tiêu chuẩn #' || p_id); end if;

  if p_hanh_dong = 'kiem_tra' then
    if v_tt <> 'cho_kiem_tra' then return jsonb_build_object('ok', false, 'error', 'Bản này không ở bước chờ kiểm tra'); end if;
    if not public.has_role('qc_manager','admin') then return jsonb_build_object('ok', false, 'error', 'Chỉ Trưởng phòng QC hoặc Admin được kiểm tra'); end if;
    v_moi := 'cho_phe_duyet';
  elsif p_hanh_dong = 'phe_duyet' then
    if v_tt <> 'cho_phe_duyet' then return jsonb_build_object('ok', false, 'error', 'Bản này chưa được Trưởng phòng QC kiểm tra'); end if;
    if not public.has_role('giam_doc_sx','admin') then return jsonb_build_object('ok', false, 'error', 'Chỉ Giám đốc sản xuất hoặc Admin được phê duyệt'); end if;
    v_moi := 'da_duyet';
  elsif p_hanh_dong = 'tra_lai' then
    if v_tt = 'cho_kiem_tra' and not public.has_role('qc_manager','admin') then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Trưởng phòng QC hoặc Admin được trả lại ở bước kiểm tra');
    elsif v_tt = 'cho_phe_duyet' and not public.has_role('giam_doc_sx','admin') then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Giám đốc sản xuất hoặc Admin được trả lại ở bước phê duyệt');
    elsif v_tt not in ('cho_kiem_tra', 'cho_phe_duyet') then
      return jsonb_build_object('ok', false, 'error', 'Bản này không ở bước chờ duyệt');
    end if;
    if v_ly_do is null then return jsonb_build_object('ok', false, 'error', 'Nhập lý do trả lại'); end if;
    v_moi := 'tra_lai';
  else
    return jsonb_build_object('ok', false, 'error', 'Thao tác không hợp lệ');
  end if;

  if p_loai = 'btk' then
    if v_moi = 'da_duyet' then
      perform pg_advisory_xact_lock(hashtext('ipqc_btk:' || v_cd || ':' || v_ma));
      update ipqc_btk set dang_dung = false where ma_sp = v_ma and cong_doan = v_cd and dang_dung and(v_cd<>'gia_cong' or buoc_gia_cong is not distinct from b.buoc_gia_cong);
    end if;
    update ipqc_btk set
      trang_thai = v_moi,
      dang_dung = (v_moi = 'da_duyet'),
      ngay_hieu_luc = case when v_moi = 'da_duyet' then greatest(coalesce(ngay_hieu_luc, v_hom_nay), v_hom_nay) else ngay_hieu_luc end,
      nguoi_kiem_tra = case when p_hanh_dong = 'kiem_tra' then p_nguoi else nguoi_kiem_tra end,
      nguoi_kiem_tra_uid = case when p_hanh_dong = 'kiem_tra' then auth.uid() else nguoi_kiem_tra_uid end,
      kiem_tra_luc = case when p_hanh_dong = 'kiem_tra' then now() else kiem_tra_luc end,
      nguoi_phe_duyet = case when p_hanh_dong = 'phe_duyet' then p_nguoi else nguoi_phe_duyet end,
      nguoi_phe_duyet_uid = case when p_hanh_dong = 'phe_duyet' then auth.uid() else nguoi_phe_duyet_uid end,
      phe_duyet_luc = case when p_hanh_dong = 'phe_duyet' then now() else phe_duyet_luc end,
      ly_do_tra_lai = case when p_hanh_dong = 'tra_lai' then v_ly_do else ly_do_tra_lai end,
      nguoi_tra_lai = case when p_hanh_dong = 'tra_lai' then p_nguoi else nguoi_tra_lai end,
      tra_lai_luc = case when p_hanh_dong = 'tra_lai' then now() else tra_lai_luc end
    where id = p_id;
  else
    update duc_ipqc_tieuchuan_de_xuat set
      trang_thai = v_moi,
      nguoi_kiem_tra = case when p_hanh_dong = 'kiem_tra' then p_nguoi else nguoi_kiem_tra end,
      nguoi_kiem_tra_uid = case when p_hanh_dong = 'kiem_tra' then auth.uid() else nguoi_kiem_tra_uid end,
      kiem_tra_luc = case when p_hanh_dong = 'kiem_tra' then now() else kiem_tra_luc end,
      nguoi_phe_duyet = case when p_hanh_dong = 'phe_duyet' then p_nguoi else nguoi_phe_duyet end,
      nguoi_phe_duyet_uid = case when p_hanh_dong = 'phe_duyet' then auth.uid() else nguoi_phe_duyet_uid end,
      phe_duyet_luc = case when p_hanh_dong = 'phe_duyet' then now() else phe_duyet_luc end,
      ly_do_tra_lai = case when p_hanh_dong = 'tra_lai' then v_ly_do else ly_do_tra_lai end,
      nguoi_tra_lai = case when p_hanh_dong = 'tra_lai' then p_nguoi else nguoi_tra_lai end,
      tra_lai_luc = case when p_hanh_dong = 'tra_lai' then now() else tra_lai_luc end
    where id = p_id;
    if v_moi = 'da_duyet' then
      insert into duc_ipqc_tieuchuan (ma_sp, cong_doan, danh_sach_muc_kiem_json, file_pdf_url, cap_nhat_lan_cuoi_boi, thoi_diem_cap_nhat)
      values (v_ma, v_cd, c.danh_sach_muc_kiem_json, c.file_pdf_url, c.nguoi_lap, now())
      on conflict (ma_sp, cong_doan) do update set
        danh_sach_muc_kiem_json = excluded.danh_sach_muc_kiem_json, file_pdf_url = excluded.file_pdf_url,
        cap_nhat_lan_cuoi_boi = excluded.cap_nhat_lan_cuoi_boi, thoi_diem_cap_nhat = excluded.thoi_diem_cap_nhat;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'trang_thai', v_moi);
end $function$;
revoke all on function public.ipqc_tc_duyet(text,bigint,text,text,text) from public,anon;
grant execute on function public.ipqc_tc_duyet(text,bigint,text,text,text) to authenticated;
commit;
