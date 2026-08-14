-- ============================================================================
-- Phase 4, bước con 7 (cutover ghi) — endShift_ (BaoCao.js): tính OEE, ghi
-- duc_bao_cao_ca + duc_lich_su_san_xuat, cập nhật shot khuôn, carry-over,
-- dọn Ca_hien_tai. Viết lại thành RPC Postgres cho trang tĩnh tương lai.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
--
-- KHÔNG bao gồm phần tạo báo cáo Google Docs → PDF (createShiftReportDoc)
-- — theo quyết định đã chốt với user, báo cáo kết ca sẽ đổi sang HTML/CSS +
-- xuất PDF bằng trình duyệt, làm ở giai đoạn viết giao diện, không phải RPC
-- backend. RPC này trả đủ dữ liệu thô (bao gồm chi tiết OEE từng dòng) để
-- trang tĩnh tự dựng báo cáo.
-- ============================================================================

-- ── Ca kế tiếp — giống getNextShift() (Utils.js) ───────────────────────────
create or replace function duc_get_next_shift(p_ngay date, p_ca text, p_phuong_an_ca text)
returns jsonb language plpgsql immutable as $$
begin
  if p_phuong_an_ca = '2 ca 12h' then
    if p_ca = 'Ca ngày' then return jsonb_build_object('ngay', p_ngay, 'ca', 'Ca đêm'); end if;
    if p_ca = 'Ca đêm' then return jsonb_build_object('ngay', p_ngay + 1, 'ca', 'Ca ngày'); end if;
  elsif p_phuong_an_ca = '2 ca 8h' then
    if p_ca = 'Ca 1' then return jsonb_build_object('ngay', p_ngay, 'ca', 'Ca 2'); end if;
    if p_ca = 'Ca 2' then return jsonb_build_object('ngay', p_ngay + 1, 'ca', 'Ca 1'); end if;
  end if;
  return null;
end;
$$;

-- ── Khung giờ nghỉ giải lao 1 ca — giống _resolveBreakWindows() (BaoCao.js).
-- LƯU Ý: chỉ hỗ trợ ĐÚNG 1 khung nghỉ/ca, khớp CONFIG.SHIFT_PLANS hiện tại
-- (mỗi ca có 1 break_windows). Nếu sau này công ty đổi thành nhiều khung nghỉ
-- /ca, phải sửa cả JS gốc lẫn hàm này cho khớp — xem ghi chú tương tự ở
-- duc_get_shift_window (migration_phase4_step5).
create or replace function duc_get_break_window(p_ngay date, p_phuong_an_ca text, p_ca text)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_h1 int; v_m1 int; v_h2 int; v_m2 int;
  v_cross boolean; v_start_h int;
  v_base date := p_ngay;
  v_start timestamptz; v_end timestamptz;
begin
  if p_phuong_an_ca = '2 ca 12h' and p_ca = 'Ca ngày' then
    v_h1:=12; v_m1:=0; v_h2:=12; v_m2:=45; v_cross:=false; v_start_h:=6;
  elsif p_phuong_an_ca = '2 ca 12h' and p_ca = 'Ca đêm' then
    v_h1:=0; v_m1:=0; v_h2:=1; v_m2:=0; v_cross:=true; v_start_h:=18;
  elsif p_phuong_an_ca = '2 ca 8h' and p_ca = 'Ca 1' then
    v_h1:=10; v_m1:=0; v_h2:=10; v_m2:=45; v_cross:=false; v_start_h:=6;
  elsif p_phuong_an_ca = '2 ca 8h' and p_ca = 'Ca 2' then
    v_h1:=18; v_m1:=0; v_h2:=18; v_m2:=45; v_cross:=false; v_start_h:=14;
  else
    return null;
  end if;

  if v_cross and v_h1 < v_start_h then v_base := p_ngay + 1; end if;
  v_start := (v_base::timestamp + make_interval(hours => v_h1, mins => v_m1)) at time zone 'Asia/Ho_Chi_Minh';
  v_end := (v_base::timestamp + make_interval(hours => v_h2, mins => v_m2)) at time zone 'Asia/Ho_Chi_Minh';
  if v_end <= v_start then return null; end if;
  return jsonb_build_object('start', v_start, 'end', v_end);
end;
$$;

