-- ============================================================================
-- D26 — Sửa lỗi D23: 1 máy có thể có NHIỀU dòng đang mở song song (chưa kết
-- ca) cho các mã SP KHÁC NHAU cùng lúc — D23 chỉ lấy đúng 1 dòng row_seq lớn
-- nhất của cả máy nên các dòng SP khác (vẫn đang có tem in thật) bị bỏ quên,
-- không được tính lại tt_ca/tt_tuan nữa (đứng ở số cũ).
--
-- Ví dụ thực tế: DC 6 có cả dòng EXE-CEN-01 (row_seq 187, mới hơn) VÀ dòng
-- EXE-OUT-01 (row_seq 180, cũ hơn nhưng CHƯA kết ca, vẫn đang in tem thật
-- trong hôm nay) mở song song. D23 chỉ tính lại cho EXE-CEN-01, bỏ quên
-- EXE-OUT-01.
--
-- Sửa: quay lại khớp theo ĐÚNG CẶP (máy, mã SP) như D22 ban đầu — nhưng vẫn
-- giữ phần sửa đúng của D23/D25 (không chặn sp_end_time, tuần tính theo giờ
-- hệ thống hiện tại). Trigger giờ nhận cả may_tt lẫn ma_sp từ tem, tìm đúng
-- dòng row_seq lớn nhất của ĐÚNG cặp đó — không còn nhầm giữa các SP khác
-- nhau chạy song song trên cùng 1 máy.
-- An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

drop function if exists duc_recompute_tt_ca(text);

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
begin
  if p_ma_may is null or p_ma_sp is null then
    return;
  end if;

  -- Dòng đang chạy của ĐÚNG cặp (máy, mã SP) = row_seq lớn nhất khớp cả 2,
  -- không lọc theo sp_end_time (dòng chưa kết ca vẫn coi là đang mở dù
  -- sp_end_time đã ở quá khứ).
  select * into v_row
  from duc_ca_hien_tai
  where ma_may = p_ma_may and ma_sp = p_ma_sp
  order by row_seq desc
  limit 1;

  if v_row.id_dong is null then
    return;
  end if;

  select coalesce(sum(so_luong_tt), 0) into v_tt_ca
  from duc_tem
  where may_tt = p_ma_may and ma_sp = p_ma_sp
    and ngay_gio_in >= coalesce(v_row.sp_start_time, '1970-01-01'::timestamptz);

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

create or replace function duc_tem_sync_actuals_trigger()
returns trigger
language plpgsql
security definer
as $$
begin
  if TG_OP in ('INSERT', 'UPDATE') then
    perform duc_recompute_tt_ca(NEW.may_tt, NEW.ma_sp);
  end if;
  if TG_OP in ('UPDATE', 'DELETE') then
    if TG_OP = 'DELETE' or OLD.may_tt is distinct from NEW.may_tt or OLD.ma_sp is distinct from NEW.ma_sp then
      perform duc_recompute_tt_ca(OLD.may_tt, OLD.ma_sp);
    end if;
  end if;
  return coalesce(NEW, OLD);
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
