# Cập nhật IPQC thời gian kiểm, OQC biểu đồ và kế hoạch nhân lực QC

Chỉ staging: https://mes-toyotaki.dangnaf.workers.dev/

Database staging: `jcjbleugnclzsghfpmvk` (`mes-toyotaki-staging`). Không thay đổi production, main hoặc master. Bản phát hành giữ đầy đủ staging tới `47a1b21`, gồm T121–T126 và D74; tích hợp bằng merge thông thường, không reset/force push. Giữ lịch sử sự cố IPQC, mô tả lỗi rút gọn và checksheet bảo dưỡng khuôn từ các commit mới.

## Thay đổi

- IPQC xác minh trạng thái checkpoint thật thay vì dựa vào trường trạng thái có thể thiếu trong hàng đợi. Chỉ bật thao tác sau khi backend xác nhận phiên đã lưu.
- Khôi phục phiên theo tài khoản từ bảng session trên server, kể cả khi mất con trỏ localStorage. Giữ bản nháp ảnh/checklist trong IndexedDB khi trình duyệt cho phép; lỗi bản nháp cục bộ không ngăn lưu phiên trên hệ thống.
- Xác nhận đầy đủ checklist trước OK/NG/Cảnh báo. Bộ đếm tiếp tục trong lúc upload/lưu; thời điểm hoàn tất lấy tại lần cập nhật kết quả thành công trên server. Lỗi lưu giữ nguyên giờ bắt đầu, hỗ trợ thử lại và xác minh phản hồi bị mất. QC Manager dùng trường thời lượng đã lưu, không tính lại dữ liệu cũ.
- OQC có top lỗi và biểu đồ xu hướng theo ngày/tuần, dùng toàn bộ dữ liệu phù hợp bộ lọc ngày/model/khách hàng/người kiểm/ca. Ghi rõ PCS NG/PCS đã kiểm và lượt lỗi riêng biệt. Xem tháng/tuần sử dụng đúng khoảng ngày của bộ lọc.
- Lịch sử OQC mới nhất trước, 5 lần/trang; biểu đồ và xuất Excel dùng toàn bộ tập dữ liệu, không dùng riêng trang đang xem. Nút Lưu; sửa record gốc, cho sửa ngày nhập sai, giữ metadata lỗi/ảnh và audit trước/sau hiện có. Chi tiết hiển thị lịch sử chỉnh sửa.
- Đổi tên menu/tiêu đề thành Định mức kiểm tra QC và Kế hoạch kiểm tra. Hiệu suất kế hoạch 80%, giờ/người tự nhập.
- Ba nguồn kế hoạch: tự thêm, Gia Công, OQC. Nạp đúng dòng tuần/ngày/model, cho điều chỉnh trước khi lưu. Lưu lại cập nhật cùng dòng, không cộng lại SL.
- Liên kết vào đúng dòng OQC của kế hoạch sản xuất tuần. Sửa SL từ phía sản xuất đồng bộ về cùng kế hoạch QC; giữ phiên bản định mức đã lưu, chỉ đổi phiên bản khi người dùng chọn rõ trên bản chỉnh sửa. Sửa model của dòng tuần chọn định mức của model mới, không dùng sai snapshot model cũ; có xung đột đích sẽ báo lỗi, không ghi đè.
- Dưới SL từng ngày/model và trong form thêm/sửa OQC hiển thị nhân lực cần. Tổng ngày cộng khối lượng chính xác rồi hiển thị một chữ số thập phân: 1.000 PCS × 30 giây / (7 giờ × 3.600 × 80%) → 1,5 người; hai model → 3,0 người. Thiếu giờ/định mức ghi rõ Chưa đủ dữ liệu tính nhân lực.
- Giữ quy trình ghi lý do và duyệt lại kế hoạch đã gửi duyệt; ghi audit thay đổi kế hoạch/giờ.

## Migration

`supabase/migration_phase_T122_qc_followup_staging.sql` yêu cầu T118/T120 đã có.

Đây là file QC follow-up, độc lập với `migration_phase_T122_lich_su_su_co.sql` của nhóm cập nhật lịch sử sự cố. Không tự chạy thêm migration của các task khác. RPC lịch sử sự cố đã được xác minh có trên staging.

