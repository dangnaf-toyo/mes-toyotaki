# Sửa IPQC Gia công — STAGING — 05/11/2026

Nền `b3b67b4`, nhánh staging, đã fast-forward để giữ đủ thay đổi mới của đồng đội. Chỉ database `jcjbleugnclzsghfpmvk`; không truy cập ghi/migrate production.

## Khảo sát và sửa lỗi tải dữ liệu (nhóm 1, 2, 6)

`Qc02Data.readAll` chỉ có quy tắc sort Model (`ma_sp`) hoặc nhân viên (`ten_nhan_vien`). Module cũ dùng hàm này để đọc `master_machines`, khiến truy vấn order theo cột không tồn tại. Đây là nguyên nhân thông báo đỏ chung làm quá trình khởi tạo cả ba tab dừng. Sửa riêng module này: đọc danh mục máy theo `ma_may` qua cùng client/RLS và cơ chế phân trang. Không đổi helper dùng cho các module khác.

Chuẩn hóa trạng thái trống thành “Chưa có dữ liệu”, thông báo chưa có tiêu chuẩn phát hành và khóa lưu khi không có căn cứ. Lỗi thật vẫn được báo, chi tiết kỹ thuật có thể mở xem; không chỉ ẩn lỗi.

“Bước gia công” đang là một phần khóa phân biệt tiêu chuẩn cùng Model/Revision, phạm vi phát hành và snapshot truy xuất đo. Giữ cột/dữ liệu và một ô khai báo trong tiêu chuẩn, bổ sung giải thích. Phần nhập đo lấy tự động theo tiêu chuẩn. Dashboard dùng danh sách nguyên công đã có thay cho nhập lại tên tự do. Không xây dựng lại bảng tiêu chuẩn hoặc luồng duyệt.

Preflight staging: 30 máy Gia công, chưa có tiêu chuẩn/đặc tính Gia công, 0 lần đo Gia công/Đúc; roles 5 Admin + 1 OQC. Checksum tiêu chuẩn và đặc tính Gia công đều `d41d8cd98f00b204e9800998ecf8427e` (tập trống). Không tự nhập tiêu chuẩn mẫu lâu dài.

PASS `tests/ipqc-gc-repair-browser.cjs`: Chrome chạy mã `qc02-data.js` thực với API fixture kiểm tra tên cột sort, kiểm tra trạng thái trống và tải đặc tính đã phát hành; không có page error. PASS bài DOM IPQC Gia công hiện có sau cập nhật fixture danh mục máy. Kiểm thử ghi dữ liệu thật sẽ dùng transaction rollback; tiêu chuẩn hiện có được giữ nguyên.
