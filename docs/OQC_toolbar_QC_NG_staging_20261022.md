# OQC thanh chức năng - QC Giám sát gọn nhãn NG

Chỉ staging: https://mes-toyotaki.dangnaf.workers.dev/

## Thay đổi
- OQC kiểm tra: chuyển Nhập báo cáo ngày, CAPA, Kế hoạch tuần OQC lên thanh trên sau Đóng gói Pallet và KHSX tuần; cùng kiểu, chiều cao tối thiểu 34px và khoảng cách 8px; tự xuống dòng trên điện thoại. Bỏ hàng nút riêng bên dưới, giữ thông báo và dashboard trong nội dung chính.
- QC Giám sát: cột Kết quả chỉ giữ nhãn NG. Thông tin trạng thái, thao tác chuyển NG và xem quyết định nằm trong Chi tiết lượt kiểm. Giữ quyền, API, chống gửi trùng, cập nhật realtime/15 giây, nội dung quyết định và kết quả NG gốc. Chi tiết dùng chung cho bảng gần đây/lịch sử trong QC Giám sát.

## File
- oqc-daily.html; shared/oqc-dashboard.js: thanh chức năng và bố cục.
- qc-manager.html; shared/mes-ng-status.js: điểm gắn phần duyệt vào popup Chi tiết; bỏ phần chèn vào cột kết quả.
- tests/oqc-dashboard-ui.cjs; tests/oqc-dashboard-browser.cjs; tests/qc-session-ui.cjs; tests/qc-manager-layout-browser.cjs: kiểm chứng bố cục và hồi quy.
- Tài liệu bàn giao này.

## Kiểm tra
- 10 nhóm OQC UI: form, CAPA, kế hoạch, giờ công, NG/OK, lịch sử và phân quyền.
- 16 nhóm IPQC/QC: phiên kiểm, ảnh, NG, chi tiết duyệt, chống gửi trùng, lỗi backend và khóa quyền. Chạy qua qc-unaffected-regressions.cjs qc-session-ui.cjs; 2 assertion OQC cũ được thay bằng bộ dashboard hiện hành như trước.
- 7 nhóm Chromium OQC + 2 nhóm Chromium QC Giám sát: desktop 1440px/mobile 390px; thứ tự 5 nút, cùng hàng trên desktop, tự xuống dòng mobile, mở form/CAPA, chi tiết NG và quyết định, không lỗi JavaScript. Đã xem ảnh chụp desktop/mobile.
- Kiểm thử UI dùng API/storage mô phỏng; không ghi dữ liệu MES thật. Chưa đăng nhập tài khoản MES để E2E trực tiếp trên staging.
- Kiểm tra cú pháp script và git diff --check.

## Triển khai
- Build asset tĩnh, Wrangler dry-run trước khi deploy worker mes-toyotaki, chỉ đẩy nhánh staging.
- Tiêu đề: OQC thanh chức năng - QC Giám sát gọn nhãn NG.
- Không cần migration; không đổi schema, dữ liệu, quyền hoặc cấu hình database. Không thao tác production/main.
- Sau deploy đối chiếu checksum toàn bộ asset với build và xác minh frontend dùng Supabase staging jcjbleugnclzsghfpmvk.
