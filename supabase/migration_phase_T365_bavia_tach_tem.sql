-- T365 (26/11/2026): Bavia TÁCH TEM thay cho "chuyển nguyên xe" (T338–T340).
--
--   * Bỏ chế độ Nguyên xe: công tắc bavia_nguyen_xe_gc = false (Bavia quay về quét tem thùng in sẵn);
--     UI bỏ nút Nguyên xe / Xong xe (Bavia) và nút Chia xe (Gia công).
--   * Sọt Đúc lớn (~1000 pcs): làm xong 1 xe con → bấm "Tách" ở tem Đúc đang làm, nhập SL/tem + số tem.
--     bavia_tach_tem tạo tem con <tem mẹ>-A, -B… (duc_tem_tach), trừ SL tem mẹ, tính sản lượng Bavia
--     (bavia_thung dang 3, tag_tp = tem con). Tem con quét ở Chuyển công đoạn sang bước sau.
--   * Tem con KHÔNG cộng sản lượng Đúc: so_luong_tt = null (duc_recompute_tt_ca / lịch sử tính theo so_luong_tt).
--   * bavia_tach_tem_huy: bấm nhầm → xoá tem con, trả SL về tem mẹ (khi tem con còn ở Bavia, chưa dùng).

-- 1) Tắt nguyên xe
update duc_cau_hinh set gia_tri = 'false'::jsonb, updated_at = now(), updated_by = 'T365'
where khoa = 'bavia_nguyen_xe_gc';

-- 2) Tách tem
create or replace function public.bavia_tach_tem(p_id_tram text, p_id bigint, p_sl numeric, p_so_tem int default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_line cd_tram_hien_tai%rowtype;
  v_n bavia_line_nguon%rowtype;
  v_me duc_tem%rowtype;
  v_info jsonb;
  v_so int := coalesce(p_so_tem, 1);
  v_dem int;
  v_con text;
  v_ds text[] := '{}';
  v_user text := duc_su_co_nguoi_hien_tai();
  v_now timestamptz := now();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if p_sl is null or p_sl <= 0 or p_sl <> trunc(p_sl) then
    return jsonb_build_object('ok', false, 'error', 'SL mỗi tem phải là số nguyên > 0');
  end if;
  if v_so < 1 or v_so > 20 then return jsonb_build_object('ok', false, 'error', 'Số tem từ 1 đến 20'); end if;
  select * into v_line from cd_tram_hien_tai where id_tram = p_id_tram and cong_doan = 'Bavia';
  if not found then return jsonb_build_object('ok', false, 'error', 'Line chưa được mở trong ca này'); end if;
  if bavia_loi_ca_khong_mo(v_line.ngay, v_line.ca) is not null then
    return jsonb_build_object('ok', false, 'error', bavia_loi_ca_khong_mo(v_line.ngay, v_line.ca));
  end if;
  if exists (select 1 from bavia_ket_ca where ngay = v_line.ngay and ca = v_line.ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không ghi thêm được');
  end if;
  if coalesce(v_line.nguoi_thao_tac, '') = '' then
    return jsonb_build_object('ok', false, 'error', v_line.ten_tram || ' chưa gán người thao tác');
  end if;
  if coalesce(v_line.nguoi_kiem_tra, '') = '' then
    return jsonb_build_object('ok', false, 'error', v_line.ten_tram || ' chưa có người kiểm tra. Trưởng ca chọn ở Line.');
  end if;
  v_info := bavia_thong_tin_ma(v_line.ma_sp);
  if not (v_info->>'ok')::boolean then return v_info; end if;
  if (v_info->>'dang')::int <> 2 then
    return jsonb_build_object('ok', false, 'error', 'Mã đóng gói xuất hàng không tách tem. Dùng Đóng thùng · In tem.');
  end if;

  select * into v_n from bavia_line_nguon where id = p_id and bo_luc is null for update;
  if not found or v_n.ten_line <> v_line.ten_tram then
    return jsonb_build_object('ok', false, 'error', 'Tem này không còn khai báo ở ' || v_line.ten_tram);
  end if;
  select * into v_me from duc_tem where tag_no = v_n.tag_no for update;
  if v_me.ma_sp is distinct from v_line.ma_sp then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_me.tag_no || ' khác mã đang chạy');
  end if;
  if duc_tem_id_ncp_cach_ly(v_me.tag_no) is not null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_me.tag_no || ' đang bị cách ly theo phiếu NCP '
      || duc_tem_id_ncp_cach_ly(v_me.tag_no) || '. Báo QC.');
  end if;
  if exists (select 1 from bavia_hang_test where tag_no = v_me.tag_no and ket_thuc_luc is null) then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_me.tag_no || ' còn hàng đang test. Kết thúc test trước.');
  end if;
  if coalesce(v_me.so_luong, 0) < p_sl * v_so then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_me.tag_no || ' chỉ còn ' || coalesce(v_me.so_luong, 0)
      || ' pcs, không đủ ' || v_so || ' × ' || p_sl);
  end if;

  select count(*) into v_dem from duc_tem_tach where tag_no_cha = v_me.tag_no;
  for i in 1..v_so loop
    loop
      if v_dem >= 26 then
        raise exception 'Tem % đã tách quá 26 tem con', v_me.tag_no;
      end if;
      v_con := v_me.tag_no || '-' || chr(65 + v_dem);
      v_dem := v_dem + 1;
      exit when not exists (select 1 from duc_tem where tag_no = v_con);
    end loop;

    insert into duc_tem (tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
      may_duc_chi_thi, ghi_chu, ngay_gio_in, ngay_gio_ghi_nhan, so_khuon_tt, so_luong_tt, may_tt,
      nguoi_tt, trang_thai, ghi_chu_sl)
    values (v_con, v_me.ten_sp, v_me.ma_sp, p_sl, v_me.ngay, v_me.lot, v_me.so_khuon, v_me.nguyen_lieu,
      v_me.may_duc_chi_thi, v_me.ghi_chu, v_now, coalesce(v_me.ngay_gio_ghi_nhan, v_me.ngay_gio_in), v_me.so_khuon_tt,
      null, v_me.may_tt, v_line.nguoi_thao_tac, v_me.trang_thai, 'Tách ở Bavia từ ' || v_me.tag_no);
    update duc_tem set so_luong = so_luong - p_sl where tag_no = v_me.tag_no;
    insert into duc_tem_tach (tag_no_cha, tag_no_con, so_luong_con, ly_do, nguoi_thao_tac)
    values (v_me.tag_no, v_con, p_sl, 'Bavia tách tem ' || v_line.ten_tram, v_user);
    insert into duc_tem_nvl_lot (tag_no, nvl_tag_no, nguoi_gan)
    select v_con, nvl_tag_no, v_user from duc_tem_nvl_lot where tag_no = v_me.tag_no;
    insert into bavia_thung (tag_tp, ten_line, id_tram, ngay, ca, ma_sp, so_luong, dang, nguoi_lam, nguoi_kiem, nguoi_ghi, nguoi_uid, nguoi_phun_bi, thoi_diem)
    values (v_con, v_line.ten_tram, v_line.id_tram, v_line.ngay, v_line.ca, v_line.ma_sp, p_sl, 3,
      v_line.nguoi_thao_tac, v_line.nguoi_kiem_tra, v_user, auth.uid(), v_line.nguoi_phun_bi, v_now);
    v_ds := v_ds || v_con;
  end loop;

  perform cd_tram_nhap_sanluong(v_line.id_tram, p_sl * v_so, 0, null, v_user);
  return jsonb_build_object('ok', true, 'tem_me', v_me.tag_no, 'tem_con', to_jsonb(v_ds), 'so_luong', p_sl,
    'con', coalesce(v_me.so_luong, 0) - p_sl * v_so, 'buoc_sau', v_info->>'buoc_sau');
