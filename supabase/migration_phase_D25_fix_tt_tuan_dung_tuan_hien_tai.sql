-- ============================================================================
-- D25 — Sửa lỗi D24: tt_tuan tính nhầm sang TUẦN TRƯỚC ở các máy có dòng
-- duc_ca_hien_tai chưa được kết ca cập nhật sang hôm nay.
--
-- Phát hiện thực tế (2026-08-24, Thứ Hai): DC 8 hiện tt_tuan = 12.072 dù hôm
-- nay là ngày đầu tuần và tt_ca (sản lượng thực tế TỚI GIỜ) chỉ 2.000. Do
-- D24 lấy tuần dựa theo cột `ngay` của dòng duc_ca_hien_tai — cột này bị cũ
-- (còn ghi ngày tuần trước, do dòng chưa được kết ca/carry-over sang hôm
-- nay) — nên hàm tính nhầm sang tuần 17–22/08, cộng luôn cả tuần cũ vào.
--
-- Sửa: xác định "tuần hiện tại" theo GIỜ HỆ THỐNG THỰC TẾ (now(), giờ VN),
-- không phụ thuộc cột `ngay` của dòng (có thể bị cũ) — luôn ra đúng tuần
-- đang chạy trên lịch thật, giống cách bao-cao-tuan.html xác định tuần.
-- An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create or replace function duc_recompute_tt_ca(p_ma_may text)
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
begin
  if p_ma_may is null then
    return;
  end if;

  select * into v_row
  from duc_ca_hien_tai
  where ma_may = p_ma_may
  order by row_seq desc
  limit 1;

  if v_row.id_dong is null or v_row.ma_sp is null then
    return;
  end if;

  -- tt_ca: cộng dồn từ khi dòng này bắt đầu chạy (sp_start_time), không giới
  -- hạn trên — dòng còn là row_seq mới nhất của máy thì vẫn coi là đang mở.
  select coalesce(sum(so_luong_tt), 0) into v_tt_ca
  from duc_tem
  where may_tt = p_ma_may and ma_sp = v_row.ma_sp
    and ngay_gio_in >= coalesce(v_row.sp_start_time, '1970-01-01'::timestamptz);

  -- tt_tuan: tuần XÁC ĐỊNH THEO NGÀY HỆ THỐNG HIỆN TẠI (không dùng v_row.ngay
  -- vì cột đó có thể cũ chưa kết ca) — Thứ Hai 00:00 -> Thứ Hai tuần sau
  -- 00:00, giờ Việt Nam.
  v_today_vn := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  v_monday := v_today_vn - (((extract(dow from v_today_vn)::int + 6) % 7));
  v_week_start := (v_monday::timestamp) at time zone 'Asia/Ho_Chi_Minh';
  v_week_end := ((v_monday + 7)::timestamp) at time zone 'Asia/Ho_Chi_Minh';

  select coalesce(sum(so_luong_tt), 0) into v_tt_tuan
  from duc_tem
  where may_tt = p_ma_may and ma_sp = v_row.ma_sp
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

-- ── Backfill lại tt_tuan cho mọi máy theo tuần hiện tại đúng ────────────────
do $$
declare
  r record;
begin
  for r in select distinct ma_may from duc_ca_hien_tai where ma_may is not null
  loop
    perform duc_recompute_tt_ca(r.ma_may);
  end loop;
end $$;
