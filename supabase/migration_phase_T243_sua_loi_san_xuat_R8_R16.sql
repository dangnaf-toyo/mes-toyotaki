-- ============================================================================
-- T243 (11/11/2026) — Rà soát 04/11 Đợt 2: sửa 9 lỗi làm sai / mất dữ liệu sản xuất (R8–R16)
--   R8  Kết ca mất sự cố đang mở khi ca sau đã có dòng KH: duc_carry_over_shift gặp dòng có sẵn
--       → chuyển sự cố vào dòng đó (chính nếu trống, không thì thành sự cố phụ) + dời sự cố phụ.
--   R9  Mã bản ghi sự cố count(*)+1 trùng khoá sau khi xoá → duc_next_id_ban_ghi = max(hậu tố)+1.
--   R10 duc_tem_sua: giữ phần SL đã tiêu thụ (so_luong_tt − so_luong); chặn đổi mã SP / SL khi tem
--       đã dùng ở công đoạn sau (duc_tem_dang_dung).
--   R11 duc_tem_xoa: chặn xoá tem đã chuyển công đoạn / khai Bavia / Gia công / phiếu xuất kho…
--   R12 gc_quet: chỉ nhận tem từ công đoạn LIỀN TRƯỚC Gia công theo lưu trình.
--   R13 Phút dừng tính theo MÁY (máy ghép 2 mã không cộng trùng): duc_tinh_phut_dung_may bỏ điều
--       kiện ma_sp; duc_end_shift hợp khoảng theo máy rồi cắt theo giờ chạy từng dòng;
--       duc_doi_phuong_an_ca chuyển mọi dòng của máy (không tách cặp). Tính lại phut_dung_may cũ.
--   R14 Ngày không SX theo KHSX (duc_ca_khong_sx): sự cố chuyển qua ca đó không tính giờ dừng
--       (kết ca + đóng sự cố); auto-close tự tick chuyển tiếp máy có sự cố thay vì bỏ cả ca.
--   R15 duc_tem_mo_coi_ca: tem in trong ca có máy nhưng mã SP không thuộc dòng đang chạy
--       (sản lượng ca không cộng) → hiện ở hộp kết ca; intem.html cảnh báo trước khi in.
--   R16 F1 tự đóng (IPQC OK) ghi tách theo ca như duc_resolve_incident (duc_su_co_ghi_log_theo_ca).
-- An toàn chạy lại. Trạng thái: ĐÃ chạy STAGING 11/11/2026, test SQL rollback 9 mục đạt (R8–R16); CHƯA chạy PROD.
-- ============================================================================

-- ── R9: mã bản ghi kế tiếp ───────────────────────────────────────────────────
create or replace function public.duc_next_id_ban_ghi(p_prefix text) returns text
language sql stable security definer set search_path = public as $$
  select p_prefix || '_' || (coalesce(max(nullif(substring(id_ban_ghi from '_([0-9]+)$'), '')::int), 0) + 1)
  from public.duc_su_co_log where id_ban_ghi like p_prefix || '\_%';
$$;
revoke all on function public.duc_next_id_ban_ghi(text) from public, anon, authenticated;

