# Chất lượng — bản tổng hợp để review, 09/11/2026

## Mốc đối chiếu

- Production: GitHub Pages xác nhận `mes.toyotaki.vn`, nhánh `master`, bản build thành công `cda817becb8e19dba5a232e8cd10e2550f908f14` (08/11/2026).
- Nguồn Chất lượng: snapshot staging `969bfd0d8d1199c31fbe8d6369df60b529b7a696`.
- Nhánh đóng gói: `review/quality-consolidated-20261109`, bắt đầu từ đúng mốc Production trên; **1 commit**, không viết lại lịch sử của staging.
- **101 file**: 100 file Chất lượng/phụ thuộc trực tiếp từ snapshot staging và báo cáo này. Chỉ đóng gói phần khác Production có liên quan đến đợt sửa 04–09/11/2026.

Không merge/push vào `master`, không triển khai Production, không chạy migration trên database nào trong lần tổng hợp này. `origin/staging` vẫn giữ nguyên.

## Nội dung

- **OQC:** số người kiểm và giờ công thực tế; phạm vi kiểm tra; Gia công ngoài → Mạ/In/Anode; giữ dữ liệu cũ chưa phân loại; nhãn, nhóm dữ liệu, bộ lọc, thống kê OK/NG và Excel theo phạm vi đã chọn.
- **IPQC Gia công / Dashboard IPQC:** nhập thủ công và file kết quả đo; đọc Actual từ CMM PDF/Excel/ảnh, ghép đặc tính và mẫu, xác nhận trước khi lưu, đánh giá OK/NG, nguồn file gốc, biểu đồ, thống kê và Excel; giao diện hai tab; ngày kiểm dùng để lấy đúng tiêu chuẩn lịch sử.
- **Quản lý tiêu chuẩn:** Gia công nằm trong module tiêu chuẩn hiện có; Revision/duyệt; dung sai có dấu và độ chính xác thập phân; copy dòng/Model độc lập; PDF/ảnh bản vẽ chỉ lưu và xem tham khảo; admin được thực hiện các bước duyệt theo quy tắc staging hiện có.
- **NCP:** theo dõi đối sách nội bộ/khách hàng, hạn/lịch sử, đồng bộ với phiếu hiện có; đính kèm nhiều ảnh lỗi, xem lớn, thêm sau tạo phiếu, xóa có lịch sử và lưu trữ riêng tư.
- **IPQC Đúc / thành phần chung:** chỉ tích hợp liên kết, cache và thành phần dùng chung trực tiếp liên quan; giữ luồng kiểm Đúc hiện hành, không đưa bản nháp cũ quay lại.

## Kiểm soát phạm vi

- Các bản nháp trong checkout gốc và worktree cũ không được sao chép hay sửa. Không gộp lại những bản sửa đã có trên MES chính.
- `shared/navbar.js` bắt đầu từ bản Production, chỉ thêm tên/liên kết IPQC Gia công và metadata trang. Không lấy thay đổi BOM, folder/menu hay CSS ngoài Chất lượng của staging.
- `gia-cong-dashboard.html` chỉ có liên kết vào IPQC Gia công và phiên bản cache navbar; không đổi nghiệp vụ Sản xuất.
- `bieu-do-chat-luong.html` chỉ bổ sung/cập nhật các script phục vụ tiêu chuẩn và biểu đồ IPQC; giữ phần đã có trên Production.
- Giữ nguyên các file Production ngoài phạm vi: `CNAME`, `.gitignore`, `CONTRIBUTING.md`, `KE_HOACH_TINH_NANG_MOI.md`, `quan-ly-danh-muc.html`, `bom.html`, `bavia-dashboard.html`, `duc-dashboard.html`, `khsx-tuan.html`.
- Không lấy migration Bavia T166, các bản sửa Kho/BOM/Nhân sự/Điều hành, tài liệu review cũ tháng 10 hay công cụ chuẩn bị bản nháp.
- `tests/qc-session-ui.cjs` được lấy nguyên bản đã push trên staging vì là fixture trực tiếp của test ảnh NCP và layout QC Manager. Không lấy các sửa test phát sinh trong lượt rà soát trước khi làm rõ phạm vi.
- Trừ các hunk Chất lượng được tách riêng trong navbar, toàn bộ 99 file còn lại khớp nội dung snapshot staging đã chốt. Không tự sửa nghiệp vụ trong lúc đóng gói.

