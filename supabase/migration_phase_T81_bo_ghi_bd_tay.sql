-- ============================================================================
-- T81 — Bỏ "Ghi BD" tay. Bảo dưỡng khuôn chỉ ghi qua KH bảo dưỡng tuần + check
-- sheet (duc_khuon_cs_luu: ảnh, hạng mục, Đạt mới reset shot).
--
-- 1) duc_ghi_lich_su_bao_duong: thu hồi quyền gọi (không xoá hàm — sổ đời khuôn
--    cũ vẫn giữ nguyên; cần mở lại thì grant lại).
-- 2) Chu kỳ bảo dưỡng theo ngày trước chỉ sửa được trong hộp Ghi BD -> chuyển
--    sang duc_configure_mold (hộp ✏ Sửa ở quan-ly-khuon.html): thêm tham số
--    p_chu_ky_bao_duong_ngay (null = giữ, 0 = bỏ chu kỳ).
--
-- Chạy trên CẢ 2 project (production + staging). Idempotent.
-- ============================================================================

revoke execute on function duc_ghi_lich_su_bao_duong from public, anon, authenticated;

drop function if exists duc_configure_mold(text, text, numeric, numeric, numeric, numeric, text, text);

create or replace function duc_configure_mold(
  p_ma_khuon text, p_ma_sp text, p_tong_shot_luy_ke numeric, p_shots_since_maintenance numeric,
  p_nguong_bao_duong_moi numeric, p_nguong_lam_moi_moi numeric, p_ghi_chu text, p_user text,
  p_chu_ky_bao_duong_ngay numeric default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row record; v_new_total numeric; v_nguong_bd numeric; v_nguong_lm numeric; v_shot_bdgn numeric;
  v_now timestamptz := now(); v_stamp text; v_new_gc text; v_ma_khuon text := trim(coalesce(p_ma_khuon, ''));
  v_chu_ky numeric;
begin
  if v_ma_khuon = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã khuôn'); end if;
  if p_ma_sp is null and p_tong_shot_luy_ke is null and p_shots_since_maintenance is null
     and p_nguong_bao_duong_moi is null and p_nguong_lam_moi_moi is null and p_chu_ky_bao_duong_ngay is null
     and (p_ghi_chu is null or trim(p_ghi_chu) = '') then
    return jsonb_build_object('ok', false, 'error', 'Chưa nhập giá trị nào để cấu hình');
  end if;
  if p_chu_ky_bao_duong_ngay is not null and p_chu_ky_bao_duong_ngay < 0 then
    return jsonb_build_object('ok', false, 'error', 'Chu kỳ bảo dưỡng không hợp lệ');
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

  v_chu_ky := v_row.chu_ky_bao_duong_ngay;
  if p_chu_ky_bao_duong_ngay is not null then v_chu_ky := nullif(round(p_chu_ky_bao_duong_ngay), 0); end if;

  v_new_gc := coalesce(v_row.ghi_chu, '');
  if p_ghi_chu is not null and trim(p_ghi_chu) <> '' then
    v_stamp := to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI');
    v_new_gc := v_new_gc || (case when v_new_gc <> '' then E'\n' else '' end) || '[' || v_stamp || '] ' || trim(p_ghi_chu);
  end if;

  update duc_shot_khuon set
    tong_shot_luy_ke = v_new_total, shot_tai_lan_bao_duong_gan_nhat = v_shot_bdgn,
    nguong_bao_duong = v_nguong_bd, nguong_lam_moi = v_nguong_lm, ghi_chu = v_new_gc,
    chu_ky_bao_duong_ngay = v_chu_ky,
    trang_thai_khuon = duc_compute_mold_status(v_new_total, v_shot_bdgn, v_nguong_bd, v_nguong_lm),
    last_updated_at = v_now
  where ma_khuon = v_ma_khuon;

  return jsonb_build_object('ok', true, 'ma_khuon', v_ma_khuon);
end;
$$;
revoke execute on function duc_configure_mold(text, text, numeric, numeric, numeric, numeric, text, text, numeric) from public, anon;
grant execute on function duc_configure_mold(text, text, numeric, numeric, numeric, numeric, text, text, numeric) to authenticated;
