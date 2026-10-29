# NCP và tiêu chuẩn theo công đoạn — 29/10/2026

Trạng thái: đang thực hiện trên nhánh `fix/ncp-deadlines-staging-20261029`, worktree `.ncp-deadlines-release`. Đã áp dụng T184/T185 lên Supabase STAGING `jcjbleugnclzsghfpmvk` ngày 29/10/2026 bằng CLI Management API, sau một lượt chạy thử transaction rollback. Chưa merge/push/deploy frontend. Không thay đổi production. Checkout gốc có merge conflict từ công việc khác, được giữ nguyên.

## Thay đổi đã soạn

- `qc-manager.html`: hạn trả lời bắt buộc khi mở phiếu; danh sách có hạn, tiến độ, trạng thái thời hạn, lọc và sắp xếp; chọn tiêu chuẩn Đúc/Gia công, truy vấn và gửi duyệt theo công đoạn.
- `ncp-detail.html`: tải/lưu hạn theo quyền khóa chỉnh sửa đối sách hiện có.
- `shared/mes-ncp-source.js`: gửi hạn trong luồng tạo phiếu theo nguồn.
- `shared/ipqc-btk-qc.js`: editor và nhập Excel tách công đoạn, giữ luồng duyệt cũ.
- `shared/ipqc-btk-do.js`: gửi ID phiên bản đã mở, cảnh báo thiếu tiêu chuẩn Đúc; lịch sử hỗ trợ nhập đo được giới hạn cùng phiên bản.
- `ipqc.html`, `shared/qc02-data.js`: truy vấn tiêu chuẩn hiện có được giới hạn Đúc.
- T184: cột hạn/người mở UID; view tiến độ; cấu hình mốc 3/1 ngày; quét theo cron mỗi giờ 07:00–22:00 GMT+7; dùng `cv_thong_bao`, helper nhân sự/vai trò hiện có và sổ sự kiện chống trùng; đóng nhắc khi đã trả lời hoặc đổi hạn.
- T185: khóa tiêu chuẩn theo công đoạn/mã/phiên bản; API lấy bản được duyệt đã hiệu lực; kiểm tra ID phiên bản lúc lưu đo; giữ ID lịch sử và trả metadata phiên bản trong dữ liệu đo.

## Kiểm thử đã chạy

`node tests/ncp-standards-postgres.cjs` dùng PGlite tại `.review/tools` (hoặc `MES_PGLITE_PATH`), không kết nối database ngoài. Fixture schema nằm trong `tests/ncp-standards-schema.fixture.json`; cron là stub cục bộ.

PASS: cú pháp JS nội tuyến; thực thi cả T183 và T184 trên PostgreSQL cục bộ; phiếu cũ giữ NULL; các mốc sắp đến hạn/hôm nay/quá hạn; đã trả lời chuyển hoàn thành; cùng mã và phiên bản ở hai công đoạn độc lập; phiên bản hiệu lực tương lai chưa thay bản hiện tại; quét lại không gửi trùng và không gửi cho phiếu đã trả lời. Chưa kiểm thử đầy đủ phân quyền và bốn nhóm người nhận trên dữ liệu staging thực tế.

Đã đọc lại schema staging trực tiếp trước migration và phát hiện API tiêu chuẩn đã được bổ sung `p_cong_doan`. T184 được điều chỉnh để giữ API này, gồm dữ liệu đo và giới hạn kiểm soát theo công đoạn. Staging hiện chưa có bảng tuần kiểm hoặc kết quả đo, nên chưa kiểm chứng được lịch sử tiêu chuẩn bằng dữ liệu nghiệp vụ thực tế.

Kiểm thử trực tiếp staging bằng `tests/ncp-deadline-staging-rollback.sql`: PASS mốc 3/1/0/quá hạn, một người vừa mở vừa đảm nhiệm chỉ nhận một thông báo, quét lặp không trùng, hoàn thành đóng nhắc ngay và không tạo nhắc mới. Toàn bộ dữ liệu thử đã rollback.

Kiểm tra sau áp dụng: cron `ncp_nhac_han_doi_sach` active, lịch `0 0-15 * * *` UTC (07:00–22:00 GMT+7); mốc cấu hình 3/1 ngày. Hai phiếu cũ vẫn có hạn NULL. Quyền anon không được tạo phiếu hoặc gọi hàm quét; authenticated được đọc view và không được gọi hàm quét server. Checksum các bảng tuần kiểm, hạng mục và kết quả đo không đổi (đều đang rỗng).

## Việc còn lại trước khi bàn giao

1. Đưa frontend nhánh tính năng lên staging để kiểm thử đồng bộ với database. Frontend staging cũ chưa gửi hạn bắt buộc khi mở phiếu và ID phiên bản lúc lưu đo.
2. Kiểm thử giao diện tạo/sửa hạn và đăng nhập bằng từng vai trò; kiểm chứng đủ bốn nhóm nhân sự với phân công thực tế, trạng thái đọc và lượt cron tự chạy.
3. Kiểm thử các luồng duyệt, hiệu lực tương lai, dữ liệu kiểm tra lịch sử, checklist/PDF và biểu đồ SPC sau thay phiên bản.
4. Rà giao diện trên trình duyệt, đặc biệt date picker DD/MM/YYYY (native date input phụ thuộc locale) và bảng nhiều cột trên di động. Chưa được coi là hoàn thành hoặc sẵn sàng production.

Không cần kết nối trình duyệt để dùng CLI: phiên Supabase CLI đã xác thực. Phiên CUA hiện chưa có trình duyệt kết nối nên chưa thực hiện được QA giao diện.
