-- ============================================================================
-- HOÀN TÁC T198 — trả lại cho anon đúng các quyền đã sao lưu trong
-- sao_luu.t198_quyen_anon (mỗi project có bản sao lưu riêng) + quyền mặc định.
-- Chỉ chạy khi cần mở lại truy cập không đăng nhập.
-- ============================================================================
begin;
do $$
declare r record;
begin
  for r in select stmt from sao_luu.t198_quyen_anon loop
    begin
      execute r.stmt;
    exception when undefined_table or undefined_function or undefined_object then
      raise notice 'Bỏ qua (đối tượng không còn): %', r.stmt;
    end;
  end loop;
end $$;
alter default privileges for role postgres in schema public grant all on tables to anon;
alter default privileges for role postgres in schema public grant all on sequences to anon;
alter default privileges for role postgres in schema public grant execute on functions to public, anon;
commit;
