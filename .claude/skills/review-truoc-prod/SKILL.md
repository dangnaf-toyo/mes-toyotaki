---
name: review-truoc-prod
description: Rà soát code (nhất là phần đồng đội làm) TRƯỚC khi đưa từ staging lên production (master + DB prod) — kiểm tra tĩnh, chụp giao diện, duyệt migration, lập danh sách điểm chưa hợp lý kèm đề xuất, rồi DỪNG chờ user quyết. Dùng khi user gõ "/review-truoc-prod", yêu cầu "đẩy/đưa ... lên prod / production / master", "push phần đồng đội lên pro", hoặc trước MỌI lần cherry-pick commit không phải do Claude viết sang master.
---

# Review trước khi lên prod (mes-toyotaki)

Quy định của user (23/10/2026): **trước khi đưa phần đồng đội làm lên prod, phải kiểm tra code và đề xuất các điểm chưa hợp lý trước** — không tự đẩy thẳng. Áp dụng cả khi user chỉ nói "đẩy tính năng X lên prod".

## 0. Xác định phạm vi

```bash
git fetch -q origin
git log --oneline --no-merges origin/master..origin/staging          # commit staging chưa lên master
git log --format='%h %an %s' --no-merges origin/master..origin/staging | grep -v 'Claude'   # phần đồng đội
git diff --stat origin/master origin/staging -- <các file của tính năng>
```

- Commit của đồng đội = commit không có dòng `Co-Authored-By: Claude`. Chỉ lấy những commit thuộc tính năng user yêu cầu; liệt kê rõ commit nào sẽ đi, commit nào ở lại staging.
- File khác nhau sẵn giữa 2 nhánh (shared/navbar.js — staging có BOM/embed) phải vá riêng trên master, không cherry-pick nguyên file.
- Số T/D của đồng đội có thể trùng số của mình (từng xảy ra: T118, T120, T122) — kiểm `ls supabase | grep migration_phase_T1` trước khi đặt số mới.

## 1. Kiểm tra tĩnh (script)

```bash
node scripts/code-review-check.cjs origin/master..origin/staging          # hoặc --files a.html shared/b.js supabase/x.sql
```
Mức **[CAO]** phải xử lý trước khi lên prod. **[TB]** đưa vào đề xuất. **[THẤP]** chỉ nêu nếu nhiều. Script chỉ là lưới thô — vẫn phải đọc diff.

## 2. Đọc diff bằng mắt — danh mục kiểm

**Đúng nghiệp vụ / so với master chuẩn**
- Có làm hỏng luồng sẵn có không (Đúc, tem, kết ca, IPQC, sự cố)? Trigger mới trên bảng nóng (duc_ca_hien_tai, duc_tem, duc_ipqc_checkpoint) có chặn thao tác cũ không?
- Đọc/ghi đúng bảng, đúng cột? Có giả định dữ liệu prod khác staging (staging ít dữ liệu, prod có hàng nghìn dòng)?
- Trang mới có trong navbar (PAGE_META, menu) và đã phân quyền vai trò chưa?

**Bảo mật / dữ liệu (SQL)**
- Hàm `security definer`: kiểm `auth.uid()`, `has_role(...)` đúng vai trò, `revoke ... from public, anon`, `grant execute ... to authenticated`, `set search_path = public`.
- Tên người thao tác lấy từ `user_roles` theo `auth.uid()`, KHÔNG tin tham số client (`p_nguoi`, `p_actor`).
- Bảng mới: bật RLS; ghi chỉ qua RPC nếu là dữ liệu cần lịch sử. `duc_tem` chỉ ghi qua RPC (T109).
- Không `drop table`/`truncate`/`delete` dữ liệu nghiệp vụ; sửa trạng thái thay vì xoá; có log + cách hoàn tác.
- Migration chạy lại được (`if not exists`, `create or replace`, `drop policy if exists`); đầu file ghi đúng trạng thái (không còn "STAGING ONLY" khi lên prod).

