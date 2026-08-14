-- ============================================================================
-- Phase 4, bước con 12 — chuẩn bị cho trang tĩnh ipqc.html (thay Web App Apps
-- Script Ipqc.html). Chạy trong Supabase SQL Editor. An toàn chạy lại (idempotent).
--
-- duc_submit_ipqc_check (tạo ở migration_phase4_step4_ipqc_checkpoint.sql) đã
-- có revoke/grant đúng chuẩn, KHÔNG cần sửa quyền. Nhưng RPC hiện CHƯA lặp lại
-- các kiểm tra nghiệp vụ mà bản Apps Script gốc làm ở tầng SERVER (submitIpqcCheck_,
-- IpqcCheckpoint.js:358-390) — trước đây không cần vì chỉ Apps Script (đáng tin,
-- code phía server) mới gọi được. Từ khi trình duyệt gọi thẳng RPC bằng
-- authenticated key, PHẢI kiểm tra lại ở server (không chỉ ở client ipqc.html),
-- đúng đúng nguyên tắc "checklist do client gửi lên, không tin tưởng tuyệt đối"
-- đã ghi rõ trong comment gốc. Bổ sung bằng create or replace (an toàn, cùng
-- chữ ký hàm, không cần revoke/grant lại).
-- ============================================================================

create or replace function duc_submit_ipqc_check(
  p_id_checkpoint text, p_checklist jsonb, p_ket_qua text, p_anh_urls jsonb,
  p_ghi_chu text, p_thoi_gian_kiem_giay numeric, p_nguoi_kiem text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_cp record;
  v_cht record;
  v_note text := '';
  v_issue_text text;
  v_vdk_id text;
  v_open_result jsonb;
  v_all_pass boolean;
  v_any_fail boolean;
begin
  if p_ket_qua not in ('OK', 'NG', 'CANH_BAO') then
    return jsonb_build_object('ok', false, 'error', 'Kết quả phải là OK, NG hoặc CANH_BAO');
  end if;
  if p_anh_urls is null or jsonb_array_length(p_anh_urls) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Bắt buộc có ít nhất 1 ảnh bằng chứng');
  end if;
  if jsonb_array_length(p_anh_urls) > 6 then
    return jsonb_build_object('ok', false, 'error', 'Tối đa 6 ảnh cho 1 lần kiểm tra');
  end if;
  if p_nguoi_kiem is null or trim(p_nguoi_kiem) = '' or position('@' in p_nguoi_kiem) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Thiếu email người kiểm hợp lệ');
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

  select id_dong, ma_may, ma_sp, loai_kiem into v_cp from duc_ipqc_checkpoint where id_checkpoint = p_id_checkpoint;
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

  select ngay, ca, so_khuon, open_gio_phat_sinh into v_cht from duc_ca_hien_tai where id_dong = v_cp.id_dong;
  if not found then
    return jsonb_build_object('ok', true, 'id_checkpoint', p_id_checkpoint, 'ket_qua', p_ket_qua, 'note', 'Dòng Ca_hien_tai gốc không còn — bỏ qua liên kết ngược.');
  end if;

  v_issue_text := duc_build_ipqc_issue_text(p_ket_qua, v_cp.loai_kiem, p_checklist, p_ghi_chu);

  if p_ket_qua = 'NG' then
    if v_cht.open_gio_phat_sinh is not null then
      v_note := 'Không tự mở sự cố F1 được — dòng đang có sự cố khác mở. Cần trưởng ca xử lý thủ công.';
    else
      v_open_result := duc_set_incident_open(v_cp.id_dong, 'F1', now(), v_issue_text, '', p_nguoi_kiem);
      if not (v_open_result->>'ok')::boolean then
        v_note := 'Lỗi mở sự cố F1 tự động: ' || (v_open_result->>'error');
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
$$;
