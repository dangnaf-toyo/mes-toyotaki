# Kế hoạch tính năng tiếp theo — MES Toyotaki (sau khi hoàn tất chuyển Supabase)

> Tài liệu này tiếp nối `KE_HOACH_MIGRATE_DATABASE.md` (đã hoàn tất việc chuyển toàn bộ 6 module từ Google Apps Script sang Supabase). Từ đây, `KE_HOACH_MIGRATE_DATABASE.md` giữ vai trò lịch sử/tham khảo; **file này là danh sách việc cần làm tiếp** để hệ thống thực sự "quản lý" được, không chỉ nhập liệu.
>
> Nguồn gốc: đề xuất theo yêu cầu người dùng ngày 2026-08-14, dựa trên hiểu biết về 6 module hiện có (Sản lượng, Chất lượng, Chuyển công đoạn, Đúc+IPQC+In tem+QC Manager+NCP+Mobile, Kế hoạch tuần, Tồn kho NVL). Làm dần theo mức ưu tiên người dùng chọn — CHƯA có mục nào bắt đầu code, đây là backlog.
>
> Bổ sung ngày 2026-08-15: backlog vận hành được xây dựng từ `Công đoạn của Toyotaki.md`. Mục tiêu dài hạn là MES phục vụ **truy xuất theo lô, kiểm soát chất lượng xuyên công đoạn và cải tiến hiện trường**; không chỉ là nơi ghi sản lượng.

## Nhóm 1 — Quản lý hệ thống

- [x] **Quản lý tài khoản & phân quyền** (2026-08-14) — (a) và (b) đã code, triển khai (SQL + Edge Function deploy qua Supabase CLI) và **test thành công trên production** (tạo tài khoản bằng mã nhân viên `nv001`, đăng nhập được). Gồm: bảng `public.user_roles` + hàm `has_role()`/`current_role_of()` (`supabase/migration_phase_S1_accounts_roles.sql`), đăng nhập bằng mã nhân viên (username) cho công nhân không có email thật qua hàm `resolve_login_email()` (`supabase/migration_phase_S2_username_login.sql`, sửa `shared/login.html`), Edge Function `admin-create-user` tạo tài khoản Auth mới bằng service_role (`supabase/functions/admin-create-user/index.ts`), trang admin `quan-ly-tai-khoan.html` (chỉ role admin vào được, tạo tài khoản + đổi vai trò). (c) RLS của các bảng nghiệp vụ khác (sản lượng/chất lượng/Đúc...) CHƯA đổi sang kiểm tra `has_role()` cụ thể — vẫn đang chỉ kiểm tra đăng nhập — làm dần khi có thời gian, để tránh khoá ghi hàng loạt cùng lúc.
- [ ] **Nhật ký thao tác (audit log)** — nhiều bảng đã có cột người/giờ cập nhật (`nguoi_cap_nhat`, `last_updated_at`, `nguoi_tt`...) nhưng rải rác, chưa có 1 màn hình tổng hợp "ai sửa gì lúc nào" xuyên suốt các module. Cần quyết định: bảng audit log riêng (ghi qua trigger) hay tổng hợp truy vấn từ các bảng nghiệp vụ hiện có.
- [ ] **Giám sát job nền (`pg_cron`)** — các job định kỳ (poll Diecast, quét sinh checkpoint IPQC) chạy âm thầm trong Postgres, lỗi sẽ không ai biết trừ khi tự vào Supabase Dashboard → Database → Cron Jobs kiểm tra. Cần 1 màn hình admin hiện trạng thái lần chạy gần nhất/lỗi gần nhất.
- [x] **Quản lý danh mục tập trung** (2026-08-14) — đã code, triển khai và test thành công trên production. Thêm policy ghi (insert/update/delete, giới hạn role admin qua `has_role()`) cho `master_products`/`master_machines`/`master_employees`/`duc_shot_khuon` (`supabase/migration_phase_S3_danh_muc_write.sql`), trang `quan-ly-danh-muc.html` (4 tab: Máy/Sản phẩm/Nhân sự/Khuôn, chỉ admin vào được, thêm/sửa/xoá). Nhân sự có thêm cột `bo_phan` tự do (Đúc/Bavia/QC/IPQC/Kho NVL/Kế hoạch/Bảo trì — gợi ý, gõ tự do được, `supabase/migration_phase_S4_nhansu_bophan.sql`). Danh sách vai trò (đăng nhập hệ thống lẫn ca sản xuất) đang khoá cứng theo `check constraint` — thêm vai trò mới cần sửa code, để sau khi phát sinh nhu cầu thật. Không đổi các RPC ghi hiện có (`duc_end_shift`...) vì chạy `security definer`, bỏ qua RLS.
- [x] **Menu điều hướng chung & chuẩn hoá tiêu đề trang** (2026-08-16) — trước đó mỗi trong 21 trang tự có header riêng, không đồng nhất, và không có điều hướng chung (phải quay về `index.html` mới sang trang khác được). Thêm `shared/navbar.js` (file mới, tự vẽ, không framework) — 1 thanh menu ngang cố định trên mọi trang (trừ `shared/login.html`), nhóm theo khu vực làm việc (Điều hành & Báo cáo / Sản xuất — Đúc ngang hàng Bavia-Gia công-Sơn-OQC / Chất lượng / Kho & Truy xuất / Quản trị-chỉ-admin), thu gọn ☰ trên di động, gộp hiển thị đăng nhập/đăng xuất. Cùng đợt: 1 thanh tiêu đề chuẩn hoá (`PAGE_META`, icon+tên+mô tả) render ngay dưới navbar thay cho header tự viết riêng của từng trang — 16 trang xoá hẳn header cũ, 5 trang có toolbar chức năng (đồng hồ/select ca/tabs/nút Refresh-In) chỉ xoá phần brand/tiêu đề và giữ nguyên toolbar; trang cần tiêu đề đổi theo runtime dùng hook `window.MesNav.setTitle(title, desc)`. Không sửa file SQL nào.

