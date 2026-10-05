-- D64: dọn tiếp sau D63 — đưa các máy chạy ca đêm 05/10/2026 về đúng "Ca đêm 05/10".
--
-- Hiện trạng (sau các thao tác nhầm tối 05/10):
--   * 18:12 trưởng ca kết nhầm "Ca đêm 05/10" (ca vừa bắt đầu) → báo cáo rỗng
--     05102026_Cadem (Kẽm 190T, TT 0) + Kẽm 190T bị đẩy sang "Ca ngày 06/10".
--   * 18:21 "Gán kế hoạch" cho DC4/5/6/7/8/10/11 nhưng rơi vào "Ca ngày 05/10"
--     (ca đã kết) → tt_ca hiện lại sản lượng ban ngày, và nếu kết ca lại sẽ ghi
--     đè báo cáo Ca ngày 05/10 vừa sửa ở D63.
-- Theo xác nhận của user: ca đêm nay chạy DC4,5,6,7,8,11 + Kẽm 190T; DC10 nghỉ.
--
--   1. DC10: xoá dòng 05102026_Cangay_DC10_OKA-GMN-01 + checkpoint IPQC chờ kiểm.
--   2. DC4/5/6/7/8/11: chuyển Ca ngày → Ca đêm 05/10, tính lại id_dong (bất biến
--      id_dong), khung giờ sp_start/sp_end, dời checkpoint IPQC chờ kiểm theo.
--   3. Kẽm 190T: xoá báo cáo rỗng 05102026_Cadem + dòng lịch sử TT 0 của nó,
--      đưa dòng 06102026_Cangay_Kem190T_… về Ca đêm 05/10.
--   4. Tính lại tt_ca cho 7 dòng theo khung giờ ca đêm.
--
-- Chạy 1 lần trên Supabase project PRODUCTION.

begin;

-- 1. DC10 không chạy đêm nay
delete from duc_ipqc_checkpoint where id_dong = '05102026_Cangay_DC10_OKA-GMN-01' and trang_thai = 'cho_kiem';
delete from duc_ca_hien_tai where id_dong = '05102026_Cangay_DC10_OKA-GMN-01';

-- 3a. Báo cáo ca đêm kết nhầm lúc 18:12
delete from duc_lich_su_san_xuat where ngay = '2026-10-05' and ca = 'Ca đêm';
delete from duc_bao_cao_ca where id_bao_cao = '05102026_Cadem';

-- 2 + 3b. Chuyển 7 dòng sang Ca đêm 05/10
create temp table d64_map on commit drop as
select id_dong as old_id,
       duc_make_id_dong('2026-10-05', 'Ca đêm', ma_may, ma_sp) as new_id,
       ma_may, ma_sp
from duc_ca_hien_tai
where id_dong in (
  '05102026_Cangay_DC4_TTI-PUM-03', '05102026_Cangay_DC5_AST-PAN-01', '05102026_Cangay_DC6_EXE-PLT-01',
  '05102026_Cangay_DC7_FCC-KPH-01', '05102026_Cangay_DC8_TTI-MOT-05', '05102026_Cangay_DC11_TTI-MOT-01',
  '06102026_Cangay_Kem190T_YHS-HAN-01'
);

do $$
begin
  if (select count(*) from d64_map) <> 7 then
    raise exception 'D64: kỳ vọng 7 dòng, thấy %', (select count(*) from d64_map);
  end if;
  if exists (select 1 from duc_ca_hien_tai c join d64_map m on c.id_dong = m.new_id) then
    raise exception 'D64: id_dong ca đêm đã tồn tại — dừng để tránh trùng dòng';
  end if;
end $$;

update duc_ca_hien_tai c set
  id_dong         = m.new_id,
  ngay            = '2026-10-05',
  ca              = 'Ca đêm',
  tuan_sx         = duc_iso_week('2026-10-05'),
  sp_start_time   = (duc_get_shift_window('2026-10-05', '2 ca 12h', 'Ca đêm')->>'start')::timestamptz,
  sp_end_time     = (duc_get_shift_window('2026-10-05', '2 ca 12h', 'Ca đêm')->>'end')::timestamptz,
  version         = coalesce(version, 0) + 1,
  last_updated_by = 'system@D64',
  last_updated_at = now()
from d64_map m
where c.id_dong = m.old_id;

update duc_ipqc_checkpoint k set id_dong = m.new_id, ngay = '2026-10-05', ca = 'Ca đêm'
from d64_map m
where k.id_dong = m.old_id and k.trang_thai = 'cho_kiem';

-- 4. tt_ca theo khung giờ ca đêm
select duc_recompute_tt_ca(ma_may, ma_sp) from d64_map;

commit;
