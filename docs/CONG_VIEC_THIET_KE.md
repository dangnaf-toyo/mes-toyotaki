# Module Quản lý công việc — thiết kế đã chốt (T161)

Chốt ngày 24/10/2026. Bản phác thảo giao diện: https://claude.ai/artifact/W2r8mEGqkByfMHSNECh32r
(8 màn hình — dùng làm chuẩn bố cục, màu sắc, chữ).

Phạm vi **giai đoạn 1** (đang làm): giao việc, chi tiết việc, bảng Kanban + ma trận ưu tiên,
bình luận / góp ý, chuông thông báo trong MES, phân quyền, việc của tôi.
**Giai đoạn 2** (sau): trang Dự án + góp ý dự án, Tổng quan Ban giám đốc, việc định kỳ tự sinh.
Lược đồ dữ liệu dưới đây đã gồm cả phần của giai đoạn 2 để không phải đổi bảng về sau.

Không dùng Zalo. Mọi thông báo nằm trong MES (bảng `cv_thong_bao`, chuông trên navbar).

## 1. Quy tắc nghiệp vụ

- Người dùng: Ban giám đốc, quản lý các cấp, nhân viên gián tiếp, trưởng ca. Tài khoản = `user_roles`.
- **Ban giám đốc** = role `admin` hoặc `giam_doc_sx`.
- Mỗi việc có **1 người làm chính** (`nguoi_lam`), nhiều **người phối hợp**, 1 **người giao** (= người tạo).
- Trạng thái: `moi` → `dang_lam` → `cho_duyet` → `hoan_thanh`; ngoài ra `huy`.
  - Người làm: nhận việc (`moi→dang_lam`), tick bước, báo hoàn thành, xin gia hạn.
  - Báo hoàn thành chỉ được khi **mọi bước checklist đã tick**. Nếu `can_duyet` → `cho_duyet`, không thì → `hoan_thanh` luôn.
  - Người giao (hoặc Ban giám đốc): duyệt (`cho_duyet→hoan_thanh`), trả lại (`cho_duyet→dang_lam`, **bắt buộc lý do**, `so_lan_tra_lai+1`), trả lời gia hạn, nhắc việc, mở lại (`hoan_thanh→dang_lam`), huỷ, sửa việc (kể cả mức ưu tiên).
  - Việc **Quan trọng** luôn `can_duyet = true` (ép ở RPC).
- **Ưu tiên** = 2 trục: `quan_trong` (bool) × `gap` (bool, người giao chọn).
  - `gap_hieu_luc` = `gap` HOẶC (chưa xong/huỷ VÀ còn ≤ 2 ngày đến `han`, kể cả đã quá hạn).
  - Nhóm: 1 Làm ngay = QT + gấp · 2 Lên kế hoạch = QT, chưa gấp · 3 Xử lý nhanh = gấp, ít QT · 4 Làm sau = còn lại.
  - Màu nhóm: 1 `#B91C1C`, 2 `#0F5FA5`, 3 `#B45309`, 4 `#64748B`. Nhãn luôn kèm chữ "1 · Làm ngay" (không chỉ màu).
- **Hạn**: `han_ban_dau` giữ nguyên mãi; `han` = hạn hiện tại (đổi khi gia hạn được duyệt hoặc người giao sửa).
  `dung_han` = `bao_xong_luc <= han` (ghi lúc chuyển hoan_thanh). `qua_han` = chưa xong/huỷ và `now() > han`.
- **Ai xem được**: `hien_thi = 'cong_khai'` → mọi tài khoản đăng nhập. `'han_che'` → người giao, người làm, người phối hợp, Ban giám đốc.
  Mọi người xem được đều **bình luận / góp ý** được, nhưng không đổi trạng thái/người/hạn/ưu tiên.
