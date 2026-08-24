-- ============================================================================
-- D32 — Sửa lỗi cốt lõi: dùng đúng KHUNG GIỜ CHUẨN CỦA CA (6h-18h / 18h-6h /
-- 6h-14h / 14h-22h theo ngay+ca+phuong_an_ca) làm ranh giới tt_ca, thay vì
-- dựa vào sp_start_time (giờ vận hành ghi lại, có thể lệch vài phút) + ân
-- hạn 30 phút (D28) — đây chính là công thức gốc getShiftWindow() bên Apps
-- Script cũ mà lẽ ra nên dùng ngay từ D22.
--
-- Lỗi thực tế phát hiện: DC 7 sau khi Kết ca sang Ca đêm (18h) vẫn hiện
-- tt_ca = 2.004 — đúng ra phải là 0 (chưa có tem nào cho Ca đêm). Nguyên
-- nhân: 3 tem cuối Ca ngày in lúc 17:41-17:42 (chỉ trước biên ca ~18-19
-- phút) bị ân hạn 30 phút (D28) quét ngược vào Ca đêm mới, dù chúng rõ
-- ràng thuộc Ca ngày (in trước 18h).
--
-- Sửa: bỏ hẳn ân hạn 30 phút ở cận dưới — dùng ĐÚNG giờ bắt đầu ca theo
-- ngay+ca+phuong_an_ca (không lệch, không ân hạn) làm cận dưới. Việc này
-- giải quyết luôn ca Kẽm 190T (tem in 13h51, nằm sâu trong khung 6h-18h,
-- không cần ân hạn vẫn tính đúng) VÀ ca DC7 (tem 17h41-42 nằm trước 18h,
-- bị loại đúng khỏi Ca đêm).
--
-- Vẫn giữ ân hạn 2 ngày ở cận trên (D27) — cho các ca đã quá giờ kết thúc
-- theo lịch nhưng CHƯA được kết ca (khác với "hết ca theo lịch" là "đã kết
-- ca thật"), để không loại oan tem của ca chưa đóng.
--
-- Nếu ca không nằm trong 4 tổ hợp chuẩn (dữ liệu lịch sử lạ, vd "Ca ngày" +
-- "2 ca 8h") → dùng lại sp_start_time/sp_end_time (D27/D28) làm phương án
-- dự phòng, không để hàm lỗi.
-- An toàn chạy lại nhiều lần (idempotent).
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

  select * into v_row
  from duc_ca_hien_tai
  where ma_may = p_ma_may and ma_sp = p_ma_sp
  order by row_seq desc
  limit 1;

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

-- ── Backfill lại cho MỌI cặp (máy, mã SP) đang có trong duc_ca_hien_tai ────
do $$
declare
  r record;
begin
  for r in select distinct ma_may, ma_sp from duc_ca_hien_tai where ma_may is not null and ma_sp is not null
  loop
    perform duc_recompute_tt_ca(r.ma_may, r.ma_sp);
  end loop;
end $$;
