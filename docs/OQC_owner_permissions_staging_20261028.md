# OQC — quyền người nhập / Admin, staging 28/10/2026

Đã triển khai migration T177 và frontend lên **staging**. Không triển khai production.

## Quy tắc

- Chủ báo cáo là `oqc_daily_inspection.created_by = auth.uid()` tại lúc tạo. Không suy quyền từ người kiểm hoặc người phân bổ giờ công được chọn trên form.
- Người có quyền nhập OQC chỉ sửa/xóa báo cáo do tài khoản mình tạo. QC Manager cũng tuân theo quy tắc sở hữu này.
- Admin sửa/xóa mọi báo cáo; báo cáo cũ thiếu `created_by` chỉ Admin thao tác. Không backfill/suy đoán người tạo.
- Giao diện ẩn Sửa/Xóa nếu không đủ quyền; gọi thẳng hàm giao diện hoặc RPC cũng không vượt quyền. Khi không xác minh được quyền thì không hiển thị thao tác.
- Xóa có xác nhận và kiểm tra `updated_at` để tránh xóa nhầm phiên bản đã bị người khác sửa. Thao tác loại báo cáo khỏi danh sách/tổng hợp, giữ bản ghi, ảnh, work/context và audit để truy vết. Không xóa vĩnh viễn; không cho sửa báo cáo đã xóa hoặc đổi người tạo.
- Tạo mới vẫn giữ các quyền module đang có. Không thay đổi quyền CAPA, danh mục, IQC hay tài khoản.

## Database

T177 thêm `da_xoa`, `ngay_xoa`, `nguoi_xoa`; trigger bảo vệ mọi đường ghi vào bảng chính, kể cả RPC cũ; RPC `oqc_quyen_bao_cao()` và `oqc_xoa_bao_cao(bigint,timestamptz)` chỉ cấp authenticated, kiểm tra người dùng phía server.

RLS SELECT loại báo cáo đã xóa. Các SQL SECURITY DEFINER bypass RLS được giữ nguyên quy tắc, chỉ lọc nguồn OQC chưa xóa: `oqc_capacity_report`, `tong_quan_hom_nay`, `wallboard_pchart`. Truy vấn giới hạn giờ công của `oqc_save_dashboard_inspection` cũng loại báo cáo đã xóa để không giữ sai giờ công. Không sửa UI/công thức khác của các module này.

Migration đã chạy thử rollback trước khi áp dụng; chạy lặp lại an toàn. Trước/sau áp dụng và kiểm thử thật: **6 báo cáo**, checksum các cột gốc **a944da6651dc19d20fcf3695c9a697ec**, không đổi. Không có báo cáo thật nào bị sửa/xóa bởi phiên làm việc này.

## Kiểm thử

- PostgreSQL/PGlite: **15 nhóm PASS**, gồm regression OQC và 5 nhóm quyền mới: tạo đúng chủ, chống giả người tạo, owner/other QC Manager/Admin, RPC hiện tại/cũ, stale timestamp, giữ bản ghi/audit, RLS, không phục hồi bằng update, không giữ giờ công báo cáo đã xóa, từ chối anonymous.
- Chromium: **4 nhóm PASS** cho nhân viên OQC, QC Manager, Admin, người chỉ xem. Đúng nút của từng chủ báo cáo; gọi hàm trực tiếp bị chặn; chống gửi xóa hai lần; xóa xong đọc lại Dashboard. API/Storage trong browser được mô phỏng.
- Regression: **4 nhóm scope/rate** và **10 nhóm IQC** PASS, không pageerror.
- Staging thật: `tests/oqc-owner-staging.sql` dùng các tài khoản Admin/OQC hiện có trong transaction rollback. PASS owner sửa/xóa, owner bị chặn sửa/xóa báo cáo Admin, Admin sửa/xóa báo cáo của owner, giữ `created_by`, RLS ẩn bản đã xóa và giữ record/work/audit. Mọi dòng thử ID âm đã rollback, không tạo tài khoản hay thay đổi vai trò.
- HTTP anonymous thật: hai RPC mới đều HTTP **401 / 42501**. Không cấp quyền PUBLIC/anon.
- Review/cú pháp và `git diff --check` đạt, không mức CAO/TB. Chưa kiểm thử E2E bằng phiên MES đăng nhập trong trình duyệt người dùng.

Lệnh PostgreSQL: đặt `MES_PGLITE_PATH`, `MES_TEST_OQC_OWNER=1`, chạy `node tests/oqc-dashboard-postgres.cjs`. Browser: `node tests/oqc-owner-browser.cjs`.

## File

- `oqc-daily.html`
- `shared/oqc-report-access.js` (mới)
- `shared/oqc-dashboard.js`
- `shared/mes-oqc-history.js`
- `supabase/migration_phase_T177_oqc_quyen_nguoi_nhap.sql` (mới)
- `tests/oqc-dashboard-fixture.cjs`, `tests/oqc-dashboard-postgres.cjs`
- `tests/oqc-owner-browser.cjs`, `tests/oqc-owner-postgres.cjs`, `tests/oqc-owner-staging.sql` (mới)
- Tài liệu này.

## Triển khai

Worker version **4be06213-69bb-4e8f-99a7-21e705159c0b**. **101/101 asset** khớp SHA-256 gói frontend; không chứa SQL, test hay dependency. URL: https://mes-toyotaki.dangnaf.workers.dev/oqc-daily.html. Gộp toàn bộ thay đổi yêu cầu này trong một commit riêng trên staging; giữ lịch sử đã chia sẻ.
