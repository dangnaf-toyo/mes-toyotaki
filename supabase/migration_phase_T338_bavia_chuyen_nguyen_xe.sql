-- T338 (23/11/2026): Bavia → Gia công CHUYỂN NGUYÊN XE (tạm thời, chưa đủ thùng nhựa quay vòng).
--
-- Khi công tắc BẬT (duc_cau_hinh khoa = 'bavia_nguyen_xe_gc'), với các mã có bước sau Bavia là "Gia Công":
--   * Bavia KHÔNG quét tem thùng in sẵn nữa. Làm xong cả xe → bấm "Xong xe" trên tem Đúc của xe:
--     sản lượng Bavia = số còn trên tem Đúc (đã trừ NG), tem Đúc chuyển thẳng sang Gia Công (bavia_xong_xe).
--     bavia_thung ghi 1 dòng dang = 3 (xe), tag_tp = tem Đúc.
--   * Gia công bấm "Chia xe": quét tem xe rồi quét từng tem thùng QLSX in sẵn (tem TP Bavia) — mỗi tem
--     trừ đúng SL từ xe (gc_chia_xe). Tem cuối thiếu → hỏi ghi thùng lẻ.
--   * Máy Gia công không nhận tem xe chưa chia (gc_quet).
-- Công tắc TẮT → quay lại cách cũ (Bavia quét tem thùng in sẵn). Xe đã chuyển trước đó vẫn chia được.
-- Các hàm cũ sửa bằng replace() trên định nghĩa đang chạy (có kiểm tra đã thay được).

-- 1) Công tắc
insert into duc_cau_hinh (khoa, gia_tri, ghi_chu, updated_at, updated_by)
values ('bavia_nguyen_xe_gc', 'true'::jsonb,
  'T338: Bavia → Gia công chuyển nguyên xe; chia thùng + dán tem in sẵn tại Gia công', now(), 'T338')
on conflict (khoa) do nothing;

