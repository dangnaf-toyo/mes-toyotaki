# Bản vẽ tham khảo trong Quản lý tiêu chuẩn Gia công — STAGING

Nền `3b3b92a`, nhánh `staging`, project `jcjbleugnclzsghfpmvk`. Không sửa schema, API, quy trình duyệt hoặc dữ liệu tiêu chuẩn đang có. Không truy cập ghi hay triển khai Production.

## Hành vi sau sửa

- Chọn PDF/JPG/JPEG/PNG chỉ thay phần xem bản vẽ bên trái; không gọi OCR/parser, không thay danh sách đặc tính, danh nghĩa, dung sai, LSL/USL, vị trí đo hoặc dấu xác nhận bên phải.
- Xem trước tại chỗ. PDF có Trang trước/sau, số trang, phóng to/thu nhỏ, vừa khung; ảnh có zoom và vùng cuộn. PDF.js chỉ render trang, không gọi trích xuất text/kích thước.
- File được upload khi gửi lưu bản nháp, cùng payload Model/mã bản vẽ/Revision hiện tại. Dùng bucket private và path UID/UUID riêng, `upsert:false`; mở lại bằng URL có thời hạn. Việc thay file bản nháp không ghi đè object của bản đã phát hành.
- Giữ nguyên dữ liệu cũ, các file đính kèm cũ, luồng xác nhận/duyệt/phát hành và nhập tiêu chuẩn thủ công. Không xóa các thành phần đọc bản vẽ dùng chung; chỉ ngừng nạp/gọi chúng ở Quản lý tiêu chuẩn.
- Luồng đọc file kết quả đo CMM tại Nhập kết quả không thay đổi.

## File thay đổi

| File | Nội dung |
| --- | --- |
| `shared/ipqc-btk-qc.js` | Thay luồng đọc kích thước bằng đính kèm; chỉ cập nhật khung trái; giữ bảng/đánh dấu xác nhận; dùng path mới không overwrite. |
| `shared/ipqc-drawing-viewer.js` | Viewer PDF/ảnh, điều khiển trang/zoom/vừa khung; giới hạn canvas và giải phóng tài nguyên khi đổi file/phiên bản. |
| `qc-manager.html` | Bỏ nạp reader/parser bản vẽ, nạp viewer và cache version mới. |
| `ipqc-gia-cong.html`, `bieu-do-chat-luong.html` | Chỉ tăng cache version module tiêu chuẩn dùng chung. |
| `tests/ipqc-drawing-attachment-browser.cjs` | Kiểm thử file/preview/lưu/mở lại/thay file/bảo toàn đặc tính và bản đã phát hành. |
| `tests/ipqc-drawing-attachment-staging-rollback.sql` | Kiểm thử RPC thực với metadata bản vẽ và workflow hiện có trong rollback. |
| `tests/ipqc-standards-manager-browser.cjs` | Cập nhật kiểm tra viewer, giữ hồi quy editor chung. |
| `tests/check-mes-nov04-staging.cjs` | Xác minh asset deploy và không còn gọi reader/parser trong editor. |
| Báo cáo này | Phạm vi và bằng chứng kiểm thử. |

## Kiểm thử đã đạt

1. Chrome với thư viện PDF.js thật và PDF hai trang, PNG/JPG/JPEG thật: đổi trang, zoom/vừa khung, xem lại sau lưu, thay từng định dạng ở bản nháp. Kiểm tra byte file được giữ, đúng Model/PART, mã bản vẽ/DWG và Revision/B; bản A và object gốc không đổi. Bảng/metadata/dấu xác nhận trước và sau chọn file giống hệt nhau. Reader OCR được gắn bẫy để phát hiện nếu bị gọi.
2. Storage staging thật: upload rồi download PDF/PNG/JPG trong thư mục UUID riêng; SHA-256 khớp cả ba. Bucket vẫn private, limit 20 MB, MIME PDF/PNG/JPEG. Đã dọn đúng ba object thử; truy vấn cuối xác nhận 0 object thử còn lại.
3. SQL staging thật với các object vừa upload: lưu liên kết Model/mã bản vẽ/Revision; bản nháp thay file giữ ID, đặc tính và lịch sử; không cho ghi đè Revision đã phát hành; bước admin kiểm tra rồi phát hành vẫn hoạt động. Toàn bộ tiêu chuẩn/kết quả thử rollback.
4. Hồi quy PASS editor chung, 20 tổ hợp vai trò/trạng thái/loại duyệt, DOM nhập kết quả/Dashboard; đọc kết quả XLSX/PDF/ảnh và hai Excel công ty PREMO/HITACHI. Không thay đổi các module `ipqc-result-*`.
5. Đã xem ảnh giao diện PDF trong editor. Cú pháp/diff whitespace đạt; kiểm tra tĩnh không có mức CAO/TB. Các nhắc THẤP ở phần mã cũ ngoài phạm vi được giữ nguyên.

Chrome sử dụng backend fixture giữ byte file và thư viện thật; Storage/RPC staging được kiểm thử riêng qua CLI/transaction. Không mô tả đây là E2E bằng tài khoản QC đăng nhập trên dữ liệu vận hành.

Checksum trước/sau giống nhau: tiêu chuẩn `1a8b9f17f306bda71b5dcfb496595a04`, đặc tính `a1623957c0336c56696bdece880591d2`, checklist `d41d8cd98f00b204e9800998ecf8427e`. Quyền tài khoản vẫn 5 admin + 1 OQC. Không giữ dữ liệu tiêu chuẩn hoặc file thử lâu dài trên staging.
