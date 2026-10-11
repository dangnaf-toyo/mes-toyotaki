-- ============================================================================
-- T75 — Phê duyệt Kế hoạch bảo dưỡng khuôn tuần (bao-duong-khuon-tuan.html).
--
-- Lộ trình theo TUẦN:
--   nhap           (Người lập = nhân viên bảo dưỡng khuôn, sửa thoải mái)
--   -> cho_kiem_tra   (Người kiểm tra = Quản lý bộ phận Đúc)
--   -> cho_phe_duyet  (Người phê duyệt = Giám đốc sản xuất)
--   -> da_duyet
-- Từ chối ở bước nào cũng bắt buộc lý do -> quay về 'nhap'.
-- Sửa/thêm/xoá lịch khi kế hoạch đã gửi (chờ kiểm tra/chờ duyệt/đã duyệt)
-- -> bắt buộc lý do, kế hoạch tự quay về 'cho_kiem_tra' (kiểm tra + duyệt
-- lại), giống KHSX tuần (T11).
-- Duyệt/từ chối KHÔNG cho admin làm hộ (giống T16).
--
-- Vai trò MỚI user_roles.role = 'nhan_vien_bao_duong_khuon' (người lập).
-- Ghi lịch (duc_khuon_bd_kh_tuan, T74) nay CHỈ qua RPC — bỏ quyền ghi trực
-- tiếp, để trạng thái duyệt + lịch sử luôn khớp với thay đổi thật.
-- Tên người ký lấy ở server từ user_roles (full_name/username), không tin
-- tên client gửi lên.
--
-- Chạy trên CẢ 2 project (production + staging). Idempotent. Chạy sau T74.
-- ============================================================================

-- 1) Vai trò mới ---------------------------------------------------------------
alter table public.user_roles drop constraint if exists user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check (
  role in (
    'admin','truong_ca','ipqc','qc_manager','kho_nvl','ke_hoach',
    'qlsx_nhan_vien','qlsx_truong_phong','quan_ly_bo_phan','giam_doc_sx',
    'nhan_vien_duc','nhan_vien_bavia','nhan_vien_gia_cong','nhan_vien_danh_bong',
    'nhan_vien_oqc','nhan_vien_son','iatf_admin','nhan_vien_bao_duong_khuon'
  )
);

-- 2) Trạng thái duyệt theo tuần + chữ ký từng bước -----------------------------
create table if not exists duc_khuon_bd_duyet (
  tuan_bat_dau        date primary key,
  trang_thai          text not null default 'nhap'
    check (trang_thai in ('nhap','cho_kiem_tra','cho_phe_duyet','da_duyet')),
  nguoi_lap           text not null default '',
  thoi_diem_lap       timestamptz,
  nguoi_kiem_tra      text not null default '',
  thoi_diem_kiem_tra  timestamptz,
  nguoi_phe_duyet     text not null default '',
  thoi_diem_phe_duyet timestamptz,
  nguoi_tu_choi       text not null default '',
  thoi_diem_tu_choi   timestamptz,
  ly_do_tu_choi       text not null default '',
  updated_at          timestamptz not null default now()
);
alter table duc_khuon_bd_duyet enable row level security;
drop policy if exists "bd_duyet public read" on duc_khuon_bd_duyet;
create policy "bd_duyet public read" on duc_khuon_bd_duyet for select using (true);
grant select on duc_khuon_bd_duyet to anon, authenticated;

-- 3) Lịch sử thay đổi + duyệt -------------------------------------------------
create table if not exists duc_khuon_bd_duyet_log (
  id            bigserial primary key,
  tuan_bat_dau  date not null,
  su_kien       text not null
    check (su_kien in ('them','sua','xoa','gui_duyet','kiem_tra','phe_duyet','tu_choi')),
  noi_dung      text not null default '',
  ly_do         text not null default '',
  nguoi         text not null default '',
  thoi_diem     timestamptz not null default now()
);
create index if not exists idx_bd_duyet_log_tuan on duc_khuon_bd_duyet_log (tuan_bat_dau, thoi_diem desc);
alter table duc_khuon_bd_duyet_log enable row level security;
drop policy if exists "bd_duyet_log public read" on duc_khuon_bd_duyet_log;
create policy "bd_duyet_log public read" on duc_khuon_bd_duyet_log for select using (true);
grant select on duc_khuon_bd_duyet_log to anon, authenticated;

