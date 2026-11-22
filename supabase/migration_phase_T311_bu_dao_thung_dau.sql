-- T311 (22/11/2026): bù dao + kiểm thùng đầu — Việc 2 trong SPEC_Quan_ly_thay_dao_MES.md.
--   * Bù dao: trên dao đang lắp, nhập trục (X/Y/Z/H chiều dài/D bán kính), số bù mm (≠ 0, |số| ≤ 0,1), lý do.
--     Ghi vào gc_dao_bu (chỉ qua RPC gc_dao_bu, không sửa/xoá).
--   * Sau Thay / Lắp dao từ tủ / Xoay cạnh / Bù dao → máy có cờ "Thùng đầu — chờ kiểm" (gc_thung_dau).
--     Mỗi máy tối đa 1 cờ đang mở; thay đổi mới khi cờ còn mở → cập nhật giờ + nối nội dung.
--     Thùng đầu = thùng đầu tiên của máy Xong sau lần thay đổi cuối (chưa Xong thì thùng đang làm).
--   * Tổ trưởng / QC / quản lý bấm Đạt hoặc Không đạt (Không đạt bắt buộc ghi chú). Cờ chỉ cảnh báo,
--     KHÔNG khoá Xong thùng.
-- An toàn chạy lại. Chạy 3 phần: a (bảng), b (hàm gắn cờ + gc_dao_lap_mot + gc_dao_xoay_canh), c (RPC bù + kiểm).
-- Trạng thái: Đã chạy STAGING + PROD 22/11/2026.

-- ===== Phần a =====
create table if not exists public.gc_thung_dau (
  id bigserial primary key,
  ma_may text not null,
  luc timestamptz not null default now(),          -- lần thay đổi cuối
  su_kien text not null default '',
  tao_luc timestamptz not null default now(),
  tao_boi text not null default '',
  ket_qua text check (ket_qua is null or ket_qua in ('dat','khong_dat')),
  id_tem_buoc bigint,
  tag_no text,
  kiem_luc timestamptz,
  kiem_boi text,
  ghi_chu text not null default ''
);
create unique index if not exists ux_gc_thung_dau_mo on public.gc_thung_dau (ma_may) where ket_qua is null;
create index if not exists idx_gc_thung_dau_tao on public.gc_thung_dau (tao_luc desc);

create table if not exists public.gc_dao_bu (
  id bigserial primary key,
  id_lap bigint not null references public.gc_dao_tren_may(id),
  ma_may text not null,
  vi_tri text not null,
  ma_dao text not null,
  truc text not null check (truc in ('X','Y','Z','H','D')),
  so_bu numeric not null check (so_bu <> 0 and abs(so_bu) <= 0.1),
  ly_do text not null,
  ghi_chu text not null default '',
  luc timestamptz not null default now(),
  nguoi text not null default '',
  id_thung_dau bigint references public.gc_thung_dau(id)
);
create index if not exists idx_gc_dao_bu_lap on public.gc_dao_bu (id_lap);
create index if not exists idx_gc_dao_bu_luc on public.gc_dao_bu (luc desc);

alter table public.gc_thung_dau enable row level security;
alter table public.gc_dao_bu enable row level security;
drop policy if exists gc_thung_dau_doc on public.gc_thung_dau;
create policy gc_thung_dau_doc on public.gc_thung_dau for select to authenticated using (true);
drop policy if exists gc_dao_bu_doc on public.gc_dao_bu;
create policy gc_dao_bu_doc on public.gc_dao_bu for select to authenticated using (true);
revoke all on public.gc_thung_dau, public.gc_dao_bu from anon;
grant select on public.gc_thung_dau, public.gc_dao_bu to authenticated;

-- ===== Phần b =====
-- Nội bộ: gắn / cập nhật cờ thùng đầu của máy. Trả id cờ.
create or replace function public.gc_thung_dau_gan(p_ma_may text, p_su_kien text, p_nguoi text)
returns bigint language plpgsql security definer set search_path to 'public' as $$
declare v_id bigint;
begin
  update gc_thung_dau set luc = now(),
    su_kien = left(case when su_kien = '' then p_su_kien else su_kien || ' · ' || p_su_kien end, 500)
  where ma_may = p_ma_may and ket_qua is null
  returning id into v_id;
  if v_id is null then
    insert into gc_thung_dau (ma_may, su_kien, tao_boi) values (p_ma_may, left(p_su_kien, 500), coalesce(p_nguoi, ''))
    returning id into v_id;
  end if;
  return v_id;
end $$;
revoke execute on function public.gc_thung_dau_gan(text, text, text) from public, anon, authenticated;

