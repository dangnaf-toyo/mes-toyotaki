-- ============================================================================
-- Giai đoạn 11 (bỏ Google) — Sửa lỗi: cảnh báo "chưa có kết quả IPQC OK"
-- (migration_phase_D10) không hiện dù thực sự chưa có IPQC OK cho đúng sự cố
-- đang đóng.
--
-- Nguyên nhân: D10 xác định "đã có IPQC OK cho sự cố này" bằng điều kiện
-- thoi_diem_kiem_thuc_te >= open_gio_phat_sinh (kiểm xong SAU khi sự cố mở).
-- Điều kiện 1 chiều này khớp NHẦM với bất kỳ lần IPQC OK nào xảy ra sau đó —
-- kể cả từ 1 sự cố/chu kỳ test hoàn toàn khác trên cùng dòng — không chỉ
-- riêng lần kiểm ứng với đúng sự cố đang đóng. Phát hiện qua test thật
-- (2026-08-15): dòng DC6 có sự cố B1 mở lúc 13/8 09:40, nhưng có 1 IPQC OK
-- không liên quan hoàn thành lúc 14/8 16:18 → bị tính nhầm là "đã kiểm OK".
--
-- Sửa: khớp CHÍNH XÁC theo han_kiem = open_gio_phat_sinh — vì khi tạo
-- checkpoint cho 1 sự cố cụ thể (duc_open_incident/duc_change_product), hệ
-- thống LUÔN đặt han_kiem = đúng giờ phát sinh của sự cố đó, nên đây là mối
-- liên kết 1-1 chính xác tới đúng sự cố đang xét, không nhầm sang lần kiểm
-- khác.
--
-- Đồng thời bổ sung: khi IPQC báo NG tự động mở sự cố F1 (duc_submit_ipqc_check),
-- trước đây KHÔNG tự tạo checkpoint "sau_su_co" cho sự cố F1 mới mở này —
-- nghĩa là F1 sẽ KHÔNG BAO GIỜ khớp được han_kiem chính xác, cảnh báo/chặn sẽ
-- luôn hiện (đúng nhưng không bao giờ tự hết) cho tới khi có 1 lần kiểm định
-- kỳ tình cờ khác đi qua. Sửa: tự tạo checkpoint sau_su_co cùng mốc giờ với
-- lúc mở F1, giống hệt cách duc_open_incident đã làm cho sự cố do trưởng ca
-- báo tay.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ── 1) duc_resolve_incident — khớp chính xác han_kiem thay vì "sau thời điểm" ──
create or replace function duc_resolve_incident(
  p_id_dong text, p_gio_tro_lai timestamptz, p_bonus_note text, p_truong_ca text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_cht record;
  v_noi_dung_combined text;
  v_seg record;
  v_stt int;
  v_id_ban_ghi text;
  v_created_ids text[] := array[]::text[];
  v_total_phut int := 0;
  v_seg_count int;
  v_idx int := 0;
  v_seg_noi_dung text;
  v_last_id text;
  v_loai_can_ipqc constant text[] := array['A1','A2','A3','B1','B2','C3','E1','F1'];
  v_hard_block_ipqc constant boolean := false;   -- Giai đoạn 2: đổi thành true khi sẵn sàng
  v_co_ipqc_ok boolean;
  v_canh_bao_ipqc boolean := false;
begin
  select ngay, ca, phuong_an_ca, ma_may, ma_sp, ten_sp, so_khuon, open_loai_su_co,
         open_gio_phat_sinh, open_noi_dung_xu_ly, open_van_de, open_dam_nhiem
  into v_cht from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng Ca_hien_tai: ' || p_id_dong);
  end if;
  if v_cht.open_gio_phat_sinh is null then
    return jsonb_build_object('ok', false, 'error', 'Dòng này không có sự cố đang mở');
  end if;
  if p_gio_tro_lai < v_cht.open_gio_phat_sinh then
    return jsonb_build_object('ok', false, 'error', 'Giờ trở lại phải sau giờ phát sinh');
  end if;
  if p_gio_tro_lai > now() + interval '1 minute' then
    return jsonb_build_object('ok', false, 'error', 'Giờ trở lại không được ở tương lai');
  end if;

  -- Bắt buộc/cảnh báo IPQC OK cho các loại sự cố liên quan chất lượng/khuôn —
  -- khớp CHÍNH XÁC checkpoint được tạo riêng cho đúng sự cố này qua han_kiem.
  if left(coalesce(v_cht.open_loai_su_co, ''), 2) = any(v_loai_can_ipqc) then
    select exists(
      select 1 from duc_ipqc_checkpoint cp
      where cp.id_dong = p_id_dong
        and cp.loai_kiem in ('doi_khuon', 'sau_su_co')
        and cp.trang_thai = 'da_kiem'
        and cp.ket_qua = 'OK'
        and cp.han_kiem = v_cht.open_gio_phat_sinh
    ) into v_co_ipqc_ok;

    if not v_co_ipqc_ok then
      if v_hard_block_ipqc then
        return jsonb_build_object('ok', false, 'error',
          'Chưa có kết quả IPQC OK cho sự cố này — không thể kết thúc. Hãy nhắc nhân viên IPQC kiểm tra và hoàn thiện trên hệ thống trước.');
      end if;
      v_canh_bao_ipqc := true;
    end if;
  end if;

  v_noi_dung_combined := coalesce(v_cht.open_noi_dung_xu_ly, '');
  if p_bonus_note is not null and trim(p_bonus_note) <> '' then
    v_noi_dung_combined := case when v_noi_dung_combined <> '' then v_noi_dung_combined || E'\n[BS] ' || trim(p_bonus_note) else trim(p_bonus_note) end;
  end if;

  select count(*) into v_seg_count from duc_split_incident_by_shift(
    v_cht.open_gio_phat_sinh, p_gio_tro_lai, v_cht.phuong_an_ca, v_cht.ngay, v_cht.ca
  );

  for v_seg in select * from duc_split_incident_by_shift(
    v_cht.open_gio_phat_sinh, p_gio_tro_lai, v_cht.phuong_an_ca, v_cht.ngay, v_cht.ca
  ) loop
    v_idx := v_idx + 1;
    select count(*) + 1 into v_stt from duc_su_co_log
      where ngay = v_seg.ngay and ca = v_seg.ca and ma_may = v_cht.ma_may and ma_sp = v_cht.ma_sp;
    v_id_ban_ghi := duc_make_id_dong(v_seg.ngay, v_seg.ca, v_cht.ma_may, v_cht.ma_sp) || '_' || v_stt;

    v_seg_noi_dung := v_noi_dung_combined;
    if v_seg_count > 1 then
      v_seg_noi_dung := v_seg_noi_dung || E'\n[Phần ' || v_idx || '/' || v_seg_count || ' — ' || v_seg.ca || ' ' || to_char(v_seg.ngay, 'DD/MM/YYYY') ||
        (case when v_idx = v_seg_count then ', xử lý xong]' else ', chuyển tiếp ca sau]' end);
    end if;

    insert into duc_su_co_log (
      id_ban_ghi, ngay, ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, loai_su_co,
      gio_phat_sinh, gio_tro_lai, thoi_gian_dung_phut, van_de, noi_dung_xu_ly,
      dam_nhiem, ghi_chu, truong_ca, thoi_diem_luu, van_de_edited
    ) values (
      v_id_ban_ghi, v_seg.ngay, v_seg.ca, duc_iso_week(v_seg.ngay), v_cht.ma_may, v_cht.ma_sp, v_cht.ten_sp, v_cht.so_khuon,
      v_cht.open_loai_su_co, v_seg.seg_start, v_seg.seg_end, v_seg.phut,
      v_cht.open_van_de, v_seg_noi_dung, v_cht.open_dam_nhiem, '', coalesce(p_truong_ca, ''), now(), 'No'
    );

    v_created_ids := array_append(v_created_ids, v_id_ban_ghi);
    v_total_phut := v_total_phut + v_seg.phut;
    v_last_id := v_id_ban_ghi;
  end loop;

  perform duc_clear_incident_open(p_id_dong, coalesce(p_truong_ca, p_user, 'system'));

  return jsonb_build_object(
    'ok', true, 'id_ban_ghi', v_last_id, 'id_ban_ghi_list', to_jsonb(v_created_ids),
    'thoi_gian_dung_phut', v_total_phut, 'canh_bao_ipqc', v_canh_bao_ipqc
  );
end;
$$;
revoke execute on function duc_resolve_incident(text, timestamptz, text, text, text) from anon;
grant execute on function duc_resolve_incident(text, timestamptz, text, text, text) to authenticated;

-- ── 2) duc_submit_ipqc_check — tự tạo checkpoint sau_su_co khi tự mở F1 ─────
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
      v_open_result := duc_set_incident_open(v_cp.id_dong, 'F1', v_now, v_issue_text, '', p_nguoi_kiem);
      if not (v_open_result->>'ok')::boolean then
        v_note := 'Lỗi mở sự cố F1 tự động: ' || (v_open_result->>'error');
      else
        -- Tạo sẵn checkpoint "sau_su_co" cùng mốc giờ với lúc mở F1 — để lần
        -- IPQC kiểm lại OK sau này khớp đúng (han_kiem = giờ phát sinh) với
        -- duc_resolve_incident khi trưởng ca đóng sự cố F1 này.
        begin perform duc_request_ipqc_check(v_cp.id_dong, 'sau_su_co', null, v_now); exception when others then null; end;
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
