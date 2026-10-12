-- ============================================================================
-- Giai đoạn T94 — Linh kiện dự phòng khuôn (GĐ1: danh mục, gán khuôn, tồn kho
-- + sổ giao dịch). Trang: linh-kien-khuon.html.
--
-- Quyết định (user 2026-10-12):
--   - Vai trò đăng nhập MỚI 'nhan_vien_thong_ke' quản lý dự phòng khuôn:
--     danh mục, gán khuôn, nhập / sửa xong / báo phế / kiểm kê, đối chiếu.
--   - NV bảo dưỡng khuôn thay linh kiện thì tự trừ kho (xuất thay / tháo ra),
--     lưu rõ ai, ngày giờ, mục đích, khuôn, vị trí, shot khuôn lúc thay.
--   - Không quản lý serial, không quản lý tiền. Tồn 2 trạng thái:
--     Chờ sử dụng / Chờ sửa.
--   - Plunger tip / sleeve / cổ khuôn gán theo khuôn như mọi linh kiện.
--
-- Cấu trúc:
--   khuon_lk_danh_muc   — 1 dòng / linh kiện (pham_vi rieng|chung chỉ là nhãn),
--                         kèm tồn hiện tại (2 cột) — CHỈ đổi qua sổ giao dịch.
--   khuon_lk_gan        — khuôn ↔ linh kiện (nhiều-nhiều): SL lắp, vị trí,
--                         dự phòng tối thiểu cho khuôn đó.
--   khuon_lk_giao_dich  — sổ giao dịch, chỉ thêm (không sửa/xoá); sai thì
--                         lập phiếu kiểm kê điều chỉnh.
-- Mọi ghi qua RPC security definer (kiểm vai trò ở server, tên người ghi lấy
-- từ user_roles — không tin client); bảng chỉ cho authenticated đọc.
-- duc_rename_khuon chuyển khuon_lk_gan sang mã mới (sổ giao dịch giữ mã cũ).
--
-- Chạy trên staging trước (NV thống kê thử), sau đó production. Idempotent.
-- ============================================================================

-- 1) Vai trò mới ---------------------------------------------------------------
alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check (
  role in (
    'admin','truong_ca','ipqc','qc_manager','kho_nvl','ke_hoach',
    'qlsx_nhan_vien','qlsx_truong_phong','quan_ly_bo_phan','giam_doc_sx',
    'nhan_vien_duc','nhan_vien_bavia','nhan_vien_gia_cong','nhan_vien_danh_bong',
    'nhan_vien_oqc','nhan_vien_son','iatf_admin','nhan_vien_bao_duong_khuon',
    'nhan_vien_thong_ke'
  )
);

-- 2) Bảng ---------------------------------------------------------------------
create table if not exists khuon_lk_danh_muc (
  id                bigserial primary key,
  ma_lk             text not null unique,
  ten_lk            text not null,
  loai              text not null check (loai in (
                      'insert','pin_tao_lo','loi_truot','ejector_pin','return_pin',
                      'co_khuon','plunger_tip','sleeve','lo_xo','dau_noi_nuoc','khac')),
  pham_vi           text not null default 'rieng' check (pham_vi in ('rieng','chung')),
  quy_cach          text not null default '',
  vat_lieu          text not null default '',
  ban_ve            text not null default '',   -- số bản vẽ / mã catalog
  nha_cung_cap      text not null default '',
  lead_time_ngay    integer check (lead_time_ngay is null or lead_time_ngay >= 0),
  tuoi_tho_shot     integer check (tuoi_tho_shot is null or tuoi_tho_shot > 0),
  sua_duoc          boolean not null default false,
  don_vi            text not null default 'cái',
  vi_tri_kho        text not null default '',
  ton_toi_thieu     numeric not null default 0 check (ton_toi_thieu >= 0),
  ghi_chu           text not null default '',
  dang_dung         boolean not null default true,
  ton_cho_su_dung   numeric not null default 0 check (ton_cho_su_dung >= 0),
  ton_cho_sua       numeric not null default 0 check (ton_cho_sua >= 0),
  created_at        timestamptz not null default now(),
  created_by        text not null default '',
  updated_at        timestamptz not null default now(),
  updated_by        text not null default ''
);

