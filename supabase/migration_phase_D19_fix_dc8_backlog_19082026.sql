-- ============================================================================
-- Giai đoạn 19 — Sửa tay 1 lần: đưa máy DC 8 về đúng dòng của ngày/ca THẬT
-- (2026-08-19, Ca đêm) thay vì phải bấm "Kết ca" liên tục qua 4-5 ca ảo
-- (17/08 Ca đêm → 18/08 Ca ngày → 18/08 Ca đêm → 19/08 Ca ngày → ...) mà
-- các ca ảo đó không có sản lượng thật để báo cáo.
--
-- Bối cảnh: DC8 chưa "Kết ca" từ 17/08 tới hôm nay — người dùng đã bấm Kết
-- ca cho (17/08, Ca ngày), hệ thống tự tạo dòng kế tiếp là (17/08, Ca đêm)
-- theo đúng thiết kế (duc_carry_over_shift chỉ nhảy đúng 1 ca, không biết
-- đã qua 2 ngày thật). File này tạo thẳng dòng đúng của HÔM NAY, giữ
-- nguyên tt_tuan (không mất sản lượng luỹ kế tuần), và chuyển 2 checkpoint
-- IPQC thật (sự cố hôm nay, bị dính nhãn ngày/ca cũ 17/08) sang đúng dòng
-- mới — KHÔNG để chúng bị migration_phase_D18 đánh nhầm thành hết hiệu lực
-- (chạy file này TRƯỚC hay SAU D18 đều an toàn, xem bước cuối).
--
-- CHỈ áp dụng cho đúng máy DC 8 / ngày 2026-08-19 — không phải mẫu dùng lại
-- cho máy khác. Chạy trong Supabase SQL Editor, an toàn chạy lại nhiều lần.
-- ============================================================================

do $$
declare
  v_ma_may constant text := 'DC 8';
  v_ma_sp constant text := 'TTI-MOT-05';
  v_ngay constant date := '2026-08-19';
  v_ca constant text := 'Ca đêm';
  v_phuong_an constant text := '2 ca 12h';
  v_id_dong_moi text;
  v_stale record;
  v_win jsonb;
  v_last_shot numeric;
begin
  v_id_dong_moi := duc_make_id_dong(v_ngay, v_ca, v_ma_may, v_ma_sp);

  select * into v_stale from duc_ca_hien_tai
  where ma_may = v_ma_may order by row_seq desc limit 1;

  if v_stale is null then
    raise notice 'Không tìm thấy dòng nào cho máy % — bỏ qua.', v_ma_may;
    return;
  end if;

  if exists (select 1 from duc_ca_hien_tai where id_dong = v_id_dong_moi) then
    raise notice 'Dòng % đã tồn tại — bỏ qua bước tạo dòng mới.', v_id_dong_moi;
  else
    v_win := duc_get_shift_window(v_ngay, v_phuong_an, v_ca);
    select so_shot_cuoi_ca_gan_nhat into v_last_shot from duc_shot_may where ma_may = v_ma_may;

    insert into duc_ca_hien_tai (
      id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon,
      kh_ca, kh_tuan, tt_ca, tt_tuan, nv_ca_ngay, nv_ca_dem, version, last_updated_by, last_updated_at,
      so_shot_nong_khuon, so_luong_ng, phan_loai_ng, sp_start_time, sp_end_time, so_shot_khuon_snapshot,
      so_shot_dau_ca, so_shot_cuoi_ca, khuon_kep_voi
    ) values (
      v_id_dong_moi, v_ngay, v_ca, v_phuong_an, duc_iso_week(v_ngay), v_ma_may, v_ma_sp, v_stale.ten_sp, v_stale.so_khuon,
      v_stale.kh_ca, v_stale.kh_tuan, 0, v_stale.tt_tuan, coalesce(v_stale.nv_ca_ngay, ''), coalesce(v_stale.nv_ca_dem, ''),
      1, 'manual_fix_dc8_backlog_19082026', now(),
      0, 0, '', (v_win->>'start')::timestamptz, (v_win->>'end')::timestamptz, 0,
      coalesce(v_last_shot, v_stale.so_shot_dau_ca), null, null
    );
    raise notice 'Đã tạo dòng mới % (tt_tuan giữ nguyên = %).', v_id_dong_moi, v_stale.tt_tuan;
  end if;

  -- Chuyển 2 checkpoint sự cố hôm nay (đang dính nhãn ngày/ca cũ 17/08) sang
  -- đúng dòng mới, và mở lại "cho_kiem" nếu lỡ bị D18 đánh het_hieu_luc trước.
  update duc_ipqc_checkpoint
  set id_dong = v_id_dong_moi, ngay = v_ngay, ca = v_ca, phuong_an_ca = v_phuong_an,
    trang_thai = case when trang_thai = 'het_hieu_luc' then 'cho_kiem' else trang_thai end
  where id_checkpoint in ('IPQC_19082026_095612_DC8_sau_su_co', 'IPQC_19082026_171101_DC8_doi_khuon');

  raise notice 'Đã chuyển checkpoint sự cố hôm nay của DC 8 sang dòng %.', v_id_dong_moi;
end $$;
