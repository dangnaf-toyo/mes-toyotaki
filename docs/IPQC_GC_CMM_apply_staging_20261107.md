# Sửa xác nhận/điền CMM và rút gọn giao diện - STAGING, 07/11/2026

Nhánh `staging`, bổ sung sau `96d0e4a`. Không migration, không sửa API, không thay đổi tiêu chuẩn hoặc dữ liệu kiểm tra hiện có. Không kết nối Production.

## Nguyên nhân xác nhận nhưng bảng đo trống

1. Nút cũ **Xác nhận các dòng khớp đang hiển thị** chỉ cập nhật checkbox; chưa gọi hàm điền ma trận. Người dùng còn phải bấm **Đồng bộ vào bảng kết quả**.
2. Dữ liệu staging tại thời điểm kiểm tra có hai tiêu chuẩn Gia công đã duyệt, mỗi tiêu chuẩn 15 đặc tính; **30/30 dòng thiếu đơn vị và mã đặc tính**. Hàm đổi đơn vị yêu cầu cả đơn vị nguồn và đích, nên checkbox bị khóa dù đã có Actual hoặc đã chọn đơn vị nguồn mm. Cảnh báo cũ gộp thiếu đơn vị với không tương thích đơn vị.
3. Bộ ghép Calypso cũ chỉ dự phòng bằng tên + thông số; không hỗ trợ trường hợp thiếu mã/tên nhưng danh nghĩa, dung sai và đơn vị đủ để xác định duy nhất.
4. Đã tái hiện thêm lỗi Chrome khi thay bảng ngay trong sự kiện change/blur của ô đang focus: phát sinh change lồng nhau và lỗi thay DOM. Đã chặn việc vẽ lại lồng nhau, vẫn giữ giá trị người dùng vừa sửa.

## Hành vi sau sửa

- Một nút **Áp dụng kết quả** xác nhận và điền ngay các dòng hợp lệ đang được chọn. Các dòng hợp lệ tự được chọn, không phải tích lần lượt. Không có hộp thoại xác nhận dài trước khi áp dụng.
- Kiểm tra từng dòng trước khi áp dụng. Dòng chưa ghép, thiếu/sai đơn vị, lỗi Actual hoặc trùng đặc tính/mẫu được giữ lại; các dòng hợp lệ khác vẫn được điền. Không tự biến mã đặc tính thành số mẫu.
- Với đơn vị còn thiếu: chọn **Đơn vị bổ sung**, ví dụ mm, rồi tích **Đã đối chiếu đơn vị**. Chỉ bổ sung chỗ thiếu cho lần nhập này, không sửa tiêu chuẩn MES. Chọn đơn vị nhưng chưa xác nhận chưa đủ để áp dụng. Đơn vị đã ghi rõ trong file/MES không bị ngầm thay thế.
- Chuẩn hóa mm, MM, khoảng trắng, dấu ngoặc và ký tự Unicode tương đương. Phân biệt **Cần đơn vị** với **Sai đơn vị**.
- Ghép theo mã; tên/vị trí; hoặc danh nghĩa + dung sai + đơn vị khi duy nhất. Khi có nhiều đặc tính giống nhau, giữ trạng thái chưa ghép/trùng để QC chọn thủ công. Không ghép bằng thứ tự dòng.
- Giá trị vào đúng ô đặc tính/mẫu và tự đánh giá OK/NG theo MES. Giữ số thập phân; vẫn sửa được trước khi lưu. Ô nhập tay khác giá trị CMM cần xác nhận ghi đè; chọn Hủy giữ dữ liệu đã nhập.
- Cập nhật ma trận theo một batch đã kiểm tra toàn bộ; chuẩn hóa khóa số. Sau khi điền, đọc lại từng ô để xác minh. Nếu setter không ghi được, báo đúng ô lỗi, không tăng số đã điền hoặc thông báo thành công giả.
- Áp dụng không ghi database/upload file. Chỉ **Lưu kết quả đo** mới gọi RPC và lưu file gốc nếu được chọn. Dấu vết lưu cả đơn vị bổ sung đã xác nhận, mapping thủ công, giá trị gốc và giá trị cuối.
- Sau Áp dụng, xác nhận kết quả được ghi nhận. Nếu sửa tay ma trận sau đó, phải tích lại **Đã kiểm tra kết quả** trước Lưu.

## Giao diện

Nhãn ngắn: Cách nhập, Nhập tay, Nhập file CMM, File CMM, Trang, Mẫu CMM, Đối chiếu CMM. Bảng có STT, Đặc tính CMM, Giá trị đo, Đặc tính MES, Đơn vị, Trạng thái, Chọn.

Hiển thị bốn số: **Đã đọc / Đã khớp / Chưa khớp / Đã điền**; lọc Tất cả / Đã khớp / Chưa khớp. Trạng thái xanh/vàng/đỏ, chi tiết mở khi nhấn trạng thái. Checkbox có vùng bấm rõ; checkbox chưa hợp lệ có lý do cụ thể. Bảng cuộn gọn, tiêu đề cố định; đã xem ảnh chụp ở desktop và mobile, không tràn trang.