- Bình luận có loại: `binh_luan`, `gop_y`, `cau_hoi`, `de_xuat`, `cap_nhat`, `tra_lai` (tự sinh khi trả lại). Có "Đồng tình" (toggle, mỗi người 1 lần).
  `gop_y`/`de_xuat` có `trang_thai_gop_y` bắt đầu `dang_xem_xet`; người giao việc / chủ dự án xử lý: `da_tiep_thu` (có thể tạo việc mới), `da_tra_loi`, `khong_ap_dung`.
- Liên kết dữ liệu MES: `lien_ket jsonb` = mảng `{"loai": "ncp"|"su_co"|"khuon"|"may"|"ma_sp"|"phieu_thay_doi", "ma": "<mã hiển thị>"}`.
- Bộ phận: bảng `cv_bo_phan` (danh sách cố định có thể sửa bằng SQL).

## 2. Thông báo (`cv_thong_bao`) — ai nhận khi nào

| Sự kiện | `loai` | Người nhận (trừ chính người thao tác) | `can_xu_ly` |
|---|---|---|---|
| Giao việc mới | `giao_viec` | người làm, người phối hợp | true cho người làm |
| Nhận việc | `nhan_viec` | người giao | false |
| Báo hoàn thành (cần duyệt) | `cho_duyet` | người giao | true |
| Báo hoàn thành (không cần duyệt) / Duyệt | `hoan_thanh` | người giao hoặc người làm + phối hợp | false |
| Trả lại | `tra_lai` | người làm | true |
| Xin gia hạn | `xin_gia_han` | người giao | true |
| Trả lời gia hạn | `tra_loi_gia_han` | người làm | false |
| Nhắc việc | `nhac_viec` | người làm | true |
| Đổi ưu tiên / đổi người làm / đổi hạn | `cap_nhat_viec` | người làm (người làm mới + cũ khi đổi người) | false |
| Mở lại, huỷ | `mo_lai` / `huy_viec` | người làm | false |
| Bình luận / góp ý / câu hỏi | `binh_luan` / `gop_y` | người giao, người làm, người phối hợp (+ chủ dự án nếu là bình luận dự án) | false |
| Gắn tên @ | `nhac_ten` | người được gắn | false |
| Quá hạn (quét mỗi giờ, 1 lần / việc / mốc hạn) | `qua_han` | người làm + người giao | true |

Khi người nhận làm xong việc tương ứng (vd đã duyệt), các thông báo `can_xu_ly` cũ của **chính việc đó, chính người đó** được đánh `da_xu_ly = true` (để mục "Cần tôi xử lý" không còn).

## 3. Lược đồ (migration `supabase/migration_phase_T161_quan_ly_cong_viec.sql`)

```
cv_bo_phan(ten text pk, thu_tu int)
cv_du_an(id bigserial pk, ten text not null, mo_ta text, bo_phan text fk cv_bo_phan, chu_du_an uuid not null fk auth.users,
         ngay_bat_dau date, ngay_ket_thuc date, trang_thai text check (dang_chay|tam_dung|hoan_thanh|huy) default dang_chay,
         created_at, created_by uuid)
cv_cong_viec(id bigserial pk, tieu_de text not null, mo_ta text,
         nguoi_giao uuid not null, nguoi_lam uuid not null, bo_phan text not null fk cv_bo_phan, du_an_id bigint fk null,
         quan_trong bool not null default false, gap bool not null default false,
         han_ban_dau timestamptz not null, han timestamptz not null,
         trang_thai text not null default 'moi' check (moi|dang_lam|cho_duyet|hoan_thanh|huy),
         can_duyet bool not null default true, hien_thi text not null default 'cong_khai' check (cong_khai|han_che),
         so_lan_tra_lai int not null default 0, lien_ket jsonb not null default '[]',
         gia_han_den timestamptz, gia_han_ly_do text,
         lap_lai text not null default 'khong' check (khong|tuan|thang|quy),
         nhan_luc, bao_xong_luc, hoan_thanh_luc timestamptz, dung_han bool, qua_han_da_bao_luc timestamptz,
         tu_gop_y_id bigint null, created_at, updated_at)
cv_nguoi_phoi_hop(cong_viec_id fk on delete cascade, user_id, pk(cong_viec_id,user_id))
cv_checklist(id bigserial pk, cong_viec_id fk cascade, thu_tu int, noi_dung text not null, xong bool default false, xong_luc, xong_boi uuid)
cv_binh_luan(id bigserial pk, cong_viec_id fk null, du_an_id fk null, check (đúng 1 trong 2 khác null),
         nguoi_viet uuid not null, loai text check (...), noi_dung text not null,
         trang_thai_gop_y text null check (dang_xem_xet|da_tiep_thu|da_tra_loi|khong_ap_dung), tra_loi text,
         cong_viec_tao_ra bigint null, created_at)
cv_dong_tinh(binh_luan_id fk cascade, user_id, pk)
cv_tep(id bigserial pk, cong_viec_id fk cascade, binh_luan_id null, duong_dan text not null, ten_tep text, loai_mime text, created_by, created_at)
cv_lich_su(id bigserial pk, cong_viec_id fk cascade, nguoi uuid, hanh_dong text, noi_dung text, created_at)
cv_thong_bao(id bigserial pk, nguoi_nhan uuid not null, loai text not null, cong_viec_id null, du_an_id null,
         noi_dung text not null, can_xu_ly bool default false, da_xu_ly bool default false,
         da_doc bool default false, da_doc_luc timestamptz, created_at)
Storage bucket "cong-viec" (public read giống "su-co-duc", ghi: authenticated, đường dẫn <cong_viec_id>/<tên file>).
```

