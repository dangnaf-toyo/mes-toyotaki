-- T339 (23/11/2026): Bavia chuyển nguyên xe — "Xong xe" KHÔNG tự chuyển sang Gia Công nữa.
-- Làm xong xe → bấm Xong xe (ghi sản lượng) → QUÉT TEM ở màn Chuyển công đoạn: Bavia → Gia Công.
--   * bavia_xong_xe: bỏ dòng ghi cd_chuyen_cong_doan_log.
--   * bavia_xong_xe_huy: chỉ huỷ khi xe còn ở Bavia (chưa quét chuyển); không xoá phiếu chuyển.
--   * cd_kiem_xe_bavia(tag, sl): tem Đúc ở Bavia, mã đang chế độ nguyên xe →
--       chưa bấm Xong xe thì chặn; đã Xong xe thì phải chuyển đủ cả xe (không tách).
--     Dùng trong cd_ghi_chuyen_cong_doan + màn Chuyển công đoạn (báo sớm lúc quét).

create or replace function public.cd_kiem_xe_bavia(p_tag_no text, p_sl numeric default null)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_tag text := upper(trim(coalesce(p_tag_no, '')));
  v_tem duc_tem%rowtype;
  v_info jsonb;
begin
  if v_tag = '' or v_tag like 'TP%' then return null; end if;
  if cd_vi_tri_tem(v_tag) is distinct from 'Bavia' then return null; end if;
  select * into v_tem from duc_tem where tag_no = v_tag;
  if not found then return null; end if;
  if exists (select 1 from bavia_thung where tag_tp = v_tag and dang = 3) then
    if p_sl is not null and p_sl <> coalesce(v_tem.so_luong, 0) then
      return 'Xe ' || v_tag || ' chuyển nguyên xe: phải chuyển đủ ' || coalesce(v_tem.so_luong, 0) || ' pcs, không tách.';
    end if;
    return null;
  end if;
  v_info := bavia_thong_tin_ma(v_tem.ma_sp);
  if coalesce((v_info->>'ok')::boolean, false) and coalesce((v_info->>'nguyen_xe')::boolean, false) then
    return 'Xe ' || v_tag || ' chưa bấm "Xong xe" ở Bavia. Bấm Xong xe rồi quét lại.';
  end if;
  return null;
end $$;
revoke execute on function public.cd_kiem_xe_bavia(text, numeric) from public, anon;
grant execute on function public.cd_kiem_xe_bavia(text, numeric) to authenticated;

do $mig$
declare v_old text; v_new text;
begin
  -- 1) cd_ghi_chuyen_cong_doan: kiểm xe Bavia
  v_old := pg_get_functiondef('public.cd_ghi_chuyen_cong_doan(text, text, text, numeric, numeric, text, text, text, text, text, text, text, text, text, text)'::regprocedure);
  if position('T339' in v_old) = 0 then
    v_new := replace(v_old, E'  v_sl_tem := coalesce(v_tem.so_luong, 0);',
      E'  if cd_kiem_xe_bavia(v_tem.tag_no, p_sl_thuc_chuyen) is not null then -- T339\n'
      || E'    raise exception ''%'', cd_kiem_xe_bavia(v_tem.tag_no, p_sl_thuc_chuyen);\n'
      || E'  end if;\n'
      || E'  v_sl_tem := coalesce(v_tem.so_luong, 0);');
    if v_new = v_old then raise exception 'T339: không sửa được cd_ghi_chuyen_cong_doan'; end if;
    execute v_new;
  end if;

  -- 2) bavia_xong_xe: bỏ ghi phiếu chuyển
  v_old := pg_get_functiondef('public.bavia_xong_xe(text, bigint)'::regprocedure);
  if position('T339' in v_old) = 0 then
    v_new := regexp_replace(v_old,
      E'  insert into cd_chuyen_cong_doan_log .*?''T338 Bavia chuyển nguyên xe '' \\|\\| v_line\\.ten_tram\\);\n',
      E'  -- T339: không tự chuyển; quét tem ở Chuyển công đoạn Bavia → Gia Công\n');
    if v_new = v_old then raise exception 'T339: không sửa được bavia_xong_xe'; end if;
    execute v_new;
  end if;

  -- 3) bavia_xong_xe_huy: chỉ khi xe còn ở Bavia; không xoá phiếu
  v_old := pg_get_functiondef('public.bavia_xong_xe_huy(text, text)'::regprocedure);
  if position('T339' in v_old) = 0 then
    v_new := regexp_replace(v_old,
      E'  select id_phieu, cong_doan_nhan, ghi_chu into v_log .*?  end if;\n',
      E'  if cd_vi_tri_tem(v_b.tag_tp) is distinct from ''Bavia'' then -- T339\n'
      || E'    return jsonb_build_object(''ok'', false, ''error'', ''Xe '' || v_b.tag_tp || '' đã quét chuyển sang '' || coalesce(cd_vi_tri_tem(v_b.tag_tp), ''?'') || '', không huỷ được'');\n'
      || E'  end if;\n');
    v_new := replace(v_new, E'  delete from cd_chuyen_cong_doan_log where id_phieu = v_log.id_phieu and tag_no = v_b.tag_tp;\n', '');
    if v_new = v_old or position('delete from cd_chuyen_cong_doan_log' in v_new) > 0 then
      raise exception 'T339: không sửa được bavia_xong_xe_huy';
    end if;
    execute v_new;
  end if;
end $mig$;
