-- T368 (26/11/2026): Bavia GHÉP TEM — tem con cuối lấy phần lẻ của tem Đúc A + phần thiếu từ tem Đúc B (cùng Line, cùng mã).
--   * bavia_tach_tem thêm tham số p_id_bu (dòng khai báo tem bù). Chỉ tem cuối được ghép (phần thiếu < SL/tem).
--     Tem con mang số tem A (A-x). Phần A ghi duc_tem_tach, phần B ghi cd_tem_nguon (truy xuất đã đọc cả 2).
--     Lot NVL chép từ cả A và B.
--   * bavia_tach_tem_huy: trả SL về cả tem B.
--   * bavia_ng_theo_tem: phần A tính theo so_luong_con (không tính trùng phần B).
--   * duc_hoan_tac_tach_tem (màn In tem): chặn tem ghép (dùng Huỷ ở Bavia).

drop function if exists public.bavia_tach_tem(text, bigint, numeric, int);

create or replace function public.bavia_tach_tem(p_id_tram text, p_id bigint, p_sl numeric, p_so_tem int default 1, p_id_bu bigint default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_line cd_tram_hien_tai%rowtype;
  v_n bavia_line_nguon%rowtype;
  v_nb bavia_line_nguon%rowtype;
  v_me duc_tem%rowtype;
  v_bu duc_tem%rowtype;
  v_info jsonb;
  v_so int := coalesce(p_so_tem, 1);
  v_tong numeric;
  v_con_a numeric;
  v_can numeric := 0;
  v_lay_a numeric;
  v_lay_b numeric;
  v_dem int;
  v_con text;
  v_ds text[] := '{}';
  v_ghep text;
  v_user text := duc_su_co_nguoi_hien_tai();
  v_now timestamptz := now();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if p_sl is null or p_sl <= 0 or p_sl <> trunc(p_sl) then
    return jsonb_build_object('ok', false, 'error', 'SL mỗi tem phải là số nguyên > 0');
  end if;
  if v_so < 1 or v_so > 20 then return jsonb_build_object('ok', false, 'error', 'Số tem từ 1 đến 20'); end if;
  v_tong := p_sl * v_so;
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
  v_con_a := coalesce(v_me.so_luong, 0);

  if p_id_bu is null then
    if v_con_a < v_tong then
      return jsonb_build_object('ok', false, 'error', 'Tem ' || v_me.tag_no || ' chỉ còn ' || v_con_a
        || ' pcs, không đủ ' || v_so || ' × ' || p_sl);
    end if;
  else
    -- T368: ghép — tem cuối lấy phần thiếu từ tem bù
    if p_id_bu = p_id then return jsonb_build_object('ok', false, 'error', 'Chọn tem bù khác tem đang tách'); end if;
    select * into v_nb from bavia_line_nguon where id = p_id_bu and bo_luc is null for update;
    if not found or v_nb.ten_line <> v_line.ten_tram then
      return jsonb_build_object('ok', false, 'error', 'Tem bù không còn khai báo ở ' || v_line.ten_tram);
    end if;
    select * into v_bu from duc_tem where tag_no = v_nb.tag_no for update;
    if v_bu.tag_no = v_me.tag_no then return jsonb_build_object('ok', false, 'error', 'Chọn tem bù khác tem đang tách'); end if;
    if v_bu.ma_sp is distinct from v_line.ma_sp then
      return jsonb_build_object('ok', false, 'error', 'Tem bù ' || v_bu.tag_no || ' khác mã đang chạy');
    end if;
    if duc_tem_id_ncp_cach_ly(v_bu.tag_no) is not null then
      return jsonb_build_object('ok', false, 'error', 'Tem ' || v_bu.tag_no || ' đang bị cách ly theo phiếu NCP '
        || duc_tem_id_ncp_cach_ly(v_bu.tag_no) || '. Báo QC.');
    end if;
    if exists (select 1 from bavia_hang_test where tag_no = v_bu.tag_no and ket_thuc_luc is null) then
      return jsonb_build_object('ok', false, 'error', 'Tem ' || v_bu.tag_no || ' còn hàng đang test. Kết thúc test trước.');
    end if;
    v_can := v_tong - v_con_a;
    if v_can <= 0 then
      return jsonb_build_object('ok', false, 'error', 'Tem ' || v_me.tag_no || ' còn đủ ' || v_con_a || ' pcs, không cần bù');
    end if;
    if v_can >= p_sl then
      return jsonb_build_object('ok', false, 'error', 'Chỉ ghép tem cuối. Tem ' || v_me.tag_no || ' còn ' || v_con_a
        || ' pcs: tách tối đa ' || (floor(v_con_a / p_sl)::int + 1) || ' tem (tem cuối ghép)');
    end if;
    if coalesce(v_bu.so_luong, 0) < v_can then
      return jsonb_build_object('ok', false, 'error', 'Tem bù ' || v_bu.tag_no || ' chỉ còn ' || coalesce(v_bu.so_luong, 0)
        || ' pcs, cần ' || v_can);
    end if;
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

    v_lay_a := least(p_sl, v_con_a - (i - 1) * p_sl);
    v_lay_b := p_sl - v_lay_a;
    v_ghep := case when v_lay_b > 0
      then 'Ghép ở Bavia: ' || v_me.tag_no || ' ' || v_lay_a || ' + ' || v_bu.tag_no || ' ' || v_lay_b
      else 'Tách ở Bavia từ ' || v_me.tag_no end;

    insert into duc_tem (tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
      may_duc_chi_thi, ghi_chu, ngay_gio_in, ngay_gio_ghi_nhan, so_khuon_tt, so_luong_tt, may_tt,
      nguoi_tt, trang_thai, ghi_chu_sl)
    values (v_con, v_me.ten_sp, v_me.ma_sp, p_sl, v_me.ngay, v_me.lot, v_me.so_khuon, v_me.nguyen_lieu,
      v_me.may_duc_chi_thi, v_me.ghi_chu, v_now, coalesce(v_me.ngay_gio_ghi_nhan, v_me.ngay_gio_in), v_me.so_khuon_tt,
      null, v_me.may_tt, v_line.nguoi_thao_tac, 'Đã làm Bavia' /* T367 */,
      v_ghep || ' · ' || v_line.ten_tram || ' · ' || v_line.ca || ' ' || to_char(v_line.ngay, 'DD/MM'));
    update duc_tem set so_luong = so_luong - v_lay_a where tag_no = v_me.tag_no;
    insert into duc_tem_tach (tag_no_cha, tag_no_con, so_luong_con, ly_do, nguoi_thao_tac)
    values (v_me.tag_no, v_con, v_lay_a, 'Bavia tách tem ' || v_line.ten_tram || case when v_lay_b > 0 then ' (ghép)' else '' end, v_user);
    insert into duc_tem_nvl_lot (tag_no, nvl_tag_no, nguoi_gan)
    select v_con, nvl_tag_no, v_user from duc_tem_nvl_lot where tag_no = v_me.tag_no
    on conflict do nothing;
    if v_lay_b > 0 then
      update duc_tem set so_luong = so_luong - v_lay_b where tag_no = v_bu.tag_no;
      insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay) values (v_con, v_bu.tag_no, v_lay_b);
      insert into duc_tem_nvl_lot (tag_no, nvl_tag_no, nguoi_gan)
      select v_con, nvl_tag_no, v_user from duc_tem_nvl_lot where tag_no = v_bu.tag_no
      on conflict do nothing;
    end if;
    insert into bavia_thung (tag_tp, ten_line, id_tram, ngay, ca, ma_sp, so_luong, dang, nguoi_lam, nguoi_kiem, nguoi_ghi, nguoi_uid, nguoi_phun_bi, thoi_diem)
    values (v_con, v_line.ten_tram, v_line.id_tram, v_line.ngay, v_line.ca, v_line.ma_sp, p_sl, 3,
      v_line.nguoi_thao_tac, v_line.nguoi_kiem_tra, v_user, auth.uid(), v_line.nguoi_phun_bi, v_now);
    v_ds := v_ds || v_con;
  end loop;

  perform cd_tram_nhap_sanluong(v_line.id_tram, v_tong, 0, null, v_user);
  return jsonb_build_object('ok', true, 'tem_me', v_me.tag_no, 'tem_con', to_jsonb(v_ds), 'so_luong', p_sl,
    'con', v_con_a - (v_tong - v_can), 'tem_bu', v_bu.tag_no, 'lay_bu', v_can, 'buoc_sau', v_info->>'buoc_sau');
