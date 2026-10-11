-- ============================================================================
-- T76 — Check sheet bảo dưỡng khuôn (checksheet-bao-duong-khuon.html).
--
-- Mỗi lịch trong Kế hoạch bảo dưỡng khuôn tuần (duc_khuon_bd_kh_tuan, T74)
-- có tối đa 1 check sheet: danh sách hạng mục OK / NG / N/A + ghi chú, giờ
-- bắt đầu/kết thúc, phụ tùng thay, chi phí, kết luận Đạt / Không đạt.
--
-- Mẫu hạng mục: duc_khuon_cs_mau (Quản lý bộ phận Đúc / admin sửa trực tiếp
-- trên trang check sheet). Check sheet lưu BẢN CHỤP hạng mục lúc tạo
-- (hang_muc jsonb), sửa mẫu sau này không làm đổi check sheet cũ.
--
-- "Hoàn thành" (chỉ 1 lần, sau đó khoá):
--   - Ghi 1 dòng sổ đời khuôn duc_khuon_bao_duong_log (loại Kiểm tra thì
--     không ghi — sổ đời chỉ có BD định kỳ / Sửa chữa / Thay khuôn mới).
--   - Đạt + (BD định kỳ | Thay khuôn mới) -> reset đồng hồ đếm shot giống
--     duc_ghi_lich_su_bao_duong (D15). Không đạt -> KHÔNG reset.
-- Lịch đã có check sheet thì không xoá / không đổi khuôn được nữa.
--
-- Ghi check sheet: nhân viên bảo dưỡng khuôn / admin, qua RPC.
-- Chạy trên CẢ 2 project (production + staging). Idempotent. Chạy sau T75.
-- ============================================================================

-- 1) Mẫu hạng mục -------------------------------------------------------------
create table if not exists duc_khuon_cs_mau (
  id          bigserial primary key,
  nhom        text not null,
  noi_dung    text not null,
  tieu_chuan  text not null default '',
  thu_tu      int not null default 0,
  dang_dung   boolean not null default true,
  updated_at  timestamptz not null default now()
);

create or replace function duc_khuon_cs_sua_mau_duoc()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid()
      and (role = 'admin' or (role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(bo_phan_phu_trach, '{}'))))
  );
$$;
revoke execute on function duc_khuon_cs_sua_mau_duoc() from public, anon;
grant execute on function duc_khuon_cs_sua_mau_duoc() to authenticated;

alter table duc_khuon_cs_mau enable row level security;
drop policy if exists "cs_mau public read" on duc_khuon_cs_mau;
create policy "cs_mau public read" on duc_khuon_cs_mau for select using (true);
drop policy if exists "cs_mau write" on duc_khuon_cs_mau;
create policy "cs_mau write" on duc_khuon_cs_mau for all
  using (duc_khuon_cs_sua_mau_duoc()) with check (duc_khuon_cs_sua_mau_duoc());
grant select on duc_khuon_cs_mau to anon, authenticated;
grant insert, update, delete on duc_khuon_cs_mau to authenticated;
grant usage, select on sequence duc_khuon_cs_mau_id_seq to authenticated;

