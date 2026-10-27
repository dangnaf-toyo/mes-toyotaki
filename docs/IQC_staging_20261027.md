# IQC staging — 27/10/2026 (GMT+7)

Trạng thái: **đã push staging và triển khai frontend + migration T176; đã kiểm thử DB staging trong transaction rollback. Chưa kiểm thử E2E bằng phiên đăng nhập người dùng trong trình duyệt**.

Nhánh `fix/iqc-dashboard-staging-20261027`, từ `origin/staging` commit `97fda9c`. Worktree `.iqc-dashboard-staging`; checkout gốc có merge conflict được giữ nguyên. Không sửa production, cấu hình Supabase, phân quyền, OQC, IPQC, kho hay sản xuất.

## Phân tích và tái sử dụng

Đã đọc IQC hiện tại, `oqc.html`, `oqc-daily.html`, dashboard/phạm vi OQC và các helper QC chung. OQC hiện tách Dashboard / Nhập báo cáo ngày trên header tối, dùng panel, toolbar, thẻ chỉ số và bảng. IQC dùng lại pattern và token CSS này; giữ nguyên LOT API, form, chi tiết, danh sách lỗi, AQL/N5/100%, ảnh và xác nhận thời gian nhận/bắt đầu/kết thúc hiện có. Phạm vi OQC hiện là các công đoạn sau gia công/sơn/gia công ngoài, khác bảy phạm vi được yêu cầu cho IQC; không sửa danh mục/phép tính OQC.

## File thay đổi

| File | Nội dung |
|---|---|
| `iqc.html` | Hai mục Nhập báo cáo ngày / Dashboard IQC; bỏ input lấy mẫu và payload nhập mẫu; bỏ lọc người kiểm theo vai trò; đọc/ghi Phạm vi và mã/tên người kiểm; hiển thị Phạm vi ở danh sách/lịch sử/chi tiết; đọc hết trang LOT/lỗi; giữ đúng timestamp bắt đầu khi hoàn thành kiểm. |
| `shared/mes-iqc-workspace.js` | Chỉ IQC nạp file này. Dùng nhân sự + tài khoản từ `Qc02Data.employees()` và sản phẩm từ `master_products`; kiểm tra lựa chọn trước lưu; năm NCC; bảy phạm vi bắt buộc; lọc danh sách; dashboard, tỷ lệ OK/NG, biểu đồ thanh theo ngày/tháng/NCC/phạm vi; CSV gồm Phạm vi và ID/tên người kiểm; realtime + polling 15 giây và refresh khi trở lại trang. |
| `supabase/migration_phase_T176_iqc_pham_vi.sql` | Thêm nullable `pham_vi`, `nguoi_kiem_id`, `nguoi_kiem_ten`. Trigger kiểm tra bảy phạm vi/năm NCC ở LOT mới hoặc trường thay đổi. Không backfill, xóa dữ liệu, sửa RLS hay vai trò. |
| `tests/iqc-workspace-browser.cjs` | Chromium với API mô phỏng: luồng nhập/sửa/hoàn thành, nhân sự, sản phẩm, dashboard, dữ liệu cũ, xuất CSV và phân trang. |
| `tests/iqc-workspace-postgres.cjs` | PostgreSQL/PGlite: migration, tính lặp lại an toàn, giữ dữ liệu cũ và kiểm tra giá trị hợp lệ. |
| `scripts/check-iqc-staging.cjs` | Kiểm tra chỉ đọc schema staging và frontend; không tải nội dung LOT hoặc ghi dữ liệu. |
| `docs/IQC_staging_20261027.md` | Bàn giao này. |

## Tương thích dữ liệu cũ

- Giữ `inspector` dạng đang dùng; lưu riêng mã định danh danh mục (`ma_nv`/username, hoặc khóa tên của nhân sự chưa có mã) và tên tại thời điểm lưu. Không đổi người thao tác đăng nhập hay quyền tài khoản theo người kiểm được chọn.
- LOT cũ chưa có Phạm vi hiển thị **Chưa xác định**, nằm nhóm riêng; không tự phân loại.
- Cột `sampled_at` và thông tin mẫu cũ còn nguyên, vẫn xem được ở danh sách/chi tiết; form mới không đọc/ghi trường này.
- NCC lịch sử vẫn hiển thị đúng; khi sửa form phải chọn NCC trong năm giá trị mới và bổ sung Phạm vi. Trigger vẫn cho phép cập nhật riêng ghi chú/trạng thái của LOT cũ mà không sửa các trường này.
- Mã sản phẩm lịch sử đã rời danh mục vẫn được giữ khi sửa cùng LOT; LOT mới phải thuộc danh mục hiện tại. Tên sản phẩm hiện tại được lấy lại khi lưu.
- Dashboard lấy ngày nhận hàng theo GMT+7; tỷ lệ OK/NG dùng số LOT có kết quả làm mẫu số, không đưa LOT chưa có kết quả vào mẫu số.

## Kết quả kiểm tra

