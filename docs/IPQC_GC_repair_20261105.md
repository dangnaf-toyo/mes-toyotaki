# Sửa IPQC Gia công — STAGING — 05/11/2026

Nền `b3b67b4`, nhánh staging, đã fast-forward để giữ đủ thay đổi mới của đồng đội. Chỉ database `jcjbleugnclzsghfpmvk`; không truy cập ghi/migrate production.

## Khảo sát và sửa lỗi tải dữ liệu (nhóm 1, 2, 6)

`Qc02Data.readAll` chỉ có quy tắc sort Model (`ma_sp`) hoặc nhân viên (`ten_nhan_vien`). Module cũ dùng hàm này để đọc `master_machines`, khiến truy vấn order theo cột không tồn tại. Đây là nguyên nhân thông báo đỏ chung làm quá trình khởi tạo cả ba tab dừng. Sửa riêng module này: đọc danh mục máy theo `ma_may` qua cùng client/RLS và cơ chế phân trang. Không đổi helper dùng cho các module khác.

Chuẩn hóa trạng thái trống thành “Chưa có dữ liệu”, thông báo chưa có tiêu chuẩn phát hành và khóa lưu khi không có căn cứ. Lỗi thật vẫn được báo, chi tiết kỹ thuật có thể mở xem; không chỉ ẩn lỗi.

“Bước gia công” đang là một phần khóa phân biệt tiêu chuẩn cùng Model/Revision, phạm vi phát hành và snapshot truy xuất đo. Giữ cột/dữ liệu và một ô khai báo trong tiêu chuẩn, bổ sung giải thích. Phần nhập đo lấy tự động theo tiêu chuẩn. Dashboard dùng danh sách nguyên công đã có thay cho nhập lại tên tự do. Không xây dựng lại bảng tiêu chuẩn hoặc luồng duyệt.

Preflight staging: 30 máy Gia công, chưa có tiêu chuẩn/đặc tính Gia công, 0 lần đo Gia công/Đúc; roles 5 Admin + 1 OQC. Checksum tiêu chuẩn và đặc tính Gia công đều `d41d8cd98f00b204e9800998ecf8427e` (tập trống). Không tự nhập tiêu chuẩn mẫu lâu dài.

PASS `tests/ipqc-gc-repair-browser.cjs`: Chrome chạy mã `qc02-data.js` thực với API fixture kiểm tra tên cột sort, kiểm tra trạng thái trống và tải đặc tính đã phát hành; không có page error. PASS bài DOM IPQC Gia công hiện có sau cập nhật fixture danh mục máy. Kiểm thử ghi dữ liệu thật sẽ dùng transaction rollback; tiêu chuẩn hiện có được giữ nguyên.

## Bảng nhập kết quả và cỡ mẫu (nhóm 3)

Mở mặc định tab Nhập kết quả; liên kết duyệt/tiêu chuẩn vẫn mở đúng tab. Bảng một dòng/đặc tính có STT, mã, tên/đơn vị, danh nghĩa, dung sai, LSL/USL, các mẫu và kết luận. Lấy đặc tính từ đúng bản đã duyệt/đang có hiệu lực; thiếu mẫu không kết luận OK, ô vượt giới hạn tô đỏ ngay. Enter/Shift+Enter chuyển ô, Tab theo trình duyệt. Thêm mẫu giữ các giá trị đã nhập. Sửa tình huống change lặp trên cùng Model làm tải lại và mất ô đang nhập.

T217 chỉ thêm `ipqc_gc_lan.co_mau_thuc_te` và thay writer đo Gia công: cho bổ sung tối đa 100 mẫu/đặc tính, không giảm dưới cỡ mẫu tiêu chuẩn; lưu từng giá trị và cỡ mẫu thực tế riêng, snapshot tiêu chuẩn giữ nguyên. Không sửa bảng tiêu chuẩn hoặc writer Đúc. Không bắt tiêu chuẩn cũ thiếu tên bước phải nhập lại bước khi đo. Tiêu chuẩn hết hiệu lực hoặc thiếu giới hạn không được dùng để tự phán OK.

