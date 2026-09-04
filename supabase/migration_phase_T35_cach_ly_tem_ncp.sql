-- ============================================================================
-- T35 — Cách ly tem/thùng hàng gắn với phiếu NCP (SP không phù hợp).
--
-- Trước đây `duc_ncp` chỉ gắn với (ma_may, ma_sp, id_checkpoint_goc) và số
-- lượng nghi vấn dạng số — KHÔNG gắn với tem/thùng cụ thể nào. Nay QC có thể
-- quét QR từng tem thuộc diện nghi vấn ngay trong phiếu NCP (ncp-detail.html)
-- để đưa vào "khu cách ly" — hệ thống chặn không cho các tem đó:
--   1. Chuyển công đoạn (cd_ghi_chuyen_cong_doan)
--   2. Đóng gói lại / dùng làm nguyên liệu đầu vào (cd_dong_goi_lai)
--   3. Nhập kho / thêm vào phiếu xuất hàng (kho_nhap_kho_tem, kho_them_vao_phieu_xuat)
--
-- Quyết định vận hành (chốt qua AskUserQuestion trong phiên):
--   - TÁCH tem (duc_tach_tem) một tem đang cách ly VẪN được phép (QC cần tách
--     để lọc/sub-sample) — tem con tự động KẾ THỪA cách ly theo cùng phiếu NCP.
--   - Giải toả cách ly PHẢI thao tác riêng từng tem (duc_ncp_giai_toa_tem) —
--     đóng phiếu NCP KHÔNG tự giải toả, tránh giải toả nhầm hàng chưa xử lý
--     xong thực tế.
--   - Xuất kho cũng bị chặn như chuyển công đoạn/đóng gói lại.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ── 1) Bảng cách ly ─────────────────────────────────────────────────────────
create table if not exists duc_tem_cach_ly (
  id                  bigserial primary key,
  tag_no              text not null references duc_tem (tag_no),
  id_ncp              text not null references duc_ncp (id_ncp),
  trang_thai          text not null default 'dang_cach_ly' check (trang_thai in ('dang_cach_ly', 'da_giai_toa')),
  nguoi_cach_ly       text,
  thoi_diem_cach_ly   timestamptz not null default now(),
  nguoi_giai_toa      text,
  thoi_diem_giai_toa  timestamptz
);
-- Tại 1 thời điểm, 1 tem chỉ có tối đa 1 dòng cách ly đang mở.
create unique index if not exists ux_tem_cach_ly_active on duc_tem_cach_ly (tag_no) where trang_thai = 'dang_cach_ly';
create index if not exists idx_tem_cach_ly_ncp on duc_tem_cach_ly (id_ncp);

-- ── 2) Helper đọc công khai — id_ncp đang cách ly tem này (null nếu không) ──
create or replace function duc_tem_id_ncp_cach_ly(p_tag_no text)
returns text
language sql
stable
as $$
  select id_ncp from duc_tem_cach_ly where tag_no = p_tag_no and trang_thai = 'dang_cach_ly' limit 1;
$$;

