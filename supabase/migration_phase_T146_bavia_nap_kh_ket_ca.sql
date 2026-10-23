-- ============================================================================
-- T146 — Bảng điều khiển Bavia (đợt 2): nạp KH từ KHSX tuần + số ca theo mã,
-- báo cáo kết ca + khoá số liệu. Nối tiếp T145 (bavia-dashboard.html).
--
-- Đã chốt với user 23/10/2026:
--   - Nạp KH lấy KH ngày của công đoạn Bavia trong cd_khsx_tuan_plan (cột theo
--     thứ của ngày). Mặc định 1 ca/ngày; trưởng ca chọn số ca (1/2) theo từng mã
--     ngay trong hộp Nạp KH, lưu bavia_so_ca theo tuần → các ngày sau trong tuần
--     dùng tiếp cho tới khi đổi. KH ca = KH ngày ÷ số ca; 1 ca/ngày thì chỉ ca
--     đầu (Ca ngày / Ca 1) có KH, ca sau KH = 0 (giống Đúc T134).
--   - Nạp lại giữa ca ghi đè KH ca và lưu nhật ký cũ → mới (bavia_kh_nhat_ky).
--   - Kết ca: Line dưới 90% KH phải ghi lý do; mọi Line phải có người thao tác
--     và người kiểm tra. Kết xong khoá số liệu ca (mọi RPC ghi của T145 đã chặn
--     ca có trong bavia_ket_ca); chỉ admin mở lại được (có lý do, ghi nhật ký).
--     Hàng còn dở trên tem Đúc và hàng đang test chuyển sang ca sau (không làm
--     gì: nguồn theo Line, test chưa kết thúc vẫn hiện ở Line ca sau).
--   - Kết ca ghi số liệu từng Line vào cd_bao_cao_ca (cong_doan 'Bavia', tổ =
--     tên Line) để Báo cáo cuối ca công đoạn đọc như cũ. KHÔNG dùng
--     cd_ket_ca_cong_doan vì hàm đó xoá cd_tram_hien_tai (Bavia cần giữ Line để
--     xem lại báo cáo / mở lại ca).
--
-- Trạng thái: Đã chạy STAGING 23/10/2026 (+ t146b sửa theo review). Đã chạy PROD 23/10/2026 (t146_bavia_nap_kh_ket_ca, bản đã sửa).
-- ============================================================================

create table if not exists public.bavia_so_ca (
  tuan_bat_dau date not null,
  ma_sp        text not null,
  so_ca        smallint not null default 1 check (so_ca in (1, 2)),
  nguoi        text,
  cap_nhat_luc timestamptz not null default now(),
  primary key (tuan_bat_dau, ma_sp)
);

create table if not exists public.bavia_kh_nhat_ky (
  id        bigserial primary key,
  ngay      date not null,
  ca        text not null,
  ten_line  text not null,
  ma_sp     text not null,
  kh_cu     numeric,
  kh_moi    numeric,
  so_ca     smallint,
  ma_cu     text,
  nguoi     text,
  luc       timestamptz not null default now()
);
create index if not exists idx_bavia_kh_nhat_ky_ca on public.bavia_kh_nhat_ky (ngay, ca);

create table if not exists public.bavia_ket_ca_nhat_ky (
  id        bigserial primary key,
  ngay      date not null,
  ca        text not null,
  hanh_dong text not null check (hanh_dong in ('ket_ca', 'mo_lai')),
  ly_do     text,
  nguoi     text,
  luc       timestamptz not null default now()
);

alter table public.bavia_so_ca enable row level security;
alter table public.bavia_kh_nhat_ky enable row level security;
alter table public.bavia_ket_ca_nhat_ky enable row level security;
drop policy if exists bavia_so_ca_doc on public.bavia_so_ca;
create policy bavia_so_ca_doc on public.bavia_so_ca for select to authenticated using (true);
drop policy if exists bavia_kh_nhat_ky_doc on public.bavia_kh_nhat_ky;
create policy bavia_kh_nhat_ky_doc on public.bavia_kh_nhat_ky for select to authenticated using (true);
drop policy if exists bavia_ket_ca_nhat_ky_doc on public.bavia_ket_ca_nhat_ky;
create policy bavia_ket_ca_nhat_ky_doc on public.bavia_ket_ca_nhat_ky for select to authenticated using (true);
revoke insert, update, delete on public.bavia_so_ca, public.bavia_kh_nhat_ky, public.bavia_ket_ca_nhat_ky from anon, authenticated;
grant select on public.bavia_so_ca, public.bavia_kh_nhat_ky, public.bavia_ket_ca_nhat_ky to authenticated;

