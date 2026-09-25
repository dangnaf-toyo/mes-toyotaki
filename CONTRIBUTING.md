# Quy trình làm việc nhóm — mes-toyotaki

## Môi trường

| | Production | Staging |
|---|---|---|
| URL | `https://dangnaf-toyo.github.io/mes-toyotaki/` | Cloudflare Pages (branch `staging`) |
| Nhánh Git | `master` | `staging` |
| Supabase project | `fgghikpzcxjqzahfiiil` | project staging riêng (xem `shared/supabase-client.js`) |
| Ai được deploy | **Chỉ chủ repo** (merge PR vào `master`) | Mọi dev (merge PR vào `staging`) |

`shared/supabase-client.js` tự chọn URL/anon key theo `location.hostname` — hostname đúng domain GitHub Pages production thì dùng DB production, mọi hostname khác (staging, localhost, mở file trực tiếp) đều dùng DB staging. Không cần đổi code khi merge giữa 2 nhánh.

## Quy trình

1. Tạo nhánh từ `staging`: `git checkout -b feature/ten-tinh-nang staging`.
2. Code + nếu có migration SQL mới (`supabase/migration_phase_...sql`), tự chạy migration đó trên **Supabase project staging** (không phải production) để test.
3. Mở PR vào `staging`. Test trên URL staging (Cloudflare Pages tự deploy khi PR merge).
4. Khi chủ repo duyệt xong trên staging, chủ repo mở PR `staging` → `master` và tự merge (nhánh `master` chỉ chủ repo mới có quyền push/merge).
5. Sau khi merge vào `master`, chủ repo tự chạy lại đúng migration SQL đó trên **Supabase project production**. Migration không tự động chạy theo code — luôn phải chạy tay, đúng thứ tự file.

## Quy ước đã chốt (đọc trước khi sửa code)

- Người thao tác hiện tại: luôn dùng `MesAuth.getCurrentUserIdentity()` (trả về `MãNV_TênNV`), không dùng `session.user.email` để hiển thị/ghi log — email chỉ dùng cho xác thực thật (đổi mật khẩu...).
- Thời gian hiển thị: mọi `toLocaleTimeString`/`toLocaleString` dùng `hour12:false` (24h, không AM/PM).
- Giao diện: theo pattern header/token của `duc-dashboard.html` — không tự chế header riêng cho trang mới.
- Icon tiêu đề trang lấy từ `PAGE_META` trong `shared/navbar.js`, không nhét icon vào chuỗi truyền cho `MesNav.setTitle()`.
- File migration đặt tên tuần tự `migration_phase_<nhóm><số>_<mô_tả>.sql` (nhóm: D=Đúc, S=hệ thống, T=chung). Trước khi đặt số kế tiếp, kiểm tra không ai khác đang dùng số đó trên nhánh `staging` cùng lúc.
- Tên bảng/cột mới đặt **tiếng Việt không dấu, snake_case** theo đúng các bảng đã có (`ma_sp`, `ma_may`, `ngay`, `ca`, `so_luong`, `nguoi_tao`...), tiền tố theo khối (`duc_`, `cd_`, `oqc_`, `iqc_`...). Không đặt tên tiếng Anh (`product_code`, `inspection_date`, `shift`...). Các bảng tiếng Anh đã có trước 25/09/2026 (`iqc_lots`, `oqc_daily_inspection`, `duc_ipqc_continue_*`, `bom_*`, `quality_defect_catalog`) giữ nguyên, không đổi tên.
- Ca làm việc chỉ dùng các giá trị đang có trong hệ thống: `Ca ngày`/`Ca đêm` (2 ca 12h) hoặc `Ca 1`/`Ca 2` (2 ca 8h). Không tự thêm ca khác.
- Không để migration trong `supabase/migrations/` hay đặt tên theo ngày giờ — luôn dùng `supabase/migration_phase_...sql` như trên.
- **Bảo mật hàm SQL:** mọi hàm `security definer` phải có ngay trong cùng file: `revoke execute on function ... from public, anon;` + `grant execute ... to authenticated;` (Postgres mặc định cho PUBLIC gọi, tức là gọi được khi chưa đăng nhập qua `/rest/v1/rpc/...`). Hàm ghi dữ liệu phải kiểm tra `auth.uid() is not null`; thao tác duyệt/xoá/sửa danh mục phải kiểm tra vai trò bằng `public.has_role('admin', ...)`. Tên người thao tác ghi vào log lấy từ `user_roles` theo `auth.uid()`, không tin tên do trình duyệt gửi lên.
- RLS: không cấp `delete` cho mọi tài khoản đăng nhập — chỉ vai trò quản lý (VD `has_role('admin','qc_manager')`).
- Không tạo bản song song kiểu `trang-v2.html` — sửa thẳng vào trang gốc (cần giữ link cũ thì để file cũ chỉ chuyển hướng).
- Giao diện (chi tiết của dòng "Giao diện" ở trên): font Inter + JetBrains Mono (Google Fonts), `html,body{font-size:13px}`, bảng màu dùng biến `:root` (`--bg-page`, `--bg-header`, `--accent`, `--border`, `--text-muted`, `--run-fg`, `--warn-fg`, `--alarm-fg`...), header tối gồm `.brand` (dòng "Toyotaki" + tên trang) + nút điều hướng `.btn-ghost` + đồng hồ `.header-clock` bên phải, trang **tràn hết chiều ngang** (không `max-width` cho khung chính), và thêm `noTitleBar: true` cho trang đó trong `PAGE_META`. Mẫu tham khảo: `duc-dashboard.html`, `bao-cao-ca.html`.
