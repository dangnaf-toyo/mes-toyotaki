-- ============================================================================
-- Phase T48 — Tồn kho theo mã SP, chia theo từng công đoạn của lưu trình sản
-- xuất mã đó (Đúc/Đánh bóng/Gia Công/OQC/Nhập kho/...). Dùng cho ô "Mã sản
-- phẩm đang sản xuất" mới ở ghi-nhan-tem-thanh-pham.html.
--
-- Cách tính: với mỗi tem còn hàng (duc_tem.so_luong > 0) của mã SP đó, vị
-- trí hiện tại = công đoạn nhận của lượt Chuyển công đoạn gần nhất
-- (cd_v_vi_tri_hien_tai) — tem CHƯA từng chuyển công đoạn nào coi như còn ở
-- "Đúc" (nơi sinh ra tem). Gộp theo vị trí, trả về (công đoạn, tổng SL).
-- Việc sắp xếp đúng thứ tự lưu trình + điền 0 cho công đoạn chưa có hàng do
-- client tự làm dựa trên master_products.quy_trinh_cong_doan.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create or replace function cd_ton_kho_theo_ma_sp(p_ma_sp text)
returns table(cong_doan text, so_luong numeric)
language sql
stable
as $$
  select coalesce(v.vi_tri_hien_tai, 'Đúc') as cong_doan, sum(t.so_luong) as so_luong
  from duc_tem t
  left join cd_v_vi_tri_hien_tai v on v.tag_no = t.tag_no
  where t.ma_sp = p_ma_sp and coalesce(t.so_luong, 0) > 0
  group by coalesce(v.vi_tri_hien_tai, 'Đúc');
$$;

revoke execute on function cd_ton_kho_theo_ma_sp(text) from anon;
grant execute on function cd_ton_kho_theo_ma_sp(text) to authenticated;
