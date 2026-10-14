-- ============================================================================
-- T107 — Dashboard tổ khuôn: xử lý bất thường (T103) ghi linh kiện / vật tư
-- tiêu hao đã dùng + tạm bỏ bắt buộc ảnh khi hoàn thành (user 2026-10-14).
--
--   1) Công tắc duc_cau_hinh['xlbt_bat_buoc_anh'] (mặc định false = KHÔNG bắt
--      buộc ảnh trước/sau). Bật lại: update duc_cau_hinh set gia_tri='true'
--      where khoa='xlbt_bat_buoc_anh'.
--   2) khuon_lk_danh_muc.loai thêm 'vat_tu_tieu_hao' (mã nhóm CSM) — vật tư
--      tiêu hao quản lý chung danh mục / tồn / sổ giao dịch với linh kiện.
--   3) khuon_lk_giao_dich.id_su_co: giao dịch gắn với sự cố (xuất thay / tháo
--      ra ghi từ form xử lý bất thường). khuon_lk_ghi_giao_dich thêm tham số
--      p_id_su_co (kiểm tra sự cố tồn tại); vật tư tiêu hao xuất không bắt
--      buộc khuôn. Hàm cũ bị DROP để PostgREST không gặp 2 bản trùng tên.
--   4) duc_khuon_xlbt_luu: kiểm ảnh theo công tắc ở (1).
--
-- Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

insert into duc_cau_hinh (khoa, gia_tri, ghi_chu)
values ('xlbt_bat_buoc_anh', 'false'::jsonb, 'T107: true = hoàn thành xử lý bất thường (dashboard tổ khuôn) bắt buộc ≥1 ảnh trước + ≥1 ảnh sau')
on conflict (khoa) do nothing;

-- 2) Loại vật tư tiêu hao ------------------------------------------------------
alter table khuon_lk_danh_muc drop constraint if exists khuon_lk_danh_muc_loai_check;
alter table khuon_lk_danh_muc add constraint khuon_lk_danh_muc_loai_check check (loai in (
  'insert','pin_tao_lo','loi_truot','ejector_pin','return_pin',
  'co_khuon','plunger_tip','sleeve','lo_xo','dau_noi_nuoc','khac','vat_tu_tieu_hao'));

-- 3) Giao dịch gắn sự cố --------------------------------------------------------
alter table khuon_lk_giao_dich add column if not exists id_su_co text;
create index if not exists khuon_lk_gd_su_co_idx on khuon_lk_giao_dich(id_su_co) where id_su_co is not null;

drop function if exists khuon_lk_ghi_giao_dich(text,bigint,numeric,text,text,text,text,text,numeric,numeric,text);
create or replace function khuon_lk_ghi_giao_dich(
  p_loai text, p_id_lk bigint, p_so_luong numeric,
  p_ma_khuon text default null, p_vi_tri text default null, p_muc_dich text default null,
  p_ket_qua_thao text default null, p_tu_trang_thai text default null,
  p_ton_cho_su_dung numeric default null, p_ton_cho_sua numeric default null,
  p_ghi_chu text default null, p_id_su_co text default null)
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
  v_sc text := nullif(trim(coalesce(p_id_su_co, '')), '');
  v_d1 numeric := 0; v_d2 numeric := 0; v_shot numeric; v_id bigint;
