-- ============================================================================
-- Phase 4, bước con 11 — cho phép trình duyệt (đã đăng nhập) gọi thẳng In tem,
-- thay Web App Apps Script "Intem QR" (Code.gs: WA_InTem/WA_UpdateTem/WA_DeleteTem).
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
--
-- duc_ghi_tem (tạo ở migration_phase4_step2_intem.sql) là security definer
-- nhưng CHƯA revoke/grant — tới giờ chỉ được gọi qua service_role key (Apps
-- Script), an toàn dù bỏ ngỏ. Từ khi trang tĩnh intem.html gọi thẳng bằng
-- authenticated key, PHẢI khoá lại theo đúng pattern đã áp dụng cho mọi RPC
-- ghi khác (xem migration_phase_D3_chuyencongdoan_write.sql).
-- ============================================================================

revoke execute on function duc_ghi_tem(text, text, text, numeric, date, text, text, text, text, text, timestamptz, text) from anon;
grant execute on function duc_ghi_tem(text, text, text, numeric, date, text, text, text, text, text, timestamptz, text) to authenticated;

-- WA_UpdateTem/WA_DeleteTem (bản Apps Script) update/delete thẳng bảng duc_tem
-- qua service_role key (bỏ qua RLS) — trang tĩnh dùng authenticated key nên
-- cần policy UPDATE/DELETE tường minh (đọc vẫn public, đã có ở schema_duc.sql).
drop policy if exists "duc_tem authenticated update" on duc_tem;
create policy "duc_tem authenticated update" on duc_tem
  for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "duc_tem authenticated delete" on duc_tem;
create policy "duc_tem authenticated delete" on duc_tem
  for delete using (auth.role() = 'authenticated');
