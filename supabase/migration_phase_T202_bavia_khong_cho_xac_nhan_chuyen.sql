-- ============================================================================
-- Phase T202 — Bavia quét tem Đúc làm nguồn KHÔNG còn phải chờ công đoạn Đúc
-- "Xác nhận đã giao hàng" (giống T45 đã bỏ cho khai báo nguồn Đánh bóng/OQC).
--
-- T152 bắt tem Đúc phải có phiếu Chuyển công đoạn Đúc → Bavia VÀ phiếu đã ở
-- trạng thái "Đã xác nhận chuyển công đoạn". Thực tế xác nhận làm gộp cuối ca
-- → Bavia đứng chờ, công đoạn sau không làm được khi công đoạn trước chưa xác nhận.
--
-- Nay: chỉ cần phiếu chuyển mới nhất của tem là tới Bavia (đang chờ xác nhận
-- hay đã xác nhận đều được). Phiếu bị "Đã từ chối" vẫn chặn.
-- Vá tại chỗ trên định nghĩa hiện có (có kiểm tra), chạy lại an toàn.
-- ============================================================================
do $$
declare
  d text;
  cu text := E'  if v_tt is distinct from ''Đã xác nhận chuyển công đoạn'' then\n'
          || E'    return jsonb_build_object(''ok'', false, ''chua_chuyen'', true, ''error'',\n'
          || E'      ''Phiếu chuyển tem '' || v_tem.tag_no || '' sang Bavia chưa được công đoạn Đúc xác nhận. Xác nhận phiếu chuyển rồi quét lại.'');\n'
          || E'  end if;\n';
  moi text := E'  -- T202: không chờ công đoạn Đúc xác nhận phiếu; chỉ chặn phiếu bị từ chối.\n'
          || E'  if v_tt = ''Đã từ chối'' then\n'
          || E'    return jsonb_build_object(''ok'', false, ''chua_chuyen'', true, ''error'',\n'
          || E'      ''Phiếu chuyển tem '' || v_tem.tag_no || '' sang Bavia đã bị từ chối. Chuyển công đoạn lại rồi quét lại.'');\n'
          || E'  end if;\n';
begin
  d := pg_get_functiondef('public.bavia_quet(text,text)'::regprocedure);
  if position('T202:' in d) > 0 then
    raise notice 'bavia_quet đã vá T202 — bỏ qua';
    return;
  end if;
  if position(cu in d) = 0 then
    raise exception 'Không vá được bavia_quet (không thấy đoạn kiểm tra xác nhận của T152)';
  end if;
  execute replace(d, cu, moi);
end $$;

-- Hoàn tác: chạy lại khối DO ở migration_phase_T152 phần bavia_quet (đảo cu/moi).
