-- ============================================================================
-- Giai đoạn 3 (bỏ Google) — Chuyển công đoạn: thêm luồng "Từ chối xác nhận"
-- (bên cạnh "Xác nhận đã giao" đã có). Chạy trong Supabase SQL Editor.
-- An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

alter table cd_chuyen_cong_doan_log add column if not exists ly_do_tu_choi text;

create or replace function cd_tu_choi_chuyen(
  p_id_phieu text, p_nguoi_tu_choi text, p_ly_do text, p_ngay_gio_xac_nhan text
)
returns void
language sql
security definer
as $$
  update cd_chuyen_cong_doan_log
  set trang_thai_xac_nhan = 'Đã từ chối',
      nguoi_giao = p_nguoi_tu_choi,
      ly_do_tu_choi = p_ly_do,
      ngay_gio_xac_nhan = p_ngay_gio_xac_nhan
  where id_phieu = p_id_phieu;
$$;

revoke execute on function cd_tu_choi_chuyen(text, text, text, text) from anon;
grant execute on function cd_tu_choi_chuyen(text, text, text, text) to authenticated;