## Nhóm 2 — Quản lý sản xuất thực tế

- [ ] **Dashboard tổng hợp/xu hướng** — OEE, sản lượng, NG hiện chỉ tính/hiện theo từng ca (bảng `duc_bao_cao_ca`/`duc_lich_su_san_xuat` đã có dữ liệu lịch sử). Cần màn hình xem xu hướng theo ngày/tuần/tháng, so sánh máy với máy, so sánh SP với SP — dữ liệu nguồn đã sẵn có, chỉ thiếu giao diện tổng hợp.
- [ ] **Phân tích sự cố (Pareto)** — đã phân loại sự cố A1-F1 (`CONFIG.LOAI_SU_CO`) và có `DOWNTIME_COST_PER_MIN` tính chi phí dừng máy, nhưng chưa có báo cáo tổng hợp "loại sự cố nào chiếm nhiều thời gian/chi phí nhất" theo tuần/tháng/máy.
- [ ] **Cảnh báo chủ động (ngoài màn hình)** — sự cố mở quá lâu, IPQC quá hạn, khuôn sắp tới ngưỡng bảo dưỡng hiện chỉ hiện khi có người đang nhìn dashboard. Cần kênh thông báo đẩy (email qua Supabase, hoặc webhook sang Zalo/Telegram) khi vượt ngưỡng — cần quyết định kênh trước khi làm.
- [ ] **Bảo trì khuôn theo lịch** — hiện chỉ cảnh báo theo số shot lũy kế (ngưỡng bảo dưỡng/thay mới), chưa có lịch bảo dưỡng định kỳ theo thời gian/nhắc hẹn trước.
- [ ] **Liên kết tồn kho NVL ↔ kế hoạch sản xuất** — 2 hệ (`nvl_*` và `duc_*`) hiện độc lập hoàn toàn, chưa tự trừ tồn NVL theo sản lượng thực tế đúc ra (cần định mức NVL/sản phẩm — dữ liệu này chưa có ở đâu cả, phải khảo sát thêm nếu làm).
- [ ] **Tem chỉ thị sản xuất kiểu Kanban (máy Kẽm 190T / 160T)** (bắt đầu 2026-08-29) — với các mã SP có quy cách đóng gói chuẩn hoá, **in trước** một loạt tem theo KH ca (chỉ thị xuống máy như thẻ Kanban); mỗi thùng xong, người thao tác **quét QR** để ghi nhận giờ SX thực tế + người thao tác + máy đúc; **chỉ khi quét** thì sản lượng mới cộng vào `tt_ca` trên dashboard; kết ca chốt theo số đã quét. Tem thừa cuối ca để nguyên, hôm sau SX bù. Cho đổi máy đúc lúc quét (máy hỏng). NG vẫn chỉ ghi nhận lúc kết ca. **Thiết kế**: luồng song song với luồng in-khi-xong hiện tại (máy khác không đổi); marker tem Kanban = `duc_tem.id_lo_chi_thi IS NOT NULL`; `duc_recompute_tt_ca` đổi mốc cửa sổ thời gian sang `coalesce(ngay_gio_ghi_nhan, ngay_gio_in)`. **Việc**: migration D48 (cột mới `duc_tem.ngay_gio_ghi_nhan/id_lo_chi_thi/so_thung_stt`, `master_products.sl_dong_goi_chuan`, `master_machines.kanban`; RPC `duc_tao_lo_kanban`/`duc_ghi_nhan_tem_kanban`/`duc_huy_tem_kanban`; sửa `duc_recompute_tt_ca`); trang mới `ghi-nhan-kanban.html`; `intem.html` tab "Chỉ thị SX (Kanban)" + in gộp N tem; `duc-dashboard.html` nút tắt + badge tiến độ; `mobile.html` nút tắt; `quan-ly-danh-muc.html` SL đóng gói chuẩn + cờ máy Kanban; `shared/navbar.js` menu.

