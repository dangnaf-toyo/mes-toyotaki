-- ============================================================================
-- Giai đoạn 12 (bỏ Google) — Thêm MÃ SỰ CỐ (id_su_co) hiển thị được, liên kết
-- rõ ràng giữa Dashboard Đúc và IPQC — tránh nhầm lẫn khi có nhiều sự cố
-- cùng lúc trên nhiều máy.
--
-- Trước đây: liên kết giữa "sự cố đang mở trên Dashboard Đúc" và "checkpoint
-- IPQC cần kiểm cho sự cố đó" chỉ dựa vào so khớp CHÍNH XÁC giờ phát sinh
-- (han_kiem = open_gio_phat_sinh, migration_phase_D11) — đúng nhưng vô hình,
-- người dùng không nhìn thấy để tự đối chiếu, và vẫn có thể lệch nếu sau này
-- sửa giờ phát sinh (duc_edit_open_incident).
--
-- Nay: sinh 1 mã sự cố NGẮN, DỄ ĐỌC ngay lúc mở sự cố — dạng
-- "SC-<máy>-<ngày/tháng>-<giờ:phút>" (vd SC-DC6-0815-1344) — lưu cố định vào
-- duc_ca_hien_tai.open_id_su_co (KHÔNG đổi lại dù sau này sửa giờ phát sinh —
-- vẫn là cùng 1 sự cố), gắn vào checkpoint IPQC tương ứng
-- (duc_ipqc_checkpoint.id_su_co_goc) ngay khi tạo, và hiện trên cả 2 màn
-- hình để người dùng tự đối chiếu bằng mắt. duc_resolve_incident chuyển sang
-- so khớp theo đúng mã này thay vì giờ phát sinh.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

alter table duc_ca_hien_tai add column if not exists open_id_su_co text;
alter table duc_su_co_log add column if not exists id_su_co text;

-- ── Hàm sinh mã sự cố ────────────────────────────────────────────────────
create or replace function duc_make_id_su_co(p_ma_may text, p_gio_phat_sinh timestamptz)
returns text
language sql
immutable
as $$
  select 'SC-' || duc_normalize_name(p_ma_may) || '-' ||
    to_char(p_gio_phat_sinh at time zone 'Asia/Ho_Chi_Minh', 'MMDD') || '-' ||
    to_char(p_gio_phat_sinh at time zone 'Asia/Ho_Chi_Minh', 'HH24MI');
$$;

-- ── duc_set_incident_open — sinh và lưu mã sự cố ngay lúc mở ────────────────
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
  v_id_su_co text;
begin
  select ma_may, open_gio_phat_sinh, version into v_current from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng: ' || p_id_dong);
  end if;
  if v_current.open_gio_phat_sinh is not null then
    return jsonb_build_object('ok', false, 'error', 'Dòng này đã có sự cố đang mở.');
  end if;

  v_id_su_co := duc_make_id_su_co(v_current.ma_may, p_gio_phat_sinh);
  v_new_version := coalesce(v_current.version, 0) + 1;
  update duc_ca_hien_tai set
    open_loai_su_co = p_loai, open_gio_phat_sinh = p_gio_phat_sinh,
    open_van_de = coalesce(p_van_de, ''), open_noi_dung_xu_ly = coalesce(p_noi_dung_xu_ly, ''),
    open_dam_nhiem = coalesce(p_dam_nhiem, ''), open_id_su_co = v_id_su_co,
    version = v_new_version, last_updated_by = coalesce(p_dam_nhiem, 'system'), last_updated_at = now()
  where id_dong = p_id_dong;

  return jsonb_build_object('ok', true, 'id_dong', p_id_dong, 'version', v_new_version, 'id_su_co', v_id_su_co);
end;
$$;
revoke execute on function duc_set_incident_open(text, text, timestamptz, text, text, text) from anon;
grant execute on function duc_set_incident_open(text, text, timestamptz, text, text, text) to authenticated;

-- ── duc_clear_incident_open — dọn mã sự cố khi đóng ─────────────────────────
create or replace function duc_clear_incident_open(p_id_dong text, p_user text)
returns void
language sql
security definer
as $$
  update duc_ca_hien_tai set
    open_loai_su_co = '', open_gio_phat_sinh = null, open_van_de = '',
    open_noi_dung_xu_ly = '', open_dam_nhiem = '', open_id_su_co = null,
    version = coalesce(version, 0) + 1, last_updated_by = p_user, last_updated_at = now()
  where id_dong = p_id_dong;
$$;
revoke execute on function duc_clear_incident_open(text, text) from anon;
grant execute on function duc_clear_incident_open(text, text) to authenticated;

