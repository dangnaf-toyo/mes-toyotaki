-- ============================================================================
-- Giai đoạn 18 — Dọn checkpoint IPQC tồn đọng ("cho_kiem" mãi không ai kiểm).
--
-- Điều tra 2026-08-19: hệ thống có 63 checkpoint đang "cho_kiem", trong đó
-- 48 checkpoint thuộc về (ngay, ca) ĐÃ ĐƯỢC "Kết ca" từ lâu (có bản ghi
-- trong duc_bao_cao_ca) — ca sản xuất đó đã đóng sổ, kiểm tra không còn ý
-- nghĩa nữa (SP đã xuất/nhập kho hoặc chuyển công đoạn từ lâu) nhưng dòng
-- checkpoint bị bỏ quên ở trạng thái "cho_kiem" vĩnh viễn, không ai xoá.
--
-- Sửa: đánh dấu "het_hieu_luc" (không phải xoá — vẫn giữ lại để tra cứu/đối
-- chiếu sau này) cho MỌI checkpoint cho_kiem mà (ngay, ca) của nó đã có
-- trong duc_bao_cao_ca. An toàn: những checkpoint mà (ngay, ca) CHƯA kết ca
-- (dòng có thể vẫn thật sự đang chạy) KHÔNG bị đụng tới — xem ghi chú cuối
-- file về 15 checkpoint còn lại (đa số thuộc máy chưa từng được "Kết ca" kể
-- từ 17/08, cần trưởng ca xử lý kết ca bù trước, không tự ý xoá).
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent) —
-- lần sau chạy lại chỉ dọn thêm các checkpoint MỚI phát sinh tồn đọng.
-- ============================================================================

update duc_ipqc_checkpoint cp
set trang_thai = 'het_hieu_luc'
where cp.trang_thai = 'cho_kiem'
  and exists (
    select 1 from duc_bao_cao_ca bc where bc.ngay = cp.ngay and bc.ca = cp.ca
  );

-- ── Ghi chú: các checkpoint KHÔNG bị đụng tới ──────────────────────────────
-- Sau khi chạy, vẫn còn khoảng 14-15 checkpoint "cho_kiem" thuộc (ngay, ca)
-- CHƯA từng "Kết ca" — chủ yếu là (2026-08-17, "Ca ngày") của nhiều máy
-- (DC3/4/5/6/7/8/10/Kẽm190T) và (2026-08-14, "Ca ngày") của DC3. Đây là dấu
-- hiệu các máy này chưa từng được trưởng ca bấm "Kết ca" cho ca ngày/đêm kể
-- từ hôm đó — dòng sản xuất bị coi là "vẫn đang chạy" liên tục nhiều ngày,
-- kéo theo IPQC không bao giờ dọn được các checkpoint này tự động.
-- KHÔNG tự động "het_hieu_luc" các dòng này ở migration này vì dòng có thể
-- vẫn đang thực sự sản xuất (đã xác nhận với máy DC 8) — cần trưởng ca bấm
-- "Kết ca" (bù, chọn đúng ngày/ca) trên bao-cao-ca.html trước, sau đó chạy
-- lại chính file migration này (idempotent) để dọn nốt.
