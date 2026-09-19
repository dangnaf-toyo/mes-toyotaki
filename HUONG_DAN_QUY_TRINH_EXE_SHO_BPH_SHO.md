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
- `migration_phase_T40_tem_thanh_pham.sql` + `migration_phase_T41_tem_thanh_pham_nguoi_kiem_luc_quet.sql` — cơ chế Tem Thành Phẩm (in trước + quét ghi nhận, người kiểm tra ghi nhận LÚC QUÉT chứ không in sẵn).
- `migration_phase_T42_bph_sho_quy_trinh_dai_hon.sql` — quy trình dài hơn cho BPH-SHO (Gia Công + OQC), dùng lại nguyên cơ chế Tem Thành Phẩm, chỉ đổi công đoạn áp dụng.
- `migration_phase_T43_tem_thanh_pham_khai_bao_nguon.sql` — **đổi cách chọn nguồn**: KHÔNG còn tự động FIFO trên mọi tem Đúc đã chuyển tới công đoạn — người ở cuối chuyền phải **khai báo tường minh** tem Đúc đang dùng (đọc tem thùng đang đánh), hệ thống chỉ trừ từ các tem đã khai báo, đúng thứ tự khai báo.

**Cả 6 migration phải chạy trên cả production và staging** trước khi dùng (theo đúng thứ tự trên).

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

**Đây là bước bắt buộc trước khi ghi nhận thùng thành phẩm** — hệ thống chỉ trừ được nguồn từ những tem Đúc **đã được Chuyển công đoạn** tới đúng công đoạn gộp đóng gói (Đánh bóng với EXE-SHO, OQC với BPH-SHO). Từ T45: **không cần đợi ai đó "Xác nhận đã giao hàng"** ở `chuyencongdoan.html` — chỉ cần phiếu chuyển tồn tại là dùng được ngay, khớp thực tế sản xuất chạy liên tục qua các công đoạn; bước "Xác nhận đã giao hàng" (lọc theo Bộ phận GIAO) vẫn còn, chỉ là làm cuối ca cho đủ sổ sách, không còn chặn thao tác.

### Bước 4 — In trước lô tem thành phẩm
`intem.html` → tab **Tem Thành Phẩm**. Chọn công đoạn (**Đánh bóng** cho EXE-SHO, **OQC** cho BPH-SHO), mã SP, ngày sản xuất, số thùng cần in → **Tạo lô & in**. Mỗi tem = 1 Tag No mới (`TP{ngày}-{số}`), trạng thái `Chờ đóng gói TP`, in sẵn 60pcs/thùng + Mã SP tại KH + Tên khách hàng.

In **trước** khi đóng thùng thật — dán/gài sẵn tem chờ. Tem **không in Người kiểm tra/Ngày SX** (T41) — 2 thông tin này ghi nhận ở bước sau, lúc quét.

### Bước 5 — Khai báo tem Đúc đang dùng (T43)
`ghi-nhan-tem-thanh-pham.html` (menu Sản xuất → "Ghi nhận thùng thành phẩm"). Chọn **Người kiểm tra**, chọn đúng **Công đoạn** (Đánh bóng hoặc OQC — dùng để khai báo, không chỉ để cộng sản lượng như "Trạm/tổ"). Ở khu **"Tem Đúc đang dùng"**, đọc/nhập Tag No của thùng Đúc đang thực sự đánh — hệ thống kiểm tra tem đó đã có phiếu Chuyển công đoạn tới đúng công đoạn này (không cần đã "Xác nhận đã giao hàng" — T45), rồi thêm vào danh sách "đang dùng".

Mỗi lần lấy 5-7 thùng Đúc về chuyền, đọc lần lượt từng tem — không cần đọc hết 1 lượt, có thể đọc thêm bất cứ lúc nào. Hệ thống chỉ trừ nguồn từ các tem **đã khai báo**, theo đúng thứ tự khai báo — tem chưa khai báo dù đã chuyển công đoạn cũng KHÔNG bị trừ nhầm. Tem đã dùng hết (0 pcs) không khai báo lại được.

