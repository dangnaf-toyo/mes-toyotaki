-- T71: 2 chốt chặn ở Đúc (Gán kế hoạch / Đổi SP / Khuôn kép, cả desktop lẫn mobile)
--
-- 1. KHÔNG cho nhập số khuôn tự do. Trước đây form có lựa chọn "✏️ Khác (nhập
--    tay)" và duc_ensure_mold_product_mapping() tự tạo khuôn mới trong
--    duc_shot_khuon cho bất kỳ chuỗi nào gõ vào → sinh khuôn "ma". Nay trigger
--    trên duc_ca_hien_tai chỉ chấp nhận số khuôn đã có trong duc_shot_khuon
--    HOẶC đã khai báo cho đúng mã SP ở master_products.so_khuon (Quản lý danh
--    mục → Sản phẩm). Kiểm tra trước khi chạy: mọi so_khuon đang dùng trong
--    duc_ca_hien_tai + KHSX tuần từ 28/09 đều hợp lệ → carry-over / kết ca
--    không bị ảnh hưởng (trigger chỉ xét khi INSERT hoặc khi so_khuon đổi).
--
-- 2. KHÔNG cho gán kế hoạch MỚI vào ca đã qua. Sự cố 05/10: tab Đúc để mở từ
--    lúc kết ca đêm 03/10 (header tự nhảy sang "Ca ngày 04/10" — Chủ nhật),
--    sáng thứ 2 trưởng ca gán KH cho 7 máy vào "Ca ngày 04/10" lúc 07:05 (SAU
--    khi job tự đóng ca 6h sáng đã chạy xong) → báo cáo ca ngày 05/10 sai.
--    Tối cùng ngày lại gán KH vào "Ca ngày 05/10" lúc 18:21 dù ca đó đã kết
--    lúc 18:10. Chặn khi tạo DÒNG MỚI nếu ca đã có báo cáo kết ca, hoặc ca đã
--    kết thúc theo lịch quá 1 tiếng. Sửa dòng đã có (KH, nhân sự...) vẫn được.
--
-- Chạy trên CẢ 2 project (production + staging).

-- ── 1. Số khuôn phải có trong danh mục ──────────────────────────────────────
create or replace function duc_khuon_hop_le(p_so_khuon text, p_ma_sp text)
returns boolean
language sql
stable
security definer
as $$
  select exists (select 1 from duc_shot_khuon where ma_khuon = trim(p_so_khuon))
      or exists (
        select 1 from master_products mp
        where mp.ma_sp = p_ma_sp
          and trim(p_so_khuon) in (select trim(x) from regexp_split_to_table(coalesce(mp.so_khuon, ''), '[,;]') x)
      );
$$;
revoke execute on function duc_khuon_hop_le(text, text) from public, anon, authenticated;

create or replace function duc_ca_hien_tai_chan_khuon_tu_do()
returns trigger
language plpgsql
security definer
as $$
begin
  if coalesce(trim(new.so_khuon), '') = '' then return new; end if;
  if tg_op = 'UPDATE' and new.so_khuon is not distinct from old.so_khuon then return new; end if;
  if not duc_khuon_hop_le(new.so_khuon, new.ma_sp) then
    raise exception 'Số khuôn "%" không có trong danh mục khuôn của SP % — chọn khuôn trong danh sách, hoặc nhờ quản lý khai báo số khuôn cho SP ở Quản lý danh mục → Sản phẩm.',
      new.so_khuon, new.ma_sp;
  end if;
  return new;
end;
$$;
revoke execute on function duc_ca_hien_tai_chan_khuon_tu_do() from public, anon, authenticated;

drop trigger if exists trg_duc_ca_hien_tai_chan_khuon_tu_do on duc_ca_hien_tai;
create trigger trg_duc_ca_hien_tai_chan_khuon_tu_do
  before insert or update of so_khuon on duc_ca_hien_tai
  for each row execute function duc_ca_hien_tai_chan_khuon_tu_do();

-- ── 2. Không gán KH mới vào ca đã qua ───────────────────────────────────────
-- Trả về NULL nếu được phép, ngược lại là câu báo lỗi.
create or replace function duc_loi_gan_kh_ca_da_qua(p_ngay date, p_ca text, p_phuong_an_ca text)
returns text
language plpgsql
stable
security definer
as $$
declare
  v_win jsonb;
  v_end timestamptz;
