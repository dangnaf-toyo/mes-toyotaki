# Sửa bổ sung phạm vi OQC — 04/11/2026

Chỉ nhánh `staging`, nền `40f1463`; database staging `jcjbleugnclzsghfpmvk`. Không ghi/migrate production, không viết lại commit đã push. Checkout độc lập `.nov04-staging`; giữ nguyên checkout gốc đang có xung đột.

## Đã sửa

- Giữ trường công đoạn ngay bên dưới ô PHẠM VI và bên trong cùng khối, để bố cục compact không loại trường khi dựng lại form. Chỉ hiện cho Gia công ngoài; chọn đơn Mạ/In/Anode, bắt buộc với báo cáo mới và báo cáo đã phân loại. Mở lại đúng giá trị; lịch sử chưa phân loại vẫn để trống/NULL và có thể sửa nội dung khác mà không bị tự phân loại.
- Giữ trường số người kiểm khi dựng lại form. Đây là sửa tích hợp cần thiết vì trường bị loại khỏi DOM làm thao tác mở form/lưu báo cáo lỗi; không thay công thức CAPA, giờ công hoặc nghiệp vụ nhân lực.
- Nhãn dùng chung trong cột PHẠM VI của tổng hợp, lịch sử, chi tiết và Excel: `Kiểm tra sau Gia Công ngoài - Mạ/In/Anode`, `Kiểm tra sau gia công`, `Kiểm tra sau Sơn`. Không thêm cột công đoạn riêng vào dashboard.
- Một bộ lọc PHẠM VI gồm tất cả, ba phạm vi chính và ba công đoạn ngoài chi tiết; giữ các lựa chọn dữ liệu cũ. Bỏ bộ lọc công đoạn rời. Gia công ngoài tổng hợp gồm cả lịch sử NULL; các công đoạn chi tiết chỉ lấy đúng mã đã lưu.
- Cùng tập bản ghi đã lọc dùng cho OK/NG, tỷ lệ, số đã kiểm, biểu đồ, bảng và Excel. Khóa nhóm thêm công đoạn để không gộp Mạ/In/Anode với nhau hoặc với lịch sử NULL; bấm dòng tổng hợp mở đúng nhóm. Bảng chi tiết xu hướng cũng tách công đoạn.
- Sửa hàm Excel đang thực sự được dùng trong `mes-oqc-record.js` (hàm này ghi đè hàm gốc trong HTML). Giữ các cột lỗi/LOT/Task và dữ liệu đang xuất; thêm nhãn PHẠM VI đầy đủ vào cùng tập báo cáo đã lọc.
- Tăng bề rộng bộ lọc PHẠM VI và giữ ô chọn đủ rộng trên điện thoại; phần kết quả kiểm không bị ép thành cột hẹp cạnh form. Cập nhật cache các asset thay đổi.

## Database staging

Cột `cong_doan_gia_cong_ngoai` và kiểm tra ba giá trị đã có từ T211, không cần thêm cột/bảng. Kiểm thử với trigger thật phát hiện writer gốc xóa cờ `mes.oqc_dashboard_write` trước khi trả về; bước update metadata của wrapper T211 vì vậy bị trigger bảo vệ chặn.

T216 chỉ thay định nghĩa `oqc_save_daily_report`: sau writer gốc, cho phép riêng bước cập nhật metadata của wrapper đáng tin cậy; sau đó khôi phục cờ transaction trước đó. Không nới quyền table, không tắt trigger, không backfill. Giữ auth/role, CAS, request ID/retry, snapshot CAPA và audit hiện có. T216 đã áp dụng riêng staging.

## Kiểm thử

- PASS `tests/oqc-outsource-browser.cjs` bằng Chrome headless thật, API fixture cách ly: tạo đủ ba công đoạn, chặn thiếu lựa chọn, chọn đơn, đổi phạm vi ẩn/hiện, vị trí dưới scope, mở lại/sửa/xem đúng giá trị; bộ lọc mọi phạm vi; tổng hợp OK/NG/tỷ lệ; hàm Excel thực; tổng hợp/drilldown/lịch sử/bảng xu hướng có nhãn và nhóm đúng; giữ NULL lịch sử. Kiểm tra desktop 1366px và mobile 390px, không có page error. Đã xem ảnh chụp form/dashboard/mobile trong `.review/` (không commit dữ liệu/ảnh thử).
- PASS `tests/oqc-outsource-staging-rollback.sql` qua RPC và trigger thật: tạo/lưu/mở lại/sửa Mạ/In/Anode; retry không trùng; chặn thiếu/sai/nhiều giá trị; giữ NULL lịch sử; cờ writer không rò rỉ và thao tác cập nhật kiểu cũ vẫn bị chặn; anon không gọi được API ghi. Chạy cả trước áp dụng T216 trong dry-run và sau áp dụng. Tất cả dữ liệu thử rollback.
- Sau rollback: vẫn 6 báo cáo OQC; checksum toàn bộ bản ghi giữ nguyên `bce5300d0f8ce1da7fe7d937dcb6af84` giữa các lần kiểm thử. Không để lại báo cáo thử hoặc thay đổi dữ liệu lịch sử.
- PASS `tests/oqc-nov04-postgres.cjs` (gồm T216), `tests/oqc-headcount.cjs`, `tests/oqc-workspace-math.cjs`, `tests/mes-nov04-integration.cjs`.
- Rà soát bằng `scripts/code-review-check.cjs`: không còn mức CAO. Các cảnh báo định dạng và câu thông báo cũ mức THẤP không liên quan nghiệp vụ mới.

Lệnh Chrome: đặt `MES_PLAYWRIGHT_PATH` tới thư viện Playwright đã có trong môi trường, rồi `node tests/oqc-outsource-browser.cjs`. Fixture được bổ sung phương thức `overlaps` đang được catalog lỗi hiện tại sử dụng.

File chính: `oqc-daily.html`, `shared/oqc-scope.js`, `shared/mes-oqc-{scope,history,record}.js`, `shared/oqc-dashboard{,-math}.js`, `shared/oqc-defect-charts.js`, `shared/oqc-workspace.{js,css}`, migration T216 và các test liên quan. Không làm lại module hoặc đổi mã phạm vi đã lưu.

Giới hạn kiểm thử: Chrome dùng API fixture; việc ghi/đọc backend thật được kiểm riêng bằng RPC staging trong transaction rollback. Không dùng thông tin đăng nhập của người dùng để tạo báo cáo thử lâu dài.

Rollback ứng dụng bằng một commit revert trên staging; không force push. T216 không thay schema/dữ liệu. Nếu cần khôi phục wrapper cũ, tạo migration tiếp theo từ định nghĩa T211 (lỗi guard của bản cũ sẽ trở lại), giữ nguyên cột và dữ liệu công đoạn đã ghi.
