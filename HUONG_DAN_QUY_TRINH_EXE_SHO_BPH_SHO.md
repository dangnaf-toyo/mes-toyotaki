# Hướng dẫn quy trình EXE-SHO-01/02/03 & BPH-SHO-01/02/03

Quy trình: **Đúc → Đánh bóng (gộp đóng gói + OQC tại chuyền) → Đóng pallet → Nhập kho → Xuất hàng.**
Không qua Bavia / Gia Công / Sơn / OQC (trạm riêng) — người cuối chuyền Đánh bóng kiêm kiểm OQC và đóng thùng.

Nền tảng kỹ thuật: `migration_phase_T38_cong_doan_danh_bong.sql` (công đoạn Đánh bóng), `migration_phase_T39_bph_sho_danh_bong.sql` (khai báo cho BPH-SHO), `migration_phase_T40_tem_thanh_pham.sql` (tem thành phẩm + ghi nhận thùng). Cả 3 **phải chạy trên cả production và staging** trước khi dùng.

---

## 1. Chuẩn bị dữ liệu danh mục (1 lần / mỗi mã SP)

Vào **Quản lý danh mục → tab Sản phẩm**, kiểm tra/điền cho từng mã (`EXE-SHO-01/02/03`, `BPH-SHO-01/02/03`):

| Trường | Giá trị cần có | Dùng ở đâu |
|---|---|---|
| Mã khách hàng / Tên khách hàng | Đã biết trước | Hiện trên tem thành phẩm |
| **Mã SP tại khách hàng** (mới — T40) | SKU/mã hàng phía khách hàng | Hiện trên tem thành phẩm — **khác** "Mã khách hàng" |
| SL đóng gói chuẩn | `150` | Quy cách thùng Đúc (Kanban) |
| Quy trình công đoạn | `Đúc, Đánh bóng, Nhập kho, Xuất hàng` | Gợi ý công đoạn nhận khi Chuyển công đoạn |

Đã chạy sẵn qua T38/T39 cho cả 6 mã (`quy_trinh_cong_doan` + `sl_dong_goi_chuan=150`) — chỉ cần **bổ sung "Mã SP tại khách hàng"** vì đây là dữ liệu thật chỉ bạn biết.

Quy cách thùng Đánh bóng (**60pcs/thùng**) không nằm trong danh mục SP — nó là định mức theo **công đoạn**, khai trong code (`CONFIG.PACKAGING`/`TP_PACKAGING` ở `chuyencongdoan.html` và `intem.html`), áp dụng cho mọi mã SP đi qua Đánh bóng.

---

## 2. Thao tác từng bước

### Bước 1 — Đúc: in tem chỉ thị Kanban
`intem.html` → tab **Chỉ thị SX**. Chọn máy đúc + mã SP + ngày → hệ thống gợi ý số thùng theo KHSX tuần (150pcs/thùng) → **Tạo lô & in**.

### Bước 2 — Đúc: ghi nhận thùng
`ghi-nhan-kanban.html`. Mỗi thùng đúc xong, quét QR trên tem → tem chuyển `Chờ sản xuất` → `Đã sản xuất`, cộng vào sản lượng ca.

### Bước 3 — Chuyển công đoạn: Đúc → Đánh bóng
`chuyencongdoan.html` tab 1 (Chuyển công đoạn). Quét tem Đúc, chọn **Đánh bóng** làm công đoạn nhận (đã gợi ý sẵn theo quy trình khai ở Bước 0), người giao/nhận xác nhận.

**Đây là bước bắt buộc trước khi ghi nhận thùng thành phẩm** — hệ thống chỉ trừ được nguồn từ những tem Đúc **đã chuyển và đã xác nhận** sang Đánh bóng.

### Bước 4 — In trước lô tem thành phẩm (Đánh bóng)
`intem.html` → tab **Tem Thành Phẩm**. Chọn công đoạn "Đánh bóng", mã SP, ngày sản xuất, người kiểm tra, số thùng cần in → **Tạo lô & in**. Mỗi tem = 1 Tag No mới (`TP{ngày}-{số}`), trạng thái `Chờ đóng gói TP`, in sẵn 60pcs/thùng + Mã SP tại KH + Tên khách hàng + Người kiểm tra.

