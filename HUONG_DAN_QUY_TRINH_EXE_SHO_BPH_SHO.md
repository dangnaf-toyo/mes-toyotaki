# Hướng dẫn quy trình EXE-SHO-01/02/03 & BPH-SHO-01/02/03

Hai nhóm mã đi **2 quy trình khác nhau** kể từ T42:

| Nhóm mã | Quy trình |
|---|---|
| `EXE-SHO-01/02/03` | Đúc (150pcs/thùng) → **Đánh bóng** (gộp về 60pcs/thùng ngay tại đây, kiêm kiểm OQC tại chuyền) → Đóng pallet → Nhập kho → Xuất hàng |
| `BPH-SHO-01/02/03` | Đúc (150pcs/thùng) → Đánh bóng → Gia Công → **OQC** (gộp về 60pcs/thùng tại đây) → Đóng pallet → Nhập kho → Xuất hàng |

Cả 2 nhóm: **Đúc → trước bước gộp đóng gói** đều giữ nguyên 150pcs/thùng nhựa, chỉ Chuyển công đoạn bình thường (không đóng gói lại). Chỉ khác nhau **gộp về 60pcs ở công đoạn nào** — EXE-SHO gộp ngay ở Đánh bóng, BPH-SHO đi thêm qua Gia Công rồi mới gộp ở OQC.

Nền tảng kỹ thuật:
- `migration_phase_T38_cong_doan_danh_bong.sql` — thêm công đoạn Đánh bóng vào hệ thống.
- `migration_phase_T39_bph_sho_danh_bong.sql` — khai báo quy trình ban đầu cho BPH-SHO (đã bị T42 thay thế bằng quy trình dài hơn).
- `migration_phase_T40_tem_thanh_pham.sql` + `migration_phase_T41_tem_thanh_pham_nguoi_kiem_luc_quet.sql` — cơ chế Tem Thành Phẩm (in trước + quét ghi nhận, tự FIFO trừ nguồn tem Đúc, người kiểm tra ghi nhận LÚC QUÉT chứ không in sẵn).
- `migration_phase_T42_bph_sho_quy_trinh_dai_hon.sql` — quy trình dài hơn cho BPH-SHO (Gia Công + OQC), dùng lại nguyên cơ chế Tem Thành Phẩm, chỉ đổi công đoạn áp dụng.

**Cả 5 migration phải chạy trên cả production và staging** trước khi dùng (theo đúng thứ tự trên).

---

## 1. Chuẩn bị dữ liệu danh mục (1 lần / mỗi mã SP)

Vào **Quản lý danh mục → tab Sản phẩm**, kiểm tra/điền cho từng mã:

| Trường | Giá trị cần có | Dùng ở đâu |
|---|---|---|
| Mã khách hàng / Tên khách hàng | Đã biết trước | Hiện trên tem thành phẩm |
| **Mã SP tại khách hàng** (T40) | SKU/mã hàng phía khách hàng | Hiện trên tem thành phẩm — **khác** "Mã khách hàng" |
| SL đóng gói chuẩn | `150` | Quy cách thùng Đúc (Kanban) — áp dụng suốt tới trước bước gộp, cả 2 nhóm mã |
| Quy trình công đoạn | `EXE-SHO`: `Đúc, Đánh bóng, Nhập kho, Xuất hàng`<br>`BPH-SHO`: `Đúc, Đánh bóng, Gia Công, OQC, Nhập kho, Xuất hàng` | Gợi ý công đoạn nhận khi Chuyển công đoạn |

Đã chạy sẵn qua T38/T39/T42 cho cả 6 mã — chỉ cần **bổ sung "Mã SP tại khách hàng"** vì đây là dữ liệu thật chỉ bạn biết.

Quy cách thùng gộp **60pcs/thùng** không nằm trong danh mục SP — là định mức theo **công đoạn**, khai trong code `TP_PACKAGING` ở `intem.html` (hiện có `"Đánh bóng": 60` và `"OQC": 60`). Lưu ý: `CONFIG.PACKAGING["OQC"]` bên `chuyencongdoan.html` (dùng cho "Đóng gói lại" thủ công của SP khác) đang là `100` — **khác** `TP_PACKAGING["OQC"]=60` — 2 map độc lập, không đụng nhau vì phục vụ 2 flow khác nhau.

