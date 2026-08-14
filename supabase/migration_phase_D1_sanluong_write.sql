-- ============================================================================
-- Giai đoạn 1 (bỏ Google) — Sản lượng: cho phép ghi thẳng bảng sl_comments
-- từ trình duyệt (đã đăng nhập), thay cho việc phải đi qua Apps Script
-- doPost (AppsScript_Comments_Backend.gs.txt) như trước.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

drop policy if exists "authenticated write sl_comments" on sl_comments;
create policy "authenticated write sl_comments" on sl_comments
  for insert with check (auth.role() = 'authenticated');

drop policy if exists "authenticated update sl_comments" on sl_comments;
create policy "authenticated update sl_comments" on sl_comments
  for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
