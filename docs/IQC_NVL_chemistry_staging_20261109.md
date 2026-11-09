# IQC NVL và thành phần hóa học — staging, 09/11/2026

Phạm vi: nhánh `staging`, project Supabase `jcjbleugnclzsghfpmvk`. Không kết nối database hoặc triển khai MES Production. Một commit riêng cho yêu cầu IQC này; không gộp lại các commit Chất lượng cũ.

## Hành vi

- Màn Nhập báo cáo ngày IQC dùng chung danh mục sản phẩm và `nvl_materials` hiện có. NVL mang định danh `[NVL] mã`, không lẫn với sản phẩm cùng mã. Tìm bằng mã/tên; tên và nhà cung cấp lấy từ danh mục hiện có. Danh mục NVL không có phiên bản riêng; phiên bản BOM sản phẩm không được dùng để nhân đôi mã NVL.
- Nhóm/mác được cấu hình theo khóa NVL trong **Quản lý tiêu chuẩn → NVL – Hóa học IQC**. Không phân loại bằng tên. Nhôm/Kẽm chuyển sang hóa học; NVL khác giữ form ngoại quan. NVL chưa phân loại có hướng dẫn cấu hình và không được âm thầm lưu thành ngoại quan.
- Tiêu chuẩn hóa học là một loại trong bảng/phê duyệt tiêu chuẩn hiện có (`ipqc_btk`, `ipqc_btk_muc`). Giới hạn được QC nhập theo đúng mã/mác, Revision và ngày hiệu lực; sử dụng nguyên quy trình soạn → kiểm tra → phê duyệt. Admin có quyền từng bước như hiện tại. Không sửa hàm phê duyệt chung, không sửa bản đã duyệt.
- Báo cáo hóa học dùng `iqc_lots`, lưu snapshot tiêu chuẩn/kết quả, file phân tích gốc, ngày/ca/lô/nhà cung cấp/người kiểm. PDF, XLS/XLSX, JPG/JPEG/PNG tối đa 20 MB; file riêng tư, đường dẫn bất biến, tải khi lưu và xem qua URL có hạn. Không ghi đè file cũ.
- Bộ đọc dùng chung PDF/Excel/OCR, bổ sung cách diễn giải bảng hóa học riêng. Chỉ ghép hàm lượng thực tế với nguyên tố, đổi đơn vị rõ ràng `%`/`ppm`/`mg/kg`; không dùng Min/Max, LOD, balance hoặc giả định giới hạn làm kết quả. OCR thấp độ tin cậy và nhiều kết quả khác nhau phải chọn nguồn/nhập tay. Đổi mã khi đang đọc hủy kết quả cũ; thay file xóa các giá trị không có trong file mới.
- Sau xác nhận QC: một nguyên tố không đạt → NG; đủ nguyên tố bắt buộc và đều đạt → OK; thiếu tiêu chuẩn/dữ liệu bắt buộc → Chưa kết luận. Trước xác nhận chưa chốt kết luận. Server tính lại bằng giới hạn đã duyệt, không tin kết luận từ client. Báo cáo đang chờ có thể tải lại tiêu chuẩn mới rồi kiểm tra/xác nhận lại.
- Dashboard lọc mã/tên NVL, nhóm, phương thức, ngày kiểm và kết quả. Tách số lô hóa học và PCS ngoại quan; nguyên tố NG không tạo lỗi PCS. CSV áp dụng đúng bộ lọc, ghi nguyên tố không đạt và để trống số lượng PCS cho hóa học. Lưu trữ báo cáo bằng quyền quản lý, có audit.
- Chống lưu trùng khi thử lại do mất mạng; kiểm tra phiên bản `updated_at` khi sửa; RLS chặn ghi thẳng báo cáo hóa học và lỗi ngoại quan của lô hóa học. Các thao tác phân loại, soạn/duyệt, lưu/lưu trữ có lịch sử.

## Dữ liệu cần QC chuẩn bị

Khảo sát staging có **33 mã NVL** và **1 LOT IQC cũ**, chưa có cột phân loại/mác tin cậy hoặc tiêu chuẩn hóa học đã duyệt. Migration không tự tạo phân loại, giới hạn hoặc báo cáo mẫu.

Trước sử dụng thực tế: QC chọn từng mã tại loại tiêu chuẩn NVL, khai báo nhóm/mác chính xác; nhập bộ nguyên tố/Min/Max/đơn vị từ tiêu chuẩn được công ty xác nhận và gửi kiểm tra/phê duyệt. Sau đó chọn mã ở IQC tự chuyển đúng form. Nếu thiếu tiêu chuẩn có thể lưu lô Chưa kết luận. Không có chuẩn chung ADC12/ZAMAK được tự cài đặt.

