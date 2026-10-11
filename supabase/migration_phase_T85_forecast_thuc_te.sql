-- ============================================================================
-- T85 — Thực tế so với forecast (forecast-san-luong.html, mục "Thực tế vs Forecast").
--
-- Thực tế = sản lượng Đúc OK đã kết ca (duc_lich_su_san_xuat.tt_ca), gộp theo
-- mã SP × tháng của năm. Đây là nguồn thực tế theo mã duy nhất hiện có (phiếu
-- xuất kho kho_phieu_xuat chưa dùng) — khi xuất hàng đi vào sử dụng có thể đổi
-- sang số giao hàng.
--
-- Chạy trên CẢ 2 project (production + staging). Idempotent. Chạy sau T83.
-- ============================================================================

create or replace function forecast_thuc_te_duc(p_nam int)
returns table (ma_sp text, thang int, so_luong numeric, so_ng numeric)
language sql
stable
set search_path = public
as $$
  select trim(ma_sp), extract(month from ngay)::int, sum(coalesce(tt_ca, 0)), sum(coalesce(so_luong_ng, 0))
  from duc_lich_su_san_xuat
  where ngay >= make_date(p_nam, 1, 1) and ngay < make_date(p_nam + 1, 1, 1)
    and coalesce(trim(ma_sp), '') <> ''
  group by 1, 2;
$$;
revoke execute on function forecast_thuc_te_duc(int) from public, anon;
grant execute on function forecast_thuc_te_duc(int) to authenticated;
