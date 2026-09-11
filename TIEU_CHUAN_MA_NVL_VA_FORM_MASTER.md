# Tiêu chuẩn mã NVL & Biểu mẫu dữ liệu master — Kho NVL Toyotaki

> Mục đích: (1) thống nhất cách đặt mã nguyên vật liệu để **ai cũng tự thêm mã mới đúng quy tắc**;
> (2) cung cấp biểu mẫu để bộ phận kho/mua hàng/kỹ thuật **điền dữ liệu trước**, sau đó mới nhập hệ thống.
> Khi các biểu mẫu (`supabase/nvl_master_templates/*.csv`) đã điền xong → gửi lại để chốt schema + viết migration
> (chạy trên **cả production `fgghikpzcxjqzahfiiil` và staging `jcjbleugnclzsghfpmvk`**) + làm màn nhập liệu trong `nvl.html`.

---

## PHẦN 1 — TIÊU CHUẨN HOÁ MÃ NVL

### 1.1 Nguyên tắc chung

| # | Quy tắc | Lý do |
|---|---------|-------|
| 1 | Mã **cố định 11 ký tự**, dạng `A-BBB-CC-NNN` (có 2 dấu gạch nối). | Căn cột, kiểm tra tự động, sắp xếp đều nhau. |
| 2 | Chỉ dùng **chữ IN HOA A–Z, số 0–9 và dấu `-`**. Chữ viết tắt lấy từ **tiếng Việt bỏ dấu** cho công nhân dễ đọc. Không dấu tiếng Việt, không khoảng trắng, không ký tự khác. | Ai đọc cũng hiểu; tương thích mọi hệ thống, in tem, quét mã. |
| 3 | Mã chia **4 nhóm ký tự**, mỗi nhóm tra từ một bảng danh mục (Bảng 1/2/3) + 1 số thứ tự. | Mỗi nhóm có nghĩa rõ ràng, thêm mã mới = tra bảng. |
| 4 | **Không nhúng thông tin biến động** vào mã (giá, tên nhà cung cấp, vị trí kho, năm nhập). Những cái đó nằm ở **trường dữ liệu** (Phần 2). | Mã sống lâu dài, không phải đổi khi NCC/giá thay đổi. |
| 5 | Mã **đã cấp thì bất biến**. Vật tư ngừng dùng → đặt `active = FALSE`, **không xoá, không tái sử dụng** mã cho vật tư khác. | Giữ toàn vẹn lịch sử nhập/xuất/tồn. |
| 6 | Chỉ tách mã khác nhau khi **cần quản lý tồn riêng** (khác mác, khác quy cách, khác tiêu chuẩn chất lượng). Chỉ khác tên nhà cung cấp mà vật tư tương đương → **dùng chung 1 mã**. | Tránh nở mã vô ích. |

### 1.2 Cấu trúc mã: `A-BBB-CC-NNN`

```
 A  -  B B B  -  C C  -  N N N
 |       |        |        +-- So thu tu 001-999 trong cung nhom (A-BBB-CC)
 |       |        +-- Bien the / mac / quy cach (Bang 3); "00" neu khong can phan biet
 |       +-- Loai chi tiet (Bang 2) - 3 chu viet tat tieng Viet bo dau
 +-- Nhom vat lieu (Bang 1) - 1 chu, chu cai dau cua ten nhom
```

Ví dụ: `K-NHN-12-001` = **K** Kim loại nạp lò · **NHN** NHôm Nguyên sinh · **12** mác ADC12 · **001** mã đầu tiên.

### 1.3 Bảng 1 — Nhóm vật liệu (ký tự **A**)

