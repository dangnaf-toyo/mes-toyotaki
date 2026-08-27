-- ============================================================================
-- D40 — Sửa duc_doi_phuong_an_ca (D39) tạo dòng trùng khoá, dọn dữ liệu đã
-- kẹt do lỗi này (DC 6 / EXE-OUT-01 / 26/08 / Ca ngày).
--
-- Lỗi: duc_doi_phuong_an_ca chỉ UPDATE cột ngay/ca của dòng đang chạy, KHÔNG
-- cập nhật lại id_dong (khoá chính, tính từ ngày+ca+máy+SP qua
-- duc_make_id_dong — mọi hàm khác đổi ngày/ca/SP đều tính lại id_dong mới,
-- riêng hàm D39 thì quên). Hệ quả: dòng cũ giữ id_dong cũ (VD "..._Ca2_...")
-- dù cột ca thật đã đổi sang "Ca ngày". Khi có sự kiện khác tính lại id_dong
-- đúng chuẩn theo (ngày,ca,máy,SP) hiện tại (VD trigger tự cập nhật sản
-- lượng theo tem in), không thấy dòng khớp id_dong nên TẠO DÒNG MỚI thay vì
-- cập nhật dòng cũ — 1 máy chạy 2 dòng song song cho cùng (ngày,ca,máy,SP).
-- Khi kết ca, insert vào duc_lich_su_san_xuat (unique ngày,ca,máy,SP) gặp cả
-- 2 dòng cùng khoá trong 1 câu lệnh → Postgres báo "ON CONFLICT DO UPDATE
-- command cannot affect row a second time".
--
-- Sửa hàm: tính lại id_dong mới, chặn (báo lỗi rõ ràng thay vì âm thầm tạo
-- trùng) nếu đã có sẵn 1 dòng khác cho đúng (ngày,ca,máy,SP) mới — giống
-- cách duc_change_product (D12) đã làm.
-- ============================================================================

