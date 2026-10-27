-- T172 (27/10/2026): admin / QC Manager được kết thúc sự cố khi IPQC chưa OK (vượt chặn cứng T170).
-- Trưởng ca vẫn bị chặn. Nội dung xử lý tự ghi chú người vượt + kết quả IPQC lúc đóng.
-- Vá bằng replace trên pg_get_functiondef đang chạy (giữ nguyên các khối khác).
do $$
declare d text; d0 text;
begin
  d := pg_get_functiondef('public.duc_resolve_incident'::regproc);
  d0 := d;

  d := replace(d, '  v_ipqc jsonb;
begin', '  v_ipqc jsonb;
  v_vuot_ipqc boolean := false;   -- T172: admin/qc_manager đóng khi IPQC chưa OK
begin');

  d := replace(d, '  v_ipqc := duc_ipqc_trang_thai_su_co(p_id_dong);
  if (v_ipqc->>''can_ipqc'')::boolean and not (v_ipqc->>''ok'')::boolean then',
'  v_ipqc := duc_ipqc_trang_thai_su_co(p_id_dong);
  v_vuot_ipqc := (v_ipqc->>''can_ipqc'')::boolean and not (v_ipqc->>''ok'')::boolean
                 and public.has_role(''admin'', ''qc_manager'');
  if (v_ipqc->>''can_ipqc'')::boolean and not (v_ipqc->>''ok'')::boolean and not v_vuot_ipqc then');

  d := replace(d, '  select count(*) into v_seg_count from duc_split_incident_by_shift(',
'  if v_vuot_ipqc then
    v_noi_dung_combined := case when v_noi_dung_combined <> '''' then v_noi_dung_combined || E''\n'' else '''' end
      || ''[Đóng khi IPQC chưa OK ('' || coalesce(v_ipqc->>''ket_qua'', ''chưa kiểm'') || '') — ''
      || coalesce(nullif(p_user, ''''), p_truong_ca, ''admin/QC Manager'') || '']'';
  end if;

  select count(*) into v_seg_count from duc_split_incident_by_shift(');

  d := replace(d, '''canh_bao_ipqc_loai'', v_canh_bao_ipqc_loai, ''id_su_co'', v_cht.open_id_su_co',
                  '''canh_bao_ipqc_loai'', v_canh_bao_ipqc_loai, ''id_su_co'', v_cht.open_id_su_co, ''vuot_ipqc'', v_vuot_ipqc');

  if (length(d) - length(d0)) < 400 or strpos(d, 'and not v_vuot_ipqc then') = 0
     or strpos(d, '''vuot_ipqc'', v_vuot_ipqc') = 0 or strpos(d, 'v_vuot_ipqc boolean := false') = 0
     or strpos(d, '[Đóng khi IPQC chưa OK') = 0 then
    raise exception 'T172: replace không khớp đủ 4 chỗ';
  end if;
  execute d;
end $$;