| A | Nhóm vật liệu | Viết tắt từ | Đơn vị hay dùng | Phạm vi |
|---|---------------|-------------|-----------------|---------|
| `K` | Kim loại nạp lò (nhôm, kẽm, hợp kim trung gian, hồi liệu) | **K**im loại | kg | Vật liệu chính đưa vào lò/máy đúc |
| `H` | Hoá chất & vật tư tiêu hao đúc | **H**oá chất | kg, L, can | Trợ dung, khử khí, sơn khuôn, dầu, mỡ, hoá chất vệ sinh |
| `P` | Phụ tùng tiêu hao gắn máy đúc | **P**hụ tùng | pcs, bộ | Đầu pít-tông, ống rót, béc phun, lõi lọc, gioăng phớt |
| `C` | Chi tiết chèn/lắp vào sản phẩm (insert) | **C**hi tiết | pcs | Bạc, ốc cấy, chốt… (đơn vị đếm chiếc) |
| `S` | Vật tư công đoạn sơn | **S**ơn | kg, L | Bột sơn, sơn nước, hoá chất tiền xử lý, vật tư che chắn |
| `D` | Vật tư đóng gói | **Đ**óng gói (bỏ dấu → D) | pcs, cuộn | Thùng, pallet, xốp, túi, dây đai |
| `X` | Chưa phân loại / dự phòng | — | — | **Chỉ dùng tạm** khi chưa thống nhất nhóm; phải chuyển sang nhóm thật sau |

> Cần thêm nhóm mới (VD vật tư kho NVL cho Gia công CNC) → người quản lý danh mục cấp 1 chữ cái mới và cập nhật bảng này.

### 1.4 Bảng 2 — Loại chi tiết (ký tự **BBB**) theo từng nhóm

**Nhóm `K` — Kim loại nạp lò**

| BBB | Viết tắt từ | Nghĩa |
|-----|-------------|-------|
| `NHN` | NHôm Nguyên sinh | Nhôm hợp kim **nguyên sinh** (thỏi mua ngoài) |
| `NHH` | NHôm Hồi liệu | Nhôm **hồi liệu nội bộ** (đậu ngót, gate, sản phẩm NG nấu lại) |
| `NHP` | NHôm Phế | Nhôm **phế/vụn mua ngoài** |
| `HKN` | Hợp Kim Nhôm | **Hợp kim trung gian** nền nhôm (biến tính, tinh hạt) |
| `KEN` | KẼm Nguyên sinh | Kẽm hợp kim **nguyên sinh** |
| `KEH` | KẼm Hồi liệu | Kẽm **hồi liệu nội bộ** |
| `HKK` | Hợp Kim Kẽm | Hợp kim trung gian nền kẽm |

**Nhóm `H` — Hoá chất & tiêu hao đúc**

| BBB | Viết tắt từ | Nghĩa |
|-----|-------------|-------|
| `TDU` | Trợ DUng | Trợ dung / chất khử xỉ, phủ bề mặt |
| `KKH` | Khử KHí | Chất khử khí (viên, khí trơ đóng chai) |
| `BTH` | Biến Tính Hạt | Chất biến tính / tinh hạt mua riêng |
| `STK` | Sơn Tách Khuôn | Sơn khuôn / chất tách khuôn |
| `BTP` | Bôi Trơn Pít-tông | Bôi trơn pít-tông (hạt/bột/lỏng) |
| `DTL` | Dầu Thủy Lực | Dầu thuỷ lực |
| `DLM` | Dầu Làm Mát | Dung dịch / dầu làm mát – giải nhiệt khuôn |
| `MOB` | MỠ Bôi trơn | Mỡ bôi trơn |
| `VSK` | Vệ Sinh Khuôn | Hoá chất vệ sinh khuôn/máy |

**Nhóm `P` — Phụ tùng tiêu hao máy đúc**

| BBB | Viết tắt từ | Nghĩa |
|-----|-------------|-------|
| `DPT` | Đầu Pít-Tông | Đầu pít-tông (plunger tip) |
| `ORO` | Ống RÓt | Ống rót / shot sleeve |
| `BEC` | BÉC phun | Béc / đầu phun sơn khuôn |
| `LOC` | LỌC | Lõi lọc / tấm lọc kim loại lỏng |
| `GIO` | GIOăng | Gioăng, phớt, ống dẫn tiêu hao |
| `PTK` | Phụ Tùng Khác | Phụ tùng tiêu hao khác |