Chưa có phiếu phân tích thực tế do người dùng cung cấp cho yêu cầu này; các file PDF/Excel/ảnh kiểm thử là dữ liệu tổng hợp, không phải tiêu chuẩn sản xuất. Các bố cục chưa nhận diện chắc chắn vẫn cần QC chọn nguồn hoặc nhập tay.

## Kiểm thử

- `node tests/iqc-chemistry-parser.cjs`: 118 ký hiệu, bảng dọc/ngang, Actual khác Min/Max, đơn vị và phép so sánh thập phân chính xác, kết quả mơ hồ, giới hạn, thiếu dữ liệu, OCR mất dấu thập phân/thấp độ tin cậy.
- `node tests/iqc-chemistry-browser.cjs`: Chromium dùng API/storage giả lập; file PDF/Excel/PNG/JPEG thật do test tạo. Catalogue/trùng mã, chuyển form, xác nhận, lưu/mở lại, mất phản hồi thử lại, thay file thiếu nguyên tố, sai chữ ký file, đổi mã khi đọc, bổ sung tiêu chuẩn cho lô đang chờ, bộ lọc/CSV, mobile, tiêu chuẩn và phê duyệt.
- `tests/iqc-chemistry-staging-rollback.sql`: chạy trên **staging** trong transaction `ROLLBACK`. Kiểm tra RPC/role/RLS thực, đúng chuẩn Nhôm/Kẽm, chưa duyệt/thiếu dữ liệu không OK, NG ưu tiên, lịch sử/Revision hiệu lực tương lai, file riêng tư, idempotency, zero PCS, audit, LOT cũ nguyên vẹn. Không lưu phân loại, giới hạn hoặc báo cáo thử. Sequence có thể tăng trong kiểm thử rollback, không đặt lại sequence.
- Hồi quy đạt: `iqc-workspace-browser.cjs` (gồm phân trang 1003 LOT), `ipqc-result-files-browser.cjs` (CMM PDF/ảnh/Excel và file mẫu công ty), `oqc-outsource-browser.cjs`, `ipqc-standards-manager-browser.cjs`, `ncp-images-browser.cjs`.
- `ipqc-cmm-apply-browser.cjs`: PDF ZEISS mẫu 11 giá trị vẫn ghép/điền/xác nhận/lưu đúng với tiêu chuẩn thiếu đơn vị; không thay đổi tiêu chuẩn hoặc luồng CMM.
- `node scripts/code-review-check.cjs --files ...`: không có lỗi mức cao/trung bình. Các cảnh báo thấp đã kiểm tra: markup dài, style/thông báo hiện hữu và thao tác thay con của **bản nháp** sau khi kiểm tra quyền/trạng thái. Không xóa tiêu chuẩn đã duyệt hoặc dữ liệu cũ.
- `git diff --check`, kiểm tra cú pháp JS/inline HTML; đóng gói frontend tĩnh. Không có `package.json`/build ứng dụng riêng trong repository.
- Checksum/số lượng 13 bảng IQC, danh mục/BOM, tiêu chuẩn, IPQC Đúc/Gia công, OQC và NCP được đối chiếu trước/sau migration (trừ các cột mới mặc định). Chỉ migration cộng thêm cấu trúc được áp dụng staging; dữ liệu thử rollback.
- `node tests/check-iqc-chemistry-staging.cjs`: chỉ đọc asset website staging sau push. Kiểm thử upload qua phiên người dùng thực chưa thực hiện; browser E2E sử dụng fixture, RPC/RLS được kiểm tra trực tiếp trong rollback.

Các test browser dùng Chrome cài sẵn và `MES_PLAYWRIGHT_PATH`; XLSX/PDF/OCR nạp từ các dependency kiểm thử tại `.review` theo quy ước test hiện có. `.review`, `.wrangler`, dữ liệu nguồn staging và file OCR sinh ra không đưa vào Git.

## Migration

`supabase/migration_phase_T232_iqc_nvl_hoa_hoc.sql` chỉ áp dụng project staging nói trên. Tạo phân loại/audit/idempotency, trường hóa học bổ sung trong LOT/tiêu chuẩn, RPC và bucket riêng tư `iqc-phan-tich`; giữ nguyên dữ liệu ngoại quan, giới hạn đã nhập, phê duyệt và các API IPQC/OQC/NCP. Không tự chạy migration trên Production.

Đã áp dụng T232 lên staging; kiểm thử SQL sau áp dụng đạt và rollback. Cả 13 bảng có số lượng/checksum dữ liệu cũ khớp trước/sau. Trạng thái sau kiểm thử: 33 NVL, 0 phân loại tự tạo, 0 tiêu chuẩn hóa học mẫu, 0 báo cáo hóa học mẫu, 0 audit thử; bucket riêng tư giới hạn 20 MB và 6 RPC nghiệp vụ đã sẵn sàng.