-- 4) Khoá ghi trực tiếp vào lịch (T74) — chỉ qua RPC bên dưới ------------------
drop policy if exists "bd_kh_tuan role insert" on duc_khuon_bd_kh_tuan;
drop policy if exists "bd_kh_tuan role update" on duc_khuon_bd_kh_tuan;
drop policy if exists "bd_kh_tuan role delete" on duc_khuon_bd_kh_tuan;
revoke insert, update, delete on duc_khuon_bd_kh_tuan from anon, authenticated;

-- 5) Helper nội bộ ---------------------------------------------------------------
create or replace function duc_khuon_bd_nguoi_hien_tai(out o_role text, out o_bo_phan text[], out o_ten text)
language sql
stable
security definer
set search_path = public
as $$
  select role, bo_phan_phu_trach, coalesce(nullif(trim(full_name), ''), nullif(trim(username), ''), email, '')
  from public.user_roles where user_id = auth.uid();
$$;
revoke execute on function duc_khuon_bd_nguoi_hien_tai() from public, anon, authenticated;

create or replace function duc_khuon_bd_mo_ta(p_ma_khuon text, p_ngay date, p_loai text, p_nguoi text, p_ghi_chu text)
returns text
language sql
immutable
as $$
  select p_ma_khuon || ' · ' || to_char(p_ngay, 'DD/MM') || ' · ' || p_loai || ' · '
      || coalesce(nullif(p_nguoi, ''), '(chưa giao)')
      || case when coalesce(p_ghi_chu, '') <> '' then ' · ' || p_ghi_chu else '' end;
$$;
revoke execute on function duc_khuon_bd_mo_ta(text, date, text, text, text) from public, anon, authenticated;

-- Gọi trước mỗi thay đổi lịch: kiểm tra quyền người lập; nếu kế hoạch đã gửi
-- thì bắt buộc lý do và đưa về 'cho_kiem_tra'. Trả về lỗi (text) hoặc null.
create or replace function duc_khuon_bd_truoc_khi_sua(p_tuan date, p_ly_do text, out o_loi text, out o_ten text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me record; v_tt text;
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  o_ten := coalesce(v_me.o_ten, '');
  if coalesce(v_me.o_role, '') not in ('nhan_vien_bao_duong_khuon', 'admin') then
    o_loi := 'Chỉ nhân viên bảo dưỡng khuôn (người lập) được sửa kế hoạch bảo dưỡng'; return;
  end if;
  select trang_thai into v_tt from duc_khuon_bd_duyet where tuan_bat_dau = p_tuan for update;
  if coalesce(v_tt, 'nhap') <> 'nhap' then
    if coalesce(trim(p_ly_do), '') = '' then
      o_loi := 'Kế hoạch đã gửi duyệt — bắt buộc nhập lý do sửa (kế hoạch sẽ phải kiểm tra & duyệt lại)'; return;
    end if;
    update duc_khuon_bd_duyet set trang_thai = 'cho_kiem_tra',
      nguoi_kiem_tra = '', thoi_diem_kiem_tra = null, nguoi_phe_duyet = '', thoi_diem_phe_duyet = null,
      updated_at = now()
    where tuan_bat_dau = p_tuan;
  end if;
end;
$$;
revoke execute on function duc_khuon_bd_truoc_khi_sua(date, text) from public, anon, authenticated;

-- 6) RPC: Thêm/sửa 1 lịch ---------------------------------------------------------
create or replace function duc_khuon_bd_kh_luu(
  p_id bigint, p_tuan date, p_ngay date, p_ma_khuon text, p_loai text,
  p_nguoi_phu_trach text, p_ghi_chu text, p_ly_do text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_chk record; v_old duc_khuon_bd_kh_tuan; v_id bigint; v_mo_ta text;
begin
  if p_ma_khuon is null or trim(p_ma_khuon) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu mã khuôn');
  end if;
  if p_id is not null then
    select * into v_old from duc_khuon_bd_kh_tuan where id = p_id;
    if not found then return jsonb_build_object('ok', false, 'error', 'Lịch không còn tồn tại — tải lại trang'); end if;
    if v_old.tuan_bat_dau <> p_tuan then return jsonb_build_object('ok', false, 'error', 'Không chuyển lịch sang tuần khác'); end if;
  elsif not exists (select 1 from duc_shot_khuon where ma_khuon = trim(p_ma_khuon)) then
    return jsonb_build_object('ok', false, 'error', 'Khuôn ' || p_ma_khuon || ' không có trong danh mục khuôn');
  end if;

  select * into v_chk from duc_khuon_bd_truoc_khi_sua(p_tuan, p_ly_do);
  if v_chk.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_chk.o_loi); end if;

  v_mo_ta := duc_khuon_bd_mo_ta(trim(p_ma_khuon), p_ngay, p_loai, coalesce(p_nguoi_phu_trach, ''), coalesce(trim(p_ghi_chu), ''));
  begin
    if p_id is null then
      insert into duc_khuon_bd_kh_tuan (tuan_bat_dau, ngay, ma_khuon, loai, nguoi_phu_trach, ghi_chu, updated_by, updated_at)
      values (p_tuan, p_ngay, trim(p_ma_khuon), p_loai, coalesce(p_nguoi_phu_trach, ''), coalesce(trim(p_ghi_chu), ''), v_chk.o_ten, now())
      returning id into v_id;
    else
      update duc_khuon_bd_kh_tuan set ngay = p_ngay, ma_khuon = trim(p_ma_khuon), loai = p_loai,
        nguoi_phu_trach = coalesce(p_nguoi_phu_trach, ''), ghi_chu = coalesce(trim(p_ghi_chu), ''),
        updated_by = v_chk.o_ten, updated_at = now()
      where id = p_id;
      v_id := p_id;
    end if;
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'error', 'Khuôn ' || p_ma_khuon || ' đã có lịch vào ngày này — sửa ô đó thay vì thêm mới');
    when check_violation then
      return jsonb_build_object('ok', false, 'error', 'Dữ liệu không hợp lệ (ngày phải trong tuần, loại công việc đúng danh sách)');
  end;

  insert into duc_khuon_bd_duyet_log (tuan_bat_dau, su_kien, noi_dung, ly_do, nguoi)
  values (p_tuan, case when p_id is null then 'them' else 'sua' end,
    case when p_id is null then v_mo_ta
         else duc_khuon_bd_mo_ta(v_old.ma_khuon, v_old.ngay, v_old.loai, v_old.nguoi_phu_trach, v_old.ghi_chu) || '  →  ' || v_mo_ta end,
    coalesce(trim(p_ly_do), ''), v_chk.o_ten);

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;
revoke execute on function duc_khuon_bd_kh_luu(bigint, date, date, text, text, text, text, text) from public, anon;
grant execute on function duc_khuon_bd_kh_luu(bigint, date, date, text, text, text, text, text) to authenticated;