In **trước** khi đóng thùng thật — dán/gài sẵn tem chờ, không cần thao tác gì thêm lúc đóng thùng ngoài quét QR.

### Bước 5 — Ghi nhận thùng thành phẩm
`ghi-nhan-tem-thanh-pham.html` (menu Sản xuất → "Ghi nhận thùng thành phẩm"). Đầu ca chọn **Trạm đang hoạt động** (công đoạn/ngày/ca/trạm — không bắt buộc, chỉ để cộng sản lượng vào đúng trạm trên dashboard). Khi 1 thùng đủ 60pcs, quét QR trên tem thành phẩm vừa dán vào thùng.

Hệ thống tự động:
1. Trừ 60pcs từ các tem Đúc **đang ở Đánh bóng** (FIFO theo thời điểm chuyển công đoạn), cùng mã SP.
2. Ghi liên kết nguồn gốc (tem thành phẩm ⇄ tem Đúc) — truy xuất được sau này.
3. Chuyển tem thành phẩm sang `Đã đóng gói TP`.
4. Cộng 60pcs OK vào trạm đã chọn (nếu có).

Nếu báo lỗi **"Không đủ tem Đúc khả dụng"** → quay lại Bước 3, chuyển công đoạn thêm tem Đúc rồi thử lại.

### Bước 6 — Đóng pallet
`oqc.html` (menu "Đóng gói Pallet" — không còn gắn nhãn OQC riêng, dùng chung cho mọi công đoạn). Tạo pallet mới, quét các tem thành phẩm (60pcs) cho tới khi đủ, đóng pallet.

### Bước 7 — Nhập kho
`kho-thanh-pham.html` tab **Nhập kho**. Quét pallet (hoặc tem lẻ nếu không đóng pallet).

### Bước 8 — Xuất hàng
`kho-thanh-pham.html` tab **Xuất hàng**. Tạo phiếu xuất theo khách hàng, quét pallet/tem vào phiếu, đóng phiếu.

---

## 3. Theo dõi sản lượng

`cong-doan-dashboard.html?cd=Đánh bóng` (menu "Bảng điều khiển Đánh bóng") — sản lượng OK/NG theo trạm/tổ, cộng dồn theo ca, giống Bavia/Gia Công/Sơn/OQC.

`khsx-tuan.html` và `cong-doan-bao-cao-ca.html` cũng có tab "Đánh bóng" để lập KH tuần / báo cáo cuối ca.

---

## 4. Checklist kiểm tra logic hệ thống

Thực hiện theo đúng thứ tự — mỗi bước xác nhận trước khi qua bước sau.

