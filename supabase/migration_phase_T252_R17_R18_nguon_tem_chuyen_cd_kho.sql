-- T252 (15/11/2026): Rà soát R17 + R18
--   R17 Tem Đúc đang dùng (ghi-nhan-tem-thanh-pham): lưu CÔNG ĐOẠN khi khai
--       nguồn; ghi nhận tem TP chỉ trừ nguồn cùng công đoạn của tem TP; tem
--       nguồn bị bỏ khỏi danh sách khi chuyển đi; thêm cd_bo_nguon_dang_dung.
--   R18 cd_ghi_chuyen_cong_doan: khoá dòng tem, lấy mã/SL từ DB, công đoạn
--       giao phải đúng vị trí hiện tại (chặn luôn phiếu trùng bấm 2 lần).
--       Kho TP: nhập kho khoá dòng + chỉ nhận từ công đoạn liền trước Nhập kho
--       theo lưu trình (hoặc OQC); 1 mã không nằm 2 phiếu xuất mở; đóng phiếu
--       kiểm lại vị trí tem.

-- ── Vị trí hiện tại của tem (1 nguồn sự thật cho DB + client) ───────────────
create or replace function public.cd_vi_tri_tem(p_tag_no text) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v_tag text := trim(p_tag_no);
  v_loc text;
  v_tem duc_tem%rowtype;
  v_cha text;
  i int := 0;
begin
  loop
    select cong_doan_nhan into v_loc from cd_chuyen_cong_doan_log
    where tag_no = v_tag and coalesce(trang_thai_xac_nhan, '') <> 'Đã từ chối'
    order by thoi_gian_chuyen desc limit 1;
    if v_loc is not null then return v_loc; end if;
    -- tem con tách ra chưa từng chuyển → đang ở cùng chỗ tem cha
    select tag_no_cha into v_cha from duc_tem_tach where tag_no_con = v_tag limit 1;
    exit when v_cha is null or i >= 5;
    v_tag := v_cha; v_cha := null; i := i + 1;
  end loop;
  select * into v_tem from duc_tem where tag_no = trim(p_tag_no);
  if v_tem.tag_no like 'TP%' then return coalesce(nullif(v_tem.tram_cong_doan, ''), 'Đúc'); end if;
  return 'Đúc';
end $$;
revoke execute on function public.cd_vi_tri_tem(text) from public, anon;
grant execute on function public.cd_vi_tri_tem(text) to authenticated;

-- ── R17 ─────────────────────────────────────────────────────────────────────
alter table public.duc_tem add column if not exists cong_doan_dang_dung text;
update public.duc_tem set cong_doan_dang_dung = public.cd_vi_tri_tem(tag_no)
where thoi_diem_bat_dau_dung is not null and so_luong > 0 and cong_doan_dang_dung is null;
create index if not exists idx_duc_tem_nguon_dang_dung on public.duc_tem (ma_sp, cong_doan_dang_dung, thoi_diem_bat_dau_dung)
where thoi_diem_bat_dau_dung is not null;

create or replace function public.cd_khai_bao_nguon_dang_dung(p_tag_no text, p_cong_doan text, p_nguoi text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_tem duc_tem%rowtype;
  v_vi_tri text;
  v_truoc boolean;
begin
  if p_tag_no is null or trim(p_tag_no) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu Tag No');
  end if;
  if p_cong_doan is null or trim(p_cong_doan) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu công đoạn');
  end if;
  if trim(p_tag_no) ilike 'TP%' then
    return jsonb_build_object('ok', false, 'error',
      'Tem thành phẩm không dùng làm nguồn được — hãy đọc đúng tem của công đoạn ĐÚC');
  end if;

  select * into v_tem from duc_tem where tag_no = trim(p_tag_no) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || p_tag_no);
  end if;
  if coalesce(v_tem.so_luong, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error',
      'Tem ' || p_tag_no || ' đã dùng hết — không thể khai báo lại', 'da_het', true);
  end if;

  v_vi_tri := cd_vi_tri_tem(v_tem.tag_no);
  if v_vi_tri is distinct from trim(p_cong_doan) then
    return jsonb_build_object('ok', false, 'error',
      'Tem ' || p_tag_no || ' chưa được Chuyển công đoạn tới ' || p_cong_doan
      || coalesce(' — hiện đang ở ' || v_vi_tri, ' — chưa chuyển tới đâu'));
  end if;

  v_truoc := v_tem.thoi_diem_bat_dau_dung is not null;
  update duc_tem set thoi_diem_bat_dau_dung = coalesce(thoi_diem_bat_dau_dung, now()),
    cong_doan_dang_dung = trim(p_cong_doan)   -- T252 (R17)
  where tag_no = v_tem.tag_no
  returning * into v_tem;

  return jsonb_build_object(
    'ok', true, 'tag_no', v_tem.tag_no, 'ma_sp', v_tem.ma_sp, 'ten_sp', v_tem.ten_sp,
    'so_luong_con_lai', v_tem.so_luong,
    'da_khai_bao_truoc_do', v_truoc
  );
