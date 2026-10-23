# T154 — CL tạm thời cho P-Chart NG OQC (23/10/2026)

**Nơi lưu:** bảng `oqc_ng_cau_hinh` (DB PROD `fgghikpzcxjqzahfiiil`), cột `cl` (dạng tỷ lệ).
Người đặt ghi là `Tự động T154 (IQR)`. Mỗi lần đổi đều có dòng trong `oqc_ng_cau_hinh_log` (giá trị cũ → mới + lý do).
DB staging chỉ có 5 phiếu thử nên **không** đặt.

## Quy tắc (theo yêu cầu QC Manager)

CL tạm thời = NG% trung bình của **toàn bộ dữ liệu** của mã, **sau khi loại các ngày bất thường**.

1. Dữ liệu: `oqc_daily_inspection` từ phiếu đầu tiên (10/06/2026) đến 22/10/2026, `total_qty > 0`.
   - Mã sau Sơn: chỉ lấy **Lần sơn 1** (hàng sơn mới) — giống mặc định của P-Chart. Hàng sơn lại (lần 2+) có NG% cao hơn nhiều, không đưa vào CL.
   - Mỗi mã hiện chỉ thuộc một phạm vi (Sau gia công hoặc Sau Sơn) nên không bị lẫn dữ liệu giữa các phạm vi.
2. Gộp theo **ngày** (giống điểm trên P-Chart): NG% ngày = ΣNG / ΣSL kiểm trong ngày.
3. Ngày bất thường = NG% ngày nằm ngoài khoảng **[Q1 − 1,5·IQR ; Q3 + 1,5·IQR]** (quy tắc Tukey; IQR = Q3 − Q1 của NG% các ngày).
4. CL = ΣNG / ΣSL của các ngày còn lại (trung bình có trọng số theo SL, không phải trung bình các %).

**Vì sao không loại theo UCL 3σ của P-Chart:** đã thử lặp 3 lần. Dữ liệu dao động giữa các ngày lớn hơn nhiều so với lý thuyết nhị thức
(SL/ngày ~1.000 pcs → giới hạn rất hẹp), nên cách đó loại 30–50% số ngày (VD EXE-CEN-01 chỉ giữ 59/101 ngày) và kéo CL xuống thấp sai.
IQR chỉ loại các ngày thật sự lệch hẳn.

## Kết quả

| Mã | Số ngày | Loại | CL tạm thời | CL cũ | Ghi chú |
|---|---:|---:|---:|---:|---|
| BPH-SHO-01 | 1 | 0 | 1,07% | 1,10% | ít dữ liệu |
| BPH-SHO-02 | 2 | 0 | 0,66% | 0,70% | ít dữ liệu |
| BPH-SHO-03 | 1 | 0 | 0,08% | 0,10% | ít dữ liệu |
| COS-GZ5-01 | 1 | 0 | 2,29% | — | ít dữ liệu |
| EXE-CEN-01 | 101 | 2 | 4,32% | 3,50% | loại 07/08 (12,2%), 21/08 (13,5%) |
| EXE-OUT-01 | 94 | 6 | 1,58% | 2,30% | loại 10/07, 18/08, 10/09, 29/09, 02/10, 22/10 (5,5–10%) |
| EXE-PLT-01 | 100 | 2 | 2,94% | 3,30% | loại 22/07 (23,1%), 06/08 (9,4%) |
| IWT-118-01 | 2 | 0 | 20,26% | — | ít dữ liệu |
| IWT-119-01 | 2 | 0 | 32,57% | — | ít dữ liệu |
| MIK-389-01 | 5 | 0 | 9,91% | 3,00% | |
| MIK-389-02 | 8 | 0 | 18,42% | — | |
| MIK-398-01 | 5 | 2 | 0,99% | — | |
| MIK-399-01 | 6 | 0 | 2,09% | — | |
| OKA-GJT-01 | 3 | 0 | 27,05% | — | Sơn lần 1; ít dữ liệu |
| OKA-GJT-02 | 6 | 1 | 20,00% | — | Sơn lần 1; loại 16/07 (86,4%) |
| OKA-GJT-03 | 16 | 0 | 33,39% | — | Sơn lần 1 |
| OKA-GJT-04 | 22 | 1 | 22,51% | — | Sơn lần 1; loại 08/09 (78,9%) |
| OKA-GJT-05 | 21 | 1 | 27,34% | — | Sơn lần 1; loại 27/07 (100%) |
| OKA-GJT-06 | 15 | 2 | 31,67% | — | Sơn lần 1; loại 01/07, 16/07 |
| OKA-GJT-07 | 5 | 0 | 20,00% | — | Sơn lần 1 |
| OKA-GJT-08 | 11 | 0 | 36,78% | — | Sơn lần 1 |
| OKA-GMN-01 | 12 | 0 | 30,05% | — | Sơn lần 1 |
| OKA-GMN-02 | 12 | 0 | 20,81% | — | Sơn lần 1 |
| OKA-GMN-03 | 7 | 1 | 20,56% | — | Sơn lần 1; loại 30/09 (56,1%) |
| OKA-GMN-06 | 8 | 1 | 29,66% | — | Sơn lần 1; loại 21/09 (89,4%) |
| OKA-GWI-01 | 10 | 1 | 23,08% | — | Sơn lần 1; loại 07/10 (64,3%) |
| OKA-GWI-02 | 14 | 1 | 29,40% | — | Sơn lần 1; loại 27/08 (100%) |
| OKA-GWI-03 | 14 | 1 | 22,35% | — | Sơn lần 1; loại 11/10 (90%) |
| OKA-GWI-04 | 17 | 1 | 22,87% | — | Sơn lần 1; loại 05/08 (78,4%) |
| OKA-GWI-05 | 11 | 1 | 21,12% | — | Sơn lần 1; loại 13/08 (69,2%) |
| OKA-GWI-06 | 13 | 3 | 15,22% | — | Sơn lần 1; loại 18/08, 22/08, 18/09 |
| PRE-W99-01 | 1 | 0 | 8,68% | — | ít dữ liệu |
| TTI-MOT-01 | 19 | 0 | 8,50% | — | |
| TTI-MOT-02 | 71 | 2 | 2,60% | — | loại 02/07 (8,9%), 09/07 (9,2%) |
| TTI-MOT-03 | 9 | 2 | 5,70% | — | loại 29/08 (1,0%), 05/10 (12,4%) |
| TTI-MOT-04 | 23 | 0 | 4,09% | — | |
| TTI-MOT-05 | 77 | 3 | 5,80% | — | loại 25/08, 27/08, 03/09 (20–26%) |
| TTI-PUM-01 | 20 | 2 | 6,46% | — | loại 28/07 (54,1%), 01/08 (62,7%) |
| TTI-PUM-02 | 11 | 2 | 4,29% | — | loại 27/08 (44%), 16/09 (50,7%) |
| TTI-PUM-03 | 18 | 0 | 18,28% | — | |

