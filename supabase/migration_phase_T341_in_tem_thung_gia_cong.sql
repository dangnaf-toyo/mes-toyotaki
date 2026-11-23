-- T341 (23/11/2026): QLSX in tem thùng Gia Công ở màn In tem (mục Tem thành phẩm, công đoạn "Gia Công"),
-- in xong cấp cho Gia công dùng khi Chia xe.
--   * Tem tạo bằng cd_tao_lo_tem_thanh_pham → tram_cong_doan = 'Gia Công', SL = SL/thùng Gia Công.
--   * gc_chia_xe nhận tem in sẵn trạm 'Gia Công' (vẫn nhận tem trạm 'Bavia' in trước đây).
--   * cd_ghi_nhan_tem_thanh_pham chặn tem trạm 'Gia Công' (phải quét ở Chia xe, tránh trừ nguồn 2 lần).

do $$
declare v_old text; v_new text;
begin
  -- 1) gc_chia_xe
  select pg_get_functiondef('public.gc_chia_xe'::regproc) into v_old;
  v_new := replace(v_old,
    E'coalesce(v_th.tram_cong_doan, '''') <> ''Bavia''',
    E'coalesce(v_th.tram_cong_doan, '''') not in (''Bavia'', ''Gia Công'') /* T341 */');
  if v_new = v_old then raise exception 'T341: không sửa được gc_chia_xe'; end if;
  execute v_new;

  -- 2) cd_ghi_nhan_tem_thanh_pham
  select pg_get_functiondef('public.cd_ghi_nhan_tem_thanh_pham'::regproc) into v_old;
  v_new := replace(v_old,
    E'  v_need := v_tem.so_luong;\n',
    E'  if coalesce(v_tem.tram_cong_doan, '''') = ''Gia Công'' then -- T341\n'
    || E'    return jsonb_build_object(''ok'', false, ''error'', ''Tem '' || p_tag_no || '' là tem thùng Gia Công — quét ở Chia xe trên Bảng điều khiển Gia công'');\n'
    || E'  end if;\n'
    || E'  v_need := v_tem.so_luong;\n');
  if v_new = v_old then raise exception 'T341: không sửa được cd_ghi_nhan_tem_thanh_pham'; end if;
  execute v_new;
end $$;