**View `cv_cong_viec_v`** (`security_invoker = true`, mọi trang đọc từ đây): mọi cột của `cv_cong_viec` +
`ten_nguoi_giao`, `ten_nguoi_lam` (qua `cv_ten_nguoi(uuid)`), `phoi_hop uuid[]`, `ten_phoi_hop text[]`,
`gap_hieu_luc bool`, `nhom int` (1–4), `qua_han bool`, `so_buoc int`, `so_buoc_xong int`, `so_binh_luan int`,
`ten_du_an text`, `con_gio numeric` (số giờ còn lại tới `han`, âm = quá hạn).

**RLS**: bật trên mọi bảng; chỉ có policy SELECT cho `authenticated` theo quy tắc "ai xem được"
(hàm `cv_xem_duoc(cong_viec_id)` security definer). `cv_thong_bao`: chỉ đọc dòng của mình.
**Không ghi trực tiếp** — mọi ghi qua RPC dưới đây.

## 4. RPC (security definer, `set search_path = public`; revoke public/anon, grant authenticated)

Lỗi nghiệp vụ: `raise exception '<câu tiếng Việt cho người dùng>'` (giao diện hiện nguyên văn `error.message`).

| Hàm | Tham số → trả về | Ai được gọi |
|---|---|---|
| `cv_danh_sach_nguoi()` | → table(user_id uuid, ten text, username text, role text) — ten = full_name, rỗng thì username/email | mọi tài khoản |
| `cv_tao_viec(p jsonb)` | keys: tieu_de, mo_ta, nguoi_lam, phoi_hop (uuid[]), bo_phan, du_an_id, quan_trong, gap, han (ISO), can_duyet, hien_thi, lien_ket, checklist (text[]), lap_lai, tu_gop_y_id → bigint id | mọi tài khoản (nguoi_giao = auth.uid()) |
| `cv_sua_viec(p_id bigint, p jsonb)` | cùng keys (trừ checklist); chỉ key có mặt mới đổi → void | người giao / BGĐ, khi chưa hoàn thành/huỷ |
| `cv_nhan_viec(p_id)` | → void | người làm, trạng thái moi |
| `cv_them_buoc(p_id, p_noi_dung text)` → bigint · `cv_xoa_buoc(p_buoc_id)` | | người giao hoặc người làm, chưa hoàn thành |
| `cv_tick_buoc(p_buoc_id, p_xong bool)` | → void | người làm, trạng thái dang_lam |
| `cv_bao_xong(p_id, p_ghi_chu text default null)` | → text trạng thái mới | người làm, dang_lam, đủ checklist |
| `cv_duyet(p_id)` | → void | người giao / BGĐ, cho_duyet |
| `cv_tra_lai(p_id, p_ly_do text)` | → void (thêm bình luận loai tra_lai) | người giao / BGĐ, cho_duyet |
| `cv_xin_gia_han(p_id, p_den timestamptz, p_ly_do text)` | → void | người làm, moi/dang_lam, chưa có yêu cầu đang chờ, p_den > han |
| `cv_tra_loi_gia_han(p_id, p_dong_y bool)` | → void | người giao / BGĐ |
| `cv_nhac_viec(p_id)` | → void | người giao / BGĐ |
| `cv_mo_lai(p_id)` | → void | người giao / BGĐ, hoan_thanh |
| `cv_huy_viec(p_id, p_ly_do text)` | → void | người giao / BGĐ, chưa hoàn thành |
| `cv_viet_binh_luan(p_cong_viec_id bigint, p_du_an_id bigint, p_loai text, p_noi_dung text, p_nhac uuid[] default null)` | → bigint | ai xem được việc/dự án; loai ∈ binh_luan/gop_y/cau_hoi/de_xuat/cap_nhat |
| `cv_dong_tinh(p_binh_luan_id)` | → bool (trạng thái mới) | ai xem được |
| `cv_xu_ly_gop_y(p_binh_luan_id, p_trang_thai text, p_tra_loi text default null)` | → void | người giao việc / chủ dự án / BGĐ |
| `cv_doc_thong_bao(p_ids bigint[] default null)` | null = tất cả của tôi → void | chính người nhận |
| `cv_tao_du_an(p jsonb)` | ten, mo_ta, bo_phan, ngay_bat_dau, ngay_ket_thuc → bigint | mọi tài khoản (chu_du_an = auth.uid()) |
| `cv_ghi_tep(p_cong_viec_id, p_duong_dan, p_ten_tep, p_loai_mime)` | → bigint | ai xem được việc |
| `cv_quet_qua_han()` | nội bộ, pg_cron mỗi giờ; revoke khỏi mọi role | — |

