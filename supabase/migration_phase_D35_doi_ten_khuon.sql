-- ============================================================================
-- D35 — Đổi tên khuôn (mã khuôn `ma_khuon`/`so_khuon` trước giờ chỉ nhập 1 lần
-- lúc khai báo khuôn mới, không sửa lại được nếu gõ sai/muốn đổi mã).
--
-- QUYẾT ĐỊNH PHẠM VI (đã hỏi người dùng, chốt: chỉ áp dụng từ nay trở đi):
--   - Đổi PK của sổ đời khuôn `duc_shot_khuon` (giữ nguyên toàn bộ số shot,
--     ngưỡng bảo dưỡng, trạng thái — chỉ đổi mã định danh).
--   - Cập nhật các nơi đang dùng SỐNG: trạm đang chạy hiện tại
--     (`duc_ca_hien_tai.so_khuon` — đây là bảng STATE, không phải lịch sử) và
--     kế hoạch tuần hiện tại/tương lai (`duc_khsx_tuan_plan.so_khuon`, CHỈ các
--     tuần >= tuần này — tuần đã qua giữ nguyên như một mốc lịch sử kế hoạch).
--   - KHÔNG đụng tới lịch sử/audit trail: `duc_khuon_bao_duong_log.ma_khuon`,
--     `duc_van_de_khuon.ma_khuon`, `duc_ncp.so_khuon`, `duc_tem.so_khuon`/
--     `so_khuon_tt` — các bản ghi cũ giữ nguyên mã cũ, đặc biệt tem đã in vật
--     lý dán trên sản phẩm thực tế vẫn mang mã cũ nên không được viết đè.
-- ============================================================================

create or replace function duc_rename_khuon(p_ma_khuon_cu text, p_ma_khuon_moi text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_cu text := trim(coalesce(p_ma_khuon_cu, ''));
  v_moi text := trim(coalesce(p_ma_khuon_moi, ''));
  v_row duc_shot_khuon%rowtype;
  v_monday date;
  v_now timestamptz := now();
  v_so_ca_hien_tai int;
  v_so_khsx int;
begin
  if v_cu = '' or v_moi = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu mã khuôn cũ/mới');
  end if;
  if v_cu = v_moi then
    return jsonb_build_object('ok', false, 'error', 'Mã khuôn mới trùng mã cũ');
  end if;

  select * into v_row from duc_shot_khuon where ma_khuon = v_cu;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy khuôn: ' || v_cu);
  end if;
  if exists (select 1 from duc_shot_khuon where ma_khuon = v_moi) then
    return jsonb_build_object('ok', false, 'error', 'Mã khuôn mới đã tồn tại: ' || v_moi);
  end if;

  -- đổi PK bảng gốc: xoá dòng cũ, chèn dòng mới giữ nguyên toàn bộ dữ liệu,
  -- ghi lại vết đổi tên vào ghi_chu để tra cứu sau này
  delete from duc_shot_khuon where ma_khuon = v_cu;
  insert into duc_shot_khuon (
    ma_khuon, ten_sp_gan_nhat, tong_shot_luy_ke, nguong_bao_duong, nguong_lam_moi,
    lan_bao_duong_gan_nhat, shot_tai_lan_bao_duong_gan_nhat, trang_thai_khuon, ghi_chu,
    last_updated_at, chu_ky_bao_duong_ngay
  ) values (
    v_moi, v_row.ten_sp_gan_nhat, v_row.tong_shot_luy_ke, v_row.nguong_bao_duong, v_row.nguong_lam_moi,
    v_row.lan_bao_duong_gan_nhat, v_row.shot_tai_lan_bao_duong_gan_nhat, v_row.trang_thai_khuon,
    coalesce(v_row.ghi_chu, '') || case when coalesce(v_row.ghi_chu, '') = '' then '' else E'\n' end
      || '[Đổi tên từ "' || v_cu || '" ngày ' || to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
      || ' bởi ' || coalesce(nullif(trim(p_user), ''), '?') || ']',
    v_now, v_row.chu_ky_bao_duong_ngay
  );

  -- trạm đang chạy hiện tại (state, không phải lịch sử) — đổi hết
  update duc_ca_hien_tai set so_khuon = v_moi where so_khuon = v_cu;
  get diagnostics v_so_ca_hien_tai = row_count;

  -- kế hoạch tuần: chỉ tuần hiện tại trở về sau, giữ nguyên các tuần đã qua
  v_monday := date_trunc('week', v_now at time zone 'Asia/Ho_Chi_Minh')::date;
  update duc_khsx_tuan_plan set so_khuon = v_moi, updated_at = v_now
    where so_khuon = v_cu and tuan_bat_dau >= v_monday;
  get diagnostics v_so_khsx = row_count;

  return jsonb_build_object(
    'ok', true, 'ma_khuon_cu', v_cu, 'ma_khuon_moi', v_moi,
    'so_dong_ca_hien_tai_da_doi', v_so_ca_hien_tai, 'so_dong_khsx_da_doi', v_so_khsx
  );
end;
$$;

revoke execute on function duc_rename_khuon(text, text, text) from anon;
grant execute on function duc_rename_khuon(text, text, text) to authenticated;
