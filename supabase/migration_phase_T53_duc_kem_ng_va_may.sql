-- ============================================================================
-- Phase T53 — Ghi nhận NG cho công đoạn "Đúc Kẽm" (chế độ Kanban gộp trong
-- ghi-nhan-tem-thanh-pham.html, xem T52). Kẽm chỉ đúc trên 2 máy "Kẽm 190T"/
-- "Kẽm 160T" (đã có sẵn trong master_machines) — không tạo tem nguồn như
-- Đánh bóng Kẽm nên không dùng lại cd_ng_khai_bao (bảng đó gắn theo tag_no
-- tem Đúc nguồn). NG ở đây chỉ là 1 con số người vận hành tự nhập khi phát
-- sinh hoặc cuối ca, CỘNG DỒN theo (ngày, mã SP) — không gắn tem/máy cụ thể.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create table if not exists public.duc_kanban_ng_log (
  id bigserial primary key,
  ngay date not null,
  ma_sp text not null,
  so_luong numeric not null check (so_luong > 0),
  nguoi text,
  created_at timestamptz not null default now()
);
create index if not exists idx_duc_kanban_ng_log_ngay_ma_sp on public.duc_kanban_ng_log (ngay, ma_sp);

alter table public.duc_kanban_ng_log enable row level security;
drop policy if exists duc_kanban_ng_log_select on public.duc_kanban_ng_log;
create policy duc_kanban_ng_log_select on public.duc_kanban_ng_log for select to authenticated using (true);

create or replace function duc_kanban_ghi_nhan_ng(
  p_ngay date,
  p_ma_sp text,
  p_so_luong numeric,
  p_nguoi text
) returns jsonb
language plpgsql
security definer
as $$
begin
  if p_ma_sp is null or trim(p_ma_sp) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu mã SP');
  end if;
  if p_so_luong is null or p_so_luong <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Số lượng NG phải lớn hơn 0');
  end if;

  insert into duc_kanban_ng_log (ngay, ma_sp, so_luong, nguoi)
  values (coalesce(p_ngay, (now() at time zone 'Asia/Ho_Chi_Minh')::date), trim(p_ma_sp), p_so_luong, p_nguoi);

  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function duc_kanban_ghi_nhan_ng(date, text, numeric, text) from anon;
grant execute on function duc_kanban_ghi_nhan_ng(date, text, numeric, text) to authenticated;