-- ── KH ngày của 1 mã trong KHSX tuần Bavia ──────────────────────────────────
create or replace function public.bavia_kh_ngay_cua_ma(p_ngay date, p_ma_sp text)
returns numeric
language sql stable security definer set search_path = public
as $$
  select coalesce(sum(case extract(isodow from p_ngay)::int
           when 1 then t2 when 2 then t3 when 3 then t4 when 4 then t5 when 5 then t6 when 6 then t7 else cn end), 0)
  from cd_khsx_tuan_plan
  where cong_doan = 'Bavia' and ma_sp = p_ma_sp
    and tuan_bat_dau = p_ngay - (extract(isodow from p_ngay)::int - 1)
    and auth.uid() is not null;
$$;
revoke execute on function public.bavia_kh_ngay_cua_ma(date, text) from public, anon, authenticated;

-- ── Dữ liệu hộp "Nạp KH": các mã có KH ngày > 0 + số ca + Line đang chạy ────
create or replace function public.bavia_kh_du_lieu(p_ngay date, p_ca text)
returns jsonb
language sql stable security definer set search_path = public
as $$
  with tuan as (select p_ngay - (extract(isodow from p_ngay)::int - 1) as t),
  kh as (
    select k.ma_sp, max(k.ten_sp) ten_sp,
      sum(case extract(isodow from p_ngay)::int
            when 1 then k.t2 when 2 then k.t3 when 3 then k.t4 when 4 then k.t5 when 5 then k.t6 when 6 then k.t7 else k.cn end) kh_ngay
    from cd_khsx_tuan_plan k, tuan
    where k.cong_doan = 'Bavia' and k.tuan_bat_dau = tuan.t
    group by k.ma_sp
  )
  select jsonb_build_object(
    'tuan_bat_dau', (select t from tuan),
    'duyet', (select to_jsonb(d) - 'lich_su' from khsx_duyet d, tuan where d.tuan_bat_dau = tuan.t and d.cong_doan = 'Bavia' limit 1),
    'ma', (select coalesce(jsonb_agg(jsonb_build_object(
        'ma_sp', kh.ma_sp, 'ten_sp', kh.ten_sp, 'kh_ngay', kh.kh_ngay,
        'so_ca', coalesce((select s.so_ca from bavia_so_ca s, tuan where s.tuan_bat_dau = tuan.t and s.ma_sp = kh.ma_sp), 1),
        'info', bavia_thong_tin_ma(kh.ma_sp),
        'line', (select l.ten_tram from cd_tram_hien_tai l where l.cong_doan = 'Bavia' and l.ngay = p_ngay and l.ca = p_ca
                 and l.ma_sp = kh.ma_sp order by l.ten_tram limit 1)
      ) order by kh.ma_sp), '[]'::jsonb) from kh where kh.kh_ngay > 0),
    'nhat_ky', (select coalesce(jsonb_agg(to_jsonb(n) order by n.luc desc), '[]'::jsonb)
                from (select * from bavia_kh_nhat_ky where ngay = p_ngay and ca = p_ca order by luc desc limit 30) n)
  )
  where auth.uid() is not null;
$$;
revoke execute on function public.bavia_kh_du_lieu(date, text) from public, anon;
grant execute on function public.bavia_kh_du_lieu(date, text) to authenticated;