end $$;

create or replace function public.cd_bo_nguon_dang_dung(p_tag_no text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_tem duc_tem%rowtype;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập');
  end if;
  select * into v_tem from duc_tem where tag_no = trim(p_tag_no) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || p_tag_no);
  end if;
  if v_tem.thoi_diem_bat_dau_dung is null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || p_tag_no || ' không nằm trong danh sách đang dùng');
  end if;
  update duc_tem set thoi_diem_bat_dau_dung = null, cong_doan_dang_dung = null where tag_no = v_tem.tag_no;
  return jsonb_build_object('ok', true, 'tag_no', v_tem.tag_no, 'so_luong', v_tem.so_luong);
end $$;
revoke execute on function public.cd_bo_nguon_dang_dung(text) from public, anon;
grant execute on function public.cd_bo_nguon_dang_dung(text) to authenticated;

create or replace function public.cd_ghi_nhan_tem_thanh_pham(p_tag_no text, p_nguoi_kiem text, p_id_tram text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_tem duc_tem%rowtype;
  v_need numeric;
  v_take numeric;
  v_src record;
  v_used jsonb := '[]'::jsonb;
  v_het jsonb := '[]'::jsonb;
  v_cd text;
begin
  if p_tag_no is null or trim(p_tag_no) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu Tag No');
  end if;
  if p_nguoi_kiem is null or trim(p_nguoi_kiem) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu người kiểm tra');
  end if;

  select * into v_tem from duc_tem where tag_no = trim(p_tag_no) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || p_tag_no);
  end if;
  if v_tem.trang_thai <> 'Chờ đóng gói TP' then
    if v_tem.trang_thai = 'Đã đóng gói TP' then
      return jsonb_build_object(
        'ok', false,
        'error', 'Tem ' || p_tag_no || ' đã được ghi nhận lúc '
          || to_char(v_tem.ngay_gio_ghi_nhan at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM')
          || ' bởi ' || coalesce(v_tem.nguoi_tt, '(không rõ)'),
        'da_ghi_nhan', true
      );
    end if;
    return jsonb_build_object('ok', false, 'error', 'Tem ' || p_tag_no || ' không phải tem thành phẩm chờ đóng gói');
  end if;

  v_need := v_tem.so_luong;
  v_cd := nullif(trim(v_tem.tram_cong_doan), '');   -- T252 (R17): chỉ trừ nguồn cùng công đoạn

  for v_src in
    select tag_no, so_luong
    from duc_tem
    where ma_sp = v_tem.ma_sp
      and thoi_diem_bat_dau_dung is not null
      and so_luong > 0
      and (v_cd is null or cong_doan_dang_dung = v_cd)
    order by thoi_diem_bat_dau_dung asc, tag_no
    for update
  loop
    exit when v_need <= 0;
    v_take := least(v_need, v_src.so_luong);
    update duc_tem set so_luong = so_luong - v_take where tag_no = v_src.tag_no;
    insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay)
    values (v_tem.tag_no, v_src.tag_no, v_take)
    on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
    v_used := v_used || jsonb_build_array(jsonb_build_object('tag_no', v_src.tag_no, 'so_luong_lay', v_take));
    if v_src.so_luong - v_take <= 0 then
      v_het := v_het || jsonb_build_array(v_src.tag_no);
    end if;
    v_need := v_need - v_take;
  end loop;

  if v_need > 0 then
    raise exception 'Chưa đủ nguồn từ tem Đúc ĐÃ KHAI BÁO đang dùng ở % cho mã % (còn thiếu % pcs) — đọc tem thùng Đúc tiếp theo rồi ghi nhận lại',
      coalesce(v_cd, 'công đoạn này'), v_tem.ma_sp, v_need;
  end if;

  update duc_tem set
    so_luong_tt = so_luong,
    nguoi_tt = p_nguoi_kiem,
    trang_thai = 'Đã đóng gói TP',
    ghi_chu_sl = 'Đã ghi nhận thành phẩm',
    ngay_gio_ghi_nhan = now(),
    ngay_gio_xuat = now()
  where tag_no = v_tem.tag_no;

  if p_id_tram is not null and trim(p_id_tram) <> '' then
    perform cd_tram_nhap_sanluong(p_id_tram, v_tem.so_luong, 0, 'Ghi nhận tem thành phẩm ' || v_tem.tag_no, p_nguoi_kiem);
  end if;

  return jsonb_build_object(
    'ok', true,
    'tag_no', v_tem.tag_no,
    'ma_sp', v_tem.ma_sp,
    'ten_sp', v_tem.ten_sp,
    'so_luong', v_tem.so_luong,
    'so_thung_stt', v_tem.so_thung_stt,
    'nguoi_kiem', p_nguoi_kiem,
    'nguon', v_used,
    'nguon_vua_het', v_het,
    'ngay_gio_ghi_nhan', now()
  );
