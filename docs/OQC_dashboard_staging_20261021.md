# OQC dashboard - CAPA - kế hoạch và hiệu suất kiểm tra

Chỉ staging: https://mes-toyotaki.dangnaf.workers.dev/oqc-daily.html. Supabase `jcjbleugnclzsghfpmvk`. Phát triển từ staging hiện có, gồm các cập nhật tới `958c810`; không thay staging bằng master và không thao tác production/main.

## Chức năng

- OQC kiểm tra mở dashboard hôm nay theo giờ Việt Nam, có ngày/tuần/tháng/khoảng ngày, bộ lọc và chi tiết model. Mặc định kiểm 100% sau gia công; vẫn xem được phạm vi khác và dữ liệu cũ chưa phân loại qua bộ lọc. Không gộp lấy mẫu vào kế hoạch kiểm 100%.
- Ba nút: Nhập báo cáo ngày, CAPA, Kế hoạch tuần OQC. CAPA là popup, bỏ mục menu định mức riêng; giữ trang/RPC cũ cho dữ liệu và tích hợp trước đây.
- CAPA lấy model trung tâm, bước kiểm sửa/thêm/xóa/sắp xếp, giây thập phân, tổng dương. CAPA giờ = 3.600/giây; ngày = CAPA giờ × 7 × 90%. Các bước 10 + 5 + 3 giây cho 200 PCS/giờ và 1.260 PCS/người/ngày.
- Kế hoạch đọc trực tiếp `cd_khsx_tuan_plan`, đúng công đoạn OQC/ngày/model. Cộng nhân lực quy đổi trước khi làm tròn; kỳ nhiều ngày hiển thị người-ngày và đề xuất riêng từng ngày. Không tạo nguồn số lượng kế hoạch thứ hai.
- Tab KH tuần OQC mở đúng panel, gợi ý nhân lực 7 giờ/90%, dẫn về dashboard/CAPA. RPC lưu số lượng và quy trình duyệt cũ giữ nguyên; không ghi lại giờ lịch sử chỉ vì xem/tính gợi ý. Các tab khác giữ nguyên.
- Báo cáo dùng form cũ, bổ sung PCS NG độc lập với tổng lượt lỗi, ảnh và giờ thực tế phân bổ theo từng người/model/lần kiểm. Danh sách người kiểm dùng nhân sự trung tâm. Không tính giờ từ mở form, không tự gán cả ca cho từng model.
- Dashboard cộng OK+NG, tính phần trăm từ tổng tử/mẫu số, đếm nhân viên duy nhất. Hiệu suất = giờ chuẩn/giờ thực tế, không nhân 90% vào mẫu số. Thiếu CAPA/giờ hoặc ngoài kế hoạch có thông báo cụ thể.
- Chi tiết model giữ đúng khoảng lọc, từng lần kiểm/ảnh, lỗi theo PCS mắc lỗi trên tổng đã kiểm; tổng lượt lỗi có thể lớn hơn PCS NG. Xuất Excel và lịch sử phân trang cũ được giữ.
- Bản ghi mới lưu snapshot CAPA/chính sách và lịch sử sửa; retry có mã chống trùng, sửa có kiểm tra phiên bản. Dữ liệu cũ thiếu CAPA/phạm vi vẫn thiếu, không tự gán định mức mới. Form cũ đã cache không được ghi đè báo cáo đã lưu PCS NG/giờ riêng.

## Migration staging đã áp dụng

File: `supabase/migration_phase_oqc_dashboard_capa_20261021_staging.sql` (yêu cầu T73/T120 đã có).

Thêm bốn bảng: `oqc_inspection_work` (giờ theo người, ảnh, snapshot CAPA/chính sách), `oqc_dashboard_plan_basis` (snapshot định mức của ngày/model, không chứa nguồn số lượng kế hoạch mới), `oqc_dashboard_write_request` (chống gửi trùng), `oqc_dashboard_audit` (lịch sử bất biến). Thêm RPC `oqc_dashboard_info()`, `oqc_save_dashboard_capa(p_product,p_effective,p_steps)`, `oqc_save_dashboard_inspection(p_id,p_data)` và hai hàm nội bộ xác minh nhân viên/bảo vệ form cũ. Trigger bảo vệ đặt trên bảng báo cáo OQC hiện có.