-- ── R14: ca / ngày không sản xuất theo KHSX tuần ─────────────────────────────
-- true khi tuần có KHSX và (số ca khai cho máy ngày đó = 0, hoặc không khai số ca mà tổng KH
-- ngày của máy = 0). Tuần chưa lập KHSX → false (coi như có SX, giữ hành vi cũ).
create or replace function public.duc_ca_khong_sx(p_ngay date, p_ma_may text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare v_tuan date := date_trunc('week', p_ngay)::date; v_col text; v_so_ca int; v_kh numeric; v_co_may boolean;
begin
  if p_ngay is null or p_ma_may is null then return false; end if;
  v_col := (array['t2','t3','t4','t5','t6','t7','cn'])[(p_ngay - v_tuan) + 1];
  execute format('select %I from public.duc_khsx_tuan_so_ca where tuan_bat_dau = $1 and ma_may = $2', v_col)
    into v_so_ca using v_tuan, p_ma_may;
  if v_so_ca is not null then return v_so_ca = 0; end if;
  -- Máy không có dòng KHSX nào trong tuần → không kết luận được (coi như có SX, giữ hành vi cũ)
  select exists (select 1 from public.duc_khsx_tuan_plan where tuan_bat_dau = v_tuan and ma_may = p_ma_may) into v_co_may;
  if not v_co_may then return false; end if;
  execute format('select coalesce(sum(coalesce(%I, 0)), 0) from public.duc_khsx_tuan_plan where tuan_bat_dau = $1 and ma_may = $2', v_col)
    into v_kh using v_tuan, p_ma_may;
  return v_kh = 0;
end $$;
revoke all on function public.duc_ca_khong_sx(date, text) from public, anon;
grant execute on function public.duc_ca_khong_sx(date, text) to authenticated;

-- ── R9 + R14 + R16: ghi sự cố vào duc_su_co_log tách theo ca (dùng chung) ────
create or replace function public.duc_su_co_ghi_log_theo_ca(
  p_id_dong text, p_gio_tro_lai timestamptz, p_noi_dung text, p_dam_nhiem text, p_truong_ca text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_cht record; v_seg record; v_tong_seg int; v_hien int; v_idx int := 0;
  v_ids text[] := '{}'; v_tong_phut int := 0; v_last text; v_id text; v_nd text; v_ksx boolean; v_id_su_co text; v_phut int;
begin
  select ngay, ca, phuong_an_ca, ma_may, ma_sp, ten_sp, so_khuon, open_loai_su_co, open_gio_phat_sinh, open_van_de, open_id_su_co
  into v_cht from public.duc_ca_hien_tai where id_dong = p_id_dong;
  if not found or v_cht.open_gio_phat_sinh is null then raise exception 'Dòng % không có sự cố đang mở', p_id_dong; end if;
  v_id_su_co := coalesce(v_cht.open_id_su_co, public.duc_make_id_su_co(v_cht.ma_may, v_cht.open_gio_phat_sinh));

  -- Số phần sẽ ghi (bỏ phần giữa rơi vào ca không SX — R14)
  select count(*), count(*) filter (where not (public.duc_ca_khong_sx(s.ngay, v_cht.ma_may) and rn < cnt))
  into v_tong_seg, v_hien
  from (select s.*, row_number() over (order by s.seg_start) rn, count(*) over () cnt
        from public.duc_split_incident_by_shift(v_cht.open_gio_phat_sinh, p_gio_tro_lai, v_cht.phuong_an_ca, v_cht.ngay, v_cht.ca) s) s;

  for v_seg in
    select s.*, row_number() over (order by s.seg_start) rn
    from public.duc_split_incident_by_shift(v_cht.open_gio_phat_sinh, p_gio_tro_lai, v_cht.phuong_an_ca, v_cht.ngay, v_cht.ca) s
    order by s.seg_start
  loop
    v_ksx := public.duc_ca_khong_sx(v_seg.ngay, v_cht.ma_may);
    if v_ksx and v_seg.rn < v_tong_seg then continue; end if;   -- R14: ca không SX ở giữa → bỏ
    v_idx := v_idx + 1;
    v_id := public.duc_next_id_ban_ghi(public.duc_make_id_dong(v_seg.ngay, v_seg.ca, v_cht.ma_may, v_cht.ma_sp));   -- R9
    v_nd := coalesce(p_noi_dung, '');
    if v_hien > 1 then
      v_nd := v_nd || E'\n[Phần ' || v_idx || '/' || v_hien || ' — ' || v_seg.ca || ' ' || to_char(v_seg.ngay, 'DD/MM/YYYY')
        || case when v_idx = v_hien then ', xử lý xong]' else ', chuyển tiếp ca sau]' end;
    end if;
    v_phut := v_seg.phut;
    if v_ksx then
      v_phut := 0;
      v_nd := v_nd || E'\n[Ca không sản xuất theo KHSX tuần — không tính giờ dừng máy]';
    end if;
    insert into public.duc_su_co_log (
      id_ban_ghi, ngay, ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, loai_su_co,
      gio_phat_sinh, gio_tro_lai, thoi_gian_dung_phut, van_de, noi_dung_xu_ly,
      dam_nhiem, ghi_chu, truong_ca, thoi_diem_luu, van_de_edited, id_su_co
    ) values (
      v_id, v_seg.ngay, v_seg.ca, public.duc_iso_week(v_seg.ngay), v_cht.ma_may, v_cht.ma_sp, v_cht.ten_sp, v_cht.so_khuon,
      v_cht.open_loai_su_co, v_seg.seg_start, v_seg.seg_end, v_phut,
      v_cht.open_van_de, v_nd, coalesce(p_dam_nhiem, ''), '', coalesce(p_truong_ca, ''), now(), 'No', v_id_su_co
    );
    v_ids := array_append(v_ids, v_id);
    v_tong_phut := v_tong_phut + v_phut;
    v_last := v_id;
  end loop;
  return jsonb_build_object('ids', to_jsonb(v_ids), 'tong_phut', v_tong_phut, 'last_id', v_last, 'id_su_co', v_id_su_co);
end $$;
revoke all on function public.duc_su_co_ghi_log_theo_ca(text, timestamptz, text, text, text) from public, anon, authenticated;

-- duc_resolve_incident: giữ nguyên mọi kiểm tra, chỉ thay vòng ghi log bằng hàm chung.
create or replace function public.duc_resolve_incident(p_id_dong text, p_gio_tro_lai timestamp with time zone, p_bonus_note text, p_truong_ca text, p_user text)
 returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_cht record;
  v_noi_dung_combined text;
  v_kq jsonb;
  v_co_ipqc_ok boolean;
  v_canh_bao_ipqc boolean := false;
  v_canh_bao_ipqc_loai text;
  v_ipqc jsonb;
  v_vuot_ipqc boolean := false;
  v_ct_loi text;
  v_doi_sp text := nullif(current_setting('duc.doi_sp_dong', true), '');
begin
  select ngay, ca, phuong_an_ca, ma_may, ma_sp, ten_sp, so_khuon, open_loai_su_co,
         open_gio_phat_sinh, open_noi_dung_xu_ly, open_van_de, open_dam_nhiem, open_id_su_co
  into v_cht from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng Ca_hien_tai: ' || p_id_dong);
  end if;
  if v_cht.open_gio_phat_sinh is null then
    return jsonb_build_object('ok', false, 'error', 'Dòng này không có sự cố đang mở');
  end if;
  if p_gio_tro_lai < v_cht.open_gio_phat_sinh then
    return jsonb_build_object('ok', false, 'error', 'Giờ trở lại phải sau giờ phát sinh');
  end if;
  if p_gio_tro_lai > now() + interval '1 minute' then
    return jsonb_build_object('ok', false, 'error', 'Giờ trở lại không được ở tương lai');
  end if;

  if v_doi_sp is null and v_cht.open_id_su_co is not null and left(coalesce(v_cht.open_loai_su_co, ''), 2) in ('A2', 'B1', 'F1') then
    v_ct_loi := duc_khuon_ct_kiem('xlbt', v_cht.open_id_su_co, 'dong');
    if v_ct_loi is not null then return jsonb_build_object('ok', false, 'chan_ct', true, 'error', v_ct_loi); end if;
  end if;

  v_ipqc := duc_ipqc_trang_thai_su_co(p_id_dong);
  v_vuot_ipqc := (v_ipqc->>'can_ipqc')::boolean and not (v_ipqc->>'ok')::boolean
                 and (public.has_role('admin', 'qc_manager')
                      or exists (select 1 from public.user_roles ur
                                 where ur.user_id = auth.uid() and ur.role = 'quan_ly_bo_phan'
                                   and 'Thiết bị' = any(coalesce(ur.bo_phan_phu_trach, '{}'))));
  if (v_ipqc->>'can_ipqc')::boolean and not (v_ipqc->>'ok')::boolean
     and not v_vuot_ipqc and v_doi_sp is null and v_cht.open_id_su_co is not null
     and v_cht.open_gio_phat_sinh >= duc_moc_giao_qc()
     and not exists (select 1 from duc_su_co_giao_qc g where g.id_su_co = v_cht.open_id_su_co)
     and not (public.has_role('admin', 'qc_manager')
              or exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role = 'quan_ly_bo_phan'
                         and 'Thiết bị' = any(coalesce(ur.bo_phan_phu_trach, '{}')))) then
    return jsonb_build_object('ok', false, 'chan_giao_qc', true, 'error',
      '⛔ Sự cố ' || v_cht.open_id_su_co || ' chưa bấm "📦 Hoàn thành mẫu & giao QC" (IPQC cũng chưa kiểm OK). Xử lý xong, lấy mẫu thì bấm nút đó để IPQC kiểm; IPQC kiểm OK hoặc Cảnh báo rồi bấm "Xong".');
  end if;

  if (v_ipqc->>'can_ipqc')::boolean and not (v_ipqc->>'ok')::boolean and not v_vuot_ipqc and v_doi_sp is null then
    if not exists (select 1 from duc_ipqc_checkpoint
                   where id_dong = p_id_dong and trang_thai = 'cho_kiem' and loai_kiem in ('sau_su_co', 'doi_khuon')) then
      begin
        perform duc_request_ipqc_check(p_id_dong, 'sau_su_co', v_cht.open_id_su_co, null);
      exception when unique_violation then null;
      end;
    end if;
    return jsonb_build_object('ok', false, 'chan_ipqc', true, 'ket_qua_ipqc', v_ipqc->>'ket_qua', 'error',
      case when v_ipqc->>'ket_qua' is null then
        '⛔ Chưa có kết quả IPQC cho sự cố ' || coalesce(v_cht.open_id_su_co, '') || ' — máy CHƯA được chạy lại. Đã gửi yêu cầu kiểm sang IPQC; khi IPQC kiểm OK hoặc Cảnh báo thì bấm "Xử lý xong" lại.'
      else
        '⛔ IPQC kiểm sự cố ' || coalesce(v_cht.open_id_su_co, '') || ' KHÔNG ĐẠT (' || (v_ipqc->>'ket_qua') || ') — máy CHƯA được chạy lại. Xử lý tiếp rồi nhờ IPQC kiểm lại; chỉ khi lần kiểm mới nhất là OK hoặc Cảnh báo mới kết thúc được sự cố.'
      end);
  end if;

  v_noi_dung_combined := coalesce(v_cht.open_noi_dung_xu_ly, '');
  if p_bonus_note is not null and trim(p_bonus_note) <> '' then
    v_noi_dung_combined := case when v_noi_dung_combined <> '' then v_noi_dung_combined || E'\n[BS] ' || trim(p_bonus_note) else trim(p_bonus_note) end;
  end if;
  if v_vuot_ipqc then
    v_noi_dung_combined := case when v_noi_dung_combined <> '' then v_noi_dung_combined || E'\n' else '' end
      || '[Đóng khi IPQC chưa OK (' || coalesce(v_ipqc->>'ket_qua', 'chưa kiểm') || ') — '
      || coalesce(nullif(p_user, ''), p_truong_ca, 'admin/QC Manager') || ']';
  end if;
  if v_doi_sp is not null then
    v_noi_dung_combined := case when v_noi_dung_combined <> '' then v_noi_dung_combined || E'\n' else '' end
      || '[Chưa xử lý xong — kết thúc sự cố lúc đổi sang SP ' || v_doi_sp || '. Khuôn '
      || coalesce(nullif(trim(v_cht.so_khuon), ''), '?') || ' xuống máy, tổ khuôn xử lý dứt điểm]';
  end if;

  -- T243 (R9/R14): ghi log tách ca bằng hàm chung
  v_kq := public.duc_su_co_ghi_log_theo_ca(p_id_dong, p_gio_tro_lai, v_noi_dung_combined, v_cht.open_dam_nhiem, p_truong_ca);

  perform duc_clear_incident_open(p_id_dong, coalesce(p_truong_ca, p_user, 'system'));

  return jsonb_build_object(
    'ok', true, 'id_ban_ghi', v_kq->>'last_id', 'id_ban_ghi_list', v_kq->'ids',
    'thoi_gian_dung_phut', (v_kq->>'tong_phut')::int, 'canh_bao_ipqc', v_canh_bao_ipqc,
    'canh_bao_ipqc_loai', v_canh_bao_ipqc_loai, 'id_su_co', v_cht.open_id_su_co, 'vuot_ipqc', v_vuot_ipqc
  );
end;
$function$;

-- R16: F1 tự đóng khi IPQC OK → tách theo ca
create or replace function public.duc_close_f1_incident_if_open(p_id_dong text, p_nguoi_kiem text)
 returns boolean language plpgsql security definer set search_path = public as $function$
declare v_cht record; v_kq jsonb;
begin
  if exists (select 1 from duc_ca_hien_tai where id_dong = p_id_dong and left(coalesce(open_loai_su_co, ''), 2) <> 'F1') then
    perform duc_su_co_doi_cho(p_id_dong, (select id_su_co from duc_su_co_mo_them where id_dong = p_id_dong and left(loai_su_co, 2) = 'F1' order by gio_phat_sinh, id limit 1));
  end if;
  select open_loai_su_co, open_gio_phat_sinh, open_dam_nhiem into v_cht from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found or v_cht.open_loai_su_co is null or left(v_cht.open_loai_su_co, 2) <> 'F1' or v_cht.open_gio_phat_sinh is null then
    return false;
  end if;
  v_kq := public.duc_su_co_ghi_log_theo_ca(p_id_dong, now(),
    'IPQC kiểm tra lại: OK — cho phép sản xuất tiếp' || case when p_nguoi_kiem is not null then ' (' || p_nguoi_kiem || ')' else '' end,
    coalesce(p_nguoi_kiem, v_cht.open_dam_nhiem), '');
  perform duc_clear_incident_open(p_id_dong, coalesce(p_nguoi_kiem, 'system'));
  return true;
end;
$function$;

-- ── R13: phút dừng theo MÁY ──────────────────────────────────────────────────
create or replace function public.duc_tinh_phut_dung_may(p_ma_may text, p_ma_sp text)
 returns void language plpgsql security definer set search_path = public as $function$
declare r record; acc tstzmultirange := '{}'; rg tstzrange; ov numeric; v numeric; v_moc timestamptz := duc_moc_phut_dung_may();
begin
  -- T243: p_ma_sp bỏ qua — máy ghép 2 mã dừng 1 lần tính 1 lần.
  for r in
    select id_ban_ghi, gio_phat_sinh, gio_tro_lai, thoi_gian_dung_phut, phut_dung_may from duc_su_co_log
     where ma_may = p_ma_may and gio_phat_sinh >= v_moc
     order by gio_phat_sinh nulls last, id_ban_ghi
  loop
    if r.gio_tro_lai is null or r.gio_tro_lai <= r.gio_phat_sinh then
      v := r.thoi_gian_dung_phut;
    else
      rg := tstzrange(r.gio_phat_sinh, r.gio_tro_lai);
      select coalesce(sum(extract(epoch from upper(x) - lower(x))), 0) into ov from unnest(acc * tstzmultirange(rg)) x;
      v := greatest(0, coalesce(r.thoi_gian_dung_phut, 0) - round(ov / 60));
      acc := acc + tstzmultirange(rg);
    end if;
    if r.phut_dung_may is distinct from v then
      update duc_su_co_log set phut_dung_may = v where id_ban_ghi = r.id_ban_ghi;
    end if;
  end loop;
  update duc_su_co_log set phut_dung_may = thoi_gian_dung_phut
   where ma_may = p_ma_may and (gio_phat_sinh is null or gio_phat_sinh < v_moc) and phut_dung_may is distinct from thoi_gian_dung_phut;
end $function$;

-- Tính lại cho dữ liệu đang có (từ mốc tính phút dừng máy)
select public.duc_tinh_phut_dung_may(m.ma_may, null)
from (select distinct ma_may from public.duc_su_co_log where gio_phat_sinh >= public.duc_moc_phut_dung_may()) m;

-- duc_doi_phuong_an_ca: chuyển MỌI dòng của máy trong ca (không tách cặp khuôn kép)
create or replace function public.duc_doi_phuong_an_ca(p_ma_may text, p_phuong_an_ca_moi text, p_user text)
 returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_row duc_ca_hien_tai%rowtype; r duc_ca_hien_tai%rowtype;
  v_now_vn timestamp; v_today_vn date; v_t_phut int; v_ca_moi text; v_ngay_moi date;
  v_start_vn timestamp; v_end_vn timestamp; v_tt_ca_cu numeric; v_tt_ca_moi numeric; v_new_id_dong text; v_n int := 0;
begin
  if auth.uid() is not null and not public.has_role(VARIADIC ARRAY['admin', 'truong_ca', 'quan_ly_bo_phan', 'qlsx_nhan_vien', 'qlsx_truong_phong', 'ke_hoach']) then
    raise exception '⛔ Tài khoản không có quyền thực hiện thao tác này — cần vai trò: %', 'Trưởng ca / QLBP / QLSX / Kế hoạch' using errcode = '42501';
  end if;
  p_user := public.duc_ten_nguoi_hien_tai(p_user);
  if p_phuong_an_ca_moi not in ('2 ca 8h', '2 ca 12h') then
    return jsonb_build_object('ok', false, 'error', 'Phương án không hợp lệ — chỉ nhận "2 ca 8h" hoặc "2 ca 12h"');
  end if;
  select * into v_row from duc_ca_hien_tai where ma_may = trim(coalesce(p_ma_may, '')) order by row_seq desc limit 1;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng đang hoạt động của máy: ' || p_ma_may); end if;
  if v_row.ma_sp is null then return jsonb_build_object('ok', false, 'error', 'Máy chưa có mã SP đang chạy, không xác định được để tính lại tt_ca'); end if;
  if v_row.phuong_an_ca = p_phuong_an_ca_moi then return jsonb_build_object('ok', false, 'error', 'Máy đã đang dùng đúng phương án này rồi'); end if;

  v_tt_ca_cu := v_row.tt_ca;
  v_now_vn := now() at time zone 'Asia/Ho_Chi_Minh'; v_today_vn := v_now_vn::date;
  v_t_phut := extract(hour from v_now_vn)::int * 60 + extract(minute from v_now_vn)::int;
  if p_phuong_an_ca_moi = '2 ca 12h' then
    if v_t_phut >= 6*60 and v_t_phut < 18*60 then
      v_ca_moi := 'Ca ngày'; v_ngay_moi := v_today_vn; v_start_vn := v_today_vn + time '06:00'; v_end_vn := v_today_vn + time '18:00';
    elsif v_t_phut >= 18*60 then
      v_ca_moi := 'Ca đêm'; v_ngay_moi := v_today_vn; v_start_vn := v_today_vn + time '18:00'; v_end_vn := (v_today_vn + 1) + time '06:00';
    else
      v_ca_moi := 'Ca đêm'; v_ngay_moi := v_today_vn - 1; v_start_vn := (v_today_vn - 1) + time '18:00'; v_end_vn := v_today_vn + time '06:00';
    end if;
  else
    if v_t_phut >= 6*60 and v_t_phut < 14*60 then
      v_ca_moi := 'Ca 1'; v_ngay_moi := v_today_vn; v_start_vn := v_today_vn + time '06:00'; v_end_vn := v_today_vn + time '14:00';
    elsif v_t_phut >= 14*60 and v_t_phut < 22*60 then
      v_ca_moi := 'Ca 2'; v_ngay_moi := v_today_vn; v_start_vn := v_today_vn + time '14:00'; v_end_vn := v_today_vn + time '22:00';
    else
      return jsonb_build_object('ok', false, 'error',
        'Giờ hiện tại (22h-6h) không thuộc ca nào của phương án "2 ca 8h" — máy nên chờ tới 6h sáng, hoặc dùng "2 ca 12h" (có Ca đêm 18h-6h)');
    end if;
  end if;

  -- T243 (R13): mọi dòng của máy trong cùng (ngày, ca) đi cùng nhau
  for r in select * from duc_ca_hien_tai where ma_may = v_row.ma_may and ngay = v_row.ngay and ca = v_row.ca and ma_sp is not null order by row_seq loop
    v_new_id_dong := duc_make_id_dong(v_ngay_moi, v_ca_moi, r.ma_may, r.ma_sp);
    if v_new_id_dong <> r.id_dong and exists (select 1 from duc_ca_hien_tai where id_dong = v_new_id_dong) then
      return jsonb_build_object('ok', false, 'error',
        'Đã có sẵn 1 dòng khác cho máy ' || r.ma_may || ' / SP ' || r.ma_sp || ' đúng (ngày,ca) mới (' || v_ngay_moi || ', ' || v_ca_moi || ') — không thể đổi tự động, cần gộp thủ công để tránh trùng khoá khi kết ca.');
    end if;
  end loop;
  for r in select * from duc_ca_hien_tai where ma_may = v_row.ma_may and ngay = v_row.ngay and ca = v_row.ca and ma_sp is not null order by row_seq loop
    v_new_id_dong := duc_make_id_dong(v_ngay_moi, v_ca_moi, r.ma_may, r.ma_sp);
    update duc_ca_hien_tai set
      id_dong = v_new_id_dong, phuong_an_ca = p_phuong_an_ca_moi, ca = v_ca_moi, ngay = v_ngay_moi,
      sp_start_time = v_start_vn at time zone 'Asia/Ho_Chi_Minh', sp_end_time = v_end_vn at time zone 'Asia/Ho_Chi_Minh',
      version = coalesce(version, 0) + 1, last_updated_by = coalesce(nullif(trim(p_user), ''), 'system'), last_updated_at = now()
    where id_dong = r.id_dong;
    update duc_ca_hien_tai set khuon_kep_voi = v_new_id_dong where khuon_kep_voi = r.id_dong;
    perform duc_recompute_tt_ca(r.ma_may, r.ma_sp);
    v_n := v_n + 1;
  end loop;
  select tt_ca into v_tt_ca_moi from duc_ca_hien_tai where id_dong = duc_make_id_dong(v_ngay_moi, v_ca_moi, v_row.ma_may, v_row.ma_sp);
  return jsonb_build_object('ok', true, 'ma_may', v_row.ma_may, 'so_dong', v_n,
    'phuong_an_ca_cu', v_row.phuong_an_ca, 'ca_cu', v_row.ca, 'ngay_cu', v_row.ngay,
    'phuong_an_ca_moi', p_phuong_an_ca_moi, 'ca_moi', v_ca_moi, 'ngay_moi', v_ngay_moi,
    'tt_ca_cu', v_tt_ca_cu, 'tt_ca_moi', v_tt_ca_moi);
end;
$function$;

-- ── R8: chuyển tiếp ca — gặp dòng có sẵn thì chuyển sự cố vào, không bỏ ───
create or replace function public.duc_carry_over_shift(p_ngay date, p_ca text, p_phuong_an_ca text, p_carry_over_list jsonb)
 returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_next jsonb; v_item jsonb; v_old record; v_dich record; v_new_id_dong text; v_win jsonb; v_kh_ca_moi numeric; v_carry_shot numeric;
  v_old_to_new jsonb := '{}'::jsonb; v_now timestamptz := now(); v_carried jsonb := '[]'::jsonb; v_ghep boolean;
  v_nd text;
begin
  if p_carry_over_list is null or jsonb_array_length(p_carry_over_list) = 0 then
    return jsonb_build_object('carried', '[]'::jsonb, 'next_ngay', null, 'next_ca', null);
  end if;
  v_next := duc_get_next_shift(p_ngay, p_ca, p_phuong_an_ca);
  if v_next is null then raise exception 'Không xác định được ca kế tiếp cho % / %', p_phuong_an_ca, p_ca; end if;

  for v_item in select * from jsonb_array_elements(p_carry_over_list) loop
    select * into v_old from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and ma_may = (v_item->>'ma_may') and ma_sp = (v_item->>'ma_sp');
    if not found then continue; end if;
    v_new_id_dong := duc_make_id_dong((v_next->>'ngay')::date, v_next->>'ca', v_old.ma_may, v_old.ma_sp);
    v_nd := '[Chuyển tiếp từ ' || p_ca || ' ' || to_char(p_ngay, 'DD/MM/YYYY') || ']';
    v_ghep := false;

    select * into v_dich from duc_ca_hien_tai where id_dong = v_new_id_dong for update;
    if found then
      -- T243 (R8): ca sau đã có dòng KH → đưa sự cố đang mở sang dòng đó, không được mất
      v_ghep := true;
      if v_old.open_gio_phat_sinh is not null then
        if v_dich.open_gio_phat_sinh is null then
          update duc_ca_hien_tai set
            open_loai_su_co = v_old.open_loai_su_co, open_gio_phat_sinh = v_old.open_gio_phat_sinh, open_van_de = v_old.open_van_de,
            open_noi_dung_xu_ly = coalesce(v_old.open_noi_dung_xu_ly, '') || case when coalesce(v_old.open_noi_dung_xu_ly, '') <> '' then E'\n' else '' end || v_nd,
            open_dam_nhiem = v_old.open_dam_nhiem, open_id_su_co = v_old.open_id_su_co,
            version = coalesce(version, 0) + 1, last_updated_by = 'system@carry-over', last_updated_at = v_now
          where id_dong = v_new_id_dong;
        else
          insert into duc_su_co_mo_them (id_dong, loai_su_co, gio_phat_sinh, van_de, noi_dung_xu_ly, dam_nhiem, id_su_co)
          values (v_new_id_dong, coalesce(nullif(v_old.open_loai_su_co, ''), '?'), v_old.open_gio_phat_sinh, coalesce(v_old.open_van_de, ''),
                  coalesce(v_old.open_noi_dung_xu_ly, '') || case when coalesce(v_old.open_noi_dung_xu_ly, '') <> '' then E'\n' else '' end || v_nd,
                  coalesce(v_old.open_dam_nhiem, ''), coalesce(v_old.open_id_su_co, duc_make_id_su_co(v_old.ma_may, v_old.open_gio_phat_sinh)));
        end if;
      end if;
    else
      v_win := duc_get_shift_window((v_next->>'ngay')::date, p_phuong_an_ca, v_next->>'ca');
      v_kh_ca_moi := coalesce((v_item->>'kh_ca_moi')::numeric, v_old.kh_ca, 0);
      v_carry_shot := v_old.so_shot_cuoi_ca;
      if v_carry_shot is null then select so_shot_cuoi_ca_gan_nhat into v_carry_shot from duc_shot_may where ma_may = v_old.ma_may; end if;
      insert into duc_ca_hien_tai (
        id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, kh_ca, kh_tuan, tt_ca, tt_tuan, nv_ca_ngay, nv_ca_dem,
        open_loai_su_co, open_gio_phat_sinh, open_van_de, open_noi_dung_xu_ly, open_dam_nhiem, open_id_su_co,
        version, last_updated_by, last_updated_at, so_shot_nong_khuon, so_luong_ng, phan_loai_ng, sp_start_time, sp_end_time, so_shot_khuon_snapshot,
        so_shot_dau_ca, so_shot_cuoi_ca
      ) values (
        v_new_id_dong, (v_next->>'ngay')::date, v_next->>'ca', p_phuong_an_ca, duc_iso_week((v_next->>'ngay')::date),
        v_old.ma_may, v_old.ma_sp, v_old.ten_sp, v_old.so_khuon, v_kh_ca_moi, coalesce((v_item->>'kh_tuan_moi')::numeric, v_old.kh_tuan, 0), 0, 0,
        v_old.nv_ca_ngay, v_old.nv_ca_dem,
        case when v_old.open_gio_phat_sinh is not null then v_old.open_loai_su_co else null end, v_old.open_gio_phat_sinh, v_old.open_van_de,
        case when v_old.open_gio_phat_sinh is not null
          then coalesce(v_old.open_noi_dung_xu_ly, '') || case when coalesce(v_old.open_noi_dung_xu_ly, '') <> '' then E'\n' else '' end || v_nd else null end,
        v_old.open_dam_nhiem, case when v_old.open_gio_phat_sinh is not null then v_old.open_id_su_co else null end,
        1, 'system@carry-over', v_now, 0, 0, '', coalesce((v_win->>'start')::timestamptz, v_now), (v_win->>'end')::timestamptz, 0, v_carry_shot, null
      );
    end if;

    -- sự cố phụ (T178) đi theo sang ca sau (cả 2 trường hợp)
    update duc_su_co_mo_them set id_dong = v_new_id_dong,
      noi_dung_xu_ly = noi_dung_xu_ly || case when noi_dung_xu_ly <> '' then E'\n' else '' end || v_nd
    where id_dong = v_old.id_dong;
    v_old_to_new := jsonb_set(v_old_to_new, array[v_old.id_dong], to_jsonb(v_new_id_dong));
    v_carried := v_carried || jsonb_build_array(jsonb_build_object('ma_may', v_old.ma_may, 'ma_sp', v_old.ma_sp,
      'kh_ca', coalesce(v_kh_ca_moi, v_dich.kh_ca), 'has_open_incident', v_old.open_gio_phat_sinh is not null, 'ghep_dong_co_san', v_ghep));
  end loop;

  for v_old in select id_dong, khuon_kep_voi from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and khuon_kep_voi is not null and khuon_kep_voi <> '' loop
    if v_old_to_new ? v_old.id_dong and v_old_to_new ? v_old.khuon_kep_voi then
      update duc_ca_hien_tai set khuon_kep_voi = v_old_to_new->>v_old.khuon_kep_voi where id_dong = v_old_to_new->>v_old.id_dong;
    end if;
  end loop;
  return jsonb_build_object('carried', v_carried, 'next_ngay', v_next->>'ngay', 'next_ca', v_next->>'ca');
end;
$function$;

-- ── R14: auto-close không bỏ cả ca vì 1 máy còn sự cố — tự chuyển tiếp ─────
create or replace function public.duc_auto_close_forgotten_shifts()
 returns jsonb language plpgsql security definer set search_path = public as $function$
declare v_row record; v_shift_window jsonb; v_result jsonb; v_closed jsonb := '[]'::jsonb; v_skipped jsonb := '[]'::jsonb; v_carry jsonb;
begin
  for v_row in
    select ngay, ca, min(phuong_an_ca) as phuong_an_ca from duc_ca_hien_tai where ma_sp is not null and ma_sp <> '' group by ngay, ca
  loop
    v_shift_window := duc_get_shift_window(v_row.ngay, v_row.phuong_an_ca, v_row.ca);
    if v_shift_window is null then continue; end if;
    if (now() - (v_shift_window->>'end')::timestamptz) < interval '12 hours' then continue; end if;
    if exists (select 1 from duc_bao_cao_ca where ngay = v_row.ngay and ca = v_row.ca) then continue; end if;
    -- T243 (R14): máy còn sự cố mở → tự tick chuyển tiếp (giữ KH ca cũ) để vẫn kết ca được
    select coalesce(jsonb_agg(jsonb_build_object('ma_may', ma_may, 'ma_sp', ma_sp, 'kh_ca_moi', coalesce(kh_ca, 0))), '[]'::jsonb)
    into v_carry from duc_ca_hien_tai where ngay = v_row.ngay and ca = v_row.ca and open_gio_phat_sinh is not null;
    begin
      v_result := duc_end_shift(v_row.ngay, v_row.ca, v_row.phuong_an_ca, 'Hệ thống (tự động)', v_carry,
        'Tự động kết ca — trưởng ca chưa kết ca quá 12 tiếng sau giờ kết thúc ca. Kiểm tra lại nếu số liệu bất thường.'
        || case when jsonb_array_length(v_carry) > 0 then ' Sự cố đang mở tự chuyển tiếp ca sau.' else '' end,
        'system@auto_close_shift');
      if coalesce((v_result->>'ok')::boolean, false) then
        v_closed := v_closed || jsonb_build_array(jsonb_build_object('ngay', v_row.ngay, 'ca', v_row.ca, 'id_bao_cao', v_result->>'id_bao_cao'));
      else
        v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('ngay', v_row.ngay, 'ca', v_row.ca, 'error', v_result->>'error'));
      end if;
    exception when others then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('ngay', v_row.ngay, 'ca', v_row.ca, 'error', sqlerrm));
    end;
  end loop;
  return jsonb_build_object('closed', v_closed, 'skipped', v_skipped);