-- gc_dao_lap_mot: lắp dao lấy từ tủ (lắp mới / thay / lắp theo bộ) → gắn cờ thùng đầu
create or replace function public.gc_dao_lap_mot(p_ma_may text, p_vi_tri text, p_id_dao bigint, p_so_luong numeric,
  p_nguon text, p_so_ct_dau numeric, p_ma_sp text, p_buoc integer, p_ghi_chu text, p_nguoi text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_d gc_dao_cu%rowtype; v_vt text := upper(trim(coalesce(p_vi_tri, ''))); v_sl numeric := coalesce(p_so_luong, 1);
  v_kq jsonb; v_id bigint;
begin
  if v_vt = '' then return jsonb_build_object('ok', false, 'error', 'Nhập vị trí (VD T01)'); end if;
  select * into v_d from gc_dao_cu where id = p_id_dao;
  if not found then return jsonb_build_object('ok', false, 'error', 'Chưa chọn mã dao đúng danh mục'); end if;
  if v_sl <= 0 then return jsonb_build_object('ok', false, 'error', 'Số lượng phải > 0'); end if;
  if coalesce(p_so_ct_dau, 0) < 0 then return jsonb_build_object('ok', false, 'error', 'Số chi tiết đã chạy phải ≥ 0'); end if;
  if exists (select 1 from gc_dao_tren_may where ma_may = p_ma_may and vi_tri = v_vt and thao_luc is null) then
    return jsonb_build_object('ok', false, 'error', p_ma_may || ' vị trí ' || v_vt || ' đang có dao — bấm Thay');
  end if;
  if coalesce(p_nguon, 'tu') = 'tu' then
    v_kq := gc_dao_cu_ghi('xuat', p_id_dao, v_sl, p_ma_may, 'Thay dao', v_vt);
    if not (v_kq->>'ok')::boolean then return v_kq; end if;
  end if;
  insert into gc_dao_tren_may (ma_may, vi_tri, id_dao, ma_dao, so_luong, ma_sp, buoc, nguon, so_ct_dau, lap_boi, ghi_chu)
  values (p_ma_may, v_vt, p_id_dao, v_d.ma_dao, v_sl, trim(coalesce(p_ma_sp, '')), coalesce(p_buoc, 1),
    case when p_nguon = 'may' then 'may' else 'tu' end,
    case when p_nguon = 'may' then coalesce(p_so_ct_dau, 0) else 0 end, coalesce(p_nguoi, ''), trim(coalesce(p_ghi_chu, '')))
  returning id into v_id;
  if coalesce(p_nguon, 'tu') <> 'may' then
    perform gc_thung_dau_gan(p_ma_may, 'Dao mới ' || v_vt, p_nguoi);   -- T311
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke execute on function public.gc_dao_lap_mot(text, text, bigint, numeric, text, numeric, text, integer, text, text) from public, anon, authenticated;

-- gc_dao_xoay_canh (T309) + gắn cờ thùng đầu
create or replace function public.gc_dao_xoay_canh(p_id_lap bigint, p_ly_do text, p_ghi_chu text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me record; t gc_dao_tren_may%rowtype; v_so_canh int; v_ct numeric; v_dung numeric; v_tt int;
  v_ld text := trim(coalesce(p_ly_do, '')); v_now timestamptz := now(); v_id bigint;
begin
  select * into v_me from gc_dao_cu_nguoi('dung');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if v_ld = '' then return jsonb_build_object('ok', false, 'error', 'Chọn lý do xoay'); end if;
  select * into t from gc_dao_tren_may where id = p_id_lap for update;
  if not found or t.thao_luc is not null then return jsonb_build_object('ok', false, 'error', 'Dao này đã được tháo — tải lại trang'); end if;
  select so_canh into v_so_canh from gc_dao_cu where id = t.id_dao;
  if t.canh >= coalesce(v_so_canh, 1) then
    return jsonb_build_object('ok', false, 'error', 'Đã hết cạnh (' || t.canh || '/' || coalesce(v_so_canh, 1) || ') — bấm Thay');
  end if;
  select so_ct, so_dung, tuoi_tho into v_ct, v_dung, v_tt from gc_dao_tren_may_v where id = p_id_lap;
  update gc_dao_tren_may set thao_luc = v_now, thao_boi = v_me.o_ten, ly_do_thao = v_ld, xu_ly_cu = 'xoay',
    so_ct_thuc_te = v_ct, so_dung_thuc_te = v_dung, tuoi_tho_luc_thao = v_tt,
    ghi_chu = trim(both ' · ' from ghi_chu || ' · ' || trim(coalesce(p_ghi_chu, '')))
  where id = p_id_lap;
  insert into gc_dao_tren_may (ma_may, vi_tri, id_dao, ma_dao, so_luong, ma_sp, buoc, nguon, so_ct_dau, lap_luc, lap_boi, canh, ghi_chu)
  values (t.ma_may, t.vi_tri, t.id_dao, t.ma_dao, t.so_luong, t.ma_sp, t.buoc, 'tu', 0, v_now, v_me.o_ten, t.canh + 1, '')
  returning id into v_id;
  perform gc_thung_dau_gan(t.ma_may, 'Xoay cạnh ' || t.vi_tri, v_me.o_ten);   -- T311
  return jsonb_build_object('ok', true, 'so_ct', v_ct, 'so_dung', v_dung, 'tuoi_tho', v_tt, 'canh', t.canh + 1,
    'so_canh', v_so_canh, 'id_moi', v_id);
end $$;

-- ===== Phần c =====
create or replace function public.gc_dao_bu(p_id_lap bigint, p_truc text, p_so_bu numeric, p_ly_do text, p_ghi_chu text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me record; t gc_dao_tren_may%rowtype; v_truc text := upper(trim(coalesce(p_truc, '')));
  v_ld text := trim(coalesce(p_ly_do, '')); v_td bigint; v_id bigint;
begin
  select * into v_me from gc_dao_cu_nguoi('dung');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if v_truc not in ('X','Y','Z','H','D') then return jsonb_build_object('ok', false, 'error', 'Chọn trục bù'); end if;
  if p_so_bu is null or p_so_bu = 0 then return jsonb_build_object('ok', false, 'error', 'Nhập số bù (mm, khác 0)'); end if;
  if abs(p_so_bu) > 0.1 then return jsonb_build_object('ok', false, 'error', 'Mỗi lần bù tối đa 0,1 mm'); end if;
  if v_ld = '' then return jsonb_build_object('ok', false, 'error', 'Chọn lý do bù'); end if;
  select * into t from gc_dao_tren_may where id = p_id_lap;
  if not found or t.thao_luc is not null then return jsonb_build_object('ok', false, 'error', 'Dao này đã được tháo — tải lại trang'); end if;
  v_td := gc_thung_dau_gan(t.ma_may, 'Bù ' || t.vi_tri || ' ' || v_truc || ' ' || replace(to_char(p_so_bu, 'FMS0.000'), '.', ','), v_me.o_ten);
  insert into gc_dao_bu (id_lap, ma_may, vi_tri, ma_dao, truc, so_bu, ly_do, ghi_chu, nguoi, id_thung_dau)
  values (t.id, t.ma_may, t.vi_tri, t.ma_dao, v_truc, p_so_bu, v_ld, trim(coalesce(p_ghi_chu, '')), v_me.o_ten, v_td)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'id_thung_dau', v_td);
end $$;
revoke execute on function public.gc_dao_bu(bigint, text, numeric, text, text) from public, anon;
grant execute on function public.gc_dao_bu(bigint, text, numeric, text, text) to authenticated;

-- Đạt / Không đạt thùng đầu
create or replace function public.gc_thung_dau_kiem(p_id bigint, p_ket_qua text, p_ghi_chu text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_role text; v_ten text; f gc_thung_dau%rowtype; b record; v_gc text := trim(coalesce(p_ghi_chu, ''));
begin
  select role, coalesce(nullif(trim(full_name), ''), nullif(trim(username), ''), email, '') into v_role, v_ten
    from user_roles where user_id = auth.uid();
  if v_role is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if v_role not in ('admin','quan_ly_bo_phan','nhan_vien_thong_ke','qlsx_truong_phong','truong_ca','ipqc','qc_manager') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ tổ trưởng / QC / quản lý được xác nhận thùng đầu');
  end if;
  if coalesce(p_ket_qua, '') not in ('dat','khong_dat') then return jsonb_build_object('ok', false, 'error', 'Chọn Đạt / Không đạt'); end if;
  if p_ket_qua = 'khong_dat' and v_gc = '' then return jsonb_build_object('ok', false, 'error', 'Không đạt: ghi chú kích thước sai'); end if;
  select * into f from gc_thung_dau where id = p_id for update;
  if not found or f.ket_qua is not null then return jsonb_build_object('ok', false, 'error', 'Cờ này đã được xác nhận — tải lại trang'); end if;
  select id, tag_no into b from gc_tem_buoc
   where ma_may = f.ma_may and bo_luc is null and (xong_luc is null or xong_luc >= f.luc)
   order by xong_luc asc nulls last, bat_dau asc limit 1;
  if b.id is null then return jsonb_build_object('ok', false, 'error', 'Máy chưa có thùng nào sau lần thay / bù dao'); end if;
  update gc_thung_dau set ket_qua = p_ket_qua, id_tem_buoc = b.id, tag_no = b.tag_no, kiem_luc = now(), kiem_boi = v_ten, ghi_chu = v_gc
  where id = p_id;
  return jsonb_build_object('ok', true, 'tag_no', b.tag_no);
end $$;
revoke execute on function public.gc_thung_dau_kiem(bigint, text, text) from public, anon;
grant execute on function public.gc_thung_dau_kiem(bigint, text, text) to authenticated;
