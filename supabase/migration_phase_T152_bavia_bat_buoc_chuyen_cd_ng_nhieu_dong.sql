-- ============================================================================
-- T152 — Bảng điều khiển Bavia:
--   1) Tem Đúc PHẢI được Chuyển công đoạn sang Bavia và phiếu chuyển đã xác nhận
--      ("Đã xác nhận chuyển công đoạn") thì Line mới khai báo làm nguồn được.
--      Bỏ cơ chế tự nhận Đúc → Bavia khi quét ở Line của T145 (user đổi ý
--      23/10/2026: tem chưa chuyển công đoạn vẫn làm Bavia và đóng gói được là sai).
--      Ô "Tem Đúc chờ Bavia" chỉ còn tính tem đã ở Bavia.
--   2) bavia_ng_nhieu: ghi nhiều dòng NG (mỗi dòng 1 lỗi + SL) cho 1 tem Đúc trong
--      1 lần, tất cả hoặc không dòng nào (dòng nào sai thì huỷ cả lần ghi).
-- Vá tại chỗ bavia_quet / bavia_du_lieu bằng replace trên định nghĩa hiện có (có kiểm tra).
--
-- Trạng thái: Đã chạy STAGING 23/10/2026. Đã chạy PROD 23/10/2026.
-- ============================================================================

do $do$
declare d text;
begin
  d := pg_get_functiondef('public.bavia_quet(text,text)'::regprocedure);
  if d not like '%chua_chuyen%' then
    d := replace(d, E'  v_line_khac text;\n', E'  v_line_khac text;\n  v_tt text;\n');
    d := regexp_replace(d,
      E'  select cong_doan_nhan into v_vi_tri from cd_chuyen_cong_doan_log\\n.*?  end if;\\n\\n  insert into bavia_line_nguon',
      E'  select cong_doan_nhan, trang_thai_xac_nhan into v_vi_tri, v_tt from cd_chuyen_cong_doan_log\n'
      || E'  where tag_no = v_tem.tag_no order by thoi_gian_chuyen desc limit 1;\n'
      || E'  -- T152: tem Đúc phải được Chuyển công đoạn sang Bavia và đã xác nhận (bỏ tự nhận của T145).\n'
      || E'  if v_vi_tri is distinct from ''Bavia'' then\n'
      || E'    return jsonb_build_object(''ok'', false, ''chua_chuyen'', true, ''error'',\n'
      || E'      ''Tem '' || v_tem.tag_no || case when v_vi_tri is null or v_vi_tri = ''Đúc''\n'
      || E'        then '' chưa chuyển công đoạn Đúc → Bavia. Chuyển công đoạn ở trang "Chuyển công đoạn / Đóng gói" rồi quét lại.''\n'
      || E'        else '' đang ở công đoạn '' || v_vi_tri || '', không phải Bavia'' end);\n'
      || E'  end if;\n'
      || E'  if v_tt is distinct from ''Đã xác nhận chuyển công đoạn'' then\n'
      || E'    return jsonb_build_object(''ok'', false, ''chua_chuyen'', true, ''error'',\n'
      || E'      ''Phiếu chuyển tem '' || v_tem.tag_no || '' sang Bavia chưa được công đoạn Đúc xác nhận. Xác nhận phiếu chuyển rồi quét lại.'');\n'
      || E'  end if;\n\n  insert into bavia_line_nguon', 's');
    d := replace(d, E'''tu_nhan'', v_vi_tri is null or v_vi_tri = ''Đúc'')', E'''tu_nhan'', false)');
    if d not like '%chua_chuyen%' or d like '%Tự nhận tại%' or d like '%v_vi_tri = ''Đúc'')%' then
      raise exception 'Không vá được bavia_quet';
    end if;
    execute d;
  end if;

  d := pg_get_functiondef('public.bavia_du_lieu(date,text)'::regprocedure);
  if d like '%t.ngay >= p_ngay - 14%' then
    d := regexp_replace(d, E'and \\(v\\.vi_tri_hien_tai = ''Bavia''\\s+or \\(coalesce\\(v\\.vi_tri_hien_tai, ''Đúc''\\) = ''Đúc'' and t\\.ngay >= p_ngay - 14\\)\\)',
                        'and v.vi_tri_hien_tai = ''Bavia''');
    if d like '%p_ngay - 14%' then raise exception 'Không vá được bavia_du_lieu'; end if;
    execute d;
  end if;
end $do$;

-- ── Ghi nhiều dòng NG cho 1 tem Đúc (tất cả hoặc không) ─────────────────────
create or replace function public.bavia_ng_nhieu(p_id_tram text, p_tag_no text, p_ds jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  r jsonb;
  v jsonb;
  n int := 0;
  v_tong numeric := 0;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if jsonb_typeof(p_ds) <> 'array' or jsonb_array_length(p_ds) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Nhập ít nhất 1 dòng NG');
  end if;
  for r in select * from jsonb_array_elements(p_ds) loop
    n := n + 1;
    if coalesce(r->>'so_luong', '') !~ '^\d+$' then
      raise exception 'Dòng %: số lượng NG phải là số nguyên lớn hơn 0', n using errcode = 'P0001';
    end if;
    v := bavia_ng(p_id_tram, p_tag_no, r->>'loai', r->>'ghi_chu', (r->>'so_luong')::numeric);
    if not (v->>'ok')::boolean then
      raise exception 'Dòng %: %', n, v->>'error' using errcode = 'P0001';
    end if;
    v_tong := v_tong + (r->>'so_luong')::numeric;
  end loop;
  return jsonb_build_object('ok', true, 'so_dong', n, 'tong', v_tong, 'so_luong_con_lai', v->'so_luong_con_lai');
end $$;
revoke execute on function public.bavia_ng_nhieu(text, text, jsonb) from public, anon;
grant execute on function public.bavia_ng_nhieu(text, text, jsonb) to authenticated;