end;
$function$;

-- ── R15: tem in trong ca nhưng mã SP không thuộc dòng đang chạy của máy ──────
create or replace function public.duc_tem_mo_coi_ca(p_ngay date, p_ca text, p_phuong_an_ca text) returns jsonb
language sql stable security definer set search_path = public as $$
  with w as (select (duc_get_shift_window(p_ngay, p_phuong_an_ca, p_ca)->>'start')::timestamptz s,
                    least(now(), (duc_get_shift_window(p_ngay, p_phuong_an_ca, p_ca)->>'end')::timestamptz) e),
  d as (select ma_may, ma_sp from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and ma_sp is not null)
  select coalesce(jsonb_agg(jsonb_build_object('tag_no', t.tag_no, 'ma_may', t.may_tt, 'ma_sp', t.ma_sp, 'so_luong', t.so_luong_tt,
           'luc', to_char(coalesce(t.ngay_gio_ghi_nhan, t.ngay_gio_in) at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'),
           'dang_chay', (select string_agg(ma_sp, ', ') from d where d.ma_may = t.may_tt)) order by coalesce(t.ngay_gio_ghi_nhan, t.ngay_gio_in)), '[]'::jsonb)
  from duc_tem t, w
  where auth.uid() is not null and t.tag_no not like 'TP%' and t.may_tt in (select ma_may from d)
    and coalesce(t.ngay_gio_ghi_nhan, t.ngay_gio_in) between w.s and w.e
    and not exists (select 1 from d where d.ma_may = t.may_tt and d.ma_sp = t.ma_sp);
$$;
revoke all on function public.duc_tem_mo_coi_ca(date, text, text) from public, anon;
grant execute on function public.duc_tem_mo_coi_ca(date, text, text) to authenticated;

-- ── R13 + R14: duc_end_shift — dừng máy theo MÁY, cắt theo giờ chạy từng dòng ──
create or replace function public.duc_end_shift(p_ngay date, p_ca text, p_phuong_an_ca text, p_truong_ca text, p_carry_over_list jsonb, p_comment_truong_ca text, p_user text)
 returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_now timestamptz := now();
  v_shift_window jsonb; v_break_window jsonb; v_shift_duration_sec numeric; v_break_min numeric;
  v_ws timestamptz; v_we timestamptz;
  v_carry_over_keys text[] := array[]::text[]; v_item jsonb; v_open_not_carried text[] := array[]::text[];
  v_row record; v_id_bao_cao text;
  v_sum_ideal numeric := 0; v_sum_ppt numeric := 0; v_sum_runtime numeric := 0; v_sum_ok numeric := 0; v_sum_ng numeric := 0;
  v_so_may_co_kh int := 0; v_so_may_hoan_thanh int := 0; v_tong_kh numeric := 0; v_tong_tt numeric := 0; v_tong_shot_nong numeric := 0;
  v_so_su_co_ca int; v_so_su_co_dang_do int; v_tong_phut_resolved numeric := 0; v_tong_phut_open numeric := 0;
  v_avail_ca numeric; v_perf_ca numeric; v_quality_ca numeric; v_oee_ca numeric;
  v_is_day_shift boolean; v_personnel text[] := array[]::text[]; v_nv text;
  v_ct numeric; v_downtime numeric; v_row_ppt numeric; v_oee jsonb;
  v_effective_start timestamptz; v_effective_end timestamptz; v_row_span numeric; v_break_sec numeric;
  v_oee_rows jsonb := '[]'::jsonb; v_mold_result jsonb; v_carry_result jsonb; v_history_count int := 0; v_tem_mo_coi jsonb;
begin
  if auth.uid() is not null and not public.has_role(VARIADIC ARRAY['admin', 'truong_ca', 'quan_ly_bo_phan', 'qlsx_truong_phong']) then
    raise exception '⛔ Tài khoản không có quyền thực hiện thao tác này — cần vai trò: %', 'Trưởng ca / QLBP / TP QLSX' using errcode = '42501';
  end if;
  p_user := public.duc_ten_nguoi_hien_tai(p_user);
  v_is_day_shift := (p_ca = 'Ca ngày' or p_ca = 'Ca 1');

  for v_item in select * from jsonb_array_elements(coalesce(p_carry_over_list, '[]'::jsonb)) loop
    v_carry_over_keys := array_append(v_carry_over_keys, (v_item->>'ma_may') || '|' || (v_item->>'ma_sp'));
  end loop;
  for v_row in select ma_may, ma_sp from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and open_gio_phat_sinh is not null loop
    if not ((v_row.ma_may || '|' || v_row.ma_sp) = any(v_carry_over_keys)) then
      v_open_not_carried := array_append(v_open_not_carried, v_row.ma_may || ' (' || v_row.ma_sp || ')');
    end if;
  end loop;
  if array_length(v_open_not_carried, 1) > 0 then
    return jsonb_build_object('ok', false, 'error',
      'Các máy sau đang có sự cố mở nhưng chưa được tick tiếp tục: ' || array_to_string(v_open_not_carried, ', ') ||
      '. Vui lòng resolve sự cố trước khi kết ca, hoặc tick tiếp tục cho máy này.');
  end if;
  if not exists (select 1 from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca)
     and not exists (select 1 from duc_su_co_log where ngay = p_ngay and ca = p_ca) then
    return jsonb_build_object('ok', false, 'error', 'Không có bản ghi đầy đủ thông tin để lưu');
  end if;

  v_shift_window := duc_get_shift_window(p_ngay, p_phuong_an_ca, p_ca);
  if v_shift_window is null then
    return jsonb_build_object('ok', false, 'error', 'Không xác định được khung giờ ca: ' || p_phuong_an_ca || ' / ' || p_ca);
  end if;
  v_ws := (v_shift_window->>'start')::timestamptz;
  v_we := least(v_now, (v_shift_window->>'end')::timestamptz);
  v_shift_duration_sec := extract(epoch from ((v_shift_window->>'end')::timestamptz - v_ws));
  v_break_window := duc_get_break_window(p_ngay, p_phuong_an_ca, p_ca);
  v_break_min := case when v_break_window is not null
    then extract(epoch from ((v_break_window->>'end')::timestamptz - (v_break_window->>'start')::timestamptz)) / 60 else 0 end;

  -- T243 (R13/R14): phần trong ca của sự cố còn mở, HỢP theo MÁY, trừ phần đã nằm trong sự cố đã
  -- đóng của máy; máy ở ca không sản xuất theo KHSX không tính.
  select coalesce(sum(sec), 0) / 60 into v_tong_phut_open from (
    with mo as (
      select c.ma_may, tstzrange(greatest(c.open_gio_phat_sinh, v_ws), v_we) r from duc_ca_hien_tai c
       where c.ngay = p_ngay and c.ca = p_ca and c.open_gio_phat_sinh is not null and greatest(c.open_gio_phat_sinh, v_ws) < v_we
         and not duc_ca_khong_sx(p_ngay, c.ma_may)
      union all
      select c.ma_may, tstzrange(greatest(t.gio_phat_sinh, v_ws), v_we) from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong
       where c.ngay = p_ngay and c.ca = p_ca and greatest(t.gio_phat_sinh, v_ws) < v_we and not duc_ca_khong_sx(p_ngay, c.ma_may)),
    g as (select ma_may, range_agg(r) mr from mo group by ma_may),
    dong as (select ma_may, range_agg(tstzrange(gio_phat_sinh, gio_tro_lai)) mr from duc_su_co_log
              where ngay = p_ngay and ca = p_ca and gio_tro_lai > gio_phat_sinh group by ma_may)
    select (select coalesce(sum(extract(epoch from upper(x) - lower(x))), 0) from unnest(g.mr - coalesce(dong.mr, '{}'::tstzmultirange)) x) sec
    from g left join dong on dong.ma_may = g.ma_may) z;
  v_tong_phut_open := round(v_tong_phut_open);

  select coalesce(sum(coalesce(phut_dung_may, thoi_gian_dung_phut)), 0) into v_tong_phut_resolved from duc_su_co_log where ngay = p_ngay and ca = p_ca;
  select count(*) into v_so_su_co_ca from duc_su_co_log where ngay = p_ngay and ca = p_ca;
  select count(*) + (select count(*) from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong where c.ngay = p_ngay and c.ca = p_ca)
    into v_so_su_co_dang_do from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and open_gio_phat_sinh is not null;

  for v_row in select * from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and ma_sp is not null and ma_sp <> '' and kh_ca is not null loop
    v_tong_kh := v_tong_kh + coalesce(v_row.kh_ca, 0);
    v_tong_tt := v_tong_tt + coalesce(v_row.tt_ca, 0);
    v_tong_shot_nong := v_tong_shot_nong + coalesce(v_row.so_shot_nong_khuon, 0);
    v_sum_ok := v_sum_ok + coalesce(v_row.tt_ca, 0);
    v_sum_ng := v_sum_ng + coalesce(v_row.so_luong_ng, 0);
    v_nv := case when v_is_day_shift then v_row.nv_ca_ngay else v_row.nv_ca_dem end;
    if v_nv is not null and trim(v_nv) <> '' and not (trim(v_nv) = any(v_personnel)) then v_personnel := array_append(v_personnel, trim(v_nv)); end if;

    if v_row.sp_start_time is not null and v_row.sp_end_time is not null then
      v_effective_start := v_row.sp_start_time; v_effective_end := least(v_row.sp_end_time, v_now);
    else
      v_effective_start := v_ws; v_effective_end := v_we;
    end if;
    v_row_span := greatest(0, extract(epoch from (v_effective_end - v_effective_start)));
    if v_break_window is not null then
      v_break_sec := duc_sum_break_overlap(v_effective_start, v_effective_end, v_break_window);
    else
      v_break_sec := case when v_shift_duration_sec > 0 then (v_break_min * 60 * v_row_span / v_shift_duration_sec) else 0 end;
    end if;
    v_row_ppt := greatest(0, v_row_span - v_break_sec);

    -- T243 (R13): dừng của dòng = hợp khoảng dừng của MÁY (đã đóng + còn mở) ∩ giờ chạy của dòng
    if v_effective_end > v_effective_start then
      select coalesce(sum(extract(epoch from upper(x) - lower(x))), 0) into v_downtime
      from unnest((
        select coalesce(range_agg(r), '{}'::tstzmultirange) from (
          select tstzrange(gio_phat_sinh, gio_tro_lai) r from duc_su_co_log
           where ma_may = v_row.ma_may and ngay = p_ngay and ca = p_ca and gio_tro_lai > gio_phat_sinh
          union all
          select tstzrange(greatest(c.open_gio_phat_sinh, v_ws), v_we) from duc_ca_hien_tai c
           where c.ma_may = v_row.ma_may and c.ngay = p_ngay and c.ca = p_ca and c.open_gio_phat_sinh is not null
             and greatest(c.open_gio_phat_sinh, v_ws) < v_we and not duc_ca_khong_sx(p_ngay, c.ma_may)
          union all
          select tstzrange(greatest(t.gio_phat_sinh, v_ws), v_we) from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong
           where c.ma_may = v_row.ma_may and c.ngay = p_ngay and c.ca = p_ca and greatest(t.gio_phat_sinh, v_ws) < v_we
             and not duc_ca_khong_sx(p_ngay, c.ma_may)) q
      ) * tstzmultirange(tstzrange(v_effective_start, v_effective_end))) x;
    else
      v_downtime := 0;
    end if;

    select cycle_time_s into v_ct from master_products where ma_sp = v_row.ma_sp;
    v_oee := duc_calculate_oee(v_ct, v_row.tt_ca, v_row_ppt, v_downtime, v_row.so_luong_ng);
    v_oee_rows := v_oee_rows || jsonb_build_array(jsonb_build_object('id_dong', v_row.id_dong, 'ma_may', v_row.ma_may, 'ma_sp', v_row.ma_sp, 'oee', v_oee));
    if v_ct is not null and v_ct > 0 then
      v_sum_ideal := v_sum_ideal + v_ct * coalesce(v_row.tt_ca, 0);
      v_sum_ppt := v_sum_ppt + v_row_ppt;
      v_sum_runtime := v_sum_runtime + greatest(0, v_row_ppt - v_downtime);
    end if;
  end loop;

  select count(*), count(*) filter (where dat) into v_so_may_co_kh, v_so_may_hoan_thanh
  from (select ma_may, bool_and(coalesce(tt_ca, 0) >= coalesce(kh_ca, 0)) as dat from duc_ca_hien_tai
        where ngay = p_ngay and ca = p_ca and ma_sp is not null and ma_sp <> '' and kh_ca is not null group by ma_may) m;

  v_avail_ca := case when v_sum_ppt > 0 then v_sum_runtime / v_sum_ppt else 0 end;
  v_perf_ca := case when v_sum_runtime > 0 then least(1, v_sum_ideal / v_sum_runtime) else 0 end;
  v_quality_ca := case when (v_sum_ok + v_sum_ng) > 0 then v_sum_ok / (v_sum_ok + v_sum_ng) else 1.0 end;
  v_oee_ca := v_avail_ca * v_perf_ca * v_quality_ca;
  v_id_bao_cao := to_char(p_ngay, 'DDMMYYYY') || '_' || duc_shift_short_id(p_ca);
  v_tem_mo_coi := duc_tem_mo_coi_ca(p_ngay, p_ca, p_phuong_an_ca);   -- R15

  insert into duc_bao_cao_ca (
    id_bao_cao, ngay, ca, phuong_an_ca, tuan_sx, truong_ca, so_may_co_kh, so_may_hoan_thanh_kh,
    tong_kh_ca, tong_tt_ca, ty_le_hoan_thanh_ca, so_su_co_ca, tong_phut_dung_ca, url_gdoc_bao_cao,
    thoi_diem_ket_ca, ghi_chu, oee_ca, availability_ca, performance_ca, quality_ca, tong_ng_ca,
    tong_shot_nong_khuon_ca, comment_truong_ca, nv_ca_bao_cao
  ) values (
    v_id_bao_cao, p_ngay, p_ca, p_phuong_an_ca, duc_iso_week(p_ngay), coalesce(p_truong_ca, p_user),
    v_so_may_co_kh, v_so_may_hoan_thanh, v_tong_kh, v_tong_tt, case when v_tong_kh > 0 then v_tong_tt / v_tong_kh else 0 end,
    v_so_su_co_ca, v_tong_phut_resolved + v_tong_phut_open, null, v_now,
    trim(both ' ' from (case when v_so_su_co_dang_do > 0 then v_so_su_co_dang_do || ' sự cố dang dở → ca sau' else '' end)
      || case when jsonb_array_length(v_tem_mo_coi) > 0 then ' ' || jsonb_array_length(v_tem_mo_coi) || ' tem in khác mã KH của máy (không cộng sản lượng ca)' else '' end),
    v_oee_ca, v_avail_ca, v_perf_ca, v_quality_ca, v_sum_ng, v_tong_shot_nong, coalesce(p_comment_truong_ca, ''), array_to_string(v_personnel, ', ')
  )
  on conflict (id_bao_cao) do update set
    truong_ca = excluded.truong_ca, so_may_co_kh = excluded.so_may_co_kh, so_may_hoan_thanh_kh = excluded.so_may_hoan_thanh_kh,
    tong_kh_ca = excluded.tong_kh_ca, tong_tt_ca = excluded.tong_tt_ca, ty_le_hoan_thanh_ca = excluded.ty_le_hoan_thanh_ca,
    so_su_co_ca = excluded.so_su_co_ca, tong_phut_dung_ca = excluded.tong_phut_dung_ca,
    thoi_diem_ket_ca = excluded.thoi_diem_ket_ca, ghi_chu = excluded.ghi_chu, oee_ca = excluded.oee_ca,
    availability_ca = excluded.availability_ca, performance_ca = excluded.performance_ca, quality_ca = excluded.quality_ca,
    tong_ng_ca = excluded.tong_ng_ca, tong_shot_nong_khuon_ca = excluded.tong_shot_nong_khuon_ca,
    comment_truong_ca = excluded.comment_truong_ca, nv_ca_bao_cao = excluded.nv_ca_bao_cao;

  insert into duc_lich_su_san_xuat (ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, kh_ca, tt_ca, so_luong_ng, thoi_diem_ghi)
  select p_ngay, p_ca, p_phuong_an_ca, duc_iso_week(p_ngay), ma_may, ma_sp, ten_sp, coalesce(kh_ca, 0), coalesce(tt_ca, 0), coalesce(so_luong_ng, 0), v_now
  from (select distinct on (ma_may, ma_sp) * from duc_ca_hien_tai
        where ngay = p_ngay and ca = p_ca and ma_sp is not null and ma_sp <> '' and kh_ca is not null order by ma_may, ma_sp, row_seq desc) dedup
  on conflict (ngay, ca, ma_may, ma_sp) do update set
    kh_ca = excluded.kh_ca, tt_ca = excluded.tt_ca, so_luong_ng = excluded.so_luong_ng, thoi_diem_ghi = excluded.thoi_diem_ghi;
  get diagnostics v_history_count = row_count;

  begin
    v_mold_result := duc_update_mold_shots_from_shift(p_ngay, p_ca);
  exception when others then
    v_mold_result := jsonb_build_object('updated', 0, 'warnings', jsonb_build_array('Lỗi cập nhật khuôn: ' || sqlerrm));
  end;

  v_carry_result := duc_carry_over_shift(p_ngay, p_ca, p_phuong_an_ca, p_carry_over_list);
  delete from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca;

  return jsonb_build_object(
    'ok', true, 'id_bao_cao', v_id_bao_cao,
    'summary', jsonb_build_object(
      'so_may_co_kh', v_so_may_co_kh, 'so_may_hoan_thanh_kh', v_so_may_hoan_thanh, 'tong_kh_ca', v_tong_kh, 'tong_tt_ca', v_tong_tt,
      'so_su_co_ca', v_so_su_co_ca, 'so_su_co_dang_do', v_so_su_co_dang_do, 'tong_phut_dung_ca', v_tong_phut_resolved + v_tong_phut_open,
      'oee_ca', v_oee_ca, 'availability_ca', v_avail_ca, 'performance_ca', v_perf_ca, 'quality_ca', v_quality_ca,
      'tong_ng_ca', v_sum_ng, 'tong_shot_nong_khuon_ca', v_tong_shot_nong, 'nv_ca_bao_cao', array_to_string(v_personnel, ', ')),
    'oee_rows', v_oee_rows, 'mold_update', v_mold_result, 'carry_over', v_carry_result, 'history_rows', v_history_count,
    'tem_mo_coi', v_tem_mo_coi);
end;
$function$;

-- ── R10 / R11: tem đang dùng ở công đoạn sau ─────────────────────────────────
create or replace function public.duc_tem_dang_dung(p_tag_no text) returns text
language sql stable security definer set search_path = public as $$
  select string_agg(x, '; ') from (
    select 'phiếu chuyển công đoạn ' || id_phieu || ' (' || cong_doan_giao || ' → ' || cong_doan_nhan || ')' x
      from cd_chuyen_cong_doan_log where tag_no = p_tag_no and coalesce(trang_thai_xac_nhan, '') <> 'Đã từ chối'
    union all select 'khai nguồn Bavia ' || ten_line from bavia_line_nguon where tag_no = p_tag_no and bo_luc is null
    union all select 'đã lấy ' || sum(so_luong_lay) || ' pcs sang tem ' || string_agg(tag_no_moi, ', ') from cd_tem_nguon where tag_no_nguon = p_tag_no having count(*) > 0
    union all select 'xử lý Bavia (' || count(*) || ' lần)' from bavia_xu_ly_nguon where tag_no_nguon = p_tag_no having count(*) > 0
    union all select 'Gia công máy ' || ma_may || ' bước ' || buoc from gc_tem_buoc where tag_no = p_tag_no and bo_luc is null
    union all select 'phiếu xuất kho ' || id_phieu from kho_phieu_xuat_item where ma = p_tag_no
    union all select 'pallet ' || id_pallet from oqc_pallet_item where tag_no = p_tag_no
    union all select 'khai NG ' || cong_doan || ' ' || sum(so_luong) || ' pcs' from cd_ng_khai_bao where tag_no = p_tag_no group by cong_doan
    union all select 'cách ly NCP ' || id_ncp from duc_tem_cach_ly where tag_no = p_tag_no and coalesce(trang_thai, '') <> 'da_giai_toa'
  ) q;
$$;
revoke all on function public.duc_tem_dang_dung(text) from public, anon;
grant execute on function public.duc_tem_dang_dung(text) to authenticated;

create or replace function public.duc_tem_sua(p_tag_no text, p_data jsonb, p_ly_do text)
 returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_old duc_tem; v_admin boolean := has_role('admin'); v_ly text := trim(coalesce(p_ly_do, ''));
  v_ma text; v_may text; v_sl numeric; v_moc timestamptz; v_gn timestamptz; v_ket_cu jsonb; v_ket_moi jsonb;
  v_da_dung numeric; v_sl_con numeric; v_dung text;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if length(v_ly) < 3 then return jsonb_build_object('ok', false, 'error', 'Nhập lý do sửa tem'); end if;
  select * into v_old from duc_tem where lower(tag_no) = lower(trim(coalesce(p_tag_no, ''))) for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || coalesce(p_tag_no, '')); end if;

  v_ma  := case when p_data ? 'ma_sp' then trim(coalesce(p_data->>'ma_sp', '')) else v_old.ma_sp end;
  v_may := case when p_data ? 'may_duc_chi_thi' then trim(coalesce(p_data->>'may_duc_chi_thi', '')) else v_old.may_tt end;
  v_sl  := case when p_data ? 'so_luong' then nullif(p_data->>'so_luong', '')::numeric else v_old.so_luong_tt end;
  v_gn  := case when p_data ? 'ngay_gio_ghi_nhan' then nullif(p_data->>'ngay_gio_ghi_nhan', '')::timestamptz else v_old.ngay_gio_ghi_nhan end;
  if coalesce(v_ma, '') = '' then return jsonb_build_object('ok', false, 'error', 'Chọn Mã sản phẩm'); end if;
  if coalesce(v_may, '') = '' and v_old.may_tt is not null then return jsonb_build_object('ok', false, 'error', 'Chọn Máy đúc'); end if;
  if v_sl is null or v_sl <= 0 then return jsonb_build_object('ok', false, 'error', 'Số lượng phải > 0'); end if;
  if v_gn > now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Ngày giờ SX thực tế không được ở tương lai'); end if;
  v_moc := coalesce(v_gn, v_old.ngay_gio_in);

  -- T243 (R10): phần đã tiêu thụ ở công đoạn sau giữ nguyên; đổi mã SP / SL khi tem đã dùng → chặn
  v_da_dung := greatest(0, coalesce(v_old.so_luong_tt, v_old.so_luong, 0) - coalesce(v_old.so_luong, 0));
  if (v_ma is distinct from v_old.ma_sp or v_sl is distinct from v_old.so_luong_tt) then
    v_dung := duc_tem_dang_dung(v_old.tag_no);
    if v_dung is not null then
      return jsonb_build_object('ok', false, 'error', 'Tem ' || v_old.tag_no || ' đã dùng ở công đoạn sau (' || v_dung
        || ') — không đổi được mã SP / số lượng. Chỉ sửa được ghi chú, người thao tác, giờ SX.');
    end if;
  end if;
  v_sl_con := v_sl - v_da_dung;
  if v_sl_con < 0 then
    return jsonb_build_object('ok', false, 'error', 'Tem đã tiêu thụ ' || v_da_dung || ' pcs — số lượng mới phải ≥ ' || v_da_dung);
  end if;

  v_ket_cu := duc_tem_ca_da_ket(v_old.may_tt, v_old.ma_sp, coalesce(v_old.ngay_gio_ghi_nhan, v_old.ngay_gio_in));
  v_ket_moi := duc_tem_ca_da_ket(nullif(v_may, ''), v_ma, v_moc);
  if (v_ket_cu is not null or v_ket_moi is not null) and not v_admin then
    return jsonb_build_object('ok', false, 'error',
      'Tem thuộc ' || (select coalesce(k->>'ca', '') || ' ' || to_char((k->>'ngay')::date, 'DD/MM/YYYY') from (select coalesce(v_ket_cu, v_ket_moi) k) x)
      || ' đã kết ca — chỉ admin được sửa.');
  end if;

  perform set_config('mes.tem_hanh_dong', 'sua', true);
  perform set_config('mes.tem_ly_do', v_ly, true);
  perform set_config('mes.tem_ca_da_ket', coalesce(coalesce(v_ket_cu, v_ket_moi)::text, ''), true);
  update duc_tem set
    ten_sp = case when p_data ? 'ten_sp' then p_data->>'ten_sp' else ten_sp end,
    ma_sp = v_ma,
    so_luong = v_sl_con, so_luong_tt = v_sl,
    lot = case when p_data ? 'lot' then p_data->>'lot' else lot end,
    so_khuon = case when p_data ? 'so_khuon' then p_data->>'so_khuon' else so_khuon end,
    so_khuon_tt = case when p_data ? 'so_khuon' then p_data->>'so_khuon' else so_khuon_tt end,
    nguyen_lieu = case when p_data ? 'nguyen_lieu' then p_data->>'nguyen_lieu' else nguyen_lieu end,
    may_duc_chi_thi = case when p_data ? 'may_duc_chi_thi' then nullif(v_may, '') else may_duc_chi_thi end,
    may_tt = case when p_data ? 'may_duc_chi_thi' then nullif(v_may, '') else may_tt end,
    ghi_chu = case when p_data ? 'ghi_chu' then p_data->>'ghi_chu' else ghi_chu end,
    nguoi_tt = case when p_data ? 'nguoi_tt' then p_data->>'nguoi_tt' else nguoi_tt end,
    ngay_gio_ghi_nhan = v_gn
  where tag_no = v_old.tag_no;
  perform set_config('mes.tem_hanh_dong', '', true);
  perform set_config('mes.tem_ly_do', '', true);
  perform set_config('mes.tem_ca_da_ket', '', true);
  return jsonb_build_object('ok', true, 'tag_no', v_old.tag_no, 'ca_da_ket', coalesce(v_ket_cu, v_ket_moi), 'da_dung', v_da_dung);
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
  return jsonb_build_object('ok', false, 'error', 'Dữ liệu không hợp lệ: ' || sqlerrm);