## Nhóm 3 — Nền tảng vận hành & truy xuất hiện trường

- [x] **Chuẩn hoá đơn vị truy xuất và nhãn QR** (2026-08-15) — đóng cả 3 khoảng trống trong chuỗi lệnh SX → ca/máy/khuôn → lot NVL → sọt/pallet → công đoạn → thành phẩm: (1) `duc_tem_nvl_lot` liên kết nhiều-nhiều tem đúc ↔ lot NVL (`nvl_tem`), chọn thủ công vì 2 lò nung tập trung dùng chung nhiều lot ingot trước khi ra máy — sửa `intem.html` (chip chọn lot ở cả tab In Tem và Tra cứu). (2) Pallet đóng gói ở OQC: `oqc_pallet`/`oqc_pallet_item` + RPC `oqc_tao_pallet`/`oqc_them_tem_vao_pallet`/`oqc_dong_pallet`, màn hình mới `oqc.html` (quét tem → gom pallet → đóng gói & nhập kho → in nhãn pallet), thêm vào `index.html`. Migration: `supabase/migration_phase_T1_qr_lot_pallet.sql`.
- [x] **Quy trình tách/gộp và điều chỉnh số lượng WIP** (2026-08-15) — phần tách (gộp chưa làm, để sau nếu phát sinh nhu cầu thật): bảng `duc_tem_tach` + RPC `duc_tach_tem` sinh tag_no con (hậu tố `-A/-B/...`), lưu số lượng tách/lý do/người thao tác, tag_no cha giữ lại phần còn lại. Dùng ở 2 nơi: `intem.html` tab Tra cứu (nút "Tách tem" thủ công, in tem con luôn) và `chuyencongdoan.html` (khi số lượng thực chuyển < số lượng trên tem, checkbox "phần còn lại vẫn ở công đoạn cũ" — khác với hao hụt/mất hẳn đã có sẵn). Cùng migration `migration_phase_T1_qr_lot_pallet.sql`.
- [ ] **Quản lý vị trí và tuổi tồn WIP** — chuẩn hoá mã khu vực chờ sau đúc, bavia, CNC, tiền xử lý, chờ sơn, OQC và kho thành phẩm. Thiết lập FIFO/FEFO, mức WIP tối thiểu/tối đa và cảnh báo lô chờ quá lâu; đặc biệt cho hàng chờ sơn và hàng đã kiểm nhưng chưa đóng gói.
- [x] **Routing theo mã sản phẩm** (2026-08-16, một phần — chưa có BOM/phiên bản) — `master_products.quy_trinh_cong_doan` (text list thứ tự công đoạn), `chuyencongdoan.html` tự khoá "Công đoạn nhận" theo đúng bước kế tiếp nếu SP đã khai báo. Cùng đợt: đóng gói lại tạo tem mới theo quy cách công đoạn (`cd_dong_goi_lai`/`cd_tem_nguon`, giữ truy xuất xuyên suốt), cảnh báo FIFO mềm, báo cáo NG cuối ca ngoài Đúc (`cd_bao_cao_ca`, trang `cong-doan-bao-cao-ca.html`). Migration `migration_phase_T2_dong_goi_routing.sql`. **CHƯA làm**: BOM (định mức vật liệu/thành phần), phiên bản/ngày hiệu lực quy trình, nhánh insert/mạ/rửa/leak test/lắp ráp.
  - **Bổ sung 2026-08-23** — giảm thao tác thủ công + hoàn thiện dữ liệu người thao tác ở `chuyencongdoan.html`: "Công đoạn giao" tự chọn theo vị trí hiện tại của tem (`cd_v_vi_tri_hien_tai`, mặc định "Đúc" nếu tem chưa từng chuyển); thêm lựa chọn "Lọc hàng" ở "Công đoạn nhận" cho trường hợp nghi ngờ hàng NG cần tách đi kiểm/lọc lại (chỉ là lựa chọn thêm ở màn hình này, không đưa vào `CONG_DOAN_LIST` dùng chung toàn hệ thống); "Người giao" chọn từ danh sách tài khoản hệ thống thật (hàm mới `danh_sach_nguoi_dung_he_thong()`, SECURITY DEFINER — vượt qua RLS "chỉ đọc được dòng của chính mình" của `user_roles`) thay vì danh mục nhân viên tự do; "Người nhận" khoá cứng = tài khoản đang đăng nhập; thêm cột "Ghi chú" (`cd_chuyen_cong_doan_log.ghi_chu`, tham số `p_ghi_chu` cho `cd_ghi_chuyen_cong_doan`) hiển thị lại ở danh sách phiếu chờ xác nhận và ở lịch sử truy xuất (`truy-xuat-nguon-goc.html`); đổi tên tab "Xác nhận nhận hàng" → "Xác nhận đã giao hàng" (đúng bản chất: bên giao xác nhận đã bàn giao, không phải bên nhận). Migration `migration_phase_T22_chuyencongdoan_nguoi_dung_ghi_chu.sql`.
