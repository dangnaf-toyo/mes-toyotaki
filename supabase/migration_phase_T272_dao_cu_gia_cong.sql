-- T272: Kho dao cụ bộ phận Gia công — Đợt 1: danh mục + tồn kho + sổ giao dịch.
-- Mã N-LOẠI-KÍCH THƯỚC-STT (Danh mục → Quy tắc đặt tên → Dao cụ).
-- Tồn chia 3 trạng thái: Mới (trong tủ) · Đang dùng (trên máy) · NG (chờ mài / chờ trả kho).
-- Phiếu: nhap (+Mới) · xuat (Mới → Đang dùng) · tra (Đang dùng → Mới) · ng (Đang dùng → NG)
--        · mai (NG mài xong → Mới) · huy_ng (NG ra khỏi bộ phận: trả kho / thanh lý) · kiem_ke (đặt lại 3 số).
-- Quyền: quản lý (danh mục, nhập, trả NG, kiểm kê) = admin / quan_ly_bo_phan / nhan_vien_thong_ke / qlsx_truong_phong;
--        xuất / trả / báo NG thêm truong_ca. Mọi tài khoản đăng nhập được xem.

create table if not exists public.gc_dao_cu (
  id bigserial primary key,
  ma_dao text not null unique,
  ten_chuan text not null,
  nhom text not null check (nhom in ('D','M','H','C','K','P')),
  quy_cach text not null default '',
  ten_cu text not null default '',
  hang text not null default '',
  ma_sp_dung text not null default '',
  dvt text not null default 'Cái',
  quan_ly text not null default 'so_luong' check (quan_ly in ('so_luong','tung_cai')),
  tuoi_tho_theo text not null default 'chi_tiet' check (tuoi_tho_theo in ('chi_tiet','lo_ren','khong')),
  tuoi_tho_chuan integer check (tuoi_tho_chuan is null or tuoi_tho_chuan > 0),
  ton_toi_thieu numeric not null default 0 check (ton_toi_thieu >= 0),
  don_gia numeric check (don_gia is null or don_gia >= 0),
  vi_tri text not null default '',
  ghi_chu text not null default '',
  dang_dung boolean not null default true,
  ton_moi numeric not null default 0 check (ton_moi >= 0),
  ton_dang_dung numeric not null default 0 check (ton_dang_dung >= 0),
  ton_ng numeric not null default 0 check (ton_ng >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.gc_dao_cu_giao_dich (
  id bigserial primary key,
  thoi_diem timestamptz not null default now(),
  loai text not null check (loai in ('nhap','xuat','tra','ng','mai','huy_ng','kiem_ke','ton_dau')),
  id_dao bigint not null references public.gc_dao_cu(id),
  ma_dao text not null,
  so_luong numeric not null default 0,
  d_moi numeric not null default 0,
  d_dang_dung numeric not null default 0,
  d_ng numeric not null default 0,
  ton_moi_sau numeric not null default 0,
  ton_dang_dung_sau numeric not null default 0,
  ton_ng_sau numeric not null default 0,
  may text not null default '',
  ly_do text not null default '',
  ghi_chu text not null default '',
  nguoi text not null default '',
  nguoi_uid uuid,
  vai_tro text not null default ''
);
create index if not exists gc_dao_cu_gd_dao_idx on public.gc_dao_cu_giao_dich (id_dao, thoi_diem desc);
create index if not exists gc_dao_cu_gd_tg_idx on public.gc_dao_cu_giao_dich (thoi_diem desc);

alter table public.gc_dao_cu enable row level security;
alter table public.gc_dao_cu_giao_dich enable row level security;
drop policy if exists "auth read" on public.gc_dao_cu;
create policy "auth read" on public.gc_dao_cu for select to authenticated using (true);
drop policy if exists "auth read" on public.gc_dao_cu_giao_dich;
create policy "auth read" on public.gc_dao_cu_giao_dich for select to authenticated using (true);
revoke all on public.gc_dao_cu, public.gc_dao_cu_giao_dich from anon;
revoke insert, update, delete on public.gc_dao_cu, public.gc_dao_cu_giao_dich from authenticated;
grant select on public.gc_dao_cu, public.gc_dao_cu_giao_dich to authenticated;

-- Người thao tác + kiểm quyền
create or replace function public.gc_dao_cu_nguoi(p_quyen text, out o_loi text, out o_ten text, out o_role text)
returns record language plpgsql stable security definer set search_path to 'public' as $$
declare v_role text; v_ten text;
begin
  select role, coalesce(nullif(trim(full_name), ''), nullif(trim(username), ''), email, '')
    into v_role, v_ten from public.user_roles where user_id = auth.uid();
  o_role := coalesce(v_role, ''); o_ten := coalesce(v_ten, '');
  if v_role is null then o_loi := 'Cần đăng nhập'; return; end if;
  if p_quyen = 'quan_ly' and v_role not in ('admin','quan_ly_bo_phan','nhan_vien_thong_ke','qlsx_truong_phong') then
    o_loi := 'Chỉ quản lý bộ phận / thống kê / admin được thao tác'; return;
  end if;
  if p_quyen = 'dung' and v_role not in ('admin','quan_ly_bo_phan','nhan_vien_thong_ke','qlsx_truong_phong','truong_ca') then
    o_loi := 'Chỉ trưởng ca / quản lý bộ phận / thống kê / admin được ghi xuất dao'; return;
  end if;
end $$;

-- Thêm / sửa 1 mã dao (không sửa tồn — tồn chỉ đổi qua phiếu)
create or replace function public.gc_dao_cu_luu(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me record; v_id bigint := nullif(p->>'id', '')::bigint; v_ma text := upper(trim(coalesce(p->>'ma_dao', '')));
  v_ten text := trim(coalesce(p->>'ten_chuan', ''));
begin
  select * into v_me from gc_dao_cu_nguoi('quan_ly');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if v_ma = '' then return jsonb_build_object('ok', false, 'error', 'Nhập mã dao'); end if;
  if v_ten = '' then return jsonb_build_object('ok', false, 'error', 'Nhập tên chuẩn'); end if;
  if exists (select 1 from gc_dao_cu where upper(ma_dao) = v_ma and id is distinct from v_id) then
    return jsonb_build_object('ok', false, 'error', 'Mã đã có: ' || v_ma);
  end if;
  if v_id is null then
    insert into gc_dao_cu (ma_dao, ten_chuan, nhom, quy_cach, hang, ma_sp_dung, dvt, quan_ly, tuoi_tho_theo,
      tuoi_tho_chuan, ton_toi_thieu, don_gia, vi_tri, ghi_chu, dang_dung)
    values (v_ma, v_ten, coalesce(nullif(p->>'nhom', ''), left(v_ma, 1)), trim(coalesce(p->>'quy_cach', '')),
      trim(coalesce(p->>'hang', '')), trim(coalesce(p->>'ma_sp_dung', '')), coalesce(nullif(trim(p->>'dvt'), ''), 'Cái'),
      coalesce(nullif(p->>'quan_ly', ''), 'so_luong'), coalesce(nullif(p->>'tuoi_tho_theo', ''), 'chi_tiet'),
      nullif(p->>'tuoi_tho_chuan', '')::int, coalesce(nullif(p->>'ton_toi_thieu', '')::numeric, 0),
      nullif(p->>'don_gia', '')::numeric, trim(coalesce(p->>'vi_tri', '')), trim(coalesce(p->>'ghi_chu', '')),
      coalesce((p->>'dang_dung')::boolean, true))
    returning id into v_id;
  else
    if exists (select 1 from gc_dao_cu_giao_dich where id_dao = v_id) and exists (select 1 from gc_dao_cu where id = v_id and ma_dao <> v_ma) then
      return jsonb_build_object('ok', false, 'error', 'Mã đã có giao dịch — không đổi mã');
    end if;
    update gc_dao_cu set ma_dao = v_ma, ten_chuan = v_ten, nhom = coalesce(nullif(p->>'nhom', ''), left(v_ma, 1)),
      quy_cach = trim(coalesce(p->>'quy_cach', '')), hang = trim(coalesce(p->>'hang', '')),
      ma_sp_dung = trim(coalesce(p->>'ma_sp_dung', '')), dvt = coalesce(nullif(trim(p->>'dvt'), ''), 'Cái'),
      quan_ly = coalesce(nullif(p->>'quan_ly', ''), 'so_luong'), tuoi_tho_theo = coalesce(nullif(p->>'tuoi_tho_theo', ''), 'chi_tiet'),
      tuoi_tho_chuan = nullif(p->>'tuoi_tho_chuan', '')::int, ton_toi_thieu = coalesce(nullif(p->>'ton_toi_thieu', '')::numeric, 0),
      don_gia = nullif(p->>'don_gia', '')::numeric, vi_tri = trim(coalesce(p->>'vi_tri', '')),
      ghi_chu = trim(coalesce(p->>'ghi_chu', '')), dang_dung = coalesce((p->>'dang_dung')::boolean, true), updated_at = now()
    where id = v_id;
    if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy mã dao'); end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
exception when check_violation then
  return jsonb_build_object('ok', false, 'error', 'Giá trị không hợp lệ (nhóm / tuổi thọ / tồn tối thiểu / giá)');
end $$;

-- Ghi 1 phiếu
create or replace function public.gc_dao_cu_ghi(p_loai text, p_id_dao bigint, p_so_luong numeric,
  p_may text default null, p_ly_do text default null, p_ghi_chu text default null,
  p_moi numeric default null, p_dang_dung numeric default null, p_ng numeric default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me record; v_d gc_dao_cu%rowtype; v_sl numeric := coalesce(p_so_luong, 0);
  a numeric := 0; b numeric := 0; c numeric := 0; v_id bigint; v_ld text := trim(coalesce(p_ly_do, ''));
begin
  if p_loai not in ('nhap','xuat','tra','ng','mai','huy_ng','kiem_ke') then
    return jsonb_build_object('ok', false, 'error', 'Loại phiếu không hợp lệ');
  end if;
  select * into v_me from gc_dao_cu_nguoi(case when p_loai in ('xuat','tra','ng') then 'dung' else 'quan_ly' end);
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  select * into v_d from gc_dao_cu where id = p_id_dao for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy mã dao'); end if;
  if p_loai <> 'kiem_ke' and v_sl <= 0 then return jsonb_build_object('ok', false, 'error', 'Số lượng phải > 0'); end if;
  if p_loai in ('ng','huy_ng','kiem_ke') and v_ld = '' then
    return jsonb_build_object('ok', false, 'error', case p_loai when 'ng' then 'Chọn lý do NG' when 'huy_ng' then 'Chọn nơi chuyển NG' else 'Nhập lý do kiểm kê' end);
  end if;
  if p_loai = 'nhap' then a := v_sl;
  elsif p_loai = 'xuat' then a := -v_sl; b := v_sl;
  elsif p_loai = 'tra' then a := v_sl; b := -v_sl;
  elsif p_loai = 'ng' then b := -v_sl; c := v_sl;
  elsif p_loai = 'mai' then c := -v_sl; a := v_sl;
  elsif p_loai = 'huy_ng' then c := -v_sl;
  else
    if p_moi is null or p_dang_dung is null or p_ng is null or p_moi < 0 or p_dang_dung < 0 or p_ng < 0 then
      return jsonb_build_object('ok', false, 'error', 'Nhập đủ số thực tế Mới / Đang dùng / NG (≥ 0)');
    end if;
    a := p_moi - v_d.ton_moi; b := p_dang_dung - v_d.ton_dang_dung; c := p_ng - v_d.ton_ng;
    v_sl := abs(a) + abs(b) + abs(c);
  end if;
  if v_d.ton_moi + a < 0 then return jsonb_build_object('ok', false, 'error', 'Không đủ tồn Mới (còn ' || v_d.ton_moi || ')'); end if;
  if v_d.ton_dang_dung + b < 0 then return jsonb_build_object('ok', false, 'error', 'Không đủ Đang dùng (còn ' || v_d.ton_dang_dung || ')'); end if;
  if v_d.ton_ng + c < 0 then return jsonb_build_object('ok', false, 'error', 'Không đủ NG (còn ' || v_d.ton_ng || ')'); end if;
  update gc_dao_cu set ton_moi = ton_moi + a, ton_dang_dung = ton_dang_dung + b, ton_ng = ton_ng + c, updated_at = now() where id = p_id_dao;
  insert into gc_dao_cu_giao_dich (loai, id_dao, ma_dao, so_luong, d_moi, d_dang_dung, d_ng, ton_moi_sau, ton_dang_dung_sau, ton_ng_sau,
    may, ly_do, ghi_chu, nguoi, nguoi_uid, vai_tro)
  values (p_loai, p_id_dao, v_d.ma_dao, v_sl, a, b, c, v_d.ton_moi + a, v_d.ton_dang_dung + b, v_d.ton_ng + c,
    trim(coalesce(p_may, '')), v_ld, trim(coalesce(p_ghi_chu, '')), v_me.o_ten, auth.uid(), v_me.o_role)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'ton_moi', v_d.ton_moi + a, 'ton_dang_dung', v_d.ton_dang_dung + b, 'ton_ng', v_d.ton_ng + c);
end $$;

revoke execute on function public.gc_dao_cu_nguoi(text) from public, anon, authenticated;
revoke execute on function public.gc_dao_cu_luu(jsonb) from public, anon;
revoke execute on function public.gc_dao_cu_ghi(text, bigint, numeric, text, text, text, numeric, numeric, numeric) from public, anon;
grant execute on function public.gc_dao_cu_luu(jsonb) to authenticated;
grant execute on function public.gc_dao_cu_ghi(text, bigint, numeric, text, text, text, numeric, numeric, numeric) to authenticated;
