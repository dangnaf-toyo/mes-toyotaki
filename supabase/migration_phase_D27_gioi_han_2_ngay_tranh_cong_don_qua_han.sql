-- ============================================================================
-- D27 — Sửa lỗi D26: bỏ hẳn giới hạn trên (sp_end_time) khiến các cặp
-- (máy, mã SP) đã NGỪNG CHẠY THỰC SỰ từ lâu (nhiều ngày/tuần, chưa từng có
-- dòng mới nào thay thế) bị cộng dồn tem của NHIỀU TUẦN vào 1 con số.
--
-- Ví dụ thực tế: DC 6 / EXE-PLT-01 (dòng từ 01/08, hơn 3 tuần trước) ra
-- tt_ca = 12.326 — cộng dồn toàn bộ tem từ 01/08 tới nay, dù SP này không
-- còn chạy trên máy DC 6 từ lâu.
--
-- Nhưng nếu quay lại dùng thẳng sp_end_time làm giới hạn cứng (như D22 ban
-- đầu) thì lại tái phát lỗi D23 đã sửa: DC 8/DC 11/DC 6-EXE-OUT-01 chỉ mới
-- "quá hạn" sp_end_time 1-2 ngày vì CHƯA ĐƯỢC KẾT CA (không phải đã ngừng
-- chạy thật) sẽ bị loại oan.
--
-- Không có cách nào phân biệt 100% chính xác "chưa kết ca" và "bỏ quên
-- thật" chỉ từ dữ liệu hiện có (kể cả kiểm tra duc_bao_cao_ca cũng không
-- giúp — nhiều dòng cũ CŨNG chưa từng được kết ca). Giải pháp thực dụng:
-- cho 1 KHOẢNG ÂN HẠN 2 ngày sau sp_end_time — quá hạn dưới 2 ngày vẫn coi
-- là đang mở (không giới hạn trên, đúng tinh thần "kết ca quyết định");
-- quá hạn hơn 2 ngày coi là bị bỏ quên thật, chặn cứng ở sp_end_time để
-- không cộng dồn vô hạn. 2 ngày đủ rộng cho 1 ca bị trễ kết ca vài hôm,
-- nhưng đủ chặt để loại các dòng thật sự đã ngừng chạy nhiều tuần.
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
  v_upper timestamptz;
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

  -- Giới hạn trên cho tt_ca: sp_end_time chỉ được tin nếu đã quá hạn hơn 2
  -- ngày (bị bỏ quên thật) — nếu chưa (mới quá hạn do chưa kết ca, hoặc còn
  -- trong tương lai/null) thì coi như đang mở, không giới hạn.
  if v_row.sp_end_time is null or now() - v_row.sp_end_time < interval '2 days' then
    v_upper := now();
  else
    v_upper := v_row.sp_end_time;
  end if;

  select coalesce(sum(so_luong_tt), 0) into v_tt_ca
  from duc_tem
  where may_tt = p_ma_may and ma_sp = p_ma_sp
    and ngay_gio_in >= coalesce(v_row.sp_start_time, '1970-01-01'::timestamptz)
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
