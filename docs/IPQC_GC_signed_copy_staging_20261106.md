# Dung sai có dấu và sao chép Model — STAGING 06/11/2026

Nền `b5a4021`, nhánh `staging`. Chỉ project `jcjbleugnclzsghfpmvk`; không truy cập ghi, merge hoặc triển khai Production.

## Dung sai và dữ liệu lịch sử

Preflight đọc trực tiếp schema, hàm lưu và dữ liệu hiện tại: writer cũ dùng `abs()` cho cả hai sai lệch, sai lệch dưới là độ lớn. Có 15 đặc tính Gia công của tiêu chuẩn đã phát hành; không được áp công thức có dấu trực tiếp lên các hàng này.

T221 thêm `ipqc_btk_muc.dung_sai_co_dau`, mặc định `false`. Không sửa số liệu lịch sử. Hàng cũ/snapshot không có cờ vẫn dùng cách tính cũ, ưu tiên LSL/USL đã lưu. Editor Gia công chỉ chuyển dấu trong bộ nhớ để hiển thị đúng ý nghĩa cũ; khi người dùng tạo/gửi Revision mới, payload có cờ và lưu đúng dấu. Client cũ không gửi cờ vẫn tương thích với cách lưu cũ. IPQC Đúc không bật cờ dù payload có gửi, giữ công thức và cách nhập cũ.

Gia công đổi nhãn thành Sai lệch trên/Sai lệch dưới. Phép cộng thập phân dùng số nguyên có hệ số (BigInt), không dùng phép cộng số thực để dựng giới hạn. Khi sửa danh nghĩa/sai lệch, LSL/USL cập nhật ngay theo `LSL = danh nghĩa + dưới`, `USL = danh nghĩa + trên`; ô trống không thành 0. Hiển thị dạng `14.6 (+0.3/+0.1)`, giữ đủ chữ số giới hạn. Chặn giới hạn đảo và số không hợp lệ. Frontend nhập đo/Dashboard và writer đo Gia công hiểu cờ trong snapshot; writer số học PostgreSQL dùng `numeric`. Các giới hạn thủ công có sẵn được bảo toàn nếu người dùng không sửa danh nghĩa/sai lệch.

Nhập/xuất mẫu Excel tiêu chuẩn Gia công dùng nhãn có dấu. File cũ với cột Dung sai − được nhận biết là độ lớn và chuyển tương thích; tiêu chuẩn Đúc giữ nhãn và cách đọc cũ.

## Sao chép toàn bộ sang Model khác

Nút ở vùng phiên bản của Quản lý tiêu chuẩn → Gia công. Cửa sổ chọn phiên bản nguồn, Model đích từ danh mục, Revision mới và xác nhận thông tin. Không sao chép thay đổi chưa lưu ở editor.

T222 cung cấp RPC `ipqc_gc_sao_chep_tieu_chuan`:

- Khóa theo Model đích, xác thực quyền soạn; từ chối Model nguồn trùng đích, nguồn không phải Gia công, Model không tồn tại, Revision trùng hoặc bản nháp đích đang có cùng bước. Không ghi đè nguồn/đích.
- Tạo ID riêng, trạng thái **Bản nháp** (`ban_nhap` chỉ hợp lệ với Gia công), chưa xác nhận/chưa phát hành. Chỉ có thể kiểm tra/duyệt sau khi chỉnh sửa, xác nhận và gửi qua luồng hiện có.
- Sao chép mọi trường cấu hình đặc tính đang có: No/mã/tên/loại/danh nghĩa/sai lệch/giới hạn/OK-NG/dụng cụ/tần suất/cỡ mẫu/phương pháp/đơn vị/JSON ghi chú. Chuyển nguồn lưu độ lớn sang dấu với giới hạn hiệu lực giữ nguyên. Không sao chép ID đặc tính hoặc người/thời gian xác nhận.
- Không sao chép kết quả đo, lịch sử kiểm tra/phê duyệt, file bản vẽ hoặc mã bản vẽ nguồn. Hướng dẫn đính kèm bản vẽ phù hợp Model đích.
- Ghi `nguon_sao_chep` gồm ID, Model, Revision, bước nguồn, người/UID và thời gian; ghi snapshot lịch sử riêng theo ID mới. Header lấy khách hàng/tên sản phẩm của Model đích.
- FK lịch sử Gia công được đổi sang cascade để thao tác Hủy bản nháp hiện có dọn đúng lịch sử phụ của bản nháp. Migration không xóa hàng nào; RPC vẫn chặn hủy tiêu chuẩn đã phát hành. Đã kiểm thử cả hai trạng thái.