create or replace function duc_doi_phuong_an_ca(p_ma_may text, p_phuong_an_ca_moi text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row duc_ca_hien_tai%rowtype;
  v_now_vn timestamp;
  v_today_vn date;
  v_t_phut int;
  v_ca_moi text;
  v_ngay_moi date;
  v_start_vn timestamp;
  v_end_vn timestamp;
  v_tt_ca_cu numeric;
  v_tt_ca_moi numeric;
  v_new_id_dong text;
begin
  if p_phuong_an_ca_moi not in ('2 ca 8h', '2 ca 12h') then
    return jsonb_build_object('ok', false, 'error', 'Phương án không hợp lệ — chỉ nhận "2 ca 8h" hoặc "2 ca 12h"');
  end if;

  select * into v_row from duc_ca_hien_tai where ma_may = trim(coalesce(p_ma_may, '')) order by row_seq desc limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng đang hoạt động của máy: ' || p_ma_may);
  end if;
  if v_row.ma_sp is null then
    return jsonb_build_object('ok', false, 'error', 'Máy chưa có mã SP đang chạy, không xác định được để tính lại tt_ca');
  end if;
  if v_row.phuong_an_ca = p_phuong_an_ca_moi then
    return jsonb_build_object('ok', false, 'error', 'Máy đã đang dùng đúng phương án này rồi');
  end if;

  v_tt_ca_cu := v_row.tt_ca;
  v_now_vn := now() at time zone 'Asia/Ho_Chi_Minh';
  v_today_vn := v_now_vn::date;
  v_t_phut := extract(hour from v_now_vn)::int * 60 + extract(minute from v_now_vn)::int;

  if p_phuong_an_ca_moi = '2 ca 12h' then
    if v_t_phut >= 6*60 and v_t_phut < 18*60 then
      v_ca_moi := 'Ca ngày'; v_ngay_moi := v_today_vn;
      v_start_vn := v_today_vn + time '06:00'; v_end_vn := v_today_vn + time '18:00';
    elsif v_t_phut >= 18*60 then
      v_ca_moi := 'Ca đêm'; v_ngay_moi := v_today_vn;
      v_start_vn := v_today_vn + time '18:00'; v_end_vn := (v_today_vn + 1) + time '06:00';
    else
      v_ca_moi := 'Ca đêm'; v_ngay_moi := v_today_vn - 1;
      v_start_vn := (v_today_vn - 1) + time '18:00'; v_end_vn := v_today_vn + time '06:00';
    end if;
  else -- '2 ca 8h'
    if v_t_phut >= 6*60 and v_t_phut < 14*60 then
      v_ca_moi := 'Ca 1'; v_ngay_moi := v_today_vn;
      v_start_vn := v_today_vn + time '06:00'; v_end_vn := v_today_vn + time '14:00';
    elsif v_t_phut >= 14*60 and v_t_phut < 22*60 then
      v_ca_moi := 'Ca 2'; v_ngay_moi := v_today_vn;
      v_start_vn := v_today_vn + time '14:00'; v_end_vn := v_today_vn + time '22:00';
    else
      return jsonb_build_object('ok', false, 'error',
        'Giờ hiện tại (22h-6h) không thuộc ca nào của phương án "2 ca 8h" — máy nên chờ tới 6h sáng, hoặc dùng "2 ca 12h" (có Ca đêm 18h-6h)');
    end if;
  end if;

  v_new_id_dong := duc_make_id_dong(v_ngay_moi, v_ca_moi, v_row.ma_may, v_row.ma_sp);
  if v_new_id_dong <> v_row.id_dong and exists (select 1 from duc_ca_hien_tai where id_dong = v_new_id_dong) then
    return jsonb_build_object('ok', false, 'error',
      'Đã có sẵn 1 dòng khác cho máy ' || v_row.ma_may || ' / SP ' || v_row.ma_sp || ' đúng (ngày,ca) mới (' || v_ngay_moi || ', ' || v_ca_moi || ') — không thể đổi tự động, cần gộp thủ công để tránh trùng khoá khi kết ca.');
  end if;

  update duc_ca_hien_tai set
    id_dong = v_new_id_dong,
    phuong_an_ca = p_phuong_an_ca_moi,
    ca = v_ca_moi,
    ngay = v_ngay_moi,
    sp_start_time = v_start_vn at time zone 'Asia/Ho_Chi_Minh',
    sp_end_time = v_end_vn at time zone 'Asia/Ho_Chi_Minh',
    version = coalesce(version, 0) + 1,
    last_updated_by = coalesce(nullif(trim(p_user), ''), 'system'),
    last_updated_at = now()
  where id_dong = v_row.id_dong;

  perform duc_recompute_tt_ca(v_row.ma_may, v_row.ma_sp);
  select tt_ca into v_tt_ca_moi from duc_ca_hien_tai where id_dong = v_new_id_dong;

  return jsonb_build_object(
    'ok', true, 'ma_may', v_row.ma_may,
    'phuong_an_ca_cu', v_row.phuong_an_ca, 'ca_cu', v_row.ca, 'ngay_cu', v_row.ngay,
    'phuong_an_ca_moi', p_phuong_an_ca_moi, 'ca_moi', v_ca_moi, 'ngay_moi', v_ngay_moi,
    'tt_ca_cu', v_tt_ca_cu, 'tt_ca_moi', v_tt_ca_moi
  );
end;
$$;

-- ── duc_end_shift: chống trùng khoá khi insert lịch sử sản xuất ───────────
-- Phòng vệ thêm (ngoài việc sửa gốc ở duc_doi_phuong_an_ca trên) — nếu vì lý
-- do khác lại phát sinh 2 dòng duc_ca_hien_tai cùng (ngày,ca,máy,SP), chỉ lấy
-- dòng row_seq lớn nhất (mới nhất) mỗi (máy,SP) thay vì để cả 2 lọt vào cùng
-- 1 câu insert...on conflict và làm sập toàn bộ kết ca. Toàn bộ phần còn lại
-- của hàm giữ nguyên y hệt migration_phase4_step7_end_shift.sql.
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

-- ── Dọn dữ liệu đã kẹt: DC 6 / EXE-OUT-01 / 26/08 / Ca ngày đang có 2 dòng
-- trùng (26082026_Cangay_DC6_EXE-OUT-01 tt_ca=2959 tự động theo tem in,
-- 26082026_Ca2_DC6_EXE-OUT-01 tt_ca=1352 sửa tay) — user xác nhận giữ số
-- 2959 (tự động theo tem, đáng tin hơn vì không phụ thuộc nhập tay).
delete from duc_ca_hien_tai
where id_dong = '26082026_Ca2_DC6_EXE-OUT-01'
  and exists (select 1 from duc_ca_hien_tai where id_dong = '26082026_Cangay_DC6_EXE-OUT-01');