**Chưa đặt được (3 mã):** `TTI-PUM-011`, `TTI-PUM-021`, `TTI-PUM-031` — có phiếu OQC nhưng **không có trong danh mục sản phẩm** (`master_products`).
Cần kiểm tra mã nhập sai hay thiếu trong danh mục; thêm vào danh mục rồi đặt CL bằng nút "Đặt CL".

## Cần theo dõi

- **Mã ít dữ liệu (< 5 ngày):** BPH-SHO-01/02/03, COS-GZ5-01, IWT-118-01, IWT-119-01, OKA-GJT-01, PRE-W99-01 — 1–3 ngày, chưa đủ để loại bất thường; CL chỉ là số tham khảo. Đặt lại khi đủ ~20 ngày kiểm.
- **CL phản ánh mức NG hiện có, không phải mức mong muốn.** Các mã NG cao (Sơn OKA 20–37%, MIK-389-02 18%, TTI-PUM-03 18%) sẽ có UCL cao → P-Chart chỉ bắt được ngày tệ đột biến; so với mục tiêu NG (mặc định 3%) để thấy khoảng cách.
- **TTI-PUM-01:** từ 01/10 NG gần 0% (trước đó 30–60%) — quá trình đã thay đổi; nên đặt lại CL chỉ theo dữ liệu từ 10/2026 khi đủ ngày.
- **TTI-MOT-05:** NG tăng mạnh từ 11/08 (5–20%) so với 07/2026 (~1–3%) — CL 5,80% là trộn hai giai đoạn.
- **Đặt lại định kỳ:** khi một mã có ≥ 20–25 ngày ổn định sau cải tiến, đặt lại CL (nút "Đặt lại" trong "🔒 CL & mục tiêu", bắt buộc ghi lý do; lịch sử nằm ở `oqc_ng_cau_hinh_log`).
- Mã mới chưa có CL: dùng cùng quy tắc trên (có thể chạy lại câu SQL trong mục dưới, chỉ cho mã đó).

## SQL đã chạy (để chạy lại / kiểm tra)

```sql
with r as (
  select d.*, c.inspection_scope sc, c.lan_son
  from oqc_daily_inspection d
  left join oqc_inspection_context c on c.inspection_id = d.id
       and c.source_date = d.inspection_date and c.source_product_code = d.product_code
  where d.total_qty > 0 and (c.inspection_scope is null or coalesce(c.lan_son, 1) = 1)),
dd as (select product_code ma, inspection_date d, sum(total_qty)::numeric n, sum(ng_qty)::numeric ng,
              sum(ng_qty)::numeric / sum(total_qty) p from r group by 1, 2),
q as (select ma, percentile_cont(0.25) within group (order by p) q1,
             percentile_cont(0.75) within group (order by p) q3 from dd group by 1),
f as (select dd.*, q.q1 - 1.5 * (q.q3 - q.q1) lo, q.q3 + 1.5 * (q.q3 - q.q1) hi from dd join q using (ma))
select ma, round(sum(ng) filter (where p between lo and hi) / sum(n) filter (where p between lo and hi), 4) cl
from f group by ma;
```
