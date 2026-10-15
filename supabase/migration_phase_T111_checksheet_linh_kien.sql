-- ============================================================================
-- T111 — Check sheet bảo dưỡng khuôn ghi linh kiện / vật tư tiêu hao đã thay
-- (user 2026-10-15), giống form xử lý bất thường (T107).
--
--   khuon_lk_ghi_giao_dich thêm tham số p_id_checksheet (cột id_checksheet đã
--   có từ T94): chỉ phiếu xuất thay / tháo ra, không gắn đồng thời sự cố,
--   check sheet phải tồn tại và CHƯA hoàn thành; khuôn của phiếu = khuôn của
--   check sheet (server tự lấy). Hàm 12 tham số bị DROP để PostgREST không gặp
--   2 bản trùng tên.
--
-- Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

create index if not exists khuon_lk_gd_checksheet_idx on khuon_lk_giao_dich(id_checksheet) where id_checksheet is not null;

drop function if exists khuon_lk_ghi_giao_dich(text,bigint,numeric,text,text,text,text,text,numeric,numeric,text,text);
create or replace function khuon_lk_ghi_giao_dich(
  p_loai text, p_id_lk bigint, p_so_luong numeric,
  p_ma_khuon text default null, p_vi_tri text default null, p_muc_dich text default null,
  p_ket_qua_thao text default null, p_tu_trang_thai text default null,
  p_ton_cho_su_dung numeric default null, p_ton_cho_sua numeric default null,
  p_ghi_chu text default null, p_id_su_co text default null, p_id_checksheet bigint default null)
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
  v_cs duc_khuon_checksheet%rowtype;
  v_d1 numeric := 0; v_d2 numeric := 0; v_shot numeric; v_id bigint;
begin
  if p_loai not in ('nhap','xuat_thay','thao_ra','sua_xong','bao_phe','kiem_ke') then
    return jsonb_build_object('ok', false, 'error', 'Loại phiếu không hợp lệ');
  end if;
  select * into v_me from khuon_lk_nguoi(case when p_loai in ('xuat_thay','thao_ra') then 'thay' else 'quan_ly' end);
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;

  if (v_sc is not null or p_id_checksheet is not null) and p_loai not in ('xuat_thay','thao_ra') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ phiếu xuất thay / tháo ra mới gắn với sự cố / check sheet');
  end if;
  if v_sc is not null and p_id_checksheet is not null then
    return jsonb_build_object('ok', false, 'error', 'Phiếu chỉ gắn với sự cố hoặc check sheet, không cả hai');
  end if;
  if v_sc is not null then
    if not exists (select 1 from duc_su_co_log where id_su_co = v_sc)
       and not exists (select 1 from duc_ca_hien_tai where open_id_su_co = v_sc) then
      return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố ' || v_sc);
    end if;
  end if;
  if p_id_checksheet is not null then
    select * into v_cs from duc_khuon_checksheet where id = p_id_checksheet;
    if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy check sheet #' || p_id_checksheet); end if;
    if v_cs.trang_thai = 'hoan_thanh' then
      return jsonb_build_object('ok', false, 'error', 'Check sheet đã hoàn thành — không ghi thêm linh kiện');
    end if;
    v_mk := v_cs.ma_khuon;
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
    ton_sau_cho_su_dung, ton_sau_cho_sua, ma_khuon, vi_tri, shot_khuon, muc_dich, ket_qua_thao, id_su_co, id_checksheet,
    nguoi, nguoi_uid, vai_tro, ghi_chu)
  values (p_loai, p_id_lk, v_lk.ma_lk, v_lk.ten_lk, v_sl, v_d1, v_d2,
    v_lk.ton_cho_su_dung + v_d1, v_lk.ton_cho_sua + v_d2, v_mk, trim(coalesce(p_vi_tri, '')), v_shot, v_md,
    case when p_loai = 'thao_ra' then p_ket_qua_thao end, v_sc, p_id_checksheet,
    v_me.o_ten, auth.uid(), v_me.o_role, trim(coalesce(p_ghi_chu, '')))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id,
    'ton_cho_su_dung', v_lk.ton_cho_su_dung + v_d1, 'ton_cho_sua', v_lk.ton_cho_sua + v_d2);
end $$;
revoke execute on function khuon_lk_ghi_giao_dich(text,bigint,numeric,text,text,text,text,text,numeric,numeric,text,text,bigint) from public, anon;
grant execute on function khuon_lk_ghi_giao_dich(text,bigint,numeric,text,text,text,text,text,numeric,numeric,text,text,bigint) to authenticated;
