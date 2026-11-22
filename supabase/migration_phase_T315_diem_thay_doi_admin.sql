-- T315: admin cũng dùng được điểm thay đổi Đúc (ghi phiếu, xác nhận "Đã chỉnh") như trưởng ca.
-- Sửa tại chỗ 3 hàm T307: has_role('truong_ca') → has_role('truong_ca', 'admin'). Phần khác giữ nguyên.
-- Duyệt vẫn theo nhóm người duyệt (duc_td_ds_duyet), không thêm admin để tránh chuông thừa.
do $$
declare r record; v_def text;
begin
  for r in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('duc_td_quyen', 'duc_td_ghi', 'duc_td_da_chinh')
  loop
    v_def := pg_get_functiondef(r.oid);
    if position('has_role(''truong_ca'')' in v_def) = 0 then continue; end if;
    v_def := replace(v_def, 'has_role(''truong_ca'')', 'has_role(''truong_ca'', ''admin'')');
    v_def := replace(v_def, '⛔ Chỉ trưởng ca được', '⛔ Chỉ trưởng ca hoặc admin được');
    execute v_def;
  end loop;
end $$;

-- Kiểm tra: phải ra 3 dòng
select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname like 'duc_td%' and pg_get_functiondef(p.oid) like '%has_role(''truong_ca'', ''admin'')%';
