# OQC: biểu đồ gọn, giờ kiểm tra và NG tự tính; IPQC: nút bắt đầu

Chỉ staging: https://mes-toyotaki.dangnaf.workers.dev/. Supabase `jcjbleugnclzsghfpmvk`. Không thao tác production/main. Bản sửa tiếp nối staging, giữ cập nhật T132 của người khác.

## Thay đổi

- Biểu đồ OQC dùng tiêu đề **Thống kê lỗi**, nhãn `4 PCS · 0,2%`, ghi chú ngắn về mẫu số tổng đã kiểm. Thanh 10 px, chữ 11–12 px, khoảng dòng gọn; tên đầy đủ và số liệu xem bằng hover/focus/bấm. Không cắt bỏ loại lỗi ngoài top 10; danh sách dài cuộn được. Hai biểu đồ xu hướng thu gọn, bảng số liệu vẫn có trong phần mở rộng.
- Nút IPQC **Bắt đầu kiểm tra** cao tối thiểu 60 px, chữ 19 px, xanh nổi bật, rộng theo màn hình và nằm trước checklist. Chỉ đổi cách tạo/hiển thị nút; toàn bộ phần xử lý phiên, timer, bản nháp và gửi kết quả giữ nguyên mã so với staging trước sửa.
- Form OQC thêm **Số giờ kiểm tra** cho người kiểm đang chọn; nhận dấu phẩy hoặc chấm thập phân. Giá trị này lưu một lần trong `oqc_inspection_work.labor`. Vẫn giữ phần thêm người kiểm khác để không mất chức năng/dữ liệu nhiều người trước đây; mỗi người chỉ một dòng, tổng giờ công cộng trực tiếp, không nhân thêm số người.
- Báo cáo mới: NG = tổng số lượng lỗi, OK = đã kiểm − NG; phần trăm chia cho tổng đã kiểm. Kết quả chỉ đọc. Hướng dẫn ghi mỗi sản phẩm NG vào một loại lỗi chính. Không lưu số lượng âm/lẻ/không hợp lệ hoặc NG vượt số đã kiểm; giờ đã nhập phải dương và tối đa 24.
- Báo cáo đã lưu giữ NG cũ khi mở/sửa, kể cả trường hợp tổng số lỗi lịch sử lớn hơn NG. Không backfill hoặc đổi NG cũ sang cách tính mới. Form có ghi chú riêng khi sửa báo cáo đã lưu.
- Đổi **Ảnh kiểm tra** thành **Ảnh lỗi**; chọn/tải ảnh, popup và zoom giữ nguyên. CAPA 7 giờ/90%, snapshot lịch sử, nguồn kế hoạch tuần và tính hiệu suất không thay đổi.

## Backend/migration

`supabase/migration_phase_oqc_report_input_20261021_staging.sql` đã áp dụng trên staging.

Thêm RPC `oqc_save_daily_report(p_id bigint,p_data jsonb)` để backend tự tính NG cho bản mới, giữ NG trong bản ghi gốc khi sửa và chuẩn hóa giờ của người kiểm chính. RPC gọi writer hiện có để giữ CAS, chống gửi trùng, xác minh nhân viên, giới hạn giờ/ngày, snapshot CAPA, ảnh và audit. `oqc_dashboard_info()` bổ sung `report_input_version: 1` để frontend kiểm tra backend sẵn sàng trước khi cho lưu.

Không thêm/sửa/xóa bảng hoặc cột; không đổi RLS, tài khoản hoặc danh mục. RPC mới chỉ cho authenticated gọi và kiểm tra các vai trò Admin/QC Manager/Nhân viên OQC hiện có. Không cấp quyền anonymous. Thân `oqc_save_dashboard_inspection` cũ được giữ nguyên. Migration gửi thông báo tải lại schema cache API.

Đã so hash trước/sau migration: 5 báo cáo, giờ công, context, snapshot kế hoạch, định mức, kế hoạch tuần và thân writer cũ không đổi. Hash báo cáo: `87f2efca44d86a3ebf0dbeae45cb50f4`. Smoke test RPC thật trên staging dùng dữ liệu QA trong transaction rollback; không để lại báo cáo/định mức/kế hoạch QA. Sequence có thể có khoảng trống do rollback.

## File sửa