**Nhóm `C` — Chi tiết chèn/lắp (insert)**

| BBB | Viết tắt từ | Nghĩa |
|-----|-------------|-------|
| `BAC` | BẠC | Bạc / bushing chèn khuôn |
| `OCC` | ỐC Cấy | Đai ốc cấy (insert nut) |
| `BLC` | Bu Lông Cấy | Bu lông / vít cấy (stud) |
| `CHO` | CHỐt | Chốt / pin |
| `KEP` | KẸP | Kẹp / clip |
| `CTK` | Chi Tiết Khác | Chi tiết chèn khác |

**Nhóm `S` — Vật tư sơn**

| BBB | Viết tắt từ | Nghĩa |
|-----|-------------|-------|
| `BOT` | BỘT sơn | Bột sơn tĩnh điện |
| `SNU` | Sơn NƯớc | Sơn nước / sơn dung môi |
| `TXL` | Tiền Xử Lý | Hoá chất tiền xử lý (tẩy dầu, phốt phát…) |
| `CHE` | CHE chắn | Vật tư che chắn khi sơn (băng keo chịu nhiệt, nút chụp) |
| `DMP` | Dung Môi Pha | Dung môi pha / chất pha loãng |

**Nhóm `D` — Đóng gói**

| BBB | Viết tắt từ | Nghĩa |
|-----|-------------|-------|
| `THU` | THÙng | Thùng carton |
| `PAL` | PA-Lét | Pallet |
| `XOP` | XỐP | Xốp / mút chèn |
| `TUI` | TÚI | Túi PE / màng |
| `DAI` | dây ĐAI | Dây đai / màng quấn / nẹp góc |

> Không tìm thấy loại phù hợp → **đề xuất mã 3 chữ viết tắt tiếng Việt mới** (bỏ dấu, gợi nhớ, chưa trùng), gửi người quản lý danh mục duyệt, cập nhật bảng này **trước khi** dùng.

### 1.5 Bảng 3 — Biến thể / mác / quy cách (ký tự **CC**)

- 2 ký tự `[A–Z0–9]`. Dùng `00` khi trong nhóm `A-BBB` **không cần phân biệt** biến thể.
- Ưu tiên lấy theo **mác kỹ thuật quốc tế** (công nhân đã quen con số) hoặc **viết tắt tiếng Việt bỏ dấu**. Ghi mác đầy đủ ở trường `mac_hop_kim` và `ten_nvl`.

| Nhóm A-BBB | CC gợi ý |
|------------|----------|
| `K-NHN` | `12`=ADC12, `10`=ADC10, `4B`=AC4B, `56`=A356, `S9`=AlSi9 |
| `K-KEN` | `Z3`=Zamak 3 (ZDC1), `Z5`=Zamak 5 (ZDC2), `ZA`=ZA-8 |
| `K-HKN` | `ST`=Stronti (AlSr), `TB`=Titan-Bo (AlTiB), `MN`=Mangan, `DO`=Đồng, `SA`=Sắt |
| `H-DTL` | `32` / `46` / `68` theo cấp độ nhớt ISO VG |
| `H-STK`, `H-TDU`, `H-BTP` | `00` nếu 1 loại; `0A`, `0B`, `0C` nếu nhiều loại / nhiều nhà cung cấp cần tách tồn |
| `C-BAC`, `C-BLC`, `C-OCC` | `00` chung; hoặc `08`,`10`,`12` theo đường kính (mm); `M6`,`M8` theo cỡ ren |
| `S-BOT` | màu rút gọn tiếng Việt: `DE`=đen, `TR`=trắng, `BA`=bạc, `XA`=xám (mã màu đầy đủ ghi ở `ten_nvl`) |

### 1.6 Số thứ tự (NNN)

- `001`–`999`, cấp **tuần tự trong phạm vi cùng `A-BBB-CC`**.
- Lấy **số lớn nhất đang có + 1**. Không lấp chỗ trống của mã đã ngừng dùng.
- Gần hết `999` cho một nhóm → mở biến thể `CC` mới thay vì phá quy tắc.

