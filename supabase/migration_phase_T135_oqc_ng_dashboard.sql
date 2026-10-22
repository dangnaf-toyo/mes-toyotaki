-- ============================================================================
-- Phase T135 — Dashboard NG OQC (QC Manager › tab "NG OQC").
--
-- Dữ liệu NG đọc thẳng từ oqc_daily_inspection (authenticated đã đọc được).
-- Migration này chỉ thêm cấu hình:
--   - CL (mức thường NG%) của từng mã — QC Manager đặt rồi KHOÁ; đặt lại phải
--     có lý do. Mã chưa có CL thì dashboard không tính UCL / bất thường.
--   - Mục tiêu NG%: dòng ma_sp='*' = mục tiêu chung; mục tiêu riêng của mã
--     (nếu có) được ưu tiên.
-- Giá trị lưu dạng TỶ LỆ (0,03 = 3%). Ghi CHỈ qua RPC oqc_ng_dat (admin /
-- qc_manager), mọi thay đổi ghi oqc_ng_cau_hinh_log.
-- ============================================================================

create table if not exists public.oqc_ng_cau_hinh (
  ma_sp text primary key,                      -- '*' = mục tiêu chung
  cl numeric check (cl is null or (cl >= 0 and cl < 1)),
  cl_nguoi text,
  cl_luc timestamptz,
  muc_tieu numeric check (muc_tieu is null or (muc_tieu > 0 and muc_tieu < 1)),
  mt_nguoi text,
  mt_luc timestamptz,
  check (ma_sp <> '*' or cl is null)
);

create table if not exists public.oqc_ng_cau_hinh_log (
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
create index if not exists idx_oqc_ng_cau_hinh_log_ma on public.oqc_ng_cau_hinh_log (ma_sp, luc desc);

alter table public.oqc_ng_cau_hinh enable row level security;
alter table public.oqc_ng_cau_hinh_log enable row level security;
revoke all on public.oqc_ng_cau_hinh, public.oqc_ng_cau_hinh_log from anon, authenticated;
grant select on public.oqc_ng_cau_hinh, public.oqc_ng_cau_hinh_log to authenticated;
drop policy if exists "oqc ng cau hinh read" on public.oqc_ng_cau_hinh;
create policy "oqc ng cau hinh read" on public.oqc_ng_cau_hinh for select to authenticated using (true);
drop policy if exists "oqc ng cau hinh log read" on public.oqc_ng_cau_hinh_log;
create policy "oqc ng cau hinh log read" on public.oqc_ng_cau_hinh_log for select to authenticated using (true);

-- p_loai: 'cl' | 'muc_tieu'; p_gia_tri: tỷ lệ (0..1), null = xoá (chỉ mục tiêu riêng).
create or replace function public.oqc_ng_dat(p_ma_sp text, p_loai text, p_gia_tri numeric, p_ly_do text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cu public.oqc_ng_cau_hinh%rowtype; v_nguoi text; v_cu numeric;
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

  select * into cu from oqc_ng_cau_hinh where ma_sp = p_ma_sp for update;
  v_cu := case when p_loai = 'cl' then cu.cl else cu.muc_tieu end;
  if p_loai = 'cl' and v_cu is not null and v_cu is distinct from p_gia_tri and length(trim(coalesce(p_ly_do, ''))) < 3 then
    return jsonb_build_object('ok', false, 'error', 'CL đã khoá — đặt lại phải nhập lý do');
  end if;
  if v_cu is not distinct from p_gia_tri then return jsonb_build_object('ok', true, 'khong_doi', true); end if;

  select coalesce(nullif(trim(coalesce(username, '') || '_' || coalesce(full_name, '')), '_'), email) into v_nguoi
    from user_roles where user_id = auth.uid();

  insert into oqc_ng_cau_hinh (ma_sp) values (p_ma_sp) on conflict (ma_sp) do nothing;
  if p_loai = 'cl' then
    update oqc_ng_cau_hinh set cl = p_gia_tri, cl_nguoi = v_nguoi, cl_luc = now() where ma_sp = p_ma_sp;
  else
    update oqc_ng_cau_hinh set muc_tieu = p_gia_tri, mt_nguoi = v_nguoi, mt_luc = now() where ma_sp = p_ma_sp;
  end if;
  insert into oqc_ng_cau_hinh_log (ma_sp, loai, gia_tri_cu, gia_tri_moi, ly_do, nguoi, nguoi_uid)
    values (p_ma_sp, p_loai, v_cu, p_gia_tri, nullif(trim(coalesce(p_ly_do, '')), ''), v_nguoi, auth.uid());
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.oqc_ng_dat(text, text, numeric, text) from public, anon;
grant execute on function public.oqc_ng_dat(text, text, numeric, text) to authenticated;

-- Mục tiêu chung mặc định 3% (đã thống nhất với user 2026-10-22).
insert into public.oqc_ng_cau_hinh (ma_sp, muc_tieu, mt_nguoi, mt_luc)
values ('*', 0.03, 'Mặc định T135', now())
on conflict (ma_sp) do nothing;
