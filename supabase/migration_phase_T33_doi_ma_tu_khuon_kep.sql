-- ============================================================================
-- Giai đoạn T33 — Đổi mã sản phẩm khi máy ĐANG chạy khuôn kép (2 cavity ra 2
-- SP khác nhau). Trước đây: nút ⇄ Đổi sản phẩm bị ẩn hẳn với dòng có
-- khuon_kep_voi (duc-dashboard.html canSwap), và duc_change_product_paired
-- tự chặn khi dòng cũ đã là khuôn kép ("không hỗ trợ đổi trực tiếp sang cặp
-- khác qua luồng này") — không có đường nào để đổi mã khi 1 hoặc cả 2 vế của
-- khuôn kép chạy xong, người dùng phải báo cáo mới phát hiện.
--
-- Quyết định vận hành (người dùng xác nhận qua hỏi đáp trong phiên):
--   - Đổi CẢ CẶP cùng lúc (không hỗ trợ đổi lẻ 1 vế trong khi vế kia vẫn
--     chạy) — giống lúc TẠO khuôn kép ban đầu, chỉ khác là áp dụng khi đang
--     ở trạng thái khuôn kép.
--   - SP mới có thể là 1 mã đơn (chuyển về khuôn đơn) hoặc 2 mã (khuôn kép
--     mới) — do người dùng chọn qua checkbox "Khuôn 2 cavity" có sẵn trong
--     modal Đổi sản phẩm.
--
-- duc_change_product_pair_out(p_old_id_dong, ...): p_old_id_dong là 1 trong 2
-- dòng của cặp hiện tại (tìm dòng kia qua khuon_kep_voi) — đóng CẢ 2 dòng cũ
-- (khuon_kep_voi = null, để không còn bị coi là "active" theo logic
-- isActive ở duc-dashboard.html: (idx===0) || (khuon_kep_voi && idSet.has)),
-- rồi tạo 1 hoặc 2 dòng SP mới y hệt mẫu duc_change_product /
-- duc_change_product_paired (pseudo sự cố "C3 - Đổi khuôn", mã sự cố
-- open_id_su_co, checkpoint IPQC 'doi_khuon').
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create or replace function duc_change_product_pair_out(
  p_old_id_dong text, p_so_khuon text, p_gio_bat_dau_doi_khuon timestamptz, p_dam_nhiem text, p_user text,
  p_new_a_ma_sp text, p_new_a_ten_sp text, p_new_a_kh_ca numeric, p_new_a_kh_tuan numeric,
  p_new_b_ma_sp text default null, p_new_b_ten_sp text default null, p_new_b_kh_ca numeric default null, p_new_b_kh_tuan numeric default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_old record; v_partner record; v_win jsonb; v_carry_shot numeric; v_now timestamptz := now();
  v_id_a text; v_id_b text; v_id_su_co text;
  v_has_b boolean := p_new_b_ma_sp is not null and trim(p_new_b_ma_sp) <> '';
begin
  if p_so_khuon is null or trim(p_so_khuon) = '' then return jsonb_build_object('ok', false, 'error', 'Bắt buộc nhập số khuôn'); end if;
  if p_gio_bat_dau_doi_khuon is null then return jsonb_build_object('ok', false, 'error', 'Chưa nhập giờ bắt đầu đổi khuôn'); end if;
  if p_new_a_ma_sp is null or trim(p_new_a_ma_sp) = '' or p_new_a_kh_ca is null or p_new_a_kh_ca <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Chưa nhập đủ Mã SP / KH ca cho SP mới');
  end if;
  if p_gio_bat_dau_doi_khuon > now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Giờ bắt đầu đổi khuôn không được ở tương lai'); end if;

  select * into v_old from duc_ca_hien_tai where id_dong = p_old_id_dong;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng SP cũ: ' || p_old_id_dong); end if;
  if v_old.khuon_kep_voi is null or v_old.khuon_kep_voi = '' then
    return jsonb_build_object('ok', false, 'error', 'Dòng SP cũ không phải khuôn kép — dùng luồng đổi SP thường (duc_change_product).');
  end if;
  if v_old.open_gio_phat_sinh is not null then return jsonb_build_object('ok', false, 'error', 'Dòng SP cũ đang có sự cố khác. Vui lòng xử lý xong trước khi đổi SP.'); end if;

  select * into v_partner from duc_ca_hien_tai where id_dong = v_old.khuon_kep_voi;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng ghép cặp: ' || v_old.khuon_kep_voi); end if;
  if v_partner.open_gio_phat_sinh is not null then
    return jsonb_build_object('ok', false, 'error', 'Dòng SP ghép cặp (' || coalesce(v_partner.ma_sp,'') || ') đang có sự cố khác. Vui lòng xử lý xong trước khi đổi SP.');
  end if;

  if trim(p_new_a_ma_sp) in (trim(coalesce(v_old.ma_sp,'')), trim(coalesce(v_partner.ma_sp,''))) then
    return jsonb_build_object('ok', false, 'error', 'SP mới A trùng với 1 trong 2 SP hiện tại của khuôn kép');
  end if;
  if v_has_b then
    if p_new_b_kh_ca is null or p_new_b_kh_ca <= 0 then return jsonb_build_object('ok', false, 'error', 'Chưa nhập KH ca cho SP mới B'); end if;
    if trim(p_new_b_ma_sp) = trim(p_new_a_ma_sp) then return jsonb_build_object('ok', false, 'error', 'SP A và SP B mới phải khác nhau'); end if;
    if trim(p_new_b_ma_sp) in (trim(coalesce(v_old.ma_sp,'')), trim(coalesce(v_partner.ma_sp,''))) then
      return jsonb_build_object('ok', false, 'error', 'SP mới B trùng với 1 trong 2 SP hiện tại của khuôn kép');
    end if;
  end if;

  v_id_a := duc_make_id_dong(v_old.ngay, v_old.ca, v_old.ma_may, p_new_a_ma_sp);
  if exists (select 1 from duc_ca_hien_tai where id_dong = v_id_a) then
    return jsonb_build_object('ok', false, 'error', 'Máy ' || v_old.ma_may || ' đã có dòng với SP ' || p_new_a_ma_sp || ' trong ca này');
  end if;
  if v_has_b then
    v_id_b := duc_make_id_dong(v_old.ngay, v_old.ca, v_old.ma_may, p_new_b_ma_sp);
    if exists (select 1 from duc_ca_hien_tai where id_dong = v_id_b) then
      return jsonb_build_object('ok', false, 'error', 'Máy ' || v_old.ma_may || ' đã có dòng với SP ' || p_new_b_ma_sp || ' trong ca này');
    end if;
  end if;

  v_win := duc_get_shift_window(v_old.ngay, v_old.phuong_an_ca, v_old.ca);
  v_carry_shot := greatest(coalesce(v_old.so_shot_cuoi_ca, 0), coalesce(v_partner.so_shot_cuoi_ca, 0));
  if v_carry_shot = 0 then
    select so_shot_cuoi_ca_gan_nhat into v_carry_shot from duc_shot_may where ma_may = v_old.ma_may;
  end if;

  v_id_su_co := duc_make_id_su_co(v_old.ma_may, p_gio_bat_dau_doi_khuon);

  insert into duc_ca_hien_tai (
    id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, kh_ca, kh_tuan, tt_ca, tt_tuan,
    nv_ca_ngay, nv_ca_dem, open_loai_su_co, open_gio_phat_sinh, open_van_de, open_noi_dung_xu_ly, open_dam_nhiem, open_id_su_co,
    version, last_updated_by, last_updated_at, so_shot_nong_khuon, so_luong_ng, phan_loai_ng,
    sp_start_time, sp_end_time, so_shot_khuon_snapshot, so_shot_dau_ca, so_shot_cuoi_ca, khuon_kep_voi
  ) values (
    v_id_a, v_old.ngay, v_old.ca, v_old.phuong_an_ca, duc_iso_week(v_old.ngay), v_old.ma_may, p_new_a_ma_sp, coalesce(p_new_a_ten_sp,''), p_so_khuon,
    p_new_a_kh_ca, coalesce(p_new_a_kh_tuan,0), 0, 0, coalesce(v_old.nv_ca_ngay,''), coalesce(v_old.nv_ca_dem,''),
    'C3 - Đổi khuôn', p_gio_bat_dau_doi_khuon,
    'Đổi khuôn từ ' || coalesce(v_old.ma_sp,'') || ' + ' || coalesce(v_partner.ma_sp,'') || ' (khuôn kép)',
    'Đang thực hiện đổi khuôn', coalesce(p_dam_nhiem,''), v_id_su_co,
    1, p_user, v_now, 0, 0, '', p_gio_bat_dau_doi_khuon, (v_win->>'end')::timestamptz, 0, v_carry_shot, null, v_id_b
  );

  if v_has_b then
    insert into duc_ca_hien_tai (
      id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, kh_ca, kh_tuan, tt_ca, tt_tuan,
      nv_ca_ngay, nv_ca_dem, open_loai_su_co, open_gio_phat_sinh, open_van_de, open_noi_dung_xu_ly, open_dam_nhiem, open_id_su_co,
      version, last_updated_by, last_updated_at, so_shot_nong_khuon, so_luong_ng, phan_loai_ng,
      sp_start_time, sp_end_time, so_shot_khuon_snapshot, so_shot_dau_ca, so_shot_cuoi_ca, khuon_kep_voi
    ) values (
      v_id_b, v_old.ngay, v_old.ca, v_old.phuong_an_ca, duc_iso_week(v_old.ngay), v_old.ma_may, p_new_b_ma_sp, coalesce(p_new_b_ten_sp,''), p_so_khuon,
      p_new_b_kh_ca, coalesce(p_new_b_kh_tuan,0), 0, 0, coalesce(v_old.nv_ca_ngay,''), coalesce(v_old.nv_ca_dem,''),
      'C3 - Đổi khuôn', p_gio_bat_dau_doi_khuon,
      'Đổi khuôn từ ' || coalesce(v_old.ma_sp,'') || ' + ' || coalesce(v_partner.ma_sp,'') || ' (khuôn kép)',
      'Đang thực hiện đổi khuôn', coalesce(p_dam_nhiem,''), v_id_su_co,
      1, p_user, v_now, 0, 0, '', p_gio_bat_dau_doi_khuon, (v_win->>'end')::timestamptz, 0, v_carry_shot, v_id_a
    );
    update duc_ca_hien_tai set khuon_kep_voi = v_id_b where id_dong = v_id_a;
  end if;

  -- Đóng cặp khuôn kép cũ: bỏ liên kết để 2 dòng cũ không còn bị tính là
  -- "active" mãi mãi theo isActive = (idx===0) || (khuon_kep_voi && idSet.has(...)).
  update duc_ca_hien_tai set khuon_kep_voi = null where id_dong in (v_old.id_dong, v_partner.id_dong);

  perform duc_ensure_mold_product_mapping(p_so_khuon, p_new_a_ma_sp);
  begin perform duc_request_ipqc_check(v_id_a, 'doi_khuon', v_id_su_co, p_gio_bat_dau_doi_khuon); exception when others then null; end;
  if v_has_b then
    perform duc_ensure_mold_product_mapping(p_so_khuon, p_new_b_ma_sp);
    begin perform duc_request_ipqc_check(v_id_b, 'doi_khuon', v_id_su_co, p_gio_bat_dau_doi_khuon); exception when others then null; end;
  end if;

  return jsonb_build_object(
    'ok', true, 'new_id_dong_a', v_id_a, 'new_id_dong_b', v_id_b,
    'old_id_dong_a', v_old.id_dong, 'old_id_dong_b', v_partner.id_dong,
    'old_ma_sp_a', v_old.ma_sp, 'old_ma_sp_b', v_partner.ma_sp,
    'new_ma_sp_a', p_new_a_ma_sp, 'new_ma_sp_b', p_new_b_ma_sp, 'ma_may', v_old.ma_may
  );
end;
$$;
revoke execute on function duc_change_product_pair_out(text, text, timestamptz, text, text, text, text, numeric, numeric, text, text, numeric, numeric) from anon;
grant execute on function duc_change_product_pair_out(text, text, timestamptz, text, text, text, text, numeric, numeric, text, text, numeric, numeric) to authenticated;
