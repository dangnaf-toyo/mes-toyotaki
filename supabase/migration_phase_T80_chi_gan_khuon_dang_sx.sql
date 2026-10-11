-- ============================================================================
-- T80 — Bảng điều khiển Đúc chỉ gắn được khuôn có tình trạng "Đang sản xuất".
--
-- 1) Trigger trên duc_ca_hien_tai (cùng kiểu T71): khi INSERT hoặc đổi so_khuon,
--    khuôn có trong duc_shot_khuon mà tinh_trang <> 'dang_sx' thì bị chặn.
--    Ngoại lệ (không phải "gắn khuôn mới lên máy"):
--    - khuôn đã nằm trên chính máy đó ở dòng khác (chuyển ca
--      duc_carry_over_shift, đổi SP giữ nguyên khuôn...);
--    - đổi tên khuôn (duc_rename_khuon: mã cũ đã bị xoá khỏi duc_shot_khuon).
--    Khuôn chỉ khai báo ở master_products.so_khuon (chưa có dòng shot) coi như
--    đang SX.
-- 2) duc_rename_khuon: chép thêm tình trạng (T79) sang mã mới, chuyển luôn
--    lịch sử tình trạng + hạng mục check sheet riêng / mục chung bị bỏ (T78)
--    theo mã mới (trước đây bị rơi mất khi đổi tên).
--
-- Chạy trên CẢ 2 project (production + staging). Idempotent. Chạy sau T79.
-- ============================================================================

create or replace function duc_ca_hien_tai_chan_khuon_ngung_sx()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tt text; v_mk text := trim(coalesce(new.so_khuon, ''));
begin
  if v_mk = '' then return new; end if;
  if tg_op = 'UPDATE' and new.so_khuon is not distinct from old.so_khuon then return new; end if;
  select tinh_trang into v_tt from duc_shot_khuon where ma_khuon = v_mk;
  if v_tt is null or v_tt = 'dang_sx' then return new; end if;
  -- khuôn đã nằm trên chính máy này (chuyển ca / đổi SP giữ khuôn) -> cho qua
  if exists (select 1 from duc_ca_hien_tai where ma_may = new.ma_may and trim(so_khuon) = v_mk
             and id_dong is distinct from new.id_dong) then
    return new;
  end if;
  -- đổi tên khuôn: mã cũ đã bị xoá khỏi duc_shot_khuon trước khi update dòng ca
  if tg_op = 'UPDATE' and new.ma_may is not distinct from old.ma_may
     and not exists (select 1 from duc_shot_khuon where ma_khuon = trim(coalesce(old.so_khuon, ''))) then
    return new;
  end if;
  raise exception 'Khuôn % đang ở tình trạng "%" — chỉ gắn được khuôn Đang sản xuất (đổi ở Quản lý khuôn)', v_mk,
    case v_tt when 'moi_chua_sx' then 'Mới — chưa vào SX' when 'dung_het_tuoi_tho' then 'Hết tuổi thọ — dừng SX'
              when 'cho_tra_khach' then 'Chờ trả khách hàng' when 'cho_bao_phe' then 'Chờ báo phế' else v_tt end;
end;
$$;
revoke execute on function duc_ca_hien_tai_chan_khuon_ngung_sx() from public, anon, authenticated;

drop trigger if exists trg_duc_ca_hien_tai_chan_khuon_ngung_sx on duc_ca_hien_tai;
create trigger trg_duc_ca_hien_tai_chan_khuon_ngung_sx
  before insert or update of so_khuon on duc_ca_hien_tai
  for each row execute function duc_ca_hien_tai_chan_khuon_ngung_sx();

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
    tinh_trang, tinh_trang_ly_do, tinh_trang_luc, tinh_trang_boi
  ) values (
    v_moi, v_row.ten_sp_gan_nhat, v_row.tong_shot_luy_ke, v_row.nguong_bao_duong, v_row.nguong_lam_moi,
    v_row.lan_bao_duong_gan_nhat, v_row.shot_tai_lan_bao_duong_gan_nhat, v_row.trang_thai_khuon,
    coalesce(v_row.ghi_chu, '') || case when coalesce(v_row.ghi_chu, '') = '' then '' else E'\n' end
      || '[Đổi tên từ "' || v_cu || '" ngày ' || to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
      || ' bởi ' || coalesce(nullif(trim(p_user), ''), '?') || ']',
    v_now, v_row.chu_ky_bao_duong_ngay,
    v_row.tinh_trang, v_row.tinh_trang_ly_do, v_row.tinh_trang_luc, v_row.tinh_trang_boi
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