-- Tổng giây overlap giữa [rowStart,rowEnd] và khung nghỉ — giống _sumBreakOverlap().
create or replace function duc_sum_break_overlap(p_row_start timestamptz, p_row_end timestamptz, p_break jsonb)
returns numeric
language sql
immutable
as $$
  select case
    when p_break is null or p_row_start is null or p_row_end is null or p_row_end <= p_row_start then 0
    else greatest(0, extract(epoch from (
      least(p_row_end, (p_break->>'end')::timestamptz) - greatest(p_row_start, (p_break->>'start')::timestamptz)
    )))
  end;
$$;

-- ── calculateOEE() (BaoCao.js) ──────────────────────────────────────────────
create or replace function duc_calculate_oee(p_ct_sec numeric, p_tt_ca numeric, p_ppt_sec numeric, p_downtime_sec numeric, p_ng_count numeric)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_run_time numeric; v_avail numeric; v_ideal numeric; v_perf numeric;
  v_ok numeric := coalesce(p_tt_ca, 0); v_ng numeric := coalesce(p_ng_count, 0); v_total numeric;
  v_quality numeric;
begin
  if p_ct_sec is null or p_ct_sec <= 0 then return null; end if;
  if p_ppt_sec is null or p_ppt_sec <= 0 then return null; end if;
  v_run_time := greatest(0, p_ppt_sec - coalesce(p_downtime_sec, 0));
  v_avail := v_run_time / p_ppt_sec;
  v_ideal := p_ct_sec * v_ok;
  v_perf := case when v_run_time > 0 then least(1, v_ideal / v_run_time) else 0 end;
  v_total := v_ok + v_ng;
  v_quality := case when v_total > 0 then v_ok / v_total else 1.0 end; -- CONFIG.DEFAULT_QUALITY = 1.0
  return jsonb_build_object(
    'availability', v_avail, 'performance', v_perf, 'quality', v_quality,
    'oee', v_avail * v_perf * v_quality, 'run_time_sec', v_run_time, 'downtime_sec', coalesce(p_downtime_sec, 0),
    'ok', v_ok, 'ng', v_ng
  );
end;
$$;

-- ── _computeMoldStatus() (ShotKhuon.js) — dùng lại cho update mold shots ────
create or replace function duc_compute_mold_status(p_tong_shot numeric, p_shot_bdgn numeric, p_nguong_bd numeric, p_nguong_lm numeric)
returns text language sql immutable as $$
  select case
    when p_tong_shot >= p_nguong_lm then 'Cần làm mới'
    when (p_tong_shot - p_shot_bdgn) >= p_nguong_bd then 'Cần bảo dưỡng'
    when (p_tong_shot - p_shot_bdgn) >= p_nguong_bd * 0.8 then 'Sắp bảo dưỡng'
    else 'OK'
  end;
$$;

