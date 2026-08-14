-- ============================================================================
-- Giai đoạn 3 (bỏ Google) — Chuyển công đoạn: khoá RPC ghi cho user chưa đăng nhập.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
--
-- LƯU Ý QUAN TRỌNG (áp dụng cho MỌI RPC SECURITY DEFINER đã viết từ trước):
-- RPC khai báo `security definer` chạy với quyền của người tạo hàm (qua SQL
-- Editor = quyền cao nhất), nên nó BỎ QUA RLS của bảng gốc — RLS "authenticated
-- write" đã thêm ở các bảng KHÔNG có tác dụng chặn nếu ghi qua RPC này. Phải
-- tự khoá quyền EXECUTE của role `anon` trên chính hàm RPC mới chặn được
-- user chưa đăng nhập gọi thẳng từ trình duyệt.
-- ============================================================================

revoke execute on function cd_ghi_chuyen_cong_doan(
  text, text, text, numeric, numeric, text, text, text, text, text, text, text, text, text
) from anon;
grant execute on function cd_ghi_chuyen_cong_doan(
  text, text, text, numeric, numeric, text, text, text, text, text, text, text, text, text
) to authenticated;

revoke execute on function cd_xac_nhan_chuyen(text, text, text) from anon;
grant execute on function cd_xac_nhan_chuyen(text, text, text) to authenticated;