- [ ] **4.1 — Danh mục:** Mở "Mã SP tại khách hàng" cho 1 mã (VD `EXE-SHO-01`), lưu, mở lại — giá trị còn nguyên.
- [ ] **4.2 — Kanban Đúc:** In 1 lô 2 thùng `EXE-SHO-01`. Kiểm tra tem in ra đúng 150pcs/thùng, đúng ngày.
- [ ] **4.3 — Ghi nhận Đúc:** Quét cả 2 tem ở `ghi-nhan-kanban.html`. Xác nhận tem chuyển `Đã sản xuất`, cộng đúng sản lượng (`tra-cuu-tem.html` tra lại 2 Tag No vừa quét).
- [ ] **4.4 — Chuyển công đoạn:** Chuyển cả 2 tem sang Đánh bóng, xác nhận nhận hàng. Tổng khả dụng lúc này = 300pcs `EXE-SHO-01` tại Đánh bóng.
- [ ] **4.5 — In tem thành phẩm:** In lô 3 tem thành phẩm (3×60=180pcs ≤ 300pcs khả dụng) cho `EXE-SHO-01`. Kiểm tra tem in ra: đúng Mã SP tại KH/Tên KH đã khai ở 4.1, đúng người kiểm tra, đúng 60pcs.
- [ ] **4.6 — Ghi nhận đủ nguồn (kỳ vọng OK):** Ghi nhận cả 3 tem thành phẩm ở `ghi-nhan-tem-thanh-pham.html`. Cả 3 phải **thành công**.
- [ ] **4.7 — FIFO đúng chiều:** Sau 4.6, kiểm tra 2 tem Đúc nguồn qua `tra-cuu-tem.html` — tem có `ngày_gio_ghi_nhan` SỚM HƠN phải bị trừ trước (tem cũ hết trước, không phải tem mới).
- [ ] **4.8 — Chặn thiếu nguồn (kỳ vọng LỖI có chủ đích):** In thêm 1 tem thành phẩm `EXE-SHO-01` nữa (thùng thứ 4, cần thêm 60pcs) nhưng KHÔNG chuyển thêm tem Đúc nào. Ghi nhận tem này ở `ghi-nhan-tem-thanh-pham.html` — phải báo lỗi **"Không đủ tem Đúc khả dụng tại Đánh bóng"**, KHÔNG được ghi nhận thành công.
- [ ] **4.9 — Chặn ghi nhận trùng:** Quét lại 1 trong 3 tem đã ghi nhận ở 4.6 — phải báo **"Tem đã được ghi nhận lúc ..."**, không trừ nguồn lần 2.
- [ ] **4.10 — Trạm/sản lượng:** Nếu có chọn Trạm ở bước ghi nhận — mở `cong-doan-dashboard.html?cd=Đánh bóng`, xác nhận trạm đó cộng đúng 180pcs OK.
- [ ] **4.11 — Truy xuất nguồn gốc:** Vào `truy-xuat-nguon-goc.html`, tra 1 trong 3 Tag No thành phẩm — phải thấy liên kết ngược về đúng 2 Tag No Đúc nguồn, đúng số lượng lấy từ mỗi tem.
- [ ] **4.12 — QR đọc được đủ trường:** Quét QR bất kỳ 1 tem thành phẩm bằng app đọc QR ngoài (điện thoại) — chuỗi trả về phải đủ 9 trường: Tag No, Tên SP, Mã SP, Số lượng, Ngày (dd/mm/yyyy), Ngày (yyyy-mm-dd), Mã SP tại KH, Tên KH, Người kiểm.
- [ ] **4.13 — Đóng pallet:** Quét 3 tem thành phẩm vào 1 pallet ở `oqc.html`, đóng pallet — tổng pallet = 180pcs.
- [ ] **4.14 — Nhập kho & xuất hàng:** Nhập kho pallet đó ở `kho-thanh-pham.html`, tạo phiếu xuất, quét pallet vào phiếu, đóng phiếu — kiểm tra tồn kho giảm đúng.
- [ ] **4.15 — Lặp lại 4.5–4.14 cho `BPH-SHO-01`** để xác nhận quy trình hoạt động đồng nhất cho cả nhóm mã Kẽm 190T.

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| "Vai trò không hợp lệ" khi tạo tài khoản Nhân viên — Đánh bóng | Edge Function `admin-create-user` chưa deploy lại sau khi đổi code | Deploy lại qua Supabase CLI |
| "Không đủ tem Đúc khả dụng tại Đánh bóng" | Chưa Chuyển công đoạn đủ tem Đúc sang Đánh bóng, hoặc tem chưa được xác nhận nhận hàng | Quay lại Bước 3, kiểm tra `cd_chuyen_cong_doan_log` đã có trạng thái "Đã xác nhận chuyển công đoạn" |
| Tem thành phẩm không hiện Mã SP tại KH / Tên KH | Chưa khai ở danh mục SP trước khi in lô | Khai trước, in lại lô (lô cũ đã đông lạnh dữ liệu tại thời điểm in, không tự cập nhật) |
| "Tem không phải tem thành phẩm chờ đóng gói" | Quét nhầm Tag No tem Đúc (TKD...) hoặc tem Kanban khác vào màn Ghi nhận thùng thành phẩm | Kiểm tra đúng màn hình — Kanban Đúc dùng `ghi-nhan-kanban.html`, thành phẩm dùng `ghi-nhan-tem-thanh-pham.html` |
