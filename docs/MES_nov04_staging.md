# Thay đổi MES — 04/11/2026 — STAGING

Checkout độc lập `.nov04-staging`, nhánh `staging`, nền `ac54148`. Project database duy nhất được dùng: `jcjbleugnclzsghfpmvk`. Không truy cập ghi hoặc migrate production. Checkout gốc đang xung đột được giữ nguyên.

## Nhóm 1 — OQC nhân lực

Thêm số người kiểm mặc định 1; người kiểm chính vẫn là một nhân viên. Ghi thời gian kiểm thực tế, tính giờ công của số người tham gia; giờ riêng của nhân viên đã định danh được ưu tiên. Phân biệt lượt nhân lực và số nhân viên đã định danh không trùng. Người chưa định danh không được tính thành mã nhân viên giả. Năng suất = PCS / tổng giờ công. Không thay công thức CAPA hoặc định mức lịch sử.

T210 thêm hai cột nullable, không backfill. RPC hiện có giữ kiểm tra quyền, phiên bản định mức, CAS, retry và lịch sử, đồng thời lưu nhân lực/thời gian cùng transaction. UI sửa/tải lại và Excel có số người. Không có thời gian thực tế thì không tạo giờ giả.

Kiểm thử: `node tests/oqc-headcount.cjs`, `node tests/oqc-workspace-math.cjs`: PASS; migration chạy thử transaction rollback thành công trên staging. Chưa kiểm thử UI bằng phiên đăng nhập thực tế.

T210 đã áp dụng STAGING; commit nhóm 1 `76f1df2`, push `origin/staging` thành công.

## Nhóm 2 — Phạm vi và gia công ngoài

Nhãn phạm vi dùng một cách viết thống nhất từ `MesOqcScope.labels`. Giữ nguyên mã enum và dữ liệu cũ. Báo cáo gia công ngoài mới phải chọn Mạ/In/Anode; lịch sử chưa phân loại giữ NULL. Các phạm vi khác lưu công đoạn ngoài là NULL. Bộ lọc công đoạn ngoài áp dụng lên cùng tập bản ghi dùng cho dashboard, biểu đồ, OK/NG và Excel; có lựa chọn tổng hợp và chưa phân loại.

T211 thêm cột nullable, cập nhật RPC hiện có với kiểm tra dữ liệu và lịch sử. `node tests/oqc-nov04-postgres.cjs`: PASS lưu/tải nhân lực, chặn count sai, bắt buộc và lưu đúng 3 công đoạn, giữ lịch sử chưa phân loại và kiểm tra quyền. Migration chạy thử rollback trên staging thành công.