-- ── Nạp KH: p_rows = [{ma_sp, so_ca, kh_ca, ten_line}] ──────────────────────
-- Line đã mở giữ nguyên người thao tác / người kiểm tra; Line mới để trống người.
create or replace function public.bavia_nap_kh(p_ngay date, p_ca text, p_rows jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  r jsonb;
  v_tuan date := p_ngay - (extract(isodow from p_ngay)::int - 1);
  v_line cd_tram_hien_tai%rowtype;
  v_res jsonb;
  v_user text := duc_su_co_nguoi_hien_tai();
  v_kh numeric;
  v_doi int := 0;
  v_dup text;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if exists (select 1 from bavia_ket_ca where ngay = p_ngay and ca = p_ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không nạp lại KH được');
  end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Chọn Line cho ít nhất 1 mã');
  end if;
  select x->>'ten_line' into v_dup from jsonb_array_elements(p_rows) x
  where coalesce(x->>'ten_line', '') <> '' group by x->>'ten_line' having count(*) > 1 limit 1;
  if v_dup is not null then
    return jsonb_build_object('ok', false, 'error', v_dup || ' đang được gán 2 mã. Mỗi Line chỉ chạy 1 mã tại một thời điểm.');
  end if;

  for r in select * from jsonb_array_elements(p_rows) loop
    -- Lưu số ca theo tuần (dùng cho các ngày sau trong tuần)
    if coalesce((r->>'so_ca')::int, 1) in (1, 2) then
      insert into bavia_so_ca (tuan_bat_dau, ma_sp, so_ca, nguoi) values (v_tuan, r->>'ma_sp', coalesce((r->>'so_ca')::int, 1), v_user)
      on conflict (tuan_bat_dau, ma_sp) do update set so_ca = excluded.so_ca, nguoi = excluded.nguoi, cap_nhat_luc = now();
    end if;
    if coalesce(r->>'ten_line', '') = '' then continue; end if;

    v_kh := greatest(0, round(coalesce((r->>'kh_ca')::numeric, 0)));
    select * into v_line from cd_tram_hien_tai
    where cong_doan = 'Bavia' and ngay = p_ngay and ca = p_ca and ten_tram = r->>'ten_line';
    v_res := bavia_line_luu(p_ngay, p_ca, r->>'ten_line', r->>'ma_sp', v_kh,
      case when found then v_line.nguoi_thao_tac else '' end, case when found then v_line.nguoi_kiem_tra else null end);
    if not (v_res->>'ok')::boolean then
      raise exception '%', v_res->>'error' using errcode = 'P0001';
    end if;
    if not found or coalesce(v_line.kh_ca, 0) <> v_kh or v_line.ma_sp <> r->>'ma_sp' then
      insert into bavia_kh_nhat_ky (ngay, ca, ten_line, ma_sp, kh_cu, kh_moi, so_ca, ma_cu, nguoi)
      values (p_ngay, p_ca, r->>'ten_line', r->>'ma_sp', case when found then v_line.kh_ca end, v_kh,
        coalesce((r->>'so_ca')::int, 1), case when found and v_line.ma_sp <> r->>'ma_sp' then v_line.ma_sp end, v_user);
      v_doi := v_doi + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'so_line_doi', v_doi);
end $$;
revoke execute on function public.bavia_nap_kh(date, text, jsonb) from public, anon;
grant execute on function public.bavia_nap_kh(date, text, jsonb) to authenticated;

-- ── Kết ca: p_ly_do = {ten_line: lý do chưa đạt KH} ────────────────────────
create or replace function public.bavia_ket_ca_luu(p_ngay date, p_ca text, p_ly_do jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  l record;
  v_ok numeric;
  v_test numeric;
  v_thieu text[] := '{}';
  v_user text := duc_su_co_nguoi_hien_tai();
  v_ly text;
  v_note text;
  v_ket_lai boolean;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if exists (select 1 from bavia_ket_ca where ngay = p_ngay and ca = p_ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca rồi');
  end if;
  if not exists (select 1 from cd_tram_hien_tai where cong_doan = 'Bavia' and ngay = p_ngay and ca = p_ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này chưa mở Line nào');
  end if;

  for l in select * from cd_tram_hien_tai where cong_doan = 'Bavia' and ngay = p_ngay and ca = p_ca order by ten_tram loop
    if coalesce(l.nguoi_thao_tac, '') = '' then v_thieu := v_thieu || (l.ten_tram || ' chưa gán người thao tác'); end if;
    if coalesce(l.nguoi_kiem_tra, '') = '' then v_thieu := v_thieu || (l.ten_tram || ' chưa có người kiểm tra'); end if;
    select coalesce(sum(so_luong), 0) into v_ok from bavia_thung where id_tram = l.id_tram;
    if coalesce(l.kh_ca, 0) > 0 and v_ok < 0.9 * l.kh_ca
       and length(trim(coalesce(p_ly_do ->> l.ten_tram, ''))) < 3 then
      v_thieu := v_thieu || (l.ten_tram || ' đạt ' || round(v_ok / l.kh_ca * 100) || '% KH, chưa ghi lý do');
    end if;
  end loop;
  if array_length(v_thieu, 1) > 0 then
    return jsonb_build_object('ok', false, 'thieu', to_jsonb(v_thieu), 'error', array_to_string(v_thieu, '; '));
  end if;

  -- Kết lại sau khi admin mở ca? (xem phần ghi báo cáo bên dưới)
  v_ket_lai := exists (select 1 from bavia_ket_ca_nhat_ky where ngay = p_ngay and ca = p_ca and hanh_dong = 'ket_ca');

  insert into bavia_ket_ca (ngay, ca, nguoi, nguoi_uid, ly_do)
  values (p_ngay, p_ca, v_user, auth.uid(), coalesce(p_ly_do, '{}'::jsonb));
  insert into bavia_ket_ca_nhat_ky (ngay, ca, hanh_dong, nguoi) values (p_ngay, p_ca, 'ket_ca', v_user);

  -- Ghi báo cáo ca Bavia. Chỉ khi KẾT LẠI (admin đã mở ca) mới xoá dòng do lần kết trước ghi, và chỉ dòng
  -- của các Line trong ca này — không đụng dòng báo cáo Bavia ghi từ trang cũ / nhập tay (sửa theo review).
  if v_ket_lai then
    delete from cd_bao_cao_ca b
    where b.ngay = p_ngay and b.ca = p_ca and b.cong_doan = 'Bavia'
      and b.to_san_xuat in (select ten_tram from cd_tram_hien_tai where cong_doan = 'Bavia' and ngay = p_ngay and ca = p_ca);
  end if;
  for l in select * from cd_tram_hien_tai where cong_doan = 'Bavia' and ngay = p_ngay and ca = p_ca loop
    select coalesce(sum(so_luong), 0) into v_ok from bavia_thung where id_tram = l.id_tram;
    select coalesce(sum(so_luong - coalesce(sl_tra_lai, 0)), 0) into v_test from bavia_hang_test where id_tram = l.id_tram;
    v_ly := nullif(trim(coalesce(p_ly_do ->> l.ten_tram, '')), '');
    v_note := concat_ws(' · ', 'KH ' || coalesce(l.kh_ca, 0), case when v_test > 0 then 'Test ' || v_test end,
      case when v_ly is not null then 'Lý do chưa đạt KH: ' || v_ly end);
    if v_ok > 0 or coalesce(l.so_luong_ng, 0) > 0 or v_test > 0 or coalesce(l.kh_ca, 0) > 0 then
      perform cd_gop_tally_vao_bao_cao(p_ngay, p_ca, 'Bavia', l.ma_sp, l.ten_sp, l.ten_tram, v_ok, coalesce(l.so_luong_ng, 0), v_note, 0);
    end if;
  end loop;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.bavia_ket_ca_luu(date, text, jsonb) from public, anon;
grant execute on function public.bavia_ket_ca_luu(date, text, jsonb) to authenticated;

-- ── Mở lại ca đã kết: chỉ admin, bắt buộc lý do ────────────────────────────
create or replace function public.bavia_mo_lai_ca(p_ngay date, p_ca text, p_ly_do text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if not public.has_role('admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ admin mở lại được ca đã kết');
  end if;
  if length(trim(coalesce(p_ly_do, ''))) < 3 then
    return jsonb_build_object('ok', false, 'error', 'Ghi lý do mở lại ca (ít nhất 3 ký tự)');
  end if;
  delete from bavia_ket_ca where ngay = p_ngay and ca = p_ca;
  if not found then return jsonb_build_object('ok', false, 'error', 'Ca này chưa kết'); end if;
  insert into bavia_ket_ca_nhat_ky (ngay, ca, hanh_dong, ly_do, nguoi)
  values (p_ngay, p_ca, 'mo_lai', trim(p_ly_do), duc_su_co_nguoi_hien_tai());
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.bavia_mo_lai_ca(date, text, text) from public, anon;
grant execute on function public.bavia_mo_lai_ca(date, text, text) to authenticated;
