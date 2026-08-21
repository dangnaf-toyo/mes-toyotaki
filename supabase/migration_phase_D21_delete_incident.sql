-- ============================================================================
-- Phase D21 — Xoá sự cố (đang mở hoặc đã đóng) trên dashboard Đúc.
-- Lý do: trưởng ca đôi khi nhập nhầm sự cố cho sai máy, cần xoá để nhập lại
-- thay vì phải sửa nội dung (sửa không đổi được máy/dòng SP gắn với sự cố).
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ── deleteIncident_ — 'open' (xoá trực tiếp trên duc_ca_hien_tai, dùng lại
-- duc_clear_incident_open) / 'closed' (xoá bản ghi trong duc_su_co_log) ────
create or replace function duc_delete_incident(
  p_mode text, p_id_dong text, p_id_ban_ghi text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare v_row record;
begin
  if p_mode = 'open' then
    select * into v_row from duc_ca_hien_tai where id_dong = p_id_dong;
    if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng: ' || p_id_dong); end if;
    if v_row.open_gio_phat_sinh is null then return jsonb_build_object('ok', false, 'error', 'Dòng này không có sự cố đang mở để xoá'); end if;
    perform duc_clear_incident_open(p_id_dong, coalesce(p_user, 'system'));
    return jsonb_build_object('ok', true, 'mode', 'open', 'id_dong', p_id_dong);
  elsif p_mode = 'closed' then
    select * into v_row from duc_su_co_log where id_ban_ghi = p_id_ban_ghi;
    if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy bản ghi sự cố: ' || p_id_ban_ghi); end if;
    delete from duc_su_co_log where id_ban_ghi = p_id_ban_ghi;
    return jsonb_build_object('ok', true, 'mode', 'closed', 'id_ban_ghi', p_id_ban_ghi, 'ma_may', v_row.ma_may);
  else
    return jsonb_build_object('ok', false, 'error', 'p_mode không hợp lệ (open/closed)');
  end if;
end;
$$;
revoke execute on function duc_delete_incident(text, text, text, text) from anon;
grant execute on function duc_delete_incident(text, text, text, text) to authenticated;
