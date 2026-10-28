# IQC/OQC — Phạm vi kiểm và % lỗi, 28/10/2026

Chỉ staging. Base `481a9eb`; không viết lại IQC/OQC, không migration hoặc ghi/xóa dữ liệu thật.

## Thay đổi

- IQC: chỉ còn một ô Số LOT trên màn nhập. Ô chọn LOT của editor lỗi được giữ làm khóa nội bộ, ẩn khỏi giao diện; lỗi gắn với LOT vừa lưu/đang sửa hoặc LOT của lỗi đã chọn sửa. Khi chưa chọn/lưu LOT thì chặn mở nhập lỗi. Reset/chuyển LOT đóng editor để không ghi nhầm lỗi.
- IQC: cột **Phạm vi kiểm** có trong danh sách và lịch sử; thêm lọc Phạm vi kiểm cho lịch sử, tìm lịch sử theo `pham_vi`, tìm trong danh sách theo mã/tên SP/phạm vi. Bản ghi cũ thiếu phạm vi hiển thị **—**, không backfill.
- OQC: thêm **Phạm vi kiểm**, **% lỗi** vào tổng hợp theo model, lịch sử, chi tiết từng lần kiểm của model và bảng theo ngày/tuần. Bảng tổng hợp tách theo `(model, scope)`; bảng ngày/tuần tách theo `(kỳ, scope)`. Nhãn lấy từ `MesOqcScope.labels`; context phải khớp ngày/model như luồng hiện tại, thiếu hoặc không khớp thì **—**.
- % lỗi = `sum(ng_qty) / sum(total_qty) × 100` cho nhóm; mỗi báo cáo dùng `ng_qty / total_qty × 100`, `toFixed(2)`. Mẫu số 0 hiển thị **—**, không tạo NaN/Infinity. Không lấy trung bình các phần trăm từng dòng.
- Giữ nguyên cột/chỉ số cũ, các công thức OK/NG/%OK/%NG, CAPA, giờ công và biểu đồ tổng thể. Kế hoạch chỉ gắn vào nhóm sau gia công. Bảng/ngăn chi tiết model chỉ đọc đúng phạm vi đang bấm.
- Helper biểu đồ dùng tùy chọn `scopeLabel` tại Dashboard OQC để bổ sung bảng theo phạm vi; các nơi khác không bật tùy chọn giữ hành vi cũ.
- Version query của asset IQC/OQC đổi sang `20261028-scope-rate` để nạp code mới đồng bộ.

## File sửa

1. `iqc.html`
2. `oqc-daily.html`
3. `shared/mes-iqc-report.js`
4. `shared/mes-iqc-workspace.js`
5. `shared/mes-oqc-history.js`
6. `shared/oqc-dashboard-math.js`
7. `shared/oqc-dashboard.js`
8. `shared/oqc-defect-charts.js`
9. `tests/iqc-workspace-browser.cjs`
10. `tests/qc-scope-rate-browser.cjs` (mới)
11. Tài liệu này.

## Kiểm tra

| Yêu cầu | Kết quả |
|---|---|
| IQC một ô Số LOT, nhập/lưu/sửa | PASS Chromium; mã LOT vẫn giữ khi mở sửa; khóa LOT lỗi nội bộ không hiển thị và không đổi khi refresh |
| IQC phạm vi trong danh sách/lịch sử và bộ lọc | PASS Chromium; lọc có/không có kết quả, dữ liệu scope đã lưu hiển thị đúng |
| OQC tổng hợp model + scope + % lỗi | PASS; model A tách phạm vi, 70 NG / 300 đã kiểm = 23.33%, không lấy trung bình |
| OQC lịch sử và bảng theo ngày | PASS; thêm hai cột, giữ cột cũ; drilldown không lấy lẫn phạm vi; sửa báo cáo rồi tải lại cập nhật đúng |
| Công thức, 2 số lẻ, mẫu số 0 | PASS; sau sửa 20/120 = 16.67%, nhóm 70/320 = 21.88%; số kiểm bằng 0 hiển thị — |
| Dữ liệu cũ/mới | PASS; thiếu/stale context hiển thị —, giữ OK/NG/%NG cũ và dữ liệu lấy mẫu IQC cũ |

Lệnh: `node tests/iqc-workspace-browser.cjs` (10 nhóm PASS); `node tests/qc-scope-rate-browser.cjs` (4 nhóm PASS); `node tests/oqc-workspace-math.cjs` (6 nhóm PASS). Browser thật Chromium, API/Storage mô phỏng trong test; không đưa fixture vào ứng dụng. Đã xem ảnh OQC desktop. `git diff --check` và kiểm tra cú pháp đạt; review không có mức CAO/TB.

Đối chiếu trước deploy: 100/100 asset đang chạy khớp base staging. Truy vấn chỉ đọc trực tiếp Supabase staging xác nhận 1 LOT IQC, 5 báo cáo OQC, 3 nhóm model/phạm vi và 3 báo cáo thiếu phạm vi; không ghi/xóa/backfill dữ liệu. Chưa dùng phiên đăng nhập MES thật để kiểm thử browser E2E.