-- Mẫu mặc định (khuôn đúc áp lực) — chỉ nạp khi bảng còn trống.
insert into duc_khuon_cs_mau (nhom, noi_dung, tieu_chuan, thu_tu)
select * from (values
  ('1. Vệ sinh', 'Vệ sinh lòng khuôn, lõi', 'Sạch bám kim loại, chất tách khuôn, cặn', 10),
  ('1. Vệ sinh', 'Vệ sinh mặt phân khuôn', 'Phẳng, không bavia/bám kim loại', 20),
  ('1. Vệ sinh', 'Vệ sinh rãnh thoát khí, túi tràn (overflow)', 'Thông, không tắc', 30),
  ('2. Lòng khuôn', 'Kiểm tra nứt nhiệt / nứt chân chim', 'Không nứt ở vùng tạo hình sản phẩm', 40),
  ('2. Lòng khuôn', 'Kiểm tra mòn, sứt mẻ, dính kim loại (hàn dính)', 'Không mòn/sứt ảnh hưởng kích thước, ngoại quan', 50),
  ('2. Lòng khuôn', 'Đánh bóng lòng khuôn (nếu cần)', 'Bề mặt đạt yêu cầu ngoại quan sản phẩm', 60),
  ('3. Cơ cấu đẩy - dẫn hướng', 'Ty đẩy, ty hồi', 'Không cong/gãy, chuyển động trơn, đủ số lượng', 70),
  ('3. Cơ cấu đẩy - dẫn hướng', 'Chốt dẫn hướng, bạc dẫn hướng', 'Không mòn/kẹt, đã bôi trơn', 80),
  ('3. Cơ cấu đẩy - dẫn hướng', 'Lõi trượt (slide), xi lanh kéo lõi', 'Hoạt động trơn tru, không rơ, không rò dầu', 90),
  ('4. Làm mát', 'Đường nước / dầu làm mát', 'Thông dòng, không rò rỉ', 100),
  ('4. Làm mát', 'Đầu nối nhanh, ống, gioăng', 'Không nứt/rò, gioăng còn tốt', 110),
  ('5. Cuống - bạc phun', 'Bạc phun (sleeve), cuống phun, cổng vào (gate)', 'Không mòn/nứt, không bám kim loại', 120),
  ('6. Tổng thể', 'Bu lông, vít, kẹp khuôn', 'Đủ và siết chặt', 130),
  ('6. Tổng thể', 'Tem / mã khuôn, số đếm shot', 'Rõ ràng, đúng khuôn', 140),
  ('7. Sau bảo dưỡng', 'Lắp khuôn, đúc thử, kiểm tra sản phẩm đầu', 'Sản phẩm đầu OK (ngoại quan + kích thước)', 150)
) v(nhom, noi_dung, tieu_chuan, thu_tu)
where not exists (select 1 from duc_khuon_cs_mau);

-- 2) Check sheet ----------------------------------------------------------------
create table if not exists duc_khuon_checksheet (
  id                   bigserial primary key,
  id_ke_hoach          bigint unique references duc_khuon_bd_kh_tuan(id) on delete set null,
  ma_khuon             text not null,
  loai                 text not null,
  ngay_ke_hoach        date,
  ngay_thuc_hien       date not null,
  nguoi_thuc_hien      text not null default '',
  gio_bat_dau          timestamptz,
  gio_ket_thuc         timestamptz,
  thoi_gian_dung_phut  numeric,
  hang_muc             jsonb not null default '[]'::jsonb,  -- [{nhom,noi_dung,tieu_chuan,ket_qua:'OK'|'NG'|'NA'|null,ghi_chu}]
  phu_tung_thay        text not null default '',
  chi_phi              numeric,
  ket_luan             text not null default '' check (ket_luan in ('', 'dat', 'khong_dat')),
  ghi_chu              text not null default '',
  trang_thai           text not null default 'dang_lam' check (trang_thai in ('dang_lam', 'hoan_thanh')),
  id_log               text,
  nguoi_tao            text not null default '',
  nguoi_hoan_thanh     text not null default '',
  thoi_diem_hoan_thanh timestamptz,
  updated_at           timestamptz not null default now()
);
create index if not exists idx_khuon_checksheet_ma_khuon on duc_khuon_checksheet (ma_khuon, ngay_thuc_hien desc);
alter table duc_khuon_checksheet enable row level security;
drop policy if exists "checksheet public read" on duc_khuon_checksheet;
create policy "checksheet public read" on duc_khuon_checksheet for select using (true);
grant select on duc_khuon_checksheet to anon, authenticated;
-- Không cấp ghi trực tiếp — chỉ qua duc_khuon_cs_luu.