### Bước 6 — Ghi nhận thùng thành phẩm
Khi 1 thùng đủ 60pcs, quét QR trên tem thành phẩm vừa dán vào thùng (khu "Quét tem thành phẩm", cùng trang). Hệ thống tự động:
1. Trừ 60pcs từ (các) tem Đúc **đã khai báo đang dùng**, theo đúng thứ tự khai báo — 1 thùng thành phẩm vẫn có thể lấy từ 2 tem Đúc liền kề (150/60 không chia hết, không tránh được).
2. Ghi liên kết nguồn gốc (tem thành phẩm ⇄ tem Đúc) — truy xuất được sau này.
3. Ghi nhận Người kiểm tra + ngày giờ kiểm (= lúc quét).
4. Chuyển tem thành phẩm sang `Đã đóng gói TP`.
5. Cộng 60pcs OK vào trạm đã chọn (nếu có).
6. Nếu ghi nhận này vừa làm 1 tem nguồn dùng hết sạch → hiện banner cảnh báo **"Tem nguồn ... vừa dùng hết"** — quay lại Bước 5 đọc tem thùng tiếp theo trước khi ghi nhận thùng kế.

Nếu báo lỗi **"Chưa đủ nguồn từ tem Đúc ĐÃ KHAI BÁO"** → quay lại Bước 5, khai báo thêm tem Đúc rồi ghi nhận lại đúng tem thành phẩm đó.

### Bước 7 — Đóng pallet
`oqc.html` (menu "Đóng gói Pallet" — không còn gắn nhãn OQC riêng, dùng chung cho mọi công đoạn). Tạo pallet mới, quét các tem thành phẩm (60pcs) cho tới khi đủ, đóng pallet.

### Bước 8 — Nhập kho
`kho-thanh-pham.html` tab **Nhập kho**. Quét pallet (hoặc tem lẻ nếu không đóng pallet).

