-- ============================================================================
-- T333 — Danh mục Khuôn: khai báo khuôn 1 shot ra nhiều mã SP + số SP/shot từng mã.
-- CHỈ KHAI BÁO — chưa dùng để tính sản lượng (vẫn theo master_products.cavity).
--   - duc_khuon_ho.so_sp_shot: số SP của mã đó ra trên 1 shot của khuôn.
--   - duc_khuon_ho_luu(): Admin ghi đè danh sách mã của 1 khuôn (rỗng = khuôn thường).
-- Chạy được nhiều lần.
-- ============================================================================
alter table duc_khuon_ho add column if not exists so_sp_shot int;
alter table duc_khuon_ho drop constraint if exists duc_khuon_ho_so_sp_shot_chk;
alter table duc_khuon_ho add constraint duc_khuon_ho_so_sp_shot_chk check (so_sp_shot is null or so_sp_shot between 1 and 99);

update duc_khuon_ho h set so_sp_shot = mp.cavity::int
from master_products mp
where mp.ma_sp = h.ma_sp and h.so_sp_shot is null and mp.cavity is not null and mp.cavity between 1 and 99;

create or replace function duc_khuon_ho_luu(p_ma_khuon text, p_ds jsonb, p_ma_khuon_cu text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ma text := trim(coalesce(p_ma_khuon, '')); v_n int;
begin
  if not has_role('admin') then return jsonb_build_object('ok', false, 'error', 'Chỉ admin được sửa khuôn'); end if;
  if v_ma = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã khuôn'); end if;
  if p_ds is null or jsonb_typeof(p_ds) <> 'array' then p_ds := '[]'::jsonb; end if;
  if exists (select 1 from jsonb_array_elements(p_ds) e
             where not exists (select 1 from master_products mp where mp.ma_sp = trim(e->>'ma_sp'))) then
    return jsonb_build_object('ok', false, 'error', 'Có mã SP không có trong danh mục');
  end if;
  if exists (select 1 from jsonb_array_elements(p_ds) e
             where nullif(e->>'so_sp_shot', '') is not null and (e->>'so_sp_shot')::numeric not between 1 and 99) then
    return jsonb_build_object('ok', false, 'error', 'SP/shot phải từ 1 đến 99');
  end if;
  select count(distinct trim(e->>'ma_sp')) into v_n from jsonb_array_elements(p_ds) e;
  if v_n <> jsonb_array_length(p_ds) then return jsonb_build_object('ok', false, 'error', 'Trùng mã SP'); end if;

  delete from duc_khuon_ho where ma_khuon in (v_ma, trim(coalesce(p_ma_khuon_cu, '')));
  insert into duc_khuon_ho (ma_khuon, ma_sp, thu_tu, so_sp_shot)
  select v_ma, trim(e->>'ma_sp'), o::int, nullif(e->>'so_sp_shot', '')::numeric::int
  from jsonb_array_elements(p_ds) with ordinality as t(e, o);
  return jsonb_build_object('ok', true, 'so_ma', v_n);
end $$;
revoke execute on function duc_khuon_ho_luu(text, jsonb, text) from public, anon;
grant execute on function duc_khuon_ho_luu(text, jsonb, text) to authenticated;