-- 3) RPC: lưu nháp / hoàn thành ----------------------------------------------------
create or replace function duc_khuon_cs_luu(p_id_ke_hoach bigint, p_data jsonb, p_hoan_thanh boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me record; v_kh duc_khuon_bd_kh_tuan; v_cs duc_khuon_checksheet; v_mold duc_shot_khuon;
  v_items jsonb; v_ket_luan text; v_ngay date; v_bd timestamptz; v_kt timestamptz; v_dung numeric;
  v_id bigint; v_id_log text; v_now timestamptz := now(); v_mo_ta text; v_reset boolean;
  v_ng text;
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  if coalesce(v_me.o_role, '') not in ('nhan_vien_bao_duong_khuon', 'admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ nhân viên bảo dưỡng khuôn được ghi check sheet');
  end if;

  select * into v_kh from duc_khuon_bd_kh_tuan where id = p_id_ke_hoach;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy lịch bảo dưỡng'); end if;

  select * into v_cs from duc_khuon_checksheet where id_ke_hoach = p_id_ke_hoach for update;
  if found and v_cs.trang_thai = 'hoan_thanh' then
    return jsonb_build_object('ok', false, 'error', 'Check sheet đã hoàn thành — không sửa được nữa');
  end if;

  v_items := coalesce(p_data->'hang_muc', '[]'::jsonb);
  if jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Check sheet chưa có hạng mục nào');
  end if;
  v_ket_luan := coalesce(p_data->>'ket_luan', '');
  v_ngay := coalesce(nullif(p_data->>'ngay_thuc_hien', '')::date, v_kh.ngay);
  v_bd := nullif(p_data->>'gio_bat_dau', '')::timestamptz;
  v_kt := nullif(p_data->>'gio_ket_thuc', '')::timestamptz;
  if v_bd is not null and v_kt is not null then
    if v_kt < v_bd then return jsonb_build_object('ok', false, 'error', 'Giờ kết thúc phải sau giờ bắt đầu'); end if;
    v_dung := round(extract(epoch from (v_kt - v_bd)) / 60);
  end if;

  if p_hoan_thanh then
    if exists (select 1 from jsonb_array_elements(v_items) x where coalesce(x->>'ket_qua', '') not in ('OK', 'NG', 'NA')) then
      return jsonb_build_object('ok', false, 'error', 'Còn hạng mục chưa đánh giá OK / NG / N/A');
    end if;
    if exists (select 1 from jsonb_array_elements(v_items) x where x->>'ket_qua' = 'NG' and coalesce(trim(x->>'ghi_chu'), '') = '') then
      return jsonb_build_object('ok', false, 'error', 'Hạng mục NG phải ghi chú tình trạng / cách xử lý');
    end if;
    if v_ket_luan not in ('dat', 'khong_dat') then
      return jsonb_build_object('ok', false, 'error', 'Chọn kết luận Đạt / Không đạt');
    end if;
    if coalesce(trim(p_data->>'nguoi_thuc_hien'), '') = '' then
      return jsonb_build_object('ok', false, 'error', 'Nhập người thực hiện');
    end if;
  end if;

  if v_cs.id is null then
    insert into duc_khuon_checksheet (id_ke_hoach, ma_khuon, loai, ngay_ke_hoach, ngay_thuc_hien, nguoi_tao)
    values (v_kh.id, v_kh.ma_khuon, v_kh.loai, v_kh.ngay, v_ngay, v_me.o_ten)
    returning id into v_id;
  else
    v_id := v_cs.id;
  end if;

  update duc_khuon_checksheet set
    ngay_thuc_hien = v_ngay,
    loai = v_kh.loai,
    nguoi_thuc_hien = coalesce(trim(p_data->>'nguoi_thuc_hien'), ''),
    gio_bat_dau = v_bd, gio_ket_thuc = v_kt, thoi_gian_dung_phut = v_dung,
    hang_muc = v_items,
    phu_tung_thay = coalesce(trim(p_data->>'phu_tung_thay'), ''),
    chi_phi = nullif(p_data->>'chi_phi', '')::numeric,
    ket_luan = v_ket_luan,
    ghi_chu = coalesce(trim(p_data->>'ghi_chu'), ''),
    updated_at = v_now
  where id = v_id;

  if not p_hoan_thanh then
    return jsonb_build_object('ok', true, 'id', v_id, 'trang_thai', 'dang_lam');
  end if;

  -- Hoàn thành: ghi sổ đời khuôn + reset đồng hồ shot nếu đạt.
  select * into v_mold from duc_shot_khuon where ma_khuon = v_kh.ma_khuon for update;
  if v_kh.loai in ('Bảo dưỡng định kỳ', 'Sửa chữa', 'Thay khuôn mới') then
    select string_agg(x->>'noi_dung' || ': ' || coalesce(x->>'ghi_chu', ''), '; ') into v_ng
    from jsonb_array_elements(v_items) x where x->>'ket_qua' = 'NG';
    v_mo_ta := 'Check sheet #' || v_id || ' — ' || case when v_ket_luan = 'dat' then 'ĐẠT' else 'KHÔNG ĐẠT' end
      || case when v_ng is not null then '. NG: ' || v_ng else '' end
      || case when coalesce(trim(p_data->>'phu_tung_thay'), '') <> '' then '. Phụ tùng thay: ' || trim(p_data->>'phu_tung_thay') else '' end
      || case when coalesce(trim(p_data->>'ghi_chu'), '') <> '' then '. ' || trim(p_data->>'ghi_chu') else '' end;
    v_id_log := 'BD-' || duc_normalize_name(v_kh.ma_khuon) || '-' || to_char(v_now, 'YYYYMMDDHH24MISS');
    insert into duc_khuon_bao_duong_log (
      id_log, ma_khuon, loai, ngay, shot_tai_thoi_diem, nguoi_thuc_hien, mo_ta,
      chi_phi, thoi_gian_dung_phut, thoi_diem_ghi
    ) values (
      v_id_log, v_kh.ma_khuon, v_kh.loai, v_ngay, coalesce(v_mold.tong_shot_luy_ke, 0),
      trim(p_data->>'nguoi_thuc_hien'), v_mo_ta, nullif(p_data->>'chi_phi', '')::numeric, v_dung, v_now
    );
    v_reset := v_ket_luan = 'dat' and v_kh.loai in ('Bảo dưỡng định kỳ', 'Thay khuôn mới') and v_mold.ma_khuon is not null;
    if v_reset then
      update duc_shot_khuon set
        lan_bao_duong_gan_nhat = v_ngay,
        shot_tai_lan_bao_duong_gan_nhat = coalesce(tong_shot_luy_ke, 0),
        trang_thai_khuon = duc_compute_mold_status(coalesce(tong_shot_luy_ke, 0), coalesce(tong_shot_luy_ke, 0),
          coalesce(nguong_bao_duong, 10000), coalesce(nguong_lam_moi, 100000)),
        last_updated_at = v_now
      where ma_khuon = v_kh.ma_khuon;
    end if;
  end if;

  update duc_khuon_checksheet set trang_thai = 'hoan_thanh', id_log = v_id_log,
    nguoi_hoan_thanh = v_me.o_ten, thoi_diem_hoan_thanh = v_now, updated_at = v_now
  where id = v_id;

  return jsonb_build_object('ok', true, 'id', v_id, 'trang_thai', 'hoan_thanh', 'id_log', v_id_log, 'reset_dong_ho', coalesce(v_reset, false));
end;
$$;
revoke execute on function duc_khuon_cs_luu(bigint, jsonb, boolean) from public, anon;
grant execute on function duc_khuon_cs_luu(bigint, jsonb, boolean) to authenticated;

-- 4) Chặn xoá lịch / đổi khuôn khi đã có check sheet ------------------------------
create or replace function duc_khuon_bd_kh_chan_khi_co_cs()
returns trigger
language plpgsql
as $$
begin
  if exists (select 1 from duc_khuon_checksheet where id_ke_hoach = old.id) then
    if tg_op = 'DELETE' then
      raise exception 'Lịch khuôn % đã có check sheet — không xoá được', old.ma_khuon;
    elsif new.ma_khuon is distinct from old.ma_khuon then
      raise exception 'Lịch khuôn % đã có check sheet — không đổi khuôn được', old.ma_khuon;
    end if;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
drop trigger if exists trg_duc_khuon_bd_kh_chan_khi_co_cs on duc_khuon_bd_kh_tuan;
create trigger trg_duc_khuon_bd_kh_chan_khi_co_cs
  before update of ma_khuon or delete on duc_khuon_bd_kh_tuan
  for each row execute function duc_khuon_bd_kh_chan_khi_co_cs();

-- 5) RPC sửa/xoá lịch (T75) — báo lỗi dễ hiểu khi lịch đã có check sheet
--    (trigger ở mục 4 vẫn là chốt chặn cuối).
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
    if v_old.ma_khuon <> trim(p_ma_khuon) and exists (select 1 from duc_khuon_checksheet where id_ke_hoach = p_id) then
      return jsonb_build_object('ok', false, 'error', 'Lịch đã có check sheet — không đổi khuôn được');
    end if;
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
  if exists (select 1 from duc_khuon_checksheet where id_ke_hoach = p_id) then
    return jsonb_build_object('ok', false, 'error', 'Lịch đã có check sheet — không xoá được');
  end if;
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
