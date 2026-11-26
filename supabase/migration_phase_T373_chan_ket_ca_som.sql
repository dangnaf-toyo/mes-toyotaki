-- T373: Chặn kết ca Đúc quá sớm.
-- Sự cố 26/11/2026: Ca đêm 26/11 bị kết lúc 18:16 (3 phút sau kết Ca ngày) → bảng điều khiển
-- nhảy sang Ca ngày 27/11, tem in tối 26/11 không được cộng vào ca nào.
-- Quy tắc: chỉ được kết ca từ 60 phút trước giờ kết thúc ca trở đi.
-- Vá trực tiếp vào định nghĩa hiện tại của duc_end_shift (chèn sau dòng gán v_ws).
do $$
declare
  v_def text;
  v_moc text := E'v_ws := (v_shift_window->>''start'')::timestamptz;';
  v_chen text := E'v_ws := (v_shift_window->>''start'')::timestamptz;\n'
    || E'  -- T373: chặn kết ca sớm hơn 60 phút trước giờ kết thúc ca\n'
    || E'  if v_now < (v_shift_window->>''end'')::timestamptz - interval ''60 minutes'' then\n'
    || E'    return jsonb_build_object(''ok'', false, ''error'', ''Chưa đến giờ kết '' || p_ca || '' '' || to_char(p_ngay, ''DD/MM'')\n'
    || E'      || '' — chỉ kết ca được từ '' || to_char(((v_shift_window->>''end'')::timestamptz - interval ''60 minutes'') at time zone ''Asia/Ho_Chi_Minh'', ''HH24:MI DD/MM'')\n'
    || E'      || ''. Kiểm tra lại ô Ngày / Ca đang chọn.'');\n'
    || E'  end if;';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'duc_end_shift';
  if v_def is null then raise exception 'Không thấy duc_end_shift'; end if;
  if position('T373' in v_def) > 0 then raise notice 'Đã vá T373 rồi'; return; end if;
  if position(v_moc in v_def) = 0 then raise exception 'Không tìm thấy dòng mốc trong duc_end_shift'; end if;
  execute replace(v_def, v_moc, v_chen);
end $$;