create table if not exists khuon_lk_gan (
  id                  bigserial primary key,
  ma_khuon            text not null,
  id_lk               bigint not null references khuon_lk_danh_muc(id),
  so_luong_lap        numeric not null default 1 check (so_luong_lap > 0),
  vi_tri_lap          text not null default '',
  du_phong_toi_thieu  numeric not null default 0 check (du_phong_toi_thieu >= 0),
  ghi_chu             text not null default '',
  updated_at          timestamptz not null default now(),
  updated_by          text not null default '',
  unique (ma_khuon, id_lk)
);
create index if not exists khuon_lk_gan_id_lk_idx on khuon_lk_gan(id_lk);

create table if not exists khuon_lk_giao_dich (
  id                  bigserial primary key,
  thoi_diem           timestamptz not null default now(),
  loai                text not null check (loai in ('nhap','xuat_thay','thao_ra','sua_xong','bao_phe','kiem_ke')),
  id_lk               bigint not null references khuon_lk_danh_muc(id),
  ma_lk               text not null,          -- chụp lại lúc ghi
  ten_lk              text not null,
  so_luong            numeric not null default 0,
  delta_cho_su_dung   numeric not null default 0,
  delta_cho_sua       numeric not null default 0,
  ton_sau_cho_su_dung numeric not null,
  ton_sau_cho_sua     numeric not null,
  ma_khuon            text,
  vi_tri              text not null default '',
  shot_khuon          numeric,                 -- tổng shot khuôn lúc ghi (server tự lấy)
  muc_dich            text not null default '',
  ket_qua_thao        text check (ket_qua_thao is null or ket_qua_thao in ('cho_su_dung','cho_sua','phe')),
  id_checksheet       bigint,                  -- GĐ2
  id_van_de           bigint,                  -- GĐ2
  nguoi               text not null,
  nguoi_uid           uuid,
  vai_tro             text not null default '',
  ghi_chu             text not null default ''
);
create index if not exists khuon_lk_gd_lk_idx on khuon_lk_giao_dich(id_lk, thoi_diem desc);
create index if not exists khuon_lk_gd_khuon_idx on khuon_lk_giao_dich(ma_khuon, thoi_diem desc);
create index if not exists khuon_lk_gd_tg_idx on khuon_lk_giao_dich(thoi_diem desc);