-- ── 3) Cách ly 1 tem theo phiếu NCP ──────────────────────────────────────────
create or replace function duc_ncp_cach_ly_tem(p_id_ncp text, p_tag_no text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_active_ncp text;
begin
  if p_tag_no is null or trim(p_tag_no) = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã tem'); end if;
  if not exists (select 1 from duc_ncp where id_ncp = p_id_ncp) then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu: ' || p_id_ncp);
  end if;
  if not exists (select 1 from duc_tem where tag_no = p_tag_no) then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem: ' || p_tag_no);
  end if;

  select id_ncp into v_active_ncp from duc_tem_cach_ly where tag_no = p_tag_no and trang_thai = 'dang_cach_ly';
  if v_active_ncp is not null then
    if v_active_ncp = p_id_ncp then
      return jsonb_build_object('ok', false, 'error', 'Tem này đã cách ly theo đúng phiếu này rồi');
    end if;
    return jsonb_build_object('ok', false, 'error', 'Tem đang bị cách ly theo phiếu khác (' || v_active_ncp || ')');
  end if;

  insert into duc_tem_cach_ly (tag_no, id_ncp, trang_thai, nguoi_cach_ly, thoi_diem_cach_ly)
  values (p_tag_no, p_id_ncp, 'dang_cach_ly', p_user, now());

  perform duc_ncp_append_log(p_id_ncp, 'Cách ly tem ' || p_tag_no || ' — bởi ' || p_user);

  return jsonb_build_object('ok', true, 'tag_no', p_tag_no);
end;
$$;
revoke execute on function duc_ncp_cach_ly_tem(text, text, text) from anon;
grant execute on function duc_ncp_cach_ly_tem(text, text, text) to authenticated;

-- ── 4) Giải toả cách ly 1 tem (phải đúng phiếu đã cách ly nó) ───────────────
create or replace function duc_ncp_giai_toa_tem(p_id_ncp text, p_tag_no text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_updated int;
begin
  update duc_tem_cach_ly set trang_thai = 'da_giai_toa', nguoi_giai_toa = p_user, thoi_diem_giai_toa = now()
  where tag_no = p_tag_no and id_ncp = p_id_ncp and trang_thai = 'dang_cach_ly';
  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy cách ly đang mở cho tem ' || p_tag_no || ' theo phiếu này');
  end if;

  perform duc_ncp_append_log(p_id_ncp, 'Giải toả cách ly tem ' || p_tag_no || ' — bởi ' || p_user);

  return jsonb_build_object('ok', true, 'tag_no', p_tag_no);
end;
$$;
revoke execute on function duc_ncp_giai_toa_tem(text, text, text) from anon;
grant execute on function duc_ncp_giai_toa_tem(text, text, text) to authenticated;

-- ── 5) Chặn CHUYỂN CÔNG ĐOẠN với tem đang cách ly ────────────────────────────
create or replace function cd_ghi_chuyen_cong_doan(
  p_tag_no text, p_ma_sp text, p_ten_sp text,
  p_sl_tren_tem numeric, p_sl_thuc_chuyen numeric,
  p_lot_no text, p_so_khuon text, p_nguyen_lieu text, p_may_duc text, p_ngay_duc text,
  p_cong_doan_giao text, p_cong_doan_nhan text,
  p_nguoi_giao text, p_nguoi_nhan text,
  p_ghi_chu text default null
)
returns table(id_phieu text, thoi_gian_chuyen timestamptz, chenh_lech numeric)
language plpgsql
security definer
as $$
declare
  v_id text := cd_next_transfer_id();
  v_now timestamptz := now();
  v_chenh_lech numeric := p_sl_tren_tem - p_sl_thuc_chuyen;
  v_id_ncp_cl text := duc_tem_id_ncp_cach_ly(p_tag_no);
begin
  if v_id_ncp_cl is not null then
    raise exception 'Tem % đang bị cách ly theo phiếu NCP % — không thể chuyển công đoạn', p_tag_no, v_id_ncp_cl;
  end if;

  insert into cd_chuyen_cong_doan_log (
    id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp,
    sl_tren_tem, sl_thuc_chuyen, chenh_lech,
    lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc,
    cong_doan_giao, cong_doan_nhan, nguoi_giao, nguoi_nhan,
    ghi_chu, trang_thai_xac_nhan
  ) values (
    v_id, v_now, p_tag_no, p_ma_sp, p_ten_sp,
    p_sl_tren_tem, p_sl_thuc_chuyen, v_chenh_lech,
    p_lot_no, p_so_khuon, p_nguyen_lieu, p_may_duc, p_ngay_duc,
    p_cong_doan_giao, p_cong_doan_nhan, p_nguoi_giao, p_nguoi_nhan,
    nullif(trim(p_ghi_chu), ''), 'Chờ công đoạn trước xác nhận'
  );
  return query select v_id, v_now, v_chenh_lech;
end;
$$;
revoke execute on function cd_ghi_chuyen_cong_doan(
  text, text, text, numeric, numeric, text, text, text, text, text, text, text, text, text, text
) from anon;
grant execute on function cd_ghi_chuyen_cong_doan(
  text, text, text, numeric, numeric, text, text, text, text, text, text, text, text, text, text
) to authenticated;