create or replace function public.bavia_nguyen_xe()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select (gia_tri #>> '{}')::boolean from duc_cau_hinh where khoa = 'bavia_nguyen_xe_gc'), false);
$$;

create or replace function public.bavia_nguyen_xe_dat(p_bat boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role text;
  v_user text := duc_su_co_nguoi_hien_tai();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select role into v_role from user_roles where user_id = auth.uid();
  if coalesce(v_role, '') not in ('admin', 'quan_ly_bo_phan', 'qlsx_truong_phong') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ admin / quản lý được đổi');
  end if;
  insert into duc_cau_hinh (khoa, gia_tri, ghi_chu, updated_at, updated_by)
  values ('bavia_nguyen_xe_gc', to_jsonb(coalesce(p_bat, false)),
    'T338: Bavia → Gia công chuyển nguyên xe; chia thùng + dán tem in sẵn tại Gia công', now(), v_user)
  on conflict (khoa) do update set gia_tri = excluded.gia_tri, updated_at = now(), updated_by = v_user;
  return jsonb_build_object('ok', true, 'bat', coalesce(p_bat, false));
end $$;

-- 2) bavia_thung: thêm dạng 3 = xe chuyển nguyên
alter table bavia_thung drop constraint if exists bavia_thung_dang_check;
alter table bavia_thung add constraint bavia_thung_dang_check check (dang = any (array[1, 2, 3]));

-- 3) Sửa hàm cũ bằng replace()
do $mig$
declare v_old text; v_new text;
begin
  -- 3a) bavia_thong_tin_ma: trả thêm nguyen_xe
  v_old := pg_get_functiondef('public.bavia_thong_tin_ma(text)'::regprocedure);
  if position('''nguyen_xe''' in v_old) = 0 then
    v_new := replace(v_old, E'    ''dang'', case when',
      E'    ''nguyen_xe'', (v_sau = ''Gia Công'' and bavia_nguyen_xe()),\n    ''dang'', case when');
    if v_new = v_old then raise exception 'T338: không sửa được bavia_thong_tin_ma'; end if;
    execute v_new;
  end if;

  -- 3b) bavia_quet: chế độ nguyên xe → không nhận tem thùng in sẵn ở Bavia
  v_old := pg_get_functiondef('public.bavia_quet(text, text)'::regprocedure);
  if position('T338' in v_old) = 0 then
    v_new := replace(v_old, E'    if v_tem.trang_thai = ''Đã đóng gói TP'' then',
      E'    if coalesce((v_info->>''nguyen_xe'')::boolean, false) then -- T338\n'
      || E'      return jsonb_build_object(''ok'', false, ''error'',\n'
      || E'        ''Đang chuyển nguyên xe sang Gia công: không quét tem thùng ở Bavia. Làm xong xe bấm "Xong xe" ở tem Đúc. Tem thùng mang xuống Gia công.'');\n'
      || E'    end if;\n'
      || E'    if v_tem.trang_thai = ''Đã đóng gói TP'' then');
    if v_new = v_old then raise exception 'T338: không sửa được bavia_quet'; end if;
    execute v_new;
  end if;

  -- 3c) gc_quet: không nhận tem xe chưa chia
  v_old := pg_get_functiondef('public.gc_quet(text, text)'::regprocedure);
  if position('T338' in v_old) = 0 then
    v_new := replace(v_old, E'  select ma_may into v_khac from gc_tem_buoc',
      E'  if v_tem.tag_no not like ''TP%'' and exists (select 1 from bavia_thung where tag_tp = v_tem.tag_no and dang = 3) then -- T338\n'
      || E'    return jsonb_build_object(''ok'', false, ''error'', ''Tem '' || v_tem.tag_no || '' là tem xe Bavia, chưa chia thùng. Bấm "Chia xe" ở đầu trang.'');\n'
      || E'  end if;\n'
      || E'  select ma_may into v_khac from gc_tem_buoc');
    if v_new = v_old then raise exception 'T338: không sửa được gc_quet'; end if;
    execute v_new;
  end if;

  -- 3d) bavia_ng_theo_tem: OK của tem Đúc tính cả xe chuyển nguyên
  v_old := pg_get_functiondef('public.bavia_ng_theo_tem(date, date)'::regprocedure);
  if position('T338' in v_old) = 0 then
    v_new := replace(v_old,
      E'    select n.tag_no_nguon tag, sum(n.so_luong_lay) ok, max(b.ngay) d\n    from cd_tem_nguon n join bavia_thung b on b.tag_tp = n.tag_no_moi\n    where b.ngay between p_tu and p_den\n    group by 1',
      E'    select tag, sum(ok) ok, max(d) d from ( -- T338: + xe chuyển nguyên (dang 3)\n'
      || E'      select n.tag_no_nguon tag, n.so_luong_lay ok, b.ngay d\n'
      || E'      from cd_tem_nguon n join bavia_thung b on b.tag_tp = n.tag_no_moi\n'
      || E'      where b.ngay between p_tu and p_den\n'
      || E'      union all\n'
      || E'      select b.tag_tp, b.so_luong, b.ngay from bavia_thung b where b.dang = 3 and b.ngay between p_tu and p_den\n'
      || E'    ) z\n    group by 1');
    if v_new = v_old then raise exception 'T338: không sửa được bavia_ng_theo_tem'; end if;
    execute v_new;
  end if;
end $mig$;

