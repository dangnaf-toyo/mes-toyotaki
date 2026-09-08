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
