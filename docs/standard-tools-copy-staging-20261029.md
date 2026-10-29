# Dụng cụ kiểm tra và sao chép dòng — STAGING 29/10/2026

Phạm vi: quản lý bảng tuần kiểm tiêu chuẩn Đúc/Gia công hiện có. Không thay đổi production.

- `shared/ipqc-btk-qc.js`: dụng cụ chọn từ đúng 12 giá trị người dùng yêu cầu; kiểm tra cả gửi duyệt và nhập Excel. Dụng cụ để trống vẫn được phép như trước. File mẫu Excel sử dụng dụng cụ hợp lệ, có danh sách hướng dẫn.
- Mỗi dòng có **Sao chép**. Trong chế độ chỉnh sửa có **Dán** vào dòng đích và **Dán thành dòng mới**. Sao chép tên hạng mục, kiểu, danh nghĩa, hai dung sai, tiêu chuẩn OK/NG, dụng cụ và tần suất. Không sao chép ID bản ghi, ID phiên bản, No hoặc vị trí đo. Dòng mới dùng No lớn nhất + 1. Dán vào dòng đích giữ No và vị trí đo của dòng đích. Dữ liệu sao chép chỉ ở bộ nhớ trang, không ghi clipboard hệ thống hoặc tự lưu database.
- Dữ liệu lịch sử có dụng cụ ngoài danh sách vẫn hiển thị ở lựa chọn bị khóa. Khi tạo phiên bản mới, người dùng cần chọn lại dụng cụ hợp lệ trước gửi duyệt; không tự chuyển đổi dụng cụ cũ.
- `qc-manager.html`, `bieu-do-chat-luong.html`: cập nhật phiên bản cache JS dùng chung.
- `supabase/migration_phase_T186_dung_cu_tieu_chuan.sql`: trigger kiểm tra dụng cụ tại database, áp dụng cả lưu thủ công, nhập Excel và RPC. Không ghi lại các hạng mục lịch sử. Giữ phân quyền và luồng duyệt hiện tại.
- `tests/standard-tools-postgres.cjs`: PASS sao chép độc lập, bỏ ID/No, giữ hiển thị dụng cụ lịch sử; 12 giá trị hợp lệ, chặn giá trị khác, giữ dữ liệu cũ, cho sửa sang dụng cụ hợp lệ; migration có thể chạy lại. Cú pháp JS và `git diff --check` đạt.

Chưa thao tác kiểm thử giao diện bằng phiên trình duyệt đăng nhập.

T186 đã áp dụng lên project STAGING `jcjbleugnclzsghfpmvk`. Trigger hoạt động; trước và sau migration vẫn có 1 hạng mục, checksum không đổi (`cede73d47ec1c78b562abdbfbebf0607`). Chưa áp dụng migration production.