begin
  if p_loai not in ('nhap','xuat_thay','thao_ra','sua_xong','bao_phe','kiem_ke') then
    return jsonb_build_object('ok', false, 'error', 'Loại phiếu không hợp lệ');
  end if;
  select * into v_me from khuon_lk_nguoi(case when p_loai in ('xuat_thay','thao_ra') then 'thay' else 'quan_ly' end);
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;

  if v_sc is not null then
    if p_loai not in ('xuat_thay','thao_ra') then
      return jsonb_build_object('ok', false, 'error', 'Chỉ phiếu xuất thay / tháo ra mới gắn với sự cố');
    end if;
    if not exists (select 1 from duc_su_co_log where id_su_co = v_sc)
       and not exists (select 1 from duc_ca_hien_tai where open_id_su_co = v_sc) then
      return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố ' || v_sc);
    end if;
  end if;

  -- Khoá dòng tồn: 2 phiếu cùng lúc không làm lệch số.
  select * into v_lk from khuon_lk_danh_muc where id = p_id_lk for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy linh kiện'); end if;

  if p_loai <> 'kiem_ke' and v_sl <= 0 then return jsonb_build_object('ok', false, 'error', 'Số lượng phải > 0'); end if;
  if p_loai in ('xuat_thay','thao_ra') then
    if v_mk is null and v_lk.loai <> 'vat_tu_tieu_hao' then return jsonb_build_object('ok', false, 'error', 'Chọn khuôn'); end if;
    if v_mk is not null then
      select tong_shot_luy_ke into v_shot from duc_shot_khuon where ma_khuon = v_mk;
      if not found then return jsonb_build_object('ok', false, 'error', 'Không có khuôn ' || v_mk); end if;
    end if;
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
    return jsonb_build_object('ok', false, 'error', 'Không đủ tồn Chờ sử dụng của ' || v_lk.ma_lk || ' (còn ' || v_lk.ton_cho_su_dung || ' ' || v_lk.don_vi || ')');
  end if;
  if v_lk.ton_cho_sua + v_d2 < 0 then
    return jsonb_build_object('ok', false, 'error', 'Không đủ tồn Chờ sửa của ' || v_lk.ma_lk || ' (còn ' || v_lk.ton_cho_sua || ' ' || v_lk.don_vi || ')');
  end if;

  update khuon_lk_danh_muc set ton_cho_su_dung = ton_cho_su_dung + v_d1, ton_cho_sua = ton_cho_sua + v_d2
  where id = p_id_lk;

  insert into khuon_lk_giao_dich (loai, id_lk, ma_lk, ten_lk, so_luong, delta_cho_su_dung, delta_cho_sua,
    ton_sau_cho_su_dung, ton_sau_cho_sua, ma_khuon, vi_tri, shot_khuon, muc_dich, ket_qua_thao, id_su_co,
    nguoi, nguoi_uid, vai_tro, ghi_chu)
  values (p_loai, p_id_lk, v_lk.ma_lk, v_lk.ten_lk, v_sl, v_d1, v_d2,
    v_lk.ton_cho_su_dung + v_d1, v_lk.ton_cho_sua + v_d2, v_mk, trim(coalesce(p_vi_tri, '')), v_shot, v_md,
    case when p_loai = 'thao_ra' then p_ket_qua_thao end, v_sc,
    v_me.o_ten, auth.uid(), v_me.o_role, trim(coalesce(p_ghi_chu, '')))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id,
    'ton_cho_su_dung', v_lk.ton_cho_su_dung + v_d1, 'ton_cho_sua', v_lk.ton_cho_sua + v_d2);
end $$;
revoke execute on function khuon_lk_ghi_giao_dich(text,bigint,numeric,text,text,text,text,text,numeric,numeric,text,text) from public, anon;
grant execute on function khuon_lk_ghi_giao_dich(text,bigint,numeric,text,text,text,text,text,numeric,numeric,text,text) to authenticated;

