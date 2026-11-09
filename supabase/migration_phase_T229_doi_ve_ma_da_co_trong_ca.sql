-- T229: Đổi sản phẩm về một mã đã có dòng trong ca (vd DC 7 ngày 09/11/2026: OUT-01 -> KPH-02 -> OUT-01).
-- Trước đây duc_change_product báo "đã có dòng với SP ... trong ca này", dòng cũ giữ row_seq nhỏ
-- nên Dashboard Đúc (lấy row_seq lớn nhất) vẫn hiện mã trước đó.
-- Nay: dùng lại dòng đã có, đưa lên làm dòng đang chạy (row_seq mới) và tạo C3 như đổi SP bình thường.
-- Giữ nguyên tt_ca / NG / id_dong của dòng. Vẫn từ chối khi dòng đó thuộc khuôn kép hoặc đang có sự cố mở.
-- Các trigger chặn lên khuôn bỏ qua UPDATE không đổi số khuôn, nên trường hợp cùng khuôn phải tự kiểm
-- chan_len_khuon (T188) ngay trong hàm.
-- Chạy lại được (create or replace).

create or replace function public.duc_change_product(
  p_old_id_dong text, p_new_ma_sp text, p_new_ten_sp text, p_new_so_khuon text, p_new_kh_ca numeric,
  p_new_kh_tuan numeric, p_gio_bat_dau_doi_khuon timestamp with time zone, p_dam_nhiem text, p_user text)
returns jsonb
language plpgsql
security definer
as $function$
declare
  v_old record; v_exist record; v_reuse boolean; v_new_id_dong text; v_win jsonb; v_carry_shot numeric; v_now timestamptz := now();
  v_id_su_co text; v_chan text;