end $function$;

create or replace function public.duc_tem_xoa(p_tag_no text, p_ly_do text)
 returns jsonb language plpgsql security definer set search_path = public as $function$
declare v_old duc_tem; v_ly text := trim(coalesce(p_ly_do, '')); v_ket jsonb; v_con text; v_cha duc_tem_tach; v_bang text; v_dung text;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if length(v_ly) < 3 then return jsonb_build_object('ok', false, 'error', 'Nhập lý do xoá tem'); end if;
  select * into v_old from duc_tem where lower(tag_no) = lower(trim(coalesce(p_tag_no, ''))) for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || coalesce(p_tag_no, '')); end if;

  select string_agg(tag_no_con || ' (' || so_luong_con || ' pcs)', ', ' order by thoi_diem) into v_con from duc_tem_tach where tag_no_cha = v_old.tag_no;
  if v_con is not null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_old.tag_no || ' đã tách ra tem con: ' || v_con ||
      '. Mở từng tem con, bấm "Hoàn tác tách" (cộng trả số lượng về tem này) rồi mới xoá được tem này.');
  end if;
  select * into v_cha from duc_tem_tach where tag_no_con = v_old.tag_no;
  if found then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_old.tag_no || ' được tách từ tem ' || v_cha.tag_no_cha ||
      ' — không xoá thẳng. Bấm nút "Hoàn tác tách" để xoá tem này và cộng trả ' || v_cha.so_luong_con || ' pcs về tem ' || v_cha.tag_no_cha || '.');
  end if;
  -- T243 (R11): tem đã đi công đoạn sau → không xoá (kể cả admin)
  v_dung := duc_tem_dang_dung(v_old.tag_no);
  if v_dung is not null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_old.tag_no || ' đã dùng ở công đoạn sau (' || v_dung
      || ') — không xoá được. Gỡ tem khỏi chỗ đó trước (Bỏ ở Bavia / Gia công, từ chối phiếu chuyển…).');
  end if;

  v_ket := duc_tem_ca_da_ket(v_old.may_tt, v_old.ma_sp, coalesce(v_old.ngay_gio_ghi_nhan, v_old.ngay_gio_in));
  if v_ket is not null and not has_role('admin') then
    return jsonb_build_object('ok', false, 'error',
      'Tem thuộc ' || coalesce(v_ket->>'ca', '') || ' ' || to_char((v_ket->>'ngay')::date, 'DD/MM/YYYY') || ' đã kết ca — chỉ admin được xoá.');
  end if;
  perform set_config('mes.tem_hanh_dong', 'xoa', true);
  perform set_config('mes.tem_ly_do', v_ly, true);
  perform set_config('mes.tem_ca_da_ket', coalesce(v_ket::text, ''), true);
  begin
    delete from duc_tem where tag_no = v_old.tag_no;
  exception when foreign_key_violation then
    get stacked diagnostics v_bang = table_name;
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_old.tag_no || ' đang được dùng ở nơi khác (' || coalesce(v_bang, '?') ||
      ') — không xoá được. Gỡ tem khỏi chỗ đó trước hoặc báo admin.');
  end;
  perform set_config('mes.tem_hanh_dong', '', true);
  perform set_config('mes.tem_ly_do', '', true);
  perform set_config('mes.tem_ca_da_ket', '', true);
  return jsonb_build_object('ok', true, 'tag_no', v_old.tag_no, 'ca_da_ket', v_ket);
