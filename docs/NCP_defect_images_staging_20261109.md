# Hình ảnh lỗi NCP — STAGING, 09/11/2026

## Phạm vi

- Chỉ nhánh `staging`, website `mes-toyotaki.dangnaf.workers.dev`, Supabase `jcjbleugnclzsghfpmvk`.
- Không truy cập hay thay đổi database Production. Không sửa trạng thái, số lượng, hạn trả lời, quy trình duyệt hoặc công thức xử lý NCP.
- Cơ sở trước sửa: `b0f15b3`, đã fast-forward từ `origin/staging`.

## Thay đổi

- `qc-manager.html`: mục **Hình ảnh lỗi** ngay dưới mô tả; hỗ trợ phiếu thủ công và từ NG. Giữ nguyên kiểm tra thông tin phiếu hiện tại.
- `shared/mes-ncp-source.js`: dùng bộ đính kèm chung thay cho input ảnh cũ chỉ có ở nguồn thủ công.
- `ncp-detail.html`: hiển thị đầy đủ ảnh, thêm ảnh sau khi tạo, xóa có lịch sử. Bằng chứng IPQC gốc vẫn hiển thị riêng và vẫn có trong bản in cùng ảnh lỗi.
- `shared/ncp-defect-images.js`, `.css`: chọn nhiều JPG/JPEG/PNG/WEBP, thumbnail, phóng to bằng trình xem ảnh có sẵn, thay/xóa trước lưu, kiểm tra file, lưu và thử lại khi lỗi mạng.
- Migration `T228_ncp_hinh_anh_loi`: bucket riêng tư `ncp-hinh-anh`, bảng liên kết ảnh, nhật ký thêm/xóa, mã yêu cầu chống tạo trùng khi thử lại. Gọi lại các hàm mở phiếu hiện có, không thay thế nghiệp vụ của chúng. Phiếu và liên kết ảnh được ghi cùng transaction.
- Giữ nguyên `source_images` trên phiếu cũ, sao chép liên kết sang bảng ảnh; không sửa file cũ. Trigger tiếp nhận ảnh từ client cũ nếu một tab chưa tải lại vẫn dùng RPC cũ.

## Giới hạn và quyền

- Tối đa 10 ảnh đang hiển thị mỗi phiếu; 5 MiB/file đầu vào; tối đa 24 triệu điểm ảnh. Ảnh lớn được giới hạn cạnh dài 4096 px.
- Kiểm tra phần mở rộng, MIME, chữ ký định dạng và khả năng giải mã. Chỉ lưu lại pixel đã giải mã dưới dạng JPEG; không lưu file gốc có thể chứa nội dung khác. Tên file hiển thị giữ nguyên.
- Bucket chỉ nhận JPEG tối đa 5 MiB; object không được ghi đè/xóa qua client. RPC kiểm tra object đã tồn tại, chủ upload, đường dẫn, MIME và dung lượng trước khi liên kết.
- Tài khoản `chi_xem`/chưa có vai trò không được sửa ảnh. Trên phiếu, Admin/Quản lý QC/GĐSX/IPQC, người mở hoặc người được giao xử lý/trả lời có quyền thêm/xóa, theo cách xác định người phụ trách sẵn có. Server kiểm lại quyền, không chỉ ẩn nút.
- Xóa ảnh là xóa khỏi hiển thị; giữ object và metadata để truy vết, ghi người thực hiện, thời điểm, số phiếu và tên file. Không đổi trạng thái duyệt của phiếu.
- URL ảnh mới được ký lại khi mở phiếu và khi bấm phóng to. Các file đã upload nhưng chưa liên kết do hủy form/lỗi mạng vẫn riêng tư; chưa bổ sung tác vụ dọn file tự động.

## Kiểm thử

1. **Chromium thực, API/storage giả lập** — `tests/ncp-images-browser.cjs`: tạo thủ công 1 ảnh; nguồn NG nhiều ảnh PNG/WEBP; không ảnh; chọn nhiều, thay/xóa trước lưu; phóng to; mở lại/tải lại; bổ sung ảnh; lỗi upload và mất phản hồi sau commit; thử lại không trùng; xóa và lịch sử; quyền chỉ xem; ảnh và bằng chứng checkpoint trong bản in; layout điện thoại; không lỗi JavaScript.
2. **RPC và RLS thật trên database STAGING**, trước và sau áp dụng migration — `tests/ncp-images-staging-rollback.sql`: transaction luôn `ROLLBACK`; tạo 0/1/nhiều ảnh theo cả nguồn thủ công/NG; liên kết đúng phiếu/checkpoint; rollback cả phiếu nếu ảnh lỗi; idempotency; thêm/xóa có audit; không đổi JSON dữ liệu phiếu; chặn tài khoản không quyền/chỉ xem; sai MIME/dung lượng/chủ file/đường dẫn; giới hạn 10 ảnh; không cho ghi bảng hay giả nhật ký trực tiếp; kiểm tra storage RLS và tương thích `source_images` cũ. Object trong test SQL là metadata fixture, không phải upload file vật lý.
3. **Hồi quy NCP thật trong ROLLBACK** — `tests/ncp-integration-rollback.sql`: đồng bộ đối sách, khóa phê duyệt, lịch sử, aggregate và quyền writer đều đạt.
4. **Hồi quy Chromium** — `tests/qc-manager-layout-browser.cjs`, `tests/qc-photo-browser.cjs`: luồng NG/duyệt hiện có và trình xem ảnh desktop/mobile đều đạt. Bổ sung stub `sbTaiHet` vào fixture layout test để hỗ trợ board đối sách đã có; không sửa code board.
5. **Bảo toàn dữ liệu**: checksum toàn bộ 3 phiếu NCP trước/sau bằng nhau; mảng ảnh cũ, định nghĩa các RPC nghiệp vụ hiện có, vai trò và policy storage cũ giữ nguyên. Không lưu fixture thử nghiệm vào dữ liệu nghiệp vụ.
6. **Schema triển khai** — `tests/ncp-images-schema-staging.sql`; **asset sau build** — `tests/check-ncp-images-staging.cjs`.
7. JavaScript syntax, inline script syntax và `git diff --check` đạt. Code review checker không phát hiện mức cao/trung bình; cảnh báo thấp chủ yếu liên quan code nén/font/thông báo lỗi cũ và ghi chú migration chỉ dành cho staging.

Chưa nghiệm thu upload file vật lý qua tài khoản đăng nhập trên website: phiên công cụ hiện không có trình duyệt kết nối. Kiểm thử giao diện dùng API giả lập; kiểm thử database/RLS dùng staging thật và rollback. Không coi các bài kiểm thử này là đăng nhập và upload trực tiếp trên website.
