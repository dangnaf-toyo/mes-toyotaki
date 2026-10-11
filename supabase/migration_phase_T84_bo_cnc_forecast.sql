-- ============================================================================
-- T84 — Trang Năng lực máy CNC (nang-luc-cnc.html) đọc forecast từ
-- forecast_san_luong (T83, forecast-san-luong.html) — một nguồn chung, không
-- nhập riêng cho CNC nữa. Bỏ bảng cnc_forecast cũ (lúc làm: 0 dòng ở cả
-- production và staging). Chỉ xoá khi bảng vẫn trống, có dữ liệu thì giữ lại
-- và báo để chuyển tay sang forecast_san_luong.
--
-- Chạy trên CẢ 2 project (production + staging). Idempotent. Chạy sau T83.
-- ============================================================================

do $$
begin
  if to_regclass('public.cnc_forecast') is null then return; end if;
  if exists (select 1 from cnc_forecast) then
    raise notice 'cnc_forecast còn dữ liệu — KHÔNG xoá, cần chuyển sang forecast_san_luong trước';
  else
    drop table cnc_forecast;
  end if;
end $$;
