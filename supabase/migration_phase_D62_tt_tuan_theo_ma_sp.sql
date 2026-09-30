-- ============================================================================
-- D62 — "TT tuần" trên dashboard Đúc tính theo MÃ SP (gộp mọi máy).
--
-- Trước (D24→D48): tt_tuan = tổng so_luong_tt của tem cùng MÁY + MÃ trong
-- tuần hiện tại → cùng 1 mã chạy 2 máy trong tuần thì mỗi thẻ chỉ thấy phần
-- của máy mình (VD TTI-MOT-02: DC 11 = 8.768, DC 4 = 0).
-- Nay: tt_tuan = tổng so_luong_tt của MỌI tem ĐÚC (may_tt có giá trị) cùng
-- ma_sp trong tuần hiện tại — bảng duc_tem còn chứa tem thành phẩm công đoạn
-- sau (TP…, tram_cong_doan = 'Đánh bóng Kẽm', may_tt NULL) cùng mã, phải loại
-- ra kẻo cộng trùng (VD EXE-SHO-01 tuần 28/09 có 6.780 pcs tem TP)
-- (Thứ Hai 00:00 → hết Chủ Nhật, giờ VN; mốc = coalesce(ngay_gio_ghi_nhan,
-- ngay_gio_in) như D48), và ghi cùng giá trị cho MỌI dòng duc_ca_hien_tai
-- có ma_sp đó.
--
-- tt_ca GIỮ NGUYÊN theo máy + mã + khung giờ ca (bản D48).
--
-- Chống race (D43): trước khi đọc tổng tem, khoá FOR UPDATE toàn bộ dòng
-- duc_ca_hien_tai của ma_sp theo thứ tự id_dong (cố định) — 2 tem cùng mã in
-- sát nhau ở 2 máy khác nhau sẽ tính tuần tự, không mất lượt cập nhật, không
-- deadlock lẫn nhau. Dòng đang tính tt_ca nằm trong tập đã khoá.
--
-- Tem in ở máy không có dòng của mã đó (VD Kanban đổi máy) vẫn cập nhật
-- tt_tuan cho các dòng của mã ở máy khác (trước đây hàm return sớm).
--
-- An toàn chạy lại nhiều lần. Chạy trên CẢ 2 project (production + staging).
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

-- Backfill — tính lại cho mọi cặp (máy, mã) đang có trên dashboard.
do $$
declare r record;
begin
  for r in select distinct ma_may, ma_sp from duc_ca_hien_tai where ma_may is not null and ma_sp is not null
  loop
    perform duc_recompute_tt_ca(r.ma_may, r.ma_sp);
  end loop;
end $$;

-- Kiểm tra: mọi dòng cùng mã phải cùng tt_tuan.
select ma_sp, string_agg(ma_may || '=' || tt_tuan, ', ' order by ma_may) as tt_tuan_theo_may
from duc_ca_hien_tai
group by ma_sp
order by ma_sp;