-- ── 6) TÁCH TEM: cho phép tách tem đang cách ly, tem con KẾ THỪA cách ly ────
create or replace function duc_tach_tem(
  p_tag_no_cha text, p_so_luong_tach numeric, p_ly_do text, p_nguoi text
)
returns text
language plpgsql
security definer
as $$
declare
  v_cha       duc_tem%rowtype;
  v_so_con    int;
  v_letter    text;
  v_tag_con   text;
begin
  select * into v_cha from duc_tem where tag_no = p_tag_no_cha for update;
  if not found then
    raise exception 'Không tìm thấy tem %', p_tag_no_cha;
  end if;
  if p_so_luong_tach is null or p_so_luong_tach <= 0 then
    raise exception 'Số lượng tách phải lớn hơn 0';
  end if;
  if v_cha.so_luong is not null and p_so_luong_tach > v_cha.so_luong then
    raise exception 'Số lượng tách (%) vượt quá số lượng còn lại trên tem cha (%)', p_so_luong_tach, v_cha.so_luong;
  end if;

  select count(*) into v_so_con from duc_tem_tach where tag_no_cha = p_tag_no_cha;
  if v_so_con >= 26 then
    raise exception 'Tem % đã tách quá 26 lần, không tự sinh thêm hậu tố được', p_tag_no_cha;
  end if;
  v_letter := chr(65 + v_so_con); -- A, B, C, ...
  v_tag_con := p_tag_no_cha || '-' || v_letter;

  insert into duc_tem (
    tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
    may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
    nguoi_tt, trang_thai, ghi_chu_sl
  ) values (
    v_tag_con, v_cha.ten_sp, v_cha.ma_sp, p_so_luong_tach, v_cha.ngay, v_cha.lot, v_cha.so_khuon, v_cha.nguyen_lieu,
    v_cha.may_duc_chi_thi, v_cha.ghi_chu, now(), v_cha.so_khuon_tt, p_so_luong_tach, v_cha.may_tt,
    p_nguoi, v_cha.trang_thai, 'Tách từ ' || p_tag_no_cha
  );

  update duc_tem set so_luong = so_luong - p_so_luong_tach where tag_no = p_tag_no_cha;

  insert into duc_tem_tach (tag_no_cha, tag_no_con, so_luong_con, ly_do, nguoi_thao_tac)
  values (p_tag_no_cha, v_tag_con, p_so_luong_tach, p_ly_do, p_nguoi);

  insert into duc_tem_nvl_lot (tag_no, nvl_tag_no, nguoi_gan)
  select v_tag_con, nvl_tag_no, p_nguoi from duc_tem_nvl_lot where tag_no = p_tag_no_cha;

  -- Kế thừa cách ly: nếu tem cha đang bị cách ly (theo phiếu NCP nào đó), tem
  -- con vừa tách ra cũng bị cách ly ngay theo đúng phiếu đó.
  insert into duc_tem_cach_ly (tag_no, id_ncp, trang_thai, nguoi_cach_ly, thoi_diem_cach_ly)
  select v_tag_con, id_ncp, 'dang_cach_ly', 'he_thong (kế thừa từ ' || p_tag_no_cha || ')', now()
  from duc_tem_cach_ly where tag_no = p_tag_no_cha and trang_thai = 'dang_cach_ly';

  return v_tag_con;
end;
$$;
revoke execute on function duc_tach_tem(text, numeric, text, text) from anon;
grant execute on function duc_tach_tem(text, numeric, text, text) to authenticated;