begin
  if exists (select 1 from duc_bao_cao_ca where ngay = p_ngay and ca = p_ca) then
    return p_ca || ' ' || to_char(p_ngay, 'DD/MM') || ' đã kết ca — không thể gán thêm kế hoạch. '
      || 'Chọn đúng ngày/ca hiện tại ở đầu trang rồi gán lại.';
  end if;
  v_win := duc_get_shift_window(p_ngay, p_phuong_an_ca, p_ca);
  v_end := (v_win->>'end')::timestamptz;
  if v_end is not null and v_end < now() - interval '1 hour' then
    return p_ca || ' ' || to_char(p_ngay, 'DD/MM') || ' đã kết thúc lúc '
      || to_char(v_end at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM')
      || ' — không thể gán kế hoạch mới cho ca đã qua. Chọn đúng ngày/ca hiện tại ở đầu trang rồi gán lại.';
  end if;
  return null;
end;
$$;
revoke execute on function duc_loi_gan_kh_ca_da_qua(date, text, text) from public, anon, authenticated;

create or replace function duc_upsert_plan(p_ngay date, p_ca text, p_phuong_an_ca text, p_ma_may text, p_ma_sp text, p_ten_sp text, p_so_khuon text, p_kh_ca numeric, p_kh_tuan numeric, p_nv_ca_ngay text, p_nv_ca_dem text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_id_dong text;
  v_existing_version bigint;
  v_new_version bigint;
  v_win jsonb;
  v_last_shot numeric;
  v_now timestamptz := now();
  v_loi_ca text;
begin
  if p_so_khuon is null or trim(p_so_khuon) = '' then
    return jsonb_build_object('ok', false, 'error', 'Bắt buộc nhập số khuôn');
  end if;

  v_id_dong := duc_make_id_dong(p_ngay, p_ca, p_ma_may, p_ma_sp);
  select version into v_existing_version from duc_ca_hien_tai where id_dong = v_id_dong;

  if found then
    v_new_version := coalesce(v_existing_version, 0) + 1;
    update duc_ca_hien_tai set
      ten_sp = coalesce(p_ten_sp, ten_sp), so_khuon = coalesce(p_so_khuon, so_khuon),
      kh_ca = coalesce(p_kh_ca, kh_ca), kh_tuan = coalesce(p_kh_tuan, kh_tuan),
      nv_ca_ngay = coalesce(p_nv_ca_ngay, nv_ca_ngay), nv_ca_dem = coalesce(p_nv_ca_dem, nv_ca_dem),
      version = v_new_version, last_updated_by = p_user, last_updated_at = v_now
    where id_dong = v_id_dong;

    if p_so_khuon is not null and p_ma_sp is not null then perform duc_ensure_mold_product_mapping(p_so_khuon, p_ma_sp); end if;
    return jsonb_build_object('ok', true, 'id_dong', v_id_dong, 'version', v_new_version, 'created', false);
  else
    -- T71: không tạo dòng mới trong ca đã kết / đã qua
    v_loi_ca := duc_loi_gan_kh_ca_da_qua(p_ngay, p_ca, p_phuong_an_ca);
    if v_loi_ca is not null then
      return jsonb_build_object('ok', false, 'error', v_loi_ca);
    end if;

    v_win := duc_get_shift_window(p_ngay, p_phuong_an_ca, p_ca);
    select so_shot_cuoi_ca_gan_nhat into v_last_shot from duc_shot_may where ma_may = p_ma_may;

    insert into duc_ca_hien_tai (
      id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon,
      kh_ca, kh_tuan, tt_ca, tt_tuan, nv_ca_ngay, nv_ca_dem, version, last_updated_by, last_updated_at,
      so_shot_nong_khuon, so_luong_ng, phan_loai_ng, sp_start_time, sp_end_time, so_shot_khuon_snapshot,
      so_shot_dau_ca, so_shot_cuoi_ca
    ) values (
      v_id_dong, p_ngay, p_ca, p_phuong_an_ca, duc_iso_week(p_ngay), p_ma_may, coalesce(p_ma_sp, ''), coalesce(p_ten_sp, ''), coalesce(p_so_khuon, ''),
      p_kh_ca, p_kh_tuan, 0, 0, coalesce(p_nv_ca_ngay, ''), coalesce(p_nv_ca_dem, ''), 1, p_user, v_now,
      0, 0, '', (v_win->>'start')::timestamptz, (v_win->>'end')::timestamptz, 0, v_last_shot, null
    );

    if p_so_khuon is not null and p_ma_sp is not null then perform duc_ensure_mold_product_mapping(p_so_khuon, p_ma_sp); end if;
    begin perform duc_request_ipqc_check(v_id_dong, 'doi_khuon'); exception when others then null; end;

    return jsonb_build_object('ok', true, 'id_dong', v_id_dong, 'version', 1, 'created', true);
  end if;
end;
$$;

create or replace function duc_assign_paired_plan(p_ngay date, p_ca text, p_phuong_an_ca text, p_ma_may text, p_so_khuon text, p_nv_ca_ngay text, p_nv_ca_dem text, p_sp_a_ma_sp text, p_sp_a_ten_sp text, p_sp_a_kh_ca numeric, p_sp_a_kh_tuan numeric, p_sp_b_ma_sp text, p_sp_b_ten_sp text, p_sp_b_kh_ca numeric, p_sp_b_kh_tuan numeric, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_id_a text; v_id_b text; v_win jsonb; v_last_shot numeric; v_now timestamptz := now();
  v_loi_ca text;
begin
  if p_so_khuon is null or trim(p_so_khuon) = '' then return jsonb_build_object('ok', false, 'error', 'Khuôn kép cần nhập số khuôn'); end if;
  if p_sp_a_ma_sp is null or p_sp_a_kh_ca is null or p_sp_a_kh_ca <= 0 then return jsonb_build_object('ok', false, 'error', 'Chưa nhập đủ Mã SP A / KH ca A'); end if;
  if p_sp_b_ma_sp is null or p_sp_b_kh_ca is null or p_sp_b_kh_ca <= 0 then return jsonb_build_object('ok', false, 'error', 'Chưa nhập đủ Mã SP B / KH ca B'); end if;
  if trim(p_sp_a_ma_sp) = trim(p_sp_b_ma_sp) then return jsonb_build_object('ok', false, 'error', 'SP A và SP B phải khác nhau'); end if;

  -- T71: không tạo dòng mới trong ca đã kết / đã qua
  v_loi_ca := duc_loi_gan_kh_ca_da_qua(p_ngay, p_ca, p_phuong_an_ca);
  if v_loi_ca is not null then return jsonb_build_object('ok', false, 'error', v_loi_ca); end if;

  v_id_a := duc_make_id_dong(p_ngay, p_ca, p_ma_may, p_sp_a_ma_sp);
  v_id_b := duc_make_id_dong(p_ngay, p_ca, p_ma_may, p_sp_b_ma_sp);
  if exists (select 1 from duc_ca_hien_tai where id_dong = v_id_a) then return jsonb_build_object('ok', false, 'error', 'Máy ' || p_ma_may || ' đã có dòng với SP ' || p_sp_a_ma_sp || ' trong ca này'); end if;
  if exists (select 1 from duc_ca_hien_tai where id_dong = v_id_b) then return jsonb_build_object('ok', false, 'error', 'Máy ' || p_ma_may || ' đã có dòng với SP ' || p_sp_b_ma_sp || ' trong ca này'); end if;

  v_win := duc_get_shift_window(p_ngay, p_phuong_an_ca, p_ca);
  select so_shot_cuoi_ca_gan_nhat into v_last_shot from duc_shot_may where ma_may = p_ma_may;

  insert into duc_ca_hien_tai (
    id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, kh_ca, kh_tuan, tt_ca, tt_tuan,
    nv_ca_ngay, nv_ca_dem, version, last_updated_by, last_updated_at, so_shot_nong_khuon, so_luong_ng, phan_loai_ng,
    sp_start_time, sp_end_time, so_shot_khuon_snapshot, so_shot_dau_ca, so_shot_cuoi_ca, khuon_kep_voi
  ) values
  (v_id_a, p_ngay, p_ca, p_phuong_an_ca, duc_iso_week(p_ngay), p_ma_may, p_sp_a_ma_sp, coalesce(p_sp_a_ten_sp,''), p_so_khuon, p_sp_a_kh_ca, coalesce(p_sp_a_kh_tuan,0), 0, 0,
    coalesce(p_nv_ca_ngay,''), coalesce(p_nv_ca_dem,''), 1, p_user, v_now, 0, 0, '', (v_win->>'start')::timestamptz, (v_win->>'end')::timestamptz, 0, v_last_shot, null, v_id_b),
  (v_id_b, p_ngay, p_ca, p_phuong_an_ca, duc_iso_week(p_ngay), p_ma_may, p_sp_b_ma_sp, coalesce(p_sp_b_ten_sp,''), p_so_khuon, p_sp_b_kh_ca, coalesce(p_sp_b_kh_tuan,0), 0, 0,
    coalesce(p_nv_ca_ngay,''), coalesce(p_nv_ca_dem,''), 1, p_user, v_now, 0, 0, '', (v_win->>'start')::timestamptz, (v_win->>'end')::timestamptz, 0, v_last_shot, null, v_id_a);

  perform duc_ensure_mold_product_mapping(p_so_khuon, p_sp_a_ma_sp);
  perform duc_ensure_mold_product_mapping(p_so_khuon, p_sp_b_ma_sp);
  begin perform duc_request_ipqc_check(v_id_a, 'doi_khuon'); exception when others then null; end;
  begin perform duc_request_ipqc_check(v_id_b, 'doi_khuon'); exception when others then null; end;

  return jsonb_build_object('ok', true, 'id_dong_a', v_id_a, 'id_dong_b', v_id_b, 'ma_sp_a', p_sp_a_ma_sp, 'ma_sp_b', p_sp_b_ma_sp);
end;
$$;
