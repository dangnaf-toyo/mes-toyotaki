-- ============================================================================
-- T86 — Thứ tự ưu tiên khuôn trong cùng mã SP (quan-ly-khuon.html), Bảng điều
-- khiển Đúc chọn khuôn mặc định theo thứ tự này.
--
-- - duc_shot_khuon.uu_tien (1 = ưu tiên nhất). Mã SP của khuôn = phần trước " ("
--   của ten_sp_gan_nhat (cùng cách dashboard đang ghép khuôn ↔ mã SP).
-- - Chỉ khuôn tình trạng 'dang_sx' có ưu tiên. Trigger tự xoá uu_tien khi khuôn
--   rời 'dang_sx' hoặc đổi sang mã SP khác.
-- - RPC duc_khuon_dat_uu_tien(p_ma_sp, p_ds_khuon[]): đặt lại cả thứ tự của mã.
--   Quyền: nhân viên bảo dưỡng khuôn, Quản lý bộ phận Đúc, admin (như T79).
-- - duc_rename_khuon chép thêm uu_tien sang mã mới.
--
-- Chạy trên CẢ 2 project (production + staging). Idempotent. Chạy sau T80.
-- ============================================================================

alter table duc_shot_khuon add column if not exists uu_tien int;
alter table duc_shot_khuon drop constraint if exists duc_shot_khuon_uu_tien_check;
alter table duc_shot_khuon add constraint duc_shot_khuon_uu_tien_check check (uu_tien is null or uu_tien >= 1);

create or replace function duc_khuon_ma_sp_cua(p_ten_sp_gan_nhat text)
returns text
language sql
immutable
as $$ select trim(split_part(coalesce(p_ten_sp_gan_nhat, ''), ' (', 1)); $$;

create or replace function duc_shot_khuon_don_uu_tien()
returns trigger
language plpgsql
as $$
begin
  if new.uu_tien is not null and (
       coalesce(new.tinh_trang, 'dang_sx') <> 'dang_sx'
       or duc_khuon_ma_sp_cua(new.ten_sp_gan_nhat) is distinct from duc_khuon_ma_sp_cua(old.ten_sp_gan_nhat)) then
    new.uu_tien := null;
  end if;
  return new;
end;
$$;
revoke execute on function duc_shot_khuon_don_uu_tien() from public, anon, authenticated;
drop trigger if exists trg_duc_shot_khuon_don_uu_tien on duc_shot_khuon;
create trigger trg_duc_shot_khuon_don_uu_tien
  before update of tinh_trang, ten_sp_gan_nhat on duc_shot_khuon
  for each row execute function duc_shot_khuon_don_uu_tien();

create or replace function duc_khuon_dat_uu_tien(p_ma_sp text, p_ds_khuon text[])
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me record; v_sp text := trim(coalesce(p_ma_sp, '')); v_mk text; i int := 0; v_tt text; v_sp_khuon text;
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  if not (coalesce(v_me.o_role, '') in ('admin', 'nhan_vien_bao_duong_khuon')
          or (v_me.o_role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(v_me.o_bo_phan, '{}')))) then
    return jsonb_build_object('ok', false, 'error', 'Chỉ nhân viên bảo dưỡng khuôn / Quản lý bộ phận Đúc / admin được đặt ưu tiên khuôn');
  end if;
  if v_sp = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã SP'); end if;
  if coalesce(cardinality(p_ds_khuon), 0) = 0 then return jsonb_build_object('ok', false, 'error', 'Chưa có khuôn nào'); end if;
  if (select count(distinct trim(x)) from unnest(p_ds_khuon) x) <> cardinality(p_ds_khuon) then
    return jsonb_build_object('ok', false, 'error', 'Danh sách khuôn bị trùng');
  end if;

  foreach v_mk in array p_ds_khuon loop
    select tinh_trang, duc_khuon_ma_sp_cua(ten_sp_gan_nhat) into v_tt, v_sp_khuon
      from duc_shot_khuon where ma_khuon = trim(v_mk) for update;
    if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy khuôn ' || v_mk); end if;
    if v_sp_khuon is distinct from v_sp then
      return jsonb_build_object('ok', false, 'error', 'Khuôn ' || v_mk || ' không thuộc mã ' || v_sp);
    end if;
    if coalesce(v_tt, 'dang_sx') <> 'dang_sx' then
      return jsonb_build_object('ok', false, 'error', 'Khuôn ' || v_mk || ' không ở tình trạng Đang sản xuất');
    end if;
  end loop;

  update duc_shot_khuon set uu_tien = null where duc_khuon_ma_sp_cua(ten_sp_gan_nhat) = v_sp and uu_tien is not null;
  foreach v_mk in array p_ds_khuon loop
    i := i + 1;
    update duc_shot_khuon set uu_tien = i where ma_khuon = trim(v_mk);
  end loop;
  return jsonb_build_object('ok', true, 'ma_sp', v_sp, 'so_khuon', i);
