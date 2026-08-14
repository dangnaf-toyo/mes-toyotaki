-- ============================================================================
-- Phase 4, bước con 9 (bổ sung, phát hiện khi viết Index.html tĩnh) — các RPC
-- còn thiếu để giao diện chính hoạt động đầy đủ: changeProductPaired_,
-- configureMold_, editIncident_ (sự cố đã đóng), hàng đợi IPQC (getIpqcQueue_
-- + enrichRowsWithIpqcStatus_).
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
--
-- ĐÃ ĐƠN GIẢN HOÁ CÓ CHỦ ĐÍCH (ghi rõ để không quên): tính năng "Nạp KHSX
-- hàng loạt" (api_getWeeklyPlanSuggestions/getWeeklyPlanSuggestions_) đọc từ
-- sheet KHSX_WEEKLY_PLAN_SHEET — dữ liệu này CHƯA từng được import vào
-- Supabase (không nằm trong phạm vi khảo sát ban đầu). Tính năng này TẠM
-- KHÔNG có trong bản web tĩnh — trưởng ca vẫn gán kế hoạch thủ công từng máy
-- (`duc_upsert_plan`) như bình thường, chỉ mất tiện ích "gợi ý nạp hàng loạt
-- từ KHSX tuần". Cần làm thêm 1 script import riêng nếu muốn khôi phục.
-- ============================================================================