-- ── 7) Chặn ĐÓNG GÓI LẠI (dùng tem cách ly làm nguyên liệu đầu vào) ─────────
create or replace function cd_dong_goi_lai(
  p_cong_doan text, p_tag_no_nguon text[], p_so_luong_moi numeric[],
  p_id_tram text, p_tram text, p_nguoi_thao_tac text, p_thoi_diem_sx timestamptz,
  p_ng_hao_hut numeric, p_ngay date, p_ca text,
  p_nguoi text
)
returns table(tag_no_moi text, so_luong numeric, ma_sp text, ten_sp text, ngay date, lot text, so_khuon text, nguyen_lieu text, may_duc text)
language plpgsql
security definer
as $$
declare
  v_src duc_tem%rowtype;
  v_ma_sp text;
  v_ten_sp text;
  v_ngay_moi date;
  v_lot_moi text[] := array[]::text[];
  v_so_khuon_moi text[] := array[]::text[];
  v_nl_moi text[] := array[]::text[];
  v_may_moi text[] := array[]::text[];
  v_remaining numeric[];
  v_total_available numeric := 0;
  v_total_requested numeric := 0;
  v_n_src int;
  v_n_out int;
  i int;
  j int;
  v_need numeric;
  v_take numeric;
  v_new_tag text;
  v_now timestamptz := now();
  v_sx_time timestamptz := coalesce(p_thoi_diem_sx, now());
  v_ng numeric := coalesce(p_ng_hao_hut, 0);
  v_tram_ten text;
  v_id_ncp_cl text;