**Giao diện / UX** (quy ước CONTRIBUTING.md + sở thích user)
- Chữ ≥ 11px, nút ≥ 32px (chạm được trên điện thoại), không tràn ngang ở 390px.
- Một dải header chuẩn của navbar; tab của trang đặt trong header tối, không thêm dải tab dưới menu.
- Không dùng pop-up/modal cho màn hình xem dữ liệu lớn — dùng trang/tab riêng.
- Ít chữ, ít màu; bảng dài phải có lọc + chia trang.
- Lỗi hiện câu dễ hiểu, chi tiết kỹ thuật thu vào `<details>`; không hiện mã 42501, tên migration, chữ "staging".
- Thời lượng dạng "x ngày y giờ", ngày dd/mm/yyyy.
- File shared đã đổi phải tăng `?v=` ở mọi trang nạp nó.

**Code dễ bảo trì**
- Không code nén một dòng dài (prettier 120 cột), không trùng lặp hàm đã có trong shared/.
- `node --check` mọi file JS, script inline HTML.

## 3. Chụp giao diện bằng phiên đăng nhập giả

```bash
MES_PLAYWRIGHT="<thư mục node_modules/playwright>" MES_CHROME="<chrome.exe>" \
  node scripts/ui-review.cjs --out "<scratchpad>/ui" trang1.html "trang2.html?id=..."
```
(Trên máy user: Playwright ở `C:/Users/DELL/AppData/Local/Temp/claude/D--Project-MES-mes-toyotaki/1da0d7a4-f326-4360-a9b3-f9b6ca1991de/scratchpad/pw/node_modules/playwright`, Chrome `C:/Users/DELL/AppData/Local/ms-playwright/chromium-1243/chrome-win64/chrome.exe`; nếu mất thì `npm i playwright` vào scratchpad.)
Xem ảnh `_d` (1366) và `_m` (390): lỗi JS, tràn ngang, trang dài bất thường, chữ/nút nhỏ. Lỗi quyền RPC trong phiên giả là bình thường.

## 4. Báo cáo cho user — rồi DỪNG

Trả lời ngắn bằng tiếng Việt, gồm:
1. **Phạm vi**: commit/tính năng sẽ lên prod, migration nào sẽ chạy trên DB prod.
2. **Bảng điểm chưa hợp lý**, xếp theo mức: `Mức | Trang/file | Vấn đề | Đề xuất sửa`. CAO = sai dữ liệu / lỗ quyền / làm hỏng luồng cũ; TB = UX kém, thiếu quy ước; THẤP = thẩm mỹ.
3. **Kết luận**: "Lên được ngay" / "Nên sửa N điểm CAO trước" / "Chưa nên lên".
4. Hỏi user chọn: (a) sửa hết rồi lên, (b) chỉ sửa mức CAO rồi lên, (c) lên nguyên trạng, (d) chưa lên.

Nếu danh sách dài (> ~10 điểm) hoặc user sẽ chuyển cho đồng đội, đăng thành Artifact và gửi link.

**KHÔNG** cherry-pick sang master, **KHÔNG** chạy migration prod cho đến khi user trả lời. Ngoại lệ: user đã nói rõ trong cùng yêu cầu "kiểm tra xong không có gì nghiêm trọng thì đẩy luôn" → chỉ được đẩy khi không có mức CAO, và vẫn báo danh sách.

## 5. Sau khi user duyệt

- Sửa trên staging (commit riêng, ghi rõ "sửa theo review"), push staging.
- Migration: staging trước → kiểm thử nhanh bằng DO-block giả lập vai trò (`set_config('request.jwt.claims', ...)`, kết thúc bằng `raise exception` để rollback) → prod.
- Cherry-pick sang master qua worktree tạm ở scratchpad; vá navbar riêng nếu cần; `git push origin <nhánh>:master` (đi thẳng, bỏ qua quy định PR — luôn nói với user).
- Chờ GitHub Pages build (8–15 phút) rồi mở trang prod kiểm lại.
- Gửi đồng đội (qua user) danh sách điểm đã sửa để họ lấy bản mới trước khi làm tiếp — tránh đè code đã định dạng lại.