- [ ] **Kỷ luật dữ liệu hiện trường** — xác định rõ dữ liệu nào công nhân, trưởng ca, QC, kho và kế hoạch chịu trách nhiệm; xây hướng dẫn thao tác 1 trang tại từng điểm quét/ghi. Mỗi biểu mẫu chỉ giữ trường thực sự cần để không làm chậm sản xuất; định kỳ kiểm tra tỷ lệ quét đúng, chậm quét và giao dịch phải sửa.

## Nhóm 4 — Chất lượng xuyên công đoạn

- [ ] **Kế hoạch kiểm soát chất lượng (Control Plan) điện tử** — chuẩn hoá điểm kiểm, tần suất, tiêu chuẩn, phương pháp đo, mẫu OK/NG, người chịu trách nhiệm và hành động phản ứng cho từng mã/nhóm SP. Tối thiểu gồm: NVL đầu vào; đúc đầu ca/sau đổi khuôn/2 giờ một lần; bavia; CNC first-off theo jig/dưỡng; trước/sau sơn; OQC trước đóng gói.
- [ ] **Khoanh vùng NG theo lần kiểm đạt gần nhất** — khi IQC/IPQC/OQC phát hiện lỗi, MES phải xác định được phạm vi nghi ngờ theo máy, khuôn, ca, lot và thời điểm kiểm OK gần nhất; liệt kê các sọt/pallet đang ở WIP, đã chuyển công đoạn hoặc đã nhập kho để cách ly. Đây là ưu tiên nghiệp vụ cao cho khối đúc.
- [ ] **Luồng xử lý NG và tái kiểm thống nhất** — tách rõ: cách ly, phân loại, sửa hàng, tái kiểm, hủy, phế liệu/hồi liệu và đóng NCP. Các công đoạn sau (bavia/CNC/sơn/OQC) cần trả lỗi về đúng công đoạn nguồn thay vì chỉ ghi một tỷ lệ NG tổng.
- [ ] **Theo dõi FPY và chi phí chất lượng** — đo First Pass Yield theo công đoạn/máy/mã SP/ca; ghi nhận số lượng rework, scrap, thời gian sửa và nguyên nhân. Trọng tâm ban đầu: NG đúc/shot nóng khuôn, NG sơn khoảng 10%, lỗi ngoại quan tại bavia và NG CNC.
- [ ] **Phòng đo & quản lý dụng cụ đo** — lập danh mục thiết bị đo/dưỡng (CMM, OMM, CT/X-Ray, độ cứng, phân tích thành phần, salt spray, thước/dưỡng/jig); theo dõi hạn hiệu chuẩn, trạng thái sử dụng, tiêu chuẩn áp dụng và kết quả đo gắn với lot. Cần xác định kiểm tra nào là công đoạn, xác nhận lô, định kỳ hay thử nghiệm sản phẩm mới.

