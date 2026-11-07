# Kiểm chứng file người dùng cung cấp: M2 1.pdf - STAGING

File gốc: `M2 1.pdf`, Measurement Plan `8001`, ZEISS Calypso, ngày đo 05/11/2026, 2 trang, 38.791 byte. Đã xem cả hai trang và kiểm tra lớp chữ/toạ độ Actual. Không đưa PDF vào Git, không chỉnh sửa file gốc. Tài liệu này bổ sung bằng chứng cho bản sửa `dce0d87`.

## Kết quả đọc file và tiêu chuẩn MES thực tế

Đọc đúng **11/11 Actual**, 0 lỗi trích xuất. Đây là file có đúng các giá trị minh họa người dùng nêu trước đó. File không ghi đơn vị, nên cần chọn mm và xác nhận đơn vị trước áp dụng.

Kiểm tra với snapshot đọc trực tiếp từ database staging `jcjbleugnclzsghfpmvk`, không sửa tiêu chuẩn:

| Mã CMM | Actual | TTI-MOT-05 / A: dòng MES tự khớp | TTI-MOT-04 / A: dòng MES tự khớp |
|---|---:|---:|---:|
| 1 | 89.2988 | 1 | 1 |
| 7 | 87.8436 | 2 | 2 |
| 7-1 | 0.0196 | Chờ mapping | Chờ mapping |
| 15 | 14.6242 | 6 | Chờ đối chiếu giới hạn |
| 18 | 12.1664 | 7 | 7 |
| 18-1 | 0.0498 | Chờ mapping | Chờ mapping |
| 18-2 | 0.0014 | Chờ mapping | Chờ mapping |
| 25 | 14.5619 | 10 - NG | 10 - NG |
| 25-1 | 0.0196 | Chờ mapping | Chờ mapping |
| 30-1 | 0.0303 | Chờ mapping | Chờ mapping |
| 30-2 | 0.0104 | Chờ mapping | Chờ mapping |

**TTI-MOT-05/A: đọc 11, tự khớp/điền 5, chờ mapping 6.**

**TTI-MOT-04/A: đọc 11, tự khớp/điền 4, chờ đối chiếu/mapping 7.**

Mã CMM `25` có Actual `14.5619`, lớn hơn USL MES `14.55`, nên NG. Các giá trị tự khớp khác OK.

Mã CMM `15`: PDF quy định 14.6 với sai lệch +0.03/+0.01, tức 14.61–14.63. TTI-MOT-05/A có giới hạn này. TTI-MOT-04/A hiện có LSL 14.59, vì vậy không tự ghép bằng danh nghĩa rồi bỏ qua khác biệt giới hạn. Không sửa giới hạn của bản đã duyệt.

## Vì sao chưa tự ghép 6 đặc tính hình học

Hai tiêu chuẩn hiện có đều chưa lưu mã đặc tính và đơn vị. Các đặc tính hình học trong PDF có mã/vị trí riêng: `7-1`, `18-1`, `18-2`, `25-1`, `30-1`, `30-2`. MES có các dòng chung như Độ đồng tâm, Kích thước, Dung sai hình học với nhiều giới hạn 0.05 hoặc 0.1 giống nhau, nhưng không có mã/vị trí để nhận dạng các dòng PDF tương ứng.

PDF ghi Nominal 0 và Upper Tol. 0.05/0.1 cho hình học; một số dòng MES đang ghi danh nghĩa là giá trị dung sai tối đa, ví dụ 0.05 hoặc 0.1. Không thay đổi tiêu chuẩn để ép khớp và không coi Lower Tol. để trống trong PDF là số 0 đã được cung cấp.

Không tự gán các vị trí `18-1/18-2` hoặc `30-1/30-2` thành Mẫu 1/Mẫu 2. Các vị trí đo khác nhau không phải các mẫu sản phẩm khác nhau. Không gộp, lấy lớn nhất hoặc bỏ một Actual để tránh xung đột.

Đã hỏi người dùng xác nhận Model/Revision đang dùng và mapping sáu mã hình học. Phần này còn chờ thông tin nghiệp vụ; chưa nghiệm thu đủ 11 dòng trên các tiêu chuẩn MES hiện tại.

## Bằng chứng kiểm thử luồng nhập và lưu

1. Chrome tải đúng PDF gốc, PDF.js thật đọc 11 Actual trên 2 trang. So sánh với 11 text box Actual độc lập: trùng toàn bộ, không dùng Nominal/Deviation làm kết quả.
2. Với snapshot tiêu chuẩn thực tế, một lần **Áp dụng kết quả** điền đúng 5 ô hoặc 4 ô ở các dòng MES trong bảng trên; các ô khác giữ trống. Không tự ghép theo số thứ tự (CMM 7 vào MES 2; CMM 18 vào MES 7).
3. Bảng đo hiển thị NG ở dòng MES 10. Bộ lọc vẫn giữ các dòng chưa ghép để xử lý, không mất các giá trị đã điền. 0 RPC ghi và 0 upload trước Lưu. Tiêu chuẩn/snapshot không đổi.
4. Tiêu chuẩn MES hiện có 15 hạng mục bắt buộc. Khi chỉ điền được 4/5 hạng mục, nút Lưu vẫn khóa; không tạo giá trị đo giả cho các hạng mục thiếu để lưu cho đủ.
5. Kiểm thử chức năng đầy đủ với **tiêu chuẩn thử cô lập có đúng 11 mã đặc tính tương ứng**: Áp dụng một lần điền đúng 11/11, 10 OK/1 NG, lưu/đọc lại và Dashboard đúng. Có thử thiếu đơn vị, dòng trùng, khôi phục mapping, sửa tay, ghi đè có xác nhận, giữ dữ liệu khi chuyển tab, batch lỗi và readback lỗi.
6. RPC thật trên staging với 11 Actual của chính file này và tiêu chuẩn thử tương ứng: lưu/đọc lại, OK/NG, Dashboard, retry và tính bất biến tiêu chuẩn đạt. Toàn bộ dữ liệu thử ROLLBACK. Kết quả tiêu chuẩn thử không được dùng để báo rằng cả 11 dòng đã tự khớp với tiêu chuẩn MES thực tế.

Không cần sửa thêm code ứng dụng để đọc file M2 hoặc để áp dụng các dòng hợp lệ. Phần còn lại là nhận dạng các đặc tính/vị trí còn thiếu trong tiêu chuẩn hoặc mapping nghiệp vụ, cần người dùng xác định.

## Chạy lại

- Đặt `MES_ZEISS_PDF` là đường dẫn M2 1.pdf rồi chạy `node tests/ipqc-zeiss-real.cjs`.
- Chạy `node tests/ipqc-cmm-apply-browser.cjs` với Playwright để kiểm tra toàn bộ 11 Actual trên tiêu chuẩn thử.
- Đọc snapshot staging bằng truy vấn chỉ đọc, đặt `MES_CMM_SNAPSHOT` là file JSON kết quả rồi chạy `node tests/ipqc-cmm-staging-standard-browser.cjs` để xác nhận các dòng thực sự tự khớp ở hai Model.
- Chạy test RPC bằng SQL ROLLBACK sinh từ `tests/ipqc-zeiss-staging-sql.cjs`, chỉ trên staging. Không kết nối Production.
