-- T336: danh mục nút chọn dừng máy Gia công (Vấn đề + Xử lý) — giống Đúc (duc_su_co_mau, T302).
-- loai = mã lý do dừng ở gia-cong-dashboard (LOAI_DUNG: A1..E3). Admin sửa trực tiếp bảng (chưa có màn sửa).
create table if not exists public.gc_su_co_mau (
  ma         text primary key,
  loai       text[] not null check (cardinality(loai) > 0),
  thu_tu     int not null default 0,
  van_de     text not null check (btrim(van_de) <> ''),
  xu_ly      text[] not null default '{}',
  hieu_luc   boolean not null default true,
  nguoi_sua  text,
  updated_at timestamptz not null default now()
);
alter table public.gc_su_co_mau enable row level security;
revoke all on public.gc_su_co_mau from anon, authenticated;
grant select on public.gc_su_co_mau to anon, authenticated;
grant insert, update, delete on public.gc_su_co_mau to authenticated;
drop policy if exists "gc_su_co_mau read" on public.gc_su_co_mau;
create policy "gc_su_co_mau read" on public.gc_su_co_mau for select to public using (true);
drop policy if exists "gc_su_co_mau admin insert" on public.gc_su_co_mau;
create policy "gc_su_co_mau admin insert" on public.gc_su_co_mau for insert to authenticated
  with check (public.has_role(variadic array['admin']));
drop policy if exists "gc_su_co_mau admin update" on public.gc_su_co_mau;
create policy "gc_su_co_mau admin update" on public.gc_su_co_mau for update to authenticated
  using (public.has_role(variadic array['admin'])) with check (public.has_role(variadic array['admin']));
drop policy if exists "gc_su_co_mau admin delete" on public.gc_su_co_mau;
create policy "gc_su_co_mau admin delete" on public.gc_su_co_mau for delete to authenticated
  using (public.has_role(variadic array['admin']));

