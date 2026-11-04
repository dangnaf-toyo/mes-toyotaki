# Thay đổi MES — 04/11/2026 — STAGING

Checkout độc lập `.nov04-staging`, nhánh `staging`, nền `ac54148`. Project database duy nhất được dùng: `jcjbleugnclzsghfpmvk`. Không truy cập ghi hoặc migrate production. Checkout gốc đang xung đột được giữ nguyên.

## Nhóm 1 — OQC nhân lực

Thêm số người kiểm mặc định 1; người kiểm chính vẫn là một nhân viên. Ghi thời gian kiểm thực tế, tính giờ công của số người tham gia; giờ riêng của nhân viên đã định danh được ưu tiên. Phân biệt lượt nhân lực và số nhân viên đã định danh không trùng. Người chưa định danh không được tính thành mã nhân viên giả. Năng suất = PCS / tổng giờ công. Không thay công thức CAPA hoặc định mức lịch sử.

T210 thêm hai cột nullable, không backfill. RPC hiện có giữ kiểm tra quyền, phiên bản định mức, CAS, retry và lịch sử, đồng thời lưu nhân lực/thời gian cùng transaction. UI sửa/tải lại và Excel có số người. Không có thời gian thực tế thì không tạo giờ giả.

Kiểm thử: `node tests/oqc-headcount.cjs`, `node tests/oqc-workspace-math.cjs`: PASS; migration chạy thử transaction rollback thành công trên staging. Chưa kiểm thử UI bằng phiên đăng nhập thực tế.

T210 đã áp dụng STAGING; commit nhóm 1 `76f1df2`, push `origin/staging` thành công.

## Nhóm 2 — Phạm vi và gia công ngoài

Nhãn phạm vi dùng một cách viết thống nhất từ `MesOqcScope.labels`. Giữ nguyên mã enum và dữ liệu cũ. Báo cáo gia công ngoài mới phải chọn Mạ/In/Anode; lịch sử chưa phân loại giữ NULL. Các phạm vi khác lưu công đoạn ngoài là NULL. Bộ lọc công đoạn ngoài áp dụng lên cùng tập bản ghi dùng cho dashboard, biểu đồ, OK/NG và Excel; có lựa chọn tổng hợp và chưa phân loại.

T211 thêm cột nullable, cập nhật RPC hiện có với kiểm tra dữ liệu và lịch sử. `node tests/oqc-nov04-postgres.cjs`: PASS lưu/tải nhân lực, chặn count sai, bắt buộc và lưu đúng 3 công đoạn, giữ lịch sử chưa phân loại và kiểm tra quyền. Migration chạy thử rollback trên staging thành công.

T211 đã áp dụng staging; nhóm 2 push thành công `05fd35b`.

## Nhóm 3 — NCP và đối sách

T212 giữ nguyên JSON cũ, bổ sung bảng theo dõi đối sách nhiều loại trong cùng phiếu và nhập các nội dung cũ vào bảng theo dõi với loại/thời điểm trả lời chưa rõ giữ NULL. Các sửa đổi trong luồng JSON hiện có đồng bộ sang bảng theo dõi. Tạo đối sách mới được chọn nội bộ/khách hàng; thêm/sửa/bỏ hạn linh hoạt, ghi lịch sử đầy đủ trước/sau, người và thời điểm server. Người phụ trách lấy từ danh sách nhân sự.

Ngày mở NCP lấy server lúc insert; trigger giữ nguyên ngày mở khi update, lưu riêng người/thời điểm cập nhật. Hạn khi mở phiếu có thể trống theo yêu cầu mới. Bảng theo dõi có lọc loại/trạng thái, liên kết phiếu, các mốc thời gian Việt Nam và màu tự tính: chưa trả lời vàng (gồm chưa đặt hạn), quá hạn chưa trả lời đỏ, đã trả lời xanh; trả lời muộn vẫn xanh và giữ cờ muộn. Dữ liệu cũ chưa có mốc trả lời không được gán thời gian giả.

Kiểm thử trực tiếp `tests/ncp-nov04-rollback.sql` kèm migration trong transaction rollback: PASS ngày tạo bất biến, hạn tùy chọn, hai loại, ưu tiên trạng thái, thời gian trả lời server, cờ muộn và lịch sử hạn. Chưa QA giao diện đăng nhập đầu cuối.

T212 đã áp dụng staging; nhóm 3 push thành công `d0cb5bc`.

## Nhóm 4 — IPQC Gia công và đọc bản vẽ

T213 tái sử dụng `ipqc_btk`, `ipqc_btk_muc` và luồng duyệt ba bước hiện có; mở rộng metadata bản vẽ/Revision/bước gia công, đặc tính, đơn vị, phương pháp, cỡ mẫu, giới hạn LSL/USL trực tiếp và dấu xác nhận. Cùng Model/Revision có thể quản lý độc lập theo bước gia công. Giữ nguyên khóa và hành vi tiêu chuẩn Đúc khi bước gia công NULL. Tiêu chuẩn đã duyệt không được sửa trực tiếp bởi API soạn.

