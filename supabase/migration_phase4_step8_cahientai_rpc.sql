-- ============================================================================
-- Phase 4, bước con 8 (bổ sung, phát hiện khi bắt đầu viết giao diện tĩnh) —
-- các hàm ghi của CaHienTai.js/ShotKhuon.js/VanDeKhuon.js (bước con 1+3) mới
-- chỉ tồn tại dạng hàm Apps Script (gọi Supabase bằng service_role key ẩn
-- trong Script Properties) — CHƯA an toàn để trình duyệt gọi thẳng bằng anon
-- key. File này port toàn bộ sang RPC Postgres theo đúng pattern đã dùng ở
-- bước con 4-7 (SECURITY DEFINER + revoke anon/grant authenticated).
--
-- Sau file này, các hàm Apps Script tương ứng (đang phục vụ link Apps Script
-- cũ chạy song song) vẫn giữ nguyên KHÔNG đổi — 2 đường (Apps Script cũ, RPC
-- mới cho web tĩnh) cùng ghi vào đúng 1 bảng Supabase nên không lệch dữ liệu.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ── ensureMoldProductMapping_ (ShotKhuon.js) — dùng nội bộ bởi upsert/change product ──
create or replace function duc_ensure_mold_product_mapping(p_ma_khuon text, p_ma_sp text)
returns void
language plpgsql
security definer
as $$
declare
  v_existing text;
  v_now timestamptz := now();
begin
  if p_ma_khuon is null or trim(p_ma_khuon) = '' or p_ma_sp is null or trim(p_ma_sp) = '' then return; end if;
  select ten_sp_gan_nhat into v_existing from duc_shot_khuon where ma_khuon = trim(p_ma_khuon);
  if not found then
    insert into duc_shot_khuon (ma_khuon, ten_sp_gan_nhat, tong_shot_luy_ke, nguong_bao_duong, nguong_lam_moi,
      shot_tai_lan_bao_duong_gan_nhat, trang_thai_khuon, ghi_chu, last_updated_at)
    values (trim(p_ma_khuon), trim(p_ma_sp), 0, 10000, 100000, 0, 'OK', '', v_now);
    return;
  end if;
  if split_part(coalesce(v_existing, ''), ' (', 1) <> trim(p_ma_sp) then
    update duc_shot_khuon set ten_sp_gan_nhat = trim(p_ma_sp), last_updated_at = v_now where ma_khuon = trim(p_ma_khuon);
  end if;
end;
$$;

-- ── setLastMachineShot_ (ShotMay.js) — dùng nội bộ ──────────────────────────
create or replace function duc_set_last_machine_shot(p_ma_may text, p_shot numeric)
returns void
language sql
security definer
as $$
  insert into duc_shot_may (ma_may, so_shot_cuoi_ca_gan_nhat, last_updated_at)
  values (p_ma_may, p_shot, now())
  on conflict (ma_may) do update set so_shot_cuoi_ca_gan_nhat = excluded.so_shot_cuoi_ca_gan_nhat, last_updated_at = excluded.last_updated_at;
$$;

-- ── upsertPlan_ ──────────────────────────────────────────────────────────
create or replace function duc_upsert_plan(
  p_ngay date, p_ca text, p_phuong_an_ca text, p_ma_may text, p_ma_sp text, p_ten_sp text,
  p_so_khuon text, p_kh_ca numeric, p_kh_tuan numeric, p_nv_ca_ngay text, p_nv_ca_dem text, p_user text
)
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
revoke execute on function duc_upsert_plan(date, text, text, text, text, text, text, numeric, numeric, text, text, text) from anon;
grant execute on function duc_upsert_plan(date, text, text, text, text, text, text, numeric, numeric, text, text, text) to authenticated;

