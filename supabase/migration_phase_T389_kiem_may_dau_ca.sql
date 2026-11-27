-- ============================================================================
-- Phase T389 — Đầu ca kiểm số máy chạy so với KH tuần
-- 5 phút sau khi ca trước kết ca, Bảng điều khiển Đúc so máy có dòng ở ca mới
-- với máy có KH ngày đó (duc_khsx_tuan_plan, trừ ca nghỉ). Lệch → khung đỏ chặn
-- màn hình, Trưởng ca phải xác nhận. Khớp → tự ghi khop = true (không hỏi nữa).
-- Mỗi ca 1 dòng (ngay, ca). Chạy lại an toàn.
-- ============================================================================

create table if not exists public.duc_kiem_may_ca (
  ngay date not null,
  ca text not null,
  phuong_an_ca text,
  so_kh int,
  so_chay int,
  thieu text[] default '{}',
  thua text[] default '{}',
  khop boolean not null default false,
  ghi_chu text,
  nguoi text,
  nguoi_uid uuid,
  thoi_diem timestamptz not null default now(),
  primary key (ngay, ca)
);
alter table public.duc_kiem_may_ca enable row level security;
drop policy if exists duc_kiem_may_ca_doc on public.duc_kiem_may_ca;
create policy duc_kiem_may_ca_doc on public.duc_kiem_may_ca for select to authenticated using (true);
revoke insert, update, delete on public.duc_kiem_may_ca from anon, authenticated;

create or replace function public.duc_kiem_may_ca_luu(
  p_ngay date, p_ca text, p_phuong_an_ca text, p_so_kh int, p_so_chay int,
  p_thieu text[], p_thua text[], p_khop boolean, p_ghi_chu text, p_nguoi text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if not coalesce(p_khop, false)
     and not has_role('truong_ca', 'admin', 'quan_ly_bo_phan', 'qlsx_truong_phong', 'giam_doc_sx') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Trưởng ca / Quản lý xác nhận được');
  end if;
  insert into duc_kiem_may_ca (ngay, ca, phuong_an_ca, so_kh, so_chay, thieu, thua, khop, ghi_chu, nguoi, nguoi_uid)
  values (p_ngay, p_ca, p_phuong_an_ca, p_so_kh, p_so_chay, coalesce(p_thieu, '{}'), coalesce(p_thua, '{}'),
          coalesce(p_khop, false), nullif(trim(coalesce(p_ghi_chu, '')), ''), nullif(trim(coalesce(p_nguoi, '')), ''), auth.uid())
  on conflict (ngay, ca) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.duc_kiem_may_ca_luu(date, text, text, int, int, text[], text[], boolean, text, text) from public, anon;
grant execute on function public.duc_kiem_may_ca_luu(date, text, text, int, int, text[], text[], boolean, text, text) to authenticated;
