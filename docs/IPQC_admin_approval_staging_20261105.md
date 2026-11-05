# Quyền admin trong luồng duyệt tiêu chuẩn — STAGING 05/11/2026

Mọi tài khoản có `user_roles.role = admin` trên staging được thực hiện các bước **Kiểm tra**, **Phê duyệt**, **Trả lại** qua các nút đang có. Cùng một admin có thể kiểm tra rồi phê duyệt bản mình soạn, không cần chờ tài khoản khác. Không thêm nút admin riêng; giữ thứ tự trạng thái hiện tại. Các vai trò khác giữ quyền cũ.

- Frontend: `IpqcBtkQc.quyen` cấp quyền kiểm tra/phê duyệt cho admin trên staging. Các nút và handler chung giữ nguyên, áp dụng bảng tiêu chuẩn kích thước và checklist/PDF, Đúc/Gia công. Không cần gán thêm chức danh GĐSX cho admin. Đã tăng phiên bản cache ở các trang dùng chung.
- T220: lấy đúng định nghĩa `ipqc_tc_duyet` đang chạy từ staging rồi chỉ bổ sung admin vào bốn kiểm tra quyền (kiểm tra, phê duyệt, trả lại ở hai bước). Giữ khóa, ngày hiệu lực, xuất bản theo Model/công đoạn/bước và định danh người thực hiện từ server. Không tự duyệt bản đang có hoặc cập nhật tài khoản.
- T220 chỉ áp dụng project `jcjbleugnclzsghfpmvk`; không đọc/ghi hay triển khai Production.

Kiểm thử PASS:

1. `ipqc-admin-approval-browser.cjs`: 20 tổ hợp vai trò/trạng thái/loại trên Chrome với backend fixture. Kiểm tra nút hiện có, admin tự kiểm tra rồi duyệt, trả lại ở mỗi bước, hủy/xác nhận duyệt, quyền vai trò khác và không mở thêm quyền ở giao diện Production.
2. `ipqc-admin-approval-staging-rollback.sql`: chạy thử rollback trước áp dụng và kiểm thử lại staging thật sau áp dụng. Admin kiểm tra/phê duyệt/trả lại cho bảng kích thước và checklist ở cả Đúc/Gia công; luồng trạng thái giữ đúng; người kiểm tra và người duyệt được ghi đúng UID/thời gian; không tin tên client; ngày hiệu lực tương lai được giữ; vai trò khác không được vượt quyền; anon không có execute. Dữ liệu/quyền thử rollback.
3. Hồi quy `ipqc-standards-manager-browser.cjs` và `ipqc-gc-dom.cjs` PASS. Cú pháp, diff whitespace đạt; kiểm tra tĩnh không có mức CAO/TB.

Checksum dữ liệu được đối chiếu trước/sau: tiêu chuẩn `c1751257394155e5ca28b005467961a0`, đặc tính `a1623957c0336c56696bdece880591d2`, checklist đề xuất `d41d8cd98f00b204e9800998ecf8427e`. Không để lại dữ liệu thử; không thay đổi danh sách 5 admin + 1 OQC.