end $$;

-- ── R18: Chuyển công đoạn ──────────────────────────────────────────────────
create or replace function public.cd_ghi_chuyen_cong_doan(p_tag_no text, p_ma_sp text, p_ten_sp text, p_sl_tren_tem numeric, p_sl_thuc_chuyen numeric, p_lot_no text, p_so_khuon text, p_nguyen_lieu text, p_may_duc text, p_ngay_duc text, p_cong_doan_giao text, p_cong_doan_nhan text, p_nguoi_giao text, p_nguoi_nhan text, p_ghi_chu text default null)
returns table(id_phieu text, thoi_gian_chuyen timestamp with time zone, chenh_lech numeric)
language plpgsql security definer set search_path = public as $$
declare
  v_id text;
  v_now timestamptz := now();
  v_tem duc_tem%rowtype;
  v_loc text;
  v_sl_tem numeric;
  v_chenh_lech numeric;
  v_id_ncp_cl text := duc_tem_id_ncp_cach_ly(p_tag_no);
begin
  if v_id_ncp_cl is not null then
    raise exception 'Tem % đang bị cách ly theo phiếu NCP % — không thể chuyển công đoạn', p_tag_no, v_id_ncp_cl;
  end if;
  if coalesce(trim(p_cong_doan_giao), '') = '' or coalesce(trim(p_cong_doan_nhan), '') = '' then
    raise exception 'Thiếu công đoạn giao/nhận';
  end if;
  if trim(p_cong_doan_giao) = trim(p_cong_doan_nhan) then
    raise exception 'Công đoạn nhận trùng công đoạn giao (%)', p_cong_doan_giao;
  end if;

  -- T252 (R18): khoá dòng tem → 2 lần bấm gần nhau chạy lần lượt, lần sau bị chặn vì vị trí đã đổi
  select * into v_tem from duc_tem where tag_no = trim(p_tag_no) for update;
  if not found then raise exception 'Không tìm thấy tem %', p_tag_no; end if;
  if v_tem.trang_thai in ('Chờ sản xuất', 'Chờ đóng gói TP') then
    raise exception 'Tem % chưa ghi nhận thùng (%) — không thể chuyển công đoạn', p_tag_no, v_tem.trang_thai;
  end if;

  v_loc := cd_vi_tri_tem(v_tem.tag_no);
  if v_loc is distinct from trim(p_cong_doan_giao) then
    raise exception 'Tem % đang ở % — không phải ở % (có thể vừa chuyển rồi). Quét lại tem.', p_tag_no, v_loc, p_cong_doan_giao;
  end if;

  v_sl_tem := coalesce(v_tem.so_luong, 0);
  if v_sl_tem <= 0 then raise exception 'Tem % đã hết số lượng', p_tag_no; end if;
  if p_sl_thuc_chuyen is null or p_sl_thuc_chuyen <= 0 then
    raise exception 'Số lượng thực chuyển phải lớn hơn 0';
  end if;
  if p_sl_thuc_chuyen > v_sl_tem then
    raise exception 'Số lượng thực chuyển (%) vượt số lượng trên tem % (% pcs)', p_sl_thuc_chuyen, p_tag_no, v_sl_tem;
  end if;
  v_chenh_lech := v_sl_tem - p_sl_thuc_chuyen;
  v_id := cd_next_transfer_id();

  insert into cd_chuyen_cong_doan_log (
    id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp,
    sl_tren_tem, sl_thuc_chuyen, chenh_lech,
    lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc,
    cong_doan_giao, cong_doan_nhan, nguoi_giao, nguoi_nhan,
    ghi_chu, trang_thai_xac_nhan
  ) values (
    v_id, v_now, v_tem.tag_no, v_tem.ma_sp, v_tem.ten_sp,
    v_sl_tem, p_sl_thuc_chuyen, v_chenh_lech,
    p_lot_no, p_so_khuon, p_nguyen_lieu, p_may_duc, p_ngay_duc,
    trim(p_cong_doan_giao), trim(p_cong_doan_nhan), p_nguoi_giao, p_nguoi_nhan,
    nullif(trim(p_ghi_chu), ''), 'Chờ công đoạn trước xác nhận'
  );

  -- R17: tem đang làm nguồn mà chuyển đi thì bỏ khỏi danh sách đang dùng
  if v_tem.thoi_diem_bat_dau_dung is not null then
    update duc_tem set thoi_diem_bat_dau_dung = null, cong_doan_dang_dung = null where tag_no = v_tem.tag_no;
  end if;

  return query select v_id, v_now, v_chenh_lech;
