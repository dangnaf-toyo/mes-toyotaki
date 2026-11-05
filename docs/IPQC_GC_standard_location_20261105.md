# Tích hợp tiêu chuẩn Gia công vào Quản lý tiêu chuẩn — STAGING 05/11/2026

Phạm vi lần sửa này: Nhóm 1 trong yêu cầu mới. Tin nhắn Nhóm 2 bị ngắt sau “danh sách đặc tính kích t…”, đã đề nghị gửi tiếp; không suy đoán yêu cầu chưa nhận được. Giữ luồng nhập kết quả đang có và kiểm thử hồi quy.

## Cấu trúc và dữ liệu

Khảo sát từ commit `af8ba1e`: QC Manager → Quản lý tiêu chuẩn đã có công đoạn Đúc/Gia công, dùng `ipqc_btk`, `ipqc_btk_muc`. Trang IPQC Gia công cũng dùng chính các bảng/ID này, không phải kho dữ liệu riêng. Vì vậy không cần chuyển/copy/xóa dữ liệu tiêu chuẩn.

- Bỏ tab/form Tiêu chuẩn Gia công khỏi `ipqc-gia-cong.html`, xóa mã editor riêng khỏi `shared/ipqc-gia-cong.js`. Giữ Nhập kết quả và Dashboard. Có liên kết đến Quản lý tiêu chuẩn → Gia công.
- Mở rộng **editor chung hiện có** `IpqcBtkQc.mountEditor` trong `shared/ipqc-btk-qc.js` cho loại Gia công: mã bản vẽ, bước, mã đặc tính, đơn vị, phương pháp, LSL/USL, cỡ mẫu, xác nhận đặc tính, bản vẽ private và lịch sử nội dung. Không thêm module quản lý mới.
- Giữ chung quy trình nhân viên soạn → trưởng phòng QC kiểm tra → giám đốc sản xuất duyệt; giữ bảng, ID, Revision, liên kết đo và snapshot. Danh sách chờ duyệt mở đúng ID phiên bản, phân biệt các bước cùng Model/Revision.
- Link cũ `ipqc-gia-cong.html?standard=...&version=...` chuyển tới đúng bản ở QC Manager. Không còn vòng chuyển từ editor chung trở lại tab cũ.
- Bản vẽ tiêu chuẩn PDF/JPG/PNG là tùy chọn, dùng lại bộ đọc bản vẽ hiện có. Không yêu cầu file CMM ở đây. Bộ đọc kết quả PDF/Excel/ảnh vẫn nằm ở Nhập kết quả.
- Sao chép/dán dòng trong editor chung giữ các trường tiêu chuẩn Gia công; không sao chép mã đặc tính tạo trùng. Mỗi dòng sửa phải xác nhận lại; dữ liệu đang soạn không mất khi thêm/xóa/dán dòng. Chặn thao tác lặp trong khi lưu và bỏ kết quả tải phiên bản lỗi thời.

## T219 và bảo toàn dữ liệu

Chỉ áp dụng trên project STAGING `jcjbleugnclzsghfpmvk`. T219 chỉ sửa wrapper `ipqc_gc_luu_tieu_chuan`: cho phép giữ trống bước/mã bản vẽ/mã đặc tính ở dữ liệu cũ; không tự tạo nội dung. Vẫn kiểm tra đăng nhập/quyền, Revision, xác nhận từng dòng, giới hạn hữu hạn, mã không trùng nếu đã khai báo. Gọi cùng writer tiêu chuẩn đã có và ghi lịch sử/xác nhận như trước. Không thay đổi writer Đúc hay writer lưu kết quả đo.

Đã chạy thử transaction rollback trước áp dụng, rồi kiểm thử lại sau áp dụng. Không có migration chuyển bảng, không tạo tiêu chuẩn/tài khoản mẫu lâu dài.

## Kết quả kiểm thử

- `ipqc-standards-manager-browser.cjs`: PASS Chrome trên trang QC Manager thực, backend fixture. Mở đúng bản A/file private/lịch sử; sửa B tại module chung; giữ metadata, vị trí đo, đơn vị, phương pháp, giới hạn, cỡ mẫu; sao chép/dán; buộc xác nhận; bản A không thay đổi. Chuyển Đúc độc lập; link cũ chuyển đúng bản; trang IPQC không còn form tiêu chuẩn và vẫn tải đặc tính đo.
- `ipqc-standards-manager-staging-rollback.sql`: PASS database staging thật. Tiêu chuẩn cũ không bước/mã giữ nguyên; tạo Revision không sửa bản đã duyệt; cập nhật bản nháp giữ ID; lịch sử được nối tiếp; giữ LSL/USL/vị trí đo/người xác nhận.
- `ipqc-gc-staging-rollback.sql`: PASS staging thật sau T219, gồm luồng duyệt/đo, OK/NG biên, cỡ mẫu bổ sung, retry, snapshot, nguồn file, quyền và cách ly Đúc. Dữ liệu/quyền thử rollback.
- Hồi quy PASS Chrome nhập tay, DOM Dashboard, parser bản vẽ/kết quả, Chrome nhập file XLSX/PDF/ảnh và hai Excel thực PREMO/HITACHI; IPQC Đúc `ipqc-start-integration` PASS 2 nhóm.
- Đã xem ảnh giao diện editor chung. Kiểm tra tĩnh không có mức CAO/TB; các nhắc THẤP về CSS nhỏ/lỗi thô/dòng dài phần có sẵn được giữ ngoài phạm vi. `git diff --check` sạch.

Preflight/postflight staging: 30 máy, 0 tiêu chuẩn Gia công, 0 lượt đo Gia công/Đúc, 5 Admin + 1 OQC. Checksum tiêu chuẩn và đặc tính đều giữ nguyên `d41d8cd98f00b204e9800998ecf8427e`. Staging chưa có dữ liệu nghiệp vụ tiêu chuẩn Gia công để kiểm thử bằng tài khoản QC thực; bảo toàn lịch sử được xác minh bằng fixture và transaction rollback.

Chỉ nhánh `staging`; không force push, không merge/deploy Production, không truy cập ghi database Production. Checkout gốc đang conflict được giữ nguyên; thực hiện trong `.nov04-staging`.