---

## 2. Thao tác từng bước

### Bước 1 — Đúc: in tem chỉ thị Kanban
`intem.html` → tab **Chỉ thị SX**. Chọn máy đúc + mã SP + ngày → hệ thống gợi ý số thùng theo KHSX tuần (150pcs/thùng) → **Tạo lô & in**.

### Bước 2 — Đúc: ghi nhận thùng
`ghi-nhan-kanban.html`. Mỗi thùng đúc xong, quét QR trên tem → tem chuyển `Chờ sản xuất` → `Đã sản xuất`, cộng vào sản lượng ca.

### Bước 3 — Chuyển công đoạn (lặp lại cho từng chặng)
`chuyencongdoan.html` tab 1 (Chuyển công đoạn). Quét tem, chọn công đoạn nhận (gợi ý sẵn theo quy trình khai ở mục 1), người giao/nhận xác nhận.

- `EXE-SHO`: 1 chặng — Đúc → Đánh bóng.
- `BPH-SHO`: 2 chặng — Đúc → Đánh bóng, rồi Đánh bóng → Gia Công, rồi Gia Công → OQC (3 lượt chuyển, tem vẫn giữ nguyên 150pcs/thùng suốt, không đóng gói lại ở Đánh bóng/Gia Công).

**Đây là bước bắt buộc trước khi ghi nhận thùng thành phẩm** — hệ thống chỉ trừ được nguồn từ những tem Đúc **đã chuyển và đã xác nhận** tới đúng công đoạn gộp đóng gói (Đánh bóng với EXE-SHO, OQC với BPH-SHO).

### Bước 4 — In trước lô tem thành phẩm
`intem.html` → tab **Tem Thành Phẩm**. Chọn công đoạn (**Đánh bóng** cho EXE-SHO, **OQC** cho BPH-SHO), mã SP, ngày sản xuất, số thùng cần in → **Tạo lô & in**. Mỗi tem = 1 Tag No mới (`TP{ngày}-{số}`), trạng thái `Chờ đóng gói TP`, in sẵn 60pcs/thùng + Mã SP tại KH + Tên khách hàng.

In **trước** khi đóng thùng thật — dán/gài sẵn tem chờ. Tem **không in Người kiểm tra/Ngày SX** (T41) — 2 thông tin này ghi nhận ở bước sau, lúc quét.

### Bước 5 — Ghi nhận thùng thành phẩm
`ghi-nhan-tem-thanh-pham.html` (menu Sản xuất → "Ghi nhận thùng thành phẩm"). Chọn **Người kiểm tra** (mặc định tài khoản đăng nhập, đổi được). Đầu ca chọn **Trạm đang hoạt động** (công đoạn Đánh bóng hoặc OQC/ngày/ca/trạm — không bắt buộc, chỉ để cộng sản lượng vào đúng trạm trên dashboard). Khi 1 thùng đủ 60pcs, quét QR trên tem thành phẩm vừa dán vào thùng.

Hệ thống tự động:
1. Trừ 60pcs từ các tem Đúc **đang ở đúng công đoạn của tem thành phẩm** (Đánh bóng hoặc OQC, tuỳ lô) — FIFO theo thời điểm chuyển công đoạn, cùng mã SP.
2. Ghi liên kết nguồn gốc (tem thành phẩm ⇄ tem Đúc) — truy xuất được sau này.
3. Ghi nhận Người kiểm tra + ngày giờ kiểm (= lúc quét).
4. Chuyển tem thành phẩm sang `Đã đóng gói TP`.
5. Cộng 60pcs OK vào trạm đã chọn (nếu có).

Nếu báo lỗi **"Không đủ tem Đúc khả dụng"** → quay lại Bước 3, chuyển công đoạn thêm tem Đúc tới đúng công đoạn rồi thử lại.

