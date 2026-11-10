# IPQC Đúc — nhiều CVT và kiểm tra một phần

Phạm vi: nhánh `staging`, dựa trên `507ed12`. Database duy nhất được kết nối: staging `jcjbleugnclzsghfpmvk`. Không kết nối MES Production, không merge/force push. Bản sửa Gia công/OCR đang dở ở bản làm việc khác được giữ riêng.

## Hành vi

- Chọn hạng mục thực tế cần kiểm; mỗi kích thước có mã CVT tự nhập, giá trị và OK/NG riêng, thêm/xóa ngay tại dòng. Chấp nhận `2-1`, `2-2`, `69`, `70`; không dùng mã CVT làm STT hay PCS.
- Kiểm 4/30 hoặc 1/30 hạng mục vẫn kết thúc được. Hạng mục không chọn là **Chưa kiểm**; hạng mục đã chọn nhưng thiếu dòng/kết quả là **Thiếu kết quả**. Cần nhập đủ phần đã chọn hoặc bỏ chọn phần chưa thực hiện.
- Chặn mã trùng trong cùng hạng mục/phiên, giá trị sai định dạng, không có kết quả, sai tiêu chuẩn và sửa phiên đã hoàn tất. Mã giống nhau ở các hạng mục khác nhau được chấp nhận.
- Nút **Kết thúc kiểm tra** suy ra OK/NG từ dữ liệu thực tế. Có NG thì cảnh báo, vẫn dùng yêu cầu ghi chú/ảnh, quy trình NG và điều kiện máy hiện có.
- Lưu nháp CVT theo tài khoản/checkpoint/phiên bản. API mới lưu kết quả và hoàn tất phiên trong một transaction; máy/model/người kiểm/thời điểm và đánh giá dung sai do server xác định. Gửi lại cùng payload không tạo kết quả trùng.
- Lịch sử ngay tại IPQC, Dashboard biểu đồ và cửa sổ **Chi tiết lượt kiểm** hiện có đều xem được các CVT. Chi tiết đọc đúng checkpoint/phiên bản, phân trang kết quả và giữ dữ liệu chưa có mã CVT.
- Dashboard giữ số phiên kiểm máy; thống kê kết quả đo chỉ lấy dữ liệu thực tế. Biểu đồ tách từng mã CVT và phiên bản hiện tại; lịch sử vẫn giữ các phiên bản cũ. Không gộp vị trí CVT thành cỡ mẫu để tính giới hạn kiểm soát cũ.

## Database

Đã áp dụng `supabase/migration_phase_T234_ipqc_duc_cvt.sql` trên staging.

- Thêm `ipqc_do_kq.ma_cvt` nullable, unique theo checkpoint/hạng mục/mã không phân biệt hoa thường.
- Giữ nguyên khóa `(id_checkpoint, muc_no, mau)`; `mau` là thứ tự lưu dòng, không phải mã CVT.
- Thêm danh sách hạng mục đã chọn, số đã/chưa kiểm và dấu kiểm payload vào `ipqc_do_lan`; dữ liệu cũ không được tự gán CVT hoặc backfill.
- RPC mới `duc_submit_ipqc_cvt` kiểm quyền IPQC/QC Manager/admin và chủ phiên, gọi nguyên luồng `duc_submit_ipqc_session` sau khi kiểm tra dữ liệu đo.
- API đọc Gia công được ủy quyền nguyên trạng sang hàm cũ, chỉ nhánh Đúc được bổ sung trường lịch sử. Hàm nền cũ và hàm tính giới hạn là private; đã kiểm tra `authenticated`/`anon` không gọi trực tiếp được.

Đối chiếu sau migration và sau kiểm thử: **3 bộ tiêu chuẩn, 32 đặc tính, 0 lần đo/0 kết quả ban đầu được giữ nguyên**. Dấu kiểm dữ liệu không đổi:

| Dữ liệu | MD5 trước/sau |
|---|---|
| Tiêu chuẩn | `6338b3f3f3dd32c04693596edc1e1165` |
| Đặc tính | `295020aed6fd31e83e2f64295ace1829` |
| Kết quả Gia công | `d41d8cd98f00b204e9800998ecf8427e` |

## Kiểm thử

Đã đạt:

- `node tests/ipqc-casting-cvt.cjs`: 4/30, 1/30; mã tự do; thêm/xóa; mỗi CVT OK/NG; trùng mã, số sai, thiếu kết quả; mở lại nháp; hoàn tất OK/NG và payload đúng phần đã chọn (API fixture).
- `node tests/ipqc-casting-browser.cjs`: Chrome thật, Dashboard tách CVT/revision, tỷ lệ NG và lọc máy, dữ liệu cũ, chuyển sang biểu đồ Gia công với 2 mẫu/lần, nhập/xóa ở chiều rộng 390px không tràn ngang; chi tiết đúng checkpoint/phiên bản và **1.002 CVT qua nhiều trang**.
- `node tests/ipqc-start-integration.cjs`: 2 nhóm khóa/mở dữ liệu theo phiên đã bắt đầu, đồng bộ bất đồng bộ, khóa mục kích thước tự đánh giá.
- `node tests/qc-session-ui.cjs --ipqc-session-only`: **13 nhóm** hồi quy phiên kiểm, bản nháp, lỗi mạng/quyền, mất phản hồi, chống bắt đầu/gửi trùng, quy trình NG.
- `node tests/ipqc-standards-manager-browser.cjs`: quản lý tiêu chuẩn, bản vẽ riêng tư, xác nhận/phiên bản, copy/paste và tách Đúc/Gia công.
- `node tests/ipqc-gc-repair-browser.cjs`: danh mục máy, nhập kết quả và Dashboard Gia công, kể cả trạng thái chưa có tiêu chuẩn.
- `tests/ipqc-casting-cvt-staging-rollback.sql`: chạy trên database staging trước/sau migration; nhiều CVT và kiểm một phần, NG đúng một CVT, dữ liệu sai bị từ chối, transaction không lưu dở, retry, lịch sử legacy, sai chủ phiên, quyền đọc bằng role `authenticated`/IPQC và API Gia công không đổi. **Rollback toàn bộ fixture và thay đổi quyền thử nghiệm.**
- Kiểm tra cú pháp, `git diff --check`, build tĩnh.

Không kết luận toàn bộ test cũ của repository đều xanh: chạy rộng `qc-session-ui.cjs` gặp fixture NCP cũ thiếu helper `sbTaiHet`; lượt này chỉ sửa/chạy 13 nhóm phiên IPQC bằng cờ phạm vi. Không sửa NCP để chữa fixture ngoài yêu cầu.

Static review không còn mức CAO. Cảnh báo yêu cầu grant cho `ipqc_gioi_han_tinh` được giữ có chủ đích: đây là hàm private, không được cấp trực tiếp cho authenticated. Câu DELETE trong RPC chỉ thay dữ liệu đo nháp của đúng checkpoint do người dùng sở hữu, chưa hoàn tất; dữ liệu đã hoàn tất không đi tới bước này.

Để chạy test cục bộ, cấu hình `MES_JSDOM_PATH`, `MES_FAKE_IDB_PATH`, `MES_PLAYWRIGHT_PATH` trỏ tới dependency đã cài. Bài SQL chỉ dùng project staging và transaction rollback. Ảnh kiểm tra/build/log nằm trong `.review/`, không đưa vào commit.
