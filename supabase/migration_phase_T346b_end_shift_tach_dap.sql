-- T346b (25/11/2026): duc_end_shift — tổng KH/TT/NG/OEE/máy có KH của ca CHỈ tính máy đúc;
-- máy "Dập …" cộng riêng vào tong_kh_dap / tong_tt_dap / tong_ng_dap. Phần còn lại giữ nguyên bản T243.
CREATE OR REPLACE FUNCTION public.duc_end_shift(p_ngay date, p_ca text, p_phuong_an_ca text, p_truong_ca text, p_carry_over_list jsonb, p_comment_truong_ca text, p_user text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_now timestamptz := now();
  v_shift_window jsonb; v_break_window jsonb; v_shift_duration_sec numeric; v_break_min numeric;
  v_ws timestamptz; v_we timestamptz;
  v_carry_over_keys text[] := array[]::text[]; v_item jsonb; v_open_not_carried text[] := array[]::text[];
  v_row record; v_id_bao_cao text;
  v_sum_ideal numeric := 0; v_sum_ppt numeric := 0; v_sum_runtime numeric := 0; v_sum_ok numeric := 0; v_sum_ng numeric := 0;
  v_so_may_co_kh int := 0; v_so_may_hoan_thanh int := 0; v_tong_kh numeric := 0; v_tong_tt numeric := 0; v_tong_shot_nong numeric := 0;
  v_kh_dap numeric := 0; v_tt_dap numeric := 0; v_ng_dap numeric := 0;   -- T346
  v_so_su_co_ca int; v_so_su_co_dang_do int; v_tong_phut_resolved numeric := 0; v_tong_phut_open numeric := 0;
  v_avail_ca numeric; v_perf_ca numeric; v_quality_ca numeric; v_oee_ca numeric;
  v_is_day_shift boolean; v_personnel text[] := array[]::text[]; v_nv text;
  v_ct numeric; v_downtime numeric; v_row_ppt numeric; v_oee jsonb;
  v_effective_start timestamptz; v_effective_end timestamptz; v_row_span numeric; v_break_sec numeric;
  v_oee_rows jsonb := '[]'::jsonb; v_mold_result jsonb; v_carry_result jsonb; v_history_count int := 0; v_tem_mo_coi jsonb;
begin
  if auth.uid() is not null and not public.has_role(VARIADIC ARRAY['admin', 'truong_ca', 'quan_ly_bo_phan', 'qlsx_truong_phong']) then
    raise exception '⛔ Tài khoản không có quyền thực hiện thao tác này — cần vai trò: %', 'Trưởng ca / QLBP / TP QLSX' using errcode = '42501';
  end if;
  p_user := public.duc_ten_nguoi_hien_tai(p_user);
  v_is_day_shift := (p_ca = 'Ca ngày' or p_ca = 'Ca 1');

  for v_item in select * from jsonb_array_elements(coalesce(p_carry_over_list, '[]'::jsonb)) loop
    v_carry_over_keys := array_append(v_carry_over_keys, (v_item->>'ma_may') || '|' || (v_item->>'ma_sp'));
  end loop;
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
  v_ws := (v_shift_window->>'start')::timestamptz;
  v_we := least(v_now, (v_shift_window->>'end')::timestamptz);
  v_shift_duration_sec := extract(epoch from ((v_shift_window->>'end')::timestamptz - v_ws));
  v_break_window := duc_get_break_window(p_ngay, p_phuong_an_ca, p_ca);
  v_break_min := case when v_break_window is not null
    then extract(epoch from ((v_break_window->>'end')::timestamptz - (v_break_window->>'start')::timestamptz)) / 60 else 0 end;

  -- T243 (R13/R14): phần trong ca của sự cố còn mở, HỢP theo MÁY, trừ phần đã nằm trong sự cố đã
  -- đóng của máy; máy ở ca không sản xuất theo KHSX không tính.
  select coalesce(sum(sec), 0) / 60 into v_tong_phut_open from (
    with mo as (
      select c.ma_may, tstzrange(greatest(c.open_gio_phat_sinh, v_ws), v_we) r from duc_ca_hien_tai c
       where c.ngay = p_ngay and c.ca = p_ca and c.open_gio_phat_sinh is not null and greatest(c.open_gio_phat_sinh, v_ws) < v_we
         and not duc_ca_khong_sx(p_ngay, c.ma_may)
      union all
      select c.ma_may, tstzrange(greatest(t.gio_phat_sinh, v_ws), v_we) from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong
       where c.ngay = p_ngay and c.ca = p_ca and greatest(t.gio_phat_sinh, v_ws) < v_we and not duc_ca_khong_sx(p_ngay, c.ma_may)),
    g as (select ma_may, range_agg(r) mr from mo group by ma_may),
    dong as (select ma_may, range_agg(tstzrange(gio_phat_sinh, gio_tro_lai)) mr from duc_su_co_log
              where ngay = p_ngay and ca = p_ca and gio_tro_lai > gio_phat_sinh group by ma_may)
    select (select coalesce(sum(extract(epoch from upper(x) - lower(x))), 0) from unnest(g.mr - coalesce(dong.mr, '{}'::tstzmultirange)) x) sec
    from g left join dong on dong.ma_may = g.ma_may) z;
  v_tong_phut_open := round(v_tong_phut_open);

  select coalesce(sum(coalesce(phut_dung_may, thoi_gian_dung_phut)), 0) into v_tong_phut_resolved from duc_su_co_log where ngay = p_ngay and ca = p_ca;
  select count(*) into v_so_su_co_ca from duc_su_co_log where ngay = p_ngay and ca = p_ca;
  select count(*) + (select count(*) from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong where c.ngay = p_ngay and c.ca = p_ca)
    into v_so_su_co_dang_do from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and open_gio_phat_sinh is not null;

  for v_row in select * from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and ma_sp is not null and ma_sp <> '' and kh_ca is not null loop
    v_nv := case when v_is_day_shift then v_row.nv_ca_ngay else v_row.nv_ca_dem end;
    if v_nv is not null and trim(v_nv) <> '' and not (trim(v_nv) = any(v_personnel)) then v_personnel := array_append(v_personnel, trim(v_nv)); end if;

    -- T346: máy Dập cộng riêng, không vào tổng/OEE của Đúc
    if duc_la_may_dap(v_row.ma_may) then
      v_kh_dap := v_kh_dap + coalesce(v_row.kh_ca, 0);
      v_tt_dap := v_tt_dap + coalesce(v_row.tt_ca, 0);
      v_ng_dap := v_ng_dap + coalesce(v_row.so_luong_ng, 0);
      continue;
    end if;

    v_tong_kh := v_tong_kh + coalesce(v_row.kh_ca, 0);
    v_tong_tt := v_tong_tt + coalesce(v_row.tt_ca, 0);
    v_tong_shot_nong := v_tong_shot_nong + coalesce(v_row.so_shot_nong_khuon, 0);
    v_sum_ok := v_sum_ok + coalesce(v_row.tt_ca, 0);
    v_sum_ng := v_sum_ng + coalesce(v_row.so_luong_ng, 0);

    if v_row.sp_start_time is not null and v_row.sp_end_time is not null then
      v_effective_start := v_row.sp_start_time; v_effective_end := least(v_row.sp_end_time, v_now);
    else
      v_effective_start := v_ws; v_effective_end := v_we;
    end if;
    v_row_span := greatest(0, extract(epoch from (v_effective_end - v_effective_start)));
    if v_break_window is not null then
      v_break_sec := duc_sum_break_overlap(v_effective_start, v_effective_end, v_break_window);
    else
      v_break_sec := case when v_shift_duration_sec > 0 then (v_break_min * 60 * v_row_span / v_shift_duration_sec) else 0 end;
    end if;
    v_row_ppt := greatest(0, v_row_span - v_break_sec);

    -- T243 (R13): dừng của dòng = hợp khoảng dừng của MÁY (đã đóng + còn mở) ∩ giờ chạy của dòng
    if v_effective_end > v_effective_start then
      select coalesce(sum(extract(epoch from upper(x) - lower(x))), 0) into v_downtime
      from unnest((
        select coalesce(range_agg(r), '{}'::tstzmultirange) from (
          select tstzrange(gio_phat_sinh, gio_tro_lai) r from duc_su_co_log
           where ma_may = v_row.ma_may and ngay = p_ngay and ca = p_ca and gio_tro_lai > gio_phat_sinh
          union all
          select tstzrange(greatest(c.open_gio_phat_sinh, v_ws), v_we) from duc_ca_hien_tai c
           where c.ma_may = v_row.ma_may and c.ngay = p_ngay and c.ca = p_ca and c.open_gio_phat_sinh is not null
             and greatest(c.open_gio_phat_sinh, v_ws) < v_we and not duc_ca_khong_sx(p_ngay, c.ma_may)
          union all
          select tstzrange(greatest(t.gio_phat_sinh, v_ws), v_we) from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong
           where c.ma_may = v_row.ma_may and c.ngay = p_ngay and c.ca = p_ca and greatest(t.gio_phat_sinh, v_ws) < v_we
             and not duc_ca_khong_sx(p_ngay, c.ma_may)) q
      ) * tstzmultirange(tstzrange(v_effective_start, v_effective_end))) x;
    else
      v_downtime := 0;
    end if;

    select cycle_time_s into v_ct from master_products where ma_sp = v_row.ma_sp;
    v_oee := duc_calculate_oee(v_ct, v_row.tt_ca, v_row_ppt, v_downtime, v_row.so_luong_ng);
    v_oee_rows := v_oee_rows || jsonb_build_array(jsonb_build_object('id_dong', v_row.id_dong, 'ma_may', v_row.ma_may, 'ma_sp', v_row.ma_sp, 'oee', v_oee));
    if v_ct is not null and v_ct > 0 then
      v_sum_ideal := v_sum_ideal + v_ct * coalesce(v_row.tt_ca, 0);
      v_sum_ppt := v_sum_ppt + v_row_ppt;
      v_sum_runtime := v_sum_runtime + greatest(0, v_row_ppt - v_downtime);
    end if;
  end loop;

  select count(*), count(*) filter (where dat) into v_so_may_co_kh, v_so_may_hoan_thanh
  from (select ma_may, bool_and(coalesce(tt_ca, 0) >= coalesce(kh_ca, 0)) as dat from duc_ca_hien_tai
        where ngay = p_ngay and ca = p_ca and ma_sp is not null and ma_sp <> '' and kh_ca is not null
          and not duc_la_may_dap(ma_may) group by ma_may) m;

  v_avail_ca := case when v_sum_ppt > 0 then v_sum_runtime / v_sum_ppt else 0 end;
  v_perf_ca := case when v_sum_runtime > 0 then least(1, v_sum_ideal / v_sum_runtime) else 0 end;
  v_quality_ca := case when (v_sum_ok + v_sum_ng) > 0 then v_sum_ok / (v_sum_ok + v_sum_ng) else 1.0 end;
  v_oee_ca := v_avail_ca * v_perf_ca * v_quality_ca;
  v_id_bao_cao := to_char(p_ngay, 'DDMMYYYY') || '_' || duc_shift_short_id(p_ca);
  v_tem_mo_coi := duc_tem_mo_coi_ca(p_ngay, p_ca, p_phuong_an_ca);   -- R15

  insert into duc_bao_cao_ca (
    id_bao_cao, ngay, ca, phuong_an_ca, tuan_sx, truong_ca, so_may_co_kh, so_may_hoan_thanh_kh,
    tong_kh_ca, tong_tt_ca, ty_le_hoan_thanh_ca, so_su_co_ca, tong_phut_dung_ca, url_gdoc_bao_cao,
    thoi_diem_ket_ca, ghi_chu, oee_ca, availability_ca, performance_ca, quality_ca, tong_ng_ca,
    tong_shot_nong_khuon_ca, comment_truong_ca, nv_ca_bao_cao, tong_kh_dap, tong_tt_dap, tong_ng_dap
  ) values (
    v_id_bao_cao, p_ngay, p_ca, p_phuong_an_ca, duc_iso_week(p_ngay), coalesce(p_truong_ca, p_user),
    v_so_may_co_kh, v_so_may_hoan_thanh, v_tong_kh, v_tong_tt, case when v_tong_kh > 0 then v_tong_tt / v_tong_kh else 0 end,
    v_so_su_co_ca, v_tong_phut_resolved + v_tong_phut_open, null, v_now,
    trim(both ' ' from (case when v_so_su_co_dang_do > 0 then v_so_su_co_dang_do || ' sự cố dang dở → ca sau' else '' end)
      || case when jsonb_array_length(v_tem_mo_coi) > 0 then ' ' || jsonb_array_length(v_tem_mo_coi) || ' tem in khác mã KH của máy (không cộng sản lượng ca)' else '' end),
    v_oee_ca, v_avail_ca, v_perf_ca, v_quality_ca, v_sum_ng, v_tong_shot_nong, coalesce(p_comment_truong_ca, ''), array_to_string(v_personnel, ', '),
    v_kh_dap, v_tt_dap, v_ng_dap
  )
  on conflict (id_bao_cao) do update set
    truong_ca = excluded.truong_ca, so_may_co_kh = excluded.so_may_co_kh, so_may_hoan_thanh_kh = excluded.so_may_hoan_thanh_kh,
    tong_kh_ca = excluded.tong_kh_ca, tong_tt_ca = excluded.tong_tt_ca, ty_le_hoan_thanh_ca = excluded.ty_le_hoan_thanh_ca,
    so_su_co_ca = excluded.so_su_co_ca, tong_phut_dung_ca = excluded.tong_phut_dung_ca,
    thoi_diem_ket_ca = excluded.thoi_diem_ket_ca, ghi_chu = excluded.ghi_chu, oee_ca = excluded.oee_ca,
    availability_ca = excluded.availability_ca, performance_ca = excluded.performance_ca, quality_ca = excluded.quality_ca,
    tong_ng_ca = excluded.tong_ng_ca, tong_shot_nong_khuon_ca = excluded.tong_shot_nong_khuon_ca,
    comment_truong_ca = excluded.comment_truong_ca, nv_ca_bao_cao = excluded.nv_ca_bao_cao,
    tong_kh_dap = excluded.tong_kh_dap, tong_tt_dap = excluded.tong_tt_dap, tong_ng_dap = excluded.tong_ng_dap;

  insert into duc_lich_su_san_xuat (ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, kh_ca, tt_ca, so_luong_ng, thoi_diem_ghi)
  select p_ngay, p_ca, p_phuong_an_ca, duc_iso_week(p_ngay), ma_may, ma_sp, ten_sp, coalesce(kh_ca, 0), coalesce(tt_ca, 0), coalesce(so_luong_ng, 0), v_now
  from (select distinct on (ma_may, ma_sp) * from duc_ca_hien_tai
        where ngay = p_ngay and ca = p_ca and ma_sp is not null and ma_sp <> '' and kh_ca is not null order by ma_may, ma_sp, row_seq desc) dedup
  on conflict (ngay, ca, ma_may, ma_sp) do update set
    kh_ca = excluded.kh_ca, tt_ca = excluded.tt_ca, so_luong_ng = excluded.so_luong_ng, thoi_diem_ghi = excluded.thoi_diem_ghi;
  get diagnostics v_history_count = row_count;

  begin
    v_mold_result := duc_update_mold_shots_from_shift(p_ngay, p_ca);
  exception when others then
    v_mold_result := jsonb_build_object('updated', 0, 'warnings', jsonb_build_array('Lỗi cập nhật khuôn: ' || sqlerrm));
  end;

  v_carry_result := duc_carry_over_shift(p_ngay, p_ca, p_phuong_an_ca, p_carry_over_list);
  delete from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca;

  return jsonb_build_object(
    'ok', true, 'id_bao_cao', v_id_bao_cao,
    'summary', jsonb_build_object(
      'so_may_co_kh', v_so_may_co_kh, 'so_may_hoan_thanh_kh', v_so_may_hoan_thanh, 'tong_kh_ca', v_tong_kh, 'tong_tt_ca', v_tong_tt,
      'so_su_co_ca', v_so_su_co_ca, 'so_su_co_dang_do', v_so_su_co_dang_do, 'tong_phut_dung_ca', v_tong_phut_resolved + v_tong_phut_open,
      'oee_ca', v_oee_ca, 'availability_ca', v_avail_ca, 'performance_ca', v_perf_ca, 'quality_ca', v_quality_ca,
      'tong_ng_ca', v_sum_ng, 'tong_shot_nong_khuon_ca', v_tong_shot_nong, 'nv_ca_bao_cao', array_to_string(v_personnel, ', '),
      'tong_kh_dap', v_kh_dap, 'tong_tt_dap', v_tt_dap, 'tong_ng_dap', v_ng_dap),
    'oee_rows', v_oee_rows, 'mold_update', v_mold_result, 'carry_over', v_carry_result, 'history_rows', v_history_count,
    'tem_mo_coi', v_tem_mo_coi);
end;
$function$;
