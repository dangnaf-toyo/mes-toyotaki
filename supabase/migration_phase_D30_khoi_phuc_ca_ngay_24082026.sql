-- ============================================================================
-- D30 — Khôi phục dữ liệu Ca ngày 24/08/2026 sau khi các dòng duc_ca_hien_tai
-- bị xoá qua các lần kết ca dọn dẹp tồn đọng (23/08, 19/08, 17/08).
--
-- Dữ liệu GỐC (tem in, sự cố) vẫn còn nguyên trong duc_tem/duc_su_co_log
-- (2 bảng append-only, kết ca không đụng tới) — chỉ mất phần "dòng đang
-- chạy" (KH ca, số khuôn, người trực...). Dựng lại từ:
--   - duc_khsx_tuan_plan (KH tuần đã đăng ký) → suy ra KH ca = KH tuần/12
--   - duc_tem hôm nay → tt_ca thực tế (đã có sẵn, trigger sẽ tự tính lại)
--   - duc_su_co_log (quét theo khung giờ Ca ngày thật, không theo cột ngay
--     cũ) → 19 sự cố đã xác nhận, đang gắn nhãn cũ (ngay=23/08, ca="Ca 1")
--
-- DC 6 và DC 10 đều đổi SP giữa ca (có sự cố C3 "Đổi khuôn" xác nhận) → mỗi
-- máy có 2 dòng: 1 dòng lịch sử (SP đã đổi khỏi) + 1 dòng đang chạy hiện tại.
-- Kẽm 190T đã có sẵn 1 dòng hôm nay nhưng sai phương án ("Ca 2"/2 ca 8h thay
-- vì "Ca ngày"/2 ca 12h) → SỬA lại dòng đó, không tạo trùng.
--
-- KH ca là số ƯỚC TÍNH (KH tuần ÷ 12) — user cần xác nhận/sửa lại nếu trưởng
-- ca đã ghi số khác. DC 10/OKA-GJT-08 không có trong KHSX tuần NÀY (chỉ có ở
-- tuần trước, 17/08) — KH tạm lấy theo tuần trước, cần xác nhận riêng.
-- An toàn chạy lại nhiều lần (idempotent — insert bỏ qua nếu đã tồn tại).
-- ============================================================================

-- ── Sửa dòng Kẽm 190T đã có sẵn: đúng phương án Ca ngày/2 ca 12h ──────────
update duc_ca_hien_tai
set ca = 'Ca ngày',
    phuong_an_ca = '2 ca 12h',
    kh_ca = 1200,
    version = coalesce(version, 0) + 1,
    last_updated_by = 'system@fix_d30',
    last_updated_at = now()
where id_dong = '24082026_Ca2_Kem190T_BPH-SHO-01';

-- ── Tạo lại các dòng còn thiếu cho Ca ngày 24/08/2026 ──────────────────────
insert into duc_ca_hien_tai (
  id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon,
  kh_ca, kh_tuan, tt_ca, tt_tuan, so_shot_nong_khuon, so_luong_ng,
  sp_start_time, sp_end_time, version, last_updated_by, last_updated_at
) values
  ('24082026_Cangay_DC4_TTI-MOT-02', '2026-08-24', 'Ca ngày', '2 ca 12h', 'W35_2026', 'DC 4', 'TTI-MOT-02', 'MOTOR 9002', '',
    1417, 17000, 0, 0, 0, 0,
    '2026-08-23T23:00:00+00', null, 1, 'system@fix_d30', now()),
  ('24082026_Cangay_DC5_AST-PAN-01', '2026-08-24', 'Ca ngày', '2 ca 12h', 'W35_2026', 'DC 5', 'AST-PAN-01', 'Panel FR', '',
    1075, 12900, 0, 0, 0, 0,
    '2026-08-23T23:00:00+00', null, 1, 'system@fix_d30', now()),
  ('24082026_Cangay_DC6_EXE-OUT-01', '2026-08-24', 'Ca ngày', '2 ca 12h', 'W35_2026', 'DC 6', 'EXE-OUT-01', 'CL OUTER', 'OUT #2',
    500, 6000, 0, 0, 0, 0,
    '2026-08-23T23:00:00+00', '2026-08-24T04:00:00+00', 1, 'system@fix_d30', now()),
  ('24082026_Cangay_DC6_EXE-CEN-01', '2026-08-24', 'Ca ngày', '2 ca 12h', 'W35_2026', 'DC 6', 'EXE-CEN-01', 'CL CENTER', 'CEN #2',
    808, 9700, 0, 0, 0, 0,
    '2026-08-24T05:30:00+00', null, 1, 'system@fix_d30', now()),
  ('24082026_Cangay_DC7_FCC-OUT-01', '2026-08-24', 'Ca ngày', '2 ca 12h', 'W35_2026', 'DC 7', 'FCC-OUT-01', 'Outer K09', '',
    1458, 17500, 0, 0, 0, 0,
    '2026-08-23T23:00:00+00', null, 1, 'system@fix_d30', now()),
  ('24082026_Cangay_DC8_FCC-KFM-01', '2026-08-24', 'Ca ngày', '2 ca 12h', 'W35_2026', 'DC 8', 'FCC-KFM-01', 'KFM', 'KFM #67-70',
    1917, 23000, 0, 0, 0, 0,
    '2026-08-23T23:00:00+00', null, 1, 'system@fix_d30', now()),
  ('24082026_Cangay_DC10_OKA-GJT-02', '2026-08-24', 'Ca ngày', '2 ca 12h', 'W35_2026', 'DC 10', 'OKA-GJT-02', 'Ghế JUST ĐM Size SS', '',
    17, 200, 0, 0, 0, 0,
    '2026-08-23T23:00:00+00', '2026-08-24T07:32:00+00', 1, 'system@fix_d30', now()),
  ('24082026_Cangay_DC10_OKA-GJT-08', '2026-08-24', 'Ca ngày', '2 ca 12h', 'W35_2026', 'DC 10', 'OKA-GJT-08', 'Ghế JUST ĐM Size LL', '',
    17, 200, 0, 0, 0, 0,
    '2026-08-24T07:32:00+00', null, 1, 'system@fix_d30', now()),
  ('24082026_Cangay_DC11_PRE-W99-01', '2026-08-24', 'Ca ngày', '2 ca 12h', 'W35_2026', 'DC 11', 'PRE-W99-01', 'W-9904-0099R1', 'PRE #1',
    375, 4500, 0, 0, 0, 0,
    '2026-08-23T23:00:00+00', null, 1, 'system@fix_d30', now())
on conflict (id_dong) do nothing;

-- ── Gắn lại 19 sự cố về đúng Ca ngày 24/08 (đang bị nhãn cũ 23/08/"Ca 1") ──
update duc_su_co_log
set ngay = '2026-08-24',
    ca = 'Ca ngày'
where ngay = '2026-08-23' and ca = 'Ca 1'
  and gio_phat_sinh >= '2026-08-23T23:00:00+00' and gio_phat_sinh <= '2026-08-24T11:00:00+00';

-- ── Tính lại tt_ca/tt_tuan cho mọi dòng vừa tạo/sửa, khớp đúng tem đã in ──
do $$
declare
  r record;
begin
  for r in
    select distinct ma_may, ma_sp from duc_ca_hien_tai
    where ngay = '2026-08-24' and ca = 'Ca ngày'
  loop
    perform duc_recompute_tt_ca(r.ma_may, r.ma_sp);
  end loop;
end $$;
