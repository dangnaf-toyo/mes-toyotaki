-- ============================================================================
-- Phase 4, bước con 5 (cutover ghi) — resolveIncident_ (BanGhiSuCo.js), gồm cả
-- logic chia đoạn sự cố qua nhiều ca (splitIncidentByShift_, Utils.js:
-- getShiftWindow/getPrevShift) viết lại thành SQL.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ── Helpers dùng chung (song song với JS gốc trong Utils.js) ──────────────
create or replace function duc_shift_short_id(p_ca text)
returns text language sql immutable as $$
  select case p_ca
    when 'Ca ngày' then 'Cangay'
    when 'Ca đêm' then 'Cadem'
    when 'Ca 1' then 'Ca1'
    when 'Ca 2' then 'Ca2'
    else regexp_replace(p_ca, '\s+', '', 'g')
  end;
$$;

create or replace function duc_make_id_dong(p_ngay date, p_ca text, p_ma_may text, p_ma_sp text)
returns text language sql immutable as $$
  select to_char(p_ngay, 'DDMMYYYY') || '_' || duc_shift_short_id(p_ca) || '_' || duc_normalize_name(p_ma_may) || '_' || coalesce(p_ma_sp, '');
$$;

-- ISO week, format "W##_YYYY" giống getISOWeek() (Utils.js).
create or replace function duc_iso_week(p_ngay date)
returns text language sql immutable as $$
  select 'W' || to_char(p_ngay, 'IW') || '_' || to_char(p_ngay, 'IYYY');
$$;

-- Khung giờ 1 ca cụ thể — giống getShiftWindow() (Utils.js). CONFIG.SHIFT_PLANS
-- hiện chỉ có 2 phương án ca (đúng bản gốc), hardcode thẳng vào đây.
create or replace function duc_get_shift_window(p_ngay date, p_phuong_an_ca text, p_ca text)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_start_h int; v_start_m int := 0; v_end_h int; v_end_m int := 0; v_cross boolean;
  v_start timestamptz; v_end timestamptz;
begin
  if p_phuong_an_ca = '2 ca 12h' then
    if p_ca = 'Ca ngày' then v_start_h:=6; v_end_h:=18; v_cross:=false;
    elsif p_ca = 'Ca đêm' then v_start_h:=18; v_end_h:=6; v_cross:=true;
    else return null; end if;
  elsif p_phuong_an_ca = '2 ca 8h' then
    if p_ca = 'Ca 1' then v_start_h:=6; v_end_h:=14; v_cross:=false;
    elsif p_ca = 'Ca 2' then v_start_h:=14; v_end_h:=22; v_cross:=false;
    else return null; end if;
  else
    return null;
  end if;

  v_start := (p_ngay::timestamp + make_interval(hours => v_start_h, mins => v_start_m)) at time zone 'Asia/Ho_Chi_Minh';
  v_end := (p_ngay::timestamp + make_interval(hours => v_end_h, mins => v_end_m)) at time zone 'Asia/Ho_Chi_Minh';
  if v_cross then v_end := v_end + interval '1 day'; end if;
  return jsonb_build_object('start', v_start, 'end', v_end);
end;
$$;

-- Ca liền trước — giống getPrevShift() (Utils.js).
create or replace function duc_get_prev_shift(p_ngay date, p_ca text, p_phuong_an_ca text)
returns jsonb
language plpgsql
immutable
as $$
begin
  if p_phuong_an_ca = '2 ca 12h' then
    if p_ca = 'Ca đêm' then return jsonb_build_object('ngay', p_ngay, 'ca', 'Ca ngày'); end if;
    if p_ca = 'Ca ngày' then return jsonb_build_object('ngay', p_ngay - 1, 'ca', 'Ca đêm'); end if;
  elsif p_phuong_an_ca = '2 ca 8h' then
    if p_ca = 'Ca 2' then return jsonb_build_object('ngay', p_ngay, 'ca', 'Ca 1'); end if;
    if p_ca = 'Ca 1' then return jsonb_build_object('ngay', p_ngay - 1, 'ca', 'Ca 2'); end if;
  end if;
  return null;
end;
$$;

