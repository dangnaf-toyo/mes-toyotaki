-- ============================================================================
-- D28 — Cho ân hạn 30 phút TRƯỚC sp_start_time (giới hạn dưới của tt_ca).
--
-- Phát hiện thực tế: Kẽm 190T / BPH-SHO-01 — tem in lúc 06:51, nhưng dòng
-- sản xuất ghi nhận "bắt đầu chạy" (sp_start_time) lúc 07:00 — sau tem 9
-- phút. Ca này CHƯA hề được kết ca, nhưng tem vẫn bị loại vì D22-D27 chặn
-- cứng "chỉ tính tem in TỪ LÚC sp_start_time trở đi".
--
-- Cùng nguyên tắc với giới hạn trên đã sửa ở D27 (ân hạn 2 ngày sau
-- sp_end_time): cho ân hạn 30 phút TRƯỚC sp_start_time — tem in sớm hơn tối
-- đa 30 phút so với mốc bắt đầu ghi nhận vẫn được tính vào ca đó. 30 phút đủ
-- nhỏ để không gộp nhầm sang lượt chạy TRƯỚC (đổi khuôn giữa 2 mã SP khác
-- nhau thường mất hơn 2 tiếng theo dữ liệu thực tế — xem báo cáo tuần), đủ
-- rộng để không loại oan các tem in ngay trước khi thao tác viên bấm "bắt
-- đầu SP" trên dashboard.
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

  -- Giới hạn dưới: ân hạn 30 phút TRƯỚC sp_start_time.
  v_lower := coalesce(v_row.sp_start_time, '1970-01-01'::timestamptz) - interval '30 minutes';

  -- Giới hạn trên: sp_end_time chỉ được tin nếu đã quá hạn hơn 2 ngày (bị bỏ
  -- quên thật) — nếu chưa thì coi như đang mở, không giới hạn.
  if v_row.sp_end_time is null or now() - v_row.sp_end_time < interval '2 days' then
    v_upper := now();
  else
    v_upper := v_row.sp_end_time;
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