| File | Nội dung |
|---|---|
| `shared/oqc-defect-charts.js` | Biểu đồ, nhãn và ghi chú gọn; tương tác xem chi tiết |
| `shared/oqc-dashboard.js` | Giờ người kiểm chính; tính NG/OK mới, bảo toàn NG đã lưu; ảnh lỗi; RPC mới |
| `shared/mes-ipqc-session.js` | CSS/nút bắt đầu nổi bật, giữ logic phiên |
| `oqc-daily.html`, `ipqc.html` | Tăng phiên bản asset tránh dùng script cũ từ cache |
| `supabase/migration_phase_oqc_report_input_20261021_staging.sql` | RPC mới và thông tin phiên bản backend |
| `tests/oqc-dashboard-fixture.cjs` | Mô phỏng hợp đồng RPC mới |
| `tests/oqc-dashboard-ui.cjs` | Form, thập phân, NG/OK, giờ nhiều người, lịch sử, biểu đồ và validation |
| `tests/oqc-dashboard-browser.cjs` | Chromium desktop/mobile, báo cáo, ảnh/zoom và kế hoạch tuần |
| `tests/oqc-dashboard-postgres.cjs` | Hook chạy thêm kiểm thử RPC mới |
| `tests/oqc-report-input-postgres.cjs` | Migration không đổi schema/dữ liệu cũ; NG/giờ/quyền/retry/lịch sử |
| `tests/qc-session-browser.cjs` | Kiểm tra nút IPQC trên điện thoại và phục hồi phiên |
| `docs/QC_input_staging_20261022.md` | Bàn giao này |

## Kiểm thử

62 nhóm đạt: 10 OQC UI; 16 OQC PostgreSQL/công thức (gồm 6 nhóm mới); 5 OQC Chromium; 4 IPQC Chromium; 16 IPQC UI; 4 kế hoạch tuần; 7 CAPA cũ. Runner IPQC liệt kê 2 assertion OQC cũ bị loại trừ, không tính là ca đạt. Kiểm tra diff xác nhận phần xử lý IPQC từ hàm `message` tới hết module không đổi, sau chuẩn hóa xuống dòng.

Lệnh (đặt biến đường dẫn dependency `MES_JSDOM_PATH`, `MES_PGLITE_PATH`, `MES_FAKE_IDB_PATH`, `MES_PLAYWRIGHT_PATH` theo môi trường):

```text
MES_TEST_OQC_REPORT_INPUT=1 node tests/oqc-dashboard-postgres.cjs
node tests/oqc-dashboard-ui.cjs
node tests/oqc-dashboard-browser.cjs
node tests/qc-session-browser.cjs
node tests/qc-unaffected-regressions.cjs qc-session-ui.cjs
node tests/oqc-dashboard-weekly.cjs
node tests/oqc-capacity-ui.cjs
```

Chromium chạy trình duyệt thật với API mô phỏng; SQL cục bộ chạy PostgreSQL/PGlite. Đã chạy thêm RPC thật sau migration trên staging với ngữ cảnh authenticated Admin/OQC và rollback. Chưa xác nhận E2E bằng phiên đăng nhập MES thật qua trình duyệt; tải ảnh/zoom được kiểm tra trong Chromium với Storage mô phỏng.

## Smoke test trên staging

1. Mở OQC, tạo báo cáo mới: đã kiểm 20, hai loại lỗi 2 và 3, giờ `1,5`. Phải thấy NG 5, OK 15, NG 25%, OK 75%; lưu và mở lại thấy đúng 1,5 giờ của người kiểm.
2. Thêm người khác 2 giờ nếu cần: tổng là 3,5 giờ công, không nhân đôi. Xem dashboard và chi tiết đúng model/ngày.
3. Thử NG vượt 20, số lỗi âm/lẻ, giờ âm/0/sai định dạng: không lưu, có lý do.
4. Mở báo cáo cũ có tổng số lỗi khác NG; sửa ghi chú/giờ và kiểm tra NG cũ vẫn giữ nguyên. Xem ảnh và zoom.
5. Biểu đồ tên “Thống kê lỗi”, nhãn chỉ PCS/%; hover/bấm xem tên đầy đủ và mẫu số.
6. IPQC chọn máy: nút bắt đầu nổi bật trên checklist. Chưa bấm thì chưa có phiên; bấm rồi đóng/mở hoặc tải lại vẫn đúng thời điểm bắt đầu; chỉ hoàn tất khi OK/NG/Cảnh báo được xác nhận lưu thành công.

Commit/Worker version/đối chiếu asset của bản deploy được ghi trong bản bàn giao triển khai và GitHub deployment staging. Production chưa triển khai.
