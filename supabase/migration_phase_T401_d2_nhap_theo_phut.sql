-- T401: Sự cố D2 (Đào tạo / Người mới) nhập theo SỐ PHÚT bị ảnh hưởng do CT chậm — máy vẫn chạy,
-- không nhập giờ dừng từ…đến. Bản ghi "điểm": gio_phat_sinh = gio_tro_lai = lúc ghi, phút = số nhập.
--  • duc_tinh_phut_dung_may: bản ghi điểm đã tự lấy phut_dung_may = thoi_gian_dung_phut (không trừ chồng giờ).
--  • Tổng phút dừng ca (duc_end_shift) cộng phut_dung_may → có D2.
--  • Dừng không rõ (duc_dung_khong_ro_ca): cộng thêm phút D2 vào phút sự cố.
--  • OEE trong duc_end_shift giữ nguyên (CT chậm là tổn thất hiệu suất, đã phản ánh qua sản lượng).

-- 1. Cột đánh dấu
alter table public.duc_su_co_log add column if not exists nhap_theo_phut boolean not null default false;
alter table public.gc_su_co      add column if not exists nhap_theo_phut boolean not null default false;

-- 2. Đúc: ghi sự cố theo phút (đã xong ngay, máy không chuyển sang dừng)
create or replace function public.duc_su_co_theo_phut(
  p_id_dong text, p_loai text, p_phut int, p_van_de text, p_noi_dung_xu_ly text,
  p_dam_nhiem text, p_truong_ca text, p_user text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_c record; v_now timestamptz := now(); v_id text; v_sc text; v_nguoi text;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if left(upper(trim(coalesce(p_loai, ''))), 2) <> 'D2' then
    return jsonb_build_object('ok', false, 'error', 'Chỉ sự cố D2 được nhập theo số phút');
  end if;
  if p_phut is null or p_phut < 1 or p_phut > 720 then
    return jsonb_build_object('ok', false, 'error', 'Số phút ảnh hưởng phải từ 1 đến 720');
  end if;
  if coalesce(trim(p_van_de), '') = '' then return jsonb_build_object('ok', false, 'error', 'Nhập vấn đề'); end if;
  if coalesce(trim(p_noi_dung_xu_ly), '') = '' then return jsonb_build_object('ok', false, 'error', 'Nhập nội dung xử lý'); end if;
  if coalesce(trim(p_dam_nhiem), '') = '' then return jsonb_build_object('ok', false, 'error', 'Nhập người đảm nhiệm'); end if;

  select ngay, ca, ma_may, ma_sp, ten_sp, so_khuon into v_c from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng ca: ' || coalesce(p_id_dong, '')); end if;
  if coalesce(trim(v_c.ma_sp), '') = '' then return jsonb_build_object('ok', false, 'error', 'Máy chưa có mã sản phẩm'); end if;
  if exists (select 1 from duc_bao_cao_ca b where b.ngay = v_c.ngay and b.ca = v_c.ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca');
  end if;

  v_sc := duc_id_su_co_moi(v_c.ma_may, v_now);
  v_id := duc_next_id_ban_ghi(duc_make_id_dong(v_c.ngay, v_c.ca, v_c.ma_may, v_c.ma_sp));
  v_nguoi := coalesce(nullif(duc_su_co_nguoi_hien_tai(), ''), p_user, '');

  insert into duc_su_co_nhat_ky (id_su_co, su_kien, id_dong, ngay, ca, du_lieu, nguoi, nguoi_uid, nguon)
  values (v_sc, 'mo', p_id_dong, v_c.ngay, v_c.ca,
          jsonb_build_object('loai', trim(p_loai), 'van_de', trim(p_van_de), 'nhap_theo_phut', true, 'phut', p_phut),
          v_nguoi, auth.uid(), '/rpc/duc_su_co_theo_phut');

  insert into duc_su_co_log (
    id_ban_ghi, ngay, ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, loai_su_co,
    gio_phat_sinh, gio_tro_lai, thoi_gian_dung_phut, van_de, noi_dung_xu_ly,
    dam_nhiem, ghi_chu, truong_ca, thoi_diem_luu, van_de_edited, id_su_co, nhap_theo_phut
  ) values (
    v_id, v_c.ngay, v_c.ca, duc_iso_week(v_c.ngay), v_c.ma_may, v_c.ma_sp, v_c.ten_sp, v_c.so_khuon, trim(p_loai),
    v_now, v_now, p_phut, trim(p_van_de), trim(p_noi_dung_xu_ly),
    trim(p_dam_nhiem), '', coalesce(p_truong_ca, ''), v_now, 'No', v_sc, true
  );

  insert into duc_su_co_nhat_ky (id_su_co, su_kien, id_dong, ngay, ca, du_lieu, nguoi, nguoi_uid, nguon)
  values (v_sc, 'dong', p_id_dong, v_c.ngay, v_c.ca,
          jsonb_build_object('id_ban_ghi', v_id, 'nhap_theo_phut', true, 'phut', p_phut),
          v_nguoi, auth.uid(), '/rpc/duc_su_co_theo_phut');

  return jsonb_build_object('ok', true, 'id_ban_ghi', v_id, 'id_su_co', v_sc, 'thoi_gian_dung_phut', p_phut);
end $$;
revoke execute on function public.duc_su_co_theo_phut(text, text, int, text, text, text, text, text) from public, anon;
grant execute on function public.duc_su_co_theo_phut(text, text, int, text, text, text, text, text) to authenticated;

-- 3. Đúc: sửa số phút của bản ghi nhập theo phút (cùng quyền với duc_edit_incident)
create or replace function public.duc_su_co_sua_phut(p_id_ban_ghi text, p_phut int, p_user text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_row duc_su_co_log; v_audit text;
begin
  if auth.uid() is null or not public.has_role(VARIADIC ARRAY['admin', 'truong_ca', 'quan_ly_bo_phan', 'qlsx_truong_phong']) then
    raise exception '⛔ Tài khoản không có quyền thực hiện thao tác này — cần vai trò: %', 'Trưởng ca / QLBP / TP QLSX' using errcode = '42501';
  end if;
  select * into v_row from duc_su_co_log where id_ban_ghi = p_id_ban_ghi;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy bản ghi sự cố: ' || coalesce(p_id_ban_ghi, '')); end if;
  if not v_row.nhap_theo_phut then return jsonb_build_object('ok', false, 'error', 'Bản ghi này nhập theo giờ, không sửa số phút được'); end if;
  if p_phut is null or p_phut < 1 or p_phut > 720 then
    return jsonb_build_object('ok', false, 'error', 'Số phút ảnh hưởng phải từ 1 đến 720');
  end if;
  if not public.has_role('admin', 'quan_ly_bo_phan', 'qlsx_truong_phong')
     and exists (select 1 from duc_bao_cao_ca b where b.ngay = v_row.ngay and b.ca = v_row.ca) then
    raise exception '⛔ Ca của sự cố này đã chốt báo cáo — chỉ QLBP / Trưởng phòng QLSX / admin được sửa' using errcode = '42501';
  end if;
  if v_row.thoi_gian_dung_phut = p_phut then return jsonb_build_object('ok', true, 'id_ban_ghi', p_id_ban_ghi); end if;
  v_audit := '[edited ' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ' by '
          || coalesce(public.duc_ten_nguoi_hien_tai(p_user), 'unknown') || ']';
  update duc_su_co_log set thoi_gian_dung_phut = p_phut, van_de_edited = 'Yes',
         ghi_chu = case when coalesce(ghi_chu, '') = '' then v_audit else ghi_chu || E'\n' || v_audit end
   where id_ban_ghi = p_id_ban_ghi;
  return jsonb_build_object('ok', true, 'id_ban_ghi', p_id_ban_ghi);
end $$;
revoke execute on function public.duc_su_co_sua_phut(text, int, text) from public, anon;
grant execute on function public.duc_su_co_sua_phut(text, int, text) to authenticated;

-- 4. Bản ghi nhập theo phút: giữ nguyên giờ (sửa giờ qua duc_edit_incident không làm mất số phút)
create or replace function public.duc_su_co_log_theo_phut_trg()
returns trigger language plpgsql set search_path to 'public' as $$
begin
  if old.nhap_theo_phut then
    new.nhap_theo_phut := true;
    if new.gio_phat_sinh is distinct from old.gio_phat_sinh or new.gio_tro_lai is distinct from old.gio_tro_lai then
      new.gio_phat_sinh := old.gio_phat_sinh;
      new.gio_tro_lai := old.gio_tro_lai;
      new.thoi_gian_dung_phut := old.thoi_gian_dung_phut;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_a_duc_su_co_log_theo_phut on public.duc_su_co_log;
create trigger trg_a_duc_su_co_log_theo_phut before update on public.duc_su_co_log
  for each row execute function public.duc_su_co_log_theo_phut_trg();

-- 5. Dừng không rõ: cộng phút D2 nhập theo phút vào phút sự cố
do $$
declare v_def text; v_old text := '- v_br) x) phut_sc';
begin
  v_def := pg_get_functiondef('public.duc_dung_khong_ro_ca(date,text,text,timestamptz)'::regprocedure);
  if position('nhap_theo_phut' in v_def) > 0 then return; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'T401: không tìm thấy đúng 1 chỗ "%" trong duc_dung_khong_ro_ca', v_old;
  end if;
  v_def := replace(v_def, v_old, '- v_br) x)
      + coalesce((select sum(l.thoi_gian_dung_phut) from duc_su_co_log l
                   where l.ma_may = m.ma_may and l.ngay = p_ngay and l.ca = p_ca and l.nhap_theo_phut), 0) phut_sc');
  execute v_def;
end $$;

-- 6. Gia công: ghi lần dừng D2 theo phút (đã đóng ngay)
create or replace function public.gc_su_co_theo_phut(
  p_id_tram text, p_loai text, p_bo_phan text, p_phut int, p_van_de text, p_noi_dung text, p_dam_nhiem text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_tram cd_tram_hien_tai%rowtype; v_now timestamptz := now(); v_id bigint; v_nguoi text;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into v_tram from cd_tram_hien_tai where id_tram = p_id_tram and cong_doan = 'Gia Công';
  if not found then return jsonb_build_object('ok', false, 'error', 'Máy chưa được mở trong ca này'); end if;
  if gc_ca_da_ket(v_tram.ngay, v_tram.ca) then return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca'); end if;
  if left(upper(trim(coalesce(p_loai, ''))), 2) <> 'D2' then
    return jsonb_build_object('ok', false, 'error', 'Chỉ lý do D2 được nhập theo số phút');
  end if;
  if p_phut is null or p_phut < 1 or p_phut > 720 then
    return jsonb_build_object('ok', false, 'error', 'Số phút ảnh hưởng phải từ 1 đến 720');
  end if;
  if length(trim(coalesce(p_van_de, ''))) < 3 then return jsonb_build_object('ok', false, 'error', 'Ghi rõ vấn đề (ít nhất 3 ký tự)'); end if;
  if length(trim(coalesce(p_noi_dung, ''))) < 3 then return jsonb_build_object('ok', false, 'error', 'Ghi nội dung xử lý (ít nhất 3 ký tự)'); end if;
  if coalesce(trim(p_dam_nhiem), '') = '' then return jsonb_build_object('ok', false, 'error', 'Chọn / ghi người xử lý'); end if;
  v_nguoi := duc_su_co_nguoi_hien_tai();
  insert into gc_su_co (ma_may, id_tram, ngay, ca, ma_sp, loai_su_co, bo_phan_xu_ly, gio_phat_sinh, gio_tro_lai, phut_dung,
                        van_de, noi_dung_xu_ly, dam_nhiem, nguoi_bao, nguoi_dong, nhap_theo_phut)
  values (v_tram.ten_tram, v_tram.id_tram, v_tram.ngay, v_tram.ca, v_tram.ma_sp, trim(p_loai),
          nullif(trim(coalesce(p_bo_phan, '')), ''), v_now, v_now, p_phut,
          trim(p_van_de), trim(p_noi_dung), trim(p_dam_nhiem), v_nguoi, v_nguoi, true)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'phut_dung', p_phut);
end $$;
revoke execute on function public.gc_su_co_theo_phut(text, text, text, int, text, text, text) from public, anon;
grant execute on function public.gc_su_co_theo_phut(text, text, text, int, text, text, text) to authenticated;