Đã áp dụng T217 staging. PASS Chrome với API fixture: tự tải 3 đặc tính, nhập 6 giá trị, cảnh báo NG, thêm 3 giá trị, lưu 9 giá trị và dashboard có kết quả mới. PASS SQL staging trong rollback: luồng soạn/duyệt/đo, OK biên/NG, retry, thiếu mẫu, bổ sung mẫu, chặn giảm cỡ mẫu, snapshot bất biến và cách ly Đúc. Không lưu tài khoản/tiêu chuẩn/kết quả thử lâu dài.

## Nhập file kết quả đo (nhóm 4)

Các module mới `ipqc-result-{parser,reader,import}.js` chỉ thao tác kết quả đo, không dùng parser bản vẽ và không ghi/sửa bảng tiêu chuẩn. Hai phương thức nhập dùng cùng `IpqcGcEntry`, cùng writer và cấu trúc từng mẫu/đặc tính.

Excel đọc giá trị số thực từ XLSX/XLS, hỗ trợ hàng đặc tính và bảng ngang. PDF ưu tiên lớp chữ; scan/ảnh dùng Tesseract cục bộ. Xem bản gốc/trang/sheet, danh sách mã/tên/giá trị đo, gợi ý ghép, dòng chưa khớp và đơn vị chưa rõ. Ghép ưu tiên mã, sau đó tên duy nhất hoặc No + danh nghĩa làm bằng chứng phụ; không ghép chỉ theo thứ tự dòng. Không tự sửa mã OCR O/0 hay đoán ô trống. Mẫu đọc cấu hình cột, dòng tiêu đề, dòng mẫu cho bảng ngang và lưu có tên trong localStorage trình duyệt.

Người dùng xác minh đơn vị và từng dòng trước Đồng bộ; các đơn vị độ dài/độ góc chỉ chuyển theo bảng hệ số xác định. Không rõ đơn vị phải chọn/xác nhận. Đồng bộ chỉ điền bảng chưa lưu; ghi đè giá trị khác phải xác nhận, hủy thì giữ ô tay. Sửa tay sau đồng bộ được phép, cần xác nhận lại bảng trước lưu. File gốc chỉ upload khi Lưu chính thức, tùy chọn, vào bucket private theo UID; có SHA-256. Chưa bấm Lưu thì không ghi kết quả hoặc upload file.

T218 đã áp dụng staging: thêm nguồn nhập, thông tin nhận diện và metadata file ở bảng kết quả; bucket private; view tổng hợp mở rộng nguồn/trace/cỡ mẫu. Wrapper kiểm tra auth/role, xác nhận nhập file, đường dẫn thuộc người nhập và object đã upload; writer nội bộ bị thu hồi quyền gọi trực tiếp. Giữ snapshot/OK-NG do server phán, retry, RLS và dữ liệu tiêu chuẩn.

PASS `tests/ipqc-result-parser.cjs`; PASS Chrome đọc XLSX, PDF có text và ảnh bảng đo bằng thư viện thật, đồng bộ/sửa tay/hủy ghi đè, lưu cùng nguồn/file private (API fixture). PDF/ảnh mẫu kiểm thử chứa các giá trị thực 20.02, 38.12, 15.15; không phải bản vẽ.

Đã đọc file công ty thật: PREMO `Kết quả kiểm tra N1 Premo 25.04.2025.xlsx` (157.07/157.48); HITACHI `kết quả đo N1 FR khuôn 25( 25.06.2025).xls`, sheet KQ ĐO 1, bảng ngang cấu hình header dòng 7, mã cột C, danh nghĩa dòng 8, mẫu dòng 12/13 (34.91/34.84). Giá trị lấy đúng mẫu, không lấy dòng Tiêu chuẩn trên/dưới. Các đặc tính không thuộc tiêu chuẩn thử vẫn chưa xác nhận, không đưa vào database.

PASS SQL rollback cho metadata nguồn/file, yêu cầu xác nhận, lưu vào dashboard, retry không trùng, chặn đường dẫn của người khác và bucket private. File gốc công ty và ảnh dựng chỉ nằm trong `.review/`, không commit. Chrome dùng tài nguyên PDF.js/Tesseract/SheetJS phiên bản ứng dụng, được phục vụ cục bộ trong bài test để tái hiện ổn định; ứng dụng tải thư viện/mô hình OCR qua CDN.