begin
  if p_cong_doan is null or trim(p_cong_doan) = '' then
    raise exception 'Thiếu công đoạn';
  end if;
  if p_tag_no_nguon is null or array_length(p_tag_no_nguon, 1) is null then
    raise exception 'Chưa quét tem nguồn nào';
  end if;
  if (p_so_luong_moi is null or array_length(p_so_luong_moi, 1) is null) and v_ng <= 0 then
    raise exception 'Chưa nhập đơn vị đóng gói mới nào (hoặc NG hao hụt)';
  end if;
  if (select count(*) from unnest(p_tag_no_nguon) t) <> (select count(distinct t) from unnest(p_tag_no_nguon) t) then
    raise exception 'Có tem nguồn bị quét trùng lặp';
  end if;

  -- Trạm gắn sẵn (nếu có) — lấy tên trạm thật để lưu lên tem cho dễ đọc, và
  -- để biết chắc trạm đó cùng công đoạn (tránh gán nhầm trạm công đoạn khác).
  if p_id_tram is not null and trim(p_id_tram) <> '' then
    select ten_tram into v_tram_ten from cd_tram_hien_tai where id_tram = p_id_tram;
    if not found then raise exception 'Không tìm thấy trạm: %', p_id_tram; end if;
  else
    v_tram_ten := nullif(trim(coalesce(p_tram, '')), '');
  end if;

  v_n_src := array_length(p_tag_no_nguon, 1);
  v_n_out := coalesce(array_length(p_so_luong_moi, 1), 0);
  v_remaining := array_fill(0::numeric, array[v_n_src]);

  for i in 1 .. v_n_src loop
    select * into v_src from duc_tem where tag_no = p_tag_no_nguon[i] for update;
    if not found then
      raise exception 'Không tìm thấy tem %', p_tag_no_nguon[i];
    end if;
    if coalesce(v_src.so_luong, 0) <= 0 then
      raise exception 'Tem % đã hết số lượng, không dùng làm nguồn được', p_tag_no_nguon[i];
    end if;
    v_id_ncp_cl := duc_tem_id_ncp_cach_ly(p_tag_no_nguon[i]);
    if v_id_ncp_cl is not null then
      raise exception 'Tem % đang bị cách ly theo phiếu NCP % — không thể dùng để đóng gói lại', p_tag_no_nguon[i], v_id_ncp_cl;
    end if;

    if v_ma_sp is null then
      v_ma_sp := v_src.ma_sp; v_ten_sp := v_src.ten_sp;
    elsif v_ma_sp <> v_src.ma_sp then
      raise exception 'Các tem nguồn không cùng mã SP (% và %)', v_ma_sp, v_src.ma_sp;
    end if;

    if v_ngay_moi is null or (v_src.ngay is not null and v_src.ngay < v_ngay_moi) then
      v_ngay_moi := v_src.ngay;
    end if;
    if v_src.lot is not null and v_src.lot <> '' and not (v_src.lot = any(v_lot_moi)) then v_lot_moi := array_append(v_lot_moi, v_src.lot); end if;
    if v_src.so_khuon is not null and v_src.so_khuon <> '' and not (v_src.so_khuon = any(v_so_khuon_moi)) then v_so_khuon_moi := array_append(v_so_khuon_moi, v_src.so_khuon); end if;
    if v_src.nguyen_lieu is not null and v_src.nguyen_lieu <> '' and not (v_src.nguyen_lieu = any(v_nl_moi)) then v_nl_moi := array_append(v_nl_moi, v_src.nguyen_lieu); end if;
    if v_src.may_duc_chi_thi is not null and v_src.may_duc_chi_thi <> '' and not (v_src.may_duc_chi_thi = any(v_may_moi)) then v_may_moi := array_append(v_may_moi, v_src.may_duc_chi_thi); end if;

    v_remaining[i] := v_src.so_luong;
    v_total_available := v_total_available + v_src.so_luong;
  end loop;

  for j in 1 .. v_n_out loop
    if p_so_luong_moi[j] is null or p_so_luong_moi[j] <= 0 then
      raise exception 'Số lượng đơn vị đóng gói thứ % không hợp lệ', j;
    end if;
    v_total_requested := v_total_requested + p_so_luong_moi[j];
  end loop;
  v_total_requested := v_total_requested + v_ng;

  if v_total_requested > v_total_available then
    raise exception 'Tổng số lượng đóng gói + NG (%) vượt quá tổng số lượng tem nguồn (%)', v_total_requested, v_total_available;
  end if;

  i := 1;
  for j in 1 .. v_n_out loop
    v_new_tag := cd_next_tag_no_dong_goi();

    insert into duc_tem (
      tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
      may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
      nguoi_tt, trang_thai, ghi_chu_sl, tram_cong_doan, thoi_diem_san_xuat
    ) values (
      v_new_tag, v_ten_sp, v_ma_sp, p_so_luong_moi[j], v_ngay_moi,
      array_to_string(v_lot_moi, ', '), array_to_string(v_so_khuon_moi, ', '), array_to_string(v_nl_moi, ', '),
      array_to_string(v_may_moi, ', '), 'Đóng gói lại tại ' || p_cong_doan, v_now,
      array_to_string(v_so_khuon_moi, ', '), p_so_luong_moi[j], array_to_string(v_may_moi, ', '),
      coalesce(nullif(trim(p_nguoi_thao_tac), ''), p_nguoi), 'Đóng gói lại', 'Đóng gói tại ' || p_cong_doan,
      v_tram_ten, v_sx_time
    );

    insert into cd_chuyen_cong_doan_log (
      id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
      lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan,
      nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan
    ) values (
      cd_next_transfer_id(), v_now, v_new_tag, v_ma_sp, v_ten_sp, p_so_luong_moi[j], p_so_luong_moi[j], 0,
      array_to_string(v_lot_moi, ', '), array_to_string(v_so_khuon_moi, ', '), array_to_string(v_nl_moi, ', '),
      array_to_string(v_may_moi, ', '), coalesce(v_ngay_moi::text, ''), p_cong_doan, p_cong_doan,
      p_nguoi, p_nguoi, 'Đã xác nhận chuyển công đoạn', to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
    );

    v_need := p_so_luong_moi[j];
    while v_need > 0 loop
      if i > v_n_src then raise exception 'Lỗi phân bổ số lượng nguồn cho tem % — liên hệ kỹ thuật', v_new_tag; end if;
      if v_remaining[i] > 0 then
        v_take := least(v_need, v_remaining[i]);
        v_remaining[i] := v_remaining[i] - v_take;
        v_need := v_need - v_take;
        insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay)
        values (v_new_tag, p_tag_no_nguon[i], v_take)
        on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
      end if;
      if v_remaining[i] <= 0 then i := i + 1; end if;
    end loop;

    tag_no_moi := v_new_tag; so_luong := p_so_luong_moi[j]; ma_sp := v_ma_sp; ten_sp := v_ten_sp;
    ngay := v_ngay_moi; lot := array_to_string(v_lot_moi, ', '); so_khuon := array_to_string(v_so_khuon_moi, ', ');
    nguyen_lieu := array_to_string(v_nl_moi, ', '); may_duc := array_to_string(v_may_moi, ', ');
    return next;
  end loop;

  -- NG hao hụt — trừ thẳng vào tem nguồn (KHÔNG tạo tem mới), rồi cộng vào
  -- đúng trạm nếu có (real-time), hoặc thẳng vào cd_bao_cao_ca theo ngày/ca
  -- người dùng chọn tay nếu đóng gói không gắn trạm.
  if v_ng > 0 then
    v_need := v_ng;
    while v_need > 0 loop
      if i > v_n_src then raise exception 'Lỗi phân bổ NG hao hụt — vượt quá tem nguồn còn lại'; end if;
      if v_remaining[i] > 0 then
        v_take := least(v_need, v_remaining[i]);
        v_remaining[i] := v_remaining[i] - v_take;
        v_need := v_need - v_take;
      end if;
      if v_remaining[i] <= 0 then i := i + 1; end if;
    end loop;

    if p_id_tram is not null and trim(p_id_tram) <> '' then
      perform cd_tram_nhap_sanluong(p_id_tram, 0, v_ng, 'NG phát hiện lúc đóng gói lại tem ' || array_to_string(p_tag_no_nguon, ', '), p_nguoi);
    elsif p_ngay is not null and p_ca is not null and trim(coalesce(p_ca, '')) <> '' then
      perform cd_gop_tally_vao_bao_cao(p_ngay, p_ca, p_cong_doan, v_ma_sp, v_ten_sp, coalesce(v_tram_ten, ''), 0, v_ng, 'NG phát hiện lúc đóng gói lại');
    else
      raise exception 'Có NG hao hụt nhưng chưa chọn trạm hoặc chưa chọn ngày/ca để ghi vào báo cáo';
    end if;
  end if;

  for i in 1 .. v_n_src loop
    update duc_tem set so_luong = v_remaining[i] where tag_no = p_tag_no_nguon[i];
  end loop;

  return;