-- ── assignPairedPlan_ (khuôn kép) ────────────────────────────────────────
create or replace function duc_assign_paired_plan(
  p_ngay date, p_ca text, p_phuong_an_ca text, p_ma_may text, p_so_khuon text,
  p_nv_ca_ngay text, p_nv_ca_dem text,
  p_sp_a_ma_sp text, p_sp_a_ten_sp text, p_sp_a_kh_ca numeric, p_sp_a_kh_tuan numeric,
  p_sp_b_ma_sp text, p_sp_b_ten_sp text, p_sp_b_kh_ca numeric, p_sp_b_kh_tuan numeric,
  p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_id_a text; v_id_b text; v_win jsonb; v_last_shot numeric; v_now timestamptz := now();
begin
  if p_so_khuon is null or trim(p_so_khuon) = '' then return jsonb_build_object('ok', false, 'error', 'Khuôn kép cần nhập số khuôn'); end if;
  if p_sp_a_ma_sp is null or p_sp_a_kh_ca is null or p_sp_a_kh_ca <= 0 then return jsonb_build_object('ok', false, 'error', 'Chưa nhập đủ Mã SP A / KH ca A'); end if;
  if p_sp_b_ma_sp is null or p_sp_b_kh_ca is null or p_sp_b_kh_ca <= 0 then return jsonb_build_object('ok', false, 'error', 'Chưa nhập đủ Mã SP B / KH ca B'); end if;
  if trim(p_sp_a_ma_sp) = trim(p_sp_b_ma_sp) then return jsonb_build_object('ok', false, 'error', 'SP A và SP B phải khác nhau'); end if;

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
revoke execute on function duc_assign_paired_plan(date, text, text, text, text, text, text, text, text, numeric, numeric, text, text, numeric, numeric, text) from anon;
grant execute on function duc_assign_paired_plan(date, text, text, text, text, text, text, text, text, numeric, numeric, text, text, numeric, numeric, text) to authenticated;

-- ── setIncidentOpen_ (khác duc_set_incident_open ở bước con 4 chỉ ở việc tự
-- validate normalizeIncidentType + chặn giờ tương lai — client nên tự chuẩn
-- hoá loại sự cố trước khi gọi RPC vì danh mục LOAI_SU_CO là JS config, không
-- lưu DB; RPC chỉ kiểm tra không rỗng) ────────────────────────────────────
create or replace function duc_open_incident(p_id_dong text, p_loai text, p_gio_phat_sinh timestamptz, p_van_de text, p_noi_dung_xu_ly text, p_dam_nhiem text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
begin
  if p_loai is null or trim(p_loai) = '' then return jsonb_build_object('ok', false, 'error', 'Invalid incident type'); end if;
  if p_gio_phat_sinh is null then return jsonb_build_object('ok', false, 'error', 'Chưa nhập giờ phát sinh'); end if;
  if p_gio_phat_sinh > now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Giờ phát sinh không được ở tương lai'); end if;
  return duc_set_incident_open(p_id_dong, p_loai, p_gio_phat_sinh, p_van_de, p_noi_dung_xu_ly, p_dam_nhiem);
end;
$$;
revoke execute on function duc_open_incident(text, text, timestamptz, text, text, text, text) from anon;
grant execute on function duc_open_incident(text, text, timestamptz, text, text, text, text) to authenticated;

-- ── acquireLock_ / releaseLock_ (khoá chỉnh sửa) ────────────────────────────
create or replace function duc_acquire_lock(p_id_dong text, p_user text, p_timeout_min numeric default 5)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_holder text; v_holder_at timestamptz; v_now timestamptz := now();
begin
  select editing_lock_user, editing_lock_at into v_holder, v_holder_at from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if v_holder is not null and v_holder <> '' and v_holder <> p_user and v_holder_at is not null then
    if extract(epoch from (v_now - v_holder_at)) / 60 < p_timeout_min then
      return jsonb_build_object('ok', false, 'error', 'locked_by_other', 'holder', v_holder);
    end if;
  end if;
  update duc_ca_hien_tai set editing_lock_user = p_user, editing_lock_at = v_now where id_dong = p_id_dong;
  return jsonb_build_object('ok', true, 'granted', true);
end;
$$;
revoke execute on function duc_acquire_lock(text, text, numeric) from anon;
grant execute on function duc_acquire_lock(text, text, numeric) to authenticated;

create or replace function duc_release_lock(p_id_dong text)
returns jsonb
language plpgsql
security definer
as $$
begin
  if not exists (select 1 from duc_ca_hien_tai where id_dong = p_id_dong) then return jsonb_build_object('ok', false); end if;
  update duc_ca_hien_tai set editing_lock_user = '', editing_lock_at = null where id_dong = p_id_dong;
  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function duc_release_lock(text) from anon;
grant execute on function duc_release_lock(text) to authenticated;

-- ── changeProduct_ ───────────────────────────────────────────────────────
create or replace function duc_change_product(
  p_old_id_dong text, p_new_ma_sp text, p_new_ten_sp text, p_new_so_khuon text,
  p_new_kh_ca numeric, p_new_kh_tuan numeric, p_gio_bat_dau_doi_khuon timestamptz, p_dam_nhiem text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_old record; v_new_id_dong text; v_win jsonb; v_carry_shot numeric; v_now timestamptz := now();
begin
  if p_new_ma_sp is null or trim(p_new_ma_sp) = '' then return jsonb_build_object('ok', false, 'error', 'Chưa nhập mã SP mới'); end if;
  if p_new_kh_ca is null or p_new_kh_ca <= 0 then return jsonb_build_object('ok', false, 'error', 'Chưa nhập KH ca cho SP mới'); end if;
  if p_gio_bat_dau_doi_khuon is null then return jsonb_build_object('ok', false, 'error', 'Chưa nhập giờ bắt đầu đổi khuôn'); end if;
  if p_new_so_khuon is null or trim(p_new_so_khuon) = '' then return jsonb_build_object('ok', false, 'error', 'Bắt buộc nhập số khuôn'); end if;
  if p_gio_bat_dau_doi_khuon > now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Giờ bắt đầu đổi khuôn không được ở tương lai'); end if;

  select * into v_old from duc_ca_hien_tai where id_dong = p_old_id_dong;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng SP cũ: ' || p_old_id_dong); end if;
  if v_old.open_gio_phat_sinh is not null then return jsonb_build_object('ok', false, 'error', 'Dòng SP cũ đang có sự cố khác. Vui lòng xử lý xong trước khi đổi SP.'); end if;
  if trim(p_new_ma_sp) = trim(coalesce(v_old.ma_sp, '')) then return jsonb_build_object('ok', false, 'error', 'SP mới trùng với SP hiện tại'); end if;

  v_new_id_dong := duc_make_id_dong(v_old.ngay, v_old.ca, v_old.ma_may, p_new_ma_sp);
  if exists (select 1 from duc_ca_hien_tai where id_dong = v_new_id_dong) then
    return jsonb_build_object('ok', false, 'error', 'Máy ' || v_old.ma_may || ' đã có dòng với SP ' || p_new_ma_sp || ' trong ca này');
  end if;

  v_win := duc_get_shift_window(v_old.ngay, v_old.phuong_an_ca, v_old.ca);
  v_carry_shot := v_old.so_shot_cuoi_ca;
  if v_carry_shot is null then select so_shot_cuoi_ca_gan_nhat into v_carry_shot from duc_shot_may where ma_may = v_old.ma_may; end if;

  insert into duc_ca_hien_tai (
    id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, kh_ca, kh_tuan, tt_ca, tt_tuan,
    nv_ca_ngay, nv_ca_dem, open_loai_su_co, open_gio_phat_sinh, open_van_de, open_noi_dung_xu_ly, open_dam_nhiem,
    version, last_updated_by, last_updated_at, so_shot_nong_khuon, so_luong_ng, phan_loai_ng,
    sp_start_time, sp_end_time, so_shot_khuon_snapshot, so_shot_dau_ca, so_shot_cuoi_ca
  ) values (
    v_new_id_dong, v_old.ngay, v_old.ca, v_old.phuong_an_ca, duc_iso_week(v_old.ngay), v_old.ma_may, p_new_ma_sp, coalesce(p_new_ten_sp,''), coalesce(p_new_so_khuon,''),
    p_new_kh_ca, coalesce(p_new_kh_tuan,0), 0, 0, coalesce(v_old.nv_ca_ngay,''), coalesce(v_old.nv_ca_dem,''),
    'C3 - Đổi khuôn', p_gio_bat_dau_doi_khuon, 'Đổi khuôn từ ' || coalesce(v_old.ma_sp,''), 'Đang thực hiện đổi khuôn', coalesce(p_dam_nhiem,''),
    1, p_user, v_now, 0, 0, '', p_gio_bat_dau_doi_khuon, (v_win->>'end')::timestamptz, 0, v_carry_shot, null
  );

  if p_new_so_khuon is not null and p_new_ma_sp is not null then perform duc_ensure_mold_product_mapping(p_new_so_khuon, p_new_ma_sp); end if;
  begin perform duc_request_ipqc_check(v_new_id_dong, 'doi_khuon'); exception when others then null; end;

  return jsonb_build_object('ok', true, 'new_id_dong', v_new_id_dong, 'old_id_dong', p_old_id_dong, 'old_ma_sp', v_old.ma_sp, 'new_ma_sp', p_new_ma_sp, 'ma_may', v_old.ma_may);
end;
$$;
revoke execute on function duc_change_product(text, text, text, text, numeric, numeric, timestamptz, text, text) from anon;
grant execute on function duc_change_product(text, text, text, text, numeric, numeric, timestamptz, text, text) to authenticated;

-- ── updateShiftInputs_ ───────────────────────────────────────────────────
create or replace function duc_update_shift_inputs(
  p_id_dong text, p_so_shot_nong_khuon numeric, p_so_luong_ng numeric, p_phan_loai_ng text,
  p_so_shot_dau_ca numeric, p_so_shot_cuoi_ca numeric, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row record; v_pair record; v_cavity numeric; v_pair_cavity numeric;
  v_has_shot_range boolean; v_ng numeric; v_ng_auto boolean := false;
  v_shot_chay_that numeric; v_new_version bigint; v_now timestamptz := now();
begin
  if p_so_shot_nong_khuon is null or p_so_shot_nong_khuon < 0 then return jsonb_build_object('ok', false, 'error', 'Số shot nóng máy không hợp lệ'); end if;
  v_has_shot_range := p_so_shot_dau_ca is not null and p_so_shot_cuoi_ca is not null;
  if v_has_shot_range and p_so_shot_dau_ca < 0 then return jsonb_build_object('ok', false, 'error', 'Số shot đầu ca không hợp lệ'); end if;
  if v_has_shot_range and p_so_shot_cuoi_ca < 0 then return jsonb_build_object('ok', false, 'error', 'Số shot cuối ca không hợp lệ'); end if;

  select * into v_row from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng: ' || p_id_dong); end if;

  if v_has_shot_range then
    if p_so_shot_cuoi_ca < p_so_shot_dau_ca then return jsonb_build_object('ok', false, 'error', 'Số shot cuối ca phải ≥ số shot đầu ca'); end if;
    select cavity into v_cavity from master_products where ma_sp = v_row.ma_sp;
    v_shot_chay_that := p_so_shot_cuoi_ca - p_so_shot_dau_ca - p_so_shot_nong_khuon;
    if v_shot_chay_that < 0 then
      return jsonb_build_object('ok', false, 'error', 'Số shot nóng máy lớn hơn tổng số shot chạy trong ca (' || (p_so_shot_cuoi_ca - p_so_shot_dau_ca) || ') — kiểm tra lại số liệu');
    end if;
    if v_cavity is not null and v_cavity > 0 then
      v_ng := round(v_shot_chay_that * v_cavity - coalesce(v_row.tt_ca, 0));
      if v_ng < 0 then return jsonb_build_object('ok', false, 'error', 'NG tính ra âm (' || v_ng || ') — kiểm tra lại số shot đầu/cuối ca, shot nóng máy, hoặc TT ca'); end if;
      v_ng_auto := true;
    else
      v_ng := p_so_luong_ng;
      if v_ng is null or v_ng < 0 then return jsonb_build_object('ok', false, 'error', 'SP ' || v_row.ma_sp || ' chưa có cavity để tự tính NG — vui lòng nhập tay NG'); end if;
    end if;
  else
    v_ng := p_so_luong_ng;
    if v_ng is null or v_ng < 0 then return jsonb_build_object('ok', false, 'error', 'Số lượng NG không hợp lệ'); end if;
  end if;

  v_new_version := coalesce(v_row.version, 0) + 1;
  update duc_ca_hien_tai set
    so_shot_nong_khuon = p_so_shot_nong_khuon, so_luong_ng = v_ng, phan_loai_ng = coalesce(p_phan_loai_ng, ''),
    so_shot_dau_ca = case when v_has_shot_range then p_so_shot_dau_ca else so_shot_dau_ca end,
    so_shot_cuoi_ca = case when v_has_shot_range then p_so_shot_cuoi_ca else so_shot_cuoi_ca end,
    version = v_new_version, last_updated_by = p_user, last_updated_at = v_now
  where id_dong = p_id_dong;

  if v_has_shot_range then
    perform duc_set_last_machine_shot(v_row.ma_may, p_so_shot_cuoi_ca);
  end if;

  -- Khuôn kép: mirror shot đầu/cuối/nóng sang dòng cặp, tính lại NG theo cavity riêng
  if v_row.khuon_kep_voi is not null and v_row.khuon_kep_voi <> '' then
    select * into v_pair from duc_ca_hien_tai where id_dong = v_row.khuon_kep_voi;
    if found then
      if v_has_shot_range then
        select cavity into v_pair_cavity from master_products where ma_sp = v_pair.ma_sp;
        update duc_ca_hien_tai set
          so_shot_nong_khuon = p_so_shot_nong_khuon, so_shot_dau_ca = p_so_shot_dau_ca, so_shot_cuoi_ca = p_so_shot_cuoi_ca,
          so_luong_ng = case when v_pair_cavity is not null and v_pair_cavity > 0
            then greatest(0, round((p_so_shot_cuoi_ca - p_so_shot_dau_ca - p_so_shot_nong_khuon) * v_pair_cavity - coalesce(v_pair.tt_ca, 0)))
            else so_luong_ng end,
          version = coalesce(v_pair.version, 0) + 1, last_updated_by = p_user, last_updated_at = v_now
        where id_dong = v_row.khuon_kep_voi;
      else
        update duc_ca_hien_tai set so_shot_nong_khuon = p_so_shot_nong_khuon, version = coalesce(v_pair.version, 0) + 1,
          last_updated_by = p_user, last_updated_at = v_now
        where id_dong = v_row.khuon_kep_voi;
      end if;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'version', v_new_version, 'so_luong_ng', v_ng, 'ng_auto_calc', v_ng_auto);
end;
$$;
revoke execute on function duc_update_shift_inputs(text, numeric, numeric, text, numeric, numeric, text) from anon;
grant execute on function duc_update_shift_inputs(text, numeric, numeric, text, numeric, numeric, text) to authenticated;

-- ── deletePlan_ ──────────────────────────────────────────────────────────
create or replace function duc_delete_plan(p_id_dong text, p_reason text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare v_row record;
begin
  select * into v_row from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng: ' || p_id_dong); end if;
  if v_row.open_gio_phat_sinh is not null then
    return jsonb_build_object('ok', false, 'error', 'Dòng này đang có sự cố mở. Vui lòng xử lý xong trước khi xoá kế hoạch.');
  end if;
  if coalesce(v_row.tt_ca, 0) > 0 then
    return jsonb_build_object('ok', false, 'error', 'Máy này đã có sản lượng thực tế (' || v_row.tt_ca || ' pcs). Không thể xoá kế hoạch.');
  end if;
  delete from duc_ca_hien_tai where id_dong = p_id_dong;
  return jsonb_build_object('ok', true, 'deleted_id_dong', p_id_dong, 'ma_may', v_row.ma_may, 'ma_sp', v_row.ma_sp);
end;
$$;
revoke execute on function duc_delete_plan(text, text, text) from anon;
grant execute on function duc_delete_plan(text, text, text) to authenticated;

-- ── editOpenIncident_ ────────────────────────────────────────────────────
create or replace function duc_edit_open_incident(p_id_dong text, p_loai text, p_gio_phat_sinh timestamptz, p_van_de text, p_noi_dung_xu_ly text, p_dam_nhiem text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare v_row record; v_new_version bigint; v_now timestamptz := now();
begin
  select * into v_row from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng: ' || p_id_dong); end if;
  if v_row.open_gio_phat_sinh is null then return jsonb_build_object('ok', false, 'error', 'Dòng này không có sự cố đang mở để sửa'); end if;
  if p_gio_phat_sinh is not null and p_gio_phat_sinh > now() + interval '1 minute' then
    return jsonb_build_object('ok', false, 'error', 'Giờ phát sinh không được ở tương lai');
  end if;

  v_new_version := coalesce(v_row.version, 0) + 1;
  update duc_ca_hien_tai set
    open_loai_su_co = coalesce(p_loai, open_loai_su_co),
    open_gio_phat_sinh = coalesce(p_gio_phat_sinh, open_gio_phat_sinh),
    open_van_de = coalesce(p_van_de, open_van_de),
    open_noi_dung_xu_ly = coalesce(p_noi_dung_xu_ly, open_noi_dung_xu_ly),
    open_dam_nhiem = coalesce(p_dam_nhiem, open_dam_nhiem),
    version = v_new_version, last_updated_by = p_user, last_updated_at = v_now
  where id_dong = p_id_dong;

  return jsonb_build_object('ok', true, 'version', v_new_version);
end;
$$;
revoke execute on function duc_edit_open_incident(text, text, timestamptz, text, text, text, text) from anon;
grant execute on function duc_edit_open_incident(text, text, timestamptz, text, text, text, text) to authenticated;

-- ── extendMachineShift_ (phần Ca_hien_tai — phần TangCa_Log dùng insert thẳng từ client) ──
create or replace function duc_extend_machine_shift(p_id_dong text, p_gio_ket_thuc_moi timestamptz, p_ly_do text, p_nguoi_duyet text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row record; v_span_hours numeric; v_id_log text; v_so_phut_them numeric; v_now timestamptz := now();
begin
  if p_gio_ket_thuc_moi is null then return jsonb_build_object('ok', false, 'error', 'Thiếu giờ kết thúc mới'); end if;
  if p_ly_do is null or trim(p_ly_do) = '' then return jsonb_build_object('ok', false, 'error', 'Lý do tăng ca không được để trống'); end if;

  select * into v_row from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng: ' || p_id_dong); end if;
  if v_row.ma_sp is null or v_row.ma_sp = '' then return jsonb_build_object('ok', false, 'error', 'Dòng không có sản phẩm — không thể tăng ca'); end if;
  if v_row.sp_start_time is null or v_row.sp_end_time is null then
    return jsonb_build_object('ok', false, 'error', 'Dòng chưa có sp_start_time/sp_end_time.');
  end if;
  if p_gio_ket_thuc_moi <= v_row.sp_end_time then
    return jsonb_build_object('ok', false, 'error', 'Giờ kết thúc mới phải lớn hơn giờ hiện tại');
  end if;
  v_span_hours := extract(epoch from (p_gio_ket_thuc_moi - v_row.sp_start_time)) / 3600;
  if v_span_hours > 12 then
    return jsonb_build_object('ok', false, 'error', 'Tổng thời gian SP trên máy (' || round(v_span_hours, 1) || 'h) vượt quá 12h.');
  end if;

  v_so_phut_them := round(extract(epoch from (p_gio_ket_thuc_moi - v_row.sp_end_time)) / 60);
  update duc_ca_hien_tai set sp_end_time = p_gio_ket_thuc_moi, version = coalesce(version, 0) + 1,
    last_updated_by = p_user, last_updated_at = v_now
  where id_dong = p_id_dong;

  v_id_log := 'TC_' || to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'YYYYMMDD_HH24MISS') || '_' || v_row.ma_may;
  insert into duc_tangca_log (id_log, id_dong, ngay, ca, ma_may, ma_sp, gio_ket_thuc_cu, gio_ket_thuc_moi, so_phut_them, ly_do, nguoi_duyet, thoi_diem_ghi)
  values (v_id_log, p_id_dong, v_row.ngay, v_row.ca, v_row.ma_may, v_row.ma_sp, v_row.sp_end_time::text, p_gio_ket_thuc_moi::text, v_so_phut_them, trim(p_ly_do), coalesce(p_nguoi_duyet, p_user), v_now);

  return jsonb_build_object('ok', true, 'id_dong', p_id_dong, 'sp_end_time_new', p_gio_ket_thuc_moi, 'so_phut_them', v_so_phut_them);
end;
$$;
revoke execute on function duc_extend_machine_shift(text, timestamptz, text, text, text) from anon;
grant execute on function duc_extend_machine_shift(text, timestamptz, text, text, text) to authenticated;

-- ── recordMoldMaintenance_ (ShotKhuon.js) ───────────────────────────────────
create or replace function duc_record_mold_maintenance(p_ma_khuon text, p_ghi_chu text, p_nguong_bao_duong_moi numeric, p_nguong_lam_moi_moi numeric, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row record; v_now timestamptz := now(); v_stamp text; v_new_gc text;
  v_nguong_bd numeric; v_nguong_lm numeric;
begin
  if p_ma_khuon is null or trim(p_ma_khuon) = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã khuôn'); end if;
  select * into v_row from duc_shot_khuon where ma_khuon = trim(p_ma_khuon);
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy khuôn: ' || p_ma_khuon); end if;

  v_nguong_bd := coalesce(p_nguong_bao_duong_moi, v_row.nguong_bao_duong, 10000);
  v_nguong_lm := coalesce(p_nguong_lam_moi_moi, v_row.nguong_lam_moi, 100000);
  v_stamp := to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI');
  v_new_gc := coalesce(v_row.ghi_chu, '');
  if p_ghi_chu is not null and trim(p_ghi_chu) <> '' then
    v_new_gc := v_new_gc || (case when v_new_gc <> '' then E'\n' else '' end) || '[' || v_stamp || '] ' || trim(p_ghi_chu);
  end if;

  update duc_shot_khuon set
    lan_bao_duong_gan_nhat = v_now::date, shot_tai_lan_bao_duong_gan_nhat = coalesce(v_row.tong_shot_luy_ke, 0),
    nguong_bao_duong = v_nguong_bd, nguong_lam_moi = v_nguong_lm, ghi_chu = v_new_gc,
    trang_thai_khuon = duc_compute_mold_status(coalesce(v_row.tong_shot_luy_ke, 0), coalesce(v_row.tong_shot_luy_ke, 0), v_nguong_bd, v_nguong_lm),
    last_updated_at = v_now
  where ma_khuon = trim(p_ma_khuon);

  return jsonb_build_object('ok', true, 'ma_khuon', trim(p_ma_khuon), 'shot_at_maintenance', coalesce(v_row.tong_shot_luy_ke, 0));
end;
$$;
revoke execute on function duc_record_mold_maintenance(text, text, numeric, numeric, text) from anon;
grant execute on function duc_record_mold_maintenance(text, text, numeric, numeric, text) to authenticated;

-- ── resolveMoldIssuePending_ / confirmMoldIssueOutcome_ (VanDeKhuon.js) ───
create or replace function duc_resolve_mold_issue_pending(p_id_van_de text, p_noi_dung_xu_ly text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare v_now timestamptz := now();
begin
  if p_noi_dung_xu_ly is null or trim(p_noi_dung_xu_ly) = '' then return jsonb_build_object('ok', false, 'error', 'Chưa nhập nội dung đã xử lý'); end if;
  if not exists (select 1 from duc_van_de_khuon where id_van_de = p_id_van_de) then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy vấn đề khuôn: ' || p_id_van_de);
  end if;
  update duc_van_de_khuon set trang_thai = 'Chờ xác nhận', noi_dung_xu_ly = trim(p_noi_dung_xu_ly),
    nguoi_xu_ly = p_user, ngay_xu_ly = v_now::date, last_updated_at = v_now
  where id_van_de = p_id_van_de;
  return jsonb_build_object('ok', true, 'id_van_de', p_id_van_de);
end;
$$;
revoke execute on function duc_resolve_mold_issue_pending(text, text, text) from anon;
grant execute on function duc_resolve_mold_issue_pending(text, text, text) to authenticated;

create or replace function duc_confirm_mold_issue_outcome(p_id_van_de text, p_ket_qua text, p_ghi_chu text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row record; v_now timestamptz := now(); v_stamp text; v_new_gc text; v_tai_phat_moi numeric;
begin
  if p_ket_qua not in ('OK', 'Tai_phat') then return jsonb_build_object('ok', false, 'error', 'Kết quả xác nhận không hợp lệ'); end if;
  select * into v_row from duc_van_de_khuon where id_van_de = p_id_van_de;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy vấn đề khuôn: ' || p_id_van_de); end if;

  v_stamp := to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI');
  v_new_gc := coalesce(v_row.ghi_chu, '');

  if p_ket_qua = 'OK' then
    v_new_gc := v_new_gc || (case when v_new_gc <> '' then E'\n' else '' end) || '[' || v_stamp || '] Xác nhận OK bởi ' || p_user || (case when p_ghi_chu is not null and p_ghi_chu <> '' then ' — ' || p_ghi_chu else '' end);
    update duc_van_de_khuon set trang_thai = 'Đã đóng', ket_qua_xac_nhan = 'OK', ghi_chu = v_new_gc,
      ngay_xac_nhan = v_now::date, nguoi_xac_nhan = p_user, last_updated_at = v_now
    where id_van_de = p_id_van_de;
  else
    v_tai_phat_moi := coalesce(v_row.lan_tai_phat, 0) + 1;
    v_new_gc := v_new_gc || (case when v_new_gc <> '' then E'\n' else '' end) || '[' || v_stamp || '] Tái phát lần ' || v_tai_phat_moi || ' — xác nhận bởi ' || p_user || (case when p_ghi_chu is not null and p_ghi_chu <> '' then ' — ' || p_ghi_chu else '' end);
    update duc_van_de_khuon set trang_thai = 'Mở', ket_qua_xac_nhan = 'Tái phát', lan_tai_phat = v_tai_phat_moi, ghi_chu = v_new_gc,
      ngay_xac_nhan = v_now::date, nguoi_xac_nhan = p_user, last_updated_at = v_now
    where id_van_de = p_id_van_de;
  end if;

  return jsonb_build_object('ok', true, 'id_van_de', p_id_van_de, 'ket_qua', p_ket_qua);
end;
$$;
revoke execute on function duc_confirm_mold_issue_outcome(text, text, text, text) from anon;
grant execute on function duc_confirm_mold_issue_outcome(text, text, text, text) to authenticated;
