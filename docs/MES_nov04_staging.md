# Thay đổi MES — 04/11/2026 — STAGING

Checkout độc lập `.nov04-staging`, nhánh `staging`, nền `ac54148`. Project database duy nhất được dùng: `jcjbleugnclzsghfpmvk`. Không truy cập ghi hoặc migrate production. Checkout gốc đang xung đột được giữ nguyên.

## Nhóm 1 — OQC nhân lực

Thêm số người kiểm mặc định 1; người kiểm chính vẫn là một nhân viên. Ghi thời gian kiểm thực tế, tính giờ công của số người tham gia; giờ riêng của nhân viên đã định danh được ưu tiên. Phân biệt lượt nhân lực và số nhân viên đã định danh không trùng. Người chưa định danh không được tính thành mã nhân viên giả. Năng suất = PCS / tổng giờ công. Không thay công thức CAPA hoặc định mức lịch sử.

T210 thêm hai cột nullable, không backfill. RPC hiện có giữ kiểm tra quyền, phiên bản định mức, CAS, retry và lịch sử, đồng thời lưu nhân lực/thời gian cùng transaction. UI sửa/tải lại và Excel có số người. Không có thời gian thực tế thì không tạo giờ giả.

Kiểm thử: `node tests/oqc-headcount.cjs`, `node tests/oqc-workspace-math.cjs`: PASS; migration chạy thử transaction rollback thành công trên staging. Chưa kiểm thử UI bằng phiên đăng nhập thực tế.
