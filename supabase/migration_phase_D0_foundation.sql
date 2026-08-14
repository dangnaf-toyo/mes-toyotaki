-- ============================================================================
-- Giai đoạn 0 (bỏ hẳn Google) — nền tảng dùng chung: Storage buckets + pg_cron.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
--
-- RLS ghi theo module (auth.role() = 'authenticated') sẽ được thêm KHI viết
-- trang tĩnh cho từng module (Giai đoạn 1-5), không làm hết 1 lần ở đây —
-- tránh khoá ghi các module còn đang chạy qua Apps Script (service_role vẫn
-- bỏ qua RLS nên không ảnh hưởng đường ghi hiện tại).
-- ============================================================================

-- ── Storage buckets (thay Google Drive) ────────────────────────────────────
-- ipqc-evidence: ảnh bằng chứng IPQC (public read qua signed URL, ghi cần đăng nhập).
-- report-files: PDF/HTML báo cáo kết ca, báo cáo tuần, PDF tiêu chuẩn IPQC.
insert into storage.buckets (id, name, public)
values ('ipqc-evidence', 'ipqc-evidence', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('report-files', 'report-files', true)
on conflict (id) do nothing;

-- Đọc công khai (khớp hành vi cũ — ảnh/báo cáo hiện đọc được qua link Drive
-- công khai không cần đăng nhập).
drop policy if exists "public read ipqc-evidence" on storage.objects;
create policy "public read ipqc-evidence" on storage.objects
  for select using (bucket_id = 'ipqc-evidence');

drop policy if exists "public read report-files" on storage.objects;
create policy "public read report-files" on storage.objects
  for select using (bucket_id = 'report-files');

-- Ghi (upload) yêu cầu đã đăng nhập — thay cho việc Apps Script (server-side,
-- có toàn quyền) là nơi duy nhất ghi Drive trước đây.
drop policy if exists "authenticated write ipqc-evidence" on storage.objects;
create policy "authenticated write ipqc-evidence" on storage.objects
  for insert with check (bucket_id = 'ipqc-evidence' and auth.role() = 'authenticated');

drop policy if exists "authenticated write report-files" on storage.objects;
create policy "authenticated write report-files" on storage.objects
  for insert with check (bucket_id = 'report-files' and auth.role() = 'authenticated');

-- ── pg_cron (thay trigger ScriptApp.newTrigger chạy nền trong Apps Script) ──
-- Bật extension — các job cụ thể (poll Diecast, IPQC scan định kỳ) sẽ được
-- tạo khi viết lại RPC tương ứng ở Giai đoạn khối Đúc, không tạo job rỗng ở đây.
create extension if not exists pg_cron with schema extensions;