Không thay đổi giao diện, công thức tính, bộ lọc hoặc xuất Excel của Dashboard.

## Kết quả kiểm thử

PDF công ty thực tế dùng kiểm chứng: `2. MẪU/8. TTI/1012/30 MAU 012/M57.pdf`, ZEISS Calypso, 4 trang, 36 Actual. Không commit tài liệu khách hàng hoặc dữ liệu thử.

| Kiểm tra | Kết quả |
|---|---|
| PDF.js đọc trực tiếp và so với text box Actual độc lập | 36/36 Actual đúng, không nhầm Nominal/Deviation |
| Chrome, tiêu chuẩn thử tương ứng thiếu đơn vị giống staging, khóa đặc tính dạng chuỗi | Không tự giả định đơn vị; sau chọn mm + xác nhận, 36 khớp; một lần Áp dụng điền đủ 36 ô |
| OK/NG trên 36 đặc tính thử | 35 OK, 1 NG |
| Hai dòng trùng đặc tính/mẫu | Giữ 2 dòng trùng, điền 34 dòng khác; sửa mapping, áp dụng lại đủ 36; không mất giá trị đã điền |
| Checkbox, bộ lọc, chuyển tab Dashboard/nhập, sửa giá trị đang focus | Hoạt động, giữ ma trận; không lỗi change/blur lồng nhau |
| Đơn vị mm/Unicode, thiếu đơn vị, deg so với mm, sửa đơn vị nguồn | Đúng trạng thái; thiếu/sai đơn vị không được xác nhận; sửa được lựa chọn |
| Số lẻ 6 chữ số, sửa tay, hủy/đồng ý ghi đè | Giữ độ chính xác, không ghi đè khi chưa đồng ý |
| Setter không ghi được hoặc batch có mẫu không hợp lệ | Thông báo thất bại đúng, số đã điền bằng 0; batch lỗi không sửa dở dang dữ liệu |
| Chưa Lưu | 0 RPC lưu và 0 upload |
| Lưu, đọc lại, trace, Dashboard | Đúng 36 giá trị và đơn vị đã xác nhận; tiêu chuẩn thử không đổi |
| RPC thật trên staging với tiêu chuẩn thử thiếu đơn vị | Lưu/đọc lại Actual, OK/NG, Dashboard và retry đúng; transaction ROLLBACK |
| Excel XLSX/XLS, PDF thường, OCR ảnh, nhiều mẫu | Qua regression; đúng ô mẫu, chỉ ghi sau Lưu |
| IPQC Đúc, nhập Gia công, biểu đồ/Excel Dashboard và dung sai có dấu | Qua regression |
| Kiểm tra tĩnh | 12 file, 0 phát hiện; cú pháp và `git diff --check` đạt |

Checksum dữ liệu staging trước/sau giống nhau:

- Tiêu chuẩn: `a531b9295049e34dff5316a4b2876689`.
- Đặc tính: `295020aed6fd31e83e2f64295ace1829`.
- Các tiêu chuẩn, metadata, kết quả CMM đã lưu và số kết quả Đúc trong bản đối chiếu không đổi.

**Giới hạn nghiệm thu:** chưa nhận được PDF riêng hiện có 11 đặc tính của người dùng. Đã hướng dẫn đính kèm hoặc cung cấp đường dẫn. Không báo đã kiểm thử 11/11 trên file chưa có; các số 36/36 ở trên thuộc file M57.pdf và tiêu chuẩn thử tương ứng, không phải tự cập nhật tiêu chuẩn thật để khớp báo cáo.

## File và lệnh kiểm tra

Ứng dụng: `ipqc-gia-cong.html`, `shared/ipqc-result-import.js`, `shared/ipqc-result-parser.js`, `shared/ipqc-gc-entry.js`.

Kiểm thử bổ sung: `tests/ipqc-cmm-apply-browser.cjs`, `tests/ipqc-cmm-matching.cjs`. Cập nhật test ZEISS/file CMM, fixture và kiểm tra asset staging theo luồng một nút áp dụng và cảnh báo đơn vị mới.

Chạy `node tests/ipqc-cmm-matching.cjs`, `node tests/ipqc-cmm-apply-browser.cjs`, `node tests/ipqc-result-files-browser.cjs`, `node tests/ipqc-zeiss-browser.cjs` với Playwright và dữ liệu kiểm chứng PDF cục bộ theo tài liệu ZEISS trước đó.

Để kiểm thử RPC với đơn vị thiếu, đặt `MES_ZEISS_MISSING_UNITS=1` rồi chạy `node tests/ipqc-zeiss-staging-sql.cjs`. SQL tạo ra trong `.review/` chỉ chạy trên staging `jcjbleugnclzsghfpmvk`, luôn ROLLBACK. Không chạy trên Production.
