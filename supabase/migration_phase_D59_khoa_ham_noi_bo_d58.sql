-- D59: Khoá hàm nội bộ của D58 — không cho gọi trực tiếp qua API.
--
-- duc_ls_dieu_chinh_tem là security definer và mặc định Postgres cấp EXECUTE
-- cho PUBLIC, nên anon/authenticated gọi được qua /rest/v1/rpc/... và cộng/
-- trừ tuỳ ý vào duc_lich_su_san_xuat + duc_bao_cao_ca. Hàm chỉ cần được gọi
-- từ trigger trg_duc_tem_sync_lich_su (chạy với quyền owner nên không bị ảnh
-- hưởng khi thu hồi).
--
-- Chạy trên CẢ 2 project (production + staging).

revoke execute on function duc_ls_dieu_chinh_tem(text, text, timestamptz, numeric) from public, anon, authenticated;
revoke execute on function duc_tem_sync_lich_su_trigger() from public, anon, authenticated;
