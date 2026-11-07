# Sửa đọc kết quả ZEISS Calypso - STAGING, 07/11/2026

Phạm vi: nhánh `staging`, bổ sung sau `7645016`. Không migration, không thay đổi API, cấu trúc database, tiêu chuẩn đã duyệt hoặc luồng đọc bản vẽ tại Quản lý tiêu chuẩn. Chỉ kết nối database staging `jcjbleugnclzsghfpmvk` để kiểm tra; không kết nối Production.

## Nguyên nhân

PDF.js đọc được chữ nhưng bộ đọc cũ chỉ tìm bảng có tiêu đề mã/tên và Actual trên cùng một dòng. Báo cáo Calypso thực tế đặt mã đặc tính phía trên dòng Actual/Nominal/Upper Tol./Lower Tol./Deviation; bảng không có tiêu đề cột mã. Khi quy về lưới theo tiêu đề gần nhất, mã bị đưa vào cột Actual nên parser không tìm được bảng.

Ngoài ra, reader dùng việc ghép được tiêu chuẩn để quyết định chạy OCR. Giá trị đã đọc được nhưng thiếu mã tiêu chuẩn cũng bị coi như lỗi trích xuất. Controller mặc định chọn một trang tốt nhất nên không tự đưa toàn bộ báo cáo nhiều trang vào danh sách.

Backend chỉ nhận kết quả sau bước xác nhận và Lưu; không có API đọc PDF phía server. Lỗi nằm ở frontend đọc/đối chiếu, không phải upload storage hoặc RPC lưu.

## Thay đổi

- Nhận diện năm tiêu đề Calypso theo tọa độ, giữ liên kết mã ở dòng trên với dòng số ngay dưới. Chỉ lấy Actual làm giá trị đo; Nominal/dung sai/Deviation là dữ liệu đối chiếu. Không hardcode các giá trị trong yêu cầu.
- Đọc tất cả trang và tự chọn chế độ tự động cho Calypso; cấu hình thủ công cho cấu trúc khác vẫn giữ lại.
- PDF có Actual đọc được không chạy OCR vì thiếu tiêu chuẩn tương ứng. PDF không có lớp chữ vẫn có OCR dự phòng. Không tạo hai bản text/OCR trùng cho cùng trang.
- Giữ và hiển thị dòng Actual thiếu/hỏng với lý do. Tách số dòng đọc được, đã khớp, đọc được nhưng chưa khớp và lỗi trích xuất.
- Mã `7-1` khác `71`; không ghép bằng số thứ tự. Ghép Calypso bằng mã chính xác, hoặc tên + danh nghĩa + giới hạn + đơn vị khi đủ thông tin. Trùng mã hoặc thiếu bằng chứng phải chọn thủ công. Cảnh báo khác danh nghĩa/giới hạn/đơn vị, luôn đánh giá theo MES.
- Người dùng đối chiếu đơn vị, xác nhận các dòng rồi đồng bộ Actual vào ma trận; không cần gõ lại. Ghi đè ô đã nhập cần xác nhận. Đồng bộ không ghi database; Lưu kết quả mới upload file nếu được chọn và gọi RPC.
- Đồng bộ lại cập nhật dấu vết từng ô, không nhân bản dấu vết giá trị cũ. Giá trị vẫn sửa được sau đồng bộ và phải xác nhận lại trước Lưu.

## Kiểm thử có bằng chứng

PDF công ty thực tế: `2. MẪU/8. TTI/1012/30 MAU 012/M57.pdf`, ZEISS Calypso, 4 trang. File khách hàng không được đưa vào Git.