end $function$;

-- ── R12: Gia công chỉ nhận tem từ công đoạn liền trước ─────────────────────
create or replace function public.gc_quet(p_id_tram text, p_tag text)
 returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_tram cd_tram_hien_tai%rowtype; v_tem duc_tem%rowtype; v_tag text := upper(trim(coalesce(p_tag, '')));
  v_steps text[]; v_i int; v_j int; v_loc text; v_loai text; v_route record; v_tong int; v_buoc int; v_khac record; v_xong record;
  v_line_bavia text; v_id bigint; v_user text := duc_su_co_nguoi_hien_tai(); v_now timestamptz := now();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if v_tag = '' then return jsonb_build_object('ok', false, 'error', 'Chưa có mã quét'); end if;
  select * into v_tram from cd_tram_hien_tai where id_tram = p_id_tram and cong_doan = 'Gia Công';
  if not found then return jsonb_build_object('ok', false, 'error', 'Máy chưa được mở trong ca này'); end if;
  if gc_ca_da_ket(v_tram.ngay, v_tram.ca) then return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không ghi thêm được'); end if;

  select * into v_tem from duc_tem where tag_no = v_tag for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || v_tag); end if;
  if v_tem.ma_sp is distinct from v_tram.ma_sp then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' là mã ' || coalesce(v_tem.ma_sp, '?') || ', ' || v_tram.ten_tram || ' đang chạy mã ' || v_tram.ma_sp);
  end if;
  if duc_tem_id_ncp_cach_ly(v_tem.tag_no) is not null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang bị cách ly theo phiếu NCP ' || duc_tem_id_ncp_cach_ly(v_tem.tag_no) || '. Báo QC.');
  end if;
  if coalesce(v_tem.trang_thai, '') in ('Chờ sản xuất', 'NG chờ sửa', 'Chờ đóng gói TP') then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang ở trạng thái "' || v_tem.trang_thai || '", chưa dùng cho Gia công được');
  end if;
  if coalesce(v_tem.so_luong, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' không còn số lượng (đã dùng hết / NG hết)');
  end if;
  select ten_line into v_line_bavia from bavia_line_nguon where tag_no = v_tem.tag_no and bo_luc is null;
  if v_line_bavia is not null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang khai báo nguồn ở Bavia ' || v_line_bavia || '. Bavia bấm Bỏ trước.');
  end if;
  select ma_may into v_khac from gc_tem_buoc where tag_no = v_tem.tag_no and xong_luc is null and bo_luc is null;
  if found then
    if v_khac.ma_may = v_tram.ten_tram then
      return jsonb_build_object('ok', false, 'trung', true, 'error', 'Tem ' || v_tem.tag_no || ' đã quét ở ' || v_khac.ma_may);
    end if;
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang làm ở ' || v_khac.ma_may || '. Bấm Xong hoặc Bỏ ở ' || v_khac.ma_may || ' trước.');
  end if;

  v_loai := gc_loai_may(v_tram.ten_tram);
  select count(*) into v_tong from master_cnc_routing where ma_sp = v_tram.ma_sp;
  v_tong := greatest(v_tong, 1);
  select max(buoc) mb, max(xong_luc) xl, (array_agg(ma_may order by xong_luc desc))[1] mm into v_xong
  from gc_tem_buoc where tag_no = v_tem.tag_no and bo_luc is null and xong_luc is not null;
  v_buoc := coalesce(v_xong.mb, 0) + 1;
  if v_buoc > v_tong then
    return jsonb_build_object('ok', false, 'error', 'Thùng ' || v_tem.tag_no || ' đã gia công xong (' || v_tong || '/' || v_tong || ' bước, lần cuối ở ' || coalesce(v_xong.mm, '?') || ' lúc '
      || coalesce(to_char(v_xong.xl at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'), '?') || ')');
  end if;
  select * into v_route from master_cnc_routing where ma_sp = v_tram.ma_sp order by buoc offset v_buoc - 1 limit 1;
  if found and not (v_route.loai_may = v_loai or (v_route.loai_may = 'phay_3_truc' and v_loai = 'phay_4_truc')) then
    return jsonb_build_object('ok', false, 'error', 'Thùng ' || v_tem.tag_no || ' đang chờ bước ' || v_buoc || '/' || v_tong || ': ' || gc_ten_loai_may(v_route.loai_may) || '. ' || v_tram.ten_tram || ' là máy ' || gc_ten_loai_may(v_loai) || '.');
  end if;

  select array_agg(trim(s) order by ord) into v_steps
  from unnest(string_to_array(coalesce((select quy_trinh_cong_doan from master_products where ma_sp = v_tem.ma_sp), ''), ',')) with ordinality as u(s, ord)
  where trim(s) <> '';
  v_i := array_position(v_steps, 'Gia Công');
  select cong_doan_nhan into v_loc from cd_chuyen_cong_doan_log
  where tag_no = v_tem.tag_no and coalesce(trang_thai_xac_nhan, '') <> 'Đã từ chối' order by thoi_gian_chuyen desc limit 1;
  v_loc := coalesce(v_loc, case when v_tem.tag_no like 'TP%' then coalesce(nullif(v_tem.tram_cong_doan, ''), 'Đúc') else 'Đúc' end);
  v_j := array_position(v_steps, v_loc);
  if v_loc <> 'Gia Công' then
    -- T243 (R12): chỉ nhận từ công đoạn LIỀN TRƯỚC, không đi tắt (VD Đúc → Gia công bỏ qua Bavia)
    if v_i is null or v_j is null or v_j <> v_i - 1 then
      return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang ở công đoạn ' || v_loc
        || case when v_i is not null and v_i > 1 then ' — phải qua ' || v_steps[v_i - 1] || ' trước rồi mới tới Gia Công' else '' end
        || ' (lưu trình: ' || array_to_string(v_steps, ' → ') || ')');
    end if;
    insert into cd_chuyen_cong_doan_log (id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech, lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc,
      cong_doan_giao, cong_doan_nhan, nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan, ghi_chu)
    values (cd_next_transfer_id(), v_now, v_tem.tag_no, v_tem.ma_sp, v_tem.ten_sp, v_tem.so_luong, v_tem.so_luong, 0, coalesce(v_tem.lot, ''),
      coalesce(v_tem.so_khuon_tt, v_tem.so_khuon, ''), coalesce(v_tem.nguyen_lieu, ''), coalesce(v_tem.may_tt, v_tem.may_duc_chi_thi, ''), coalesce(v_tem.ngay::text, ''),
      v_loc, 'Gia Công', 'Tự nhận tại ' || v_tram.ten_tram, v_user, 'Đã xác nhận chuyển công đoạn',
      to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI:SS DD/MM/YYYY'), 'Quét tem ở Bảng điều khiển Gia công');
  end if;

  insert into gc_tem_buoc (tag_no, ma_sp, ma_may, loai_may, buoc, tong_buoc, id_tram, sl_vao, nguoi_quet)
  values (v_tem.tag_no, v_tem.ma_sp, v_tram.ten_tram, v_loai, v_buoc, v_tong, v_tram.id_tram, v_tem.so_luong, v_user)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'tag_no', v_tem.tag_no, 'so_luong', v_tem.so_luong, 'buoc', v_buoc, 'tong_buoc', v_tong, 'tu_nhan', v_loc <> 'Gia Công', 'tu_cong_doan', v_loc);
end $function$;

notify pgrst, 'reload schema';