- `node tests/iqc-workspace-browser.cjs`: **9 nhóm PASS**, Chromium thật, API/Storage mô phỏng. Có kiểm tra người SX/người kho không có vai trò IQC, nhân sự mới, SP mới/tên SP, đúng 5 NCC/7 phạm vi, tạo LOT qua form, sửa, hoàn thành NG, Dashboard 50%/50%, dữ liệu cũ/ảnh hưởng sampled_at, bộ lọc, CSV, giá trị sai, và đủ 1.003 LOT qua phân trang. Không có pageerror.
- `node tests/iqc-workspace-postgres.cjs`: **5 nhóm PASS**, PostgreSQL cục bộ; chưa phải Supabase staging.
- `node tests/oqc-workspace-math.cjs`: **6 nhóm PASS**.
- `node scripts/code-review-check.cjs --files iqc.html shared/mes-iqc-workspace.js supabase/migration_phase_T176_iqc_pham_vi.sql`: không có mức CAO/TB. Còn cảnh báo THẤP về chuỗi HTML/CSS dài, font cũ, thông báo lỗi cũ và nhãn STAGING ONLY.
- `git diff --check` và kiểm tra cú pháp: PASS.
- Đã xem ảnh Chromium desktop `.review/iqc-dashboard-desktop.png`, `.review/iqc-report-desktop.png`; panel, form và điều hướng hiển thị đúng. `.review/tools` chỉ chứa dependency kiểm thử, không đưa vào triển khai.
- Hai bộ browser regression có sẵn chưa PASS toàn bộ: `oqc-dashboard-browser.cjs` dừng ở kỳ vọng 102 nhưng nhận 0 (dòng 22); `qc-session-browser.cjs` dừng vì fixture chưa định nghĩa `sbTaiHet` (dòng 5). Các trang/helper của OQC/IPQC và chính hai bộ test này không thay đổi so với base staging. Không coi hai bộ test này là PASS.

## Kiểm tra trực tiếp staging (chỉ đọc)

`node scripts/check-iqc-staging.cjs`:

- `iqc_lots?select=id&limit=0`: HTTP 200.
- `iqc_lots?select=id,pham_vi,nguoi_kiem_id,nguoi_kiem_ten&limit=0`: HTTP 400, `42703`, **chưa có cột pham_vi**.
- `https://mes-toyotaki.dangnaf.workers.dev/iqc.html`: HTTP 200, **chưa nạp workspace mới**.

Chưa tạo/sửa/xóa LOT thật, chưa chạy migration trên Supabase, chưa push/merge/deploy frontend. Công cụ CUA trả về không có trình duyệt/phiên được kết nối. Đã mở trang đăng nhập MES staging và Supabase SQL Editor staging trên máy người dùng.

## Bước còn lại để xác nhận hoàn tất

1. Kết nối phiên đăng nhập có quyền với đúng project staging **jcjbleugnclzsghfpmvk**. Áp dụng T176 sau khi kiểm tra số migration chưa bị nhánh staging mới sử dụng.
2. Chạy lại script kiểm tra schema; cả ba cột mới phải đọc được. Không triển khai frontend khi migration chưa thành công.
3. Đối chiếu lại staging HEAD và asset đang chạy, tích hợp riêng thay đổi IQC vào staging. Không đưa các worktree/checkout đang conflict vào deploy; không deploy SQL/dependency/test.
4. Đăng nhập MES staging: tạo LOT thử với người ngoài QC, chọn SP/NCC/Phạm vi; mở lại và sửa; hoàn thành kiểm tra; đối chiếu dữ liệu thật trong Dashboard/CSV/lịch sử, các bộ lọc và LOT cũ. Xác minh cập nhật giữa hai phiên và quyền hiện có.
5. Ghi kết quả test thật và version deploy trước khi thông báo hoàn tất. Không tự xóa LOT thử hay LOT cũ.

## Chuẩn bị đẩy staging

Đã fetch staging mới nhất: 04a567e (tính năng giao việc Excel, T175). Đổi migration IQC sang T176 để tránh trùng số; giữ nguyên thay đổi giao việc và navbar của staging.

## Triển khai staging thực tế

- Đã nhập staging mới nhất `04a567e`, giữ nguyên chức năng giao việc Excel/navbar.
- Push `origin/staging`: `04a567e` → **`1f9d245`** (commit thay đổi IQC `6fd099c`). Không push master/production.
- Migration **T176** chạy thành công qua Supabase Management API với `--linked --project-ref jcjbleugnclzsghfpmvk`.
- Kiểm thử thật dưới `set local role authenticated`, auth context từ tài khoản admin staging hiện có: insert/read/update đủ 7 Phạm vi, đổi đủ 5 NCC, kiểm tra mã/tên người kiểm, chặn Phạm vi/NCC ngoài danh sách, hoàn thành NG và truy vấn nguồn Dashboard. **PASS; toàn bộ transaction ROLLBACK**, không giữ LOT thử. SQL tái hiện: `tests/iqc-workspace-staging.sql`.
- Số LOT cũ trước/sau là **1**; checksum các cột gốc trước/sau migration và kiểm thử giống nhau: **a432286214553b506aac5bfe64f98200**. Không đổi/xóa nội dung LOT cũ.
- Trước triển khai: đối chiếu **97** asset frontend đang chạy với base staging, **0 sai khác nội dung** (chuẩn hóa CRLF/LF).
- Worker cũ: version `88078cd6-47b1-4df4-b5ad-6049c6d56c92`; phiên bản mới: **`c014e664-cc49-4c01-8a47-aed08ebe0e10`**, URL **https://mes-toyotaki.dangnaf.workers.dev/iqc.html**. Giữ compatibility date `2026-10-23`, assets-only, không bindings.
- Sau triển khai: **98/98 asset khớp SHA-256** của gói build, không lỗi HTTP; schema 3 cột mới HTTP 200; HTML staging đã nạp `mes-iqc-workspace.js`. Gói frontend không chứa SQL, test, dependency hoặc tài liệu review.
- Chạy lại 9 nhóm Chromium/API mô phỏng và 5 nhóm PostgreSQL cục bộ sau khi tích hợp staging: PASS.
- Mục “Bước còn lại” phía trên là kế hoạch tại thời điểm chưa triển khai. Bước migration/push/deploy/xác minh asset đã hoàn tất; còn xác nhận nghiệp vụ bằng phiên đăng nhập MES thật (gồm cập nhật giữa hai trình duyệt, quyền tài khoản hiện có). Không khẳng định đã test E2E đăng nhập/Storage thật.