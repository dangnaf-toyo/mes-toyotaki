-- ============================================================================
-- Giai đoạn 2 (bỏ Google) — Chất lượng: cho phép ghi thẳng bảng cl_comments
-- từ trình duyệt (đã đăng nhập), thay cho việc phải đi qua Apps Script.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

drop policy if exists "authenticated write cl_comments" on cl_comments;
create policy "authenticated write cl_comments" on cl_comments
  for insert with check (auth.role() = 'authenticated');

drop policy if exists "authenticated update cl_comments" on cl_comments;
create policy "authenticated update cl_comments" on cl_comments
  for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