-- 4) Bavia: Xong xe
create or replace function public.bavia_xong_xe(p_id_tram text, p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_line cd_tram_hien_tai%rowtype;
  v_n bavia_line_nguon%rowtype;
  v_tem duc_tem%rowtype;
  v_info jsonb;
  v_sl numeric;
  v_user text := duc_su_co_nguoi_hien_tai();
  v_now timestamptz := now();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
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
  if not coalesce((v_info->>'nguyen_xe')::boolean, false) then
    return jsonb_build_object('ok', false, 'error', 'Chế độ chuyển nguyên xe đang tắt. Quét tem thùng in sẵn như cũ.');
  end if;

  select * into v_n from bavia_line_nguon where id = p_id and bo_luc is null for update;
  if not found or v_n.ten_line <> v_line.ten_tram then
    return jsonb_build_object('ok', false, 'error', 'Tem này không còn khai báo ở ' || v_line.ten_tram);
  end if;
  select * into v_tem from duc_tem where tag_no = v_n.tag_no for update;
  if v_tem.ma_sp is distinct from v_line.ma_sp then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' khác mã đang chạy');
  end if;
  if duc_tem_id_ncp_cach_ly(v_tem.tag_no) is not null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang bị cách ly theo phiếu NCP '
      || duc_tem_id_ncp_cach_ly(v_tem.tag_no) || '. Báo QC.');
  end if;
  if exists (select 1 from bavia_hang_test where tag_no = v_tem.tag_no and ket_thuc_luc is null) then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' còn hàng đang test. Kết thúc test trước.');
  end if;
  if exists (select 1 from bavia_thung where tag_tp = v_tem.tag_no) then
    return jsonb_build_object('ok', false, 'error', 'Xe ' || v_tem.tag_no || ' đã bấm Xong xe trước đó');
  end if;
  v_sl := coalesce(v_tem.so_luong, 0);
  if v_sl <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' không còn hàng OK');
  end if;

  update bavia_line_nguon set bo_luc = v_now, bo_boi = v_user || ' · xong xe' where id = v_n.id;
  insert into bavia_thung (tag_tp, ten_line, id_tram, ngay, ca, ma_sp, so_luong, dang, nguoi_lam, nguoi_kiem, nguoi_ghi, nguoi_uid, nguoi_phun_bi, thoi_diem)
  values (v_tem.tag_no, v_line.ten_tram, v_line.id_tram, v_line.ngay, v_line.ca, v_line.ma_sp, v_sl, 3,
    v_line.nguoi_thao_tac, v_line.nguoi_kiem_tra, v_user, auth.uid(), v_line.nguoi_phun_bi, v_now);
  insert into cd_chuyen_cong_doan_log (id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
    lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan, nguoi_giao, nguoi_nhan,
    trang_thai_xac_nhan, ngay_gio_xac_nhan, ghi_chu)
  values (cd_next_transfer_id(), v_now, v_tem.tag_no, v_tem.ma_sp, v_tem.ten_sp, v_sl, v_sl, 0,
    coalesce(v_tem.lot, ''), coalesce(v_tem.so_khuon_tt, v_tem.so_khuon, ''), coalesce(v_tem.nguyen_lieu, ''),
    coalesce(v_tem.may_tt, v_tem.may_duc_chi_thi, ''), coalesce(v_tem.ngay::text, ''),
    'Bavia', 'Gia Công', v_user, 'Gia Công (chờ chia xe)', 'Đã xác nhận chuyển công đoạn',
    to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI:SS DD/MM/YYYY'), 'T338 Bavia chuyển nguyên xe ' || v_line.ten_tram);
  perform cd_tram_nhap_sanluong(v_line.id_tram, v_sl, 0, null, v_user);
  return jsonb_build_object('ok', true, 'tag_no', v_tem.tag_no, 'so_luong', v_sl, 'buoc_sau', v_info->>'buoc_sau');
end $$;

-- 5) Bavia: huỷ Xong xe (bấm nhầm) — chỉ khi Gia công chưa chia / chưa quét xe
create or replace function public.bavia_xong_xe_huy(p_id_tram text, p_tag text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_b bavia_thung%rowtype;
  v_line cd_tram_hien_tai%rowtype;
  v_tem duc_tem%rowtype;
  v_log record;
  v_nid bigint;
  v_user text := duc_su_co_nguoi_hien_tai();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into v_b from bavia_thung where tag_tp = upper(trim(p_tag)) and dang = 3 and id_tram = p_id_tram for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy xe ' || coalesce(p_tag, '') || ' ở Line này'); end if;
  select * into v_line from cd_tram_hien_tai where id_tram = p_id_tram;
  if exists (select 1 from bavia_ket_ca where ngay = v_line.ngay and ca = v_line.ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không huỷ được');
  end if;
  select * into v_tem from duc_tem where tag_no = v_b.tag_tp for update;
  if coalesce(v_tem.so_luong, 0) <> v_b.so_luong
     or exists (select 1 from cd_tem_nguon where tag_no_nguon = v_b.tag_tp and tag_no_moi like 'TP%'
                  and tag_no_moi in (select tag_no from cd_chuyen_cong_doan_log where ghi_chu = 'T338 Chia xe ' || v_b.tag_tp))
     or exists (select 1 from gc_tem_buoc where tag_no = v_b.tag_tp and bo_luc is null) then
    return jsonb_build_object('ok', false, 'error', 'Gia công đã chia / dùng xe ' || v_b.tag_tp || ', không huỷ được');
  end if;
  select id_phieu, cong_doan_nhan, ghi_chu into v_log from cd_chuyen_cong_doan_log
  where tag_no = v_b.tag_tp order by thoi_gian_chuyen desc limit 1;
  if v_log.cong_doan_nhan is distinct from 'Gia Công' or coalesce(v_log.ghi_chu, '') not like 'T338 Bavia chuyển nguyên xe%' then
    return jsonb_build_object('ok', false, 'error', 'Xe ' || v_b.tag_tp || ' đã chuyển tiếp, không huỷ được');
  end if;
  if exists (select 1 from bavia_line_nguon where tag_no = v_b.tag_tp and bo_luc is null) then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_b.tag_tp || ' đang khai báo ở Line khác');
  end if;

  delete from cd_chuyen_cong_doan_log where id_phieu = v_log.id_phieu and tag_no = v_b.tag_tp;
  delete from bavia_thung where tag_tp = v_b.tag_tp;
  select id into v_nid from bavia_line_nguon
  where tag_no = v_b.tag_tp and ten_line = v_b.ten_line and bo_boi like '% · xong xe' order by bo_luc desc limit 1;
  update bavia_line_nguon set bo_luc = null, bo_boi = null where id = v_nid;
  update cd_tram_hien_tai set so_luong_ok = greatest(0, so_luong_ok - v_b.so_luong), version = version + 1,
    last_updated_by = v_user, last_updated_at = now()
  where id_tram = p_id_tram;
  return jsonb_build_object('ok', true, 'tag_no', v_b.tag_tp, 'so_luong', v_b.so_luong);
end $$;

-- 6) Gia công: Chia xe. p_tag_thung null = chỉ xem thông tin xe.
create or replace function public.gc_chia_xe(p_tag_xe text, p_tag_thung text default null, p_cho_le boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_xe duc_tem%rowtype;
  v_th duc_tem%rowtype;
  v_b bavia_thung%rowtype;
  v_loc text;
  v_sl numeric;
  v_da jsonb;
  v_tag text := upper(trim(coalesce(p_tag_xe, '')));
  v_tt text := upper(trim(coalesce(p_tag_thung, '')));
  v_user text := duc_su_co_nguoi_hien_tai();
  v_now timestamptz := now();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if v_tag = '' then return jsonb_build_object('ok', false, 'error', 'Chưa quét tem xe'); end if;
  if v_tag like 'TP%' then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tag || ' là tem thùng. Quét tem xe (tem Đúc) trước.');
  end if;
  select * into v_xe from duc_tem where tag_no = v_tag for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || v_tag); end if;
  select * into v_b from bavia_thung where tag_tp = v_tag and dang = 3;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tag || ' không phải xe Bavia chuyển nguyên');
  end if;
  if duc_tem_id_ncp_cach_ly(v_tag) is not null then
    return jsonb_build_object('ok', false, 'error', 'Xe ' || v_tag || ' đang bị cách ly theo phiếu NCP ' || duc_tem_id_ncp_cach_ly(v_tag) || '. Báo QC.');
  end if;
  select cong_doan_nhan into v_loc from cd_chuyen_cong_doan_log
  where tag_no = v_tag and coalesce(trang_thai_xac_nhan, '') <> 'Đã từ chối' order by thoi_gian_chuyen desc limit 1;
  if v_loc is distinct from 'Gia Công' then
    return jsonb_build_object('ok', false, 'error', 'Xe ' || v_tag || ' đang ở công đoạn ' || coalesce(v_loc, '?') || ', không phải Gia Công');
  end if;
  if exists (select 1 from gc_tem_buoc where tag_no = v_tag and bo_luc is null) then
    return jsonb_build_object('ok', false, 'error', 'Xe ' || v_tag || ' đã quét vào máy Gia công');
  end if;

  if v_tt <> '' then
    if coalesce(v_xe.so_luong, 0) <= 0 then
      return jsonb_build_object('ok', false, 'error', 'Xe ' || v_tag || ' đã chia hết');
    end if;
    if v_tt not like 'TP%' then
      return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tt || ' không phải tem thùng in sẵn');
    end if;
    select * into v_th from duc_tem where tag_no = v_tt for update;
    if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || v_tt); end if;
    if v_th.ma_sp is distinct from v_xe.ma_sp then
      return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tt || ' là mã ' || coalesce(v_th.ma_sp, '?') || ', xe là mã ' || v_xe.ma_sp);
    end if;
    if v_th.trang_thai = 'Đã đóng gói TP' then
      return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tt || ' đã dùng lúc '
        || coalesce(to_char(v_th.ngay_gio_ghi_nhan at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'), '?'));
    end if;
    if v_th.trang_thai <> 'Chờ đóng gói TP' or coalesce(v_th.tram_cong_doan, '') <> 'Bavia' then
      return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tt || ' không phải tem thùng Bavia in sẵn (hoặc đã huỷ)');
    end if;
    v_sl := v_th.so_luong;
    if v_xe.so_luong < v_sl then
      if not coalesce(p_cho_le, false) then
        return jsonb_build_object('ok', false, 'le', true, 'con', v_xe.so_luong, 'sl_tem', v_sl,
          'error', 'Xe còn ' || v_xe.so_luong || ' pcs, ít hơn SL tem ' || v_sl);
      end if;
      v_sl := v_xe.so_luong;
    end if;

    update duc_tem set so_luong = so_luong - v_sl where tag_no = v_tag;
    insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay) values (v_tt, v_tag, v_sl)
      on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
    update duc_tem set so_luong = v_sl, so_luong_tt = v_sl, nguoi_tt = v_b.nguoi_kiem, trang_thai = 'Đã đóng gói TP',
      ghi_chu_sl = 'Chia xe ' || v_tag || ' tại Gia công', ngay_gio_ghi_nhan = v_now, ngay_gio_xuat = v_now,
      thoi_diem_san_xuat = v_b.thoi_diem
    where tag_no = v_tt;
    perform bavia_dien_thong_tin_nguon(v_tt);
    insert into cd_chuyen_cong_doan_log (id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
      lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan, nguoi_giao, nguoi_nhan,
      trang_thai_xac_nhan, ngay_gio_xac_nhan, ghi_chu)
    values (cd_next_transfer_id(), v_now, v_tt, v_xe.ma_sp, v_xe.ten_sp, v_sl, v_sl, 0,
      coalesce(v_xe.lot, ''), coalesce(v_xe.so_khuon_tt, v_xe.so_khuon, ''), coalesce(v_xe.nguyen_lieu, ''),
      coalesce(v_xe.may_tt, v_xe.may_duc_chi_thi, ''), coalesce(v_xe.ngay::text, ''),
      'Bavia', 'Gia Công', v_user, v_user, 'Đã xác nhận chuyển công đoạn',
      to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI:SS DD/MM/YYYY'), 'T338 Chia xe ' || v_tag);
    select * into v_xe from duc_tem where tag_no = v_tag;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('tag_no', n.tag_no_moi, 'so_luong', n.so_luong_lay) order by t.ngay_gio_ghi_nhan desc), '[]'::jsonb)
  into v_da
  from cd_tem_nguon n join duc_tem t on t.tag_no = n.tag_no_moi
  where n.tag_no_nguon = v_tag and n.tag_no_moi like 'TP%'
    and exists (select 1 from cd_chuyen_cong_doan_log g where g.tag_no = n.tag_no_moi and g.ghi_chu = 'T338 Chia xe ' || v_tag);
  return jsonb_build_object('ok', true, 'xe', v_tag, 'ma_sp', v_xe.ma_sp, 'ten_sp', v_xe.ten_sp, 'con', v_xe.so_luong,
    'sl_xe', v_b.so_luong, 'line', v_b.ten_line, 'thung', v_da,
    'tag_no', nullif(v_tt, ''), 'so_luong', v_sl);
end $$;

revoke execute on function public.bavia_nguyen_xe() from public, anon;
revoke execute on function public.bavia_nguyen_xe_dat(boolean) from public, anon;
revoke execute on function public.bavia_xong_xe(text, bigint) from public, anon;
revoke execute on function public.bavia_xong_xe_huy(text, text) from public, anon;
revoke execute on function public.gc_chia_xe(text, text, boolean) from public, anon;
grant execute on function public.bavia_nguyen_xe() to authenticated;
grant execute on function public.bavia_nguyen_xe_dat(boolean) to authenticated;
grant execute on function public.bavia_xong_xe(text, bigint) to authenticated;
grant execute on function public.bavia_xong_xe_huy(text, text) to authenticated;
grant execute on function public.gc_chia_xe(text, text, boolean) to authenticated;