RLS bật trên bốn bảng: authenticated được đọc, không được DML trực tiếp; request chỉ đọc của chính mình. Chỉ authenticated được gọi ba RPC; hàm lưu kiểm tra quyền hiện có (Admin/QC Manager sửa CAPA; thêm Nhân viên OQC được lưu báo cáo). Không sửa tài khoản/vai trò hay chính sách bảng khác. Không thêm danh mục model/nhân viên. Không thay thân RPC cũ; không backfill, cập nhật hay xóa dữ liệu nghiệp vụ cũ. Đã gọi `NOTIFY pgrst,'reload schema'` riêng sau migration.

Trước/sau migration và smoke rollback: 4 báo cáo, 2 phiên bản định mức; hash toàn bộ báo cáo `9e6cb96c538ae81d9626f6af90a0c8d5`, định mức `05a972539a53ad8af6d9ff1fbc38d857`, kế hoạch tuần `c9daa14ee6cd7090fb37dc0e8deb0c45` giữ nguyên. Bốn bảng mới chưa có dữ liệu nghiệp vụ thử tồn dư. Các sequence có thể có khoảng trống do giao dịch thử rollback.

## File thay đổi

| File | Phạm vi |
|---|---|
| `oqc-daily.html` | Tiêu đề, nạp dashboard mới |
| `shared/oqc-dashboard.js` | Dashboard, popup CAPA, báo cáo/giờ/ảnh, chi tiết model |
| `shared/oqc-dashboard-math.js` | Công thức riêng OQC 7 giờ/90%, tổng hợp có kiểm tra thiếu dữ liệu |
| `shared/mes-oqc-history.js` | Kết quả tải và API đọc bộ lọc/danh mục cho dashboard |
| `shared/oqc-defect-charts.js` | Tùy chọn nhãn PCS mắc lỗi; giữ mặc định cho màn hình cũ |
| `shared/navbar.js` | OQC kiểm tra, bỏ menu định mức riêng |
| `khsx-tuan.html` | Mở đúng tab OQC theo liên kết, nạp công thức OQC mới |
| `shared/qc-production-staff.js` | Gợi ý OQC tuần 7 giờ/90%, giữ nguồn/snapshot và luồng lưu/duyệt |
| `supabase/migration_phase_oqc_dashboard_capa_20261021_staging.sql` | Bảng/RPC/RLS/trigger OQC bổ sung |
| `tests/oqc-dashboard-fixture.cjs` | API giả lập dùng cho kiểm thử trình duyệt |
| `tests/oqc-dashboard-postgres.cjs` | 10 nhóm SQL/công thức |
| `tests/oqc-dashboard-ui.cjs` | 7 nhóm UI, dữ liệu cũ và phân trang >1.000 |
| `tests/oqc-dashboard-browser.cjs` | 5 nhóm Chromium máy tính/điện thoại/điều hướng tuần |
| `tests/oqc-dashboard-weekly.cjs` | 4 nhóm tích hợp kế hoạch tuần OQC |
| `tests/qc-unaffected-regressions.cjs` | Chạy ca IPQC/IQC/NCP còn phù hợp, liệt kê rõ assertion cũ loại trừ |
| `docs/OQC_dashboard_staging_20261021.md` | Bàn giao này |

## Kết quả kiểm tra

92 nhóm đạt: OQC mới 10 SQL/công thức + 7 UI + 5 Chromium + 4 tuần; hồi quy 20 MES + 5 yêu cầu QC + 16 IPQC + 7 CAPA cũ + 18 SQL tích hợp T118/T120/T122. Không tính 16 assertion OQC/task cũ bị loại trừ (NG=sum lỗi, API/form cũ, bố trí dashboard cũ, hoặc so file menu phải giữ nguyên byte). Các suite cũ nguyên bản vì vậy không được báo là toàn bộ đạt; chạy các ca còn phù hợp bằng runner có danh sách loại trừ cụ thể.

