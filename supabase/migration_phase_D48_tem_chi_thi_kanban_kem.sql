-- ============================================================================
-- D48 — Tem chỉ thị sản xuất kiểu Kanban cho máy Kẽm 190T / 160T.
--
-- Luồng MỚI, chạy SONG SONG với luồng in-khi-xong hiện tại (máy DC khác KHÔNG
-- đổi hành vi):
--   1) In TRƯỚC N tem theo KH ca (chỉ thị xuống máy). Tem lúc này:
--      so_luong_tt = NULL, may_tt = NULL, trang_thai = 'Chờ sản xuất',
--      id_lo_chi_thi = <mã lô>, so_thung_stt = <thứ tự thùng>.
--   2) Mỗi thùng xong -> người thao tác quét QR -> duc_ghi_nhan_tem_kanban():
--      set so_luong_tt = so_luong, may_tt (mặc định = may_duc_chi_thi, CHO ĐỔI
--      khi máy hỏng), nguoi_tt = họ tên người thao tác, ngay_gio_ghi_nhan = now(),
--      trang_thai = 'Đã sản xuất'. Trigger trg_duc_tem_sync_actuals (D22) tự
--      chạy duc_recompute_tt_ca -> tt_ca trên dashboard cập nhật ngay.
--   3) Kết ca: duc_end_shift đọc tt_ca (đã chỉ gồm thùng đã quét) — KHÔNG sửa.
--      Tem 'Chờ sản xuất' còn sót để nguyên, hôm sau quét thì rơi vào ca hôm
--      sau (SX bù). duc_huy_tem_kanban chỉ để SỬA LỖI (tạo nhầm lô).
--
-- Marker tem Kanban = id_lo_chi_thi IS NOT NULL (không thêm cột bool riêng).
--
-- Thay đổi cốt lõi ở duc_recompute_tt_ca: mốc cửa sổ thời gian đổi từ
-- ngay_gio_in sang coalesce(ngay_gio_ghi_nhan, ngay_gio_in). Tem Kanban chưa
-- quét có so_luong_tt = NULL nên sum() bỏ qua; tem luồng cũ có
-- ngay_gio_ghi_nhan = NULL nên vẫn dùng ngay_gio_in y như trước. Giữ nguyên
-- FOR UPDATE chống race (D43) và bỏ cận trên now() cho ca chưa quá hạn 2 ngày
-- (D44).
--
-- An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Cột mới
-- ─────────────────────────────────────────────────────────────────────────────
alter table duc_tem
  add column if not exists ngay_gio_ghi_nhan timestamptz,
  add column if not exists id_lo_chi_thi     text,
  add column if not exists so_thung_stt      int;

create index if not exists idx_duc_tem_kanban_may_ngay
  on duc_tem (may_duc_chi_thi, ngay) where id_lo_chi_thi is not null;
create index if not exists idx_duc_tem_lo_chi_thi
  on duc_tem (id_lo_chi_thi) where id_lo_chi_thi is not null;

alter table master_products
  add column if not exists sl_dong_goi_chuan numeric;

alter table master_machines
  add column if not exists kanban boolean not null default false;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) duc_recompute_tt_ca — chỉ đổi mốc cửa sổ thời gian sang