-- ── updateMoldShotsFromShift_() (ShotKhuon.js) ──────────────────────────────
create or replace function duc_update_mold_shots_from_shift(p_ngay date, p_ca text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row record;
  v_pair_skip text[] := array[]::text[];
  v_shot_by_khuon jsonb := '{}'::jsonb;
  v_cavity numeric;
  v_shot_duc numeric;
  v_total numeric;
  v_existing record;
  v_now timestamptz := now();
  v_updated int := 0;
  v_warnings text[] := array[]::text[];
  v_khuon text;
  v_info jsonb;
  v_new_total numeric;
  v_status text;
begin
  for v_row in
    select id_dong, khuon_kep_voi from duc_ca_hien_tai
    where ngay = p_ngay and ca = p_ca and khuon_kep_voi is not null and khuon_kep_voi <> ''
  loop
    if not (v_row.id_dong = any(v_pair_skip)) and not (v_row.khuon_kep_voi = any(v_pair_skip)) then
      v_pair_skip := array_append(v_pair_skip,
        case when v_row.id_dong < v_row.khuon_kep_voi then v_row.khuon_kep_voi else v_row.id_dong end);
    end if;
  end loop;

  for v_row in
    select cht.id_dong, cht.so_khuon, cht.ma_sp, cht.tt_ca, cht.so_shot_nong_khuon, mp.cavity
    from duc_ca_hien_tai cht
    left join master_products mp on mp.ma_sp = cht.ma_sp
    where cht.ngay = p_ngay and cht.ca = p_ca and cht.so_khuon is not null and cht.so_khuon <> ''
  loop
    if v_row.id_dong = any(v_pair_skip) then continue; end if;
    v_cavity := v_row.cavity;
    if v_cavity is null or v_cavity <= 0 then
      v_warnings := array_append(v_warnings, 'SP ' || v_row.ma_sp || ' (khuôn ' || v_row.so_khuon || '): không có cavity — shot đúc không được tính.');
      v_shot_duc := 0;
    else
      v_shot_duc := floor(coalesce(v_row.tt_ca, 0) / v_cavity);
    end if;
    v_total := coalesce(v_row.so_shot_nong_khuon, 0) + v_shot_duc;

    v_info := coalesce(v_shot_by_khuon->v_row.so_khuon, jsonb_build_object('shot', 0, 'ma_sp_last', null));
    v_info := jsonb_set(v_info, '{shot}', to_jsonb((v_info->>'shot')::numeric + v_total));
    if v_total > 0 then
      v_info := jsonb_set(v_info, '{ma_sp_last}', to_jsonb(v_row.ma_sp));
    end if;
    v_shot_by_khuon := jsonb_set(v_shot_by_khuon, array[v_row.so_khuon], v_info);
  end loop;

  for v_khuon, v_info in select key, value from jsonb_each(v_shot_by_khuon) loop
    if (v_info->>'shot')::numeric = 0 then continue; end if;

    select tong_shot_luy_ke, nguong_bao_duong, nguong_lam_moi, shot_tai_lan_bao_duong_gan_nhat
    into v_existing from duc_shot_khuon where ma_khuon = v_khuon;

    if found then
      v_new_total := coalesce(v_existing.tong_shot_luy_ke, 0) + (v_info->>'shot')::numeric;
      v_status := duc_compute_mold_status(v_new_total, coalesce(v_existing.shot_tai_lan_bao_duong_gan_nhat, 0),
        coalesce(v_existing.nguong_bao_duong, 10000), coalesce(v_existing.nguong_lam_moi, 100000));
      update duc_shot_khuon set
        tong_shot_luy_ke = v_new_total, ten_sp_gan_nhat = coalesce(v_info->>'ma_sp_last', ten_sp_gan_nhat),
        trang_thai_khuon = v_status, last_updated_at = v_now
      where ma_khuon = v_khuon;
    else
      v_status := duc_compute_mold_status((v_info->>'shot')::numeric, 0, 10000, 100000);
      insert into duc_shot_khuon (ma_khuon, ten_sp_gan_nhat, tong_shot_luy_ke, nguong_bao_duong, nguong_lam_moi,
        shot_tai_lan_bao_duong_gan_nhat, trang_thai_khuon, ghi_chu, last_updated_at)
      values (v_khuon, v_info->>'ma_sp_last', (v_info->>'shot')::numeric, 10000, 100000, 0, v_status, '', v_now);
    end if;
    v_updated := v_updated + 1;
  end loop;

  return jsonb_build_object('updated', v_updated, 'warnings', to_jsonb(v_warnings));
end;
$$;
revoke execute on function duc_update_mold_shots_from_shift(date, text) from anon;
grant execute on function duc_update_mold_shots_from_shift(date, text) to authenticated;

-- ── Carry-over (khối "Carry-over" trong endShift_, BaoCao.js) ─────────────
create or replace function duc_carry_over_shift(p_ngay date, p_ca text, p_phuong_an_ca text, p_carry_over_list jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_next jsonb;
  v_item jsonb;
  v_old record;
  v_new_id_dong text;
  v_win jsonb;
  v_kh_ca_moi numeric;
  v_carry_shot numeric;
  v_old_to_new jsonb := '{}'::jsonb;
  v_now timestamptz := now();
  v_carried jsonb := '[]'::jsonb;
begin
  if p_carry_over_list is null or jsonb_array_length(p_carry_over_list) = 0 then
    return jsonb_build_object('carried', '[]'::jsonb, 'next_ngay', null, 'next_ca', null);
  end if;

  v_next := duc_get_next_shift(p_ngay, p_ca, p_phuong_an_ca);
  if v_next is null then
    raise exception 'Không xác định được ca kế tiếp cho % / %', p_phuong_an_ca, p_ca;
  end if;

  for v_item in select * from jsonb_array_elements(p_carry_over_list) loop
    select * into v_old from duc_ca_hien_tai
      where ngay = p_ngay and ca = p_ca and ma_may = (v_item->>'ma_may') and ma_sp = (v_item->>'ma_sp');
    if not found then continue; end if;

    v_new_id_dong := duc_make_id_dong((v_next->>'ngay')::date, v_next->>'ca', v_old.ma_may, v_old.ma_sp);
    if exists (select 1 from duc_ca_hien_tai where id_dong = v_new_id_dong) then continue; end if;

    v_win := duc_get_shift_window((v_next->>'ngay')::date, p_phuong_an_ca, v_next->>'ca');
    v_kh_ca_moi := coalesce((v_item->>'kh_ca_moi')::numeric, v_old.kh_ca, 0);

    v_carry_shot := v_old.so_shot_cuoi_ca;
    if v_carry_shot is null then
      select so_shot_cuoi_ca_gan_nhat into v_carry_shot from duc_shot_may where ma_may = v_old.ma_may;
    end if;

    insert into duc_ca_hien_tai (
      id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon,
      kh_ca, kh_tuan, tt_ca, tt_tuan, nv_ca_ngay, nv_ca_dem,
      open_loai_su_co, open_gio_phat_sinh, open_van_de, open_noi_dung_xu_ly, open_dam_nhiem,
      version, last_updated_by, last_updated_at,
      so_shot_nong_khuon, so_luong_ng, phan_loai_ng, sp_start_time, sp_end_time, so_shot_khuon_snapshot,
      so_shot_dau_ca, so_shot_cuoi_ca
    ) values (
      v_new_id_dong, (v_next->>'ngay')::date, v_next->>'ca', p_phuong_an_ca, duc_iso_week((v_next->>'ngay')::date),
      v_old.ma_may, v_old.ma_sp, v_old.ten_sp, v_old.so_khuon,
      v_kh_ca_moi, coalesce((v_item->>'kh_tuan_moi')::numeric, v_old.kh_tuan, 0), 0, 0,
      v_old.nv_ca_ngay, v_old.nv_ca_dem,
      case when v_old.open_gio_phat_sinh is not null then v_old.open_loai_su_co else null end,
      v_old.open_gio_phat_sinh,
      v_old.open_van_de,
      case when v_old.open_gio_phat_sinh is not null
        then coalesce(v_old.open_noi_dung_xu_ly, '') || (case when coalesce(v_old.open_noi_dung_xu_ly, '') <> '' then E'\n' else '' end) ||
             '[Chuyển tiếp từ ' || p_ca || ' ' || to_char(p_ngay, 'DD/MM/YYYY') || ']'
        else null end,
      v_old.open_dam_nhiem,
      1, 'system@carry-over', v_now,
      0, 0, '', coalesce((v_win->>'start')::timestamptz, v_now), (v_win->>'end')::timestamptz, 0,
      v_carry_shot, null
    );

    v_old_to_new := jsonb_set(v_old_to_new, array[v_old.id_dong], to_jsonb(v_new_id_dong));
    v_carried := v_carried || jsonb_build_array(jsonb_build_object(
      'ma_may', v_old.ma_may, 'ma_sp', v_old.ma_sp, 'kh_ca', v_kh_ca_moi,
      'has_open_incident', v_old.open_gio_phat_sinh is not null
    ));
  end loop;

  for v_old in select id_dong, khuon_kep_voi from duc_ca_hien_tai
    where ngay = p_ngay and ca = p_ca and khuon_kep_voi is not null and khuon_kep_voi <> ''
  loop
    if v_old_to_new ? v_old.id_dong and v_old_to_new ? v_old.khuon_kep_voi then
      update duc_ca_hien_tai set khuon_kep_voi = v_old_to_new->>v_old.khuon_kep_voi
      where id_dong = v_old_to_new->>v_old.id_dong;
    end if;
  end loop;

  return jsonb_build_object('carried', v_carried, 'next_ngay', v_next->>'ngay', 'next_ca', v_next->>'ca');
end;
$$;
revoke execute on function duc_carry_over_shift(date, text, text, jsonb) from anon;
grant execute on function duc_carry_over_shift(date, text, text, jsonb) to authenticated;

-- ── endShift_() — RPC chính, gói toàn bộ quy trình kết ca ──────────────────
-- Trả về đủ dữ liệu (kể cả oee_rows chi tiết từng dòng) để trang tĩnh tự
-- dựng báo cáo HTML/PDF — KHÔNG tự tạo Google Doc như bản cũ.
create or replace function duc_end_shift(
  p_ngay date, p_ca text, p_phuong_an_ca text, p_truong_ca text,
  p_carry_over_list jsonb, p_comment_truong_ca text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := now();
  v_shift_window jsonb;
  v_break_window jsonb;
  v_shift_duration_sec numeric;
  v_break_min numeric;
  v_carry_over_keys text[] := array[]::text[];
  v_item jsonb;
  v_open_not_carried text[] := array[]::text[];
  v_row record;
  v_downtime_by_key jsonb := '{}'::jsonb;
  v_key text;
  v_open_start timestamptz; v_seg_start timestamptz; v_seg_end timestamptz;
  v_id_bao_cao text;
  v_sum_ideal numeric := 0; v_sum_ppt numeric := 0; v_sum_runtime numeric := 0;
  v_sum_ok numeric := 0; v_sum_ng numeric := 0;
  v_so_may_co_kh int := 0; v_so_may_hoan_thanh int := 0; v_tong_kh numeric := 0; v_tong_tt numeric := 0;
  v_tong_shot_nong numeric := 0;
  v_so_su_co_ca int; v_so_su_co_dang_do int; v_tong_phut_resolved numeric := 0; v_tong_phut_open numeric := 0;
  v_avail_ca numeric; v_perf_ca numeric; v_quality_ca numeric; v_oee_ca numeric;
  v_is_day_shift boolean;
  v_personnel text[] := array[]::text[];
  v_nv text;
  v_ct numeric; v_downtime numeric; v_row_ppt numeric; v_oee jsonb;
  v_effective_start timestamptz; v_effective_end timestamptz; v_row_span numeric; v_break_sec numeric;
  v_oee_rows jsonb := '[]'::jsonb;
  v_mold_result jsonb;
  v_carry_result jsonb;
  v_history_count int := 0;
begin
  v_is_day_shift := (p_ca = 'Ca ngày' or p_ca = 'Ca 1');

  -- Danh sách (ma_may|ma_sp) được tick "tiếp tục" (carry-over)
  for v_item in select * from jsonb_array_elements(coalesce(p_carry_over_list, '[]'::jsonb)) loop
    v_carry_over_keys := array_append(v_carry_over_keys, (v_item->>'ma_may') || '|' || (v_item->>'ma_sp'));
  end loop;

  -- Sự cố đang mở nhưng KHÔNG được tick tiếp tục → chặn kết ca
  for v_row in select ma_may, ma_sp from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and open_gio_phat_sinh is not null loop
    if not ((v_row.ma_may || '|' || v_row.ma_sp) = any(v_carry_over_keys)) then
      v_open_not_carried := array_append(v_open_not_carried, v_row.ma_may || ' (' || v_row.ma_sp || ')');
    end if;
  end loop;
  if array_length(v_open_not_carried, 1) > 0 then
    return jsonb_build_object('ok', false, 'error',
      'Các máy sau đang có sự cố mở nhưng chưa được tick tiếp tục: ' || array_to_string(v_open_not_carried, ', ') ||
      '. Vui lòng resolve sự cố trước khi kết ca, hoặc tick tiếp tục cho máy này.');
  end if;

  if not exists (select 1 from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca)
     and not exists (select 1 from duc_su_co_log where ngay = p_ngay and ca = p_ca) then
    return jsonb_build_object('ok', false, 'error', 'Không có bản ghi đầy đủ thông tin để lưu');
  end if;

  v_shift_window := duc_get_shift_window(p_ngay, p_phuong_an_ca, p_ca);
  if v_shift_window is null then
    return jsonb_build_object('ok', false, 'error', 'Không xác định được khung giờ ca: ' || p_phuong_an_ca || ' / ' || p_ca);
  end if;
  v_shift_duration_sec := extract(epoch from ((v_shift_window->>'end')::timestamptz - (v_shift_window->>'start')::timestamptz));
  v_break_window := duc_get_break_window(p_ngay, p_phuong_an_ca, p_ca);
  v_break_min := case when v_break_window is not null
    then extract(epoch from ((v_break_window->>'end')::timestamptz - (v_break_window->>'start')::timestamptz)) / 60
    else 0 end;

  -- Downtime theo (ma_may,ma_sp): từ sự cố đã đóng trong ca (duc_su_co_log) +
  -- phần TRONG CA HIỆN TẠI của sự cố còn đang mở (carry-over), không đếm dồn từ mốc gốc.
  for v_row in
    select ma_may, ma_sp, sum(coalesce(thoi_gian_dung_phut, 0)) * 60 as sec
    from duc_su_co_log where ngay = p_ngay and ca = p_ca
    group by ma_may, ma_sp
  loop
    v_key := v_row.ma_may || '|' || v_row.ma_sp;
    v_downtime_by_key := jsonb_set(v_downtime_by_key, array[v_key], to_jsonb(v_row.sec::numeric));
  end loop;

  for v_row in select ma_may, ma_sp, open_gio_phat_sinh from duc_ca_hien_tai
    where ngay = p_ngay and ca = p_ca and open_gio_phat_sinh is not null
  loop
    v_key := v_row.ma_may || '|' || v_row.ma_sp;
    v_open_start := v_row.open_gio_phat_sinh;
    v_seg_start := greatest(v_open_start, (v_shift_window->>'start')::timestamptz);
    v_seg_end := least(v_now, (v_shift_window->>'end')::timestamptz);
    v_downtime_by_key := jsonb_set(v_downtime_by_key, array[v_key],
      to_jsonb(coalesce((v_downtime_by_key->>v_key)::numeric, 0) + greatest(0, extract(epoch from (v_seg_end - v_seg_start)))));
    v_tong_phut_open := v_tong_phut_open + greatest(0, round(extract(epoch from (v_seg_end - v_seg_start)) / 60));
  end loop;

  select coalesce(sum(thoi_gian_dung_phut), 0) into v_tong_phut_resolved from duc_su_co_log where ngay = p_ngay and ca = p_ca;
  select count(*) into v_so_su_co_ca from duc_su_co_log where ngay = p_ngay and ca = p_ca;
  select count(*) into v_so_su_co_dang_do from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and open_gio_phat_sinh is not null;

  -- Per-row OEE cho các dòng có kế hoạch (ma_sp + kh_ca)
  for v_row in select * from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and ma_sp is not null and ma_sp <> '' and kh_ca is not null loop
    v_so_may_co_kh := v_so_may_co_kh + 1;
    if coalesce(v_row.tt_ca, 0) >= coalesce(v_row.kh_ca, 0) then v_so_may_hoan_thanh := v_so_may_hoan_thanh + 1; end if;
    v_tong_kh := v_tong_kh + coalesce(v_row.kh_ca, 0);
    v_tong_tt := v_tong_tt + coalesce(v_row.tt_ca, 0);
    v_tong_shot_nong := v_tong_shot_nong + coalesce(v_row.so_shot_nong_khuon, 0);
    v_sum_ok := v_sum_ok + coalesce(v_row.tt_ca, 0);
    v_sum_ng := v_sum_ng + coalesce(v_row.so_luong_ng, 0);

    v_nv := case when v_is_day_shift then v_row.nv_ca_ngay else v_row.nv_ca_dem end;
    if v_nv is not null and trim(v_nv) <> '' and not (trim(v_nv) = any(v_personnel)) then
      v_personnel := array_append(v_personnel, trim(v_nv));
    end if;

    -- Effective PPT (giờ chạy thực tế trừ giờ nghỉ) theo đúng logic _computeRowPptSec
    if v_row.sp_start_time is not null and v_row.sp_end_time is not null then
      v_effective_start := v_row.sp_start_time;
      v_effective_end := least(v_row.sp_end_time, v_now);
      v_row_span := greatest(0, extract(epoch from (v_effective_end - v_effective_start)));
    else
      v_effective_start := (v_shift_window->>'start')::timestamptz;
      v_effective_end := least(v_now, (v_shift_window->>'end')::timestamptz);
      v_row_span := greatest(0, extract(epoch from (v_effective_end - v_effective_start)));
    end if;

    if v_break_window is not null then
      v_break_sec := duc_sum_break_overlap(v_effective_start, v_effective_end, v_break_window);
    else
      v_break_sec := case when v_shift_duration_sec > 0 then (v_break_min * 60 * v_row_span / v_shift_duration_sec) else 0 end;
    end if;
    v_row_ppt := greatest(0, v_row_span - v_break_sec);

    select cycle_time_s into v_ct from master_products where ma_sp = v_row.ma_sp;
    v_key := v_row.ma_may || '|' || v_row.ma_sp;
    v_downtime := coalesce((v_downtime_by_key->>v_key)::numeric, 0);
    v_oee := duc_calculate_oee(v_ct, v_row.tt_ca, v_row_ppt, v_downtime, v_row.so_luong_ng);
    v_oee_rows := v_oee_rows || jsonb_build_array(jsonb_build_object(
      'id_dong', v_row.id_dong, 'ma_may', v_row.ma_may, 'ma_sp', v_row.ma_sp, 'oee', v_oee
    ));

    if v_ct is not null and v_ct > 0 then
      v_sum_ideal := v_sum_ideal + v_ct * coalesce(v_row.tt_ca, 0);
      v_sum_ppt := v_sum_ppt + v_row_ppt;
      v_sum_runtime := v_sum_runtime + greatest(0, v_row_ppt - v_downtime);
    end if;
  end loop;

  v_avail_ca := case when v_sum_ppt > 0 then v_sum_runtime / v_sum_ppt else 0 end;
  v_perf_ca := case when v_sum_runtime > 0 then least(1, v_sum_ideal / v_sum_runtime) else 0 end;
  v_quality_ca := case when (v_sum_ok + v_sum_ng) > 0 then v_sum_ok / (v_sum_ok + v_sum_ng) else 1.0 end;
  v_oee_ca := v_avail_ca * v_perf_ca * v_quality_ca;

  v_id_bao_cao := to_char(p_ngay, 'DDMMYYYY') || '_' || duc_shift_short_id(p_ca);

  insert into duc_bao_cao_ca (
    id_bao_cao, ngay, ca, phuong_an_ca, tuan_sx, truong_ca, so_may_co_kh, so_may_hoan_thanh_kh,
    tong_kh_ca, tong_tt_ca, ty_le_hoan_thanh_ca, so_su_co_ca, tong_phut_dung_ca, url_gdoc_bao_cao,
    thoi_diem_ket_ca, ghi_chu, oee_ca, availability_ca, performance_ca, quality_ca, tong_ng_ca,
    tong_shot_nong_khuon_ca, comment_truong_ca, nv_ca_bao_cao
  ) values (
    v_id_bao_cao, p_ngay, p_ca, p_phuong_an_ca, duc_iso_week(p_ngay), coalesce(p_truong_ca, p_user),
    v_so_may_co_kh, v_so_may_hoan_thanh, v_tong_kh, v_tong_tt,
    case when v_tong_kh > 0 then v_tong_tt / v_tong_kh else 0 end,
    v_so_su_co_ca, v_tong_phut_resolved + v_tong_phut_open, null, v_now,
    case when v_so_su_co_dang_do > 0 then v_so_su_co_dang_do || ' sự cố dang dở → ca sau' else '' end,
    v_oee_ca, v_avail_ca, v_perf_ca, v_quality_ca, v_sum_ng, v_tong_shot_nong,
    coalesce(p_comment_truong_ca, ''), array_to_string(v_personnel, ', ')
  )
  on conflict (id_bao_cao) do update set
    truong_ca = excluded.truong_ca, so_may_co_kh = excluded.so_may_co_kh, so_may_hoan_thanh_kh = excluded.so_may_hoan_thanh_kh,
    tong_kh_ca = excluded.tong_kh_ca, tong_tt_ca = excluded.tong_tt_ca, ty_le_hoan_thanh_ca = excluded.ty_le_hoan_thanh_ca,
    so_su_co_ca = excluded.so_su_co_ca, tong_phut_dung_ca = excluded.tong_phut_dung_ca,
    thoi_diem_ket_ca = excluded.thoi_diem_ket_ca, ghi_chu = excluded.ghi_chu, oee_ca = excluded.oee_ca,
    availability_ca = excluded.availability_ca, performance_ca = excluded.performance_ca, quality_ca = excluded.quality_ca,
    tong_ng_ca = excluded.tong_ng_ca, tong_shot_nong_khuon_ca = excluded.tong_shot_nong_khuon_ca,
    comment_truong_ca = excluded.comment_truong_ca, nv_ca_bao_cao = excluded.nv_ca_bao_cao;

  -- Lưu lịch sử sản xuất (appendProductionHistory_, BaoCaoTuan.js) — nguồn cho báo cáo tuần
  insert into duc_lich_su_san_xuat (ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, kh_ca, tt_ca, so_luong_ng, thoi_diem_ghi)
  select p_ngay, p_ca, p_phuong_an_ca, duc_iso_week(p_ngay), ma_may, ma_sp, ten_sp, coalesce(kh_ca, 0), coalesce(tt_ca, 0), coalesce(so_luong_ng, 0), v_now
  from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and ma_sp is not null and ma_sp <> '' and kh_ca is not null
  on conflict (ngay, ca, ma_may, ma_sp) do update set
    kh_ca = excluded.kh_ca, tt_ca = excluded.tt_ca, so_luong_ng = excluded.so_luong_ng, thoi_diem_ghi = excluded.thoi_diem_ghi;
  get diagnostics v_history_count = row_count;

  -- Cập nhật shot khuôn (lỗi ở đây không chặn toàn bộ, giống try/catch bản gốc)
  begin
    v_mold_result := duc_update_mold_shots_from_shift(p_ngay, p_ca);
  exception when others then
    v_mold_result := jsonb_build_object('updated', 0, 'warnings', jsonb_build_array('Lỗi cập nhật khuôn: ' || sqlerrm));
  end;

  -- Carry-over kế hoạch/sự cố mở sang ca sau
  v_carry_result := duc_carry_over_shift(p_ngay, p_ca, p_phuong_an_ca, p_carry_over_list);

  -- Dọn Ca_hien_tai của ca vừa đóng (clearCaHienTai_)
  delete from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca;

  return jsonb_build_object(
    'ok', true, 'id_bao_cao', v_id_bao_cao,
    'summary', jsonb_build_object(
      'so_may_co_kh', v_so_may_co_kh, 'so_may_hoan_thanh_kh', v_so_may_hoan_thanh,
      'tong_kh_ca', v_tong_kh, 'tong_tt_ca', v_tong_tt,
      'so_su_co_ca', v_so_su_co_ca, 'so_su_co_dang_do', v_so_su_co_dang_do,
      'tong_phut_dung_ca', v_tong_phut_resolved + v_tong_phut_open,
      'oee_ca', v_oee_ca, 'availability_ca', v_avail_ca, 'performance_ca', v_perf_ca, 'quality_ca', v_quality_ca,
      'tong_ng_ca', v_sum_ng, 'tong_shot_nong_khuon_ca', v_tong_shot_nong,
      'nv_ca_bao_cao', array_to_string(v_personnel, ', ')
    ),
    'oee_rows', v_oee_rows,
    'mold_update', v_mold_result,
    'carry_over', v_carry_result,
    'history_rows', v_history_count
  );
end;
$$;
revoke execute on function duc_end_shift(date, text, text, text, jsonb, text, text) from anon;
grant execute on function duc_end_shift(date, text, text, text, jsonb, text, text) to authenticated;

-- ── saveTieuChuan_ / uploadTieuChuanPdf_ (IpqcCheckpoint.js) ────────────────
-- PDF: trình duyệt tự upload lên Storage bucket "report-files" (đã tạo ở D0),
-- rồi truyền URL vào p_file_pdf_url (thay _uploadNcpImage_/DriveApp.createFile).
create or replace function duc_ipqc_save_tieu_chuan(p_ma_sp text, p_muc_kiem jsonb, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := now();
begin
  if p_ma_sp is null or trim(p_ma_sp) = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã SP'); end if;
  if p_muc_kiem is null or jsonb_array_length(p_muc_kiem) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Checklist cần ít nhất 1 mục kiểm');
  end if;

  insert into duc_ipqc_tieuchuan (ma_sp, danh_sach_muc_kiem_json, cap_nhat_lan_cuoi_boi, thoi_diem_cap_nhat)
  values (trim(p_ma_sp), p_muc_kiem, p_user, v_now)
  on conflict (ma_sp) do update set
    danh_sach_muc_kiem_json = excluded.danh_sach_muc_kiem_json,
    cap_nhat_lan_cuoi_boi = excluded.cap_nhat_lan_cuoi_boi, thoi_diem_cap_nhat = excluded.thoi_diem_cap_nhat;

  return jsonb_build_object('ok', true, 'ma_sp', trim(p_ma_sp));
end;
$$;
revoke execute on function duc_ipqc_save_tieu_chuan(text, jsonb, text) from anon;
grant execute on function duc_ipqc_save_tieu_chuan(text, jsonb, text) to authenticated;

create or replace function duc_ipqc_set_tieu_chuan_pdf(p_ma_sp text, p_url text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := now();
begin
  if p_ma_sp is null or trim(p_ma_sp) = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã SP'); end if;
  if p_url is null or trim(p_url) = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu URL file PDF'); end if;

  insert into duc_ipqc_tieuchuan (ma_sp, file_pdf_url, cap_nhat_lan_cuoi_boi, thoi_diem_cap_nhat)
  values (trim(p_ma_sp), p_url, p_user, v_now)
  on conflict (ma_sp) do update set
    file_pdf_url = excluded.file_pdf_url, cap_nhat_lan_cuoi_boi = excluded.cap_nhat_lan_cuoi_boi, thoi_diem_cap_nhat = excluded.thoi_diem_cap_nhat;

  return jsonb_build_object('ok', true, 'ma_sp', trim(p_ma_sp), 'url', p_url);
end;
$$;
revoke execute on function duc_ipqc_set_tieu_chuan_pdf(text, text, text) from anon;
grant execute on function duc_ipqc_set_tieu_chuan_pdf(text, text, text) to authenticated;
