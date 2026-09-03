-- ============================================================================
-- Phase T30 — IPQC: mỗi máy chỉ có 1 ĐIỂM KIỂM SỐNG tại một thời điểm; sự cố /
-- đổi khuôn ưu tiên hơn định kỳ; kiểm sự cố / đổi khuôn xong tính luôn là đã
-- kiểm định kỳ (đồng hồ định kỳ reset từ đó).
--
-- Bối cảnh (điều tra DC7 ngày 03/09/2026): lượt kiểm 'sau_su_co' lúc 14:24 hiện
-- "Trễ 505 phút". Nguyên nhân: sự cố SC-DC7-0903-0600 phát sinh khai 06:00
-- nhưng mãi 12:26 trưởng ca mới nhập vào hệ thống → checkpoint 'sau_su_co'
-- sinh lúc 12:26 với han_kiem = 06:00 (giờ phát sinh). "Trễ" = giờ kiểm −
-- han_kiem = 14:24 − 06:00 ≈ 505, dù IPQC không thể kiểm trước lúc checkpoint
-- tồn tại (12:26). Ngoài ra checkpoint 'dinh_ky' bị bỏ dở (IPQC bấm vào rồi
-- thoát) vẫn nằm 'cho_kiem' song song với checkpoint sự cố của cùng máy.
--
-- Sửa (chỉ áp cho checkpoint sinh TỪ ĐÂY VỀ SAU — dữ liệu cũ giữ nguyên):
--
-- 1) duc_request_ipqc_check — mốc bắt đầu tính "trễ" (han_kiem) KHÔNG bao giờ
--    lùi trước lần kiểm HOÀN THÀNH gần nhất của chính dòng đó. Với 'dinh_ky'
--    client đã truyền sẵn p_moc_cho_override tính từ lần kiểm trước → không
--    đổi. Với 'sau_su_co' / 'doi_khuon', p_moc_cho_override là giờ phát sinh
--    sự cố / giờ đổi khuôn — nếu bị nhập lùi giờ trước lần kiểm gần nhất thì
--    kẹp về đúng lần kiểm gần nhất (kiểm sự cố cũng là kiểm định kỳ, tính mốc
--    mới từ lần kiểm trước). Trường hợp báo sự cố đúng lúc: p_moc_cho_override
--    ≈ now() ≥ lần kiểm gần nhất → không đổi gì.
--
-- 2) duc_request_ipqc_check — khi tạo checkpoint 'sau_su_co' / 'doi_khuon',
--    cho HẾT HIỆU LỰC ('het_hieu_luc', không xoá — giữ tra cứu, giống D18)
--    mọi checkpoint 'dinh_ky' đang 'cho_kiem' của cùng dòng. Chiều ngược lại
--    đã được duc_get_ipqc_periodic_due (D17) lo: không sinh mục định kỳ ảo khi
--    dòng đang có bất kỳ checkpoint 'cho_kiem' nào.
--
-- 3) duc_submit_ipqc_check — khi một lượt kiểm bất kỳ hoàn thành, cho hết hiệu
--    lực mọi checkpoint 'dinh_ky' khác còn 'cho_kiem' của cùng dòng. Đồng hồ
--    định kỳ tự tính lại từ thoi_diem_kiem_thuc_te của lượt vừa xong qua
--    duc_get_ipqc_periodic_due (mốc = max(thoi_diem_kiem_thuc_te) mọi loại
--    kiểm, cùng id_dong).
--
-- Không cần sửa frontend: ipqc.html + qc-manager.html đều chỉ xử lý
-- trang_thai 'cho_kiem' / 'da_kiem', tự bỏ qua 'het_hieu_luc'.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ── 1) + 2) duc_request_ipqc_check ─────────────────────────────────────────
create or replace function duc_request_ipqc_check(
  p_id_dong text, p_loai_kiem text, p_id_su_co_goc text default null,
  p_moc_cho_override timestamptz default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_cht record;
  v_dup int;
  v_id text;
  v_han_kiem timestamptz;
  v_last_check timestamptz;
begin
  select ma_may, ma_sp, ngay, ca, phuong_an_ca into v_cht from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then return jsonb_build_object('ok', false, 'reason', 'khong_tim_thay_dong'); end if;
  if v_cht.ma_sp is null or v_cht.ma_sp = '' then return jsonb_build_object('ok', false, 'reason', 'dong_khong_co_sp'); end if;

  select count(*) into v_dup from duc_ipqc_checkpoint
    where id_dong = p_id_dong and loai_kiem = p_loai_kiem and trang_thai = 'cho_kiem';
  if v_dup > 0 then return jsonb_build_object('ok', false, 'reason', 'da_co_checkpoint_cho_kiem'); end if;

  -- Sự cố / đổi khuôn ưu tiên hơn định kỳ: nuốt luôn checkpoint 'dinh_ky'
  -- đang chờ của cùng dòng (thường là dòng định kỳ IPQC bấm vào rồi bỏ dở).
  if p_loai_kiem in ('sau_su_co', 'doi_khuon') then
    update duc_ipqc_checkpoint
      set trang_thai = 'het_hieu_luc'
      where id_dong = p_id_dong and loai_kiem = 'dinh_ky' and trang_thai = 'cho_kiem';
  end if;

  -- Mốc bắt đầu tính "trễ": không bao giờ lùi trước lần kiểm HOÀN THÀNH gần
  -- nhất của chính dòng này (kiểm sự cố / đổi khuôn cũng là kiểm định kỳ).
  select max(thoi_diem_kiem_thuc_te) into v_last_check
    from duc_ipqc_checkpoint
    where id_dong = p_id_dong and trang_thai = 'da_kiem';

  v_han_kiem := coalesce(p_moc_cho_override, now());
  if v_last_check is not null and v_han_kiem < v_last_check then
    v_han_kiem := v_last_check;
  end if;
  if v_han_kiem > now() then
    v_han_kiem := now();
  end if;

  v_id := 'IPQC_' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DDMMYYYY_HH24MISS')
    || '_' || duc_normalize_name(v_cht.ma_may) || '_' || p_loai_kiem;

  insert into duc_ipqc_checkpoint (
    id_checkpoint, id_dong, ma_may, ma_sp, ngay, ca, phuong_an_ca, loai_kiem,
    id_su_co_goc, thoi_diem_tao, han_kiem, trang_thai
  ) values (
    v_id, p_id_dong, v_cht.ma_may, v_cht.ma_sp, v_cht.ngay, v_cht.ca, v_cht.phuong_an_ca,
    p_loai_kiem, p_id_su_co_goc, now(), v_han_kiem, 'cho_kiem'
  );

  return jsonb_build_object('ok', true, 'id_checkpoint', v_id);
end;
$$;
revoke execute on function duc_request_ipqc_check(text, text, text, timestamptz) from anon;
grant execute on function duc_request_ipqc_check(text, text, text, timestamptz) to authenticated;

-- ── 3) duc_submit_ipqc_check (giữ nguyên bản T12, thêm bước dọn 'dinh_ky') ──
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
  v_now timestamptz := now();
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

  -- Một máy chỉ 1 điểm kiểm sống: lượt kiểm này xong thì cho hết hiệu lực mọi
  -- checkpoint 'dinh_ky' khác còn 'cho_kiem' của cùng dòng. Đồng hồ định kỳ
  -- tự tính lại từ thoi_diem_kiem_thuc_te vừa ghi qua duc_get_ipqc_periodic_due.
  update duc_ipqc_checkpoint set trang_thai = 'het_hieu_luc'
  where id_dong = v_cp.id_dong and loai_kiem = 'dinh_ky'
    and trang_thai = 'cho_kiem' and id_checkpoint <> p_id_checkpoint;

  select ngay, ca, so_khuon, open_gio_phat_sinh into v_cht from duc_ca_hien_tai where id_dong = v_cp.id_dong;
  if not found then
    return jsonb_build_object('ok', true, 'id_checkpoint', p_id_checkpoint, 'ket_qua', p_ket_qua, 'note', 'Dòng Ca_hien_tai gốc không còn — bỏ qua liên kết ngược.');
  end if;

  v_issue_text := duc_build_ipqc_issue_text(p_ket_qua, v_cp.loai_kiem, p_checklist, p_ghi_chu);

  if p_ket_qua = 'NG' then
    if v_cht.open_gio_phat_sinh is not null then
      v_note := 'Không tự mở sự cố F1 được — dòng đang có sự cố khác mở. Cần trưởng ca xử lý thủ công.';
    else
      v_open_result := duc_set_incident_open(v_cp.id_dong, 'F1', v_now, v_issue_text, '', p_nguoi_kiem);
      if not (v_open_result->>'ok')::boolean then
        v_note := 'Lỗi mở sự cố F1 tự động: ' || (v_open_result->>'error');
      else
        begin perform duc_request_ipqc_check(v_cp.id_dong, 'sau_su_co', v_open_result->>'id_su_co', v_now); exception when others then null; end;
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
revoke execute on function duc_submit_ipqc_check(text, jsonb, text, jsonb, text, numeric, text) from anon;
grant execute on function duc_submit_ipqc_check(text, jsonb, text, jsonb, text, numeric, text) to authenticated;
