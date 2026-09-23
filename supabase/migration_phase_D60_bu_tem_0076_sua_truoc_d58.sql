-- D60: Bù lần sửa tem TKD20260923-0076 (Kẽm 190T / EXE-SHO-01) 3200 → 50 pcs
-- được làm TRƯỚC khi chạy D58, nên trigger chưa có để cập nhật báo cáo.
-- Lịch sử Ca ngày 23/09 đang giữ 6350 (= 21 tem × 150 + 3200 số cũ); tổng tem
-- thật hiện tại = 3200 → trừ 3150 vào lịch sử + báo cáo ca qua đúng hàm D58.
-- Chỉ chạy khi số lịch sử vẫn là 6350 (tránh trừ 2 lần nếu chạy lại).
--
-- Chạy trên PRODUCTION (staging không có dữ liệu này — chạy cũng không đổi gì).

do $$
begin
  if exists (
    select 1 from duc_lich_su_san_xuat
    where ngay = '2026-09-23' and ca = 'Ca ngày' and ma_may = 'Kẽm 190T' and ma_sp = 'EXE-SHO-01' and tt_ca = 6350
  ) then
    perform duc_ls_dieu_chinh_tem('Kẽm 190T', 'EXE-SHO-01', '2026-09-23T10:40:00+00'::timestamptz, -3150);
  end if;
end $$;
