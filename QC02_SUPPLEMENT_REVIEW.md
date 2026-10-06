# Bổ sung QC02 — 07/10/2026

Branch: `qc02-rebuild`. Các thay đổi dưới đây chưa commit/push/deploy. Không sửa master, không thực hiện DB write/seed/migration.

## File và thay đổi

- `ipqc.html`: checkbox “Check điều kiện máy”; lưu trạng thái qua ghi chú hiện có, không thêm mục checklist đánh giá. Preview ảnh chụp bằng helper chung; PDF tiêu chuẩn trong viewer và thông báo thiếu PDF.
- `iqc.html`: số LOT ở bảng chính là nút mở chi tiết; modal hiển thị thêm toàn bộ record LOT, lỗi và thumbnail ảnh liên quan. Model autocomplete từ `master_products`, tự điền tên. Gợi ý người kiểm từ `master_employees`. Xem PDF theo mã sản phẩm trong form/chi tiết LOT.
- `qc-manager.html`: số phiếu mở chi tiết NCP, tìm chính xác/gần đúng trên phiếu đang xử lý và đã đóng; tải danh sách có phân trang để không chỉ tìm trên 1 trang dữ liệu. Hiển thị trạng thái check điều kiện máy trong lịch sử. Preview PDF giữ upload hiện có. Gợi ý nhân sự NCP từ master.
- `ncp-detail.html`: bổ sung toàn bộ thông tin phiếu và checkpoint nguồn, người phát hiện, công đoạn (hiển thị “Chưa ghi nhận” nếu DB không có), ảnh, nguyên nhân/đối sách và trạng thái/xác nhận hiện có. Nút in A4 có ảnh lỗi/bằng chứng, ảnh nguyên nhân, ảnh đối sách, người thực hiện, thời hạn, đánh giá và thông tin cách ly. Trạng thái khóa/sửa/duyệt và RPC được giữ.
- `oqc.html`: chỉ nhúng helper popup; source hiện tại không có form ảnh riêng để bổ sung dữ liệu mới.
- `oqc-daily.html`: giữ bộ lọc/thống kê/field/submit/RPC và nguồn nhân viên OQC; bổ sung viewer PDF theo model, refresh danh sách OQC khi focus để đọc nhân sự mới từ master. Không mở rộng nhân viên ngoài vai trò OQC.
- `shared/qc02-view.js`: popup ảnh dùng chung, nút đóng, đóng nền tối, trước/sau và phím mũi tên; native dialog và fallback overlay. Hỗ trợ HTTP(S), blob và ảnh data URL an toàn; viewer PDF; encode/decode trạng thái điều kiện máy.
- Mới `shared/qc02-data.js`: đọc danh mục nhân sự/model có phân trang, gợi ý và refresh trực tiếp; lookup PDF theo mã; bảo vệ response PDF cũ ghi đè model mới khi đổi nhanh.
- Mới `shared/qc02-ncp.js`: view đọc đầy đủ và bản in A4; chờ ảnh tải trước in, giữ nguyên workflow ghi dữ liệu.
- Mới `tests/qc02-supplement-fixtures.cjs`: tạo fixture offline bằng HTML/JS thật của các trang, mock API và chặn network; không ghi DB.

## Lưu Check điều kiện máy

`duc_submit_ipqc_check` giữ nguyên tên/chữ ký. `p_checklist` và quy tắc OK/NG không đổi. Frontend kiểm tra ghi chú bắt buộc trước khi thêm metadata:

```
[QC02_MACHINE_CHECK:1]
[QC02_MACHINE_CHECK:0]
```

Chỉ một trong hai dòng được thêm vào `p_ghi_chu` theo checkbox; RPC hiện có lưu vào `duc_ipqc_checkpoint.ghi_chu`. Lịch sử QC Manager hiển thị nhãn đã/chưa check thay cho dòng marker. Record cũ không có marker được xem là chưa ghi nhận, không tự sửa hay đánh đồng với “chưa check”. Không thêm đánh giá máy hoặc thay kết quả.