### Bước 6 — Đóng pallet
`oqc.html` (menu "Đóng gói Pallet" — không còn gắn nhãn OQC riêng, dùng chung cho mọi công đoạn). Tạo pallet mới, quét các tem thành phẩm (60pcs) cho tới khi đủ, đóng pallet.

### Bước 7 — Nhập kho
`kho-thanh-pham.html` tab **Nhập kho**. Quét pallet (hoặc tem lẻ nếu không đóng pallet).

### Bước 8 — Xuất hàng
`kho-thanh-pham.html` tab **Xuất hàng**. Tạo phiếu xuất theo khách hàng, quét pallet/tem vào phiếu, đóng phiếu.

---

## 3. Theo dõi sản lượng

`cong-doan-dashboard.html?cd=Đánh bóng` và `?cd=OQC` (menu "Bảng điều khiển Đánh bóng"/"Bảng điều khiển OQC") — sản lượng OK/NG theo trạm/tổ, cộng dồn theo ca.

`khsx-tuan.html` và `cong-doan-bao-cao-ca.html` cũng có tab Đánh bóng/OQC để lập KH tuần / báo cáo cuối ca.

---

## 4. Checklist kiểm tra logic hệ thống

Thực hiện theo đúng thứ tự — mỗi bước xác nhận trước khi qua bước sau. Làm với `EXE-SHO-01` trước (mục 4.1–4.14), sau đó lặp lại với `BPH-SHO-01` (mục 4.15) để phủ luôn nhánh dài hơn.

