# IPQC Gia công: giao diện tối giản và ngày kiểm - STAGING 07/11/2026

Phạm vi: nhánh `staging`. Không kết nối hoặc triển khai database Production. Không sửa tiêu chuẩn, đặc tính kích thước hoặc công thức OK/NG/SPC.

## Giao diện

- Nhập kết quả: Ngày kiểm, Model, Máy, Ca; bỏ trường Revision và Mã lô. Ngày mặc định theo Việt Nam, không phụ thuộc múi giờ trình duyệt.
- **Hình thức nhập** có đúng hai lựa chọn **Thủ công / Tự động**, mặc định Thủ công. Tự động mở khu vực CMM hiện có; vẫn đối chiếu/xác nhận, điền Actual và chỉ ghi khi Lưu.
- Dashboard giữ tám bộ lọc: Từ ngày, Đến ngày, Công đoạn, Model, Máy, Ca, Người kiểm, Đặc tính. Bỏ bộ lọc Revision, Nguyên công và Mã lô; không còn truy vấn theo các trường đã bỏ.
- Rút gọn tiêu đề, nút Xem, chỉ số Lần kiểm/Số mẫu, các khu vực Biểu đồ kích thước, Biểu đồ SPC, Đặc tính NG, Chi tiết kết quả.
- Giữ cảnh báo SPC và các ngưỡng tính Cp/Cpk; phần giải thích quá trình/phân phối chuyển vào tooltip. Điều kiện 25 nhóm SPC, cùng cỡ mẫu/tiêu chuẩn/máy, 100 giá trị/30 nhóm/xác nhận để đánh giá năng lực không đổi.
- Bộ lọc thẳng hàng, chỉ số gọn; đã xem ảnh desktop và mobile, không tràn trang.

## Ngày kiểm và lịch sử tiêu chuẩn

Thêm RPC đọc `ipqc_gc_tieu_chuan_theo_ngay(Model, ngày)` dùng chung với kiểm tra phía server khi lưu. QC không chọn Revision.

Chỉ xét tiêu chuẩn Gia công đã duyệt có ngày hiệu lực không sau ngày kiểm. Trong cùng nguyên công, phiên bản kế tiếp kết thúc khoảng hiệu lực của phiên bản trước theo ngày bắt đầu. Cờ đang dùng hiện tại không loại bỏ tiêu chuẩn lịch sử khi nhập bù. Nếu trùng ngày hiệu lực hoặc nhiều nguyên công cùng phù hợp, báo **Tiêu chuẩn chồng lấn**, không chọn theo ID hoặc chọn ngẫu nhiên.

Không có tiêu chuẩn hợp lệ thì báo **Chưa có tiêu chuẩn**. Không lấy phiên bản tương lai hoặc bản đang chờ duyệt để điền thay. Với dữ liệu staging hiện tại, hai Model TTI-MOT-04/05 có tiêu chuẩn bắt đầu 06/11/2026; ngày kiểm trước đó không tự lấy bản này.

Server kiểm tra lại phiên bản theo ngày khi Lưu, vẫn lưu `id_btk`, Revision và snapshot đặc tính/LSL/USL. Có khóa phối hợp với phê duyệt để tránh đổi tiêu chuẩn giữa kiểm tra và lưu. Không thay đổi quy trình duyệt.

Đổi ngày nhưng vẫn cùng tiêu chuẩn giữ kết quả đang nhập. Nếu chuyển sang tiêu chuẩn khác, hỏi ngắn trước khi xóa dữ liệu chưa lưu; Hủy giữ cả dữ liệu và Model/ngày cũ. Có chặn phản hồi cũ trả về trễ và sự kiện blur lặp làm khóa nhầm ô đang nhận focus.

## Database T223

Migration `supabase/migration_phase_T223_ipqc_gc_ngay_kiem.sql` chỉ áp dụng staging `jcjbleugnclzsghfpmvk`:

- Thêm `ngay_kiem date`; thời điểm `thoi_diem` vẫn là thời điểm tạo thực tế từ server, không đổi thành ngày nhập bù.
- Thêm `cap_nhat_luc` và trigger cập nhật khi bản ghi đổi. Không gán thời điểm migration làm thời điểm cập nhật của bản ghi cũ.
- Mã lô được phép để trống vì đã bỏ khỏi form. Nguyên công kết quả được phép null để tương thích các tiêu chuẩn staging đang không có nguyên công. Không tạo mã lô/nguyên công giả và không thay giá trị cũ.
- View `ipqc_lan_tong_hop` giữ toàn bộ cột cũ, bổ sung ngày kiểm và thời điểm cập nhật. Dữ liệu cũ chưa có ngày riêng dùng ngày Việt Nam từ thời điểm đã lưu; không backfill hoặc suy đoán một ngày kiểm mới.
- Nhánh Đúc trong view chỉ suy ra ngày từ thời điểm sẵn có như bộ lọc trước đây; không sửa bảng, writer hoặc chức năng nhập IPQC Đúc.
- Dashboard, nhãn ngày trên biểu đồ và Excel dùng ngày kiểm. Thời điểm tạo/cập nhật, Revision và metadata cũ vẫn có để truy vết. Biểu đồ tách theo ID tiêu chuẩn/đặc tính, không trộn giới hạn giữa các phiên bản.
- Giữ wrapper công khai kiểm tra nguồn/file/xác nhận; writer nội bộ `ipqc_gc_luu_do_t217` vẫn không cấp EXECUTE trực tiếp cho authenticated. Giữ kiểm tra quyền, danh tính server, đủ mẫu, chống trùng, snapshot và đánh giá lại OK/NG.
- Client cũ không gửi ngày kiểm vẫn lưu ngày Việt Nam hiện tại; mã lô đã gửi vẫn được giữ. Retry không tạo thêm bản ghi hoặc đổi ngày/giờ audit.

## Kiểm thử

1. SQL migration + kiểm thử trong một transaction ROLLBACK trước khi áp dụng; chạy lại bộ kiểm thử ROLLBACK sau khi áp dụng.
2. Tiêu chuẩn A lịch sử không còn cờ đang dùng, B mới: chọn đúng theo ngày; kiểm tra ranh giới bắt đầu, trước hiệu lực, bản chờ duyệt, trùng ngày và nhiều nguyên công. Server từ chối ID tiêu chuẩn không đúng ngày.
3. Nhập bù tháng 01, lưu tháng 11: ngày kiểm, thời điểm tạo và cập nhật riêng; Dashboard lọc đúng tháng 01. Kiểm tra dữ liệu cũ và ranh giới ngày Việt Nam khi UTC còn là hôm trước.
4. Chrome đặt múi giờ Honolulu: mặc định ngày kiểm vẫn theo Việt Nam; hai chế độ đúng tên, không còn các trường đã bỏ; chọn tiêu chuẩn tự động, giữ/hủy đổi dữ liệu chưa lưu, kiểm tra blur và phản hồi async đảo thứ tự.
5. Nhập thủ công nhiều mẫu, thêm mẫu, OK/NG, lưu/đọc lại, Dashboard, biểu đồ, điều kiện SPC/CpCpk, Excel theo ngày kiểm và giới hạn lịch sử đạt.
6. CMM PDF M2 1.pdf thực tế (11 Actual), Excel XLSX/XLS, PDF thường và OCR ảnh vẫn đọc/điền/lưu đúng trên tiêu chuẩn thử tương ứng; 0 RPC ghi/0 upload trước Lưu. Trạng thái ghép với hai tiêu chuẩn thực tế vẫn 4/11 hoặc 5/11 như báo cáo M2, không ép ghép các vị trí hình học chưa xác định.
7. Kiểm tra IPQC Đúc, số thập phân/dung sai có dấu và sao chép/phát hành tiêu chuẩn hiện có đạt; không sửa mã các bộ tính.
8. Kiểm tra cú pháp, `git diff --check` và bộ review tĩnh. Cảnh báo cấp EXECUTE cho writer nội bộ là yêu cầu cố ý không thực hiện để bảo vệ wrapper; header test ghi STAGING vì không được chạy trên Production. Không có phát hiện mức cao.

Các PDF, ảnh chụp, dữ liệu snapshot và thư viện test cục bộ nằm trong `.review/`, không commit.

T223 đã áp dụng và kiểm thử lại thành công trên staging. Đối chiếu trước/sau giữ nguyên checksum tiêu chuẩn `a531b9295049e34dff5316a4b2876689`, đặc tính `295020aed6fd31e83e2f64295ace1829`, kết quả GC theo cột cũ, các giá trị đo và dữ liệu Đúc. Quyền đọc tiêu chuẩn vẫn là authenticated; anonymous không được gọi RPC mới, authenticated không được gọi writer nội bộ trực tiếp.

## File chính

Ứng dụng: `ipqc-gia-cong.html`, `shared/ipqc-gia-cong.js`, thông báo Model/ngày trong `shared/ipqc-result-import.js`.

SQL: migration T223. Kiểm thử mới: `tests/ipqc-gc-inspection-date-browser.cjs`, `tests/ipqc-gc-inspection-date-staging.sql`; cập nhật các test hiện có để dùng ngày kiểm/tiêu chuẩn tự chọn, không tham chiếu trường đã bỏ.