## Nhóm 5 — Đúc, khuôn, vật liệu và năng lượng

- [x] **Sổ đời khuôn đúc** (2026-08-15) — thêm lịch sử từng lần Bảo dưỡng định kỳ/Sửa chữa/Thay khuôn mới (bảng `duc_khuon_bao_duong_log`: ngày, shot tại thời điểm, người thực hiện, mô tả, chi phí, thời gian dừng máy, liên kết vấn đề khuôn), lịch bảo dưỡng THEO THỜI GIAN (`duc_shot_khuon.chu_ky_bao_duong_ngay`, hạn tiếp theo hiện trong modal bảo dưỡng + bảng quản lý khuôn), RPC `duc_ghi_lich_su_bao_duong` (chỉ Bảo dưỡng định kỳ/Thay mới mới reset đồng hồ đếm shot). Migration `migration_phase_D15_so_doi_khuon.sql`, sửa `duc-dashboard.html`. **Khuôn dập gate CHƯA làm** — hiện `duc_shot_khuon` chỉ có khuôn đúc, cần khảo sát thêm nếu muốn quản lý riêng khuôn dập gate.
- [ ] **Cân bằng khối lượng nhôm/kẽm** — theo dõi vật liệu từ nhập kho → cấp lò tập trung → cấp máy → sản lượng OK → đầu ngót/runner hồi liệu → phế phẩm → tồn lò/chênh lệch. Chỉ sau khi quy trình cân và đơn vị tính được chuẩn hoá mới xem xét tự động trừ tồn theo sản lượng.
- [ ] **Quản lý cấp liệu/lò và tiêu hao năng lượng** — với 2 lò tập trung 800 kg/h và 1.000 kg/h, cần ghi kế hoạch cấp liệu, công suất thực, thời gian nung/chờ, tồn kim loại lỏng và tiêu hao điện/gas theo ca. Dữ liệu này giúp nhận biết nút thắt cấp nhôm lỏng và đánh giá chi phí đúc.
- [ ] **Theo dõi hiệu suất sơn và hao hụt không thu hồi** — ghi loại sơn (nước/bột), lot sơn, lượng cấp, lượng sử dụng, lượng bám ước tính, lượng hao hụt, điều kiện sấy và thời gian masking. Đây là dữ liệu nền để cải tiến tỷ lệ NG sơn và chi phí vật tư, không nên suy ra chỉ từ sản lượng thành phẩm.

## Nhóm 6 — Năng lực, bảo trì và luồng mở rộng

