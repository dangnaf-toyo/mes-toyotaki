-- T205: Sản lượng ca KHÔNG cộng trùng tem của ca trước in sau giờ giao ca.
--
-- 03/11/2026 ca đêm: chưa in tem nào nhưng DC 4/5/6/7 đã có TT (620/336/792/216). Đó là tem ca ngày
-- in 18:24–18:39, trước khi kết ca ngày lúc 18:42. Kết ca ngày đã tính các tem này cho ca ngày
-- (đúng quy ước D58: tem in sau giờ hết ca nhưng trước lúc bấm kết ca, tối đa 2 giờ, thuộc ca cũ),
-- nhưng duc_recompute_tt_ca của ca đêm lấy cận dưới = 18:00 → cộng trùng ở cả 2 ca.
--
-- Sửa: cận dưới của ca = thời điểm kết ca trước, nếu ca trước kết trong 2 giờ đầu ca này.
-- Kết ca (insert/update thoi_diem_ket_ca của duc_bao_cao_ca) → tính lại TT ca các dòng ca khác.
-- Giữ nguyên khoá FOR UPDATE (D43), cận trên D44 và TT tuần theo mã (D62).

create or replace function public.duc_recompute_tt_ca(p_ma_may text, p_ma_sp text)
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
  v_ket_ca_truoc timestamptz;
begin
  -- p_ma_may NULL = tem thành phẩm công đoạn sau → không ảnh hưởng số đúc.
  if p_ma_may is null or p_ma_sp is null then
    return;
  end if;

  -- Khoá mọi dòng của mã (thứ tự cố định) TRƯỚC khi đọc tổng tem (D43 → D62).
  perform 1 from duc_ca_hien_tai where ma_sp = p_ma_sp order by id_dong for update;

  -- ── TT tuần theo mã SP (mọi máy) ──────────────────────────────────────────
  v_today_vn := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  v_monday := v_today_vn - (((extract(dow from v_today_vn)::int + 6) % 7));
  v_week_start := (v_monday::timestamp) at time zone 'Asia/Ho_Chi_Minh';
  v_week_end := ((v_monday + 7)::timestamp) at time zone 'Asia/Ho_Chi_Minh';

  select coalesce(sum(so_luong_tt), 0) into v_tt_tuan
  from duc_tem
  where ma_sp = p_ma_sp
    and may_tt is not null   -- chỉ tem ĐÚC; tem thành phẩm công đoạn sau (TP…, Đánh bóng Kẽm) không có máy
    and coalesce(ngay_gio_ghi_nhan, ngay_gio_in) >= v_week_start
    and coalesce(ngay_gio_ghi_nhan, ngay_gio_in) <  v_week_end;

  -- ── TT ca theo máy + mã (giữ nguyên D48) ──────────────────────────────────
  select * into v_row
  from duc_ca_hien_tai
  where ma_may = p_ma_may and ma_sp = p_ma_sp
  order by row_seq desc
  limit 1;

  if v_row.id_dong is not null then
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
      -- T205: ca trước kết ca trễ (trong 2 giờ đầu ca này) → tem in trước lúc kết ca đã thuộc ca trước
      -- (D58) → ca này chỉ tính từ lúc kết ca trước.
      select max(b.thoi_diem_ket_ca) into v_ket_ca_truoc
      from duc_bao_cao_ca b
      where b.thoi_diem_ket_ca > v_lower
        and b.thoi_diem_ket_ca <= v_lower + interval '2 hours'
        and (b.ngay, b.ca) is distinct from (v_row.ngay, v_row.ca);
      if v_ket_ca_truoc is not null then
        v_lower := v_ket_ca_truoc;
      end if;
    else
      v_lower := coalesce(v_row.sp_start_time, '1970-01-01'::timestamptz) - interval '30 minutes';
      v_scheduled_end := v_row.sp_end_time;
    end if;

    -- Cận trên (D44): chỉ áp khi ca đã quá giờ kết thúc THEO LỊCH hơn 2 ngày.
    if v_scheduled_end is not null and now() - v_scheduled_end >= interval '2 days' then
      v_upper := v_scheduled_end;
    else
      v_upper := null;
    end if;

    select coalesce(sum(so_luong_tt), 0) into v_tt_ca
    from duc_tem
    where may_tt = p_ma_may and ma_sp = p_ma_sp
      and coalesce(ngay_gio_ghi_nhan, ngay_gio_in) >= v_lower
      and (v_upper is null or coalesce(ngay_gio_ghi_nhan, ngay_gio_in) <= v_upper);

    update duc_ca_hien_tai
    set tt_ca = v_tt_ca,
        version = coalesce(version, 0) + 1,
        last_updated_by = 'system@tem_trigger',
        last_updated_at = now()
    where id_dong = v_row.id_dong
      and coalesce(tt_ca, -1) is distinct from v_tt_ca;
  end if;

  update duc_ca_hien_tai
  set tt_tuan = v_tt_tuan,
      version = coalesce(version, 0) + 1,
      last_updated_by = 'system@tem_trigger',
      last_updated_at = now()
  where ma_sp = p_ma_sp
    and coalesce(tt_tuan, -1) is distinct from v_tt_tuan;
end;
$$;

-- ── Kết ca → tính lại TT ca của các dòng ca khác (ca sau đã có KH) ──────────
create or replace function public.duc_bao_cao_ca_tinh_lai_tt_ca_sau()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare r record;
begin
  if new.thoi_diem_ket_ca is null then return new; end if;
  for r in
    select distinct c.ma_may, c.ma_sp from duc_ca_hien_tai c
     where (c.ngay, c.ca) is distinct from (new.ngay, new.ca)
       and c.ma_may is not null and coalesce(c.ma_sp, '') <> ''
     order by 1, 2
  loop
    perform duc_recompute_tt_ca(r.ma_may, r.ma_sp);
  end loop;
  return new;
end $$;
revoke execute on function public.duc_bao_cao_ca_tinh_lai_tt_ca_sau() from public, anon, authenticated;

drop trigger if exists trg_duc_bao_cao_ca_tinh_lai_tt_ca_sau on public.duc_bao_cao_ca;
create trigger trg_duc_bao_cao_ca_tinh_lai_tt_ca_sau
  after insert or update of thoi_diem_ket_ca on public.duc_bao_cao_ca
  for each row execute function public.duc_bao_cao_ca_tinh_lai_tt_ca_sau();

-- ── Tính lại ngay các dòng ca đang mở ────────────────────────────────────────
do $$
declare r record;
begin
  for r in select distinct ma_may, ma_sp from duc_ca_hien_tai
            where ma_may is not null and coalesce(ma_sp, '') <> '' order by 1, 2 loop
    perform duc_recompute_tt_ca(r.ma_may, r.ma_sp);
  end loop;
end $$;
