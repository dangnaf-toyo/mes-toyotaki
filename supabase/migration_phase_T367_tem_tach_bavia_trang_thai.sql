-- T367 (26/11/2026): Tem con tách ở Bavia = ĐÃ LÀM BAVIA (không còn chép trạng thái "Đã đúc" của tem mẹ).
--   * bavia_tach_tem: trang_thai = 'Đã làm Bavia', ghi_chu_sl ghi line Bavia + ca; người thao tác = người làm ở line (giữ).
--   * Sửa các tem con đã tách trước đó.
--   Không đổi tram_cong_doan (cột này dành cho tem thành phẩm — tồn kho / vị trí tem đọc theo nó).

do $mig$
declare v_old text; v_new text;
begin
  v_old := pg_get_functiondef('public.bavia_tach_tem(text, bigint, numeric, int)'::regprocedure);
  if position('T367' in v_old) = 0 then
    v_new := replace(v_old,
      E'null, v_me.may_tt, v_line.nguoi_thao_tac, v_me.trang_thai, ''Tách ở Bavia từ '' || v_me.tag_no);',
      E'null, v_me.may_tt, v_line.nguoi_thao_tac, ''Đã làm Bavia'' /* T367 */,\n'
      || E'      ''Tách ở Bavia từ '' || v_me.tag_no || '' · '' || v_line.ten_tram || '' · '' || v_line.ca || '' '' || to_char(v_line.ngay, ''DD/MM''));');
    if v_new = v_old then raise exception 'T367: không sửa được bavia_tach_tem'; end if;
    execute v_new;
  end if;
end $mig$;

update duc_tem t
set trang_thai = 'Đã làm Bavia',
    nguoi_tt = b.nguoi_lam,
    ghi_chu_sl = 'Tách ở Bavia từ ' || x.tag_no_cha || ' · ' || b.ten_line || ' · ' || b.ca || ' ' || to_char(b.ngay, 'DD/MM')
from duc_tem_tach x
join bavia_thung b on b.tag_tp = x.tag_no_con and b.dang = 3
where t.tag_no = x.tag_no_con and x.ly_do like 'Bavia tách%'
  and t.trang_thai is distinct from 'Đã làm Bavia';