- [ ] **Năng lực và nút thắt theo công đoạn** — xây công suất chuẩn theo máy/ca/người cho 10 máy đúc nhôm, 2 máy đúc kẽm, phun bi/mài, CNC, sơn và OQC; so sánh kế hoạch với năng lực thực tế. Cần theo dõi riêng nguồn lực masking, OQC và các máy CNC/jig đặc thù vì dễ thành điểm nghẽn.
- [ ] **Bảo trì thiết bị ngoài khuôn** — lập lịch bảo trì phòng ngừa cho lò, robot, máy đúc, máy dập gate, phun bi, máy mài, CNC, dây chuyền sơn và thiết bị đo. Liên kết downtime với nguyên nhân, lệnh bảo trì, vật tư thay thế và ảnh hưởng sản lượng.
- [ ] **Quản lý gia công ngoài** — với mạ/in, quản lý phiếu giao nhận theo lot: nhà cung cấp, số lượng giao/nhận, hao hụt, hạn trả, kết quả QC và biên bản bất thường. Hàng thuê ngoài vẫn phải truy được về ca đúc/lot NVL ban đầu.
- [ ] **Sẵn sàng cho sản phẩm mới** — tạo quy trình NPI trước khi báo giá/sản xuất: routing, BOM, dụng cụ/jig, tiêu chuẩn đo, Control Plan, năng lực, rủi ro và phê duyệt thử nghiệm. Cần hỗ trợ sớm các công đoạn rửa, leak test và lắp ráp để không phải sửa cấu trúc dữ liệu khi sản phẩm mới vào sản xuất.
- [ ] **Họp cải tiến hằng ngày dựa trên dữ liệu** — chuẩn hoá bảng họp 10–15 phút theo ca/ngày: an toàn, kế hoạch–thực tế, chất lượng, downtime, WIP bất thường, hành động khắc phục và người/hạn hoàn thành. MES cung cấp dữ liệu; trưởng bộ phận chịu trách nhiệm chốt hành động và theo dõi đến khi đóng.

## Thứ tự ưu tiên nghiệp vụ đề xuất

1. Chuẩn QR/lot/pallet, quy trình tách-gộp và vị trí WIP.
2. Control Plan điện tử, khoanh vùng NG và luồng cách ly–tái kiểm.
3. Routing/BOM, sổ đời khuôn (bao gồm khuôn dập gate) và cân bằng vật liệu đúc.
4. FPY/OEE, năng lực–nút thắt, bảo trì thiết bị và dashboard cải tiến hằng ngày.
5. Phòng đo, gia công ngoài và luồng NPI cho rửa/leak test/lắp ráp.

## Roadmap tóm tắt tính năng cần thiết để hoàn thiện MES

### Giai đoạn 1 — Nền tảng dữ liệu và truy xuất
- [ ] **Chuẩn hoá master data** — sản phẩm, máy, nhân sự, khuôn, vật liệu và quy tắc mã dùng chung cho toàn hệ thống.
- [x] **QR / lot / pallet / tag** (2026-08-15) — xem chi tiết ở Nhóm 3 phía trên.
- [ ] **Truy xuất ngược-xuôi** — tra cứu từ thành phẩm về nguyên liệu, từ lot gốc về ca/máy/khuôn/công đoạn.
- [ ] **Quản lý WIP** — theo dõi trạng thái, vị trí, tuổi tồn và mức cảnh báo hàng chờ quá lâu.
- [ ] **Tách/gộp/điều chỉnh WIP** — lưu lịch sử thay đổi số lượng, lý do, người thao tác và thời điểm xử lý.

### Giai đoạn 2 — Kiểm soát chất lượng xuyên công đoạn
- [ ] **Control Plan điện tử** — định nghĩa từng điểm kiểm, tần suất, tiêu chuẩn, phương pháp đo và người chịu trách nhiệm.
- [ ] **NCP / xử lý NG thống nhất** — cách ly, sửa, tái kiểm, phế liệu, hủy, báo cáo nguyên nhân và đối sách.
- [ ] **Khoanh vùng NG** — xác định phạm vi khả nghi theo máy, ca, khuôn, lot và công đoạn gần nhất.
- [ ] **FPY & chi phí chất lượng** — đo First Pass Yield, rework, scrap, thời gian sửa và nguyên nhân gây lỗi.
- [ ] **IPQC/OQC tích hợp** — kiểm tra theo mốc thời gian và sau sự cố, gắn với nơi sản xuất đang chạy.