end $$;

-- 3) Huỷ tách (bấm nhầm). Không phải tem con → huỷ Xong xe cũ (T338).
create or replace function public.bavia_tach_tem_huy(p_id_tram text, p_tag text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_tag text := upper(trim(coalesce(p_tag, '')));
  v_b bavia_thung%rowtype;
  v_t duc_tem_tach%rowtype;
  v_con duc_tem%rowtype;
  v_line cd_tram_hien_tai%rowtype;
  v_user text := duc_su_co_nguoi_hien_tai();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into v_t from duc_tem_tach where tag_no_con = v_tag;
  if not found then return bavia_xong_xe_huy(p_id_tram, v_tag); end if;
  select * into v_b from bavia_thung where tag_tp = v_tag and dang = 3 and id_tram = p_id_tram for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || v_tag || ' ở Line này'); end if;
  select * into v_line from cd_tram_hien_tai where id_tram = p_id_tram;
  if exists (select 1 from bavia_ket_ca where ngay = v_line.ngay and ca = v_line.ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không huỷ được');
  end if;
  select * into v_con from duc_tem where tag_no = v_tag for update;
  if exists (select 1 from cd_chuyen_cong_doan_log where tag_no = v_tag) then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tag || ' đã quét chuyển công đoạn, không huỷ được');
  end if;
  if coalesce(v_con.so_luong, 0) <> v_b.so_luong
     or exists (select 1 from cd_tem_nguon where tag_no_nguon = v_tag)
     or exists (select 1 from duc_tem_tach where tag_no_cha = v_tag)
     or exists (select 1 from gc_tem_buoc where tag_no = v_tag)
     or exists (select 1 from cd_ng_khai_bao where tag_no = v_tag) then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tag || ' đã được dùng, không huỷ được');
  end if;
  if duc_tem_id_ncp_cach_ly(v_tag) is not null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tag || ' đang bị cách ly, không huỷ được');
  end if;

  delete from bavia_thung where tag_tp = v_tag;
  delete from duc_tem_nvl_lot where tag_no = v_tag;
  delete from duc_tem_tach where tag_no_con = v_tag;
  delete from duc_tem where tag_no = v_tag;
  update duc_tem set so_luong = coalesce(so_luong, 0) + v_t.so_luong_con where tag_no = v_t.tag_no_cha;
  update cd_tram_hien_tai set so_luong_ok = greatest(0, so_luong_ok - v_b.so_luong), version = version + 1,
    last_updated_by = v_user, last_updated_at = now()
  where id_tram = p_id_tram;
  return jsonb_build_object('ok', true, 'tag_no', v_tag, 'tem_me', v_t.tag_no_cha, 'so_luong', v_b.so_luong);
