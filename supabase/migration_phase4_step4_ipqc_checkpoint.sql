-- ============================================================================
-- Phase 4, bước con 4 (cutover ghi) — chuỗi IPQC checkpoint đầy đủ
-- (IpqcCheckpoint.js: requestIpqcCheck_, submitIpqcCheck_, _closeF1IncidentIfOpen_)
-- + các hàm nội bộ dùng chung với VanDeKhuon.js/CaHienTai.js/BanGhiSuCo.js
-- (reportMoldIssue_, setIncidentOpen_, clearIncidentOpen_) viết lại thành SQL
-- để trang tĩnh (browser) gọi thẳng được, không qua Apps Script.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- Ảnh bằng chứng: KHÔNG upload trong SQL — trình duyệt tự upload lên Storage
-- bucket "ipqc-evidence" (đã tạo ở migration_phase_D0_foundation.sql) TRƯỚC,
-- rồi truyền mảng URL vào duc_submit_ipqc_check qua tham số p_anh_urls.
--
-- Đơn giản hoá có chủ đích so với bản Apps Script cũ:
-- - reportMoldIssue_ bản cũ tự "đoán" ca/ngày hiện tại qua detectCurrentShift()
--   (dựa giờ hệ thống). Khi gọi từ chuỗi IPQC submit, bản SQL này dùng thẳng
--   ca/ngày của DÒNG Ca_hien_tai liên quan — chính xác hơn vì đúng ngữ cảnh
--   ca đang IPQC kiểm, không phụ thuộc giờ đồng hồ lúc bấm nút.
-- ============================================================================

create extension if not exists unaccent with schema extensions;

-- Chuẩn hoá tên máy/khuôn giống hệt normalizeMachineName() (Utils.js): bỏ dấu
-- tiếng Việt, xử lý riêng đ/Đ (không nằm trong phạm vi unaccent), bỏ khoảng trắng.
create or replace function duc_normalize_name(p_name text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    extensions.unaccent(replace(replace(coalesce(p_name, ''), 'đ', 'd'), 'Đ', 'D')),
    '\s+', '', 'g'
  );
$$;