### Giai đoạn 3 — Routing, BOM và sản phẩm mới
- [ ] **BOM theo mã SP** — định nghĩa vật liệu, định mức, thành phần và phiên bản quy trình cho từng sản phẩm.
- [ ] **Routing theo công đoạn** — đúc → bavia → CNC → sơn → OQC, cộng thêm nhánh mạ, rửa, leak test, lắp ráp.
- [ ] **Quy trình NPI / sản phẩm mới** — chuẩn hóa thử nghiệm, dung cụ, tiêu chuẩn đo, năng lực và phê duyệt trước khi sản xuất hàng loạt.
- [ ] **Phiên bản quy trình** — cho phép thay đổi routing/BOM mà không làm mất lịch sử dữ liệu cũ.

### Giai đoạn 4 — Khuôn, máy, bảo trì và hiệu suất
- [ ] **Sổ đời khuôn** — số shot, shot nóng, lịch bảo dưỡng, sửa chữa, thay mới và chi phí liên quan.
- [ ] **Bảo trì máy và thiết bị** — lò, robot, máy đúc, máy dập gate, CNC, sơn, thiết bị đo, máy phun bi, máy mài.
- [ ] **Downtime & nguyên nhân** — phân tích dừng máy theo thời gian, công đoạn, máy và đầu máy gây lỗi.
- [ ] **OEE / năng lực / nút thắt** — giám sát hiệu suất, tiến độ, năng lực thực tế và khu vực nghẽn của dây chuyền.

### Giai đoạn 5 — Vật liệu, năng lượng và tối ưu hóa sản xuất
- [ ] **Quản lý vật liệu từ nhập kho đến sản lượng** — cấp liệu, tồn kho, chênh lệch, hao hụt và hồi liệu.
- [ ] **Cân bằng khối lượng nhôm/kẽm** — theo dõi cấp liệu lò, khối lượng thực tế, đầu ngót, phế liệu và tồn lò.
- [ ] **Quản lý năng lượng / tiêu hao** — theo dõi tiêu hao điện/gas, thời gian nung, sử dụng lò và chỉ số chi phí theo ca.
- [ ] **Tối ưu hóa sơn và hao hụt** — lượng sơn cấp, lượng bám, lượng hao hụt không thu hồi, điều kiện sấy và masking.

### Giai đoạn 6 — Điều hành và cải tiến liên tục
- [ ] **Dashboard điều hành** — sản lượng, NG, WIP, OEE, năng lực, downtime, KPI ngày/tuần/tháng.
- [ ] **Cảnh báo chủ động** — quá hạn IPQC, máy dừng, lô tồn quá lâu, NG tăng bất thường, khuôn sắp bảo dưỡng.
- [ ] **Báo cáo Pareto và cải tiến hằng ngày** — xác định nguyên nhân chính, nhóm lỗi, vùng nguy hiểm và hành động khắc phục.
- [ ] **Họp cải tiến dựa trên dữ liệu** — xuất báo cáo cho trưởng bộ phận, theo dõi hành động và thời hạn đóng.

### Giai đoạn 7 — Mở rộng và nâng cấp lâu dài
- [ ] **Gia công ngoài / mạ / rửa / leak test / lắp ráp** — quản lý nhà cung cấp, lot, chất lượng nhập/xuất và hàng thuê ngoài.
- [ ] **Phòng đo & dụng cụ đo** — hiệu chuẩn, trạng thái dụng cụ, lịch hiệu chuẩn và kết quả đo gắn với lot.
- [ ] **Quy trình quản lý tài khoản & audit log** — ghi rõ ai sửa gì lúc nào, phân quyền theo vai trò và kiểm soát vận hành.
- [ ] **Giám sát job nền / cron / automation** — hệ thống tự động quét và cảnh báo lỗi trong job nền, không để mất dữ liệu hoặc job chết âm thầm.

## Cách làm việc tiếp

Mỗi khi bắt đầu 1 mục, đổi `[ ]` thành `[x]` kèm ngày hoàn thành + link file/thay đổi liên quan, theo đúng phong cách ghi chép đã dùng trong `KE_HOACH_MIGRATE_DATABASE.md`. Ưu tiên do người dùng chọn tại thời điểm bắt đầu mỗi mục, không tự ý làm trước.