### 1.7 Quy trình thêm mã mới

1. Xác định **Nhóm `A`** — Bảng 1.
2. Xác định **Loại chi tiết `BBB`** — Bảng 2 theo nhóm. Chưa có → đề xuất mã 3 chữ viết tắt tiếng Việt mới cho người quản lý danh mục duyệt.
3. Xác định **Biến thể `CC`** — Bảng 3. Không cần phân biệt → `00`.
4. **`NNN`** = số kế tiếp chưa dùng trong nhóm `A-BBB-CC` (tra danh mục hiện hành).
5. Điền đủ 1 dòng vào biểu mẫu **`nvl_materials`** + (nếu cần) **`nvl_cai_dat`**, **`nvl_dinh_muc`**.
6. **Người quản lý danh mục** kiểm tra trùng lặp / nhầm nhóm rồi mới nhập hệ thống.

**Ai được làm gì:** bất kỳ ai (thủ kho, mua hàng, kỹ thuật) được **đề xuất** mã mới theo quy tắc trên.
Chỉ **người quản lý danh mục** — đề xuất: *1 thủ kho chính + 1 kỹ thuật đúc* — mới **xác nhận đưa vào hệ thống** và cập nhật Bảng 2/Bảng 3.

### 1.8 Ví dụ minh hoạ

| Mã | Diễn giải |
|----|-----------|
| `K-NHN-12-001` | Nhôm hợp kim nguyên sinh, mác ADC12 — mã đầu tiên |
| `K-NHN-12-002` | Cũng ADC12 nhưng **quy cách/tiêu chuẩn khác cần tách tồn riêng** |
| `K-NHH-00-001` | Nhôm hồi liệu nội bộ (đậu ngót/gate/NG nấu lại), không phân biệt biến thể |
| `K-KEN-Z5-001` | Kẽm hợp kim nguyên sinh Zamak 5 (ZDC2) |
| `K-HKN-ST-001` | Hợp kim trung gian nền nhôm – Stronti (biến tính) |
| `H-STK-0A-001` | Sơn khuôn / chất tách khuôn loại A |
| `H-DTL-46-001` | Dầu thuỷ lực ISO VG46 |
| `P-DPT-00-001` | Đầu pít-tông máy đúc (phụ tùng tiêu hao) |
| `C-BAC-08-001` | Bạc chèn khuôn Ø8 mm |
| `S-BOT-DE-001` | Bột sơn tĩnh điện màu đen |
| `D-THU-00-001` | Thùng carton tiêu chuẩn |

### 1.9 KHÔNG được làm

- ❌ Dấu tiếng Việt, khoảng trắng, ký tự ngoài `A–Z 0–9 -`. Viết tắt phải **bỏ dấu**.
- ❌ Nhét giá / tên NCC / vị trí kho / năm vào mã.
- ❌ Sửa mã đã phát sinh; tái sử dụng mã cũ cho vật tư khác.
- ❌ Tạo 2 mã cho cùng một vật tư chỉ vì khác nhà cung cấp (khi mác + quy cách y hệt).
- ❌ Để mã ở nhóm `X` lâu dài.

---

## PHẦN 2 — BIỂU MẪU DỮ LIỆU MASTER

4 file để điền, trong `supabase/nvl_master_templates/`. **3 dòng đầu mỗi file là ví dụ — xoá trước khi nhập thật.**
Cột `active` điền `TRUE`/`FALSE`. Ngày điền dạng `YYYY-MM-DD`. Số thập phân dùng dấu chấm.

### 2.1 `1_nvl_materials.csv` — Danh mục NVL (bảng chính)