-- Chỉ người đăng nhập đọc; không ai ghi thẳng.
do $$
declare t text;
begin
  foreach t in array array['khuon_lk_danh_muc','khuon_lk_gan','khuon_lk_giao_dich'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "auth read" on %I', t);
    execute format('create policy "auth read" on %I for select to authenticated using (true)', t);
    execute format('revoke all on %I from anon, authenticated', t);
    execute format('grant select on %I to authenticated', t);
  end loop;
end $$;

-- 3) Hàm trợ giúp -------------------------------------------------------------
-- Người đang gọi + quyền. Trả lỗi (text) hoặc null.
create or replace function khuon_lk_nguoi(p_quyen text, out o_loi text, out o_ten text, out o_role text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text; v_ten text;
begin
  select role, coalesce(nullif(trim(full_name), ''), nullif(trim(username), ''), email, '')
    into v_role, v_ten from public.user_roles where user_id = auth.uid();
  o_role := coalesce(v_role, ''); o_ten := coalesce(v_ten, '');
  if v_role is null then o_loi := 'Cần đăng nhập'; return; end if;
  -- 'quan_ly': danh mục, gán khuôn, nhập / sửa xong / báo phế / kiểm kê.
  -- 'thay': xuất thay vào khuôn / tháo ra (thêm NV bảo dưỡng khuôn).
  if p_quyen = 'quan_ly' and v_role not in ('nhan_vien_thong_ke', 'admin') then
    o_loi := 'Chỉ nhân viên thống kê / admin được thao tác'; return;
  end if;
  if p_quyen = 'thay' and v_role not in ('nhan_vien_thong_ke', 'nhan_vien_bao_duong_khuon', 'admin') then
    o_loi := 'Chỉ nhân viên bảo dưỡng khuôn / thống kê / admin được ghi thay linh kiện'; return;
  end if;
end $$;
revoke execute on function khuon_lk_nguoi(text) from public, anon, authenticated;

-- 4) Danh mục -----------------------------------------------------------------
-- p_data: {id?, ma_lk, ten_lk, loai, pham_vi, quy_cach, vat_lieu, ban_ve,
--          nha_cung_cap, lead_time_ngay, tuoi_tho_shot, sua_duoc, don_vi,
--          vi_tri_kho, ton_toi_thieu, ghi_chu, dang_dung}
create or replace function khuon_lk_luu(p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me record; v_id bigint := nullif(p_data->>'id', '')::bigint;
  v_ma text := trim(coalesce(p_data->>'ma_lk', ''));
  v_ten text := trim(coalesce(p_data->>'ten_lk', ''));
begin
  select * into v_me from khuon_lk_nguoi('quan_ly');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if v_ma = '' or v_ten = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã / tên linh kiện'); end if;
  if exists (select 1 from khuon_lk_danh_muc where lower(ma_lk) = lower(v_ma) and id is distinct from v_id) then
    return jsonb_build_object('ok', false, 'error', 'Mã linh kiện đã tồn tại: ' || v_ma);
  end if;
  if v_id is null then
    insert into khuon_lk_danh_muc (ma_lk, ten_lk, loai, pham_vi, quy_cach, vat_lieu, ban_ve, nha_cung_cap,
      lead_time_ngay, tuoi_tho_shot, sua_duoc, don_vi, vi_tri_kho, ton_toi_thieu, ghi_chu, dang_dung, created_by, updated_by)
    values (v_ma, v_ten, coalesce(nullif(p_data->>'loai', ''), 'khac'), coalesce(nullif(p_data->>'pham_vi', ''), 'rieng'),
      trim(coalesce(p_data->>'quy_cach', '')), trim(coalesce(p_data->>'vat_lieu', '')), trim(coalesce(p_data->>'ban_ve', '')),
      trim(coalesce(p_data->>'nha_cung_cap', '')), nullif(p_data->>'lead_time_ngay', '')::int, nullif(p_data->>'tuoi_tho_shot', '')::int,
      coalesce((p_data->>'sua_duoc')::boolean, false), coalesce(nullif(trim(p_data->>'don_vi'), ''), 'cái'),
      trim(coalesce(p_data->>'vi_tri_kho', '')), coalesce(nullif(p_data->>'ton_toi_thieu', '')::numeric, 0),
      trim(coalesce(p_data->>'ghi_chu', '')), coalesce((p_data->>'dang_dung')::boolean, true), v_me.o_ten, v_me.o_ten)
    returning id into v_id;
  else
    update khuon_lk_danh_muc set
      ma_lk = v_ma, ten_lk = v_ten, loai = coalesce(nullif(p_data->>'loai', ''), loai),
      pham_vi = coalesce(nullif(p_data->>'pham_vi', ''), pham_vi),
      quy_cach = trim(coalesce(p_data->>'quy_cach', '')), vat_lieu = trim(coalesce(p_data->>'vat_lieu', '')),
      ban_ve = trim(coalesce(p_data->>'ban_ve', '')), nha_cung_cap = trim(coalesce(p_data->>'nha_cung_cap', '')),
      lead_time_ngay = nullif(p_data->>'lead_time_ngay', '')::int, tuoi_tho_shot = nullif(p_data->>'tuoi_tho_shot', '')::int,
      sua_duoc = coalesce((p_data->>'sua_duoc')::boolean, sua_duoc), don_vi = coalesce(nullif(trim(p_data->>'don_vi'), ''), don_vi),
      vi_tri_kho = trim(coalesce(p_data->>'vi_tri_kho', '')), ton_toi_thieu = coalesce(nullif(p_data->>'ton_toi_thieu', '')::numeric, 0),
      ghi_chu = trim(coalesce(p_data->>'ghi_chu', '')), dang_dung = coalesce((p_data->>'dang_dung')::boolean, dang_dung),
      updated_at = now(), updated_by = v_me.o_ten
    where id = v_id;
    if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy linh kiện'); end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
exception when check_violation or invalid_text_representation then
  return jsonb_build_object('ok', false, 'error', 'Dữ liệu không hợp lệ: ' || sqlerrm);
end $$;

-- Xoá hẳn chỉ khi chưa có giao dịch nào; còn lịch sử thì chuyển "ngừng dùng".
create or replace function khuon_lk_xoa(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_me record;
begin
  select * into v_me from khuon_lk_nguoi('quan_ly');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if exists (select 1 from khuon_lk_giao_dich where id_lk = p_id) then
    return jsonb_build_object('ok', false, 'error', 'Linh kiện đã có giao dịch — không xoá được, hãy bỏ tick "Đang dùng"');
  end if;
  delete from khuon_lk_gan where id_lk = p_id;
  delete from khuon_lk_danh_muc where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- 5) Gán khuôn ----------------------------------------------------------------
create or replace function khuon_lk_gan_luu(p_ma_khuon text, p_id_lk bigint, p_so_luong_lap numeric,
  p_vi_tri_lap text, p_du_phong_toi_thieu numeric, p_ghi_chu text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_me record; v_mk text := trim(coalesce(p_ma_khuon, ''));
begin
  select * into v_me from khuon_lk_nguoi('quan_ly');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if not exists (select 1 from duc_shot_khuon where ma_khuon = v_mk) then
    return jsonb_build_object('ok', false, 'error', 'Không có khuôn ' || v_mk || ' trong danh sách khuôn');
  end if;
  if not exists (select 1 from khuon_lk_danh_muc where id = p_id_lk) then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy linh kiện');
  end if;
  if coalesce(p_so_luong_lap, 0) <= 0 then return jsonb_build_object('ok', false, 'error', 'Số lượng lắp phải > 0'); end if;
  insert into khuon_lk_gan (ma_khuon, id_lk, so_luong_lap, vi_tri_lap, du_phong_toi_thieu, ghi_chu, updated_by)
  values (v_mk, p_id_lk, p_so_luong_lap, trim(coalesce(p_vi_tri_lap, '')), greatest(coalesce(p_du_phong_toi_thieu, 0), 0),
    trim(coalesce(p_ghi_chu, '')), v_me.o_ten)
  on conflict (ma_khuon, id_lk) do update set
    so_luong_lap = excluded.so_luong_lap, vi_tri_lap = excluded.vi_tri_lap,
    du_phong_toi_thieu = excluded.du_phong_toi_thieu, ghi_chu = excluded.ghi_chu,
    updated_at = now(), updated_by = excluded.updated_by;
  return jsonb_build_object('ok', true);
end $$;

create or replace function khuon_lk_gan_xoa(p_ma_khuon text, p_id_lk bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_me record;
begin
  select * into v_me from khuon_lk_nguoi('quan_ly');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  delete from khuon_lk_gan where ma_khuon = trim(p_ma_khuon) and id_lk = p_id_lk;
  return jsonb_build_object('ok', true);
end $$;

-- Sao chép danh sách linh kiện của khuôn nguồn sang khuôn đích (khuôn giống
-- nhau, VD #1 → #2). Linh kiện khuôn đích đã có thì giữ nguyên.
create or replace function khuon_lk_gan_sao_chep(p_tu_khuon text, p_den_khuon text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_me record; v_n int;
begin
  select * into v_me from khuon_lk_nguoi('quan_ly');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if trim(coalesce(p_tu_khuon, '')) = trim(coalesce(p_den_khuon, '')) then
    return jsonb_build_object('ok', false, 'error', 'Khuôn nguồn trùng khuôn đích');
  end if;
  if not exists (select 1 from duc_shot_khuon where ma_khuon = trim(p_den_khuon)) then
    return jsonb_build_object('ok', false, 'error', 'Không có khuôn ' || p_den_khuon);
  end if;
  insert into khuon_lk_gan (ma_khuon, id_lk, so_luong_lap, vi_tri_lap, du_phong_toi_thieu, ghi_chu, updated_by)
  select trim(p_den_khuon), id_lk, so_luong_lap, vi_tri_lap, du_phong_toi_thieu, ghi_chu, v_me.o_ten
  from khuon_lk_gan where ma_khuon = trim(p_tu_khuon)
  on conflict (ma_khuon, id_lk) do nothing;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'so_dong', v_n);
end $$;

-- 6) Giao dịch kho ------------------------------------------------------------
-- p_loai:
--   nhap      : + chờ sử dụng (mục đích: mua mới / chế tạo / tồn đầu kỳ / khác)
--   xuat_thay : − chờ sử dụng, bắt buộc khuôn + mục đích (lý do thay)
--   thao_ra   : linh kiện tháo khỏi khuôn → p_ket_qua_thao: cho_su_dung (+) /
--               cho_sua (+) / phe (không đổi tồn, chỉ ghi lại)
--   sua_xong  : − chờ sửa, + chờ sử dụng
--   bao_phe   : − p_tu_trang_thai (cho_su_dung | cho_sua)
--   kiem_ke   : đặt tồn = số thực tế (p_ton_cho_su_dung, p_ton_cho_sua), bắt buộc lý do
create or replace function khuon_lk_ghi_giao_dich(
  p_loai text, p_id_lk bigint, p_so_luong numeric,
  p_ma_khuon text default null, p_vi_tri text default null, p_muc_dich text default null,
  p_ket_qua_thao text default null, p_tu_trang_thai text default null,
  p_ton_cho_su_dung numeric default null, p_ton_cho_sua numeric default null,
  p_ghi_chu text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me record; v_lk khuon_lk_danh_muc%rowtype;
  v_sl numeric := coalesce(p_so_luong, 0);
  v_mk text := nullif(trim(coalesce(p_ma_khuon, '')), '');
  v_md text := trim(coalesce(p_muc_dich, ''));
  v_d1 numeric := 0; v_d2 numeric := 0; v_shot numeric; v_id bigint;
begin
  if p_loai not in ('nhap','xuat_thay','thao_ra','sua_xong','bao_phe','kiem_ke') then
    return jsonb_build_object('ok', false, 'error', 'Loại phiếu không hợp lệ');
  end if;
  select * into v_me from khuon_lk_nguoi(case when p_loai in ('xuat_thay','thao_ra') then 'thay' else 'quan_ly' end);
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;

  -- Khoá dòng tồn: 2 phiếu cùng lúc không làm lệch số.
  select * into v_lk from khuon_lk_danh_muc where id = p_id_lk for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy linh kiện'); end if;

  if p_loai <> 'kiem_ke' and v_sl <= 0 then return jsonb_build_object('ok', false, 'error', 'Số lượng phải > 0'); end if;
  if p_loai in ('xuat_thay','thao_ra') then
    if v_mk is null then return jsonb_build_object('ok', false, 'error', 'Chọn khuôn'); end if;
    select tong_shot_luy_ke into v_shot from duc_shot_khuon where ma_khuon = v_mk;
    if not found then return jsonb_build_object('ok', false, 'error', 'Không có khuôn ' || v_mk); end if;
  end if;
  if p_loai in ('xuat_thay','kiem_ke','bao_phe') and v_md = '' then
    return jsonb_build_object('ok', false, 'error', case p_loai when 'xuat_thay' then 'Nhập mục đích / lý do thay'
      when 'kiem_ke' then 'Nhập lý do điều chỉnh kiểm kê' else 'Nhập lý do báo phế' end);
  end if;

  if p_loai = 'nhap' then v_d1 := v_sl;
  elsif p_loai = 'xuat_thay' then v_d1 := -v_sl;
  elsif p_loai = 'thao_ra' then
    if p_ket_qua_thao = 'cho_su_dung' then v_d1 := v_sl;
    elsif p_ket_qua_thao = 'cho_sua' then v_d2 := v_sl;
    elsif p_ket_qua_thao = 'phe' then null;
    else return jsonb_build_object('ok', false, 'error', 'Chọn tình trạng linh kiện tháo ra');
    end if;
  elsif p_loai = 'sua_xong' then v_d2 := -v_sl; v_d1 := v_sl;
  elsif p_loai = 'bao_phe' then
    if p_tu_trang_thai = 'cho_su_dung' then v_d1 := -v_sl;
    elsif p_tu_trang_thai = 'cho_sua' then v_d2 := -v_sl;
    else return jsonb_build_object('ok', false, 'error', 'Chọn báo phế từ Chờ sử dụng hay Chờ sửa');
    end if;
  elsif p_loai = 'kiem_ke' then
    if p_ton_cho_su_dung is null or p_ton_cho_sua is null or p_ton_cho_su_dung < 0 or p_ton_cho_sua < 0 then
      return jsonb_build_object('ok', false, 'error', 'Nhập số thực tế Chờ sử dụng và Chờ sửa (≥ 0)');
    end if;
    v_d1 := p_ton_cho_su_dung - v_lk.ton_cho_su_dung; v_d2 := p_ton_cho_sua - v_lk.ton_cho_sua;
    v_sl := abs(v_d1) + abs(v_d2);
  end if;

  if v_lk.ton_cho_su_dung + v_d1 < 0 then
    return jsonb_build_object('ok', false, 'error', 'Không đủ tồn Chờ sử dụng (còn ' || v_lk.ton_cho_su_dung || ' ' || v_lk.don_vi || ')');
  end if;
  if v_lk.ton_cho_sua + v_d2 < 0 then
    return jsonb_build_object('ok', false, 'error', 'Không đủ tồn Chờ sửa (còn ' || v_lk.ton_cho_sua || ' ' || v_lk.don_vi || ')');
  end if;

  update khuon_lk_danh_muc set ton_cho_su_dung = ton_cho_su_dung + v_d1, ton_cho_sua = ton_cho_sua + v_d2
  where id = p_id_lk;

  insert into khuon_lk_giao_dich (loai, id_lk, ma_lk, ten_lk, so_luong, delta_cho_su_dung, delta_cho_sua,
    ton_sau_cho_su_dung, ton_sau_cho_sua, ma_khuon, vi_tri, shot_khuon, muc_dich, ket_qua_thao,
    nguoi, nguoi_uid, vai_tro, ghi_chu)
  values (p_loai, p_id_lk, v_lk.ma_lk, v_lk.ten_lk, v_sl, v_d1, v_d2,
    v_lk.ton_cho_su_dung + v_d1, v_lk.ton_cho_sua + v_d2, v_mk, trim(coalesce(p_vi_tri, '')), v_shot, v_md,
    case when p_loai = 'thao_ra' then p_ket_qua_thao end,
    v_me.o_ten, auth.uid(), v_me.o_role, trim(coalesce(p_ghi_chu, '')))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id,
    'ton_cho_su_dung', v_lk.ton_cho_su_dung + v_d1, 'ton_cho_sua', v_lk.ton_cho_sua + v_d2);
end $$;

-- 7) Nhập từ Excel ------------------------------------------------------------
-- p_danh_muc: [{ma_lk, ten_lk, loai, pham_vi, ..., ton_dau_ky}] — upsert theo
--   ma_lk; ton_dau_ky chỉ áp dụng cho linh kiện CHƯA có giao dịch nào (ghi 1
--   phiếu nhập "Tồn đầu kỳ").
-- p_gan: [{ma_khuon, ma_lk, so_luong_lap, vi_tri_lap, du_phong_toi_thieu}]
-- Lỗi từng dòng trả về trong 'loi' (không dừng cả lô).
create or replace function khuon_lk_nhap_excel(p_danh_muc jsonb, p_gan jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me record; r jsonb; v_res jsonb; v_id bigint; v_loi jsonb := '[]'::jsonb;
  v_n_lk int := 0; v_n_gan int := 0; v_n_ton int := 0; v_i int := 0; v_ton numeric;
begin
  select * into v_me from khuon_lk_nguoi('quan_ly');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;

  for r in select * from jsonb_array_elements(coalesce(p_danh_muc, '[]'::jsonb)) loop
    v_i := v_i + 1;
    select id into v_id from khuon_lk_danh_muc where lower(ma_lk) = lower(trim(coalesce(r->>'ma_lk', '')));
    begin
      v_res := khuon_lk_luu(r || jsonb_build_object('id', v_id));
    exception when others then
      v_res := jsonb_build_object('ok', false, 'error', sqlerrm);
    end;
    if not coalesce((v_res->>'ok')::boolean, false) then
      v_loi := v_loi || jsonb_build_object('sheet', 'Danh mục', 'dong', v_i + 1, 'loi', v_res->>'error');
      continue;
    end if;
    v_n_lk := v_n_lk + 1;
    v_ton := nullif(r->>'ton_dau_ky', '')::numeric;
    if coalesce(v_ton, 0) > 0 and not exists (select 1 from khuon_lk_giao_dich where id_lk = (v_res->>'id')::bigint) then
      perform khuon_lk_ghi_giao_dich('nhap', (v_res->>'id')::bigint, v_ton, null, null, 'Tồn đầu kỳ (nhập Excel)');
      v_n_ton := v_n_ton + 1;
    end if;
  end loop;

  v_i := 0;
  for r in select * from jsonb_array_elements(coalesce(p_gan, '[]'::jsonb)) loop
    v_i := v_i + 1;
    select id into v_id from khuon_lk_danh_muc where lower(ma_lk) = lower(trim(coalesce(r->>'ma_lk', '')));
    if v_id is null then
      v_loi := v_loi || jsonb_build_object('sheet', 'Gán khuôn', 'dong', v_i + 1, 'loi', 'Không có mã linh kiện ' || coalesce(r->>'ma_lk', ''));
      continue;
    end if;
    begin
      v_res := khuon_lk_gan_luu(r->>'ma_khuon', v_id, coalesce(nullif(r->>'so_luong_lap', '')::numeric, 1),
        r->>'vi_tri_lap', nullif(r->>'du_phong_toi_thieu', '')::numeric, r->>'ghi_chu');
    exception when others then
      v_res := jsonb_build_object('ok', false, 'error', sqlerrm);
    end;
    if coalesce((v_res->>'ok')::boolean, false) then v_n_gan := v_n_gan + 1;
    else v_loi := v_loi || jsonb_build_object('sheet', 'Gán khuôn', 'dong', v_i + 1, 'loi', v_res->>'error');
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'so_lk', v_n_lk, 'so_gan', v_n_gan, 'so_ton_dau_ky', v_n_ton, 'loi', v_loi);
end $$;

-- Quyền gọi: chỉ người đăng nhập (vai trò kiểm trong hàm).
do $$
declare f text;
begin
  foreach f in array array[
    'khuon_lk_luu(jsonb)', 'khuon_lk_xoa(bigint)',
    'khuon_lk_gan_luu(text,bigint,numeric,text,numeric,text)', 'khuon_lk_gan_xoa(text,bigint)',
    'khuon_lk_gan_sao_chep(text,text)',
    'khuon_lk_ghi_giao_dich(text,bigint,numeric,text,text,text,text,text,numeric,numeric,text)',
    'khuon_lk_nhap_excel(jsonb,jsonb)'] loop
    execute 'revoke execute on function ' || f || ' from public, anon';
    execute 'grant execute on function ' || f || ' to authenticated';
  end loop;
end $$;

-- 8) Đổi mã khuôn chuyển luôn danh sách linh kiện của khuôn -------------------
do $$
declare v_def text; v_moc text := E'  update duc_khuon_cs_mau_bo set ma_khuon = v_moi where ma_khuon = v_cu;\n';
begin
  v_def := pg_get_functiondef('duc_rename_khuon'::regproc);
  if position('khuon_lk_gan' in v_def) = 0 then
    if position(v_moc in v_def) = 0 then raise exception 'T94: không tìm thấy chỗ chèn trong duc_rename_khuon'; end if;
    execute replace(v_def, v_moc, v_moc || E'  update khuon_lk_gan set ma_khuon = v_moi where ma_khuon = v_cu;  -- T94\n');
  end if;
end $$;