-- ── changeProductPaired_ — đổi sang khuôn kép (2 cavity, 2 SP khác nhau) ───
create or replace function duc_change_product_paired(
  p_old_id_dong text, p_so_khuon text, p_gio_bat_dau_doi_khuon timestamptz, p_dam_nhiem text,
  p_sp_a_ma_sp text, p_sp_a_ten_sp text, p_sp_a_kh_ca numeric, p_sp_a_kh_tuan numeric,
  p_sp_b_ma_sp text, p_sp_b_ten_sp text, p_sp_b_kh_ca numeric, p_sp_b_kh_tuan numeric,
  p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_old record; v_id_a text; v_id_b text; v_win jsonb; v_carry_shot numeric; v_now timestamptz := now();
begin
  if p_so_khuon is null or trim(p_so_khuon) = '' then return jsonb_build_object('ok', false, 'error', 'Bắt buộc nhập số khuôn'); end if;
  if p_gio_bat_dau_doi_khuon is null then return jsonb_build_object('ok', false, 'error', 'Chưa nhập giờ bắt đầu đổi khuôn'); end if;
  if p_sp_a_ma_sp is null or p_sp_a_kh_ca is null or p_sp_a_kh_ca <= 0 then return jsonb_build_object('ok', false, 'error', 'Chưa nhập đủ Mã SP A / KH ca A'); end if;
  if p_sp_b_ma_sp is null or p_sp_b_kh_ca is null or p_sp_b_kh_ca <= 0 then return jsonb_build_object('ok', false, 'error', 'Chưa nhập đủ Mã SP B / KH ca B'); end if;
  if trim(p_sp_a_ma_sp) = trim(p_sp_b_ma_sp) then return jsonb_build_object('ok', false, 'error', 'SP A và SP B phải khác nhau'); end if;
  if p_gio_bat_dau_doi_khuon > now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Giờ bắt đầu đổi khuôn không được ở tương lai'); end if;

  select * into v_old from duc_ca_hien_tai where id_dong = p_old_id_dong;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng SP cũ: ' || p_old_id_dong); end if;
  if v_old.open_gio_phat_sinh is not null then return jsonb_build_object('ok', false, 'error', 'Dòng SP cũ đang có sự cố khác. Vui lòng xử lý xong trước khi đổi SP.'); end if;
  if v_old.khuon_kep_voi is not null and v_old.khuon_kep_voi <> '' then
    return jsonb_build_object('ok', false, 'error', 'Dòng SP cũ đang là khuôn kép — không hỗ trợ đổi trực tiếp sang cặp khác qua luồng này.');
  end if;
  if trim(p_sp_a_ma_sp) = trim(coalesce(v_old.ma_sp, '')) or trim(p_sp_b_ma_sp) = trim(coalesce(v_old.ma_sp, '')) then
    return jsonb_build_object('ok', false, 'error', 'SP mới trùng với SP hiện tại');
  end if;

  v_id_a := duc_make_id_dong(v_old.ngay, v_old.ca, v_old.ma_may, p_sp_a_ma_sp);
  v_id_b := duc_make_id_dong(v_old.ngay, v_old.ca, v_old.ma_may, p_sp_b_ma_sp);
  if exists (select 1 from duc_ca_hien_tai where id_dong = v_id_a) then return jsonb_build_object('ok', false, 'error', 'Máy ' || v_old.ma_may || ' đã có dòng với SP ' || p_sp_a_ma_sp || ' trong ca này'); end if;
  if exists (select 1 from duc_ca_hien_tai where id_dong = v_id_b) then return jsonb_build_object('ok', false, 'error', 'Máy ' || v_old.ma_may || ' đã có dòng với SP ' || p_sp_b_ma_sp || ' trong ca này'); end if;

  v_win := duc_get_shift_window(v_old.ngay, v_old.phuong_an_ca, v_old.ca);
  v_carry_shot := v_old.so_shot_cuoi_ca;
  if v_carry_shot is null then select so_shot_cuoi_ca_gan_nhat into v_carry_shot from duc_shot_may where ma_may = v_old.ma_may; end if;

  insert into duc_ca_hien_tai (
    id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, kh_ca, kh_tuan, tt_ca, tt_tuan,
    nv_ca_ngay, nv_ca_dem, open_loai_su_co, open_gio_phat_sinh, open_van_de, open_noi_dung_xu_ly, open_dam_nhiem,
    version, last_updated_by, last_updated_at, so_shot_nong_khuon, so_luong_ng, phan_loai_ng,
    sp_start_time, sp_end_time, so_shot_khuon_snapshot, so_shot_dau_ca, so_shot_cuoi_ca, khuon_kep_voi
  ) values
  (v_id_a, v_old.ngay, v_old.ca, v_old.phuong_an_ca, duc_iso_week(v_old.ngay), v_old.ma_may, p_sp_a_ma_sp, coalesce(p_sp_a_ten_sp,''), p_so_khuon, p_sp_a_kh_ca, coalesce(p_sp_a_kh_tuan,0), 0, 0,
    coalesce(v_old.nv_ca_ngay,''), coalesce(v_old.nv_ca_dem,''), 'C3 - Đổi khuôn', p_gio_bat_dau_doi_khuon, 'Đổi khuôn từ ' || coalesce(v_old.ma_sp,''), 'Đang thực hiện đổi khuôn', coalesce(p_dam_nhiem,''),
    1, p_user, v_now, 0, 0, '', p_gio_bat_dau_doi_khuon, (v_win->>'end')::timestamptz, 0, v_carry_shot, null, v_id_b),
  (v_id_b, v_old.ngay, v_old.ca, v_old.phuong_an_ca, duc_iso_week(v_old.ngay), v_old.ma_may, p_sp_b_ma_sp, coalesce(p_sp_b_ten_sp,''), p_so_khuon, p_sp_b_kh_ca, coalesce(p_sp_b_kh_tuan,0), 0, 0,
    coalesce(v_old.nv_ca_ngay,''), coalesce(v_old.nv_ca_dem,''), 'C3 - Đổi khuôn', p_gio_bat_dau_doi_khuon, 'Đổi khuôn từ ' || coalesce(v_old.ma_sp,''), 'Đang thực hiện đổi khuôn', coalesce(p_dam_nhiem,''),
    1, p_user, v_now, 0, 0, '', p_gio_bat_dau_doi_khuon, (v_win->>'end')::timestamptz, 0, v_carry_shot, null, v_id_a);

  perform duc_ensure_mold_product_mapping(p_so_khuon, p_sp_a_ma_sp);
  perform duc_ensure_mold_product_mapping(p_so_khuon, p_sp_b_ma_sp);
  begin perform duc_request_ipqc_check(v_id_a, 'doi_khuon'); exception when others then null; end;
  begin perform duc_request_ipqc_check(v_id_b, 'doi_khuon'); exception when others then null; end;

  return jsonb_build_object('ok', true, 'id_dong_a', v_id_a, 'id_dong_b', v_id_b, 'old_id_dong', p_old_id_dong,
    'old_ma_sp', v_old.ma_sp, 'ma_sp_a', p_sp_a_ma_sp, 'ma_sp_b', p_sp_b_ma_sp, 'ma_may', v_old.ma_may);
end;
$$;
revoke execute on function duc_change_product_paired(text, text, timestamptz, text, text, text, numeric, numeric, text, text, numeric, numeric, text) from anon;
grant execute on function duc_change_product_paired(text, text, timestamptz, text, text, text, numeric, numeric, text, text, numeric, numeric, text) to authenticated;

-- ── configureMold_ ───────────────────────────────────────────────────────
create or replace function duc_configure_mold(
  p_ma_khuon text, p_ma_sp text, p_tong_shot_luy_ke numeric, p_shots_since_maintenance numeric,
  p_nguong_bao_duong_moi numeric, p_nguong_lam_moi_moi numeric, p_ghi_chu text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row record; v_new_total numeric; v_nguong_bd numeric; v_nguong_lm numeric; v_shot_bdgn numeric;
  v_now timestamptz := now(); v_stamp text; v_new_gc text; v_ma_khuon text := trim(coalesce(p_ma_khuon, ''));
begin
  if v_ma_khuon = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã khuôn'); end if;
  if p_ma_sp is null and p_tong_shot_luy_ke is null and p_shots_since_maintenance is null
     and p_nguong_bao_duong_moi is null and p_nguong_lam_moi_moi is null and (p_ghi_chu is null or trim(p_ghi_chu) = '') then
    return jsonb_build_object('ok', false, 'error', 'Chưa nhập giá trị nào để cấu hình');
  end if;

  select * into v_row from duc_shot_khuon where ma_khuon = v_ma_khuon;
  if not found then
    if p_ma_sp is null or trim(p_ma_sp) = '' then return jsonb_build_object('ok', false, 'error', 'Khuôn mới cần khai báo mã sản phẩm'); end if;
    insert into duc_shot_khuon (ma_khuon, ten_sp_gan_nhat, tong_shot_luy_ke, nguong_bao_duong, nguong_lam_moi,
      shot_tai_lan_bao_duong_gan_nhat, trang_thai_khuon, ghi_chu, last_updated_at)
    values (v_ma_khuon, trim(p_ma_sp), 0, 10000, 100000, 0, 'OK', '', v_now);
    select * into v_row from duc_shot_khuon where ma_khuon = v_ma_khuon;
  elsif p_ma_sp is not null and trim(p_ma_sp) <> '' then
    update duc_shot_khuon set ten_sp_gan_nhat = trim(p_ma_sp) where ma_khuon = v_ma_khuon;
  end if;

  v_new_total := coalesce(v_row.tong_shot_luy_ke, 0);
  if p_tong_shot_luy_ke is not null then
    if p_tong_shot_luy_ke < 0 then return jsonb_build_object('ok', false, 'error', 'Tổng shot lũy kế không hợp lệ'); end if;
    v_new_total := p_tong_shot_luy_ke;
  end if;

  v_shot_bdgn := coalesce(v_row.shot_tai_lan_bao_duong_gan_nhat, 0);
  if p_shots_since_maintenance is not null then
    if p_shots_since_maintenance < 0 then return jsonb_build_object('ok', false, 'error', 'Shot từ lần bảo dưỡng gần nhất không hợp lệ'); end if;
    v_shot_bdgn := v_new_total - p_shots_since_maintenance;
  end if;

  v_nguong_bd := coalesce(v_row.nguong_bao_duong, 10000);
  if p_nguong_bao_duong_moi is not null and p_nguong_bao_duong_moi > 0 then v_nguong_bd := p_nguong_bao_duong_moi; end if;
  v_nguong_lm := coalesce(v_row.nguong_lam_moi, 100000);
  if p_nguong_lam_moi_moi is not null and p_nguong_lam_moi_moi > 0 then v_nguong_lm := p_nguong_lam_moi_moi; end if;

  v_new_gc := coalesce(v_row.ghi_chu, '');
  if p_ghi_chu is not null and trim(p_ghi_chu) <> '' then
    v_stamp := to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI');
    v_new_gc := v_new_gc || (case when v_new_gc <> '' then E'\n' else '' end) || '[' || v_stamp || '] ' || trim(p_ghi_chu);
  end if;

  update duc_shot_khuon set
    tong_shot_luy_ke = v_new_total, shot_tai_lan_bao_duong_gan_nhat = v_shot_bdgn,
    nguong_bao_duong = v_nguong_bd, nguong_lam_moi = v_nguong_lm, ghi_chu = v_new_gc,
    trang_thai_khuon = duc_compute_mold_status(v_new_total, v_shot_bdgn, v_nguong_bd, v_nguong_lm),
    last_updated_at = v_now
  where ma_khuon = v_ma_khuon;

  return jsonb_build_object('ok', true, 'ma_khuon', v_ma_khuon);
end;
$$;
revoke execute on function duc_configure_mold(text, text, numeric, numeric, numeric, numeric, text, text) from anon;
grant execute on function duc_configure_mold(text, text, numeric, numeric, numeric, numeric, text, text) to authenticated;

-- ── editIncident_ (sửa sự cố ĐÃ ĐÓNG, trong duc_su_co_log) ─────────────────
create or replace function duc_edit_incident(
  p_id_ban_ghi text, p_loai_su_co text, p_gio_phat_sinh timestamptz, p_gio_tro_lai timestamptz,
  p_van_de text, p_noi_dung_xu_ly text, p_dam_nhiem text, p_ghi_chu text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row record; v_final_ps timestamptz; v_final_tl timestamptz; v_stamp text; v_audit text;
  v_current_gc text; v_user_gc text; v_new_gc text; v_now timestamptz := now();
begin
  select * into v_row from duc_su_co_log where id_ban_ghi = p_id_ban_ghi;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy bản ghi sự cố: ' || p_id_ban_ghi); end if;

  if p_gio_tro_lai is not null and p_gio_tro_lai > now() + interval '1 minute' then
    return jsonb_build_object('ok', false, 'error', 'Giờ trở lại không được ở tương lai');
  end if;

  v_final_ps := coalesce(p_gio_phat_sinh, case when p_gio_tro_lai is not null and p_gio_phat_sinh is null then v_row.gio_phat_sinh else null end);
  v_final_tl := coalesce(p_gio_tro_lai, case when p_gio_phat_sinh is not null and p_gio_tro_lai is null then v_row.gio_tro_lai else null end);
  if v_final_ps is not null and v_final_tl is not null and v_final_tl < v_final_ps then
    return jsonb_build_object('ok', false, 'error', 'Giờ trở lại phải sau giờ phát sinh (sau khi kết hợp giờ hiện tại)');
  end if;

  v_stamp := to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM');
  v_audit := '[edited ' || v_stamp || ' by ' || coalesce(p_user, 'unknown') || ']';
  v_current_gc := coalesce(v_row.ghi_chu, '');
  v_user_gc := trim(coalesce(p_ghi_chu, ''));
  v_new_gc := case when v_user_gc <> '' then v_user_gc || E'\n' || v_audit else v_audit end;
  -- Bảo tồn các audit-stamp trước đó (nếu có) — nối thêm vào cuối, giống bản gốc.
  if v_current_gc ~ '\[edited [0-9:/ ]+ by [^\]]+\]' then
    v_new_gc := v_new_gc || E'\n' || (
      select string_agg(m[1], E'\n') from regexp_matches(v_current_gc, '(\[edited [0-9:/ ]+ by [^\]]+\])', 'g') m
    );
  end if;

  update duc_su_co_log set
    loai_su_co = case when p_loai_su_co is not null and p_loai_su_co <> '' then p_loai_su_co else loai_su_co end,
    gio_phat_sinh = coalesce(v_final_ps, gio_phat_sinh),
    gio_tro_lai = coalesce(v_final_tl, gio_tro_lai),
    thoi_gian_dung_phut = case when v_final_ps is not null and v_final_tl is not null and (p_gio_phat_sinh is not null or p_gio_tro_lai is not null)
      then round(extract(epoch from (v_final_tl - v_final_ps)) / 60) else thoi_gian_dung_phut end,
    van_de = coalesce(p_van_de, van_de),
    noi_dung_xu_ly = coalesce(p_noi_dung_xu_ly, noi_dung_xu_ly),
    dam_nhiem = coalesce(p_dam_nhiem, dam_nhiem),
    ghi_chu = v_new_gc, van_de_edited = 'Yes'
  where id_ban_ghi = p_id_ban_ghi;

  return jsonb_build_object('ok', true, 'id_ban_ghi', p_id_ban_ghi, 'van_de_edited', 'Yes');
end;
$$;
revoke execute on function duc_edit_incident(text, text, timestamptz, timestamptz, text, text, text, text, text) from anon;
grant execute on function duc_edit_incident(text, text, timestamptz, timestamptz, text, text, text, text, text) to authenticated;

-- ── getIpqcQueue_ + enrichRowsWithIpqcStatus_ — đọc tổng hợp, public ───────
-- Trả sẵn dạng "map theo id_dong" (chỉ checkpoint ĐÃ TỚI HẠN thật, giống
-- enrichRowsWithIpqcStatus_ lọc da_den_han) để trang tĩnh JOIN thẳng vào rows
-- khi render — không cần dựng lại toàn bộ hàng đợi phía client.
create or replace function duc_get_ipqc_due_by_id_dong()
returns table(id_dong text, loai_kiem text, phut_da_troi int)
language plpgsql
stable
as $$
declare
  v_active_id_dong text[];
begin
  select array_agg(t.id_dong) into v_active_id_dong from (
    select cht.id_dong,
      row_number() over (partition by cht.ma_may order by cht.row_seq desc) as rn,
      cht.khuon_kep_voi
    from duc_ca_hien_tai cht
  ) t
  where t.rn = 1 or exists (
    select 1 from duc_ca_hien_tai c2
    where c2.id_dong = t.khuon_kep_voi
      and (select rn2.rn from (select cht2.id_dong, row_number() over (partition by cht2.ma_may order by cht2.row_seq desc) as rn from duc_ca_hien_tai cht2) rn2 where rn2.id_dong = t.khuon_kep_voi) = 1
  );

  return query
  select cp.id_dong, cp.loai_kiem,
    round(extract(epoch from (now() - cp.han_kiem)) / 60)::int as phut_da_troi
  from duc_ipqc_checkpoint cp
  where cp.trang_thai = 'cho_kiem'
    and cp.id_dong = any(v_active_id_dong)
    and round(extract(epoch from (now() - cp.han_kiem)) / 60) >=
      case when cp.loai_kiem = 'dinh_ky' then 120 else 0 end; -- CONFIG.IPQC_CHECK_INTERVAL_MIN = 120
end;
$$;
