# OQC ba phạm vi - thứ tự lỗi - dashboard gọn

Chỉ staging: https://mes-toyotaki.dangnaf.workers.dev/oqc-daily.html
Supabase: jcjbleugnclzsghfpmvk. Tiếp nối staging 12c6061, không thay bằng master/main.

## Thay đổi
- Form, bộ lọc và chi tiết dùng thống nhất: Kiểm tra sau gia công (giữ mã FULL_POST_MACHINING), Kiểm tra sau Sơn (POST_PAINTING), Kiểm tra sau Gia Công ngoài (POST_OUTSOURCED_MACHINING).
- Bộ lọc vẫn cho xem Tất cả, Chưa xác định và Phạm vi cũ khác để giữ truy cập dữ liệu lịch sử SAMPLING/OTHER/NULL. Khi sửa báo cáo cũ chưa xác định hoặc phạm vi cũ, giữ nguyên phạm vi; không tự gán sang phạm vi mới. Các lựa chọn cũ chỉ hiện dạng khóa khi sửa đúng báo cáo đó.
- Bỏ ô LOT khỏi form; giữ input nội bộ ẩn để bảo toàn LOT cũ khi sửa. Báo cáo mới không nhập LOT; thông tin LOT trong lịch sử vẫn xem được.
- Danh mục có sort_order nhưng không có mức nghiêm trọng. Theo xác nhận của người dùng: giữ thứ tự cấu hình, cho admin/QC Manager dùng ↑/↓ và Lưu thứ tự riêng OQC. Không tự gán mức nghiêm trọng, không sửa danh mục chung IQC/IPQC. Thứ tự lưu theo phiên bản, kiểm tra xung đột trước ghi; đổi thứ tự không mất số lượng/chi tiết đang nhập.
- Báo cáo mới bỏ mã iqc_7f55011aff5e (Kích thước lệch) khỏi ngoại quan; Sai kích thước vẫn thuộc NG kích thước. Không đổi/xóa mã trong danh mục chung hoặc lỗi/ảnh/nhóm lỗi của báo cáo cũ. Form sửa báo cáo cũ vẫn đọc được mã lỗi đó.
- CAPA bỏ thanh tiêu đề thừa, giữ thanh chức năng và bố cục nhập hiện tại.
- Dashboard còn 9 KPI và 9 cột theo model; bỏ cột/khối nhân lực, bảng đề xuất theo ngày và các đoạn công thức/hướng dẫn dài. Dữ liệu CAPA/nhân lực nguồn không bị xóa. Thiếu số liệu hiển thị —, lý do và mục tiêu hiệu suất xem bằng tooltip. Biểu đồ trống/không có NG/lỗi chỉ hiện Chưa có dữ liệu.

## Ranh giới nguồn dữ liệu
Kế hoạch tuần hiện liên kết kiểm sau gia công, CAPA hiện lưu theo model thuộc phạm vi này. Không tự lấy KH/CAPA sau gia công gán cho Sơn/Gia Công ngoài. Hai phạm vi mới vẫn lưu/lọc đủ sản lượng, NG/OK, ảnh và giờ công; kế hoạch/hiệu suất thiếu nguồn đúng phạm vi hiện — với tooltip. Không thay chức năng kế hoạch tuần hoặc cấu hình giờ/hiệu suất đã triển khai.

## Migration staging
supabase/migration_phase_oqc_scopes_order_20261022_staging.sql đã áp dụng:
- Mở rộng CHECK của oqc_inspection_context.inspection_scope; giữ các giá trị cũ, không UPDATE/backfill phạm vi.
- Thêm oqc_defect_order_version chỉ lưu thứ tự các mã từ danh mục trung tâm, người/thời điểm lưu; RLS cho tài khoản đăng nhập đọc, không cho ghi trực tiếp, phiên bản bất biến.
- Thêm oqc_save_defect_order(text[],bigint): admin/QC Manager; kiểm tra đúng danh mục, không lặp mã, khóa ghi và kiểm tra phiên bản để tránh ghi đè người khác.
- Cập nhật validation trong oqc_save_dashboard_inspection cho ba phạm vi mới, giữ CAS/chống gửi trùng/giờ công/ảnh/audit/snapshot; chặn tự phân loại dữ liệu cũ chưa rõ. oqc_dashboard_info thêm inspection_scope_version=2.
- Giữ nguyên hàm báo cáo ngày, CAPA/config và writer T73; không thay quyền cũ hoặc danh mục chung. Không chạy SQL trên production.
- Hash 5 báo cáo, context, work, basis, danh mục lỗi, định mức/config, kế hoạch tuần và các RPC giữ nguyên đã đối chiếu trước/sau migration. Hash báo cáo: 87f2efca44d86a3ebf0dbeae45cb50f4.

## Kiểm tra
- 16 nhóm JSDOM OQC: ba phạm vi lưu/lọc/chi tiết, dữ liệu legacy, LOT ẩn vẫn bảo toàn, lỗi/ảnh cũ, thứ tự lỗi mới, KPI/tooltip/biểu đồ trống và hồi quy cấu hình/report.
- 19 nhóm PostgreSQL cục bộ: migration lặp lại, dữ liệu cũ, ba scope lưu độc lập, không gán CAPA khác phạm vi, cấu hình/snapshot, order/CAS/RLS/quyền và danh mục chung bất biến.
- 10 nhóm Chromium desktop 1366×768/mobile 390×844: không lệch/không cuộn trang nhập desktop, 102 lỗi cuộn riêng, không LOT/CAPA header, ba scope native chọn/lưu/lọc/chi tiết, ảnh/zoom và kế hoạch tuần; không page errors.
- 6 nhóm công thức + 2 nhóm kế hoạch tuần vẫn qua. Tổng 53 nhóm.
- Smoke RPC thật staging lưu/đọc cả ba scope và thứ tự lỗi trong transaction ROLLBACK; danh mục chung không đổi, không gán CAPA sau gia công cho phạm vi khác. Không để lại dữ liệu thử; sequence có thể tăng sau rollback.
- Browser/UI dùng API/storage mô phỏng. Chưa đăng nhập MES để E2E trình duyệt trực tiếp. API thật kiểm qua Management SQL và schema cache/anonymous guard sau deploy.
- Build và Wrangler dry-run trước deploy; đối chiếu asset live. Không push/deploy production/main.

## File
- oqc-daily.html: phiên bản asset.
- shared/mes-oqc-scope.js; shared/oqc-dashboard.js: lựa chọn/nhãn/chi tiết, lọc, tooltip/KPI/bảng gọn.
- shared/oqc-workspace.js; shared/oqc-workspace.css: LOT ẩn, thứ tự lỗi, bỏ CAPA header, bố cục gọn.
- shared/oqc-defect-charts.js: trạng thái trống một dòng, công thức mẫu số chuyển tooltip.
- supabase/migration_phase_oqc_scopes_order_20261022_staging.sql.
- tests/oqc-dashboard-fixture.cjs; tests/oqc-dashboard-ui.cjs; tests/oqc-dashboard-browser.cjs; tests/oqc-dashboard-postgres.cjs; tests/oqc-scopes-order-postgres.cjs.
- Tài liệu này.
