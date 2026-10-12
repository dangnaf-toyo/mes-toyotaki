-- ============================================================================
-- T102 — Check sheet bảo dưỡng khuôn: người thực hiện chia thành Đảm nhiệm
-- chính + Đảm nhiệm phụ (user 2026-10-12: mỗi khuôn thường 2 người cùng làm).
--
--   - duc_khuon_checksheet.nguoi_thuc_hien     = đảm nhiệm chính (giữ cột cũ,
--     vẫn bắt buộc khi hoàn thành).
--   - duc_khuon_checksheet.nguoi_thuc_hien_phu = đảm nhiệm phụ (không bắt buộc,
--     phải khác người chính).
--   - duc_khuon_bao_duong_log.nguoi_thuc_hien ghi "Chính + Phụ".
--   - duc_khuon_cs_luu: chèn vào thân hàm đang có (giống D68), không chép lại.
--
-- Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

alter table duc_khuon_checksheet add column if not exists nguoi_thuc_hien_phu text not null default '';

do $$
declare
  v_def text;
  v_cu1 text := E'    nguoi_thuc_hien = coalesce(trim(p_data->>\'nguoi_thuc_hien\'), \'\'),\n';
  v_moi1 text := E'    nguoi_thuc_hien = coalesce(trim(p_data->>\'nguoi_thuc_hien\'), \'\'),\n'
              || E'    nguoi_thuc_hien_phu = coalesce(trim(p_data->>\'nguoi_thuc_hien_phu\'), \'\'),  -- T102\n';
  v_cu2 text := E'  if v_cs.id is null then\n';
  v_moi2 text := E'  if coalesce(trim(p_data->>\'nguoi_thuc_hien_phu\'), \'\') <> \'\'\n'
              || E'     and trim(p_data->>\'nguoi_thuc_hien_phu\') = coalesce(trim(p_data->>\'nguoi_thuc_hien\'), \'\') then\n'
              || E'    return jsonb_build_object(\'ok\', false, \'error\', \'Đảm nhiệm phụ phải khác đảm nhiệm chính\');\n'
              || E'  end if;\n\n'
              || E'  if v_cs.id is null then\n';
  v_cu3 text := E'      trim(p_data->>\'nguoi_thuc_hien\'), v_mo_ta,';
  v_moi3 text := E'      trim(p_data->>\'nguoi_thuc_hien\') || coalesce(\' + \' || nullif(trim(p_data->>\'nguoi_thuc_hien_phu\'), \'\'), \'\'), v_mo_ta,';
begin
  v_def := pg_get_functiondef('duc_khuon_cs_luu'::regproc);
  if position('-- T102' in v_def) = 0 then
    if position(v_cu1 in v_def) = 0 or position(v_cu2 in v_def) = 0 or position(v_cu3 in v_def) = 0 then
      raise exception 'T102: không tìm thấy đoạn cần sửa trong duc_khuon_cs_luu';
    end if;
    v_def := replace(replace(replace(v_def, v_cu1, v_moi1), v_cu2, v_moi2), v_cu3, v_moi3);
    execute v_def;
  end if;
end $$;
