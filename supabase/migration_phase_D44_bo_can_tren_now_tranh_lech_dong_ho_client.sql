-- ============================================================================
-- D44 — Bỏ cận trên "now()" (giờ SERVER) khi ca CHƯA thực sự quá hạn 2 ngày,
-- vì nó có thể loại oan chính tem VỪA kích hoạt trigger, nếu đồng hồ máy in
-- tem (client) nhanh hơn đồng hồ Supabase (server) dù chỉ vài trăm mili-giây.
--
-- Bằng chứng thực tế (DC 6, 27/08/2026, EXE-PLT-01, Ca đêm):
--   - Tem TKD20260827-0051, so_luong_tt=672, ngay_gio_in (client)
--     = 2026-08-27T14:11:21.347+00:00 — tem DUY NHẤT trong khung ca
--     [11:00, 23:00] UTC (18:00-06:00 VN) của dòng 27082026_Cadem_DC6_EXE-PLT-01.
--   - Ngay sau khi tem này insert, trigger trg_duc_tem_sync_actuals chạy
--     duc_recompute_tt_ca trong CÙNG transaction, ghi
--     last_updated_at = now() = 2026-08-27T14:11:20.663822+00:00 — SỚM HƠN
--     ngay_gio_in của chính tem đó 0.684 giây.
--   - now() trong PL/pgSQL là "transaction timestamp" — cùng 1 giá trị cho
--     mọi lời gọi now() trong cùng transaction. Vậy v_upper (:= now() ở dòng
--     tính cận trên) CHÍNH LÀ giá trị 14:11:20.663822 đó — nhỏ hơn
--     NEW.ngay_gio_in (14:11:21.347). Điều kiện "ngay_gio_in <= v_upper"
--     trong SELECT SUM loại bỏ đúng tem vừa kích hoạt trigger ra khỏi tổng,
--     kết quả tt_ca = 0 dù tem đã in.
--   - Hướng lệch này (client NHANH hơn server) ngược với hướng độ trễ mạng
--     (network latency luôn khiến client timestamp SỚM HƠN thời điểm server
--     nhận request, không phải muộn hơn) — chỉ giải thích được bằng đồng hồ
--     thiết bị in tem chạy nhanh hơn đồng hồ server, xác nhận đúng giả
--     thuyết lệch đồng hồ client, không phải trùng hợp ngẫu nhiên.
--   - Nguyên nhân gốc: ngay_gio_in không có DEFAULT ở schema (duc_tem.ngay_gio_in
--     timestamptz, không default), do CLIENT tự sinh bên intem.html
--     (var now = new Date(); ... p_ngay_gio_in: now.toISOString()) và RPC
--     duc_ghi_tem() (migration_phase4_step2_intem.sql) ghi thẳng giá trị này,
--     không có bước server tự sinh/ghi đè lại.
--
-- Sửa: cận trên "now()" trong nhánh ca CHƯA quá hạn 2 ngày về bản chất không
-- lọc được gì có ý nghĩa (ca đang chạy, mọi tem hợp lệ đều nằm trước "bây
-- giờ" trừ khi lệch đồng hồ) — bỏ hẳn cận trên trong nhánh này (NULL = không
-- giới hạn). Chỉ giữ cận trên CỐ ĐỊNH (v_scheduled_end, không phụ thuộc
-- now()) khi ca đã quá hạn kết thúc theo lịch hơn 2 ngày thật sự — nhánh đó
-- không có rủi ro lệch đồng hồ vì mốc so sánh không còn là "now()".
--
-- Giữ nguyên toàn bộ phần khác của hàm (bản D43 có FOR UPDATE chống race
-- condition 2 tem gần như đồng thời — vẫn giữ nguyên, không đụng tới).
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

  -- Khoá đúng dòng đang tính TRƯỚC khi đọc tổng tem — chặn race condition
  -- khi 2 tem cùng (máy,SP) in gần như đồng thời (D43).
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

  -- Cận trên (D44): CHỈ áp cận trên khi ca đã quá giờ kết thúc THEO LỊCH hơn
  -- 2 ngày thật sự (chưa được kết ca thật dù đã trễ rất lâu — dữ liệu bất
  -- thường, cần chặn để không cộng dồn tem của các ca sau đó nhỡ trùng
  -- máy/mã SP). Khi ca CHƯA quá hạn 2 ngày (trường hợp bình thường, kể cả
  -- đang chạy hay vừa hết giờ theo lịch nhưng chưa kết ca) — KHÔNG dùng
  -- now() (giờ SERVER) làm cận trên nữa: NULL = không giới hạn, vì cận trên
  -- "now()" trong nhánh này không lọc được gì có ý nghĩa (chỉ để có giá trị
  -- non-null cho WHERE clause) nhưng lại có thể loại oan tem vừa in nếu
  -- đồng hồ thiết bị in tem (client, tự sinh ngay_gio_in) nhanh hơn đồng hồ
  -- server dù chỉ vài trăm mili-giây — đúng lỗi thực tế gây tt_ca=0 cho DC6
  -- ngày 27/08/2026 (xem phần ghi chú đầu file).
  if v_scheduled_end is not null and now() - v_scheduled_end >= interval '2 days' then
    v_upper := v_scheduled_end;
  else
    v_upper := null;
  end if;

  select coalesce(sum(so_luong_tt), 0) into v_tt_ca
  from duc_tem
  where may_tt = p_ma_may and ma_sp = p_ma_sp
    and ngay_gio_in >= v_lower
    and (v_upper is null or ngay_gio_in <= v_upper);

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

-- ── Sửa ngay dòng DC 6 đang bị thiếu (đã xác nhận qua thực tế 27/08/2026) ──
select duc_recompute_tt_ca('DC 6', 'EXE-PLT-01');

-- ── Backfill an toàn cho MỌI cặp (máy, mã SP) đang có, phòng còn máy khác
-- bị lệch đồng hồ tương tự mà chưa ai để ý (im lặng cho tới khi có tem tiếp
-- theo bù lại, nên rất dễ bị bỏ sót).
do $$
declare
  r record;
begin
  for r in select distinct ma_may, ma_sp from duc_ca_hien_tai where ma_may is not null and ma_sp is not null
  loop
    perform duc_recompute_tt_ca(r.ma_may, r.ma_sp);
  end loop;
end $$;