insert into public.gc_su_co_mau (ma, loai, thu_tu, van_de, xu_ly) values
  -- A1 — Sự cố máy CNC
  ('A1-01', '{A1}', 1, 'Máy báo alarm (NC / servo / trục chính)', array['Đọc mã alarm, chụp màn hình.','Reset alarm, chạy lại đầu chương trình.','Kiểm tra quá tải trục, kẹt phoi.','Báo Thiết bị sửa.']::text[]),
  ('A1-02', '{A1}', 2, 'Va đập máy (crash) / mất gốc toạ độ', array['Dừng khẩn, kiểm tra dao, đồ gá, trục chính.','Về gốc máy, kiểm lại gốc phôi (G54).','Chạy thử từng khối, giảm tốc.','Cách ly SP, QC kiểm lại.','Báo Thiết bị kiểm độ chính xác.']::text[]),
  ('A1-03', '{A1}', 3, 'Lỗi thay dao tự động (ATC / ổ dao)', array['Gỡ dao kẹt trên tay thay dao.','Khởi tạo lại ổ dao về gốc.','Kiểm tra bảng số dao trong ổ.','Báo Thiết bị sửa.']::text[]),
  ('A1-04', '{A1}', 4, 'Trục chính kêu / rung / nóng', array['Kiểm tra cân bằng, độ đảo dao.','Vệ sinh côn dao, lỗ côn trục chính.','Chạy hâm nóng trục chính.','Báo Thiết bị kiểm vòng bi.']::text[]),
  ('A1-05', '{A1}', 5, 'Kẹp phôi (thuỷ lực / khí) không đủ lực', array['Kiểm tra áp thuỷ lực, khí nén.','Kiểm tra rò rỉ ống, khớp nối.','Vệ sinh van, xi lanh kẹp.','Báo Thiết bị sửa.']::text[]),
  ('A1-06', '{A1}', 6, 'Thiếu dầu bôi trơn / dầu thuỷ lực', array['Châm dầu đúng loại.','Kiểm tra rò rỉ đường dầu.','Reset cảnh báo, chạy lại.']::text[]),
  ('A1-07', '{A1}', 7, 'Nước làm mát thiếu / tắc / bẩn', array['Châm nước làm mát, kiểm nồng độ.','Thông vòi phun, vệ sinh lọc.','Vệ sinh bể nước làm mát.']::text[]),
  ('A1-08', '{A1}', 8, 'Băng tải phoi kẹt / đầy phoi', array['Dọn phoi, gỡ kẹt băng tải.','Đổ thùng phoi.','Báo Thiết bị nếu băng tải không chạy.']::text[]),
  ('A1-09', '{A1}', 9, 'Cửa / cảm biến an toàn lỗi', array['Vệ sinh, kiểm tra công tắc cửa.','Báo Thiết bị sửa (không nối tắt an toàn).']::text[]),
  ('A1-10', '{A1}', 10, 'Lỗi chương trình / dừng giữa chừng', array['Kiểm tra đúng số chương trình theo mã.','Nạp lại chương trình chuẩn đã duyệt.','Báo Kỹ thuật sửa chương trình.']::text[]),
  -- A2 — Dao cụ / đồ gá
  ('A2-01', '{A2}', 1, 'Gãy dao', array['Lấy mảnh dao gãy khỏi SP, đồ gá.','Thay dao mới, đo và nhập bù dao.','Kiểm tra lại tốc độ, lượng ăn dao.','Cách ly SP lúc gãy dao, QC kiểm.']::text[]),
  ('A2-02', '{A2}', 2, 'Mòn / mẻ dao', array['Thay dao / mảnh dao mới.','Đo và nhập bù dao.','Chạy thử 1 SP, QC đo.']::text[]),
  ('A2-03', '{A2}', 3, 'Kích thước lệch do dao', array['Bù dao theo kết quả đo.','Đo lại chiều dài dao.','QC đo SP đầu sau bù.']::text[]),
  ('A2-04', '{A2}', 4, 'Quấn phoi / dính phoi trên dao', array['Gỡ phoi, vệ sinh dao.','Tăng nước làm mát / thổi khí.','Chỉnh thông số cắt để bẻ phoi.']::text[]),
  ('A2-05', '{A2}', 5, 'Đồ gá lỏng / mòn / lệch chuẩn', array['Siết lại, rà chuẩn đồ gá bằng đồng hồ so.','Thay chốt định vị / mặt tỳ mòn.','Báo Kỹ thuật sửa đồ gá.']::text[]),
  ('A2-06', '{A2}', 6, 'Phoi bám mặt tỳ / chốt định vị', array['Vệ sinh mặt tỳ, chốt định vị.','Thổi khí sạch trước khi gá phôi.']::text[]),
  ('A2-07', '{A2}', 7, 'Thiếu dao dự phòng', array['Báo tủ dao / mài dao cấp.','Dùng dao tương đương (Kỹ thuật duyệt).']::text[]),
  ('A2-08', '{A2}', 8, 'Lắp sai dao / sai vị trí ổ dao', array['Đổi dao về đúng số theo bảng dao.','Đo lại chiều dài, nhập bù dao.','Chạy thử 1 SP, QC đo.']::text[]),
  -- A3 — Hạ tầng
  ('A3-01', '{A3}', 1, 'Mất điện / sụt áp', array['Tắt máy, chờ điện ổn định.','Về gốc máy, kiểm gốc phôi.','Chạy lại từ đầu chương trình.']::text[]),
  ('A3-02', '{A3}', 2, 'Thiếu áp khí nén', array['Kiểm tra máy nén khí, van tổng.','Kiểm tra rò rỉ đường ống.','Báo Thiết bị.']::text[]),
  ('A3-03', '{A3}', 3, 'Làm mát tủ điện / chiller lỗi', array['Vệ sinh lưới lọc, quạt tản nhiệt.','Kiểm tra nước / ga chiller.','Báo Thiết bị.']::text[]),
  ('A3-04', '{A3}', 4, 'Lỗi mạng / truyền chương trình', array['Kiểm tra cáp, khởi động lại máy tính.','Nạp chương trình bằng USB / thẻ nhớ.','Báo Kỹ thuật.']::text[]),
  -- B1 — CL sản phẩm (chọn nhiều)
  ('B1-01', '{B1}', 1, 'Sai kích thước', array['Cách ly hàng, QC đo lại.','Bù dao theo kết quả đo.','Kiểm tra chuẩn gá, phoi bám.','Kiểm tra chương trình.']::text[]),
  ('B1-02', '{B1}', 2, 'Sai vị trí lỗ / lệch tâm', array['Rà lại chuẩn đồ gá, gốc phôi.','Kiểm tra chốt định vị.','Cách ly hàng, QC đo.']::text[]),
  ('B1-03', '{B1}', 3, 'Ren NG (calip không qua)', array['Thay dao ta rô / phay ren.','Kiểm tra đường kính lỗ khoan mồi.','Bù dao ren, kiểm calip.']::text[]),
  ('B1-04', '{B1}', 4, 'Bavia sau gia công', array['Thay dao mòn.','Chỉnh đường vát mép trong chương trình.','Đánh bavia thủ công, QC duyệt.']::text[]),
  ('B1-05', '{B1}', 5, 'Bề mặt xấu / vết rung dao', array['Thay dao, kiểm độ đảo dao.','Giảm tốc độ / lượng ăn dao.','Kiểm tra kẹp phôi chắc.']::text[]),
  ('B1-06', '{B1}', 6, 'Sót nguyên công (thiếu lỗ / ren / mặt)', array['Cách ly hàng, kiểm 100%.','Kiểm tra chương trình, bảng dao.','Gia công bổ sung (QC duyệt).']::text[]),
  ('B1-07', '{B1}', 7, 'Móp / xước / va đập SP', array['Lót đệm đồ gá, khay chứa.','Nhắc thao tác lấy SP nhẹ tay.','Cách ly, QC phân loại.']::text[]),
  ('B1-08', '{B1}', 8, 'Sót phoi / bẩn trong lỗ', array['Thổi khí, rửa SP.','Tăng nước làm mát xịt rửa.']::text[]),
  -- B2 — CL phôi đầu vào (chọn nhiều)
  ('B2-01', '{B2}', 1, 'Rỗ khí / rỗ co lộ ra sau gia công', array['Cách ly SP, QC phân loại.','Báo Đúc, lập NCP phôi.','Đổi lô phôi khác.']::text[]),
  ('B2-02', '{B2}', 2, 'Phôi thiếu lượng dư / sai kích thước', array['Cách ly lô phôi, QC đo.','Báo Đúc.','Đổi lô phôi khác.']::text[]),
  ('B2-03', '{B2}', 3, 'Phôi bavia / mụn lớn, gá không vào', array['Mài bavia, mụn trước khi gá.','Trả bộ phận bavia xử lý lại.']::text[]),
  ('B2-04', '{B2}', 4, 'Phôi cong vênh / biến dạng', array['Cách ly, QC đo.','Báo Đúc.']::text[]),
  ('B2-05', '{B2}', 5, 'Phôi lẫn mã / sai tem', array['Cách ly, kiểm lại tem.','Báo Kho / Đúc đổi đúng mã.']::text[]),
  -- C1 — Thay đổi KHSX
  ('C1-01', '{C1}', 1, 'Đơn gấp chen ngang', array['Đổi sang mã theo KH mới.','Để phôi đang dở về khu chờ, ghi tem.']::text[]),
  ('C1-02', '{C1}', 2, 'Khách đổi / huỷ đơn', array['Dừng chờ Kế hoạch xác nhận.','Chuyển máy sang mã khác.']::text[]),
  ('C1-03', '{C1}', 3, 'Chưa có lệnh sản xuất', array['Báo Kế hoạch ra lệnh.','Dùng thời gian vệ sinh máy (5S).']::text[]),
  -- C2 — Chờ hàng / hết phôi
  ('C2-01', '{C2}', 1, 'Hết phôi từ Đúc / bavia', array['Báo Kế hoạch điều phôi.','Chuyển máy sang mã khác có phôi.','Dùng thời gian vệ sinh máy (5S).']::text[]),
  ('C2-02', '{C2}', 2, 'Phôi chờ QC duyệt', array['Báo QC ưu tiên kiểm.','Chuyển máy sang mã khác có phôi.']::text[]),
  ('C2-03', '{C2}', 3, 'Thiếu thùng / khay chứa', array['Báo Kho cấp thùng, khay.','Mượn thùng tạm, ghi tem rõ.']::text[]),
  ('C2-04', '{C2}', 4, 'Chờ xe nâng / vận chuyển', array['Báo tổ trưởng điều xe.']::text[]),
  -- C3 — Đổi mã / gá đặt
  ('C3-01', '{C3}', 1, 'Đổi mã theo KH', array['Tháo, lắp đồ gá, rà chuẩn.','Nạp chương trình, kiểm bảng dao.','Chạy SP đầu, QC đo duyệt.','Bù dao theo kết quả đo.']::text[]),
  ('C3-02', '{C3}', 2, 'Thay đồ gá / dao cho mã mới', array['Lắp dao theo bảng dao, đo chiều dài.','Lắp đồ gá, rà chuẩn bằng đồng hồ so.']::text[]),
  ('C3-03', '{C3}', 3, 'Chờ QC duyệt SP đầu', array['QC đo SP đầu xong, cho chạy.','Bù dao theo kết quả đo, chạy lại SP đầu.']::text[]),
  -- D1 — Thiếu nhân lực
  ('D1-01', '{D1}', 1, 'Công nhân nghỉ', array['Tổ trưởng điều người thay.','Ưu tiên chạy máy mã gấp.']::text[]),
  ('D1-02', '{D1}', 2, 'Đứng nhiều máy, không kịp', array['Tổ trưởng điều thêm người.','Ưu tiên máy mã gấp.']::text[]),
  ('D1-03', '{D1}', 3, 'Điều đi việc khác', array['Có người quay lại, chạy máy.']::text[]),
  -- D2 — Đào tạo / người mới
  ('D2-01', '{D2}', 1, 'Người mới chưa đứng máy độc lập', array['Người có kinh nghiệm kèm cặp.','Đào tạo xong, cho chạy lại.']::text[]),
  ('D2-02', '{D2}', 2, 'Đào tạo tại máy', array['Đào tạo xong, cho chạy lại.']::text[]),
  -- E1 — Bảo dưỡng máy theo KH
  ('E1-01', '{E1}', 1, 'Bảo dưỡng định kỳ', array['Bảo dưỡng xong theo checklist.','Chạy thử, QC đo SP đầu.']::text[]),
  ('E1-02', '{E1}', 2, 'Kiểm tra độ chính xác máy', array['Kiểm tra xong, chỉnh bù máy.','Chạy thử, QC đo SP đầu.']::text[]),
  -- E2 — Vệ sinh theo KH
  ('E2-01', '{E2}', 1, 'Vệ sinh máy cuối ca / tuần', array['Vệ sinh xong, kiểm tra máy.']::text[]),
  ('E2-02', '{E2}', 2, 'Thay nước làm mát / vệ sinh bể', array['Thay xong, kiểm nồng độ.']::text[]),
  -- E3 — Kiểm kê định kỳ
  ('E3-01', '{E3}', 1, 'Kiểm kê định kỳ', array['Kiểm kê xong, chạy lại.']::text[])
on conflict (ma) do update set loai = excluded.loai, thu_tu = excluded.thu_tu, van_de = excluded.van_de, xu_ly = excluded.xu_ly, hieu_luc = true, updated_at = now();
