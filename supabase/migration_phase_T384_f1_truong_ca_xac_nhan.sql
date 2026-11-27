-- T384: IPQC kiểm NG tự mở sự cố F1 — KHÔNG ghi tên IPQC vào "Người đảm nhiệm" nữa.
-- Để trống đảm nhiệm → Bảng điều khiển Đúc hiện bước "Xác nhận": Trưởng ca xác nhận nội dung
-- bất thường + cử người đảm nhiệm (lưu qua duc_edit_open_incident_x; trigger nhật ký sự cố ghi lại).
-- Chỉ nhắc, không chặn. F1 cũ (đã có tên đảm nhiệm) giữ nguyên.
-- Thêm chuông cho Trưởng ca khi IPQC mở F1.

CREATE OR REPLACE FUNCTION public.duc_submit_ipqc_check(p_id_checkpoint text, p_checklist jsonb, p_ket_qua text, p_anh_urls jsonb, p_ghi_chu text, p_thoi_gian_kiem_giay numeric, p_nguoi_kiem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cp record; v_cht record; v_note text := ''; v_issue_text text; v_vdk_id text; v_open_result jsonb;
  v_all_pass boolean; v_any_fail boolean; v_now timestamptz := now();
begin
  if p_ket_qua not in ('OK', 'NG', 'CANH_BAO') then
    return jsonb_build_object('ok', false, 'error', 'Kết quả phải là OK, NG hoặc CANH_BAO');
  end if;
  if p_anh_urls is null or jsonb_array_length(p_anh_urls) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Bắt buộc có ít nhất 1 ảnh bằng chứng');
  end if;
  if jsonb_array_length(p_anh_urls) > 10 then
    return jsonb_build_object('ok', false, 'error', 'Tối đa 10 ảnh cho 1 lần kiểm tra');
  end if;
  if p_nguoi_kiem is null or trim(p_nguoi_kiem) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu người kiểm');
  end if;

  select
    bool_and((elem->>'dat')::boolean is true) filter (where jsonb_array_length(coalesce(p_checklist,'[]'::jsonb)) > 0)
      and jsonb_array_length(coalesce(p_checklist,'[]'::jsonb)) > 0,
    bool_or((elem->>'dat') = 'false')
  into v_all_pass, v_any_fail
  from jsonb_array_elements(coalesce(p_checklist, '[]'::jsonb)) elem;
  v_all_pass := coalesce(v_all_pass, false);
  v_any_fail := coalesce(v_any_fail, false);

  if p_ket_qua = 'OK' and not v_all_pass then
    return jsonb_build_object('ok', false, 'error', 'Chỉ được chọn OK khi tất cả các mục kiểm đều Đạt');
  end if;
  if p_ket_qua in ('NG', 'CANH_BAO') and not v_any_fail then
    return jsonb_build_object('ok', false, 'error', 'NG / Cảnh báo cần ít nhất 1 mục kiểm Không đạt');
  end if;
  if p_ket_qua in ('NG', 'CANH_BAO') and (p_ghi_chu is null or trim(p_ghi_chu) = '') then
    return jsonb_build_object('ok', false, 'error', 'NG / Cảnh báo bắt buộc phải nhập ghi chú');
  end if;

  select id_dong, ma_may, ma_sp, loai_kiem, id_su_co_goc into v_cp from duc_ipqc_checkpoint where id_checkpoint = p_id_checkpoint;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy checkpoint: ' || p_id_checkpoint); end if;

  if (select trang_thai from duc_ipqc_checkpoint where id_checkpoint = p_id_checkpoint) = 'da_kiem' then
    return jsonb_build_object('ok', false, 'error', 'Điểm kiểm này đã được xử lý trước đó');
  end if;

  update duc_ipqc_checkpoint set
    trang_thai = 'da_kiem', thoi_diem_kiem_thuc_te = now(), nguoi_kiem = p_nguoi_kiem,
    ket_qua = p_ket_qua, checklist_json = coalesce(p_checklist, '[]'::jsonb),
    anh_bang_chung_url = p_anh_urls, thoi_gian_kiem_giay = p_thoi_gian_kiem_giay,
    ghi_chu = coalesce(p_ghi_chu, '')
  where id_checkpoint = p_id_checkpoint;

  update duc_ipqc_checkpoint set trang_thai = 'het_hieu_luc'
  where id_dong = v_cp.id_dong and loai_kiem = 'dinh_ky'
    and trang_thai = 'cho_kiem' and id_checkpoint <> p_id_checkpoint;

  select ngay, ca, so_khuon, open_gio_phat_sinh, open_loai_su_co, open_id_su_co into v_cht from duc_ca_hien_tai where id_dong = v_cp.id_dong;
  if not found then
    return jsonb_build_object('ok', true, 'id_checkpoint', p_id_checkpoint, 'ket_qua', p_ket_qua, 'note', 'Dòng Ca_hien_tai gốc không còn — bỏ qua liên kết ngược.');
  end if;

  v_issue_text := duc_build_ipqc_issue_text(p_ket_qua, v_cp.loai_kiem, p_checklist, p_ghi_chu);

  if p_ket_qua = 'NG' then
    if v_cht.open_gio_phat_sinh is not null then
      v_note := case
        when v_cp.loai_kiem in ('sau_su_co', 'doi_khuon') then 'Không mở thêm sự cố F1 — máy đang dừng vì sự cố chờ IPQC; sự cố đó chỉ kết thúc được khi IPQC kiểm lại OK / Cảnh báo.'
        when left(coalesce(v_cht.open_loai_su_co, ''), 2) = 'F1' then 'Không mở thêm sự cố F1 — máy đã có sự cố F1 đang mở; kết quả NG đã ghi vào lý lịch sự cố đó.'
        else 'Không mở thêm sự cố F1 — máy đang có sự cố khác mở; kết quả NG đã ghi vào lý lịch sự cố đó và báo trưởng ca.' end;
      if v_cht.open_id_su_co is not null and v_cp.id_su_co_goc is distinct from v_cht.open_id_su_co then
        begin
          insert into duc_su_co_nhat_ky (id_su_co, su_kien, id_dong, ngay, ca, du_lieu, nguoi, nguoi_uid, nguon)
          values (v_cht.open_id_su_co, 'ipqc_ng', v_cp.id_dong, v_cht.ngay, v_cht.ca,
                  jsonb_build_object('id_checkpoint', p_id_checkpoint, 'loai_kiem', v_cp.loai_kiem,
                                     'id_su_co_kiem', v_cp.id_su_co_goc, 'noi_dung', v_issue_text),
                  p_nguoi_kiem, auth.uid(), '/rpc/duc_submit_ipqc_check');
          perform cv_pd_gui(cv_pd_ds_role(array['truong_ca']), 'ipqc', 'ipqc_ng_dang_su_co', 'ipqc_ng:' || p_id_checkpoint,
            'duc-dashboard.html',
            '🧪 IPQC kiểm NG máy ' || v_cp.ma_may || ' trong lúc đang có sự cố ' || v_cht.open_id_su_co || ' — ' || left(coalesce(v_issue_text, ''), 200),
            false);
        exception when others then raise warning 'duc_submit_ipqc_check ghi ipqc_ng: %', sqlerrm;
        end;
      end if;
    else
      -- T384: đảm nhiệm để trống — Trưởng ca xác nhận nội dung + cử người.
      v_open_result := duc_set_incident_open(v_cp.id_dong, 'F1', v_now, v_issue_text, '', '');
      if not (v_open_result->>'ok')::boolean then
        v_note := 'Lỗi mở sự cố F1 tự động: ' || (v_open_result->>'error');
      else
        begin
          perform cv_pd_gui(cv_pd_ds_role(array['truong_ca']), 'ipqc', 'ipqc_ng_f1', 'ipqc_f1:' || p_id_checkpoint,
            'duc-dashboard.html',
            '🧪 IPQC ' || p_nguoi_kiem || ' kiểm NG máy ' || v_cp.ma_may || ' → mở sự cố F1. Trưởng ca xác nhận và cử người xử lý — ' || left(coalesce(v_issue_text, ''), 200),
            false);
        exception when others then raise warning 'duc_submit_ipqc_check chuông F1: %', sqlerrm;
        end;
      end if;
    end if;
    if v_cht.so_khuon is not null and v_cht.so_khuon <> '' then
      v_vdk_id := duc_report_mold_issue(v_cht.so_khuon, v_cp.ma_may, v_cp.ma_sp, v_issue_text, p_nguoi_kiem, v_cht.ngay, v_cht.ca);
      update duc_ipqc_checkpoint set id_van_de_lien_quan = v_vdk_id where id_checkpoint = p_id_checkpoint;
    end if;
  elsif p_ket_qua = 'CANH_BAO' then
    if v_cht.so_khuon is null or v_cht.so_khuon = '' then
      v_note := 'Không tạo được báo cáo vấn đề khuôn — dòng chưa gán số khuôn.';
    else
      v_vdk_id := duc_report_mold_issue(v_cht.so_khuon, v_cp.ma_may, v_cp.ma_sp, v_issue_text, p_nguoi_kiem, v_cht.ngay, v_cht.ca);
      update duc_ipqc_checkpoint set id_van_de_lien_quan = v_vdk_id where id_checkpoint = p_id_checkpoint;
    end if;
  else
    perform duc_close_f1_incident_if_open(v_cp.id_dong, p_nguoi_kiem);
  end if;

  return jsonb_build_object('ok', true, 'id_checkpoint', p_id_checkpoint, 'ket_qua', p_ket_qua, 'note', v_note);
end;
$function$;