end;
$$;
revoke execute on function cd_dong_goi_lai(text, text[], numeric[], text, text, text, timestamptz, numeric, date, text, text) from anon;
grant execute on function cd_dong_goi_lai(text, text[], numeric[], text, text, text, timestamptz, numeric, date, text, text) to authenticated;

-- ── 8) Chặn NHẬP KHO tem lẻ đang cách ly ─────────────────────────────────────
create or replace function kho_nhap_kho_tem(p_tag_no text, p_nguoi text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_tem duc_tem%rowtype;
  v_vitri text;
  v_now timestamptz := now();
  v_id_ncp_cl text := duc_tem_id_ncp_cach_ly(p_tag_no);
begin
  if v_id_ncp_cl is not null then
    raise exception 'Tem % đang bị cách ly theo phiếu NCP % — không thể nhập kho', p_tag_no, v_id_ncp_cl;
  end if;

  select * into v_tem from duc_tem where tag_no = p_tag_no;
  if not found then raise exception 'Không tìm thấy tem %', p_tag_no; end if;
  if coalesce(v_tem.so_luong, 0) <= 0 then raise exception 'Tem % đã hết số lượng', p_tag_no; end if;

  select vi_tri_hien_tai into v_vitri from cd_v_vi_tri_hien_tai where tag_no = p_tag_no;
  if v_vitri = 'Nhập kho' then raise exception 'Tem % đã nhập kho rồi', p_tag_no; end if;

  insert into cd_chuyen_cong_doan_log (
    id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
    cong_doan_giao, cong_doan_nhan, nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan
  ) values (
    cd_next_transfer_id(), v_now, p_tag_no, v_tem.ma_sp, v_tem.ten_sp, v_tem.so_luong, v_tem.so_luong, 0,
    coalesce(v_vitri, 'OQC'), 'Nhập kho', p_nguoi, p_nguoi, 'Đã xác nhận chuyển công đoạn',
    to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
  );

  return jsonb_build_object('ok', true, 'ma_sp', v_tem.ma_sp, 'ten_sp', v_tem.ten_sp, 'so_luong', v_tem.so_luong);
end;
$$;
revoke execute on function kho_nhap_kho_tem(text, text) from anon;
grant execute on function kho_nhap_kho_tem(text, text) to authenticated;

-- ── 9) Chặn THÊM VÀO PHIẾU XUẤT (tem lẻ trực tiếp, hoặc pallet chứa tem cách ly) ──
create or replace function kho_them_vao_phieu_xuat(p_id_phieu text, p_ma text, p_nguoi text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_loai text;
  v_sl numeric;
  v_ma_sp text;
  v_ten_sp text;
  v_trang_thai_phieu text;
  v_vi_tri text;
  v_id_ncp_cl text;
  v_tag_cach_ly text;
begin
  if p_ma is null or trim(p_ma) = '' then raise exception 'Thiếu mã quét'; end if;
  select trang_thai into v_trang_thai_phieu from kho_phieu_xuat where id_phieu = p_id_phieu;
  if not found then raise exception 'Không tìm thấy phiếu xuất %', p_id_phieu; end if;
  if v_trang_thai_phieu <> 'mo' then raise exception 'Phiếu % đã đóng, không thêm được nữa', p_id_phieu; end if;
  if exists (select 1 from kho_phieu_xuat_item where id_phieu = p_id_phieu and ma = p_ma) then
    raise exception 'Mã % đã có trong phiếu này rồi', p_ma;
  end if;

  if p_ma like 'PLT%' then
    select tong_so_luong into v_sl from oqc_pallet where id_pallet = p_ma and trang_thai = 'da_nhap_kho';
    if not found then raise exception 'Không tìm thấy pallet % đang trong kho (chưa nhập kho, hoặc đã xuất, hoặc đang ở phiếu xuất khác)', p_ma; end if;

    select oi.tag_no, duc_tem_id_ncp_cach_ly(oi.tag_no) into v_tag_cach_ly, v_id_ncp_cl
    from oqc_pallet_item oi where oi.id_pallet = p_ma and duc_tem_id_ncp_cach_ly(oi.tag_no) is not null
    limit 1;
    if v_id_ncp_cl is not null then
      raise exception 'Pallet % chứa tem % đang bị cách ly theo phiếu NCP % — không thể xuất kho', p_ma, v_tag_cach_ly, v_id_ncp_cl;
    end if;

    v_loai := 'pallet';
    select string_agg(distinct t.ma_sp, ', ') into v_ma_sp
    from duc_tem t where t.tag_no in (select tag_no from oqc_pallet_item where id_pallet = p_ma);
  else
    v_id_ncp_cl := duc_tem_id_ncp_cach_ly(p_ma);
    if v_id_ncp_cl is not null then
      raise exception 'Tem % đang bị cách ly theo phiếu NCP % — không thể xuất kho', p_ma, v_id_ncp_cl;
    end if;

    select ma_sp, ten_sp, so_luong into v_ma_sp, v_ten_sp, v_sl from duc_tem where tag_no = p_ma;
    if not found then raise exception 'Không tìm thấy tem %', p_ma; end if;
    select vi_tri_hien_tai into v_vi_tri from cd_v_vi_tri_hien_tai where tag_no = p_ma;
    if v_vi_tri is distinct from 'Nhập kho' then
      raise exception 'Tem % chưa ở trạng thái trong kho (vị trí hiện tại: %)', p_ma, coalesce(v_vi_tri, '(chưa xác định)');
    end if;
    v_loai := 'tem';
  end if;

  insert into kho_phieu_xuat_item (id_phieu, loai, ma, ma_sp, ten_sp, so_luong)
  values (p_id_phieu, v_loai, p_ma, v_ma_sp, v_ten_sp, coalesce(v_sl, 0));

  return jsonb_build_object('ok', true, 'loai', v_loai, 'ma_sp', v_ma_sp, 'so_luong', v_sl);
end;
$$;
revoke execute on function kho_them_vao_phieu_xuat(text, text, text) from anon;
grant execute on function kho_them_vao_phieu_xuat(text, text, text) to authenticated;
