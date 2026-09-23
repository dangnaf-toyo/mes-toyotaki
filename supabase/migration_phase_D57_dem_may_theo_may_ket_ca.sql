-- D57: Báo cáo kết ca Đúc — "Máy có KH" / "Máy đạt KH" đếm theo MÁY, không
-- theo mã SP.
--
-- Trước đây duc_end_shift() cộng +1 cho mỗi DÒNG (máy, mã SP) có kế hoạch,
-- nên 1 máy chạy 2 mã trong ca bị đếm thành 2 máy (VD ca ngày 23/09: báo
-- 13 máy có KH trong khi thực tế chỉ 8 máy).
--
-- Quy tắc mới:
--   - so_may_co_kh        = số máy KHÁC NHAU có ít nhất 1 mã có kế hoạch.
--   - so_may_hoan_thanh_kh = số máy mà TẤT CẢ các mã của máy đó đều đạt KH
--                            (tt_ca >= kh_ca).
-- Các chỉ số khác (tổng KH/TT, OEE, NG...) giữ nguyên, vẫn cộng theo dòng.
--
-- Hàm duc_end_shift giữ nguyên y hệt bản D40, chỉ đổi phần đếm máy.
-- Cuối file: tính lại 2 cột này cho các báo cáo ca CŨ từ duc_lich_su_san_xuat.
--
-- Chạy trên CẢ 2 project (production + staging).

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

  -- D57: đếm theo MÁY — máy chạy nhiều mã chỉ tính 1, và chỉ "đạt KH" khi
  -- tất cả các mã của máy đó đều đạt (tt_ca >= kh_ca).
  select count(*), count(*) filter (where dat)
    into v_so_may_co_kh, v_so_may_hoan_thanh
  from (
    select ma_may, bool_and(coalesce(tt_ca, 0) >= coalesce(kh_ca, 0)) as dat
    from duc_ca_hien_tai
    where ngay = p_ngay and ca = p_ca and ma_sp is not null and ma_sp <> '' and kh_ca is not null
    group by ma_may
  ) m;

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

  -- Lưu lịch sử sản xuất (appendProductionHistory_, BaoCaoTuan.js) — nguồn cho báo cáo tuần.
  -- distinct on (ma_may, ma_sp) + order by row_seq desc: nếu lỡ có >1 dòng
  -- duc_ca_hien_tai trùng (ngay,ca,ma_may,ma_sp) (bug, không nên xảy ra —
  -- xem chú thích D40 ở duc_doi_phuong_an_ca), chỉ lấy dòng row_seq mới nhất
  -- thay vì để cả 2 vào cùng 1 insert...on conflict làm sập kết ca.
  insert into duc_lich_su_san_xuat (ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, kh_ca, tt_ca, so_luong_ng, thoi_diem_ghi)
  select p_ngay, p_ca, p_phuong_an_ca, duc_iso_week(p_ngay), ma_may, ma_sp, ten_sp, coalesce(kh_ca, 0), coalesce(tt_ca, 0), coalesce(so_luong_ng, 0), v_now
  from (
    select distinct on (ma_may, ma_sp) *
    from duc_ca_hien_tai
    where ngay = p_ngay and ca = p_ca and ma_sp is not null and ma_sp <> '' and kh_ca is not null
    order by ma_may, ma_sp, row_seq desc
  ) dedup
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

-- ── Tính lại cho các báo cáo ca đã lưu ─────────────────────────────────────
-- duc_lich_su_san_xuat lưu đúng các dòng (máy, mã SP) có kế hoạch của mỗi ca
-- lúc kết ca, nên dùng làm nguồn đếm lại. Ca nào không có lịch sử thì giữ nguyên.
update duc_bao_cao_ca b set
  so_may_co_kh = x.so_may,
  so_may_hoan_thanh_kh = x.so_may_dat
from (
  select ngay, ca, count(*) as so_may, count(*) filter (where dat) as so_may_dat
  from (
    select ngay, ca, ma_may, bool_and(coalesce(tt_ca, 0) >= coalesce(kh_ca, 0)) as dat
    from duc_lich_su_san_xuat
    group by ngay, ca, ma_may
  ) m
  group by ngay, ca
) x
where b.ngay = x.ngay and b.ca = x.ca;
