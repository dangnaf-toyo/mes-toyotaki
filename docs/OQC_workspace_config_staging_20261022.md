# OQC bố cục nhập liệu - CAPA tùy chỉnh - thu gọn kế hoạch tuần

Đích duy nhất: https://mes-toyotaki.dangnaf.workers.dev/ — Supabase jcjbleugnclzsghfpmvk.
Tiếp nối staging 197568e (T134), không thay bằng master/main.

## Chức năng
- Thanh chức năng giữ nguyên, thêm Dashboard OQC. Nhập báo cáo ngày/CAPA đổi vùng nội dung trong cùng trang, không mở popup/tab/trang mới. Chi tiết báo cáo và trình xem ảnh vẫn giữ nguyên.
- Form báo cáo: hàng thông tin đầu; nhân viên/giờ/OK/NG bên trái, nhóm lỗi bên phải; danh sách dài cuộn riêng; ảnh thumbnail và Lưu ở cuối. Hướng dẫn dài chuyển tooltip; thông tin phụ vẫn truy cập được. Model, nhân viên, lỗi và đường lưu dùng nguồn hiện có; không tạo danh mục trùng.
- CAPA hai cột, lịch sử thu gọn. Giờ/người/ngày và hiệu suất mục tiêu do người có quyền nhập. Chưa lưu thì để trống, không tự lấy 7 giờ/90%. Cấu hình dùng chung OQC theo ngày áp dụng; thay đổi tạo phiên bản, không ghi đè phiên bản cũ. CAPA kế hoạch làm tròn xuống PCS.
- Kế hoạch liên kết cũ chưa chụp cấu hình dùng cấu hình hiệu lực; plan basis đã chụp nhưng thiếu cấu hình giữ nguyên NULL, không gán ngược dữ liệu mới.
- Dashboard tính nhân lực theo cấu hình từng ngày/snapshot, hiệu suất thực tế = giờ chuẩn/giờ công; mục tiêu lấy từ snapshot đã lưu. Khi gộp nhiều mục tiêu, so sánh theo trọng số giờ công. Thiếu dữ liệu thì báo rõ.
- Kế hoạch tuần OQC chỉ còn số lượng; bỏ nhãn nhân lực, khối tổng và các phần nhập giờ/preview bổ sung. Giữ nguyên RPC lưu, nhập Excel, tổng tuần, thêm/sửa/gửi duyệt. Không sửa logic ca máy T134 hay tab khác.

## Migration đã chạy trên staging
File: supabase/migration_phase_oqc_workspace_config_20261022_staging.sql.
- Thêm oqc_planning_config_version (ngày hiệu lực, giờ, tỷ lệ mục tiêu, người/thời điểm tạo); RLS cho người đăng nhập đọc, chỉ admin/QC Manager được lưu qua RPC; cấm sửa/xóa phiên bản.
- oqc_inspection_work: thêm planning_config_version_id, bỏ default/khóa bằng 7/.9, cho phép NULL khi chưa có cấu hình và kiểm tra giá trị nhập hợp lệ. Giá trị 7/.9 vốn đã lưu trên báo cáo cũ giữ nguyên.
- oqc_dashboard_plan_basis: thêm cột phiên bản/giờ/mục tiêu cho snapshot mới; bản cũ thiếu cấu hình không tự gán cấu hình mới và hiển thị chưa đủ dữ liệu nhân lực nếu cần.
- Thêm RPC oqc_save_capa_config(text,date,jsonb,numeric,numeric) lưu CAPA + cấu hình trong cùng transaction. Cập nhật writer dashboard để chụp cấu hình cho báo cáo mới, giữ snapshot khi sửa cùng ngày/model/phạm vi; giữ CAS, chống trùng, validation giờ công, NG và audit. Info RPC trả planning_config_version=1.
- Không UPDATE/DELETE/backfill dữ liệu nghiệp vụ, không tạo giá trị mặc định, không đổi vai trò/danh mục hoặc kết nối production. RPC báo cáo ngày và writer cũ T73 giữ nguyên thân hàm.
- Sau migration và smoke ROLLBACK, hash báo cáo/giờ công/context/định mức/plan basis/kế hoạch tuần được đối chiếu với trước. 5 báo cáo giữ hash 87f2efca44d86a3ebf0dbeae45cb50f4.

## Kiểm tra
- 12 nhóm JSDOM OQC: mở form trong trang, lưu/nạp cấu hình, thiếu backend/quyền, dữ liệu lịch sử, ảnh, NG/OK/giờ công.
- 15 nhóm PostgreSQL cục bộ: migration lặp lại, không đổi dữ liệu cũ, snapshot, thiếu cấu hình, save/retry, phân quyền, bất biến lịch sử.
- 6 nhóm công thức: giờ thập phân, mục tiêu tùy chỉnh, làm tròn PCS, cộng model trước làm tròn người, hiệu suất 80% khác hoàn thành KH 100%, thiếu dữ liệu.
- 9 nhóm Chromium: 1366×768, 390×844, 102 dòng lỗi cuộn riêng và không cuộn trang desktop, ảnh/zoom, form/CAPA trong trang, không lỗi JS, kế hoạch tuần chỉ hiện số lượng.
- 2 nhóm kế hoạch tuần: không chèn DOM nhân lực/không gọi API CAPA, giữ đường lưu/duyệt.
- Smoke RPC thật staging trong transaction ROLLBACK: lưu/đọc lại cấu hình và báo cáo, cùng ID khi retry, hiệu suất 80%, giữ snapshot khi đổi cấu hình. Không để lại dữ liệu thử. Sequence có thể tăng sau rollback, không ảnh hưởng dữ liệu cũ.
- UI/browser dùng API/storage mô phỏng; chưa đăng nhập tài khoản MES để E2E trình duyệt trực tiếp. Kiểm thử RPC thật qua Management API đặt đúng identity staging admin, kiểm tra quyền trực tiếp/RLS bằng PostgreSQL và catalog.
- Build asset tĩnh và Wrangler dry-run trước deploy; đối chiếu asset live sau deploy.

## File thay đổi
- oqc-daily.html; khsx-tuan.html: nạp asset mới theo phiên bản.
- shared/oqc-workspace.js; shared/oqc-workspace.css: bố cục trong trang, nhóm lỗi, thumbnail.
- shared/oqc-dashboard.js; shared/oqc-dashboard-math.js: cấu hình, công thức, snapshot/hiển thị.
- shared/qc-production-staff.js: bỏ hiển thị nhân lực, giữ hours() trả object rỗng để không đổi giờ khi lưu kế hoạch.
- supabase/migration_phase_oqc_workspace_config_20261022_staging.sql.
- tests/oqc-dashboard-ui.cjs; tests/oqc-dashboard-browser.cjs; tests/oqc-dashboard-fixture.cjs; tests/oqc-dashboard-postgres.cjs; tests/oqc-dashboard-weekly.cjs; tests/oqc-workspace-postgres.cjs; tests/oqc-workspace-math.cjs.
- Tài liệu này. Không deploy production/main.