## Kiểm thử trên worktree tổng hợp

- **64** JavaScript/script nội tuyến parse thành công; **70** tham chiếu script nội bộ tồn tại.
- **22 bộ test đạt:** `mes-nov04-integration`, `ipqc-gc-signed-decimal`, `ipqc-result-parser`, `ipqc-cmm-matching`, `ipqc-gc-parser`, `oqc-headcount`, `oqc-nov04-postgres`, `ipqc-zeiss-real`, `ipqc-gc-dom`, `ipqc-gc-repair-browser`, `ipqc-standards-manager-browser`, `ipqc-admin-approval-browser`, `ipqc-drawing-attachment-browser`, `ipqc-gc-signed-copy-browser`, `ipqc-gc-inspection-date-browser`, `ipqc-result-files-browser`, `ipqc-zeiss-browser`, `ipqc-cmm-apply-browser`, `ipqc-cmm-staging-standard-browser`, `oqc-outsource-browser`, `qc-manager-layout-browser`, `ncp-images-browser`.
- Có test Chromium thực cho tiêu chuẩn, quyền duyệt, bản vẽ nhiều trang, copy Model, nhập/đọc lại kết quả, CMM, nguồn file, dashboard, biểu đồ/Excel, OQC từng công đoạn, NCP ảnh/lịch sử/quyền và layout desktop/mobile.
- PDF M2 mẫu: đọc 2 trang, 11 giá trị Actual. Với snapshot tiêu chuẩn staging thực tế, TTI-MOT-04/A tự ghép 4, còn 7 chưa khớp; TTI-MOT-05/A tự ghép 5, còn 6 chưa khớp. Không đoán kích thước hình học hoặc tự tạo tiêu chuẩn để lấp chỗ thiếu.
- Test XLS/XLSX/PDF/ảnh OCR đạt sau khi bổ sung cache mô hình OCR vào thư mục fixture cục bộ. Lượt đầu thiếu asset mô hình của môi trường test; không sửa code sản phẩm để xử lý việc này.
- Code review tự động: không có phát hiện mức cao/trung bình. Còn cảnh báo thấp về định dạng code, cỡ chữ/thông báo cũ, kiểm tra `DELETE` đối với bảng con và ghi chú trạng thái staging của SQL; không chạy SQL để xử lý các cảnh báo này.
- Kiểm tra allowlist/hash: chỉ đúng file Chất lượng được chọn; các hunk BOM và file nghiệp vụ ngoài phạm vi giữ nguyên từ Production. `git diff --cached --check` đạt trước commit.

Các test UI/API dùng fixture cô lập; SQL chạy bằng PostgreSQL cục bộ/PGlite. Không đăng nhập hay ghi dữ liệu vào MES chính. Chưa coi đây là nghiệm thu upload qua tài khoản thật trên website hoặc triển khai Production.

## Các commit nguồn gần đây

`76f1df2`, `05fd35b`, `d0cb5bc`, `2403783`, `0d7f84a`, `40f1463`, `952fbdc`, `7c14768`, `e50e33b`, `2791cc6`, `73d07af`, `af8ba1e`, `c5ef4cd`, `f586c3f`, `b8dc092`, `3b3b92a`, `b5a4021`, `7645016`, `355ea66`, `96d0e4a`, `dce0d87`, `10e7dec`, `fff8498`, `969bfd0`.

Chỉ lấy nội dung cuối cùng còn khác mốc Production và đúng phạm vi, không cherry-pick nguyên các commit hỗn hợp và không sửa lịch sử những commit này.
