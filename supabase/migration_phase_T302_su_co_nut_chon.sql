-- T302: danh mục nút chọn sự cố Đúc (Vấn đề + Xử lý) — nguồn Excel file/Danh_sach_su_co_thuong_gap_Duc_2026-11-21.xlsx
-- Sửa danh sách: sửa Excel rồi nhờ Claude nạp lại (chưa có màn sửa). loai = mã loại sự cố áp dụng (B1/F1 dùng chung).
create table if not exists public.duc_su_co_mau (
  ma         text primary key,
  loai       text[] not null,
  thu_tu     int not null default 0,
  van_de     text not null,
  xu_ly      text[] not null default '{}',
  hieu_luc   boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.duc_su_co_mau enable row level security;
revoke all on public.duc_su_co_mau from anon, authenticated;
grant select on public.duc_su_co_mau to anon, authenticated;
drop policy if exists "su_co_mau read" on public.duc_su_co_mau;
create policy "su_co_mau read" on public.duc_su_co_mau for select to public using (true);

insert into public.duc_su_co_mau (ma, loai, thu_tu, van_de, xu_ly) values
  ('CL-01', '{B1,F1}', 1, 'Bã trầu bề mặt', array['Đánh bóng vị trí bã trầu.','Giảm dầu xịt, thổi khô mặt khuôn.','Thông nước làm mát vùng lỗi.','Xuống khuôn đánh bóng.']::text[]),
  ('CL-02', '{B1,F1}', 2, 'Dính nhôm', array['Đục nhôm bằng que đồng, đánh bóng.','Tăng dầu xịt vị trí dính.','Thông nước làm mát vùng dính.','Xuống khuôn đánh bóng.']::text[]),
  ('CL-03', '{B1,F1}', 3, 'Kéo xước', array['Đánh bóng theo hướng rút sản phẩm.','Tăng dầu xịt vị trí xước.','Chỉnh pin đẩy đẩy đều.','Xuống khuôn đánh bóng.']::text[]),
  ('CL-04', '{B1,F1}', 4, 'NG chiều cao pin đẩy (lõm / lồi)', array['Mài ngắn pin đẩy cao.','Đệm lại bàn pin đẩy.','Vệ sinh bàn pin đẩy.','Thay pin đẩy mới.']::text[]),
  ('CL-05', '{B1,F1}', 5, 'Nhăn đen / nhăn răng / vết dòng chảy', array['Chạy nóng khuôn.','Giảm dầu xịt, thổi khô mặt khuôn.','Chờ nhôm đủ nhiệt.','Chỉnh điều kiện đúc theo phiếu.']::text[]),
  ('CL-06', '{B1,F1}', 6, 'Bong nhôm / phồng rộp', array['Sửa rò nước khuôn.','Giảm dầu xịt, thổi khô mặt khuôn.','Vệ sinh rãnh thoát khí, túi tràn.','Chỉnh điều kiện đúc theo phiếu.']::text[]),
  ('CL-07', '{B1,F1}', 7, 'NG kích thước / chật jig', array['Cách ly hàng, QC đo lại.','Thay chốt / lõi mòn.','Xuống khuôn sửa.','Lên khuôn dự phòng.']::text[]),
  ('CL-08', '{B1,F1}', 8, 'Vết lồi / thừa vật liệu', array['Mài, đánh bóng vị trí khuôn lõm.','Xuống khuôn hàn sửa.','Cách ly hàng, chờ QC duyệt.']::text[]),
  ('CL-09', '{B1,F1}', 9, 'NG lotmark', array['Thay lotmark đúng ngày / mã.','Vệ sinh, siết lại lotmark.','Chỉnh chiều cao lotmark.','Thay lotmark mới.']::text[]),
  ('CL-10', '{B1,F1}', 10, 'Dày bavia / mụn', array['Vệ sinh mặt phân khuôn, slider.','Chỉnh lực kẹp khuôn.','Chỉnh áp tăng áp theo phiếu.','Xuống khuôn sửa mặt phân khuôn.']::text[]),
  ('CL-11', '{B1,F1}', 11, 'Lõm / sứt / thiếu vật liệu / biến dạng', array['Chỉnh lượng rót.','Vệ sinh rãnh thoát khí, túi tràn.','Chỉnh pin đẩy, thời gian làm nguội.','Xuống khuôn sửa.']::text[]),
  ('CL-12', '{B1,F1}', 12, 'Rạn / nứt sản phẩm', array['Đánh bóng, tăng dầu xịt vị trí nứt.','Thông nước làm mát vùng nứt.','Chỉnh pin đẩy đẩy đều.','Khuôn nứt: mở sự cố A2.']::text[]),
  ('CL-13', '{B1,F1}', 13, 'Điều kiện máy không đạt tiêu chuẩn', array['Chỉnh điều kiện máy theo phiếu.','Cách ly hàng, báo IPQC kiểm lại.']::text[]),
  ('A2-01', '{A2}', 1, 'Gãy chốt / pin tạo lỗ / bạc', array['Lấy hết mảnh gãy, cách ly hàng.','Thay chốt mới.','Lên khuôn dự phòng.','Chạy bỏ cavity (QC + KT duyệt).']::text[]),
  ('A2-02', '{A2}', 2, 'Gãy pin đẩy sản phẩm', array['Lấy hết mảnh gãy, thay pin mới.','Vệ sinh lỗ pin, bôi mỡ chịu nhiệt.','Chỉnh bàn pin đẩy.','Lên khuôn dự phòng.']::text[]),
  ('A2-03', '{A2}', 3, 'Bắn nhôm mặt khuôn / slider / insert', array['Dừng máy, tránh xa mặt phân khuôn.','Vệ sinh mặt phân khuôn, slider.','Chỉnh lực kẹp.','Xuống khuôn sửa.']::text[]),
  ('A2-04', '{A2}', 4, 'Cong / kẹt / lệch chốt', array['Thay chốt mới.','Bôi mỡ chịu nhiệt chốt, bạc dẫn.','Tháo chốt lai vệ sinh.']::text[]),
  ('A2-05', '{A2}', 5, 'Dính sản phẩm trên khuôn', array['Gỡ sản phẩm bằng que đồng.','Đánh bóng, tăng dầu xịt vị trí dính.','Chỉnh hành trình pin đẩy.','Xuống khuôn động xử lý.']::text[]),
  ('A2-06', '{A2}', 6, 'Rò / tắc nước làm mát khuôn', array['Dừng máy, khoá van nước khuôn.','Thay ống, khớp nối, giấy nước.','Thông tắc đường nước.','Xuống khuôn xử lý đường nước.']::text[]),
  ('A2-07', '{A2}', 7, 'Vỡ / rạn khuôn (vị trí gate, viền)', array['Mài, đánh bóng vết rạn nhỏ.','Xuống khuôn hàn sửa.']::text[]),
  ('A2-08', '{A2}', 8, 'Hỏng / kẹt slider khuôn', array['Tháo slider, đục nhôm, vệ sinh.','Bôi mỡ chịu nhiệt slider.','Hàn sửa slider.','Lên khuôn dự phòng.']::text[]),
  ('A2-09', '{A2}', 9, 'Hỏng cổ khuôn', array['Thay cổ khuôn.','Căn đồng tâm cổ khuôn – ống liệu.']::text[]),
  ('A2-10', '{A2}', 10, 'Kẹt pin đẩy / giàn pin đẩy', array['Vệ sinh giàn pin đẩy.','Bôi mỡ chịu nhiệt pin đẩy.','Thay pin cong.','Xuống khuôn sửa.']::text[]),
  ('A2-11', '{A2}', 11, 'Lõi khuôn hỏng – đổi lõi', array['Đổi lõi khuôn.','Chạy nóng khuôn, IPQC kiểm.']::text[]),
  ('A2-12', '{A2}', 12, 'Khuôn dập dập lẹm vào sản phẩm', array['Căn chỉnh khuôn dập.','Mài / thay dao dập.']::text[]),
  ('A1-01', '{A1}', 1, 'Kẹt đầu típ / gãy cuống sản phẩm', array['Thay đầu típ.','Thay ống liệu.','Thông nước làm mát đầu típ.','Sửa bơm dầu bôi trơn típ.']::text[]),
  ('A1-02', '{A1}', 2, 'Lỗi tay gắp sản phẩm', array['Sửa tay gắp.','Thay dây hơi / van khí.','Căn chỉnh tay gắp, limit.']::text[]),
  ('A1-03', '{A1}', 3, 'Lỗi limit / cảm biến / đèn auto', array['Vệ sinh, chỉnh limit.','Siết ốc, đấu lại dây limit.','Thay limit / cảm biến.']::text[]),
  ('A1-04', '{A1}', 4, 'Rò / bục / thiếu dầu thủy lực', array['Thay roong / dây dầu.','Bổ sung dầu thủy lực.','Lau sạch dầu tràn.','Sửa bộ làm mát dầu.']::text[]),
  ('A1-05', '{A1}', 5, 'Rò nước làm mát (trục đẩy, đầu típ)', array['Quấn băng tan / thay roong.','Thay dây, van nước.','Thông tắc đường nước.']::text[]),
  ('A1-06', '{A1}', 6, 'Trục đẩy / ốp trục / zen nối', array['Thay bulông, đệm lại ốp trục.','Thay zen nối.','Căn chỉnh / thay trục đẩy.']::text[]),
  ('A1-07', '{A1}', 7, 'Dây hơi / dây khí / bơm dầu bôi trơn típ', array['Thay dây hơi / dây khí.','Thay bơm dầu bôi trơn.','Đấu nối lại dây.']::text[]),
  ('A1-08', '{A1}', 8, 'Lỗi giàn phun / giàn xịt', array['Thay van khí giàn xịt.','Thông / thay đầu phun.','Pha lại dầu xịt.','Sửa giàn xịt.']::text[]),
  ('A1-09', '{A1}', 9, 'Lỗi van / áp lực', array['Hiệu chỉnh van, áp lực.','Nạp nitơ bình tích áp.']::text[]),
  ('A1-10', '{A1}', 10, 'Lò ủ / lò giữ nhiệt: cháy dây nhiệt, không đủ nhiệt', array['Thay heater / dây nhiệt.','Thay cặp nhiệt.','Chờ lò đủ nhiệt.']::text[]),
  ('A1-11', '{A1}', 11, 'Lỗi gáo múc nhôm', array['Sửa gáo múc.','Thay vòng bi / củ gầu.','Chỉnh xích, lượng múc.']::text[]),
  ('A1-12', '{A1}', 12, 'Mất nguồn / sập nguồn 1 máy', array['Sửa nguồn, khởi động lại máy.','Chạy nóng khuôn, bỏ shot đầu.']::text[]),
  ('A1-13', '{A1}', 13, 'Bắn nhôm do máy thiếu lực kẹp', array['Chỉnh lực kẹp máy.','Căn song song tấm khuôn.']::text[]),
  ('A1-14', '{A1}', 14, 'Hỏng băng tải / cẩu trục', array['Sửa băng tải / cẩu trục.']::text[]),
  ('A3-01', '{A3}', 1, 'Mất điện toàn xưởng', array['Chờ có điện.','Chờ lò đủ nhiệt, chạy nóng khuôn.']::text[]),
  ('A3-02', '{A3}', 2, 'Chưa có / mất nước làm mát, khí nén toàn xưởng', array['Chờ có nước / khí nén.','Chạy nóng khuôn.']::text[]),
  ('B2-01', '{B2}', 1, 'Nhiệt độ nhôm / kẽm thấp dưới tiêu chuẩn', array['Chờ nhôm / kẽm đủ nhiệt.','Báo Tổ Thiết bị kiểm tra lò.','Cách ly hàng đúc lúc nhiệt thấp.']::text[]),
  ('B2-02', '{B2}', 2, 'Thành phần vật liệu đầu vào NG', array['Ngừng dùng lô NG, ghi số lô.','Cách ly hàng đã đúc.','Đổi lô nhôm / kẽm khác.']::text[]),
  ('C1-01', '{C1}', 1, 'Đổi khuôn do KHSX thay đổi đột xuất', array['Đổi khuôn theo KHSX mới.','Chạy nóng khuôn, IPQC kiểm.']::text[]),
  ('C1-02', '{C1}', 2, 'Đúc mẫu (khuôn mới, mẫu cho khách)', array['Lên khuôn mẫu, đúc mẫu.','Giao mẫu cho QC.','Lên lại khuôn theo KHSX.']::text[]),
  ('C1-03', '{C1}', 3, 'Họp / liên hoan công ty', array['Dừng máy theo lịch công ty.']::text[]),
  ('C1-04', '{C1}', 4, 'Thay insert / đổi nguyên liệu', array['Thay insert.','Vớt kẽm cũ, nấu kẽm mới.','Chờ đổi kế hoạch.']::text[]),
  ('C1-05', '{C1}', 5, 'Thay lotmark đầu tháng', array['Thay lotmark tháng mới.','Chạy nóng khuôn, kiểm lotmark.']::text[]),
  ('C1-06', '{C1}', 6, 'Đúc test khuôn sau sửa chữa, cải tiến', array['Đúc test, giao QC xác nhận.','Chạy lại theo KHSX.']::text[]),
  ('C2-01', '{C2}', 1, 'Hết nhôm lò ủ', array['Chờ cấp nhôm.','Sấy khô nhôm trước khi nạp lò.','Chờ lò đủ nhiệt.','Làm việc khác theo phân công.']::text[]),
  ('C2-02', '{C2}', 2, 'Hết linh kiện lắp kèm', array['Chờ cấp linh kiện.']::text[]),
  ('C3-01', '{C3}', 1, 'Đổi khuôn theo KHSX tuần', array['Gia nhiệt khuôn mới trước.','Xuống khuôn cũ, lên khuôn mới.','Thay hệ thống đẩy (φ60/70/80).','Chạy nóng khuôn, IPQC kiểm.']::text[]),
  ('C3-02', '{C3}', 2, 'Hoàn thiện khuôn sau khi lên', array['Lắp đường nước, kiểm tra rò.','Chỉnh xịt dầu, xịt khí.','Khò nóng khuôn, đầu phun.']::text[]),
  ('C3-03', '{C3}', 3, 'Chờ QC xác nhận sau đổi khuôn', array['Giao sản phẩm đầu cho IPQC.']::text[]),
  ('D1-01', '{D1}', 1, 'Thiếu người đứng máy (nghỉ, xin về sớm)', array['Chờ bố trí người.','Bổ sung người, chạy lại máy.','Vệ sinh máy, sắp xếp khu vực.']::text[]),
  ('D2-01', '{D2}', 1, 'Đào tạo nhân viên mới', array['Hướng dẫn thao tác.','Trưởng ca đứng máy thay.']::text[]),
  ('E2-01', '{E2}', 1, 'Vệ sinh lò ủ theo kế hoạch', array['Vớt xỉ, cạo cặn thành lò.','Bổ sung bông cách nhiệt.','Chờ lò đủ nhiệt.']::text[]),
  ('E2-02', '{E2}', 2, 'Tổng vệ sinh 5S', array['Tổng vệ sinh 3S / 5S.']::text[]),
  ('E3-01', '{E3}', 1, 'Kiểm kê định kỳ', array['Kiểm kê NVL.']::text[]),
  ('E3-02', '{E3}', 2, 'Kiểm kê NVL đầu giờ', array['Kiểm kê NVL đầu ca.']::text[])
on conflict (ma) do update set loai = excluded.loai, thu_tu = excluded.thu_tu, van_de = excluded.van_de,
  xu_ly = excluded.xu_ly, hieu_luc = true, updated_at = now();
-- mã không còn trong Excel → tắt
update public.duc_su_co_mau set hieu_luc = false, updated_at = now()
 where ma <> all (array['CL-01','CL-02','CL-03','CL-04','CL-05','CL-06','CL-07','CL-08','CL-09','CL-10','CL-11','CL-12','CL-13','A2-01','A2-02','A2-03','A2-04','A2-05','A2-06','A2-07','A2-08','A2-09','A2-10','A2-11','A2-12','A1-01','A1-02','A1-03','A1-04','A1-05','A1-06','A1-07','A1-08','A1-09','A1-10','A1-11','A1-12','A1-13','A1-14','A3-01','A3-02','B2-01','B2-02','C1-01','C1-02','C1-03','C1-04','C1-05','C1-06','C2-01','C2-02','C3-01','C3-02','C3-03','D1-01','D2-01','E2-01','E2-02','E3-01','E3-02']);