| Trường | Bắt buộc | Kiểu | Ý nghĩa & cách điền |
|--------|:---:|------|--------------------|
| `ma_nvl` | ✔ | text | Mã theo Phần 1 (`A-BBB-CC-NNN`). Khoá chính, duy nhất. |
| `ten_nvl` | ✔ | text | Tên mô tả đầy đủ: loại + mác + quy cách. VD *"Nhôm hợp kim ADC12 thỏi 10kg"*. |
| `nhom_vl` | ✔ | chọn | Nhóm đọc-được, chọn từ danh sách 2.5. Phải khớp ý nghĩa ký tự `A` của mã. |
| `mac_hop_kim` | nên | text | Mác kỹ thuật: `ADC12`, `ZDC2`, `AlSr10`, `ISO VG46`… Để trống nếu không có. |
| `don_vi_kho` | ✔ | chọn | Đơn vị tồn kho chuẩn: `kg`, `pcs`, `L`, `m`, `cuộn`, `bộ`, `can`, `thùng`. |
| `bo_phan_su_dung` | ✔ | chọn | `Đúc` / `Sơn` / `Gia công CNC` / `Đóng gói` / `Chung`. Mặc định `Đúc`. |
| `nha_cung_cap_chinh` | nên | text | Tên nhà cung cấp chính (text tự do; sẽ thay bằng mã ERP sau). |
| `ma_vat_tu_ncc` | tuỳ chọn | text | Mã / part-no phía nhà cung cấp để đối chiếu chứng từ. |
| `lead_time_ngay` | nên | số nguyên | Số ngày từ lúc đặt đến lúc nhận hàng. Dùng để tính điểm đặt hàng. |
| `moq_kg` | nên | số | Lượng đặt tối thiểu, theo `don_vi_kho`. |
| `don_gia_tham_khao` | nên | số | Đơn giá gần nhất cho 1 `don_vi_kho`. Để ước tính giá trị tồn. |
| `tien_te` | nên | chọn | `VND` / `USD` / `JPY`. Bắt buộc nếu có `don_gia_tham_khao`. |
| `vi_tri_luu_kho` | nên | text | Khu / kệ. VD `A-01`, `Kho hoá chất`. |
| `active` | ✔ | TRUE/FALSE | `TRUE` = đang dùng; `FALSE` = ngừng dùng (giữ dòng, giữ lịch sử). |
| `ghi_chu` | tuỳ chọn | text | Ghi chú tự do (NCC phụ, lưu ý bảo quản…). |

### 2.2 `2_nvl_cai_dat.csv` — Ngưỡng kiểm soát tồn

> Giữ **song song** hai chỉ số theo yêu cầu — chúng khác nghĩa nhau:

| Trường | Bắt buộc | Kiểu | Ý nghĩa & cách điền |
|--------|:---:|------|--------------------|
| `ma_nvl` | ✔ | text | Khớp `nvl_materials`. |
| `ton_toi_thieu_kg` | ✔ | số | **Mức sàn tuyệt đối.** Chạm/dưới mức này → cảnh báo đỏ, đặt hàng gấp. |
| `ton_an_toan_kg` | nên | số | **Tồn dự phòng (safety stock)** cho dao động tiêu hao trong thời gian chờ hàng. Điểm đặt hàng thực tế ≈ `ton_an_toan_kg` + (tiêu hao bình quân ngày × `lead_time_ngay`). |
| `ton_muc_tieu_kg` | nên | số | **Mức tồn mục tiêu** — tâm của dải kiểm soát (dùng cùng `be_rong_kg`). |
| `ton_toi_da_kg` | tuỳ chọn | số | **Mức trần.** Không nhập vượt (giới hạn vốn / không gian). Để trống nếu không giới hạn. |
| `be_rong_kg` | ✔ | số | **Nửa bề rộng dải kiểm soát** quanh `ton_muc_tieu_kg`. Giới hạn trên/dưới = mục tiêu ± bề rộng (giữ đúng ý nghĩa USL/LSL của hệ cũ). **Khác** `ton_toi_thieu_kg`. |
| `ghi_chu` | tuỳ chọn | text | |

### 2.3 `3_nvl_ton_dau_ky.csv` — Tồn đầu kỳ (khởi động số liệu)