-- 4) Hoàn thành xử lý bất thường: ảnh theo công tắc ----------------------------
create or replace function duc_khuon_xlbt_luu(
  p_id_su_co text, p_hanh_dong text,
  p_nguoi_dam_nhiem text default '', p_nguoi_dam_nhiem_phu text default '',
  p_bat_dau timestamptz default null, p_ket_thuc timestamptz default null,
  p_noi_dung text default '')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me record;
  v_id text := trim(coalesce(p_id_su_co, ''));
  v_cu duc_khuon_xu_ly_bat_thuong;
  v_chinh text := trim(coalesce(p_nguoi_dam_nhiem, ''));
  v_phu text := trim(coalesce(p_nguoi_dam_nhiem_phu, ''));
  v_nd text := trim(coalesce(p_noi_dung, ''));
  v_ps timestamptz;
  v_anh_truoc int; v_anh_sau int;
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  if not duc_khuon_bd_la_nguoi_lap(v_me.o_role, v_me.o_bo_phan) then
    return jsonb_build_object('ok', false, 'error', 'Chỉ nhân viên bảo dưỡng khuôn / Quản lý bộ phận Đúc được ghi xử lý bất thường');
  end if;
  if p_hanh_dong not in ('luu', 'hoan_thanh', 'mo_lai') then
    return jsonb_build_object('ok', false, 'error', 'Thao tác không hợp lệ');
  end if;

  select least(
      (select min(gio_phat_sinh) from duc_su_co_log where id_su_co = v_id and left(coalesce(loai_su_co, ''), 2) in ('A2', 'B1', 'F1')),
      (select min(open_gio_phat_sinh) from duc_ca_hien_tai where open_id_su_co = v_id and left(coalesce(open_loai_su_co, ''), 2) in ('A2', 'B1', 'F1')))
    into v_ps;
  if v_ps is null then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố A2/B1/F1 mã ' || v_id);
  end if;

  select * into v_cu from duc_khuon_xu_ly_bat_thuong where id_su_co = v_id for update;

  if p_hanh_dong = 'mo_lai' then
    if v_cu.id_su_co is null or v_cu.trang_thai <> 'hoan_thanh' then
      return jsonb_build_object('ok', false, 'error', 'Phiếu chưa hoàn thành');
    end if;
    update duc_khuon_xu_ly_bat_thuong set trang_thai = 'dang_xu_ly', nguoi_hoan_thanh = '', hoan_thanh_luc = null,
      nguoi_cap_nhat = coalesce(v_me.o_ten, ''), cap_nhat_luc = now()
    where id_su_co = v_id;
    return jsonb_build_object('ok', true);
  end if;

  if v_cu.trang_thai = 'hoan_thanh' then
    return jsonb_build_object('ok', false, 'error', 'Phiếu đã hoàn thành — bấm Mở lại để sửa');
  end if;
  if v_phu <> '' and v_phu = v_chinh then
    return jsonb_build_object('ok', false, 'error', 'Đảm nhiệm phụ phải khác đảm nhiệm chính');
  end if;
  if p_bat_dau is not null and p_bat_dau < v_ps - interval '5 minutes' then
    return jsonb_build_object('ok', false, 'error', 'Thời gian bắt đầu trước giờ phát sinh sự cố');
  end if;
  if p_bat_dau is not null and p_bat_dau > now() + interval '5 minutes' then
    return jsonb_build_object('ok', false, 'error', 'Thời gian bắt đầu ở tương lai');
  end if;
  if p_ket_thuc is not null and p_ket_thuc > now() + interval '5 minutes' then
    return jsonb_build_object('ok', false, 'error', 'Thời gian kết thúc ở tương lai');
  end if;
  if p_ket_thuc is not null and (p_bat_dau is null or p_ket_thuc < p_bat_dau) then
    return jsonb_build_object('ok', false, 'error', 'Thời gian kết thúc phải sau thời gian bắt đầu');
  end if;

  if p_hanh_dong = 'hoan_thanh' then
    if v_chinh = '' then return jsonb_build_object('ok', false, 'error', 'Chọn người đảm nhiệm chính'); end if;
    if p_bat_dau is null or p_ket_thuc is null then
      return jsonb_build_object('ok', false, 'error', 'Nhập đủ thời gian bắt đầu và kết thúc xử lý');
    end if;
    if v_nd = '' then return jsonb_build_object('ok', false, 'error', 'Nhập nội dung xử lý'); end if;
    if coalesce((select gia_tri = 'true'::jsonb from duc_cau_hinh where khoa = 'xlbt_bat_buoc_anh'), false) then
      select count(*) filter (where loai = 'truoc'), count(*) filter (where loai = 'sau')
        into v_anh_truoc, v_anh_sau from duc_su_co_anh where id_su_co = v_id;
      if v_anh_truoc = 0 or v_anh_sau = 0 then
        return jsonb_build_object('ok', false, 'error', 'Cần ít nhất 1 ảnh trước và 1 ảnh sau xử lý');
      end if;
    end if;
  end if;

  insert into duc_khuon_xu_ly_bat_thuong as x (id_su_co, trang_thai, nguoi_dam_nhiem, nguoi_dam_nhiem_phu, bat_dau, ket_thuc,
      noi_dung_xu_ly, nguoi_cap_nhat, cap_nhat_luc, nguoi_hoan_thanh, hoan_thanh_luc)
  values (v_id, case when p_hanh_dong = 'hoan_thanh' then 'hoan_thanh' else 'dang_xu_ly' end, v_chinh, v_phu, p_bat_dau, p_ket_thuc,
      v_nd, coalesce(v_me.o_ten, ''), now(),
      case when p_hanh_dong = 'hoan_thanh' then coalesce(v_me.o_ten, '') else '' end,
      case when p_hanh_dong = 'hoan_thanh' then now() end)
  on conflict (id_su_co) do update set
    trang_thai = excluded.trang_thai, nguoi_dam_nhiem = excluded.nguoi_dam_nhiem,
    nguoi_dam_nhiem_phu = excluded.nguoi_dam_nhiem_phu, bat_dau = excluded.bat_dau, ket_thuc = excluded.ket_thuc,
    noi_dung_xu_ly = excluded.noi_dung_xu_ly, nguoi_cap_nhat = excluded.nguoi_cap_nhat, cap_nhat_luc = now(),
    nguoi_hoan_thanh = excluded.nguoi_hoan_thanh, hoan_thanh_luc = excluded.hoan_thanh_luc;

  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function duc_khuon_xlbt_luu(text, text, text, text, timestamptz, timestamptz, text) from public, anon;
grant execute on function duc_khuon_xlbt_luu(text, text, text, text, timestamptz, timestamptz, text) to authenticated;