### Bước 9 — Xuất hàng
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
- [ ] **4.5b — Chặn ghi nhận khi CHƯA khai báo nguồn (kỳ vọng LỖI có chủ đích):** KHÔNG khai báo tem Đúc nào, thử ghi nhận ngay 1 trong 3 tem thành phẩm — phải báo lỗi thiếu nguồn (danh sách "Tem Đúc đang dùng" đang trống), KHÔNG được thành công dù 2 tem Đúc đã chuyển công đoạn xong ở 4.4.
- [ ] **4.6 — Khai báo nguồn đúng thứ tự:** Ở `ghi-nhan-tem-thanh-pham.html` khu "Tem Đúc đang dùng", đọc lần lượt Tag No 2 tem Đúc từ 4.3/4.4 (tem cũ trước, tem mới sau) — cả 2 xuất hiện trong danh sách, đúng còn 150pcs mỗi tem.
- [ ] **4.7 — Ghi nhận đủ nguồn theo đúng thứ tự khai báo (kỳ vọng OK):** Chọn Người kiểm tra, ghi nhận cả 3 tem thành phẩm. Cả 3 phải **thành công**. Sau khi ghi nhận đủ, kiểm tra 2 tem Đúc nguồn qua `tra-cuu-tem.html` — tem khai báo TRƯỚC phải bị trừ hết trước (đúng theo thứ tự khai báo ở 4.6, không phải theo mã Tag No hay thời gian chuyển công đoạn).
- [ ] **4.8 — Cảnh báo hết nguồn:** Trong lúc ghi nhận ở 4.7, tem nào làm tem Đúc đang dùng đầu tiên dùng hết sạch (0pcs) phải kích hoạt banner cảnh báo "Tem nguồn ... vừa dùng hết" ngay sau lần ghi nhận đó.
- [ ] **4.9 — Chặn khai báo lại tem đã hết (kỳ vọng LỖI có chủ đích):** Sau khi 1 tem Đúc về 0pcs ở 4.7/4.8, thử đọc lại đúng Tag No đó ở khu "Tem Đúc đang dùng" — phải báo lỗi **"đã dùng hết — không thể khai báo lại"**.
- [ ] **4.9b — Chặn thiếu nguồn dù đã khai báo (kỳ vọng LỖI có chủ đích):** In thêm 1 tem thành phẩm `EXE-SHO-01` nữa (thùng thứ 4, cần thêm 60pcs) khi cả 2 tem Đúc đã khai báo đều hết. Ghi nhận tem này — phải báo lỗi **"Chưa đủ nguồn từ tem Đúc ĐÃ KHAI BÁO"**, KHÔNG được ghi nhận thành công dù có thể còn tem Đúc khác (chưa khai báo) tồn tại ở công đoạn.
- [ ] **4.9c — Chặn ghi nhận trùng:** Quét lại 1 trong 3 tem đã ghi nhận ở 4.7 — phải báo **"Tem đã được ghi nhận lúc ..."**, không trừ nguồn lần 2.
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
| "Chưa đủ nguồn từ tem Đúc ĐÃ KHAI BÁO" | Chưa khai báo (đọc) đủ tem Đúc ở khu "Tem Đúc đang dùng" — dù tem Đúc đã Chuyển công đoạn xong, hệ thống KHÔNG tự dùng nếu chưa khai báo tường minh (T43) | Quay lại Bước 5, đọc thêm tem thùng Đúc tiếp theo rồi ghi nhận lại đúng tem thành phẩm đó |
| "Tem đã dùng hết — không thể khai báo lại" | Đọc lại 1 tem Đúc đã tiêu thụ hết (0pcs) ở khu "Tem Đúc đang dùng" | Đọc tem thùng Đúc khác còn hàng — đây là chặn có chủ đích, không phải lỗi |
| Khai báo nguồn báo "chưa được Chuyển công đoạn tới ..." | Đọc nhầm tem Đúc chưa Chuyển công đoạn tới đúng công đoạn đang chọn ở đầu trang (từ T45 không còn cần "Xác nhận đã giao hàng" nữa, chỉ cần phiếu chuyển tồn tại) | Kiểm tra lại Bước 3 (Chuyển công đoạn), và đúng "Công đoạn" đang chọn ở đầu `ghi-nhan-tem-thanh-pham.html` |
| "Xác nhận đã giao hàng" chọn nhầm Bộ phận không thấy phiếu | Màn xác nhận ở `chuyencongdoan.html` lọc theo **Bộ phận GIAO** (VD "Đúc"), không phải bộ phận nhận (VD "Đánh bóng") | Chọn đúng bộ phận đã GIAO hàng ở dropdown, không phải bộ phận đang nhận — từ T45 bước này không còn bắt buộc trước khi khai báo nguồn nữa, chỉ để đủ sổ sách |
| Tem thành phẩm không hiện Mã SP tại KH / Tên KH | Chưa khai ở danh mục SP trước khi in lô | Khai trước, in lại lô (lô cũ đã đông lạnh dữ liệu tại thời điểm in, không tự cập nhật) |
| "Tem không phải tem thành phẩm chờ đóng gói" | Quét nhầm Tag No tem Đúc (TKD...) hoặc tem Kanban khác vào màn Ghi nhận thùng thành phẩm | Kiểm tra đúng màn hình — Kanban Đúc dùng `ghi-nhan-kanban.html`, thành phẩm dùng `ghi-nhan-tem-thanh-pham.html` |
| Danh mục sản phẩm hiện trống toàn bộ | Trang `quan-ly-danh-muc.html` đọc cột chưa được tạo (migration liên quan T40 chưa chạy) — lỗi PostgREST làm SẬP CẢ query, không riêng field mới | Chạy đủ migration theo đúng thứ tự ở đầu file này |