Lệnh chính (Node; cần đường dẫn dependency qua `MES_JSDOM_PATH`, `MES_FAKE_IDB_PATH`, `MES_PGLITE_PATH`, `MES_PLAYWRIGHT_PATH` nếu chưa cài trong repo):

```text
node tests/oqc-dashboard-postgres.cjs
node tests/oqc-dashboard-ui.cjs
node tests/oqc-dashboard-browser.cjs
node tests/oqc-dashboard-weekly.cjs
node tests/qc-unaffected-regressions.cjs mes-update.cjs
node tests/qc-unaffected-regressions.cjs qc-requirements.cjs
node tests/qc-unaffected-regressions.cjs qc-session-ui.cjs
node tests/oqc-capacity-ui.cjs
MES_TEST_COMBINED_QC=1 MES_TEST_QC_FOLLOWUP=1 node tests/qc-session-postgres.cjs
```

Chạy thêm RPC thật trên database staging, trong transaction rollback với ngữ cảnh authenticated của Admin/Nhân viên OQC: tạo/đọc CAPA, lưu nhiều báo cáo, NG nhiều lỗi, retry, sửa có audit, snapshot kế hoạch/kết quả không đổi khi thêm CAPA mới. Kiểm tra chữ ký RPC, RLS, quyền execute và quyền tải ảnh hiện có của bucket `ipqc-evidence`. Dữ liệu thử SQL được rollback toàn bộ.

Giới hạn: UI/Chromium dùng API giả lập; SQL thực dùng ngữ cảnh role xác thực trên database, không phải đăng nhập MES qua trình duyệt. Công cụ điều khiển trình duyệt thật hiện lỗi khởi tạo `os error 3`, nên chưa xác nhận E2E bằng tài khoản MES thật hoặc tải ảnh lên Storage thật trong phiên đó. Không ghi dữ liệu thử tồn dư để giả lập đã hoàn tất E2E.

## Smoke test của chủ MES

1. Admin mở OQC kiểm tra → CAPA, chọn model và ngày áp dụng, lưu các bước 10/5/3 giây; mở lại thấy 18 giây, 200 PCS/giờ, 1.260 PCS/người/ngày và lịch sử.
2. Mở KH tuần OQC, kiểm tra đúng tab/ngày/model và số lượng hiện có. Hai model 1.000 PCS, 18 giây có tổng 1,5873 người → bố trí 2, không cộng làm tròn từng model.
3. Nhập nhiều báo cáo/model/ngày. Một người làm 3,5 + 3,5 giờ trên hai báo cáo chỉ đếm một người, 7 giờ công; hai người mỗi người 2 giờ là 4 giờ công. Kiểm tra thêm ảnh, lưu/mở lại và sửa đúng bản ghi.
4. Một báo cáo 1.260 PCS, 18 giây, 7 giờ công: hiệu suất 90%; KH 1.260 thì hoàn thành 100%. Nhập PCS NG 2 và hai loại lỗi mỗi loại 2: NG vẫn 2, lượt lỗi 4.
5. Đổi bộ lọc ngày/tuần/tháng, bấm model, kiểm tra từng lần kiểm/ảnh/lỗi đúng khoảng. Xem dữ liệu cũ ở phạm vi chưa phân loại hoặc tất cả.
6. Thiếu CAPA/giờ hiện chưa đủ dữ liệu; không có KH hiện ngoài kế hoạch. Đổi CAPA không đổi báo cáo đã lưu. Kiểm tra vai trò chỉ xem không lưu được CAPA/báo cáo.

Production chưa triển khai. Bản frontend staging phải được build và đối chiếu asset sau deploy; mã commit và version Worker báo trong bàn giao triển khai.
