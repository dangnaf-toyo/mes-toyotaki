-- ============================================================================
-- D46 — DC 10 (OKA-GMN-01) và Kẽm 190T (BPH-SHO-01) ngày 28/08/2026: kế hoạch
-- được thêm tay nhưng bị gắn NHẦM ca = 'Ca đêm' thay vì 'Ca ngày'.
--
-- Bối cảnh:
--   - Ca đêm 27/08 hai máy KHÔNG sản xuất → không có dòng ca trước để
--     carry-over. Dòng duy nhất của 2 mã SP này là dòng user tự thêm sáng
--     28/08. Lúc thêm, ô chọn ca trên dashboard đang ở "Ca đêm" (nhớ từ
--     localStorage lần trước) → submitPlan() ghi thành Ca đêm 28/08.
--   - Suốt Ca ngày, dòng mang nhãn Ca đêm → khung giờ 18:00–06:00. Tem gộp
--     cuối ca in lúc 17:19 (DC 10, 126 pcs) và 17:25 (Kẽm 190T, 900 pcs) nằm
--     TRƯỚC 18:00 → duc_recompute_tt_ca loại khỏi tt_ca, chỉ tt_tuan nhặt
--     được. Kết quả trên dashboard: tt_ca = 0 nhưng tt_tuan = 126 / 7700.
--   - Chưa hề kết ca Ca ngày 28/08 (duc_bao_cao_ca / duc_lich_su_san_xuat
--     không có bản ghi nào) — Ca ngày 28/08 vẫn là ca đang mở cho các máy
--     khác (vd DC 11 vẫn còn dòng 28082026_Cangay_DC11_...).
--
-- Đã xác nhận với user: kh_ca 300 (DC 10) / 2400 (Kẽm 190T) là số kế hoạch
-- đúng cho Ca ngày; thực tế Ca ngày chạy đúng 126 / 900 pcs (không còn tem
-- chưa in).
--
-- Sửa: đổi 2 dòng về ca = 'Ca ngày', DỰNG LẠI id_dong (28082026_Cangay_...)
-- — BẮT BUỘC, vì nếu để id_dong cũ chứa "Cadem", khi kết ca Ca ngày 28/08
-- thì duc_carry_over_shift tính v_new_id_dong = 28082026_Cadem_... trùng
-- ngay id_dong cũ → "if exists ... continue" → BỎ QUA tạo dòng Ca đêm mới.
-- Kèm sửa sp_start_time/sp_end_time về khung 06:00–18:00, giữ nguyên kh_ca
-- và toàn bộ cột open_* (không có sự cố mở). Sau đó duc_recompute_tt_ca để
-- tt_ca nhặt đúng 126 / 900.
--
-- An toàn chạy lại nhiều lần (idempotent — chỉ tác động khi dòng còn nhãn
-- 'Ca đêm' với đúng id_dong cũ).
--
-- SAU KHI CHẠY: kết ca Ca ngày 28/08 như bình thường qua app — carry-over
-- sẽ tự tạo dòng Ca đêm 28/08 sạch (tt_ca = 0) cho 2 máy này.
-- ============================================================================

do $$
declare
  r record;
  v_new_id_dong text;
  -- Khung giờ Ca ngày (2 ca 12h) ngày 28/08/2026, giờ VN 06:00–18:00:
  v_sp_start constant timestamptz := '2026-08-27T23:00:00+00';  -- 06:00 VN 28/08
  v_sp_end   constant timestamptz := '2026-08-28T11:00:00+00';  -- 18:00 VN 28/08
begin
  for r in
    select id_dong, ngay, ma_may, ma_sp
    from duc_ca_hien_tai
    where id_dong in (
      '28082026_Cadem_DC10_OKA-GMN-01',
      '28082026_Cadem_Kem190T_BPH-SHO-01'
    )
    and ca = 'Ca đêm'
  loop
    v_new_id_dong := duc_make_id_dong(r.ngay, 'Ca ngày', r.ma_may, r.ma_sp);

    if exists (select 1 from duc_ca_hien_tai where id_dong = v_new_id_dong) then
      raise notice 'Bỏ qua % : id_dong đích % đã tồn tại', r.id_dong, v_new_id_dong;
      continue;
    end if;

    update duc_ca_hien_tai
    set id_dong = v_new_id_dong,
        ca = 'Ca ngày',
        sp_start_time = v_sp_start,
        sp_end_time = v_sp_end,
        version = coalesce(version, 0) + 1,
        last_updated_by = 'system@fix_d46',
        last_updated_at = now()
    where id_dong = r.id_dong;

    raise notice 'Đổi % -> % (ca ngày)', r.id_dong, v_new_id_dong;
  end loop;
end $$;

-- ── Tính lại tt_ca/tt_tuan cho 2 dòng vừa đổi ─────────────────────────────
do $$
declare
  r record;
begin
  for r in
    select distinct ma_may, ma_sp from duc_ca_hien_tai
    where id_dong in (
      '28082026_Cangay_DC10_OKA-GMN-01',
      '28082026_Cangay_Kem190T_BPH-SHO-01'
    )
  loop
    perform duc_recompute_tt_ca(r.ma_may, r.ma_sp);
  end loop;
end $$;

-- ── Kiểm tra kết quả (kỳ vọng: tt_ca = 126 cho DC 10, 900 cho Kẽm 190T) ───
select id_dong, ngay, ca, phuong_an_ca, kh_ca, tt_ca, tt_tuan,
       sp_start_time, sp_end_time, last_updated_by
from duc_ca_hien_tai
where id_dong in (
  '28082026_Cangay_DC10_OKA-GMN-01',
  '28082026_Cangay_Kem190T_BPH-SHO-01'
)
order by id_dong;
