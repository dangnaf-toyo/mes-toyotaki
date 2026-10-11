-- ============================================================================
-- T83 — Forecast sản lượng năm (forecast-san-luong.html, menu Điều hành & Báo cáo).
--
-- - forecast_san_luong (nam, ma_sp, thang) -> so_luong (chiếc). Dùng lập KHSX,
--   kế hoạch đầu tư thiết bị (giờ máy đúc), kế hoạch làm khuôn mới (tuổi thọ).
-- - Ghi chỉ qua RPC forecast_luu (lưu hàng loạt), mỗi thay đổi ghi vào
--   forecast_san_luong_log (cũ -> mới, ai, lúc nào, ghi chú đợt cập nhật).
-- - Số liệu kinh doanh: chỉ người đã đăng nhập mới đọc được (không public).
-- - Quyền sửa: admin, ke_hoach, qlsx_truong_phong, giam_doc_sx.
--
-- Chạy trên CẢ 2 project (production + staging). Idempotent.
-- ============================================================================

create table if not exists forecast_san_luong (
  nam         int not null check (nam between 2000 and 2100),
  ma_sp       text not null,
  thang       int not null check (thang between 1 and 12),
  so_luong    numeric not null check (so_luong >= 0),
  updated_by  text not null default '',
  updated_at  timestamptz not null default now(),
  primary key (nam, ma_sp, thang)
);

create table if not exists forecast_san_luong_log (
  id          bigserial primary key,
  nam         int not null,
  ma_sp       text not null,
  thang       int not null,
  cu          numeric,
  moi         numeric,
  ghi_chu     text not null default '',
  nguoi       text not null default '',
  thoi_diem   timestamptz not null default now()
);
create index if not exists idx_forecast_log_nam on forecast_san_luong_log (nam, thoi_diem desc);

alter table forecast_san_luong enable row level security;
alter table forecast_san_luong_log enable row level security;
drop policy if exists "forecast read authenticated" on forecast_san_luong;
create policy "forecast read authenticated" on forecast_san_luong for select to authenticated using (true);
drop policy if exists "forecast log read authenticated" on forecast_san_luong_log;
create policy "forecast log read authenticated" on forecast_san_luong_log for select to authenticated using (true);
revoke all on forecast_san_luong, forecast_san_luong_log from anon;
revoke insert, update, delete on forecast_san_luong, forecast_san_luong_log from authenticated;
grant select on forecast_san_luong, forecast_san_luong_log to authenticated;

-- p_rows: [{ma_sp, thang, so_luong}] ; so_luong null/'' = xoá ô.
create or replace function forecast_luu(p_nam int, p_rows jsonb, p_ghi_chu text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text; v_ten text; v_now timestamptz := now(); x jsonb;
  v_ma text; v_th int; v_sl numeric; v_cu numeric; n_doi int := 0;
begin
  select role, coalesce(nullif(trim(full_name), ''), nullif(trim(username), ''), email, '')
    into v_role, v_ten from user_roles where user_id = auth.uid();
  if coalesce(v_role, '') not in ('admin', 'ke_hoach', 'qlsx_truong_phong', 'giam_doc_sx') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Kế hoạch / Trưởng phòng QLSX / Giám đốc SX / admin được sửa forecast');
  end if;
  if p_nam is null or p_nam < 2000 or p_nam > 2100 then
    return jsonb_build_object('ok', false, 'error', 'Năm không hợp lệ');
  end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Không có thay đổi nào');
  end if;
  if jsonb_array_length(p_rows) > 5000 then
    return jsonb_build_object('ok', false, 'error', 'Quá nhiều ô trong 1 lần lưu (tối đa 5000)');
  end if;

  for x in select * from jsonb_array_elements(p_rows) loop
    v_ma := trim(coalesce(x->>'ma_sp', ''));
    v_th := (x->>'thang')::int;
    v_sl := nullif(x->>'so_luong', '')::numeric;
    if not exists (select 1 from master_products where ma_sp = v_ma) then
      return jsonb_build_object('ok', false, 'error', 'Mã SP không có trong danh mục: ' || v_ma);
    end if;
    if v_th is null or v_th < 1 or v_th > 12 then
      return jsonb_build_object('ok', false, 'error', 'Tháng không hợp lệ (' || v_ma || ')');
    end if;
    if v_sl is not null and v_sl < 0 then
      return jsonb_build_object('ok', false, 'error', 'Số lượng âm (' || v_ma || ' T' || v_th || ')');
    end if;

    select so_luong into v_cu from forecast_san_luong where nam = p_nam and ma_sp = v_ma and thang = v_th for update;
    if not found then v_cu := null; end if;
    if v_cu is not distinct from v_sl then continue; end if;

    if v_sl is null then
      delete from forecast_san_luong where nam = p_nam and ma_sp = v_ma and thang = v_th;
    else
      insert into forecast_san_luong (nam, ma_sp, thang, so_luong, updated_by, updated_at)
      values (p_nam, v_ma, v_th, v_sl, v_ten, v_now)
      on conflict (nam, ma_sp, thang) do update set so_luong = excluded.so_luong,
        updated_by = excluded.updated_by, updated_at = excluded.updated_at;
    end if;
    insert into forecast_san_luong_log (nam, ma_sp, thang, cu, moi, ghi_chu, nguoi, thoi_diem)
    values (p_nam, v_ma, v_th, v_cu, v_sl, coalesce(trim(p_ghi_chu), ''), v_ten, v_now);
    n_doi := n_doi + 1;
  end loop;

  return jsonb_build_object('ok', true, 'so_o_doi', n_doi);
end;
$$;
revoke execute on function forecast_luu(int, jsonb, text) from public, anon;
grant execute on function forecast_luu(int, jsonb, text) to authenticated;
