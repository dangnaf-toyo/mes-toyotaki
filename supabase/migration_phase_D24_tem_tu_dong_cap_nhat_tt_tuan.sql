-- ============================================================================
-- D24 — Bổ sung tt_tuan (sản lượng thực tế TUẦN) vào cơ chế tự cập nhật từ
-- tem in ra, cùng cơ chế với tt_ca đã làm ở D22/D23.
--
-- D22/D23 mới chỉ tính tt_ca (sản lượng thực tế CA), cố tình để tt_tuan lại
-- vì chưa xác nhận công thức. Nay đã tìm đúng công thức gốc trong Apps Script
-- cũ (Utils.js -> getWeekWindow(ngay)): tuần chạy Thứ Hai 00:00 -> Thứ Hai
-- tuần kế tiếp 00:00 (giờ Việt Nam), dựa theo cột `ngay` của dòng
-- duc_ca_hien_tai — khớp đúng quy ước "tuần Thứ Hai -> Thứ Bảy" đã thống nhất
-- ở skill bao-cao-tuan.
--
-- tt_tuan = tổng so_luong_tt của mọi tem cùng (ma_may, ma_sp) với dòng đang
-- chạy, in ra trong đúng tuần lịch của dòng đó — KHÔNG giới hạn theo
-- sp_start_time như tt_ca (vì tt_tuan là tổng cộng dồn cả tuần, có thể trải
-- qua nhiều ca/nhiều dòng duc_ca_hien_tai khác nhau trong cùng tuần).
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

  -- tt_tuan: cộng dồn cả tuần lịch (Thứ Hai -> Thứ Hai kế tiếp, giờ VN) chứa
  -- ngày `v_row.ngay` — đúng công thức getWeekWindow() gốc bên Apps Script.
  if v_row.ngay is not null then
    v_monday := v_row.ngay - (((extract(dow from v_row.ngay)::int + 6) % 7));
    v_week_start := (v_monday::timestamp) at time zone 'Asia/Ho_Chi_Minh';
    v_week_end := ((v_monday + 7)::timestamp) at time zone 'Asia/Ho_Chi_Minh';

    select coalesce(sum(so_luong_tt), 0) into v_tt_tuan
    from duc_tem
    where may_tt = p_ma_may and ma_sp = v_row.ma_sp
      and ngay_gio_in >= v_week_start and ngay_gio_in < v_week_end;
  else
    v_tt_tuan := v_row.tt_tuan;
  end if;

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

-- ── Backfill lại tt_tuan cho mọi máy ────────────────────────────────────────
do $$
declare
  r record;
begin
  for r in select distinct ma_may from duc_ca_hien_tai where ma_may is not null
  loop
    perform duc_recompute_tt_ca(r.ma_may);
  end loop;
end $$;