end $$;

revoke execute on function public.bavia_tach_tem(text, bigint, numeric, int) from public, anon;
revoke execute on function public.bavia_tach_tem_huy(text, text) from public, anon;
grant execute on function public.bavia_tach_tem(text, bigint, numeric, int) to authenticated;
grant execute on function public.bavia_tach_tem_huy(text, text) to authenticated;

-- 4) Sửa hàm cũ bằng replace() (có kiểm tra)
do $mig$
declare v_old text; v_new text;
begin
  -- 4a) bavia_quet: tem con đã làm xong ở Bavia không khai báo làm nguồn
  v_old := pg_get_functiondef('public.bavia_quet(text, text)'::regprocedure);
  if position('T365' in v_old) = 0 then
    v_new := replace(v_old, E'  select ten_line into v_line_khac from bavia_line_nguon',
      E'  if exists (select 1 from bavia_thung where tag_tp = v_tem.tag_no and dang = 3) then -- T365\n'
      || E'    return jsonb_build_object(''ok'', false, ''error'', ''Tem '' || v_tem.tag_no || '' đã làm xong ở Bavia. Quét ở Chuyển công đoạn sang bước sau.'');\n'
      || E'  end if;\n'
      || E'  select ten_line into v_line_khac from bavia_line_nguon');
    if v_new = v_old then raise exception 'T365: không sửa được bavia_quet'; end if;
    execute v_new;
  end if;

  -- 4b) bavia_du_lieu: nguồn của tem con = tem mẹ; tem đã xong (dang 3) không hiện ở "chờ"
  v_old := pg_get_functiondef('public.bavia_du_lieu(date, text)'::regprocedure);
  if position('T365' in v_old) = 0 then
    v_new := replace(v_old,
      E'from cd_tem_nguon s where s.tag_no_moi = b.tag_tp)',
      E'from (select tag_no_nguon, so_luong_lay from cd_tem_nguon where tag_no_moi = b.tag_tp\n'
      || E'                              union all select tag_no_cha, so_luong_con from duc_tem_tach where tag_no_con = b.tag_tp) s) /* T365 */');
    v_new := replace(v_new,
      E'and not exists (select 1 from bavia_line_nguon n where n.tag_no = t.tag_no and n.bo_luc is null)',
      E'and not exists (select 1 from bavia_line_nguon n where n.tag_no = t.tag_no and n.bo_luc is null)\n'
      || E'          and not exists (select 1 from bavia_thung b3 where b3.tag_tp = t.tag_no and b3.dang = 3)');
    if position('T365' in v_new) = 0 or position('b3.dang = 3' in v_new) = 0 then
      raise exception 'T365: không sửa được bavia_du_lieu';
    end if;
    execute v_new;
  end if;

  -- 4c) bavia_ng_theo_tem: OK của tem con tính về tem mẹ
  v_old := pg_get_functiondef('public.bavia_ng_theo_tem(date, date)'::regprocedure);
  if position('T365' in v_old) = 0 then
    v_new := replace(v_old,
      E'select b.tag_tp, b.so_luong, b.ngay from bavia_thung b where b.dang = 3',
      E'select coalesce((select x.tag_no_cha from duc_tem_tach x where x.tag_no_con = b.tag_tp), b.tag_tp) /* T365 */, b.so_luong, b.ngay from bavia_thung b where b.dang = 3');
    if v_new = v_old then raise exception 'T365: không sửa được bavia_ng_theo_tem'; end if;
    execute v_new;
  end if;

  -- 4d) Thông báo không còn nói "Chia xe"
  v_old := pg_get_functiondef('public.cd_kiem_xe_bavia(text, numeric)'::regprocedure);
  if position('T365' in v_old) = 0 then
    v_new := replace(v_old,
      E'phải gia công xong rồi chia thùng ở Bảng điều khiển Gia công (nút Chia xe), không chuyển nguyên xe.''',
      E'phải gia công ở Bảng điều khiển Gia công, đầy thùng quét tem GC vào ô QR máy. Không chuyển nguyên xe.'' /* T365 */');
    if v_new = v_old then raise exception 'T365: không sửa được cd_kiem_xe_bavia'; end if;
    execute v_new;
  end if;

  v_old := pg_get_functiondef('public.cd_ghi_nhan_tem_thanh_pham(text, text, text)'::regprocedure);
  if position('T365' in v_old) = 0 then
    v_new := replace(v_old,
      E'là tem thùng Gia Công — quét ở Chia xe trên Bảng điều khiển Gia công''',
      E'là tem thùng Gia Công — đầy thùng quét vào ô QR máy trên Bảng điều khiển Gia công'' /* T365 */');
    if v_new = v_old then raise exception 'T365: không sửa được cd_ghi_nhan_tem_thanh_pham'; end if;
    execute v_new;
  end if;
end $mig$;
