-- ============================================================================
-- Phase T5 — Truy xuất nguồn gốc trực quan: RPC đệ quy trả về toàn bộ phả hệ
-- (nguồn gốc ngược + đã dùng để tạo ra gì) của 1 Tag No, gộp cả 2 loại quan hệ
-- đã có sẵn trong hệ thống:
--   - duc_tem_tach   (tách 1 tem → nhiều tem con,      migration_phase_T1)
--   - cd_tem_nguon   (gộp nhiều tem nguồn → 1 tem mới, migration_phase_T2)
-- Dùng cho trang truy-xuat-nguon-goc.html.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create or replace function cd_truy_xuat_pha_he(p_tag_no text)
returns table(huong text, cap int, tag_cha text, tag_con text, so_luong numeric, loai text)
language sql
stable
as $$
  with recursive edges as (
    select tag_no_cha as tu, tag_no_con as den, so_luong_con as sl, 'tach'::text as loai from duc_tem_tach
    union all
    select tag_no_nguon as tu, tag_no_moi as den, so_luong_lay as sl, 'dong_goi'::text as loai from cd_tem_nguon
  ),
  -- Nguồn gốc ngược: từ tag đang tra, đi lên tìm "ai sinh ra nó" (tu = cha).
  nguoc as (
    select e.tu, e.den, e.sl, e.loai, 1 as cap from edges e where e.den = p_tag_no
    union all
    select e.tu, e.den, e.sl, e.loai, n.cap + 1
    from edges e join nguoc n on e.den = n.tu
    where n.cap < 15
  ),
  -- Đã dùng để tạo ra gì: từ tag đang tra, đi xuống tìm "nó sinh ra ai" (den = con).
  xuoi as (
    select e.tu, e.den, e.sl, e.loai, 1 as cap from edges e where e.tu = p_tag_no
    union all
    select e.tu, e.den, e.sl, e.loai, x.cap + 1
    from edges e join xuoi x on e.tu = x.den
    where x.cap < 15
  )
  select 'nguoc'::text as huong, cap, tu as tag_cha, den as tag_con, sl as so_luong, loai from nguoc
  union all
  select 'xuoi'::text as huong, cap, tu as tag_cha, den as tag_con, sl as so_luong, loai from xuoi
  order by huong, cap;
$$;

revoke execute on function cd_truy_xuat_pha_he(text) from anon;
grant execute on function cd_truy_xuat_pha_he(text) to anon;
grant execute on function cd_truy_xuat_pha_he(text) to authenticated;
