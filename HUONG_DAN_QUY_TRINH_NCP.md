# Hướng dẫn quy trình xử lý NCP (SP không phù hợp)

Quy trình đầy đủ 1 phiếu NCP từ mở đến đóng, trên `qc-manager.html` (danh sách phiếu) và `ncp-detail.html` (chi tiết 1 phiếu — Nguyên nhân & Đối sách + Cách ly tem).

## 1. Mở phiếu — `qc-manager.html` (tab NCP)

Bấm **"+ Mở phiếu mới"**. Có 2 cách chọn nguồn:
- **Từ 1 lần IPQC NG** (radio "ng"): chọn trong danh sách các lần kiểm NG chưa gắn phiếu nào → tự điền sẵn máy/SP/mô tả lỗi.
- **Nhập tay**: tự chọn máy + mã SP.

Điền tiếp: số khuôn, mô tả lỗi, **số lượng nghi vấn**, **số lượng NG dự kiến** (tham khảo, ≤ số nghi vấn), **vị trí cách ly** (mô tả chỗ để hàng, dạng text tự do), người đảm nhiệm xử lý, người đảm nhiệm trả lời Nguyên nhân & Đối sách.

→ Tạo phiếu, trạng thái bắt đầu = `da_cach_ly`.

## 2. Cách ly tem/thùng hàng cụ thể — `ncp-detail.html`

Bấm **"📝 Đối sách"** trên dòng phiếu vừa mở → mở tab mới, panel đầu tiên **"🔒 Cách ly tem/thùng hàng"**:
- Bấm **"📷 Quét QR"** (mở camera) hoặc gõ tay Tag No vào ô bên cạnh → Enter, cho từng tem/thùng thuộc lô nghi vấn.
- Mỗi tem quét xong hiện ngay trong danh sách, và **ngay lập tức bị chặn** ở mọi nơi khác trong hệ thống: không chuyển công đoạn được, không dùng làm nguyên liệu đóng gói lại, không nhập/xuất kho được (kể cả khi đã đóng vào pallet).
- Có thể quay lại quét thêm tem bất cứ lúc nào trong suốt vòng đời phiếu.
- Tem bị tách (`duc_tach_tem`) trong lúc đang cách ly → tem con sinh ra tự động kế thừa cách ly theo cùng phiếu.

## 3. Lọc/phân loại — trạng thái `da_cach_ly` / `dang_loc`

Bấm **"Cập nhật"** trên qc-manager → nhập số lượng vừa lọc được **OK** / **NG** của đợt này. Có thể lọc nhiều đợt (cộng dồn), hệ thống tự tính trạng thái tiếp theo:
- Lọc chưa hết số nghi vấn → vẫn ở `dang_loc`, lọc tiếp.
- Lọc hết mà không còn NG tồn → **tự đóng phiếu** luôn.
- Lọc hết mà còn NG tồn → chuyển sang `cho_quyet_dinh`.

## 4. Quyết định phương án — trạng thái `cho_quyet_dinh`

Chọn 1 trong 2:
- **Sửa chữa**: nhập mô tả phương án sửa → chuyển `dang_sua`.
- **Báo phế**: nhập số lượng đề nghị phế + lý do → sinh số phiếu phế `PBP_...`, chuyển `cho_duyet_phe`.

## 5. Sửa chữa hoặc duyệt phế

- **`dang_sua`**: nhập kết quả — số **sửa OK** / **không sửa được**. Hệ thống tự tính lại: còn tồn NG → quay lại `cho_quyet_dinh` (báo phế phần còn lại hoặc sửa tiếp); hết tồn → tự đóng.
- **`cho_duyet_phe`**: người có thẩm quyền bấm **Duyệt**/**Từ chối** — Duyệt thì cộng vào số phế đã duyệt và tính lại trạng thái; Từ chối quay về `cho_quyet_dinh` để chọn phương án khác.

Vòng lặp **bước 4 ↔ 5** lặp lại đến khi toàn bộ số lượng NG đã lọc được xử lý hết (sửa OK hết hoặc phế đã duyệt hết) → **phiếu tự chuyển `dong`** — không có nút "Đóng phiếu" thủ công riêng, đây là hệ quả tự động.

## 6. Song song: Nguyên nhân & Đối sách (không phụ thuộc bước 3-5)

Vẫn trong `ncp-detail.html`: điền **Nguyên nhân phát sinh** + **Nguyên nhân lưu xuất** (kèm ảnh minh hoạ), thêm **đối sách tạm thời/lâu dài** cho từng loại nguyên nhân → **Lưu nháp** hoặc **Gửi phê duyệt** → người duyệt bấm Duyệt/Từ chối.

Có thể làm bất kỳ lúc nào, kể cả sau khi phiếu đã đóng — bấm **"🔓 Mở lại để chỉnh sửa"** nếu cần sửa sau khi đã duyệt.

## 7. Giải toả cách ly tem

**Phiếu đóng KHÔNG tự giải toả tem đã cách ly** (cố ý thiết kế vậy, tránh giải toả nhầm hàng chưa thực sự xử lý xong). Sau khi đã xử lý xong thực tế (đã sửa xong / đã phế xong) từng tem cụ thể, quay lại panel **"🔒 Cách ly tem/thùng hàng"** trong `ncp-detail.html`, bấm **"🔓 Giải toả"** trên từng dòng tem → tem đó mới được phép chuyển công đoạn/sản xuất tiếp bình thường trở lại.

Nếu tem đã bị tách khi đang cách ly, các tem con sinh ra cũng phải giải toả riêng từng tem con.

## Sơ đồ trạng thái phiếu (`trang_thai`)

```
da_cach_ly → dang_loc → cho_quyet_dinh ─┬→ dang_sua ─────┐
                              ▲          └→ cho_duyet_phe┤
                              └──────────────────────────┘
                                         (còn tồn NG, lặp lại)
                                                │
                                        hết tồn NG
                                                ▼
                                              dong
```

Cách ly tem (`duc_tem_cach_ly.trang_thai`: `dang_cach_ly` / `da_giai_toa`) là track **độc lập**, không nằm trong sơ đồ trên — phải tự tay giải toả từng tem, không tự động theo `trang_thai` của phiếu.