## Kiểm thử

- `tests/ipqc-gc-signed-decimal.cjs`: PASS cả 5 ví dụ, `0.1 + 0.2 = 0.3`, số thập phân nhỏ/phẩy thập phân, phân biệt trống/0, dấu và giới hạn đảo; giá trị nguồn legacy không bị sửa.
- `tests/ipqc-gc-signed-copy-browser.cjs`: PASS Chrome với backend fixture: chọn nguồn 50 hoặc 10 hạng mục, chặn đích có nháp/Revision trùng, copy 50, header/khách hàng/lịch sử nguồn đúng, file nguồn không gán sang đích, nháp chưa có nút duyệt, 5 ví dụ tính ngay, lưu/mở lại đúng dấu, xác nhận/gửi/duyệt và nhập đo theo Revision B; 14.69 là NG với 14.7–14.9.
- `tests/ipqc-gc-signed-copy-staging-rollback.sql`: PASS PostgreSQL staging thật, chạy thử hai migration trong rollback trước áp dụng và chạy lại sau áp dụng. 5 ví dụ lưu số đúng dấu; dữ liệu magnitude/Đúc giữ cách lưu; copy từ nguồn legacy giữ giới hạn; copy 50 cấu hình, sửa 3; không sửa nguồn/đích cũ; ngăn nháp dùng đo/duyệt sớm; từ chối Revision trùng/nguồn Đúc; phát hành rồi đo phán NG đúng, snapshot giữ dấu; hủy nháp riêng được, hủy bản đã phát hành bị chặn. Không cấp execute hàm nội bộ hoặc cho anon sao chép.
- Hồi quy PASS editor chung, 20 trường hợp quyền duyệt, IPQC Đúc (2 nhóm Start/session), bản vẽ PDF/PNG/JPG/JPEG chỉ tham khảo, DOM Dashboard/Excel, đọc kết quả XLSX/PDF/ảnh và hai Excel công ty PREMO/HITACHI. RPC Gia công cũ `ipqc-gc-staging-rollback.sql` PASS cỡ mẫu/retry/nguồn file/snapshot/quyền/cách ly Đúc.
- Đã xem ảnh giao diện; cú pháp và diff whitespace đạt. Kiểm tra tĩnh không có CAO. Một nhắc TB đòi grant cho `ipqc_gc_luu_do_t217` được rà tay: đây là hàm nội bộ phải **không** grant cho authenticated; kiểm thử quyền xác nhận bị thu hồi. Không thay grant này chỉ để làm sạch cảnh báo.

Chrome sử dụng backend fixture; PostgreSQL/RPC staging được kiểm thử thật trong rollback. Không mô tả đây là E2E bằng tài khoản QC đăng nhập trên tiêu chuẩn vận hành.

## Đối chiếu sau áp dụng

Loại các cột metadata mới khỏi phép so sánh, checksum trước/sau hoàn toàn giống nhau:

- Tiêu chuẩn: `69a980f60fa14d6961c2c1b2eed839fb`.
- Đặc tính: `e8d488bbccb4335f3b8093a4fd744151`.

15 LSL/USL Gia công hiện có giữ nguyên; không hàng cũ nào bị đánh dấu signed. Số bản sao thử còn lại sau rollback: 0. Không để lại tiêu chuẩn, kết quả đo hoặc quyền mẫu lâu dài trên staging. Các file bản vẽ và nội dung chuẩn đã phát hành không được ghi lại.

## File chính

`shared/ipqc-gc-standard.js`, `shared/ipqc-btk-qc.js`, `shared/ipqc-gc-entry.js`, `shared/ipqc-gia-cong.js`; cập nhật nạp/cache ở `qc-manager.html`, `ipqc-gia-cong.html`, `bieu-do-chat-luong.html`; migration T221/T222; các bài kiểm thử trên, fixture/API kiểm thử và kiểm tra asset triển khai. Không sửa `ipqc.html` hoặc `shared/ipqc-spc.js`.