Mỗi RPC thay đổi việc đều ghi `cv_lich_su` (hanh_dong = tên ngắn, noi_dung = câu tiếng Việt đầy đủ) và cập nhật `updated_at`.

## 5. Giao diện (giai đoạn 1)

Theo chuẩn `duc-dashboard.html` (header tối, Inter 13px, token màu `:root`), `noTitleBar: true` trong `shared/navbar.js`.
Dùng chung `shared/cong-viec.js` (hằng số, hàm định dạng, gọi RPC, vẽ thẻ, thanh tab module) và `shared/cong-viec.css`.

| Trang | Nội dung |
|---|---|
| `cong-viec-cua-toi.html` | Mặc định khi vào module. Tab: Tôi làm / Tôi giao / Chờ tôi duyệt. Nhóm Quá hạn / Hôm nay / Tuần này / Sau. Hộp "Việc hôm nay". Dùng tốt trên điện thoại. |
| `cong-viec.html` | Bảng công việc: chuyển Kanban ⇄ Ma trận ưu tiên; lọc bộ phận, người làm, dự án, tìm kiếm, nhóm ưu tiên. Kéo thả theo đúng quyền. |
| `cong-viec-chi-tiet.html?id=` | Chi tiết: bước, tệp/ảnh, trao đổi & góp ý (loại, đồng tình, @tên), khung "Việc bạn cần làm" theo vai, mức ưu tiên, thông tin, lịch sử. |
| `cong-viec-giao.html` | Giao việc mới / sửa (`?id=`). Nhận tham số điền sẵn `?tieu_de=&lk=<loai>:<ma>&bo_phan=`. |
| `thong-bao.html` | Trang thông báo: Tất cả / Chưa đọc / Cần tôi xử lý; bấm = đánh đã đọc + mở việc. |
| `shared/navbar.js` | Nhóm menu "Công việc", chuông có số chưa đọc (đếm lại mỗi 60 giây và khi quay lại tab). |