-- ── setIncidentOpen_ / clearIncidentOpen_ (CaHienTai.js) ───────────────────
create or replace function duc_set_incident_open(
  p_id_dong text, p_loai text, p_gio_phat_sinh timestamptz,
  p_van_de text, p_noi_dung_xu_ly text, p_dam_nhiem text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_current record;
  v_new_version bigint;
begin
  select open_gio_phat_sinh, version into v_current from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng: ' || p_id_dong);
  end if;
  if v_current.open_gio_phat_sinh is not null then
    return jsonb_build_object('ok', false, 'error', 'Dòng này đã có sự cố đang mở.');
  end if;

  v_new_version := coalesce(v_current.version, 0) + 1;
  update duc_ca_hien_tai set
    open_loai_su_co = p_loai, open_gio_phat_sinh = p_gio_phat_sinh,
    open_van_de = coalesce(p_van_de, ''), open_noi_dung_xu_ly = coalesce(p_noi_dung_xu_ly, ''),
    open_dam_nhiem = coalesce(p_dam_nhiem, ''),
    version = v_new_version, last_updated_by = coalesce(p_dam_nhiem, 'system'), last_updated_at = now()
  where id_dong = p_id_dong;

  return jsonb_build_object('ok', true, 'id_dong', p_id_dong, 'version', v_new_version);
end;
$$;
revoke execute on function duc_set_incident_open(text, text, timestamptz, text, text, text) from anon;
grant execute on function duc_set_incident_open(text, text, timestamptz, text, text, text) to authenticated;

create or replace function duc_clear_incident_open(p_id_dong text, p_user text)
returns void
language sql
security definer
as $$
  update duc_ca_hien_tai set
    open_loai_su_co = '', open_gio_phat_sinh = null, open_van_de = '',
    open_noi_dung_xu_ly = '', open_dam_nhiem = '',
    version = coalesce(version, 0) + 1, last_updated_by = p_user, last_updated_at = now()
  where id_dong = p_id_dong;
$$;
revoke execute on function duc_clear_incident_open(text, text) from anon;
grant execute on function duc_clear_incident_open(text, text) to authenticated;

-- ── reportMoldIssue_ (VanDeKhuon.js) ────────────────────────────────────────
create or replace function duc_report_mold_issue(
  p_ma_khuon text, p_ma_may text, p_ma_sp text, p_mo_ta text,
  p_nguoi_phat_hien text, p_ngay date, p_ca text
)
returns text
language plpgsql
security definer
as $$
declare
  v_id text;
begin
  v_id := 'VDK_' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DDMMYYYY_HH24MISS')
    || '_' || duc_normalize_name(p_ma_khuon);

  insert into duc_van_de_khuon (
    id_van_de, ma_khuon, ngay_phat_hien, ca_phat_hien, ma_may, ma_sp,
    mo_ta, nguoi_phat_hien, trang_thai, lan_tai_phat, last_updated_at
  ) values (
    v_id, p_ma_khuon, coalesce(p_ngay, (now() at time zone 'Asia/Ho_Chi_Minh')::date), p_ca,
    p_ma_may, p_ma_sp, p_mo_ta, p_nguoi_phat_hien, 'Mở', 0, now()
  );
  return v_id;
end;
$$;
revoke execute on function duc_report_mold_issue(text, text, text, text, text, date, text) from anon;
grant execute on function duc_report_mold_issue(text, text, text, text, text, date, text) to authenticated;

-- ── _closeF1IncidentIfOpen_ (IpqcCheckpoint.js) — đóng sự cố F1 khi IPQC OK lại ─
create or replace function duc_close_f1_incident_if_open(p_id_dong text, p_nguoi_kiem text)
returns boolean
language plpgsql
security definer
as $$
declare
  v_cht record;
  v_stt int;
  v_id_ban_ghi text;
begin
  select ngay, ca, ma_may, ma_sp, ten_sp, so_khuon, open_loai_su_co, open_gio_phat_sinh, open_van_de, open_dam_nhiem
  into v_cht from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found or v_cht.open_loai_su_co is null or left(v_cht.open_loai_su_co, 2) <> 'F1'
     or v_cht.open_gio_phat_sinh is null then
    return false;
  end if;

  select count(*) + 1 into v_stt from duc_su_co_log
    where ngay = v_cht.ngay and ca = v_cht.ca and ma_may = v_cht.ma_may and ma_sp = v_cht.ma_sp;
  v_id_ban_ghi := p_id_dong || '_' || v_stt;

  insert into duc_su_co_log (
    id_ban_ghi, ngay, ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, loai_su_co,
    gio_phat_sinh, gio_tro_lai, thoi_gian_dung_phut, van_de, noi_dung_xu_ly,
    dam_nhiem, ghi_chu, truong_ca, thoi_diem_luu, van_de_edited
  ) values (
    v_id_ban_ghi, v_cht.ngay, v_cht.ca, to_char(v_cht.ngay, '"W"WW_YYYY'), v_cht.ma_may, v_cht.ma_sp, v_cht.ten_sp, v_cht.so_khuon,
    v_cht.open_loai_su_co, v_cht.open_gio_phat_sinh, now(),
    round(extract(epoch from (now() - v_cht.open_gio_phat_sinh)) / 60),
    v_cht.open_van_de, 'IPQC kiểm tra lại: OK — cho phép sản xuất tiếp' || case when p_nguoi_kiem is not null then ' (' || p_nguoi_kiem || ')' else '' end,
    coalesce(p_nguoi_kiem, v_cht.open_dam_nhiem), '', '', now(), 'No'
  );

  perform duc_clear_incident_open(p_id_dong, coalesce(p_nguoi_kiem, 'system'));
  return true;
end;
$$;
revoke execute on function duc_close_f1_incident_if_open(text, text) from anon;
grant execute on function duc_close_f1_incident_if_open(text, text) to authenticated;

-- ── requestIpqcCheck_ (IpqcCheckpoint.js) ───────────────────────────────────
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
begin
  select ma_may, ma_sp, ngay, ca, phuong_an_ca into v_cht from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then return jsonb_build_object('ok', false, 'reason', 'khong_tim_thay_dong'); end if;
  if v_cht.ma_sp is null or v_cht.ma_sp = '' then return jsonb_build_object('ok', false, 'reason', 'dong_khong_co_sp'); end if;

  select count(*) into v_dup from duc_ipqc_checkpoint
    where id_dong = p_id_dong and loai_kiem = p_loai_kiem and trang_thai = 'cho_kiem';
  if v_dup > 0 then return jsonb_build_object('ok', false, 'reason', 'da_co_checkpoint_cho_kiem'); end if;

  v_id := 'IPQC_' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DDMMYYYY_HH24MISS')
    || '_' || duc_normalize_name(v_cht.ma_may) || '_' || p_loai_kiem;

  insert into duc_ipqc_checkpoint (
    id_checkpoint, id_dong, ma_may, ma_sp, ngay, ca, phuong_an_ca, loai_kiem,
    id_su_co_goc, thoi_diem_tao, han_kiem, trang_thai
  ) values (
    v_id, p_id_dong, v_cht.ma_may, v_cht.ma_sp, v_cht.ngay, v_cht.ca, v_cht.phuong_an_ca,
    p_loai_kiem, p_id_su_co_goc, now(), coalesce(p_moc_cho_override, now()), 'cho_kiem'
  );

  return jsonb_build_object('ok', true, 'id_checkpoint', v_id);
end;
$$;
revoke execute on function duc_request_ipqc_check(text, text, text, timestamptz) from anon;
grant execute on function duc_request_ipqc_check(text, text, text, timestamptz) to authenticated;

-- Dựng nội dung mô tả vấn đề khi IPQC kết luận NG/CANH_BAO (_buildIpqcIssueText_).
create or replace function duc_build_ipqc_issue_text(p_ket_qua text, p_loai_kiem text, p_checklist jsonb, p_ghi_chu text)
returns text
language plpgsql
immutable
as $$
declare
  v_text text;
  v_hang_muc text;
begin
  v_text := case when p_ket_qua = 'NG' then 'IPQC phát hiện NG khi kiểm tra' else 'IPQC cảnh báo NG (cho sản xuất tiếp) lúc kiểm tra' end;
  if p_loai_kiem is not null then v_text := v_text || ' — loại kiểm: ' || p_loai_kiem; end if;

  select string_agg(elem->>'muc', '; ') into v_hang_muc
  from jsonb_array_elements(coalesce(p_checklist, '[]'::jsonb)) elem
  where (elem->>'dat')::boolean = false;

  if v_hang_muc is not null and v_hang_muc <> '' then
    v_text := v_text || ' — Hạng mục không đạt: ' || v_hang_muc;
  end if;
  if p_ghi_chu is not null and p_ghi_chu <> '' then
    v_text := v_text || ' — Ghi chú IPQC: ' || p_ghi_chu;
  end if;
  return v_text;
end;
$$;

-- ── submitIpqcCheck_ (IpqcCheckpoint.js) — RPC chính, gói toàn bộ chuỗi ────
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
begin
  if p_ket_qua not in ('OK', 'NG', 'CANH_BAO') then
    return jsonb_build_object('ok', false, 'error', 'Kết quả phải là OK, NG hoặc CANH_BAO');
  end if;
  if p_anh_urls is null or jsonb_array_length(p_anh_urls) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Bắt buộc có ít nhất 1 ảnh bằng chứng');
  end if;

  select id_dong, ma_may, ma_sp, loai_kiem into v_cp from duc_ipqc_checkpoint where id_checkpoint = p_id_checkpoint;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy checkpoint: ' || p_id_checkpoint); end if;

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
revoke execute on function duc_submit_ipqc_check(text, jsonb, text, jsonb, text, numeric, text) from anon;
grant execute on function duc_submit_ipqc_check(text, jsonb, text, jsonb, text, numeric, text) to authenticated;
