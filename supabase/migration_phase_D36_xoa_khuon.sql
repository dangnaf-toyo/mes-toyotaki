-- ============================================================================
-- D36 — Xoá mã khuôn thừa/không dùng khỏi sổ đời khuôn (duc_shot_khuon), để
-- không còn hiện trong danh sách chọn khuôn (populateSoKhuonField ở
-- duc-dashboard.html) tránh trưởng ca chọn nhầm khuôn cũ/dư.
--
-- CHỈ xoá khỏi bảng gốc duc_shot_khuon — KHÔNG đụng lịch sử/audit trail đã có
-- (duc_khuon_bao_duong_log, duc_van_de_khuon, duc_ncp, duc_tem): các bản ghi
-- cũ vẫn giữ nguyên mã khuôn dạng text, chỉ không còn join được với sổ đời
-- khuôn (giống cách D35 xử lý đổi tên — không viết lại lịch sử).
--
-- CHẶN xoá nếu khuôn đang được DÙNG SỐNG: đang gán cho 1 trạm/máy đang chạy
-- (duc_ca_hien_tai) hoặc có trong kế hoạch tuần hiện tại/tương lai
-- (duc_khsx_tuan_plan, tuần >= tuần này) — phải đổi khuôn khác cho các dòng
-- đó trước, tránh xoá nhầm khuôn đang dùng thật.
-- ============================================================================

create or replace function duc_xoa_khuon(p_ma_khuon text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_ma text := trim(coalesce(p_ma_khuon, ''));
  v_monday date;
  v_so_ca_hien_tai int;
  v_so_khsx int;
begin
  if v_ma = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu mã khuôn');
  end if;

  if not exists (select 1 from duc_shot_khuon where ma_khuon = v_ma) then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy khuôn: ' || v_ma);
  end if;

  select count(*) into v_so_ca_hien_tai from duc_ca_hien_tai where so_khuon = v_ma;
  if v_so_ca_hien_tai > 0 then
    return jsonb_build_object('ok', false, 'error',
      'Khuôn đang được gán cho ' || v_so_ca_hien_tai || ' trạm/máy đang chạy — đổi khuôn khác cho các trạm đó trước khi xoá');
  end if;

  v_monday := date_trunc('week', now() at time zone 'Asia/Ho_Chi_Minh')::date;
  select count(*) into v_so_khsx from duc_khsx_tuan_plan where so_khuon = v_ma and tuan_bat_dau >= v_monday;
  if v_so_khsx > 0 then
    return jsonb_build_object('ok', false, 'error',
      'Khuôn đang có trong kế hoạch tuần hiện tại/tương lai (' || v_so_khsx || ' dòng) — sửa lại kế hoạch trước khi xoá');
  end if;

  delete from duc_shot_khuon where ma_khuon = v_ma;

  return jsonb_build_object('ok', true, 'ma_khuon', v_ma);
end;
$$;

revoke execute on function duc_xoa_khuon(text, text) from anon;
grant execute on function duc_xoa_khuon(text, text) to authenticated;
