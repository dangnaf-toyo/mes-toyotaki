# QC02 — sửa theo yêu cầu thực tế

Branch `qc02-rebuild`, nền commit `55601ab`. Các sửa đổi này chưa commit/push/deploy; không sửa master, không ghi DB, không thêm migration hoặc thay secret/env.

## Thay đổi

- `qc-manager.html`: thống kê nằm cuối tab real-time, sau chờ kiểm / tuân thủ / kết quả gần đây. Real-time và lịch sử đều có cột điều kiện máy. Bản ghi cũ không có marker được ghi “Chưa ghi nhận điều kiện máy”, không suy đoán đã/chưa kiểm. Nút Chi tiết ở mọi kết quả mở dialog tại trang, có máy/model/loại/người/thời gian/kết quả/checklist/ghi chú/trạng thái máy/ảnh/vấn đề/sự cố liên quan từ dữ liệu hiện có. Tìm NCP và link số phiếu giữ nguyên.
- `ncp-detail.html`, `shared/qc02-ncp.js`: thông tin phiếu chia nhóm, grid hai cột trên desktop và một cột ở màn hẹp; bảng có xuống dòng và giới hạn cột. Giữ nguyên form nguyên nhân, đối sách, cách ly và khóa/duyệt. Nút “In phiếu đối sách A4” dùng CSS/window.print, có thông tin và ảnh, thêm vùng trống Nguyên nhân, Đối sách, Người trả lời / Ngày trả lời, Xác nhận. Không dùng backend PDF; số trang tùy dữ liệu.
- `oqc-daily.html`: bỏ Pareto, Top SP NG, xu hướng khỏi UI và bỏ đoạn render tương ứng. Giữ form, KHSX, tiêu chuẩn, bộ lọc, số liệu tổng hợp, lịch sử, sửa record và Excel. Mã nhân viên dùng select, tự điền tên; bảo toàn người kiểm trên record cũ khi không còn trong danh sách. Khởi tạo sau khai báo helper để tránh lỗi khi API trả nhanh.
- `iqc.html`, `shared/qc02-data.js`: không có PDF thì không hiển thị khối tiêu chuẩn; có URL PDF mới hiển thị nút. Giữ autocomplete model và popup LOT đầy đủ. Nhân sự dùng helper chung.
- `shared/qc02-view.js`: bảo đảm thuộc tính hidden không bị CSS display:flex ghi đè. Lightbox chung hiện có được giữ: nền tối, đóng, trước/sau, phím trái/phải; áp dụng IQC/IPQC/QC Manager/NCP, helper cũng nạp trên OQC. OQC hiện tại không có gallery ảnh lỗi để mở; ảnh QR phục vụ đọc mã giữ nguyên.
- `tests/qc02-supplement-fixtures.cjs`: bổ sung kiểm tra vị trí thống kê, badge máy, dialog chi tiết, ảnh, ẩn/hiện PDF, nhân sự mới có quyền đọc, loại inactive, tên tự điền, bỏ biểu đồ và vùng viết tay.

## Nhân sự — giới hạn cần giải quyết

**Cập nhật:** đã chuẩn bị endpoint đọc chung không migration; xem `QC02_PERSONNEL_REVIEW.md`. Phần dưới mô tả giới hạn của query trực tiếp trước endpoint. Endpoint chưa triển khai nên các giới hạn này vẫn áp dụng cho fallback hiện tại.

IQC/NCP/QC Manager và OQC dùng cùng `Qc02Data.employees()`. Directory đọc `master_employees` có phân trang và bổ sung `user_roles` mà tài khoản hiện tại được phép đọc; chỉ ghép mã trùng, không đoán liên kết từ tên. OQC lọc role oqc không phân biệt hoa/thường; Admin không vào dropdown người kiểm OQC, giữ bộ lọc nghiệp vụ cũ. Admin có thể là actor lưu tùy RPC hiện có, khác với nhân viên được chọn trên phiếu. IPQC/OQC pallet/approval lấy người thực hiện từ MesAuth; không cho chọn người khác thay tài khoản đang thao tác.

Hai bảng vẫn là hai nguồn lưu vật lý. Helper chung KHÔNG phải một bảng nhân sự đã đồng bộ hoàn chỉnh. Không thể bảo đảm mọi tài khoản mới xuất hiện cho mọi người: policy `self or admin read user_roles` trong migration S1 chỉ cho người thường đọc chính mình, Admin đọc toàn bộ. Frontend không vượt RLS. Trạng thái vô hiệu hóa tài khoản trong Supabase Auth không có nguồn đọc danh mục đã xác nhận; không suy đoán từ role. Để hoàn thành yêu cầu một nguồn chuẩn và tự đồng bộ đầy đủ cần xác nhận mapping mã nhân viên/tài khoản và cơ chế directory có quyền đọc phù hợp. Chưa tạo/chạy migration vì không có hợp đồng dữ liệu đó.

## Kiểm tra

- Parse 54 script classic trong HTML toàn repo và shared JS: PASS.
- `git diff --check`: PASS.
- Chrome offline với API giả/CSP chặn network: IQC, IPQC, QC Manager, NCP, OQC daily PASS; không lỗi JS được ghi nhận trong fixture.
- Kiểm tra mẫu PDF: `C:/Users/OS/AppData/Local/Temp/qc02-correction-tests/ncp-handwriting-a4.pdf`, 116441 byte, 3 trang A4 (594.96 × 841.92 pt), có ảnh và vùng viết tay trong DOM bản in. Chưa thử máy in vật lý.
- Chưa kiểm thử tài khoản/RLS và dữ liệu thật trên staging. Không gọi RPC ghi dữ liệu thật. Không deploy staging hay production trong lần sửa này.
- Không thêm code/RPC qc03_*. Navbar và Supabase client không thay đổi. Repo không có build/package.json để chạy npm build.
