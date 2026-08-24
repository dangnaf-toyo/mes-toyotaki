---
name: bao-cao-tuan
description: Tạo báo cáo sản xuất tuần khối Đúc (mes-toyotaki) — kế hoạch/thực tế, so sánh Ca 1/Ca 2 (hoàn thành KH, phút dừng, sự cố/ca, dừng do chất lượng, dừng do sự cố khuôn, đổi khuôn TB/lần, NG), thời gian dừng máy phân tích theo máy/loại vấn đề/mã sản phẩm, mỗi phần kèm 3 vấn đề ưu tiên xử lý. Dùng khi user gõ "/bao-cao-tuan", yêu cầu "báo cáo sản xuất tuần", "báo cáo tuần", hoặc theo lịch chạy định kỳ sáng thứ Hai.
---

# Báo cáo sản xuất tuần — khối Đúc

Tạo báo cáo HTML (Artifact) tổng kết sản xuất tuần cho khối Đúc, dựa trên dữ liệu thật trong Supabase — không dùng số liệu giả định.

## 1. Xác định kỳ báo cáo

- Tuần chạy **Thứ Hai → Thứ Bảy** (nhà máy hiện tại chạy phương án **2 ca 8 tiếng: Ca 1 + Ca 2**, không có Ca 3/Ca đêm cố định).
- Nếu skill được gọi **định kỳ sáng Thứ Hai** (job lịch): báo cáo **tuần vừa kết thúc** — Thứ Hai đến Thứ Bảy tuần trước, dữ liệu đã đầy đủ (đã kết ca hết), không có ngày nào "đang chạy".
- Nếu user gọi thủ công giữa tuần (vd "báo cáo tuần này"): báo cáo **tuần hiện tại tính đến hiện tại** — những ngày đã kết ca coi là đầy đủ, ca đang chạy dở (nếu có, từ `duc_ca_hien_tai`) coi là "tạm tính", đánh dấu rõ trên báo cáo (badge "đang chạy" ở header + trong bảng "Diễn biến theo ngày").
- Luôn tính Thứ Hai của tuần mục tiêu bằng ngày thật (không đoán), ví dụ trong Bash: `python3 -c "import datetime; d=datetime.date.today(); print(d - datetime.timedelta(days=d.weekday()))"` (điều chỉnh offset -7 ngày nếu lấy tuần trước).

## 2. Lấy dữ liệu (Supabase REST, anon key)

Lấy `SUPABASE_URL`/`SUPABASE_ANON_KEY` từ `shared/supabase-client.js` (2 hằng số đầu file — key là publishable/anon, an toàn dùng qua REST GET, không cần token bí mật).

Query 4 bảng, lọc `ngay=gte.<thu2>&ngay=lte.<thu7>`:

- `duc_bao_cao_ca` — báo cáo kết ca (KPI cấp ca): `ngay,ca,truong_ca,so_may_co_kh,so_may_hoan_thanh_kh,tong_kh_ca,tong_tt_ca,ty_le_hoan_thanh_ca,so_su_co_ca,tong_phut_dung_ca,tong_ng_ca` — **chỉ dùng cho các ca đã kết ca**, đây là nguồn số liệu "chính thức" của mỗi ca.
- `duc_su_co_log` — nhật ký sự cố chi tiết: `ngay,ca,ma_may,ma_sp,ten_sp,loai_su_co,thoi_gian_dung_phut,van_de,truong_ca` — nguồn cho mọi phân tích thời gian dừng (theo máy/loại vấn đề/mã SP/đổi khuôn).
- `duc_lich_su_san_xuat` — sản lượng theo (ngày,ca,máy,SP) khi đã kết ca: `ngay,ca,ma_may,ma_sp,ten_sp,kh_ca,tt_ca,so_luong_ng`.
- `duc_ca_hien_tai` — **chỉ cần nếu báo cáo có ngày đang chạy dở** (không cần khi báo cáo tuần đã xong hẳn): `ngay,ca,ma_may,ma_sp,ten_sp,kh_ca,tt_ca,so_luong_ng,trang_thai,open_loai_su_co,open_van_de,sp_start_time,sp_end_time`. Dùng để cộng thêm phần "tạm tính" của ca đang chạy vào sản lượng theo máy/SP (không cộng vào KPI tổng tuần/`duc_bao_cao_ca`-based vì ca chưa kết ca chưa có ở đó).

