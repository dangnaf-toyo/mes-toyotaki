# Kiểm tra nguồn QC03 trước khi sửa — 06/10/2026

## Nguồn đã kiểm tra

- Repo: `dangnaf-toyo/mes-toyotaki`; HEAD ban đầu `ae14039`, branch ban đầu thực tế là `master`, working tree sạch.
- Đã chuyển sang branch có sẵn `qc03-staging-fix`, cùng HEAD với master. Không sửa master.
- Đã fetch origin và tìm `qc03` trong HTML/JS/SQL của tất cả local branches và remote refs hiện có: không có kết quả.
- `origin/staging` ở `c0df3c0`; diff so với master gồm `.gitignore`, `CONTRIBUTING.md`, `bom.html`, `quan-ly-danh-muc.html`, `sanluong-supabase.html`, `shared/navbar.js`, `supabase/migration_phase_T61_bom_versions.sql`. Không tự nhập diff này vì navbar/danh mục là tài nguyên dùng chung.
- Repo là ứng dụng HTML/JS tĩnh; SQL hiện đặt ở `supabase/migration_phase_*.sql`. Không thấy package.json, bộ test hay workflow build trong checkout.

## RPC QC03

Danh sách đầy đủ tìm thấy trong các nguồn Git đã kiểm tra: **rỗng**.

Không có lời gọi hay định nghĩa SQL của `qc03_submit_ipqc`, `qc03_dashboard`, `qc03_notifications`, hoặc hàm `qc03_*` khác. Điều này chỉ phản ánh nguồn Git; chưa xác minh catalog DB staging. Không tạo hàm thay thế khi chưa biết chữ ký, schema và hành vi của bản staging cần bảo toàn.

RPC IPQC frontend hiện gọi:

- `duc_get_ipqc_periodic_due`
- `duc_request_ipqc_check`
- `duc_submit_ipqc_check`
- `duc_ipqc_bat_dau_ngay`
- `duc_ipqc_ket_thuc_ngay`
- `duc_ipqc_create_continue_request`
- `duc_ipqc_refresh_continue_request`
- `duc_ipqc_decide_continue_request`
- `duc_ipqc_update_continue_production`
- `duc_ipqc_cancel_continue_request`
- `duc_ipqc_set_tieu_chuan_pdf`
- `duc_ipqc_save_tieu_chuan`

## Chênh lệch với yêu cầu

| Luồng | Bằng chứng trong checkout | Cần đối chiếu bản staging |
|---|---|---|
| Chu kỳ IPQC | `ipqc.html:217`: 120 phút | Xác minh vận hành thực tế và SQL đang áp dụng |
| Ảnh IPQC | `ipqc.html:218`: tối đa 6 ảnh | Yêu cầu 10 ảnh; phân biệt ảnh lỗi và ảnh điều kiện máy |
| 1 shot, QR lô lỗi | Chưa xác nhận luồng đáp ứng trong checkout | Cần nguồn QC03 và hợp đồng dữ liệu staging |
| Cảnh báo | `submitCheck` nộp `CANH_BAO` qua `duc_submit_ipqc_check`; cần checklist có mục không đạt và ghi chú | Chưa thấy frontend tự gửi yêu cầu duyệt chỉ bằng lý do |
| Form duyệt | `ipqc-approval.html` có nhiều trường máy/model/process/lot/thông số | Đối chiếu cơ chế tự điền thông tin QC03 |
| Quyền duyệt | D61 kiểm tra admin/vai trò theo bước ở server; frontend vẫn hiển thị nút duyệt với mọi yêu cầu pending | Chưa kiểm thử với tài khoản thường/Admin/người có quyền trên staging |
| Toàn bộ pending | Query không lọc người tạo nhưng giới hạn 200 bản ghi mới nhất | Không bảo đảm lấy toàn bộ pending; cần phân trang hoặc query pending riêng |
| Notification | T66 có bảng thông báo; navbar chưa thấy notification bell | Cần bảo toàn và đối chiếu implementation staging |
| QC Manager | Feed, tra cứu và link NCP đã có; lịch sử ảnh mở tab mới | Yêu cầu popup ảnh, thống kê theo máy/lỗi lặp cần đối chiếu |
| Quá 2 giờ | Có chu kỳ 120 phút và ân hạn 30 phút cho thống kê đúng hạn | Cần test riêng cảnh báo quá 120 phút, không đánh đồng với KPI ân hạn |
| OQC | `oqc-daily.html` hiện tổng kiểm/OK/NG/%; có lọc ngày, sản phẩm, người kiểm, ca | Không giống bản chỉ hiện % theo ngày/model và click xem lỗi mô tả trong yêu cầu |
| NCP/OQC | Form NCP nằm ở `qc-manager.html`, phản hồi ở `ncp-detail.html` | Chưa xác nhận bản mới cho mở thiếu dữ liệu, chọn nhân viên/lỗi, khóa trường theo quyền và in ảnh |

## Kiểm tra đã chạy

- Quét cấu trúc toàn repo (219 file được liệt kê), code QC/IPQC/OQC/approval/notification, migration bảo mật và các nguồn Git hiện có.
- Parse bằng Node `vm.Script` toàn bộ JS standalone và script inline classic không có `src`: **48 script, 0 lỗi cú pháp**. Đây là kiểm tra cú pháp, không phải test hành vi hay kiểm tra toàn bộ dependency CDN.
- Không có lint/build/test runner được cấu hình trong repo. Máy hiện có Node, không tìm thấy `psql`/Supabase CLI qua PATH.
- Không gọi RPC ghi dữ liệu; không sửa DB; không deploy, push hoặc merge.
- Không thay đổi file OQC, IPQC, NCP, navbar hoặc SQL hiện có. Chỉ thêm báo cáo này.

## Blocker và phần cần bảo toàn

Chưa có URL/bản source QC03 staging hoặc schema SQL staging để đối chiếu. Không thể kết luận staging có drift chỉ từ Git. Nếu staging đang chạy đúng bản được mô tả, cần bảo toàn **HTML/JS QC03, IPQC, approval, notification, QC Manager, OQC/NCP và shared dependencies**, cùng **định nghĩa toàn bộ RPC qc03_*, bảng/cột, RLS, grants, trigger và storage policy liên quan** trước khi cập nhật.

Không reset/xóa/ghi đè nguồn staging. Cần URL staging và branch/commit hoặc bản xuất source hiện đang phục vụ, cộng schema/định nghĩa RPC staging (không chứa secret). Sau khi so sánh mới bổ sung migration review được trong `supabase/migrations`, giữ nguyên các sửa OQC và chạy kiểm thử vai trò/hành vi trên staging.

**Chưa đủ điều kiện xác nhận QC03 sẵn sàng test staging:** chưa có đúng source QC03, chưa có migration tương ứng và chưa có kiểm thử hành vi. Báo cáo này không phải xác nhận hoàn tất yêu cầu triển khai.