end $$;

-- ── R18: Kho thành phẩm ─────────────────────────────────────────────────────
create or replace function public.kho_nhap_kho_tem(p_tag_no text, p_nguoi text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_tem duc_tem%rowtype;
  v_vitri text;
  v_now timestamptz := now();
  v_id_ncp_cl text := duc_tem_id_ncp_cach_ly(p_tag_no);
  v_steps text[];
  v_i int;
  v_truoc text;
  v_pallet text;
begin
  if auth.uid() is not null and not public.has_role(VARIADIC ARRAY['admin', 'kho_nvl', 'nhan_vien_oqc', 'qc_manager', 'ke_hoach', 'qlsx_nhan_vien', 'qlsx_truong_phong']) then
    raise exception '⛔ Tài khoản không có quyền thực hiện thao tác này — cần vai trò: %', 'Kho / OQC / Kế hoạch / QLSX' using errcode = '42501';
  end if;   -- T212
  p_nguoi := public.duc_ten_nguoi_hien_tai(p_nguoi);   -- T212: tên theo tài khoản
  if v_id_ncp_cl is not null then
    raise exception 'Tem % đang bị cách ly theo phiếu NCP % — không thể nhập kho', p_tag_no, v_id_ncp_cl;
  end if;

  select * into v_tem from duc_tem where tag_no = trim(p_tag_no) for update;   -- T252 (R18)
  if not found then raise exception 'Không tìm thấy tem %', p_tag_no; end if;
  if coalesce(v_tem.so_luong, 0) <= 0 then raise exception 'Tem % đã hết số lượng', p_tag_no; end if;
  if v_tem.trang_thai in ('Chờ sản xuất', 'Chờ đóng gói TP') then
    raise exception 'Tem % chưa ghi nhận thùng (%) — không nhập kho được', p_tag_no, v_tem.trang_thai;
  end if;

  v_vitri := cd_vi_tri_tem(v_tem.tag_no);
  if v_vitri = 'Nhập kho' then raise exception 'Tem % đã nhập kho rồi', p_tag_no; end if;
  if v_vitri = 'Xuất hàng' then raise exception 'Tem % đã xuất hàng', p_tag_no; end if;
  if v_vitri = 'Lọc hàng' then raise exception 'Tem % đang ở Lọc hàng — chưa được nhập kho', p_tag_no; end if;

  -- T252 (R18): chỉ nhận từ công đoạn liền trước "Nhập kho" theo lưu trình, hoặc OQC
  select array_agg(trim(s) order by ord) into v_steps
  from unnest(string_to_array(coalesce((select quy_trinh_cong_doan from master_products where ma_sp = v_tem.ma_sp limit 1), ''), ',')) with ordinality as u(s, ord)
  where trim(s) <> '';
  v_i := array_position(v_steps, 'Nhập kho');
  if v_i is not null and v_i > 1 then
    v_truoc := v_steps[v_i - 1];
    if v_vitri is distinct from v_truoc and v_vitri <> 'OQC' then
      raise exception 'Tem % đang ở % — phải qua % rồi mới nhập kho (lưu trình: %)',
        p_tag_no, v_vitri, v_truoc, array_to_string(v_steps, ' → ');
    end if;
  end if;

  select oi.id_pallet into v_pallet from oqc_pallet_item oi
  where oi.tag_no = v_tem.tag_no limit 1;
  if v_pallet is not null then
    raise exception 'Tem % thuộc pallet % — nhập kho theo pallet', p_tag_no, v_pallet;
  end if;

  insert into cd_chuyen_cong_doan_log (
    id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
    cong_doan_giao, cong_doan_nhan, nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan
  ) values (
    cd_next_transfer_id(), v_now, v_tem.tag_no, v_tem.ma_sp, v_tem.ten_sp, v_tem.so_luong, v_tem.so_luong, 0,
    v_vitri, 'Nhập kho', p_nguoi, p_nguoi, 'Đã xác nhận chuyển công đoạn',
    to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
  );
  if v_tem.thoi_diem_bat_dau_dung is not null then
    update duc_tem set thoi_diem_bat_dau_dung = null, cong_doan_dang_dung = null where tag_no = v_tem.tag_no;
  end if;

  return jsonb_build_object('ok', true, 'ma_sp', v_tem.ma_sp, 'ten_sp', v_tem.ten_sp, 'so_luong', v_tem.so_luong);
end $$;

create or replace function public.kho_them_vao_phieu_xuat(p_id_phieu text, p_ma text, p_nguoi text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_loai text;
  v_sl numeric;
  v_ma_sp text;
  v_ten_sp text;
  v_trang_thai_phieu text;
  v_vi_tri text;
  v_id_ncp_cl text;
  v_tag_cach_ly text;
  v_phieu_khac text;
  v_x text;
begin
  if auth.uid() is not null and not public.has_role(VARIADIC ARRAY['admin', 'kho_nvl', 'nhan_vien_oqc', 'qc_manager', 'ke_hoach', 'qlsx_nhan_vien', 'qlsx_truong_phong']) then
    raise exception '⛔ Tài khoản không có quyền thực hiện thao tác này — cần vai trò: %', 'Kho / OQC / Kế hoạch / QLSX' using errcode = '42501';
  end if;   -- T212
  p_nguoi := public.duc_ten_nguoi_hien_tai(p_nguoi);   -- T212: tên theo tài khoản
  if p_ma is null or trim(p_ma) = '' then raise exception 'Thiếu mã quét'; end if;
  p_ma := trim(p_ma);
  -- T252 (R18): khoá theo mã — 2 phiếu thêm cùng mã cùng lúc sẽ chạy lần lượt
  perform pg_advisory_xact_lock(hashtext('kho_xuat_ma:' || p_ma));
  select trang_thai into v_trang_thai_phieu from kho_phieu_xuat where id_phieu = p_id_phieu for update;
  if not found then raise exception 'Không tìm thấy phiếu xuất %', p_id_phieu; end if;
  if v_trang_thai_phieu <> 'mo' then raise exception 'Phiếu % đã đóng, không thêm được nữa', p_id_phieu; end if;
  if exists (select 1 from kho_phieu_xuat_item where id_phieu = p_id_phieu and ma = p_ma) then
    raise exception 'Mã % đã có trong phiếu này rồi', p_ma;
  end if;
  select i.id_phieu into v_phieu_khac from kho_phieu_xuat_item i join kho_phieu_xuat p on p.id_phieu = i.id_phieu
  where i.ma = p_ma and p.trang_thai = 'mo' and i.id_phieu <> p_id_phieu limit 1;
  if v_phieu_khac is not null then
    raise exception 'Mã % đang nằm trong phiếu xuất % (chưa đóng) — bỏ ra khỏi phiếu đó trước', p_ma, v_phieu_khac;
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
    select i.ma, i.id_phieu into v_x, v_phieu_khac from kho_phieu_xuat_item i join kho_phieu_xuat p on p.id_phieu = i.id_phieu
    where p.trang_thai = 'mo' and i.ma in (select tag_no from oqc_pallet_item where id_pallet = p_ma) limit 1;
    if v_x is not null then
      raise exception 'Pallet % có tem % đã nằm lẻ trong phiếu xuất %', p_ma, v_x, v_phieu_khac;
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
    v_vi_tri := cd_vi_tri_tem(p_ma);
    if v_vi_tri is distinct from 'Nhập kho' then
      raise exception 'Tem % chưa ở trạng thái trong kho (vị trí hiện tại: %)', p_ma, coalesce(v_vi_tri, '(chưa xác định)');
    end if;
    select oi.id_pallet into v_x from oqc_pallet_item oi where oi.tag_no = p_ma limit 1;
    if v_x is not null then
      raise exception 'Tem % thuộc pallet % — quét mã pallet để xuất', p_ma, v_x;
    end if;
    v_loai := 'tem';
  end if;

  insert into kho_phieu_xuat_item (id_phieu, loai, ma, ma_sp, ten_sp, so_luong)
  values (p_id_phieu, v_loai, p_ma, v_ma_sp, v_ten_sp, coalesce(v_sl, 0));

  return jsonb_build_object('ok', true, 'loai', v_loai, 'ma_sp', v_ma_sp, 'so_luong', v_sl);
end $$;

create or replace function public.kho_dong_phieu_xuat(p_id_phieu text, p_nguoi text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_item record;
  v_now timestamptz := now();
  v_count int := 0;
begin
  if auth.uid() is not null and not public.has_role(VARIADIC ARRAY['admin', 'kho_nvl', 'nhan_vien_oqc', 'qc_manager', 'ke_hoach', 'qlsx_nhan_vien', 'qlsx_truong_phong']) then
    raise exception '⛔ Tài khoản không có quyền thực hiện thao tác này — cần vai trò: %', 'Kho / OQC / Kế hoạch / QLSX' using errcode = '42501';
  end if;   -- T212
  p_nguoi := public.duc_ten_nguoi_hien_tai(p_nguoi);   -- T212: tên theo tài khoản
  -- T252 (R18): khoá phiếu — bấm đóng 2 lần không ghi xuất 2 lần
  perform 1 from kho_phieu_xuat where id_phieu = p_id_phieu and trang_thai = 'mo' for update;
  if not found then
    raise exception 'Không tìm thấy phiếu đang mở %', p_id_phieu;
  end if;
  if not exists (select 1 from kho_phieu_xuat_item where id_phieu = p_id_phieu) then
    raise exception 'Phiếu chưa có mã nào — quét ít nhất 1 pallet/tem trước khi đóng phiếu';
  end if;

  for v_item in select * from kho_phieu_xuat_item where id_phieu = p_id_phieu order by ma loop
    if v_item.loai = 'pallet' then
      update oqc_pallet set trang_thai = 'da_xuat' where id_pallet = v_item.ma and trang_thai = 'da_nhap_kho';
      if not found then raise exception 'Pallet % không còn ở trạng thái trong kho — có thể đã xuất ở phiếu khác', v_item.ma; end if;
    else
      perform 1 from duc_tem where tag_no = v_item.ma for update;
      if cd_vi_tri_tem(v_item.ma) is distinct from 'Nhập kho' then
        raise exception 'Tem % không còn trong kho (đang ở %) — có thể đã xuất ở phiếu khác; bỏ ra khỏi phiếu rồi đóng lại',
          v_item.ma, coalesce(cd_vi_tri_tem(v_item.ma), '?');
      end if;
      insert into cd_chuyen_cong_doan_log (
        id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
        cong_doan_giao, cong_doan_nhan, nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan
      ) values (
        cd_next_transfer_id(), v_now, v_item.ma, v_item.ma_sp, v_item.ten_sp, v_item.so_luong, v_item.so_luong, 0,
        'Nhập kho', 'Xuất hàng', p_nguoi, p_nguoi, 'Đã xác nhận chuyển công đoạn',
        to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
      );
    end if;
    v_count := v_count + 1;
  end loop;

  update kho_phieu_xuat set trang_thai = 'da_xuat', thoi_diem_dong = v_now, nguoi_xuat = coalesce(nguoi_xuat, p_nguoi)
  where id_phieu = p_id_phieu;

  return jsonb_build_object('ok', true, 'so_muc', v_count);
end $$;