--    coalesce(ngay_gio_ghi_nhan, ngay_gio_in). Phần còn lại giữ NGUYÊN bản D44.
-- ─────────────────────────────────────────────────────────────────────────────
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

  -- Khoá đúng dòng đang tính TRƯỚC khi đọc tổng tem (D43).
  select * into v_row
  from duc_ca_hien_tai
  where ma_may = p_ma_may and ma_sp = p_ma_sp
  order by row_seq desc
  limit 1
  for update;

  if v_row.id_dong is null then
    return;
  end if;

  -- Khung giờ chuẩn của ca theo phuong_an_ca + ca (khớp CONFIG.SHIFT_PLANS).
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

  -- D48: mốc so sánh = coalesce(ngay_gio_ghi_nhan, ngay_gio_in).
  --   - Tem Kanban đã quét: ngay_gio_ghi_nhan = lúc quét -> tính vào đúng ca quét.
  --   - Tem Kanban chưa quét: so_luong_tt = NULL -> sum() bỏ qua (mốc không quan trọng).
  --   - Tem luồng cũ: ngay_gio_ghi_nhan = NULL -> dùng ngay_gio_in như trước.
  select coalesce(sum(so_luong_tt), 0) into v_tt_ca
  from duc_tem
  where may_tt = p_ma_may and ma_sp = p_ma_sp
    and coalesce(ngay_gio_ghi_nhan, ngay_gio_in) >= v_lower
    and (v_upper is null or coalesce(ngay_gio_ghi_nhan, ngay_gio_in) <= v_upper);

  v_today_vn := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  v_monday := v_today_vn - (((extract(dow from v_today_vn)::int + 6) % 7));
  v_week_start := (v_monday::timestamp) at time zone 'Asia/Ho_Chi_Minh';
  v_week_end := ((v_monday + 7)::timestamp) at time zone 'Asia/Ho_Chi_Minh';

  select coalesce(sum(so_luong_tt), 0) into v_tt_tuan
  from duc_tem
  where may_tt = p_ma_may and ma_sp = p_ma_sp
    and coalesce(ngay_gio_ghi_nhan, ngay_gio_in) >= v_week_start
    and coalesce(ngay_gio_ghi_nhan, ngay_gio_in) <  v_week_end;

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

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) duc_tao_lo_kanban — sinh N tem chỉ thị cho 1 ca
-- ─────────────────────────────────────────────────────────────────────────────
-- p_sl_thung_cuoi: số lượng thùng CUỐI (khi KH không chia hết cho quy cách).
--   NULL hoặc <=0 -> mọi thùng đều = p_sl_thung.
-- Trả về: { ok, id_lo_chi_thi, so_tem, tems: [{ tag_no, ma_sp, ten_sp, so_luong,
--   so_khuon, nguyen_lieu, may_duc_chi_thi, ngay, so_thung_stt, tong_so_thung }] }
-- Frontend tự dựng chuỗi QR theo format cũ: tag_no>ten_sp>ma_sp>so_luong>ngay>
--   lot>so_khuon>nguyen_lieu>may_duc_chi_thi
create or replace function duc_tao_lo_kanban(
  p_ma_may text,
  p_ma_sp text,
  p_ngay date,
  p_ca text,
  p_so_thung int,
  p_sl_thung numeric,
  p_sl_thung_cuoi numeric,
  p_so_khuon text,
  p_nguyen_lieu text,
  p_nguoi text
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_ten_sp text;
  v_so_khuon text;
  v_nguyen_lieu text;
  v_lo text;
  v_tag text;
  v_sl numeric;
  v_tems jsonb := '[]'::jsonb;
  i int;
  v_loai_sp text;
begin
  if p_ma_may is null or trim(p_ma_may) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu mã máy');
  end if;
  if p_ma_sp is null or trim(p_ma_sp) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu mã SP');
  end if;
  if p_ngay is null then
    return jsonb_build_object('ok', false, 'error', 'Thiếu ngày sản xuất');
  end if;
  if coalesce(p_so_thung, 0) < 1 then
    return jsonb_build_object('ok', false, 'error', 'Số thùng phải >= 1');
  end if;
  if coalesce(p_sl_thung, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Số lượng/thùng phải > 0');
  end if;
  if p_so_thung > 500 then
    return jsonb_build_object('ok', false, 'error', 'Tối đa 500 tem/lô');
  end if;

  select ten_sp, so_khuon, nguyen_lieu
    into v_ten_sp, v_so_khuon, v_nguyen_lieu
  from master_products where ma_sp = p_ma_sp;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Mã SP không có trong danh mục: ' || p_ma_sp);
  end if;

  v_so_khuon := coalesce(nullif(trim(p_so_khuon), ''), v_so_khuon, '');
  v_nguyen_lieu := coalesce(nullif(trim(p_nguyen_lieu), ''), v_nguyen_lieu, '');
  v_loai_sp := case when p_ma_sp ilike 'D-%' or v_ten_sp ilike '%phát triển%' then 'phattrien' else 'hangloat' end;

  v_lo := 'LK' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYYMMDDHH24MISS')
          || '_' || regexp_replace(p_ma_may, '\s+', '', 'g');

  for i in 1..p_so_thung loop
    v_tag := duc_next_tag_no(v_loai_sp);
    if i = p_so_thung and coalesce(p_sl_thung_cuoi, 0) > 0 then
      v_sl := p_sl_thung_cuoi;
    else
      v_sl := p_sl_thung;
    end if;

    insert into duc_tem (
      tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
      may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
      nguoi_tt, ngay_gio_xuat, nguoi_nhan, trang_thai, ghi_chu2, ng, ghi_chu_sl,
      id_lo_chi_thi, so_thung_stt, ngay_gio_ghi_nhan
    ) values (
      v_tag, v_ten_sp, p_ma_sp, v_sl, p_ngay, p_ngay::text, v_so_khuon, v_nguyen_lieu,
      p_ma_may, 'Kanban ' || coalesce(p_ca, '') || ' — thùng ' || i || '/' || p_so_thung,
      now(), v_so_khuon, null, null,
      null, null, null, 'Chờ sản xuất', null, null, 'Chờ ghi nhận Kanban',
      v_lo, i, null
    );

    v_tems := v_tems || jsonb_build_array(jsonb_build_object(
      'tag_no', v_tag, 'ma_sp', p_ma_sp, 'ten_sp', v_ten_sp, 'so_luong', v_sl,
      'so_khuon', v_so_khuon, 'nguyen_lieu', v_nguyen_lieu, 'may_duc_chi_thi', p_ma_may,
      'ngay', p_ngay, 'so_thung_stt', i, 'tong_so_thung', p_so_thung
    ));
  end loop;

  return jsonb_build_object('ok', true, 'id_lo_chi_thi', v_lo, 'so_tem', p_so_thung, 'tems', v_tems);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) duc_ghi_nhan_tem_kanban — quét QR ghi nhận 1 thùng đã sản xuất
-- ─────────────────────────────────────────────────────────────────────────────
-- p_may_tt: NULL -> dùng may_duc_chi_thi trên tem. Khác -> máy đúc thực tế
--   (trường hợp máy hỏng phải chuyển). p_nguoi_tt: họ tên người thao tác
--   (MãNV_TênNV, do frontend truyền — mặc định tài khoản đăng nhập, cho chọn khác).
create or replace function duc_ghi_nhan_tem_kanban(
  p_tag_no text,
  p_may_tt text,
  p_nguoi_tt text
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_tem duc_tem%rowtype;
  v_may text;
begin
  if p_tag_no is null or trim(p_tag_no) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu Tag No');
  end if;

  select * into v_tem from duc_tem where tag_no = trim(p_tag_no) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || p_tag_no);
  end if;
  if v_tem.id_lo_chi_thi is null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || p_tag_no || ' không phải tem chỉ thị Kanban');
  end if;
  if v_tem.trang_thai = 'Hủy' then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || p_tag_no || ' đã bị hủy');
  end if;
  if v_tem.trang_thai <> 'Chờ sản xuất' or v_tem.ngay_gio_ghi_nhan is not null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Tem ' || p_tag_no || ' đã được ghi nhận lúc '
        || to_char(v_tem.ngay_gio_ghi_nhan at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM')
        || ' bởi ' || coalesce(v_tem.nguoi_tt, '(không rõ)'),
      'da_ghi_nhan', true
    );
  end if;

  v_may := coalesce(nullif(trim(p_may_tt), ''), v_tem.may_duc_chi_thi);

  update duc_tem set
    so_luong_tt = so_luong,
    so_khuon_tt = coalesce(so_khuon_tt, so_khuon),
    may_tt = v_may,
    nguoi_tt = p_nguoi_tt,
    ngay_gio_ghi_nhan = now(),
    ngay_gio_xuat = now(),
    trang_thai = 'Đã sản xuất',
    ghi_chu_sl = 'Đã ghi nhận Kanban'
  where tag_no = v_tem.tag_no;
  -- trigger trg_duc_tem_sync_actuals (D22) tự chạy duc_recompute_tt_ca(v_may, ma_sp)

  return jsonb_build_object(
    'ok', true,
    'tag_no', v_tem.tag_no,
    'ma_sp', v_tem.ma_sp,
    'ten_sp', v_tem.ten_sp,
    'so_luong', v_tem.so_luong,
    'so_thung_stt', v_tem.so_thung_stt,
    'may_tt', v_may,
    'doi_may', v_may is distinct from v_tem.may_duc_chi_thi,
    'ngay_gio_ghi_nhan', now()
  );
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) duc_huy_tem_kanban — hủy tem chỉ thị CHƯA ghi nhận (chỉ dùng SỬA LỖI)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function duc_huy_tem_kanban(
  p_id_lo text,
  p_tag_no text[],
  p_nguoi text
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_n int;
begin
  if (p_id_lo is null or trim(p_id_lo) = '') and (p_tag_no is null or array_length(p_tag_no, 1) is null) then
    return jsonb_build_object('ok', false, 'error', 'Cần id_lo_chi_thi hoặc danh sách tag_no');
  end if;

  update duc_tem set
    trang_thai = 'Hủy',
    ghi_chu_sl = 'Hủy tem Kanban bởi ' || coalesce(p_nguoi, '(không rõ)') || ' lúc '
      || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM/YYYY')
  where id_lo_chi_thi is not null
    and trang_thai = 'Chờ sản xuất'
    and ngay_gio_ghi_nhan is null
    and (
      (p_id_lo is not null and trim(p_id_lo) <> '' and id_lo_chi_thi = trim(p_id_lo))
      or (p_tag_no is not null and tag_no = any(p_tag_no))
    );
  get diagnostics v_n = row_count;

  return jsonb_build_object('ok', true, 'so_tem_huy', v_n);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6) Grants — RPC gọi từ trình duyệt (authenticated), chặn anon