## Nhân sự: phần đã làm và blocker

Nguồn chính cho gợi ý/chọn nhân sự QC là `master_employees`, giống OQC hiện có. Gợi ý được đọc trực tiếp khi vào trang/focus, không hardcode danh sách. Các giá trị lịch sử và field text hiện có vẫn được bảo toàn. Người thao tác đăng nhập IPQC/OQC/người mở phiếu vẫn dùng MesAuth; quyền vẫn từ `user_roles`, không biến chọn nhân viên thành quyền duyệt hoặc thay actor tùy ý.

**Chưa hoàn thành yêu cầu tự đồng bộ tài khoản toàn hệ thống.** Quản lý danh mục ghi `master_employees`; Edge Function tạo tài khoản ghi `user_roles`. Trong Git chưa có quan hệ/trigger đồng bộ; `master_employees` khóa chính theo tên, `ma_nv` có thể null, `user_roles` dùng `user_id` và username. Cần xác nhận quy tắc `username` ↔ `ma_nv`, cách xử lý tên trùng/mã thiếu và vai trò khác nhau trước khi thiết kế migration đồng bộ. Không tự sửa trang Admin hoặc dữ liệu ngoài QC02 khi chưa đủ thông tin.

## PDF và ảnh

PDF hiện có dùng `duc_ipqc_tieuchuan.file_pdf_url` và bucket `report-files`; không tạo nguồn tiêu chuẩn khác. Viewer được thêm ở IPQC, QC Manager, form/chi tiết IQC và OQC daily theo mã sản phẩm. Nếu bảng tiêu chuẩn hiện chỉ có file IPQC thì không suy đoán file đó là tiêu chuẩn IQC/OQC riêng.

Ảnh IPQC/NCP dùng `ipqc-evidence` và các trường JSON hiện có. IQC giữ ảnh data URL trong `iqc_defects.images`. Popup được áp dụng ở IQC, IPQC, QC Manager, NCP và sẵn sàng trong hai trang OQC; không tự tạo trường ảnh OQC mà source không có.

## Validation

- Parse toàn repo HTML classic script/JS/CJS: 56 script, không lỗi cú pháp; các shared script references tồn tại. TypeScript Edge Functions ngoài phạm vi thay đổi.
- 5 fixture Chrome headless PASS: IQC, IPQC, QC Manager, NCP detail, OQC daily; không lỗi JavaScript được ghi nhận trong fixture.
- Test: LOT và full record, nguồn model/nhân sự, mốc ngày +07, payload submit IPQC thật qua API mock (checklist/kết quả giữ nguyên, metadata lưu), record cũ/checked/unchecked, tìm NCP gần đúng/link, OQC filters/source, gallery trước/sau/đóng nền, PDF iframe, nội dung nguyên nhân/đối sách và ảnh trong bản in.
- PDF Chrome xuất từ fixture cuối: 2 trang A4 (MediaBox 594.96 × 841.92 pt), 96,041 byte, có image object nhúng. Ảnh test 600×240 pixel; chưa thử máy in vật lý hay record thực nhiều trang.
- `git diff --check` đạt; không đổi SQL/schema/navbar/shared auth/client; không reference RPC tiền tố QC03 trong HTML/JS/SQL.
- Repo không có build/lint runner. Chưa test đăng nhập thật, RLS/schema/RPC và ảnh/PDF thực trên staging.

Tạo fixture lại bằng `node tests/qc02-supplement-fixtures.cjs <thư-mục-tạm>`, rồi mở bằng Chrome headless với `--virtual-time-budget=2500 --dump-dom file:///.../<trang>.html?id=NCP-001`; kết quả nằm ở `body[data-test-result]`. Fixture chặn network và dùng API giả.

Code frontend có thể review để chuẩn bị kiểm thử staging. Chưa deploy; chưa xác nhận hoàn tất mục đồng bộ tài khoản hoặc sẵn sàng production.