end;
$$;
revoke execute on function duc_khuon_dat_uu_tien(text, text[]) from public, anon;
grant execute on function duc_khuon_dat_uu_tien(text, text[]) to authenticated;

-- Đổi tên khuôn: giữ uu_tien (bản T80 + cột uu_tien).
create or replace function duc_rename_khuon(p_ma_khuon_cu text, p_ma_khuon_moi text, p_user text)
returns jsonb
language plpgsql
security definer
as $function$
declare
  v_cu text := trim(coalesce(p_ma_khuon_cu, ''));
  v_moi text := trim(coalesce(p_ma_khuon_moi, ''));
  v_row duc_shot_khuon%rowtype;
  v_monday date;
  v_now timestamptz := now();
  v_so_ca_hien_tai int;
  v_so_khsx int;
begin
  if v_cu = '' or v_moi = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu mã khuôn cũ/mới');
  end if;
  if v_cu = v_moi then
    return jsonb_build_object('ok', false, 'error', 'Mã khuôn mới trùng mã cũ');
  end if;

  select * into v_row from duc_shot_khuon where ma_khuon = v_cu;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy khuôn: ' || v_cu);
  end if;
  if exists (select 1 from duc_shot_khuon where ma_khuon = v_moi) then
    return jsonb_build_object('ok', false, 'error', 'Mã khuôn mới đã tồn tại: ' || v_moi);
  end if;

  -- đổi PK bảng gốc: xoá dòng cũ, chèn dòng mới giữ nguyên toàn bộ dữ liệu,
  -- ghi lại vết đổi tên vào ghi_chu để tra cứu sau này
  delete from duc_shot_khuon where ma_khuon = v_cu;
  insert into duc_shot_khuon (
    ma_khuon, ten_sp_gan_nhat, tong_shot_luy_ke, nguong_bao_duong, nguong_lam_moi,
    lan_bao_duong_gan_nhat, shot_tai_lan_bao_duong_gan_nhat, trang_thai_khuon, ghi_chu,
    last_updated_at, chu_ky_bao_duong_ngay,
    tinh_trang, tinh_trang_ly_do, tinh_trang_luc, tinh_trang_boi, uu_tien
  ) values (
    v_moi, v_row.ten_sp_gan_nhat, v_row.tong_shot_luy_ke, v_row.nguong_bao_duong, v_row.nguong_lam_moi,
    v_row.lan_bao_duong_gan_nhat, v_row.shot_tai_lan_bao_duong_gan_nhat, v_row.trang_thai_khuon,
    coalesce(v_row.ghi_chu, '') || case when coalesce(v_row.ghi_chu, '') = '' then '' else E'\n' end
      || '[Đổi tên từ "' || v_cu || '" ngày ' || to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
      || ' bởi ' || coalesce(nullif(trim(p_user), ''), '?') || ']',
    v_now, v_row.chu_ky_bao_duong_ngay,
    v_row.tinh_trang, v_row.tinh_trang_ly_do, v_row.tinh_trang_luc, v_row.tinh_trang_boi, v_row.uu_tien
  );

  -- cấu hình gắn với khuôn (T78/T79) đi theo mã mới
  update duc_khuon_tinh_trang_log set ma_khuon = v_moi where ma_khuon = v_cu;
  update duc_khuon_cs_mau set ma_khuon = v_moi where ma_khuon = v_cu;
  update duc_khuon_cs_mau_bo set ma_khuon = v_moi where ma_khuon = v_cu;

  -- trạm đang chạy hiện tại (state, không phải lịch sử) — đổi hết
  update duc_ca_hien_tai set so_khuon = v_moi where so_khuon = v_cu;
  get diagnostics v_so_ca_hien_tai = row_count;

  -- kế hoạch tuần: chỉ tuần hiện tại trở về sau, giữ nguyên các tuần đã qua
  v_monday := date_trunc('week', v_now at time zone 'Asia/Ho_Chi_Minh')::date;
  update duc_khsx_tuan_plan set so_khuon = v_moi, updated_at = v_now
    where so_khuon = v_cu and tuan_bat_dau >= v_monday;
  get diagnostics v_so_khsx = row_count;

  return jsonb_build_object(
    'ok', true, 'ma_khuon_cu', v_cu, 'ma_khuon_moi', v_moi,
    'so_dong_ca_hien_tai_da_doi', v_so_ca_hien_tai, 'so_dong_khsx_da_doi', v_so_khsx
  );
end;
$function$;
