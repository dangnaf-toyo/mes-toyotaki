-- ============================================================================
-- Phase T54 — Ghi nhận NG cho Đúc Kẽm (T53) thêm CHỦNG LOẠI NG, không chỉ số
-- lượng. Đổi chữ ký duc_kanban_ghi_nhan_ng (thêm p_loai_ng) nên phải DROP
-- trước khi CREATE lại — không thể CREATE OR REPLACE thêm tham số.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

alter table public.duc_kanban_ng_log add column if not exists loai_ng text;

drop function if exists duc_kanban_ghi_nhan_ng(date, text, numeric, text);

create or replace function duc_kanban_ghi_nhan_ng(
  p_ngay date,
  p_ma_sp text,
  p_loai_ng text,
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
  if p_loai_ng is null or trim(p_loai_ng) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu chủng loại NG');
  end if;
  if p_so_luong is null or p_so_luong <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Số lượng NG phải lớn hơn 0');
  end if;

  insert into duc_kanban_ng_log (ngay, ma_sp, loai_ng, so_luong, nguoi)
  values (coalesce(p_ngay, (now() at time zone 'Asia/Ho_Chi_Minh')::date), trim(p_ma_sp), trim(p_loai_ng), p_so_luong, p_nguoi);

  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function duc_kanban_ghi_nhan_ng(date, text, text, numeric, text) from anon;
grant execute on function duc_kanban_ghi_nhan_ng(date, text, text, numeric, text) to authenticated;
