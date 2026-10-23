-- ============================================================================
-- Phase T159 — P-Chart NG Bavia (Chất lượng › Biểu đồ chất lượng › tab "P-Chart NG Bavia").
-- Giống P-Chart NG OQC (T135): CL từng mã do QC Manager đặt + khoá, mục tiêu chung
-- ma_sp='*' + mục tiêu riêng. Bảng cấu hình RIÊNG cho Bavia (mức NG Bavia khác OQC).
--
-- Dữ liệu: hàm bavia_ng_du_lieu(p_tu, p_den) gộp 2 nguồn
--   - Quá khứ (T158): bavia_sx_qua_khu (SL sản xuất) + bavia_ng_qua_khu (NG theo lỗi)
--   - MES: cd_ng_khai_bao cong_doan='Bavia' (ngày = ngày ca của Line) + bavia_thung (OK);
--     SL kiểm = OK + NG. Chỉ lấy ngày SAU ngày cuối của dữ liệu quá khứ để không cộng trùng.
-- An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create table if not exists public.bavia_ng_cau_hinh (
  ma_sp text primary key,                      -- '*' = mục tiêu chung
  cl numeric check (cl is null or (cl >= 0 and cl < 1)),
  cl_nguoi text,
  cl_luc timestamptz,
  muc_tieu numeric check (muc_tieu is null or (muc_tieu > 0 and muc_tieu < 1)),
  mt_nguoi text,
  mt_luc timestamptz,
  check (ma_sp <> '*' or cl is null)
);

create table if not exists public.bavia_ng_cau_hinh_log (
  id bigserial primary key,
  ma_sp text not null,
  loai text not null check (loai in ('cl', 'muc_tieu')),
  gia_tri_cu numeric,
  gia_tri_moi numeric,
  ly_do text,
  nguoi text,
  nguoi_uid uuid,
  luc timestamptz not null default now()
);
create index if not exists idx_bavia_ng_cau_hinh_log_ma on public.bavia_ng_cau_hinh_log (ma_sp, luc desc);

alter table public.bavia_ng_cau_hinh enable row level security;
alter table public.bavia_ng_cau_hinh_log enable row level security;
revoke all on public.bavia_ng_cau_hinh, public.bavia_ng_cau_hinh_log from anon, authenticated;
grant select on public.bavia_ng_cau_hinh, public.bavia_ng_cau_hinh_log to authenticated;
drop policy if exists "bavia ng cau hinh read" on public.bavia_ng_cau_hinh;
create policy "bavia ng cau hinh read" on public.bavia_ng_cau_hinh for select to authenticated using (true);
drop policy if exists "bavia ng cau hinh log read" on public.bavia_ng_cau_hinh_log;
create policy "bavia ng cau hinh log read" on public.bavia_ng_cau_hinh_log for select to authenticated using (true);