begin
  if p_new_ma_sp is null or trim(p_new_ma_sp) = '' then return jsonb_build_object('ok', false, 'error', 'Chưa nhập mã SP mới'); end if;
  if p_new_kh_ca is null or p_new_kh_ca <= 0 then return jsonb_build_object('ok', false, 'error', 'Chưa nhập KH ca cho SP mới'); end if;
  if p_gio_bat_dau_doi_khuon is null then return jsonb_build_object('ok', false, 'error', 'Chưa nhập giờ bắt đầu đổi khuôn'); end if;
  if p_new_so_khuon is null or trim(p_new_so_khuon) = '' then return jsonb_build_object('ok', false, 'error', 'Bắt buộc nhập số khuôn'); end if;
  if p_gio_bat_dau_doi_khuon > now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Giờ bắt đầu đổi khuôn không được ở tương lai'); end if;

  select * into v_old from duc_ca_hien_tai where id_dong = p_old_id_dong;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng SP cũ: ' || p_old_id_dong); end if;
  -- T188: đang có sự cố mở vẫn đổi SP được (duc_doi_sp_dong_su_co)
  if trim(p_new_ma_sp) = trim(coalesce(v_old.ma_sp, '')) then return jsonb_build_object('ok', false, 'error', 'SP mới trùng với SP hiện tại'); end if;

  v_new_id_dong := duc_make_id_dong(v_old.ngay, v_old.ca, v_old.ma_may, p_new_ma_sp);

  -- T229: mã mới đã có dòng trong ca -> dùng lại dòng đó nếu an toàn
  select * into v_exist from duc_ca_hien_tai where id_dong = v_new_id_dong for update;
  v_reuse := found;
  if v_reuse then
    if v_exist.row_seq > v_old.row_seq then
      return jsonb_build_object('ok', false, 'error', 'Máy ' || v_old.ma_may || ' đã có dòng với SP ' || p_new_ma_sp || ' trong ca này');
    end if;
    if nullif(v_exist.khuon_kep_voi, '') is not null then
      return jsonb_build_object('ok', false, 'error', 'Mã ' || p_new_ma_sp || ' trên máy ' || v_old.ma_may || ' đang thuộc cặp khuôn kép trong ca này, không đổi về được.');
    end if;
    if v_exist.open_gio_phat_sinh is not null then
      return jsonb_build_object('ok', false, 'error', 'Mã ' || p_new_ma_sp || ' trên máy ' || v_old.ma_may || ' đang có sự cố mở (' || coalesce(v_exist.open_id_su_co, v_exist.open_loai_su_co, '') || '). Kết thúc sự cố đó trước khi đổi về mã này.');
    end if;
    if trim(coalesce(v_exist.so_khuon, '')) = trim(p_new_so_khuon) then
      select string_agg(coalesce(id_su_co, id_van_de), ', ') into v_chan
        from duc_van_de_khuon where trim(ma_khuon) = trim(p_new_so_khuon) and chan_len_khuon and trang_thai = 'Mở';
      if v_chan is not null then
        return jsonb_build_object('ok', false, 'error', 'Khuôn ' || trim(p_new_so_khuon) || ' đã xuống máy khi sự cố ' || v_chan || ' chưa xử lý xong — tổ khuôn phải xử lý dứt điểm và ghi nội dung xử lý ở trang "Vấn đề khuôn" trước khi lên lại khuôn.');
      end if;
    end if;
  end if;

  v_win := duc_get_shift_window(v_old.ngay, v_old.phuong_an_ca, v_old.ca);
  v_carry_shot := v_old.so_shot_cuoi_ca;
  if v_carry_shot is null then select so_shot_cuoi_ca_gan_nhat into v_carry_shot from duc_shot_may where ma_may = v_old.ma_may; end if;

  perform duc_doi_sp_dong_su_co(v_old.id_dong, p_gio_bat_dau_doi_khuon, trim(p_new_ma_sp), p_user);   -- T188
  v_id_su_co := duc_make_id_su_co(v_old.ma_may, p_gio_bat_dau_doi_khuon);

  if v_reuse then
    update duc_ca_hien_tai set
      row_seq = nextval('duc_ca_hien_tai_row_seq_seq'::regclass),
      ten_sp = coalesce(nullif(trim(p_new_ten_sp), ''), ten_sp),
      so_khuon = p_new_so_khuon,
      kh_ca = p_new_kh_ca,
      kh_tuan = case when coalesce(p_new_kh_tuan, 0) > 0 then p_new_kh_tuan else kh_tuan end,
      open_loai_su_co = 'C3 - Đổi khuôn',
      open_gio_phat_sinh = p_gio_bat_dau_doi_khuon,
      open_van_de = 'Đổi khuôn từ ' || coalesce(v_old.ma_sp, ''),
      open_noi_dung_xu_ly = 'Đang thực hiện đổi khuôn',
      open_dam_nhiem = coalesce(p_dam_nhiem, ''),
      open_id_su_co = v_id_su_co,
      sp_start_time = p_gio_bat_dau_doi_khuon,
      -- dòng chưa sản xuất gì: shot đầu lấy theo mã vừa chạy; đã có sản lượng thì giữ nguyên
      so_shot_dau_ca = case when coalesce(tt_ca, 0) = 0 and so_shot_cuoi_ca is null then v_carry_shot else so_shot_dau_ca end,
      version = coalesce(version, 0) + 1,
      last_updated_by = p_user,
      last_updated_at = v_now
    where id_dong = v_new_id_dong;
  else
    insert into duc_ca_hien_tai (
      id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, kh_ca, kh_tuan, tt_ca, tt_tuan,
      nv_ca_ngay, nv_ca_dem, open_loai_su_co, open_gio_phat_sinh, open_van_de, open_noi_dung_xu_ly, open_dam_nhiem, open_id_su_co,
      version, last_updated_by, last_updated_at, so_shot_nong_khuon, so_luong_ng, phan_loai_ng,
      sp_start_time, sp_end_time, so_shot_khuon_snapshot, so_shot_dau_ca, so_shot_cuoi_ca
    ) values (
      v_new_id_dong, v_old.ngay, v_old.ca, v_old.phuong_an_ca, duc_iso_week(v_old.ngay), v_old.ma_may, p_new_ma_sp, coalesce(p_new_ten_sp,''), coalesce(p_new_so_khuon,''),
      p_new_kh_ca, coalesce(p_new_kh_tuan,0), 0, 0, coalesce(v_old.nv_ca_ngay,''), coalesce(v_old.nv_ca_dem,''),
      'C3 - Đổi khuôn', p_gio_bat_dau_doi_khuon, 'Đổi khuôn từ ' || coalesce(v_old.ma_sp,''), 'Đang thực hiện đổi khuôn', coalesce(p_dam_nhiem,''), v_id_su_co,
      1, p_user, v_now, 0, 0, '', p_gio_bat_dau_doi_khuon, (v_win->>'end')::timestamptz, 0, v_carry_shot, null
    );
  end if;

  if p_new_so_khuon is not null and p_new_ma_sp is not null then perform duc_ensure_mold_product_mapping(p_new_so_khuon, p_new_ma_sp); end if;
  begin perform duc_request_ipqc_check(v_new_id_dong, 'doi_khuon', v_id_su_co, p_gio_bat_dau_doi_khuon); exception when others then null; end;

  return jsonb_build_object('ok', true, 'new_id_dong', v_new_id_dong, 'old_id_dong', p_old_id_dong, 'old_ma_sp', v_old.ma_sp, 'new_ma_sp', p_new_ma_sp, 'ma_may', v_old.ma_may, 'id_su_co', v_id_su_co, 'dung_lai_dong', v_reuse);
end;
$function$;
