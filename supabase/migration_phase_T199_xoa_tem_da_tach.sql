-- ============================================================================
-- T199 — Xoá tem đã tách: báo lỗi tiếng Việt rõ ràng thay vì lỗi khoá ngoại.
-- Sự cố 31/10: tem TKD20261031-0126 đã tách ra -A, bấm xoá tem cha 12 lần chỉ
-- nhận "violates foreign key constraint duc_tem_tach_tag_no_cha_fkey" (409).
--   • Tem cha còn tem con  → liệt kê tem con, hướng dẫn Hoàn tác tách từng tem con trước.
--   • Tem con (tách ra)    → hướng dẫn dùng nút "Hoàn tác tách" (cộng trả SL về tem cha).
--   • Khoá ngoại khác      → "tem đang được dùng ở <bảng>", không lộ lỗi kỹ thuật.
-- Còn lại giữ nguyên logic cũ (đăng nhập, lý do, khoá kết ca chỉ admin).
-- Chạy: staging jcjbleugnclzsghfpmvk rồi production fgghikpzcxjqzahfiiil.
-- ============================================================================
create or replace function duc_tem_xoa(p_tag_no text, p_ly_do text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old duc_tem; v_ly text := trim(coalesce(p_ly_do, '')); v_ket jsonb;
  v_con text; v_cha duc_tem_tach; v_bang text;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if length(v_ly) < 3 then return jsonb_build_object('ok', false, 'error', 'Nhập lý do xoá tem'); end if;
  select * into v_old from duc_tem where lower(tag_no) = lower(trim(coalesce(p_tag_no, ''))) for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || coalesce(p_tag_no, '')); end if;

  select string_agg(tag_no_con || ' (' || so_luong_con || ' pcs)', ', ' order by thoi_diem) into v_con
    from duc_tem_tach where tag_no_cha = v_old.tag_no;
  if v_con is not null then
    return jsonb_build_object('ok', false, 'error',
      'Tem ' || v_old.tag_no || ' đã tách ra tem con: ' || v_con ||
      '. Mở từng tem con, bấm "Hoàn tác tách" (cộng trả số lượng về tem này) rồi mới xoá được tem này.');
  end if;
  select * into v_cha from duc_tem_tach where tag_no_con = v_old.tag_no;
  if found then
    return jsonb_build_object('ok', false, 'error',
      'Tem ' || v_old.tag_no || ' được tách từ tem ' || v_cha.tag_no_cha ||
      ' — không xoá thẳng. Bấm nút "Hoàn tác tách" để xoá tem này và cộng trả ' ||
      v_cha.so_luong_con || ' pcs về tem ' || v_cha.tag_no_cha || '.');
  end if;

  v_ket := duc_tem_ca_da_ket(v_old.may_tt, v_old.ma_sp, coalesce(v_old.ngay_gio_ghi_nhan, v_old.ngay_gio_in));
  if v_ket is not null and not has_role('admin') then
    return jsonb_build_object('ok', false, 'error',
      'Tem thuộc ' || coalesce(v_ket->>'ca', '') || ' ' || to_char((v_ket->>'ngay')::date, 'DD/MM/YYYY') || ' đã kết ca — chỉ admin được xoá.');
  end if;
  perform set_config('mes.tem_hanh_dong', 'xoa', true);
  perform set_config('mes.tem_ly_do', v_ly, true);
  perform set_config('mes.tem_ca_da_ket', coalesce(v_ket::text, ''), true);
  begin
    delete from duc_tem where tag_no = v_old.tag_no;
  exception when foreign_key_violation then
    get stacked diagnostics v_bang = table_name;
    return jsonb_build_object('ok', false, 'error',
      'Tem ' || v_old.tag_no || ' đang được dùng ở nơi khác (' || coalesce(v_bang, '?') ||
      ') — không xoá được. Gỡ tem khỏi chỗ đó trước hoặc báo admin.');
  end;
  perform set_config('mes.tem_hanh_dong', '', true);
  perform set_config('mes.tem_ly_do', '', true);
  perform set_config('mes.tem_ca_da_ket', '', true);
  return jsonb_build_object('ok', true, 'tag_no', v_old.tag_no, 'ca_da_ket', v_ket);
end $$;

revoke execute on function duc_tem_xoa(text, text) from public, anon;
grant execute on function duc_tem_xoa(text, text) to authenticated, service_role;
