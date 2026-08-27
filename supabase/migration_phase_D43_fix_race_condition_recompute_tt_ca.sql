-- ============================================================================
-- D43 — Sửa race condition trong duc_recompute_tt_ca: khi 2 tem cùng máy/mã
-- SP được in gần như đồng thời (VD 1 lệnh sản xuất tách nhiều tem pallet, in
-- liên tiếp cách nhau vài giây), 2 giao dịch trigger chạy chồng lên nhau —
-- giao dịch chạy SAU đọc tổng số_luong_tt TRƯỚC KHI giao dịch kia kịp commit,
-- rồi ghi đè tt_ca bằng số thiếu đúng bằng số lượng tem "thua cuộc đua".
--
-- Phát hiện qua báo cáo thực tế 27/08: DC4 tem in ra tổng 830pcs nhưng
-- dashboard hiện 726 (thiếu đúng 104 — tem cuối cùng in lúc 10:52:21, cách
-- tem trước 25 giây); DC5 tem in ra 912 nhưng dashboard hiện 768 (thiếu
-- đúng 144 — tem cuối in lúc 10:48:57).
--
-- Sửa: khoá dòng duc_ca_hien_tai đang tính (select ... for update) TRƯỚC khi
-- đọc tổng tem — buộc 2 giao dịch trigger cùng 1 dòng phải chạy TUẦN TỰ thay
-- vì chồng lên nhau, giao dịch chạy sau luôn thấy đủ dữ liệu giao dịch chạy
-- trước đã commit.
-- ============================================================================

create or replace function duc_recompute_tt_ca(p_ma_may text, p_ma_sp text)
returns void
language plpgsql
security definer
as $$
declare
  v_row duc_ca_hien_tai%rowtype;
  v_tt_ca numeric;
  v_tt_tuan numeric;
  v_today_vn date;
  v_monday date;
  v_week_start timestamptz;
  v_week_end timestamptz;
  v_lower timestamptz;
  v_upper timestamptz;
  v_shift_start time;
  v_shift_end time;
  v_cross boolean;
  v_scheduled_end timestamptz;
begin
  if p_ma_may is null or p_ma_sp is null then
    return;
  end if;

  -- Khoá đúng dòng đang tính TRƯỚC khi đọc tổng tem — chặn race condition
  -- khi 2 tem cùng (máy,SP) in gần như đồng thời (xem chú thích D43 ở trên).
  select * into v_row
  from duc_ca_hien_tai
  where ma_may = p_ma_may and ma_sp = p_ma_sp
  order by row_seq desc
  limit 1
  for update;

  if v_row.id_dong is null then
    return;
  end if;

  -- Xác định khung giờ chuẩn của ca theo phuong_an_ca + ca (khớp CONFIG.SHIFT_PLANS
  -- bên duc-dashboard.html).
  if v_row.phuong_an_ca = '2 ca 12h' and v_row.ca = 'Ca ngày' then
    v_shift_start := time '06:00'; v_shift_end := time '18:00'; v_cross := false;
  elsif v_row.phuong_an_ca = '2 ca 12h' and v_row.ca = 'Ca đêm' then
    v_shift_start := time '18:00'; v_shift_end := time '06:00'; v_cross := true;
  elsif v_row.phuong_an_ca = '2 ca 8h' and v_row.ca = 'Ca 1' then
    v_shift_start := time '06:00'; v_shift_end := time '14:00'; v_cross := false;
  elsif v_row.phuong_an_ca = '2 ca 8h' and v_row.ca = 'Ca 2' then
    v_shift_start := time '14:00'; v_shift_end := time '22:00'; v_cross := false;
  else
    v_shift_start := null;
  end if;

  if v_shift_start is not null and v_row.ngay is not null then
    v_lower := (v_row.ngay::timestamp + v_shift_start) at time zone 'Asia/Ho_Chi_Minh';
    v_scheduled_end := ((v_row.ngay + case when v_cross then 1 else 0 end)::timestamp + v_shift_end) at time zone 'Asia/Ho_Chi_Minh';
  else
    -- Tổ hợp ca lạ (dữ liệu lịch sử) — dự phòng bằng sp_start_time, ân hạn 30 phút.
    v_lower := coalesce(v_row.sp_start_time, '1970-01-01'::timestamptz) - interval '30 minutes';
    v_scheduled_end := v_row.sp_end_time;
  end if;

  -- Cận trên: ân hạn 2 ngày cho ca đã quá giờ kết thúc THEO LỊCH nhưng CHƯA
  -- được kết ca thật (dòng vẫn còn tồn tại = chưa đóng).
  if v_scheduled_end is null or now() - v_scheduled_end < interval '2 days' then
    v_upper := now();
  else
    v_upper := v_scheduled_end;
  end if;

  select coalesce(sum(so_luong_tt), 0) into v_tt_ca
  from duc_tem
  where may_tt = p_ma_may and ma_sp = p_ma_sp
    and ngay_gio_in >= v_lower
    and ngay_gio_in <= v_upper;

  v_today_vn := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  v_monday := v_today_vn - (((extract(dow from v_today_vn)::int + 6) % 7));
  v_week_start := (v_monday::timestamp) at time zone 'Asia/Ho_Chi_Minh';
  v_week_end := ((v_monday + 7)::timestamp) at time zone 'Asia/Ho_Chi_Minh';

  select coalesce(sum(so_luong_tt), 0) into v_tt_tuan
  from duc_tem
  where may_tt = p_ma_may and ma_sp = p_ma_sp
    and ngay_gio_in >= v_week_start and ngay_gio_in < v_week_end;

  update duc_ca_hien_tai
  set tt_ca = v_tt_ca,
      tt_tuan = v_tt_tuan,
      version = coalesce(version, 0) + 1,
      last_updated_by = 'system@tem_trigger',
      last_updated_at = now()
  where id_dong = v_row.id_dong
    and (coalesce(tt_ca, -1) is distinct from v_tt_ca or coalesce(tt_tuan, -1) is distinct from v_tt_tuan);
end;
$$;

-- ── Sửa ngay 2 dòng đang bị thiếu (đã xác nhận qua thực tế) ────────────────
select duc_recompute_tt_ca('DC 4', 'TTI-MOT-02');
select duc_recompute_tt_ca('DC 5', 'AST-PAN-01');

-- ── Backfill an toàn cho MỌI cặp (máy, mã SP) đang có, phòng còn máy khác
-- bị race tương tự mà chưa ai để ý.
do $$
declare
  r record;
begin
  for r in select distinct ma_may, ma_sp from duc_ca_hien_tai where ma_may is not null and ma_sp is not null
  loop
    perform duc_recompute_tt_ca(r.ma_may, r.ma_sp);
  end loop;
end $$;