**Lọc bắt buộc: loại bỏ mọi dòng có `ca` KHÁC "Ca 1" hoặc "Ca 2"** (vd "Ca ngày", "Ca đêm" nếu phát sinh) ở CẢ 3 bảng `duc_bao_cao_ca`/`duc_su_co_log`/`duc_lich_su_san_xuat` — nhà máy hiện chỉ vận hành 2 ca 8 tiếng, dữ liệu ca khác là ngoại lệ/lịch sử không thuộc phương án hiện tại. Đây là quy tắc đã được user xác nhận rõ ràng (2026-08-22), áp dụng cho mọi lần chạy skill này, không hỏi lại.

## 3. Tính toán

Tất cả số liệu phải tính từ dữ liệu vừa lấy, không hard-code:

- **KPI tuần**: tổng KH/TT/%HT/NG/số sự cố/phút dừng từ `duc_bao_cao_ca` (chỉ ca đã kết ca). "Hoàn thành KH bình quân" = trung bình cộng %HT của từng ca riêng lẻ (không phải KH/TT gộp) — **không dùng OEE, nhà máy chưa quản lý chỉ số này**.
- **Diễn biến theo ngày**: KH/TT/%HT mỗi ngày (cộng Ca1+Ca2 của ngày đó), cột chiều cao theo tỉ lệ % so với ngày có KH lớn nhất trong tuần.
- **3 ca yếu nhất tuần**: xếp theo %HT từng ca (thấp nhất trước), kèm trưởng ca/số sự cố/phút dừng.
- **So sánh Ca 1 và Ca 2**: gộp toàn bộ 5-6 ca mỗi bên theo nhãn `ca` (không theo `truong_ca`). Các chỉ số, đúng thứ tự hiển thị: Hoàn thành KH, Phút dừng máy, Số sự cố/ca (trung bình), Dừng do vấn đề chất lượng (mã B1/B2/F1, tổng phút từ `duc_su_co_log`), Dừng do sự cố khuôn (mã A2, tổng phút — khác C3 "Đổi khuôn"), Đổi khuôn TB/lần (mã C3, trung bình phút/lần + số lần, gộp theo `ca` chứ không theo `truong_ca`), NG. **Không có hàng Availability/Performance/Quality/OEE** — nhà máy chưa quản lý OEE. **Đã bỏ bảng riêng "Thời gian đổi khuôn theo trưởng ca"** (2026-08-24) — chỉ số đổi khuôn giờ chỉ so sánh theo Ca 1/Ca 2 trong bảng này, không còn gộp theo người ghi nhận (`truong_ca`) nữa.
- **Dừng máy theo máy / theo loại vấn đề / theo mã SP**: tổng phút + số lượt từ `duc_su_co_log`, xếp giảm dần.
- **3 vấn đề lớn nhất bên trong mỗi máy / mỗi loại vấn đề / mỗi mã SP**: với MỖI máy (và MỖI loại vấn đề, MỖI mã SP), gộp các bản ghi theo đúng nội dung cột `van_de` (chuẩn hoá whitespace, giữ nguyên chữ), lấy 3 mục có tổng phút cao nhất — đây là các "root cause" cụ thể, không phải chỉ nhắc lại mã lỗi chung chung.
- **Sản lượng theo máy / theo mã SP**: KH/TT/%HT/NG từ `duc_lich_su_san_xuat` (+ `duc_ca_hien_tai` nếu có ca đang chạy dở). "Thiếu hụt" = KH − TT (số tuyệt đối), dùng số này để xếp hạng ưu tiên (không chỉ dùng %) — máy/SP có KH nhỏ nhưng %HT thấp có thể không đáng ưu tiên bằng máy/SP có KH lớn.
- **Mỗi phần trong báo cáo PHẢI có 1 khối "🎯 3 [X] ưu tiên xử lý"** (priority-box) tính từ chính dữ liệu tuần đó — không dùng lại số của tuần trước.

## 4. Các lỗi dữ liệu cần xử lý (đã gặp thực tế, luôn kiểm tra lại)