`ipqc-gia-cong.html` và các script mới: nhập tiêu chuẩn thủ công hoặc PDF/JPG/JPEG/PNG; trái là bản gốc, phải là bảng gợi ý có trang/vị trí, nguồn chữ/OCR, mức tin cậy và ô xác nhận. PDF.js 4.10.38 đọc lớp chữ trước; Tesseract.js 6.0.1 xử lý scan/ảnh và phần hình khi lớp chữ chưa đủ. OCR chạy cục bộ trong trình duyệt, không gửi bản vẽ tới dịch vụ AI. Bản gốc chỉ upload vào bucket private trên staging khi người có quyền lưu bản nháp; lấy signed URL khi xem. Lưu lịch sử soạn và người/thời điểm xác minh từng đặc tính. Phát hành tiếp tục dùng QC Manager → Giám đốc sản xuất.

Các kích thước/ren/GD&T/ghi chú chưa rõ luôn chưa xác nhận; không tự áp dung sai chung hoặc gán dung sai 0. Giới hạn Min/Max có thể lưu mà không tự tạo danh nghĩa. Nhận diện là bước gợi ý, không phải cam kết đọc đầy đủ bản vẽ kỹ thuật phức tạp. Người dùng bắt buộc đối chiếu/sửa/xóa/thêm và xác nhận trước gửi duyệt.

Kết quả đo Gia công lưu riêng theo phiên bản/ca/máy/lô/người/thời điểm server; từng mẫu được kiểm tra trên server, retry dùng request ID, snapshot tiêu chuẩn không đổi khi tiêu chuẩn nguồn thay đổi. Không dùng checkpoint hoặc ghi kết quả vào IPQC Đúc.

Dashboard có Đúc/Gia công/Tất cả, bộ lọc ngày/model/Revision/bước/máy/ca/người/lô/đặc tính, tổng hợp và bảng chi tiết, đặc tính NG, Excel và in/lưu PDF bằng trình duyệt. Biểu đồ kích thước có danh nghĩa và LSL/USL; I–MR hoặc Xbar–R chỉ khi có >=25 nhóm cùng cỡ mẫu 1–5 và một máy. Cp/Cpk cần >=100 giá trị, >=30 nhóm, không có tín hiệu mất kiểm soát và xác nhận điều kiện quá trình/phân phối; sigma lấy từ MR/R trong nhóm, không dùng nhầm độ lệch chuẩn tổng thể.

Kiểm thử:

- `tests/ipqc-gc-staging-rollback.sql`: PASS soạn/duyệt/đo nhiều mẫu, biên 19.95 OK và 20.06 NG cho 20±0.05; thiếu mẫu bị chặn; retry không trùng; snapshot bất biến; dashboard tổng hợp và cách ly Đúc; Max-only không tự tạo danh nghĩa; cùng Revision khác bước độc lập.
- Staging hiện chỉ có 5 Admin và 1 OQC. Kiểm thử ba vai trò dùng thay đổi tạm trong transaction rollback, không lưu phân quyền mới. Chưa có tài khoản IPQC/QC Manager/GĐ SX để người dùng chạy quy trình thực tế, cần phân công bởi chủ hệ thống.
- `node tests/ipqc-gc-dom.cjs`: PASS sự kiện form thực, tải Revision đã duyệt, đo nhiều mẫu/NG, tự tính giới hạn có dấu, xác nhận/gửi draft, lọc dashboard hai công đoạn/tất cả, biểu đồ theo phiên bản, chặn SPC khi thiếu dữ liệu, Excel theo bộ lọc. Đây là DOM test bằng fixture, không phải trình duyệt đăng nhập staging.
- `node tests/ipqc-gc-parser.cjs`: PASS dung sai đối xứng/lệch/một phía, không tự tạo dung sai, ren/GD&T/ghi chú cần xác minh, điều kiện Cp/Cpk.
- Thử bằng bản vẽ thực tế trong thư mục BẢN VẼ: `1FC, 1PB - CL CENTER.pdf` và `1012-BẢN VẼ ĐÚC CỦ NHÔM LIGO PRO-v1.pdf` là scan, OCR tạo lần lượt 73 và 19 ứng viên ở lần thử sparse-text; tất cả chưa xác nhận. `20240604-CL CENTER-3A26020000_SOZAI_Rev1.pdf` có 105 text items, phần chữ kết hợp OCR cho ra 100 ứng viên ở lần thử sau (bao gồm ghi chú), không tự xác nhận. Đã render và kiểm tra hình gốc. Số ứng viên không phải số kích thước đã đọc chính xác; không đưa dữ liệu thử vào dashboard.
- Script tái hiện: `node scripts/check-ipqc-drawings.mjs <PDF...>`. Thư viện test trong `.review/tools`: `pdfjs-dist@4.10.38`, `tesseract.js@6.0.1`, `@napi-rs/canvas@0.1.80`; DOM test dùng `linkedom@0.18.12`. Không commit bản vẽ, mô hình OCR hoặc ảnh render riêng tư.

T213 đã áp dụng STAGING 04/11/2026. Không tạo hoặc đổi vai trò tài khoản lâu dài; bucket bản vẽ private. Chưa dùng tài khoản người dùng thực tế để kiểm thử đăng nhập trình duyệt.
