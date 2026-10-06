# QC02 rebuild — 06/10/2026

Branch: `qc02-rebuild`, tạo từ checkout Git `ae14039` (cùng master tại thời điểm kiểm tra). Các file IQC, IPQC, QC Manager, OQC và NCP đều đã có trên master. Chưa commit/push/merge/deploy.

## Thay đổi

- `iqc.html`: bổ sung khoảng ngày nhận LOT (ngày/tháng/năm, múi giờ +07, ngày cuối bao gồm cả ngày) cho tìm kiếm model/tên/LOT. Cho phép chỉ lọc ngày; kiểm tra khoảng ngày ngược; lỗi API không còn biến thành danh sách rỗng. Giữ style hệ thống và popup chi tiết LOT có sẵn. Người kiểm vẫn dùng field hiện có: IQC chưa có nguồn dropdown nhân viên trong implementation hiện tại, không thêm logic tài khoản.
- `ipqc.html`: ghi rõ chu kỳ 2 giờ/lần, 1 shot/lần; nhãn QUÁ 2 GIỜ sau 120 phút cho định kỳ; link tới lịch sử/ảnh trong QC Manager. Giữ submit/checklist/upload và giới hạn ảnh hiện có. 1 shot là hướng dẫn thao tác; schema/submit hiện tại không có trường số shot để cưỡng chế ở server.
- `qc-manager.html`: thống kê số lượt OK/NG/cảnh báo theo máy và số lượt mục checklist không đạt; popup ảnh có fallback link cho trình duyệt không hỗ trợ dialog; nhãn và màu cảnh báo quá 120 phút. Query đọc bao gồm mọi điểm đang chờ (vẫn lọc máy đang hoạt động), và các lần hoàn thành 24h gần nhất thay vì chỉ theo thời điểm tạo. KPI ân hạn 30 phút hiện có vẫn giữ; nhãn quá 2 giờ độc lập với KPI đó.
- `shared/qc02-view.js`: helper đọc/hiển thị cho hai trang IPQC và QC Manager; thống kê dùng dữ liệu đã tải; render bảng bằng textContent; popup chỉ cho URL HTTP(S).

OQC, OQC daily, NCP detail, shared navbar, auth/client và SQL không đổi. Không xóa field, bộ lọc, thống kê hay chức năng pallet/in/NCP. Không thêm workflow duyệt hoặc notification mới.

## RPC/API đang dùng và dependency

Mọi RPC dưới đây có định nghĩa trong SQL đã lưu ở repo; chưa xác nhận migration nào đã áp dụng trên DB staging.

| Module | RPC hiện có |
|---|---|
| IQC | Không gọi RPC; dùng Supabase bảng trực tiếp |
| IPQC | `duc_get_ipqc_periodic_due`, `duc_request_ipqc_check`, `duc_submit_ipqc_check`, `duc_ipqc_bat_dau_ngay`, `duc_ipqc_ket_thuc_ngay` |
| QC Manager | `duc_get_ipqc_periodic_due`, `duc_get_available_ng_checkpoints_for_ncp`, `duc_ncp_open_case`, `duc_ncp_record_sorting`, `duc_ncp_choose_sua`, `duc_ncp_request_scrap`, `duc_ncp_record_repair`, `duc_ncp_approve_scrap`, `duc_ipqc_save_tieu_chuan`, `duc_ipqc_set_tieu_chuan_pdf` |
| OQC | `oqc_tao_pallet`, `oqc_dong_pallet`, `oqc_them_tem_vao_pallet` |
| OQC daily | `oqc_save_daily_inspection` |
| NCP detail (giữ nguyên) | `duc_ncp_update_root_cause`, `duc_ncp_submit_root_cause_for_approval`, `duc_ncp_approve_root_cause`, `duc_ncp_reopen_root_cause`, `duc_ncp_xac_nhan_task`, `duc_ncp_cach_ly_task`, `duc_ncp_giai_toa_tem_v2` |

- IQC: `iqc_lots`, `iqc_defects`, `quality_defect_catalog` (đọc/ghi hiện có).
- IPQC: đọc `duc_ca_hien_tai`, `duc_bao_cao_ca`, `duc_ipqc_tam_dung`, `duc_ipqc_checkpoint`, `duc_ipqc_tieuchuan`, `duc_su_co_log`; upload hiện có vào Storage `ipqc-evidence`.
- QC Manager: cùng checkpoint/ca/log với IPQC; thêm `master_products`, `master_machines`, `duc_shot_khuon`, `duc_ncp`, `duc_ipqc_tieuchuan` và Storage PDF tiêu chuẩn hiện có.
- OQC: `oqc_pallet`, `oqc_pallet_item`, `duc_tem`.
- OQC daily: `master_products`, `master_employees`, `quality_defect_catalog`, `cd_khsx_tuan_plan`, `oqc_daily_inspection`.
- NCP detail: `duc_ncp`, `duc_ipqc_checkpoint`, `duc_tem_cach_ly`.
- Các trang phụ thuộc CDN Supabase, `shared/supabase-client.js`, `shared/navbar.js`; OQC daily thêm XLSX CDN. IQC/OQC dùng chung danh mục lỗi; IPQC/QC Manager/NCP dùng chung checkpoint.
- Trang approval đã tồn tại trong Git được giữ nguyên ngoài phạm vi sửa, không được thêm vào rebuild.

## Validation và giới hạn

- Parse toàn repo HTML classic script và JS: 49 script, không lỗi cú pháp (không kiểm TypeScript Edge Functions bằng phép parse này).
- 10 assertions Node: trước/đúng/sau 120 phút, dữ liệu phút thiếu/sai, thống kê nhiều máy, phân loại NG/cảnh báo, lỗi lặp, dữ liệu rỗng.
- Chrome headless fixture: bảng escape nội dung, popup mở/đóng và cleanup; PASS, không lỗi JavaScript ghi nhận trong fixture. Chưa kiểm console của các trang với phiên đăng nhập thật.
- RPC inventory: không thiếu định nghĩa SQL trong repo; không đổi tên/chữ ký RPC.
- Không reference RPC tiền tố QC03 trong HTML/JS/SQL; không migration mới, không DB write/seed từ phiên làm việc.
- Repo không có package.json/build/lint/test runner; chưa có test end-to-end dữ liệu thực. Cần kiểm quyền đọc, response RPC và hạn phân trang Supabase trên staging.
- Trước deploy staging: review diff, xác nhận deployment source, rồi test IQC ngày đầu/cuối/model/LOT, IPQC 119/120/121 phút và submit 1 shot, popup ảnh, pending cũ, thống kê theo máy/lỗi, cùng regression OQC filters/kiểm tra/NCP/in.

Đủ để đưa bản code này lên staging nhằm kiểm thử sau khi xác nhận nguồn deployment; chưa xác nhận nghiệp vụ end-to-end hay đủ điều kiện production. Không deploy trong phiên này.

`QC03_STAGING_AUDIT.md` là báo cáo untracked có trước rebuild; không thuộc bộ thay đổi QC02 và không được đưa vào commit QC02.
