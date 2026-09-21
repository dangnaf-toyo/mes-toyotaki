-- D53: gộp thủ công báo cáo "Ca ngày 21/09/2026" (id_bao_cao = 21092026_Cangay)
-- để bao gồm cả 5 máy DC4-8 — chúng bị kẹt ở "Ca ngày 20/09" (chưa kết ca từ
-- hôm trước) nên không có mặt lúc trưởng ca kết ca "Ca ngày 21/09" lúc 11:04
-- sáng nay (chỉ ghi nhận đúng DC10/DC11/Kẽm 190T — 3 máy). Sau khi đóng nốt
-- backlog, DC4-8 đã có số liệu thật cho đúng "Ca ngày 21/09" (dòng
-- 21092026_Cangay_DC{4..8}_...) nhưng đã bị dòng "Ca đêm 21/09" mới đè lên,
-- nên duc_end_shift() gọi lại sẽ không thấy — phải cộng thủ công.
--
-- Các trường CỘNG DỒN được (so_may, KH, TT, sự cố, phút dừng, NG, shot) —
-- chính xác 100%. Riêng OEE/Availability/Performance/Quality là TỶ LỆ, không
-- cộng được — ƯỚC LƯỢNG bằng weighted average theo sản lượng (tt_ca) giữa
-- số liệu gốc 3 máy và số liệu tính lại cho 5 máy DC4-8 (cycle_time_s theo
-- master_products, break 12:00-12:45 theo duc_get_break_window, không có sự
-- cố nào log cho DC4-8 trong khung giờ này). Xem hội thoại/agent để đối
-- chiếu công thức nếu cần kiểm tra lại.
--
-- Chạy 1 lần trên Supabase project PRODUCTION.

update duc_bao_cao_ca set
  so_may_co_kh          = 8,
  so_may_hoan_thanh_kh  = 2,
  tong_kh_ca            = 15410,
  tong_tt_ca            = 14011,
  ty_le_hoan_thanh_ca   = 0.909214795587281,
  so_su_co_ca           = 4,
  tong_phut_dung_ca     = 399,
  oee_ca                = 0.7202303939321045,
  availability_ca       = 0.918504772705044,
  performance_ca        = 0.8017256212270607,
  quality_ca            = 1.0,
  tong_ng_ca            = 0,
  tong_shot_nong_khuon_ca = 97,
  nv_ca_bao_cao         = 'Đỗ Minh Tân, Nguyễn Văn Lâm, Hạ Văn Nam, Phùng Văn Sơn, Bùi Quyết Thắng',
  ghi_chu               = 'Gộp thủ công D53: cộng thêm 5 máy DC4-8 (kẹt ở Ca ngày 20/09, đóng backlog trễ) — OEE/Availability/Performance là ước lượng weighted theo sản lượng, không phải tính chính xác từng dòng.'
where id_bao_cao = '21092026_Cangay';