| Trường | Bắt buộc | Kiểu | Ý nghĩa & cách điền |
|--------|:---:|------|--------------------|
| `ma_nvl` | ✔ | text | Khớp `nvl_materials`. |
| `ngay_dau_ky` | ✔ | ngày | Ngày chốt tồn để bắt đầu theo dõi trên hệ thống. VD `2026-10-01`. |
| `ton_dau_ky_kg` | ✔ | số | Số lượng **thực kiểm** tại ngày đầu kỳ, theo `don_vi_kho`. |

### 2.4 `4_nvl_dinh_muc.csv` — Định mức tiêu hao (BOM)

> Lượng NVL tiêu hao chuẩn để làm ra sản phẩm / mẻ / ca. Cho phép **đổi định mức theo thời gian** bằng `hieu_luc_tu`.

| Trường | Bắt buộc | Kiểu | Ý nghĩa & cách điền |
|--------|:---:|------|--------------------|
| `ma_sp` | tuỳ chọn | text | Mã sản phẩm đúc (khớp mã SP đang dùng ở khối Đúc). **Để trống** nếu là định mức phụ liệu dùng chung không theo SP. |
| `ma_nvl` | ✔ | text | Khớp `nvl_materials`. |
| `luong_dinh_muc` | ✔ | số | Lượng NVL tiêu hao (theo `co_so_tinh`). |
| `don_vi_dinh_muc` | ✔ | chọn | Đơn vị của `luong_dinh_muc`: `kg` / `pcs` / `L`. Thường trùng `don_vi_kho`. |
| `co_so_tinh` | ✔ | chọn | Mẫu số: `/SP`, `/1000SP`, `/tan_kim_loai`, `/me`, `/ca`, `/shot`. |
| `ty_le_hao_hut_pct` | tuỳ chọn | số | % cộng thêm cho hao hụt (đậu ngót, NG nấu lại, rơi vãi, bay hơi) **nếu chưa gộp** vào `luong_dinh_muc`. |
| `hieu_luc_tu` | ✔ | ngày | Ngày bắt đầu áp dụng định mức này. Bản mới có hiệu lực từ ngày sau. |
| `active` | ✔ | TRUE/FALSE | |
| `ghi_chu` | tuỳ chọn | text | |

### 2.5 Danh sách giá trị hợp lệ (dùng chung)

| Trường | Giá trị hợp lệ |
|--------|----------------|
| `nhom_vl` | Nhôm nguyên sinh · Nhôm hồi liệu · Nhôm phế mua ngoài · Hợp kim trung gian nhôm · Kẽm nguyên sinh · Kẽm hồi liệu · Hợp kim trung gian kẽm · Hoá chất đúc · Tiêu hao đúc · Phụ tùng máy đúc · Chi tiết chèn/lắp · Vật tư sơn · Vật tư đóng gói · Khác |
| `don_vi_kho` / `don_vi_dinh_muc` | kg · pcs · L · m · cuộn · bộ · can · thùng |
| `bo_phan_su_dung` | Đúc · Sơn · Gia công CNC · Đóng gói · Chung |
| `tien_te` | VND · USD · JPY |
| `co_so_tinh` | /SP · /1000SP · /tan_kim_loai · /me · /ca · /shot |
| `active` | TRUE · FALSE |

---

## PHẦN 3 — BƯỚC TIẾP THEO (sau khi điền xong biểu mẫu)

1. Bạn gửi lại 4 file CSV đã điền.
2. Chốt schema: thêm cột nhóm A+B vào `nvl_materials`; mở rộng `nvl_cai_dat` (thêm `ton_an_toan_kg`, `ton_muc_tieu_kg`, `ton_toi_da_kg`); tạo bảng mới `nvl_dinh_muc`.
3. Viết migration `supabase/migration_nvl_step2_master.sql` + script import → chạy trên **cả production và staging**.
4. Bổ sung màn nhập/sửa các trường mới trong `nvl.html` (theo pattern header/token của `duc-dashboard.html`).
5. Ban hành Phần 1 làm quy định nội bộ cho việc cấp mã NVL.
