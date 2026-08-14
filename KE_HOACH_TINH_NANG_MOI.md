# Kế hoạch tính năng tiếp theo — MES Toyotaki (sau khi hoàn tất chuyển Supabase)

> Tài liệu này tiếp nối `KE_HOACH_MIGRATE_DATABASE.md` (đã hoàn tất việc chuyển toàn bộ 6 module từ Google Apps Script sang Supabase). Từ đây, `KE_HOACH_MIGRATE_DATABASE.md` giữ vai trò lịch sử/tham khảo; **file này là danh sách việc cần làm tiếp** để hệ thống thực sự "quản lý" được, không chỉ nhập liệu.
>
> Nguồn gốc: đề xuất theo yêu cầu người dùng ngày 2026-08-14, dựa trên hiểu biết về 6 module hiện có (Sản lượng, Chất lượng, Chuyển công đoạn, Đúc+IPQC+In tem+QC Manager+NCP+Mobile, Kế hoạch tuần, Tồn kho NVL). Làm dần theo mức ưu tiên người dùng chọn — CHƯA có mục nào bắt đầu code, đây là backlog.

## Nhóm 1 — Quản lý hệ thống

- [x] **Quản lý tài khoản & phân quyền** (2026-08-14) — đã code xong (a) và (b): bảng `public.user_roles` + hàm `has_role()`/`current_role_of()` (`supabase/migration_phase_S1_accounts_roles.sql`), Edge Function `admin-create-user` tạo tài khoản Auth mới bằng service_role (`supabase/functions/admin-create-user/index.ts`), trang admin `quan-ly-tai-khoan.html` (chỉ role admin vào được, tạo tài khoản + đổi vai trò). **Chưa triển khai** — cần chạy SQL migration, deploy Edge Function bằng Supabase CLI, và bootstrap admin đầu tiên (xem hướng dẫn cuối file SQL). (c) RLS của các bảng nghiệp vụ khác (sản lượng/chất lượng/Đúc...) CHƯA đổi sang kiểm tra `has_role()` cụ thể — vẫn đang chỉ kiểm tra đăng nhập — làm dần khi có thời gian, để tránh khoá ghi hàng loạt cùng lúc.
- [ ] **Nhật ký thao tác (audit log)** — nhiều bảng đã có cột người/giờ cập nhật (`nguoi_cap_nhat`, `last_updated_at`, `nguoi_tt`...) nhưng rải rác, chưa có 1 màn hình tổng hợp "ai sửa gì lúc nào" xuyên suốt các module. Cần quyết định: bảng audit log riêng (ghi qua trigger) hay tổng hợp truy vấn từ các bảng nghiệp vụ hiện có.
- [ ] **Giám sát job nền (`pg_cron`)** — các job định kỳ (poll Diecast, quét sinh checkpoint IPQC) chạy âm thầm trong Postgres, lỗi sẽ không ai biết trừ khi tự vào Supabase Dashboard → Database → Cron Jobs kiểm tra. Cần 1 màn hình admin hiện trạng thái lần chạy gần nhất/lỗi gần nhất.
- [ ] **Quản lý danh mục tập trung** — máy/SP/nhân sự/khuôn (khối Đúc) hiện chỉ sửa được qua Supabase Dashboard trực tiếp (SQL). NVL (`nvl_materials`) và KHSX tuần đã có UI riêng rồi — nên làm tương tự cho `master_machines`/`master_products`/`master_employees`/`duc_shot_khuon`, gộp chung vào 1 trang "Quản lý danh mục" nếu hợp lý.

## Nhóm 2 — Quản lý sản xuất thực tế

- [ ] **Dashboard tổng hợp/xu hướng** — OEE, sản lượng, NG hiện chỉ tính/hiện theo từng ca (bảng `duc_bao_cao_ca`/`duc_lich_su_san_xuat` đã có dữ liệu lịch sử). Cần màn hình xem xu hướng theo ngày/tuần/tháng, so sánh máy với máy, so sánh SP với SP — dữ liệu nguồn đã sẵn có, chỉ thiếu giao diện tổng hợp.
- [ ] **Phân tích sự cố (Pareto)** — đã phân loại sự cố A1-F1 (`CONFIG.LOAI_SU_CO`) và có `DOWNTIME_COST_PER_MIN` tính chi phí dừng máy, nhưng chưa có báo cáo tổng hợp "loại sự cố nào chiếm nhiều thời gian/chi phí nhất" theo tuần/tháng/máy.
- [ ] **Cảnh báo chủ động (ngoài màn hình)** — sự cố mở quá lâu, IPQC quá hạn, khuôn sắp tới ngưỡng bảo dưỡng hiện chỉ hiện khi có người đang nhìn dashboard. Cần kênh thông báo đẩy (email qua Supabase, hoặc webhook sang Zalo/Telegram) khi vượt ngưỡng — cần quyết định kênh trước khi làm.
- [ ] **Bảo trì khuôn theo lịch** — hiện chỉ cảnh báo theo số shot lũy kế (ngưỡng bảo dưỡng/thay mới), chưa có lịch bảo dưỡng định kỳ theo thời gian/nhắc hẹn trước.
- [ ] **Liên kết tồn kho NVL ↔ kế hoạch sản xuất** — 2 hệ (`nvl_*` và `duc_*`) hiện độc lập hoàn toàn, chưa tự trừ tồn NVL theo sản lượng thực tế đúc ra (cần định mức NVL/sản phẩm — dữ liệu này chưa có ở đâu cả, phải khảo sát thêm nếu làm).

## Cách làm việc tiếp

Mỗi khi bắt đầu 1 mục, đổi `[ ]` thành `[x]` kèm ngày hoàn thành + link file/thay đổi liên quan, theo đúng phong cách ghi chép đã dùng trong `KE_HOACH_MIGRATE_DATABASE.md`. Ưu tiên do người dùng chọn tại thời điểm bắt đầu mỗi mục, không tự ý làm trước.