- Đổi hai hàm mới của T118: `duc_ipqc_session_complete_trigger`, `duc_submit_ipqc_session`; không thay thân RPC kiểm tra cũ.
- `oqc_capacity_plan`: thêm `source_kind`, `source_plan_id`, `oqc_plan_id` và index/FK liên kết kế hoạch tuần. Cho phép NULL phiên bản/giây khi một kế hoạch sản xuất mới chưa đủ định mức.
- `oqc_capacity_day.hours_per_person`: cho phép NULL khi kế hoạch mới chưa nhập giờ. NULL luôn được giao diện coi là thiếu dữ liệu, không phải 0 người.
- Thêm RPC `qc_save_linked_plan(jsonb)`, `qc_save_week_hours(date,jsonb,text)`, `qc_save_oqc_week(bigint,jsonb,jsonb)` và trigger đồng bộ OQC tuần. Chỉ authenticated gọi RPC; hàm lưu có kiểm tra vai trò/RLS tương ứng. Không thêm vai trò, không đổi kết nối, không đổi chính sách RLS hiện có.
- Không backfill, gán định mức mới, UPDATE hoặc DELETE hàng loạt dữ liệu cũ. Các câu UPDATE/DELETE trong thân hàm chỉ chạy khi người dùng lưu/sửa kế hoạch cụ thể về sau.
- Đã chạy thử toàn migration và smoke test trên staging trong giao dịch rollback trước khi áp dụng chính thức. Mọi dữ liệu thử được rollback.

## Kiểm thử và giới hạn

- PostgreSQL cục bộ: 18 nhóm kết hợp T118/T120/T122; migration chạy lại, giữ lịch sử NG/NCP, cả ba kết quả IPQC, thời điểm server lưu thành công, ba nguồn kế hoạch, chống trùng, sửa model, giữ snapshot, phân quyền authenticated và quy trình duyệt.
- UI/analytics và hồi quy: 28 + 11 + 9 + 18 + 7 + 4 kiểm tra/nhóm. Bao gồm tải hơn 1.000 record nhưng chỉ hiển thị 5/trang, biểu đồ không bị giới hạn theo trang, edit giữ metadata và phép tính nhân lực.
- Chromium: 7 nhóm desktop/mobile cho zoom ảnh, khôi phục phiên/ảnh nháp sau reload, xóa con trỏ localStorage vẫn lấy phiên từ server, gửi kết quả và bố cục OQC.
- Database staging, dưới SQL role authenticated và ngữ cảnh tài khoản QC có quyền: lưu/đọc định mức, kế hoạch ba nguồn, nạp lại không trùng, liên kết nguồn OQC, tổng nhân lực 3,0; tạo/sửa OQC giữ ID, có audit và cập nhật báo cáo; bắt đầu/kết thúc IPQC, giữ NG và đúng thời lượng. Toàn bộ bản ghi smoke được rollback.
- Kiểm thử Chromium dùng backend giả lập; kiểm thử database staging dùng SQL role-context. Chưa có kiểm thử E2E đăng nhập tài khoản MES qua giao diện live vì công cụ điều khiển phiên trình duyệt hiện báo lỗi khởi tạo. Cần chủ MES kiểm tra thao tác đăng nhập và luồng nghiệp vụ trên link staging trước khi nghiệm thu; không coi các kiểm thử trên là E2E live.

## File ứng dụng/migration

`ipqc.html`, `oqc-daily.html`, `oqc-capacity.html`, `khsx-tuan.html`, `shared/navbar.js`, `shared/mes-ipqc-session.js`, `shared/mes-ipqc-warning.js`, `shared/mes-oqc-history.js`, `shared/mes-oqc-record.js`, `shared/oqc-capacity.js`, `shared/oqc-defect-charts.js`, `shared/qc-production-staff.js`, `supabase/migration_phase_T122_qc_followup_staging.sql`.

Kiểm thử: `tests/mes-update.cjs`, `tests/qc-requirements.cjs`, `tests/qc-session-ui.cjs`, `tests/qc-session-browser.cjs`, `tests/qc-session-postgres.cjs`, `tests/oqc-capacity-ui.cjs`, `tests/oqc-capacity-browser.cjs`, `tests/qc-followup-ui.cjs`, `tests/qc-followup-postgres.cjs`.