-- p_loai: 'cl' | 'muc_tieu'; p_gia_tri: tỷ lệ (0..1), null = xoá (chỉ mục tiêu riêng).
create or replace function public.bavia_ng_dat(p_ma_sp text, p_loai text, p_gia_tri numeric, p_ly_do text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cu public.bavia_ng_cau_hinh%rowtype; v_nguoi text; v_cu numeric;
begin
  if auth.uid() is null or not public.has_role('admin', 'qc_manager') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ QC Manager / admin được đặt CL và mục tiêu NG');
  end if;
  if p_loai not in ('cl', 'muc_tieu') then return jsonb_build_object('ok', false, 'error', 'Loại không hợp lệ'); end if;
  if p_ma_sp is null or (p_ma_sp <> '*' and not exists (select 1 from master_products where ma_sp = p_ma_sp)) then
    return jsonb_build_object('ok', false, 'error', 'Mã SP không có trong danh mục');
  end if;
  if p_ma_sp = '*' and p_loai = 'cl' then return jsonb_build_object('ok', false, 'error', 'CL chỉ đặt theo từng mã'); end if;
  if p_gia_tri is not null and (p_gia_tri < 0 or p_gia_tri >= 1 or (p_loai = 'muc_tieu' and p_gia_tri = 0)) then
    return jsonb_build_object('ok', false, 'error', 'Giá trị phải trong khoảng 0–100%');
  end if;
  if p_loai = 'cl' and p_gia_tri is null then return jsonb_build_object('ok', false, 'error', 'CL không được để trống'); end if;
  if p_ma_sp = '*' and p_gia_tri is null then return jsonb_build_object('ok', false, 'error', 'Mục tiêu chung không được để trống'); end if;

  select * into cu from bavia_ng_cau_hinh where ma_sp = p_ma_sp for update;
  v_cu := case when p_loai = 'cl' then cu.cl else cu.muc_tieu end;
  if p_loai = 'cl' and v_cu is not null and v_cu is distinct from p_gia_tri and length(trim(coalesce(p_ly_do, ''))) < 3 then
    return jsonb_build_object('ok', false, 'error', 'CL đã khoá — đặt lại phải nhập lý do');
  end if;
  if v_cu is not distinct from p_gia_tri then return jsonb_build_object('ok', true, 'khong_doi', true); end if;

  select coalesce(nullif(trim(coalesce(username, '') || '_' || coalesce(full_name, '')), '_'), email) into v_nguoi
    from user_roles where user_id = auth.uid();

  insert into bavia_ng_cau_hinh (ma_sp) values (p_ma_sp) on conflict (ma_sp) do nothing;
  if p_loai = 'cl' then
    update bavia_ng_cau_hinh set cl = p_gia_tri, cl_nguoi = v_nguoi, cl_luc = now() where ma_sp = p_ma_sp;
  else
    update bavia_ng_cau_hinh set muc_tieu = p_gia_tri, mt_nguoi = v_nguoi, mt_luc = now() where ma_sp = p_ma_sp;
  end if;
  insert into bavia_ng_cau_hinh_log (ma_sp, loai, gia_tri_cu, gia_tri_moi, ly_do, nguoi, nguoi_uid)
    values (p_ma_sp, p_loai, v_cu, p_gia_tri, nullif(trim(coalesce(p_ly_do, '')), ''), v_nguoi, auth.uid());
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bavia_ng_dat(text, text, numeric, text) from public, anon;
grant execute on function public.bavia_ng_dat(text, text, numeric, text) to authenticated;

-- Dữ liệu theo ngày × mã: { sx: [[ngay, ma_sp, sl_kiem, nguon]], ng: [[ngay, ma_sp, loai_ng, sl, ghi_chu]] }
-- nguon: 'excel' | 'mes'. Chạy quyền người gọi (các bảng nguồn authenticated đã đọc được).
create or replace function public.bavia_ng_du_lieu(p_tu date, p_den date)
returns jsonb language sql stable security invoker set search_path = public as $$
  with moc as (select coalesce(max(ngay), date '2000-01-01') m from bavia_sx_qua_khu),
  ng_mes as (
    select coalesce(t.ngay, (g.ngay_gio at time zone 'Asia/Ho_Chi_Minh')::date) ngay, g.ma_sp, g.loai_ng, g.so_luong, g.ghi_chu
    from cd_ng_khai_bao g left join cd_tram_hien_tai t on t.id_tram = g.id_tram
    where g.cong_doan = 'Bavia' and g.ngay_gio >= p_tu::timestamp - interval '2 day' and g.ngay_gio < p_den::timestamp + interval '3 day'
  ),
  ng_mes_k as (select n.* from ng_mes n, moc where n.ngay between p_tu and p_den and n.ngay > moc.m),
  ok_mes as (
    select b.ngay, b.ma_sp, sum(b.so_luong) ok from bavia_thung b, moc
    where b.ngay between p_tu and p_den and b.ngay > moc.m group by 1, 2
  ),
  sx_mes as (
    select coalesce(o.ngay, n.ngay) ngay, coalesce(o.ma_sp, n.ma_sp) ma_sp, coalesce(o.ok, 0) + coalesce(n.ng, 0) n
    from ok_mes o full join (select ngay, ma_sp, sum(so_luong) ng from ng_mes_k group by 1, 2) n
      on n.ngay = o.ngay and n.ma_sp = o.ma_sp
  ),
  sx as (
    select ngay, ma_sp, sum(so_luong) n, 'excel' nguon from bavia_sx_qua_khu where ngay between p_tu and p_den group by 1, 2
    union all select ngay, ma_sp, n, 'mes' from sx_mes where n > 0
  ),
  ng as (
    select ngay, ma_sp, loai_ng, sum(so_luong) sl, string_agg(distinct nullif(loai_ng_goc, loai_ng), ', ') gc
      from bavia_ng_qua_khu where ngay between p_tu and p_den group by 1, 2, 3
    union all select ngay, ma_sp, loai_ng, sum(so_luong), string_agg(distinct ghi_chu, ', ') from ng_mes_k group by 1, 2, 3
  )
  select jsonb_build_object(
    'sx', coalesce((select jsonb_agg(jsonb_build_array(ngay, ma_sp, n, nguon)) from sx), '[]'::jsonb),
    'ng', coalesce((select jsonb_agg(jsonb_build_array(ngay, ma_sp, loai_ng, sl, gc)) from ng), '[]'::jsonb));
$$;
revoke all on function public.bavia_ng_du_lieu(date, date) from public, anon;
grant execute on function public.bavia_ng_du_lieu(date, date) to authenticated;

-- Mục tiêu chung mặc định 2% (≈ mức NG Bavia TB 2026 theo Excel; QC Manager đặt lại trên màn hình).
insert into public.bavia_ng_cau_hinh (ma_sp, muc_tieu, mt_nguoi, mt_luc)
values ('*', 0.02, 'Mặc định T159', now())
on conflict (ma_sp) do nothing;