-- ── duc_open_incident — gắn mã sự cố vào checkpoint IPQC tạo ra ─────────────
create or replace function duc_open_incident(p_id_dong text, p_loai text, p_gio_phat_sinh timestamptz, p_van_de text, p_noi_dung_xu_ly text, p_dam_nhiem text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_result jsonb;
begin
  if p_loai is null or trim(p_loai) = '' then return jsonb_build_object('ok', false, 'error', 'Invalid incident type'); end if;
  if p_gio_phat_sinh is null then return jsonb_build_object('ok', false, 'error', 'Chưa nhập giờ phát sinh'); end if;
  if p_gio_phat_sinh > now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Giờ phát sinh không được ở tương lai'); end if;

  v_result := duc_set_incident_open(p_id_dong, p_loai, p_gio_phat_sinh, p_van_de, p_noi_dung_xu_ly, p_dam_nhiem);

  if (v_result->>'ok')::boolean then
    begin
      perform duc_request_ipqc_check(p_id_dong, 'sau_su_co', v_result->>'id_su_co', p_gio_phat_sinh);
    exception when others then
      null;
    end;
  end if;

  return v_result;
end;
$$;
revoke execute on function duc_open_incident(text, text, timestamptz, text, text, text, text) from anon;
grant execute on function duc_open_incident(text, text, timestamptz, text, text, text, text) to authenticated;

-- ── duc_change_product — sinh mã sự cố cho pseudo-sự cố "C3 Đổi khuôn" ──────
create or replace function duc_change_product(
  p_old_id_dong text, p_new_ma_sp text, p_new_ten_sp text, p_new_so_khuon text,
  p_new_kh_ca numeric, p_new_kh_tuan numeric, p_gio_bat_dau_doi_khuon timestamptz, p_dam_nhiem text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_old record; v_new_id_dong text; v_win jsonb; v_carry_shot numeric; v_now timestamptz := now();
  v_id_su_co text;
begin
  if p_new_ma_sp is null or trim(p_new_ma_sp) = '' then return jsonb_build_object('ok', false, 'error', 'Chưa nhập mã SP mới'); end if;
  if p_new_kh_ca is null or p_new_kh_ca <= 0 then return jsonb_build_object('ok', false, 'error', 'Chưa nhập KH ca cho SP mới'); end if;
  if p_gio_bat_dau_doi_khuon is null then return jsonb_build_object('ok', false, 'error', 'Chưa nhập giờ bắt đầu đổi khuôn'); end if;
  if p_new_so_khuon is null or trim(p_new_so_khuon) = '' then return jsonb_build_object('ok', false, 'error', 'Bắt buộc nhập số khuôn'); end if;
  if p_gio_bat_dau_doi_khuon > now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Giờ bắt đầu đổi khuôn không được ở tương lai'); end if;

  select * into v_old from duc_ca_hien_tai where id_dong = p_old_id_dong;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng SP cũ: ' || p_old_id_dong); end if;
  if v_old.open_gio_phat_sinh is not null then return jsonb_build_object('ok', false, 'error', 'Dòng SP cũ đang có sự cố khác. Vui lòng xử lý xong trước khi đổi SP.'); end if;
  if trim(p_new_ma_sp) = trim(coalesce(v_old.ma_sp, '')) then return jsonb_build_object('ok', false, 'error', 'SP mới trùng với SP hiện tại'); end if;

  v_new_id_dong := duc_make_id_dong(v_old.ngay, v_old.ca, v_old.ma_may, p_new_ma_sp);
  if exists (select 1 from duc_ca_hien_tai where id_dong = v_new_id_dong) then
    return jsonb_build_object('ok', false, 'error', 'Máy ' || v_old.ma_may || ' đã có dòng với SP ' || p_new_ma_sp || ' trong ca này');
  end if;

  v_win := duc_get_shift_window(v_old.ngay, v_old.phuong_an_ca, v_old.ca);
  v_carry_shot := v_old.so_shot_cuoi_ca;
  if v_carry_shot is null then select so_shot_cuoi_ca_gan_nhat into v_carry_shot from duc_shot_may where ma_may = v_old.ma_may; end if;

  v_id_su_co := duc_make_id_su_co(v_old.ma_may, p_gio_bat_dau_doi_khuon);

  insert into duc_ca_hien_tai (
    id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, kh_ca, kh_tuan, tt_ca, tt_tuan,
    nv_ca_ngay, nv_ca_dem, open_loai_su_co, open_gio_phat_sinh, open_van_de, open_noi_dung_xu_ly, open_dam_nhiem, open_id_su_co,
    version, last_updated_by, last_updated_at, so_shot_nong_khuon, so_luong_ng, phan_loai_ng,
    sp_start_time, sp_end_time, so_shot_khuon_snapshot, so_shot_dau_ca, so_shot_cuoi_ca
  ) values (
    v_new_id_dong, v_old.ngay, v_old.ca, v_old.phuong_an_ca, duc_iso_week(v_old.ngay), v_old.ma_may, p_new_ma_sp, coalesce(p_new_ten_sp,''), coalesce(p_new_so_khuon,''),
    p_new_kh_ca, coalesce(p_new_kh_tuan,0), 0, 0, coalesce(v_old.nv_ca_ngay,''), coalesce(v_old.nv_ca_dem,''),
    'C3 - Đổi khuôn', p_gio_bat_dau_doi_khuon, 'Đổi khuôn từ ' || coalesce(v_old.ma_sp,''), 'Đang thực hiện đổi khuôn', coalesce(p_dam_nhiem,''), v_id_su_co,
    1, p_user, v_now, 0, 0, '', p_gio_bat_dau_doi_khuon, (v_win->>'end')::timestamptz, 0, v_carry_shot, null
  );

  if p_new_so_khuon is not null and p_new_ma_sp is not null then perform duc_ensure_mold_product_mapping(p_new_so_khuon, p_new_ma_sp); end if;
  begin perform duc_request_ipqc_check(v_new_id_dong, 'doi_khuon', v_id_su_co, p_gio_bat_dau_doi_khuon); exception when others then null; end;

  return jsonb_build_object('ok', true, 'new_id_dong', v_new_id_dong, 'old_id_dong', p_old_id_dong, 'old_ma_sp', v_old.ma_sp, 'new_ma_sp', p_new_ma_sp, 'ma_may', v_old.ma_may, 'id_su_co', v_id_su_co);
end;
$$;
revoke execute on function duc_change_product(text, text, text, text, numeric, numeric, timestamptz, text, text) from anon;
grant execute on function duc_change_product(text, text, text, text, numeric, numeric, timestamptz, text, text) to authenticated;

-- ── duc_submit_ipqc_check — gắn mã sự cố khi tự mở F1 ───────────────────────
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

-- ── duc_resolve_incident — khớp theo MÃ SỰ CỐ thay vì giờ phát sinh ─────────
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
         open_gio_phat_sinh, open_noi_dung_xu_ly, open_van_de, open_dam_nhiem, open_id_su_co
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
  -- khớp theo MÃ SỰ CỐ (open_id_su_co) — ổn định, không đổi dù sau này sửa
  -- giờ phát sinh của sự cố.
  if left(coalesce(v_cht.open_loai_su_co, ''), 2) = any(v_loai_can_ipqc) then
    select exists(
      select 1 from duc_ipqc_checkpoint cp
      where cp.id_dong = p_id_dong
        and cp.loai_kiem in ('doi_khuon', 'sau_su_co')
        and cp.trang_thai = 'da_kiem'
        and cp.ket_qua = 'OK'
        and cp.id_su_co_goc = v_cht.open_id_su_co
    ) into v_co_ipqc_ok;

    if not v_co_ipqc_ok then
      if v_hard_block_ipqc then
        return jsonb_build_object('ok', false, 'error',
          'Chưa có kết quả IPQC OK cho sự cố ' || coalesce(v_cht.open_id_su_co, '') || ' — không thể kết thúc. Hãy nhắc nhân viên IPQC kiểm tra và hoàn thiện trên hệ thống trước.');
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
      dam_nhiem, ghi_chu, truong_ca, thoi_diem_luu, van_de_edited, id_su_co
    ) values (
      v_id_ban_ghi, v_seg.ngay, v_seg.ca, duc_iso_week(v_seg.ngay), v_cht.ma_may, v_cht.ma_sp, v_cht.ten_sp, v_cht.so_khuon,
      v_cht.open_loai_su_co, v_seg.seg_start, v_seg.seg_end, v_seg.phut,
      v_cht.open_van_de, v_seg_noi_dung, v_cht.open_dam_nhiem, '', coalesce(p_truong_ca, ''), now(), 'No', v_cht.open_id_su_co
    );

    v_created_ids := array_append(v_created_ids, v_id_ban_ghi);
    v_total_phut := v_total_phut + v_seg.phut;
    v_last_id := v_id_ban_ghi;
  end loop;

  perform duc_clear_incident_open(p_id_dong, coalesce(p_truong_ca, p_user, 'system'));

  return jsonb_build_object(
    'ok', true, 'id_ban_ghi', v_last_id, 'id_ban_ghi_list', to_jsonb(v_created_ids),
    'thoi_gian_dung_phut', v_total_phut, 'canh_bao_ipqc', v_canh_bao_ipqc, 'id_su_co', v_cht.open_id_su_co
  );
end;
$$;
revoke execute on function duc_resolve_incident(text, timestamptz, text, text, text) from anon;
grant execute on function duc_resolve_incident(text, timestamptz, text, text, text) to authenticated;
