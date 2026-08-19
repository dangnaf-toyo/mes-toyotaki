-- ============================================================================
-- Giai đoạn 20 — Sửa lỗi của chính migration_phase_D19: D19 gán nhầm DC8
-- sang phương án "2 ca 12h" (Ca ngày/Ca đêm) dựa theo nhãn cũ (đã sai) của
-- chính máy DC8 từ 17/08 — trong khi thực tế TOÀN NHÀ MÁY đang chạy phương
-- án "2 ca 8h" (Ca 1/Ca 2), xác nhận qua duc_bao_cao_ca hôm nay:
--   (2026-08-19, Ca 1) kết ca lúc 13:52 VN — phương án "2 ca 8h"
--   (2026-08-19, Ca 2) kết ca lúc 22:05 VN — phương án "2 ca 8h"
-- Vì dòng DC8 mang nhãn "Ca đêm" (không khớp "Ca 1"/"Ca 2"), nó bị bỏ sót
-- khỏi CẢ 2 lần kết ca hôm nay — lại treo "active" vĩnh viễn y hệt lỗi gốc,
-- dù cả nhà máy đã chuyển ca đúng.
--
-- File này: tạo dòng đúng theo lịch nhà máy đang dùng thật — (2026-08-20,
-- Ca 1, "2 ca 8h") — id_dong khớp với các máy khác (VD DC7) đã tự động
-- rotate sang đúng dòng này. Giữ nguyên tt_tuan (không mất sản lượng luỹ kế
-- tuần), tt_ca reset về 0 cho ca mới. Chuyển 2 checkpoint đang chờ sang
-- đúng dòng mới.
--
-- LƯU Ý QUAN TRỌNG (không tự động sửa được, cần bạn biết): sản lượng thật
-- DC8 làm trong khung giờ Ca 2 hôm nay (tt_ca = 1194 pcs, tính tới lúc sửa)
-- KHÔNG có trong báo cáo Ca 2 đã chốt (vì dòng DC8 khi đó mang nhãn "Ca đêm"
-- nên duc_end_shift bỏ qua không gộp) — báo cáo Ca 2 ngày 19/08 đang bị
-- THIẾU sản lượng của DC8. Muốn cộng bù vào báo cáo, cần sửa tay bảng
-- duc_bao_cao_ca (tong_tt_ca +1194, so_may_co_kh/so_may_hoan_thanh_kh nếu
-- cần) — báo tôi nếu muốn tôi làm bước này, tôi chưa tự ý đụng vào số liệu
-- báo cáo đã chốt.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

do $$
declare
  v_ma_may constant text := 'DC 8';
  v_ma_sp constant text := 'TTI-MOT-05';
  v_ngay constant date := '2026-08-20';
  v_ca constant text := 'Ca 1';
  v_phuong_an constant text := '2 ca 8h';
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
      1, 'manual_fix_dc8_20082026', now(),
      0, 0, '', (v_win->>'start')::timestamptz, (v_win->>'end')::timestamptz, 0,
      coalesce(v_stale.so_shot_cuoi_ca, v_last_shot, v_stale.so_shot_dau_ca), null, null
    );
    raise notice 'Đã tạo dòng mới % (tt_tuan giữ nguyên = %).', v_id_dong_moi, v_stale.tt_tuan;
  end if;

  update duc_ipqc_checkpoint
  set id_dong = v_id_dong_moi, ngay = v_ngay, ca = v_ca, phuong_an_ca = v_phuong_an,
    trang_thai = case when trang_thai = 'het_hieu_luc' then 'cho_kiem' else trang_thai end
  where id_checkpoint in ('IPQC_19082026_171101_DC8_doi_khuon', 'IPQC_19082026_212725_DC8_sau_su_co');

  raise notice 'Đã chuyển checkpoint đang chờ của DC 8 sang dòng %.', v_id_dong_moi;
end $$;