| Nội dung | Kết quả |
|---|---|
| So sánh parser với các text box Actual đọc trực tiếp bằng PDF.js, độc lập với parser | 36/36 Actual đúng, đủ 4 trang; 0 lỗi trích xuất |
| Ghép với bộ tiêu chuẩn thử cô lập có đúng 36 mã đặc tính của báo cáo | 36 khớp, 0 chưa xử lý; không cần cấu hình cột |
| Chrome thật, PDF.js thật, upload file gốc | Xác nhận và điền đủ 36 ô; 35 OK, 1 NG; không chạy OCR |
| Tiêu chuẩn thử không có mã/tên khớp | Vẫn hiện đủ 36 Actual, 0 tự ghép; chọn đặc tính thủ công và đồng bộ được; không chạy OCR |
| Đồng bộ, từ chối ghi đè, đồng bộ lại, sửa tay, Lưu, Dashboard | Đúng giá trị; chưa Lưu thì 0 RPC/0 upload; dấu vết cuối có đúng 36 ô |
| Thiếu Actual, dấu âm Unicode, dấu phẩy thập phân, trùng mã, nhầm `7-1`/`71`, khác tiêu chuẩn, PDF hỏng | Có kiểm tra, giữ dòng lỗi và không lấy Nominal/Deviation thay Actual |
| Staging RPC với 36 Actual lấy từ PDF thực tế | Tạo tiêu chuẩn thử qua quy trình duyệt hiện có, lưu/đọc lại đúng 36 giá trị; OK/NG, Dashboard, retry và snapshot đúng; toàn bộ transaction ROLLBACK |
| Kiểm tra mở rộng các PDF Calypso tìm được trong thư mục công việc | 502 tài liệu, 1.585 trang có mẫu Calypso, 13.549 Actual; khớp toàn bộ text box Actual độc lập, 0 lỗi trích xuất |
| Excel XLSX/XLS công ty, PDF bảng thông thường, OCR ảnh, Dashboard lọc/Excel | Qua regression |
| IPQC Đúc, trang nhập Gia công, đính kèm bản vẽ chỉ tham khảo | Qua regression; không đổi mã của các luồng này |
| Kiểm tra tĩnh | Cú pháp, `git diff --check`, code review tự động không phát hiện lỗi |

Các kết quả ghép 36 đặc tính ở trên sử dụng tiêu chuẩn thử tương ứng, không phải tự bổ sung mã vào tiêu chuẩn thật đang sử dụng. PDF Calypso không ghi đơn vị phải được người dùng xác nhận đơn vị trước đồng bộ.

Chưa được cung cấp đúng PDF chứa các giá trị `89.2988`, `87.8436`, `14.6242` trong ảnh của yêu cầu. Đã tìm trong thư mục công việc nhưng chưa thấy file đó; đã hỏi đường dẫn. Vì vậy chưa thể báo số dòng khớp/chưa khớp riêng cho PDF đó và Model/Revision người dùng đang chọn. Không lấy các giá trị minh họa để giả lập kết quả đọc file.

Checksum trước/sau kiểm thử staging giống nhau:

- Tiêu chuẩn: `a531b9295049e34dff5316a4b2876689`.
- Đặc tính: `295020aed6fd31e83e2f64295ace1829`.
- Checklist: `d41d8cd98f00b204e9800998ecf8427e`.
- Quyền: 5 admin, 1 nhân viên OQC, không thay đổi.

## File sửa và cách chạy lại

Ứng dụng: `ipqc-gia-cong.html`, `shared/ipqc-result-parser.js`, `shared/ipqc-result-reader.js`, `shared/ipqc-result-import.js`.

Kiểm thử: `tests/ipqc-zeiss-real.cjs`, `tests/ipqc-zeiss-browser.cjs`, `tests/ipqc-zeiss-staging-sql.cjs`, `tests/ipqc-result-files-browser.cjs`, `tests/check-mes-nov04-staging.cjs`. Hai test hiện có chỉ cập nhật thông báo trạng thái/cache marker theo thay đổi.

1. Cài PDF.js/Playwright theo hạ tầng test sẵn có; đặt `MES_ZEISS_PDF` là đường dẫn báo cáo Calypso thực tế và `MES_PLAYWRIGHT_PATH` là đường dẫn Playwright.
2. Chạy `node tests/ipqc-zeiss-real.cjs` để trích xuất và tạo dữ liệu kiểm chứng cục bộ `.review/zeiss-validation.json`.
3. Chạy `node tests/ipqc-zeiss-browser.cjs` để kiểm thử upload/ghép/điền/lưu/Dashboard với API fixture cô lập.
4. `node tests/ipqc-zeiss-staging-sql.cjs` tạo SQL kiểm thử ROLLBACK từ các Actual vừa đọc. Chỉ chạy SQL này trên staging `jcjbleugnclzsghfpmvk`; không chạy trên Production.

Không commit các PDF, ảnh chụp, dữ liệu thử hoặc thư viện trong `.review/`.