-- 7) RPC: Xoá 1 lịch ----------------------------------------------------------------
create or replace function duc_khuon_bd_kh_xoa(p_id bigint, p_ly_do text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old duc_khuon_bd_kh_tuan; v_chk record;
begin
  select * into v_old from duc_khuon_bd_kh_tuan where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'Lịch không còn tồn tại — tải lại trang'); end if;
  select * into v_chk from duc_khuon_bd_truoc_khi_sua(v_old.tuan_bat_dau, p_ly_do);
  if v_chk.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_chk.o_loi); end if;
  delete from duc_khuon_bd_kh_tuan where id = p_id;
  insert into duc_khuon_bd_duyet_log (tuan_bat_dau, su_kien, noi_dung, ly_do, nguoi)
  values (v_old.tuan_bat_dau, 'xoa',
    duc_khuon_bd_mo_ta(v_old.ma_khuon, v_old.ngay, v_old.loai, v_old.nguoi_phu_trach, v_old.ghi_chu),
    coalesce(trim(p_ly_do), ''), v_chk.o_ten);
  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function duc_khuon_bd_kh_xoa(bigint, text) from public, anon;
grant execute on function duc_khuon_bd_kh_xoa(bigint, text) to authenticated;

-- 8) RPC: Gửi duyệt (người lập) -----------------------------------------------------
create or replace function duc_khuon_bd_gui_duyet(p_tuan date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me record; v_tt text;
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  if coalesce(v_me.o_role, '') not in ('nhan_vien_bao_duong_khuon', 'admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ nhân viên bảo dưỡng khuôn (người lập) được gửi duyệt');
  end if;
  if not exists (select 1 from duc_khuon_bd_kh_tuan where tuan_bat_dau = p_tuan) then
    return jsonb_build_object('ok', false, 'error', 'Tuần này chưa có lịch bảo dưỡng nào để gửi duyệt');
  end if;
  insert into duc_khuon_bd_duyet (tuan_bat_dau) values (p_tuan) on conflict do nothing;
  select trang_thai into v_tt from duc_khuon_bd_duyet where tuan_bat_dau = p_tuan for update;
  if v_tt <> 'nhap' then
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch đã gửi duyệt rồi');
  end if;
  update duc_khuon_bd_duyet set trang_thai = 'cho_kiem_tra',
    nguoi_lap = v_me.o_ten, thoi_diem_lap = now(),
    nguoi_kiem_tra = '', thoi_diem_kiem_tra = null, nguoi_phe_duyet = '', thoi_diem_phe_duyet = null,
    nguoi_tu_choi = '', thoi_diem_tu_choi = null, ly_do_tu_choi = '', updated_at = now()
  where tuan_bat_dau = p_tuan;
  insert into duc_khuon_bd_duyet_log (tuan_bat_dau, su_kien, nguoi) values (p_tuan, 'gui_duyet', v_me.o_ten);
  return jsonb_build_object('ok', true, 'trang_thai_moi', 'cho_kiem_tra');
end;
$$;
revoke execute on function duc_khuon_bd_gui_duyet(date) from public, anon;
grant execute on function duc_khuon_bd_gui_duyet(date) to authenticated;

-- 9) RPC: Kiểm tra / Phê duyệt / Từ chối bước hiện tại ------------------------------
-- p_dong_y = true: chuyển bước tiếp; false: từ chối (bắt buộc lý do) -> 'nhap'.
create or replace function duc_khuon_bd_xu_ly_duyet(p_tuan date, p_dong_y boolean, p_ly_do text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me record; v_tt text; v_moi text;
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  select trang_thai into v_tt from duc_khuon_bd_duyet where tuan_bat_dau = p_tuan for update;
  if v_tt is null or v_tt not in ('cho_kiem_tra', 'cho_phe_duyet') then
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch không ở trạng thái chờ kiểm tra/phê duyệt');
  end if;
  if v_tt = 'cho_kiem_tra' and not (coalesce(v_me.o_role, '') = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(v_me.o_bo_phan, '{}'))) then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Quản lý bộ phận Đúc được kiểm tra bước này');
  end if;
  if v_tt = 'cho_phe_duyet' and coalesce(v_me.o_role, '') <> 'giam_doc_sx' then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Giám đốc sản xuất được phê duyệt bước này');
  end if;

  if not p_dong_y then
    if coalesce(trim(p_ly_do), '') = '' then
      return jsonb_build_object('ok', false, 'error', 'Cần nhập lý do từ chối');
    end if;
    update duc_khuon_bd_duyet set trang_thai = 'nhap',
      nguoi_kiem_tra = '', thoi_diem_kiem_tra = null, nguoi_phe_duyet = '', thoi_diem_phe_duyet = null,
      nguoi_tu_choi = v_me.o_ten, thoi_diem_tu_choi = now(), ly_do_tu_choi = trim(p_ly_do), updated_at = now()
    where tuan_bat_dau = p_tuan;
    insert into duc_khuon_bd_duyet_log (tuan_bat_dau, su_kien, noi_dung, ly_do, nguoi)
    values (p_tuan, 'tu_choi', case when v_tt = 'cho_kiem_tra' then 'Bước kiểm tra' else 'Bước phê duyệt' end, trim(p_ly_do), v_me.o_ten);
    return jsonb_build_object('ok', true, 'trang_thai_moi', 'nhap');
  end if;

  if v_tt = 'cho_kiem_tra' then
    v_moi := 'cho_phe_duyet';
    update duc_khuon_bd_duyet set trang_thai = v_moi, nguoi_kiem_tra = v_me.o_ten, thoi_diem_kiem_tra = now(), updated_at = now()
    where tuan_bat_dau = p_tuan;
  else
    v_moi := 'da_duyet';
    update duc_khuon_bd_duyet set trang_thai = v_moi, nguoi_phe_duyet = v_me.o_ten, thoi_diem_phe_duyet = now(), updated_at = now()
    where tuan_bat_dau = p_tuan;
  end if;
  insert into duc_khuon_bd_duyet_log (tuan_bat_dau, su_kien, ly_do, nguoi)
  values (p_tuan, case when v_tt = 'cho_kiem_tra' then 'kiem_tra' else 'phe_duyet' end, coalesce(trim(p_ly_do), ''), v_me.o_ten);
  return jsonb_build_object('ok', true, 'trang_thai_moi', v_moi);
end;
$$;
revoke execute on function duc_khuon_bd_xu_ly_duyet(date, boolean, text) from public, anon;
grant execute on function duc_khuon_bd_xu_ly_duyet(date, boolean, text) to authenticated;