- **Chuẩn hoá dấu gạch ngang trong `loai_su_co`**: cột này đôi khi dùng `–`/`—`/`-` không nhất quán cho cùng 1 mã lỗi (vd "C3 — Đổi khuôn" và "C3 - Đổi khuôn" là CÙNG 1 loại, cần gộp) — regex `\s*[-—–]\s*` → thay bằng `' - '` trước khi group.
- **Gộp nhãn "F1" trùng lặp**: có thể tồn tại cả `"F1"` (mã ngắn, không mô tả) và `"F1 — Chất lượng - IPQC phát hiện NG"` (mã đầy đủ) là CÙNG 1 loại vấn đề — gộp lại thành 1 dòng "F1 — CL / IPQC phát hiện NG" trong mọi bảng/card, ghi chú rõ có bao nhiêu % số lượt chỉ ghi mã ngắn (data-entry gap đáng nêu ra cho user biết, không tự ý "sửa" dữ liệu).
- **`van_de` rỗng** → hiển thị "(không ghi nội dung xử lý)", không bỏ qua bản ghi khỏi tổng phút/lượt.
- Nếu sau khi lọc, một máy/loại vấn đề/mã SP nào đó chỉ còn <3 mục `van_de` khác nhau, card vẫn hiển thị bình thường với số mục thực có (ghi chú "(chỉ có N vấn đề)"), không bịa thêm cho đủ 3.
- Nếu lọc Ca 1/Ca 2 làm một mã SP/máy nào đó KHÔNG còn bản ghi dừng máy nào (toàn bộ downtime của nó nằm ở ca bị loại) → bỏ hẳn khỏi phần "3 vấn đề lớn nhất", cập nhật đúng số đếm "(N/N mã có phát sinh...)".

## 5. Trang thật đã có — `bao-cao-tuan.html`

Kể từ 2026-08-22, báo cáo tuần có **trang thật trong app**: `bao-cao-tuan.html` (đã đẩy lên repo, có trong navbar "Điều hành & Báo cáo" → "Báo cáo sản xuất tuần"). Trang này **tự tính lại 100% nội dung trực tiếp từ Supabase mỗi khi mở** — không cache, không lưu số liệu report ở đâu — nên **KHÔNG BAO GIỜ cần "cập nhật" nội dung báo cáo bằng tay hay bằng migration**. Xem tuần nào, trang tự tính đúng tuần đó.

- Truy cập 1 tuần cụ thể qua query param: `bao-cao-tuan.html?monday=YYYY-MM-DD` (YYYY-MM-DD là Thứ Hai của tuần cần xem — trang tự chuẩn hoá về đúng Thứ Hai nếu lỡ truyền ngày khác).
- Trang gồm đủ các phần theo đúng thứ tự: KPI tuần → diễn biến theo ngày (+3 ca yếu nhất) → sản lượng theo mã SP → sản lượng theo máy (+ ưu tiên theo thiếu hụt) → dừng máy theo máy (+ ưu tiên) → dừng máy theo loại vấn đề (+ ưu tiên) → **so sánh Ca 1/Ca 2** (hoàn thành KH, phút dừng, sự cố/ca, dừng do chất lượng, dừng do sự cố khuôn, đổi khuôn TB/lần, NG) → dừng máy theo mã SP (+ ưu tiên) → **3 vấn đề lớn nhất bên trong từng máy/loại/mã SP** (dạng card, y hệt logic mục 3 ở trên) → bảng "Tổng hợp vấn đề và hành động đối ứng" (lưu vào `duc_bao_cao_tuan_van_de`, chỉ ghi được khi đã đăng nhập — cloud routine KHÔNG ghi được bảng này, đây là việc con người làm thủ công trên trang). **Không còn card "Thời gian đổi khuôn theo trưởng ca" riêng** (2026-08-24) — đã gộp vào bảng so sánh Ca 1/Ca 2.
- **`template.html` trong thư mục skill này CHỈ còn dùng khi user yêu cầu rõ ràng 1 bản Artifact rời (vd để chia sẻ nhanh qua link không cần đăng nhập, hoặc xem trên điện thoại không vào được app)** — không dùng cho việc chạy định kỳ nữa, xem mục 7.

## 5b. Thiết kế / định dạng khi vẫn cần tạo Artifact rời — LUÔN theo đúng `template.html` trong cùng thư mục skill này

`template.html` là bản báo cáo mẫu đầy đủ (CSS + cấu trúc HTML) đã được user duyệt qua nhiều vòng chỉnh sửa. Khi tạo báo cáo mới:

1. Copy nguyên `template.html` làm điểm xuất phát.
2. **Giữ nguyên 100%** phần `<style>` (design tokens: nền `#F5F2ED`/`#161210`, accent `#C8703A`/`#E28A4C` — đúng màu "Đúc" dùng xuyên suốt app, font Archivo/IBM Plex Sans/IBM Plex Mono, `.priority-box`, `.pcard`, `.ca-row`, `.kpi`, bar-in-cell `.barcell`), toàn bộ class names, dark-mode block.
3. **Giữ nguyên thứ tự các section** (đổi 2026-08-24 — không còn card đổi khuôn theo trưởng ca riêng, bảng so sánh Ca 1/Ca 2 chuyển xuống sau mục dừng theo loại vấn đề): Header → KPI strip → Diễn biến theo ngày (+ 3 ca yếu nhất) → Sản lượng theo mã SP → Sản lượng theo máy → Thời gian dừng theo máy (+ ưu tiên) → Thời gian dừng theo loại vấn đề (+ ưu tiên) → So sánh Ca 1/Ca 2 (hoàn thành KH, phút dừng, sự cố/ca, dừng do chất lượng, dừng do sự cố khuôn, đổi khuôn TB/lần, NG, + ưu tiên) → Thời gian dừng theo mã SP (+ ưu tiên) → 3 vấn đề lớn nhất (theo máy / theo loại / theo mã SP, dạng card 3 cột) → Footer ghi chú nguồn số liệu.
4. **Thay TOÀN BỘ nội dung số liệu** (KPI, bảng, bar width %, priority-box, thẻ card) bằng số liệu tuần mới tính ở bước 3 — không được để sót số liệu cũ.
5. Tiêu đề đổi theo tuần thật, vd `<title>Đúc Tuần 35</title>` (số tuần ISO, tính bằng `date.isocalendar()[1]` của ngày Thứ Hai kỳ báo cáo) và `<h1>Báo cáo Sản xuất Tuần 35</h1>`.
6. Nếu báo cáo là tuần đã xong hẳn (chạy sáng thứ Hai) → **bỏ hẳn** badge "đang chạy" (`.live-pill`) ở header và card "hôm nay" (`.day.today`) trong Diễn biến theo ngày — không có ngày nào tạm tính.
7. Footer: cập nhật đúng khoảng ngày, và ghi rõ nếu có loại bỏ ca không chuẩn (vd nếu tuần đó có phát sinh "Ca ngày"/ca lạ, nêu rõ như đã làm ở báo cáo Tuần 34).

## 6. Xuất bản

- Ghi file HTML vào thư mục scratchpad của phiên hiện tại (không ghi vào repo).
- Publish qua Artifact tool: `favicon: "🏭"`, `title` dạng `"Đúc Tuần <N>"`, `description` 1 câu tóm tắt nội dung tuần đó.
- **Nếu đây là lần đầu tạo báo cáo cho tuần đó** → publish mới (không truyền `url`).
- **Nếu user yêu cầu sửa/cập nhật báo cáo đã có trong phiên này** → publish lại đúng `file_path` đó để giữ nguyên URL (không tạo artifact mới).
- Trả lời user: link Artifact + tóm tắt 3-5 gạch đầu dòng những điểm nổi bật nhất tuần (không liệt kê lại toàn bộ số liệu đã có trong báo cáo).

## 7. Khi chạy như routine định kỳ sáng Thứ Hai (cloud, không có phiên trò chuyện)

**KHÔNG tạo Artifact nữa.** Việc của routine chỉ là: tính nhanh dữ liệu tuần vừa kết thúc (đọc trực tiếp Supabase REST, y như mục 2-3) để rút ra vài điểm nổi bật, rồi trỏ user sang trang thật kèm đúng tuần:

1. Tính ngày Thứ Hai của tuần vừa kết thúc (tuần trước tuần hiện tại) bằng lệnh ngày thực tế, không đoán.
2. Lấy dữ liệu Supabase (đọc thôi, không ghi — cloud routine không có phiên đăng nhập nên không ghi được bảng `duc_bao_cao_tuan_van_de`, việc đó để user tự làm trên trang).
3. Rút ra 3-5 điểm nổi bật nhất tuần (vd ca yếu nhất, máy/mã SP thiếu hụt nhiều nhất, vấn đề lặp lại nhiều nhất) — dùng đúng logic mục 3.
4. Kết thúc bằng 1 tin nhắn ngắn gồm: link trực tiếp đến đúng tuần đó —
   `https://dangnaf-toyo.github.io/mes-toyotaki/bao-cao-tuan.html?monday=<Thứ Hai tuần đó, YYYY-MM-DD>`
   — và danh sách 3-5 gạch đầu dòng điểm nổi bật. Không liệt lại toàn bộ số liệu (trang đã có đủ).
- Không có ai để hỏi lại — nếu dữ liệu tuần đó thiếu/bất thường (vd thiếu hẳn 1 ngày không có `duc_bao_cao_ca` nào), vẫn nêu điểm nổi bật với dữ liệu đang có, ghi chú rõ chỗ thiếu, không suy diễn số liệu.