-- Cắt [openTime, gioTroLai) thành nhiều đoạn theo ranh giới ca — giống
-- splitIncidentByShift_() (BanGhiSuCo.js). Trả về 1 dòng/đoạn.
create or replace function duc_split_incident_by_shift(
  p_open_time timestamptz, p_gio_tro_lai timestamptz, p_phuong_an_ca text, p_end_ngay date, p_end_ca text
)
returns table(ngay date, ca text, seg_start timestamptz, seg_end timestamptz, phut int)
language plpgsql
immutable
as $$
declare
  chain_ngay date[] := array[p_end_ngay];
  chain_ca text[] := array[p_end_ca];
  v_win jsonb;
  v_prev jsonb;
  v_guard int := 0;
  i int;
  v_seg_start timestamptz;
  v_seg_end timestamptz;
  v_found boolean := false;
begin
  loop
    v_win := duc_get_shift_window(chain_ngay[1], p_phuong_an_ca, chain_ca[1]);
    exit when v_win is null; -- fallback bên dưới nếu không xác định được cấu hình ca
    exit when p_open_time >= (v_win->>'start')::timestamptz;
    v_prev := duc_get_prev_shift(chain_ngay[1], chain_ca[1], p_phuong_an_ca);
    exit when v_prev is null;
    chain_ngay := array_prepend((v_prev->>'ngay')::date, chain_ngay);
    chain_ca := array_prepend(v_prev->>'ca', chain_ca);
    v_guard := v_guard + 1;
    exit when v_guard > 20;
  end loop;

  for i in 1 .. array_length(chain_ngay, 1) loop
    v_win := duc_get_shift_window(chain_ngay[i], p_phuong_an_ca, chain_ca[i]);
    if v_win is null then continue; end if;
    v_seg_start := case when i = 1 then p_open_time else (v_win->>'start')::timestamptz end;
    v_seg_end := case when i = array_length(chain_ngay, 1) then p_gio_tro_lai else (v_win->>'end')::timestamptz end;
    if v_seg_end > v_seg_start then
      ngay := chain_ngay[i]; ca := chain_ca[i]; seg_start := v_seg_start; seg_end := v_seg_end;
      phut := round(extract(epoch from (v_seg_end - v_seg_start)) / 60);
      v_found := true;
      return next;
    end if;
  end loop;

  -- Fallback an toàn: không xác định được chuỗi ca → giữ nguyên 1 khối gán cho ca hiện tại
  if not v_found then
    ngay := p_end_ngay; ca := p_end_ca; seg_start := p_open_time; seg_end := p_gio_tro_lai;
    phut := round(extract(epoch from (p_gio_tro_lai - p_open_time)) / 60);
    return next;
  end if;
end;
$$;

-- ── resolveIncident_ (BanGhiSuCo.js) — RPC chính ────────────────────────────
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

  -- V2.3: vừa xử lý xong sự cố → bắt buộc IPQC kiểm tra lại. Lỗi ở đây không
  -- được làm hỏng luồng chính, giống try/catch bản gốc.
  begin
    perform duc_request_ipqc_check(p_id_dong, 'sau_su_co', v_last_id);
  exception when others then
    null;
  end;

  return jsonb_build_object(
    'ok', true, 'id_ban_ghi', v_last_id, 'id_ban_ghi_list', to_jsonb(v_created_ids),
    'thoi_gian_dung_phut', v_total_phut
  );
end;
$$;
revoke execute on function duc_resolve_incident(text, timestamptz, text, text, text) from anon;
grant execute on function duc_resolve_incident(text, timestamptz, text, text, text) to authenticated;

-- Sửa lại duc_close_f1_incident_if_open (bước con 4) — dùng đúng duc_iso_week
-- thay vì định dạng "W"WW_YYYY (tuần theo lịch, KHÔNG phải tuần ISO — sai so
-- với getISOWeek() bản gốc). Phát hiện khi viết bước con 5, sửa luôn tại đây.
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
    v_id_ban_ghi, v_cht.ngay, v_cht.ca, duc_iso_week(v_cht.ngay), v_cht.ma_may, v_cht.ma_sp, v_cht.ten_sp, v_cht.so_khuon,
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
