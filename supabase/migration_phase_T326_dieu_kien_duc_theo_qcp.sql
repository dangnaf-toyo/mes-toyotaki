-- T326: Rà soát danh mục thông số ĐK đúc theo file QCP mẫu (Bảng QLCL công đoạn — Đúc, DC-350J).
-- 1) Thêm nhóm TB — Thiết bị (kiểm thiết bị đầu ca theo QCP).
-- 2) Thêm 12 thông số cài đặt còn thiếu (VL07–08, PE15–17, NT12–15, PT10–12).
-- 3) Sửa tên/đơn vị cho khớp QCP: NT04, NT07, PE09, PE11 (bar → MPa). Chưa có phiếu nào nên an toàn.
-- 4) Bỏ ★ (Nhôm) ở mục QCP không có: VL03, PE06, PE10, NT01, NT05.
-- Giữ nguyên quy tắc: phiếu ghi Chuẩn (= điểm giữa khoảng QCP), trưởng ca tự chỉnh ±5%.

alter table public.duc_dk_thong_so drop constraint if exists duc_dk_thong_so_nhom_check;
alter table public.duc_dk_thong_so add constraint duc_dk_thong_so_nhom_check
  check (nhom in ('VL','PE','NT','PT','TB'));

update public.duc_dk_thong_so set ten = 'Thời gian làm nguội trong khuôn (thời gian Die)' where ma_ts = 'NT04';
update public.duc_dk_thong_so set ten = 'Thời gian vệ sinh khuôn 1 (thổi khí)'           where ma_ts = 'NT07';
update public.duc_dk_thong_so set ten = 'Thời gian tăng áp (lên áp)'                      where ma_ts = 'PE09';
update public.duc_dk_thong_so set ten = 'Áp khí N₂ bình tích áp ACC2', don_vi = 'MPa'     where ma_ts = 'PE11';
update public.duc_dk_thong_so set bat_buoc_nhom = false where ma_ts in ('VL03','PE06','PE10','NT01','NT05');

insert into public.duc_dk_thong_so
  (ma_ts, nhom, thu_tu, ten, don_vi, kieu, ap_dung, bat_buoc_nhom, bat_buoc_kem, phu_thuoc,
   goi_y_nhom_min, goi_y_nhom_max, goi_y_kem_min, goi_y_kem_max, goi_y_chu, ma_muc_td)
values
('VL07','VL',7,'Thời gian gáo múc trong lò','giây','so','nhom',false,false,null,null,null,null,null,'Theo SP',null),
('VL08','VL',8,'Thời gian gàu dừng chờ','giây','so','nhom',false,false,null,null,null,null,null,'Theo SP',null),
('PE15','PE',15,'Hành trình không tải','mm','so','ca_hai',false,false,null,null,null,null,null,'Theo máy',null),
('PE16','PE',16,'Thời gian bắt đầu tăng','giây','so','nhom',false,false,null,null,null,null,null,'Theo SP',null),
('PE17','PE',17,'Cảnh báo lực kẹp khuôn','%','so','ca_hai',false,false,null,90,110,90,110,null,null),
('NT12','NT',12,'Thời gian lùi phun','giây','so','ca_hai',false,false,null,null,null,null,null,'Theo SP',null),
('NT13','NT',13,'Cảnh báo vượt thời gian chu kỳ','giây','so','ca_hai',false,false,null,null,null,null,null,'Theo SP',null),
('NT14','NT',14,'Thời gian vệ sinh khuôn 2 (thổi khí)','giây','so','ca_hai',false,false,null,null,null,null,null,'Theo SP',null),
('NT15','NT',15,'Lượng dầu bôi trơn đầu típ','cc','so','nhom',false,false,null,0.5,2,null,null,null,'D17'),
('PT10','PT',10,'Vị trí đẩy sản phẩm','mm','so','ca_hai',false,false,null,null,null,null,null,'Theo SP',null),
('PT11','PT',11,'Thời gian chờ đẩy sản phẩm','giây','so','ca_hai',false,false,null,null,null,null,null,'Theo SP',null),
('PT12','PT',12,'Thời gian đẩy sản phẩm lùi','giây','so','ca_hai',false,false,null,null,null,null,null,'Theo SP',null),
-- TB — Thiết bị (kiểm 1 ca/lần, bằng mắt)
('TB01','TB',1,'Áp lực trong bình ACC2','MPa','so','nhom',false,false,null,13.0,13.5,null,null,null,null),
('TB02','TB',2,'Đồng hồ áp nguồn cấp G1 — mức cao nhất',null,'chu','nhom',false,false,null,null,null,null,null,'≤ 15 MPa',null),
('TB03','TB',3,'Đồng hồ áp nguồn cấp (đồng hồ 2) — mức cao nhất',null,'chu','nhom',false,false,null,null,null,null,null,'≤ 14,5 MPa',null),
('TB04','TB',4,'Mức dầu thuỷ lực trong thùng',null,'chu','ca_hai',false,false,null,null,null,null,null,'Trong vạch cho phép',null),
('TB05','TB',5,'Hệ thống ép khuôn',null,'chu','ca_hai',false,false,null,null,null,null,null,'Linh hoạt, không trở ngại',null),
('TB06','TB',6,'Hệ thống đẩy nhôm',null,'chu','nhom',false,false,null,null,null,null,null,'Linh hoạt, không trở ngại',null),
('TB07','TB',7,'Hệ thống gắp sản phẩm',null,'chu','ca_hai',false,false,null,null,null,null,null,'Linh hoạt, không trở ngại',null),
('TB08','TB',8,'Giàn phun',null,'chu','ca_hai',false,false,null,null,null,null,null,'Linh hoạt, không trở ngại',null),
('TB09','TB',9,'Hệ thống pin đẩy, bàn đẩy',null,'chu','ca_hai',false,false,null,null,null,null,null,'Linh hoạt, không trở ngại',null),
('TB10','TB',10,'Bôi chất chống dính lên gáo múc nhôm',null,'chu','nhom',false,false,null,null,null,null,null,'Bôi đều trên bề mặt gáo',null),
('TB11','TB',11,'Nước làm mát khuôn, đầu típ',null,'chu','ca_hai',false,false,null,null,null,null,null,'Cửa thoát có nước chảy ra',null),
('TB12','TB',12,'Khuôn, đầu típ',null,'chu','ca_hai',false,false,null,null,null,null,null,'Không rò nước, không bắn nhôm',null),
('TB13','TB',13,'Áp lực bình chất tách khuôn','MPa','so','ca_hai',false,false,null,0.3,0.5,0.3,0.5,null,null)
on conflict (ma_ts) do nothing;