end $$;

revoke execute on function public.bavia_tach_tem(text, bigint, numeric, int, bigint) from public, anon;
grant execute on function public.bavia_tach_tem(text, bigint, numeric, int, bigint) to authenticated;

do $mig$
declare v_old text; v_new text;
begin
  -- Huỷ: trả phần ghép về tem bù
  v_old := pg_get_functiondef('public.bavia_tach_tem_huy(text, text)'::regprocedure);
  if position('T368' in v_old) = 0 then
    v_new := replace(v_old, '  delete from bavia_thung where tag_tp = v_tag;',
      E'  update duc_tem d set so_luong = coalesce(d.so_luong, 0) + n.so_luong_lay /* T368 */\n'
      || E'  from cd_tem_nguon n where n.tag_no_moi = v_tag and d.tag_no = n.tag_no_nguon;\n'
      || E'  delete from cd_tem_nguon where tag_no_moi = v_tag;\n'
      || '  delete from bavia_thung where tag_tp = v_tag;');
    if v_new = v_old then raise exception 'T368: không sửa được bavia_tach_tem_huy'; end if;
    execute v_new;
  end if;

  -- NG theo tem: phần tem mẹ A tính theo so_luong_con
  v_old := pg_get_functiondef('public.bavia_ng_theo_tem(date, date)'::regprocedure);
  if position('T368' in v_old) = 0 then
    v_new := replace(v_old, '/* T365 */, b.so_luong, b.ngay from bavia_thung b where b.dang = 3',
      '/* T365 */, coalesce((select x.so_luong_con from duc_tem_tach x where x.tag_no_con = b.tag_tp), b.so_luong) /* T368 */, b.ngay from bavia_thung b where b.dang = 3');
    if v_new = v_old then raise exception 'T368: không sửa được bavia_ng_theo_tem'; end if;
    execute v_new;
  end if;

  -- Hoàn tác tách ở màn In tem: chặn tem ghép
  v_old := pg_get_functiondef('public.duc_hoan_tac_tach_tem(text, text)'::regprocedure);
  if position('T368' in v_old) = 0 then
    v_new := replace(v_old, '    delete from duc_tem_tach where tag_no_con = p_tag_no_con;',
      E'    if exists (select 1 from cd_tem_nguon where tag_no_moi = p_tag_no_con) then /* T368 */\n'
      || E'      raise exception ''Tem % là tem ghép ở Bavia — huỷ ở Bảng điều khiển Bavia'', p_tag_no_con;\n'
      || E'    end if;\n'
      || '    delete from duc_tem_tach where tag_no_con = p_tag_no_con;');
    if v_new = v_old then raise exception 'T368: không sửa được duc_hoan_tac_tach_tem'; end if;
    execute v_new;
  end if;
end $mig$;