-- ─────────────────────────────────────────────────────────────────────────────
revoke execute on function duc_tao_lo_kanban(text, text, date, text, int, numeric, numeric, text, text, text) from anon;
grant  execute on function duc_tao_lo_kanban(text, text, date, text, int, numeric, numeric, text, text, text) to authenticated;
revoke execute on function duc_ghi_nhan_tem_kanban(text, text, text) from anon;
grant  execute on function duc_ghi_nhan_tem_kanban(text, text, text) to authenticated;
revoke execute on function duc_huy_tem_kanban(text, text[], text) from anon;
grant  execute on function duc_huy_tem_kanban(text, text[], text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7) Backfill an toàn — tính lại tt_ca/tt_tuan cho mọi cặp (máy, mã SP) đang có
--    (công thức coalesce mới không đổi kết quả cho dữ liệu cũ, chạy cho chắc)
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare r record;
begin
  for r in select distinct ma_may, ma_sp from duc_ca_hien_tai where ma_may is not null and ma_sp is not null
  loop
    perform duc_recompute_tt_ca(r.ma_may, r.ma_sp);
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8) (tùy chọn) đánh dấu 2 máy Kẽm chạy Kanban — bỏ comment nếu muốn set sẵn
-- ─────────────────────────────────────────────────────────────────────────────
-- update master_machines set kanban = true where ma_may in ('Kẽm 190T', 'Kẽm 160T');