- [ ] **4.1 — Danh mục:** Mở "Mã SP tại khách hàng" cho `EXE-SHO-01`, lưu, mở lại — giá trị còn nguyên.
- [ ] **4.2 — Kanban Đúc:** In 1 lô 2 thùng `EXE-SHO-01`. Kiểm tra tem in ra đúng 150pcs/thùng, đúng ngày.
- [ ] **4.3 — Ghi nhận Đúc:** Quét cả 2 tem ở `ghi-nhan-kanban.html`. Xác nhận tem chuyển `Đã sản xuất`, cộng đúng sản lượng (`tra-cuu-tem.html` tra lại 2 Tag No vừa quét).
- [ ] **4.4 — Chuyển công đoạn:** Chuyển cả 2 tem sang Đánh bóng, xác nhận nhận hàng. Tổng khả dụng lúc này = 300pcs `EXE-SHO-01` tại Đánh bóng.
- [ ] **4.5 — In tem thành phẩm:** In lô 3 tem thành phẩm công đoạn "Đánh bóng" (3×60=180pcs ≤ 300pcs khả dụng) cho `EXE-SHO-01`. Kiểm tra tem in ra: đúng Mã SP tại KH/Tên KH đã khai ở 4.1, đúng 60pcs, **không có** dòng Người kiểm/Ngày SX.
- [ ] **4.6 — Ghi nhận đủ nguồn (kỳ vọng OK):** Chọn Người kiểm tra, ghi nhận cả 3 tem thành phẩm ở `ghi-nhan-tem-thanh-pham.html`. Cả 3 phải **thành công**, kết quả hiện đúng tên người kiểm vừa chọn + giờ ghi nhận.
- [ ] **4.7 — FIFO đúng chiều:** Sau 4.6, kiểm tra 2 tem Đúc nguồn qua `tra-cuu-tem.html` — tem có `ngày_gio_ghi_nhan` SỚM HƠN phải bị trừ trước (tem cũ hết trước, không phải tem mới).
- [ ] **4.8 — Chặn thiếu nguồn (kỳ vọng LỖI có chủ đích):** In thêm 1 tem thành phẩm `EXE-SHO-01` nữa (thùng thứ 4, cần thêm 60pcs) nhưng KHÔNG chuyển thêm tem Đúc nào. Ghi nhận tem này — phải báo lỗi **"Không đủ tem Đúc khả dụng tại Đánh bóng"**, KHÔNG được ghi nhận thành công.
- [ ] **4.9 — Chặn ghi nhận trùng:** Quét lại 1 trong 3 tem đã ghi nhận ở 4.6 — phải báo **"Tem đã được ghi nhận lúc ..."**, không trừ nguồn lần 2.
- [ ] **4.10 — Trạm/sản lượng:** Nếu có chọn Trạm ở bước ghi nhận — mở `cong-doan-dashboard.html?cd=Đánh bóng`, xác nhận trạm đó cộng đúng 180pcs OK.
- [ ] **4.11 — Truy xuất nguồn gốc:** Vào `truy-xuat-nguon-goc.html`, tra 1 trong 3 Tag No thành phẩm — phải thấy liên kết ngược về đúng 2 Tag No Đúc nguồn, đúng số lượng lấy từ mỗi tem.
- [ ] **4.12 — QR đọc được đủ trường:** Quét QR bất kỳ 1 tem thành phẩm bằng app đọc QR ngoài (điện thoại) — chuỗi trả về phải đủ 8 trường: Tag No, Tên SP, Mã SP, Số lượng, Ngày (dd/mm/yyyy), Ngày (yyyy-mm-dd), Mã SP tại KH, Tên KH (không có người kiểm — chưa xác định lúc in).
- [ ] **4.13 — Đóng pallet:** Quét 3 tem thành phẩm vào 1 pallet ở `oqc.html`, đóng pallet — tổng pallet = 180pcs.
- [ ] **4.14 — Nhập kho & xuất hàng:** Nhập kho pallet đó ở `kho-thanh-pham.html`, tạo phiếu xuất, quét pallet vào phiếu, đóng phiếu — kiểm tra tồn kho giảm đúng.
- [ ] **4.15 — Lặp lại cho `BPH-SHO-01` với nhánh dài hơn:** Đúc (4.2–4.3) → Chuyển công đoạn Đúc→Đánh bóng→Gia Công→OQC (3 lượt, đều xác nhận nhận hàng) → In tem thành phẩm công đoạn **"OQC"** (không phải Đánh bóng) → Ghi nhận (4.6–4.9, kỳ vọng giống hệt) → Trạm OQC (`cong-doan-dashboard.html?cd=OQC`) → Truy xuất nguồn gốc → Đóng pallet → Nhập/Xuất kho. Đặc biệt chú ý: nếu chỉ chuyển công đoạn tới **Gia Công** (chưa chuyển tiếp lên OQC) rồi thử in/ghi nhận tem thành phẩm công đoạn OQC — phải báo lỗi thiếu nguồn giống 4.8 (nguồn phải "ở đúng" OQC, không tự động cộng dồn qua các chặng trước).

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| "Vai trò không hợp lệ" khi tạo tài khoản Nhân viên — Đánh bóng | Edge Function `admin-create-user` chưa deploy lại sau khi đổi code | Deploy lại qua Supabase CLI |
| "Không đủ tem Đúc khả dụng tại Đánh bóng/OQC" | Chưa Chuyển công đoạn đủ tem Đúc tới đúng công đoạn, hoặc tem chưa được xác nhận nhận hàng, hoặc (với BPH-SHO) tem mới tới Gia Công chứ chưa tới OQC | Quay lại Bước 3, kiểm tra `cd_chuyen_cong_doan_log` đã có trạng thái "Đã xác nhận chuyển công đoạn" đúng tới công đoạn của tem thành phẩm |
| Tem thành phẩm không hiện Mã SP tại KH / Tên KH | Chưa khai ở danh mục SP trước khi in lô | Khai trước, in lại lô (lô cũ đã đông lạnh dữ liệu tại thời điểm in, không tự cập nhật) |
| "Tem không phải tem thành phẩm chờ đóng gói" | Quét nhầm Tag No tem Đúc (TKD...) hoặc tem Kanban khác vào màn Ghi nhận thùng thành phẩm | Kiểm tra đúng màn hình — Kanban Đúc dùng `ghi-nhan-kanban.html`, thành phẩm dùng `ghi-nhan-tem-thanh-pham.html` |
| Danh mục sản phẩm hiện trống toàn bộ | Trang `quan-ly-danh-muc.html` đọc cột chưa được tạo (migration liên quan T40 chưa chạy) — lỗi PostgREST làm SẬP CẢ query, không riêng field mới | Chạy đủ migration theo đúng thứ tự ở đầu file này |
