-- T343 (24/11/2026): Gia công ĐÓNG THÙNG NGAY TRONG LÚC LÀM XE (thay "làm xong cả xe rồi chia" của T340).
--   * Quét tem xe (TKD) vào ô QR máy như cũ.
--   * Đầy 1 thùng → quét tem GC (QLSX in sẵn) vào CÙNG ô QR: gc_quet tự chuyển sang gc_dong_thung.
--     Lấy đúng SL/thùng Gia Công, FIFO theo giờ quét xe: xe đang làm ở máy này (bước cuối)
--     + hàng lẻ của xe đã Xong bước cuối còn ở Gia Công (tiếp ca sau). Hết xe trước → lấy tiếp xe sau.
--     Chưa đủ 1 thùng → báo, không đóng.
--   * Mã nhiều bước: chỉ nhận ở bước cuối.
--   * Xong: SL ra = còn trên tem + đã đóng thùng (sl_dong). Phần lẻ để đóng cùng xe sau.
--   * Nút Dừng (gc_dung_xe): bất thường không làm tiếp xe → bắt buộc lý do; phần đã đóng thùng tính sản lượng;
--     phần còn lại ở trên tem xe, quét lại vào máy để làm tiếp.
--   * Bỏ (quét nhầm) bị chặn khi xe đã đóng thùng.

alter table public.gc_tem_buoc add column if not exists sl_dong numeric not null default 0;
alter table public.gc_tem_buoc add column if not exists so_thung int not null default 0;
alter table public.gc_tem_buoc add column if not exists ly_do_dung text;

-- 1) Đóng 1 thùng
create or replace function public.gc_dong_thung(p_id_tram text, p_tag_thung text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_tram cd_tram_hien_tai%rowtype; v_th duc_tem%rowtype; v_xe duc_tem%rowtype; v_b bavia_thung%rowtype;
  v_tt text := upper(trim(coalesce(p_tag_thung, '')));
  v_slt numeric; v_can numeric; v_lay numeric; v_co numeric := 0; c record; v_dau text; v_tu jsonb := '[]'::jsonb;
  v_con_xe numeric; v_user text := duc_su_co_nguoi_hien_tai(); v_now timestamptz := now();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into v_tram from cd_tram_hien_tai where id_tram = p_id_tram and cong_doan = 'Gia Công';
  if not found then return jsonb_build_object('ok', false, 'error', 'Máy chưa được mở trong ca này'); end if;
  if gc_ca_da_ket(v_tram.ngay, v_tram.ca) then return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không ghi thêm được'); end if;
  select * into v_th from duc_tem where tag_no = v_tt for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || v_tt); end if;
  if v_th.trang_thai = 'Đã đóng gói TP' then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tt || ' đã dùng lúc '
      || coalesce(to_char(v_th.ngay_gio_ghi_nhan at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'), '?'));
  end if;
  if coalesce(v_th.trang_thai, '') <> 'Chờ đóng gói TP' or coalesce(v_th.tram_cong_doan, '') not in ('Bavia', 'Gia Công') then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tt || ' không phải tem thùng in sẵn (hoặc đã huỷ)');
  end if;
  if v_th.ma_sp is distinct from v_tram.ma_sp then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tt || ' là mã ' || coalesce(v_th.ma_sp, '?') || ', ' || v_tram.ten_tram || ' đang chạy mã ' || v_tram.ma_sp);
  end if;
  v_slt := gc_sl_thung(v_th.ma_sp);
  if v_slt is null or v_slt <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Mã ' || v_th.ma_sp || ' chưa khai SL/thùng Gia Công. Khai ở Danh mục mã SP rồi quét lại.');
  end if;

  -- Hàng sẵn có, FIFO theo giờ quét xe
  for c in
    select g.id, g.tag_no, g.xong_luc, d.so_luong
    from gc_tem_buoc g join duc_tem d on d.tag_no = g.tag_no
    where g.ma_sp = v_th.ma_sp and g.bo_luc is null and g.buoc >= g.tong_buoc
      and g.tag_no !~ '^(TP|GC)' and coalesce(d.so_luong, 0) > 0
      and ((g.xong_luc is null and g.ma_may = v_tram.ten_tram)
        or (g.xong_luc is not null and cd_vi_tri_tem(g.tag_no) = 'Gia Công'
            and not exists (select 1 from gc_tem_buoc u where u.tag_no = g.tag_no and u.bo_luc is null and u.xong_luc is null)))
      and duc_tem_id_ncp_cach_ly(g.tag_no) is null
    order by g.bat_dau, g.id
  loop
    v_co := v_co + c.so_luong;
  end loop;
  if v_co < v_slt then
    return jsonb_build_object('ok', false, 'error', 'Chưa đủ 1 thùng: còn ' || v_co || ' pcs, cần ' || v_slt || '. Đầy thùng rồi quét tem ' || v_tt || '.');
  end if;

  v_can := v_slt;
  for c in
    select g.id, g.tag_no, g.xong_luc
    from gc_tem_buoc g join duc_tem d on d.tag_no = g.tag_no
    where g.ma_sp = v_th.ma_sp and g.bo_luc is null and g.buoc >= g.tong_buoc
      and g.tag_no !~ '^(TP|GC)' and coalesce(d.so_luong, 0) > 0
      and ((g.xong_luc is null and g.ma_may = v_tram.ten_tram)
        or (g.xong_luc is not null and cd_vi_tri_tem(g.tag_no) = 'Gia Công'
            and not exists (select 1 from gc_tem_buoc u where u.tag_no = g.tag_no and u.bo_luc is null and u.xong_luc is null)))
      and duc_tem_id_ncp_cach_ly(g.tag_no) is null
    order by g.bat_dau, g.id
  loop
    exit when v_can <= 0;
    select * into v_xe from duc_tem where tag_no = c.tag_no for update;
    v_lay := least(v_can, coalesce(v_xe.so_luong, 0));
    continue when v_lay <= 0;
    update duc_tem set so_luong = so_luong - v_lay where tag_no = c.tag_no;
    insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay) values (v_tt, c.tag_no, v_lay)
      on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
    if c.xong_luc is null then
      update gc_tem_buoc set sl_dong = sl_dong + v_lay, so_thung = so_thung + 1 where id = c.id;
    end if;
    v_tu := v_tu || jsonb_build_object('xe', c.tag_no, 'so_luong', v_lay, 'con', v_xe.so_luong - v_lay);
    if v_dau is null then v_dau := c.tag_no; end if;
    v_can := v_can - v_lay;
  end loop;
  if v_can > 0 then raise exception 'Chưa đủ 1 thùng (hàng vừa thay đổi), quét lại'; end if;

  select * into v_xe from duc_tem where tag_no = v_dau;
  select * into v_b from bavia_thung where tag_tp = v_dau and dang = 3;
  update duc_tem set so_luong = v_slt, so_luong_tt = v_slt, nguoi_tt = coalesce(nullif(v_tram.nguoi_thao_tac, ''), v_user),
    trang_thai = 'Đã đóng gói TP', tram_cong_doan = 'Gia Công',
    ghi_chu_sl = 'Đóng thùng từ xe ' || (select string_agg(x->>'xe', ' + ') from jsonb_array_elements(v_tu) x) || ' ở ' || v_tram.ten_tram,
    ngay_gio_ghi_nhan = v_now, ngay_gio_xuat = v_now, thoi_diem_san_xuat = coalesce(v_b.thoi_diem, v_now)
  where tag_no = v_tt;
  perform bavia_dien_thong_tin_nguon(v_tt);
  insert into cd_chuyen_cong_doan_log (id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
    lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan, nguoi_giao, nguoi_nhan,
    trang_thai_xac_nhan, ngay_gio_xac_nhan, ghi_chu)
  values (cd_next_transfer_id(), v_now, v_tt, v_xe.ma_sp, v_xe.ten_sp, v_slt, v_slt, 0,
    coalesce(v_xe.lot, ''), coalesce(v_xe.so_khuon_tt, v_xe.so_khuon, ''), coalesce(v_xe.nguyen_lieu, ''),
    coalesce(v_xe.may_tt, v_xe.may_duc_chi_thi, ''), coalesce(v_xe.ngay::text, ''),
    'Bavia', 'Gia Công', v_user, v_user, 'Đã xác nhận chuyển công đoạn',
    to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI:SS DD/MM/YYYY'), 'T338 Chia xe ' || v_dau);
  return jsonb_build_object('ok', true, 'dong_thung', true, 'tag_no', v_tt, 'so_luong', v_slt, 'tu', v_tu);
end $$;

-- 2) Dừng sản xuất xe (bất thường), bắt buộc lý do
create or replace function public.gc_dung_xe(p_id_tram text, p_id_buoc bigint, p_ly_do text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_chk jsonb; b gc_tem_buoc%rowtype; v_tram cd_tram_hien_tai%rowtype; v_user text := duc_su_co_nguoi_hien_tai();
  v_ld text := trim(coalesce(p_ly_do, ''));
begin
  v_chk := gc_kiem_buoc(p_id_tram, p_id_buoc);
  if not (v_chk->>'ok')::boolean then return v_chk; end if;
  if length(v_ld) < 3 then return jsonb_build_object('ok', false, 'error', 'Ghi rõ lý do dừng'); end if;
  if exists (select 1 from gc_hang_test where id_buoc = p_id_buoc and ket_thuc_luc is null) then
    return jsonb_build_object('ok', false, 'error', 'Xe còn hàng test chưa kết thúc');
  end if;
  select * into v_tram from cd_tram_hien_tai where id_tram = p_id_tram;
  select * into b from gc_tem_buoc where id = p_id_buoc for update;
  update gc_tem_buoc set bo_luc = now(), bo_boi = v_user, ly_do_dung = v_ld, sl_ra = sl_dong,
    id_tram_xong = p_id_tram, nguoi_lam = v_tram.nguoi_thao_tac
  where id = p_id_buoc;
  if b.buoc >= b.tong_buoc and coalesce(b.sl_dong, 0) > 0 then
    perform cd_tram_nhap_sanluong(p_id_tram, b.sl_dong, 0, null, v_user);
  end if;
  return jsonb_build_object('ok', true, 'tag_no', b.tag_no, 'sl_dong', b.sl_dong,
    'con', (select so_luong from duc_tem where tag_no = b.tag_no));
end $$;

revoke execute on function public.gc_dong_thung(text, text) from public, anon;
revoke execute on function public.gc_dung_xe(text, bigint, text) from public, anon;
grant execute on function public.gc_dong_thung(text, text) to authenticated;
grant execute on function public.gc_dung_xe(text, bigint, text) to authenticated;

-- 3) Sửa hàm cũ bằng replace()
do $mig$
declare v_old text; v_new text;
begin
  -- 3a) gc_quet: tem thùng in sẵn → đóng thùng
  v_old := pg_get_functiondef('public.gc_quet(text, text)'::regprocedure);
  if position('T343' in v_old) = 0 then
    v_new := replace(v_old,
      E'  if v_tag = '''' then return jsonb_build_object(''ok'', false, ''error'', ''Chưa có mã quét''); end if;\n',
      E'  if v_tag = '''' then return jsonb_build_object(''ok'', false, ''error'', ''Chưa có mã quét''); end if;\n'
      || E'  if v_tag ~ ''^(TP|GC)'' and exists (select 1 from duc_tem where tag_no = v_tag and trang_thai in (''Chờ đóng gói TP'', ''Đã đóng gói TP'') and tram_cong_doan = ''Gia Công'') then -- T343\n'
      || E'    return gc_dong_thung(p_id_tram, v_tag);\n'
      || E'  end if;\n');
    if v_new = v_old then raise exception 'T343: không sửa được gc_quet'; end if;
    execute v_new;
  end if;

  -- 3b) gc_xong: SL ra cộng phần đã đóng thùng; không mở Chia xe nữa
  v_old := pg_get_functiondef('public.gc_xong(text, bigint)'::regprocedure);
  if position('T343' in v_old) = 0 then
    v_new := replace(v_old,
      E'  select coalesce(so_luong, 0) into v_sl from duc_tem where tag_no = b.tag_no for update;\n',
      E'  select coalesce(so_luong, 0) into v_sl from duc_tem where tag_no = b.tag_no for update;\n'
      || E'  v_sl := v_sl + coalesce(b.sl_dong, 0); -- T343\n');
    v_new := replace(v_new,
      E'''chia_xe'', b.buoc >= b.tong_buoc and v_sl > 0 and exists (select 1 from bavia_thung where tag_tp = b.tag_no and dang = 3)); -- T340',
      E'''chia_xe'', false, ''sl_dong'', coalesce(b.sl_dong, 0), ''con'', v_sl - coalesce(b.sl_dong, 0)); -- T343');
    if position('chia_xe'', false' in v_new) = 0 or position('v_sl := v_sl + ' in v_new) = 0 then raise exception 'T343: không sửa được gc_xong'; end if;
    execute v_new;
  end if;

  -- 3c) gc_xong_huy: đã đóng thùng thì không huỷ Xong
  v_old := pg_get_functiondef('public.gc_xong_huy(bigint)'::regprocedure);
  if position('T343' in v_old) = 0 then
    v_new := replace(v_old,
      E'  if exists (select 1 from cd_chuyen_cong_doan_log where ghi_chu = ''T338 Chia xe '' || b.tag_no) then -- T340\n',
      E'  if exists (select 1 from cd_chuyen_cong_doan_log where ghi_chu = ''T338 Chia xe '' || b.tag_no) or coalesce(b.sl_dong, 0) > 0\n'
      || E'     or (b.buoc >= b.tong_buoc and exists (select 1 from cd_tem_nguon n where n.tag_no_nguon = b.tag_no and n.tag_no_moi ~ ''^(TP|GC)'')) then -- T340/T343\n');
    if v_new = v_old then raise exception 'T343: không sửa được gc_xong_huy'; end if;
    execute v_new;
  end if;

  -- 3d) gc_bo_tem: đã đóng thùng thì dùng Dừng
  v_old := pg_get_functiondef('public.gc_bo_tem(bigint)'::regprocedure);
  if position('T343' in v_old) = 0 then
    v_new := replace(v_old,
      E'  update gc_tem_buoc set bo_luc = now(), bo_boi = duc_su_co_nguoi_hien_tai() where id = p_id_buoc;\n',
      E'  if coalesce(b.sl_dong, 0) > 0 then -- T343\n'
      || E'    return jsonb_build_object(''ok'', false, ''error'', ''Xe đã đóng '' || b.sl_dong || '' pcs vào thùng. Dùng nút Dừng.'');\n'
      || E'  end if;\n'
      || E'  update gc_tem_buoc set bo_luc = now(), bo_boi = duc_su_co_nguoi_hien_tai() where id = p_id_buoc;\n');
    if v_new = v_old then raise exception 'T343: không sửa được gc_bo_tem'; end if;
    execute v_new;
  end if;

  -- 3e) gc_du_lieu: trả sl_dong / so_thung cho thùng đang làm
  v_old := pg_get_functiondef('public.gc_du_lieu(date, text)'::regprocedure);
  if position('sl_dong' in v_old) = 0 then
    v_new := replace(v_old,
      E'''sl_vao'', b.sl_vao, ''con'', d.so_luong, ''bat_dau''',
      E'''sl_vao'', b.sl_vao, ''con'', d.so_luong, ''sl_dong'', b.sl_dong, ''so_thung'', b.so_thung, ''bat_dau''');
    if v_new = v_old then raise exception 'T343: không sửa được gc_du_lieu'; end if;
    execute v_new;
  end if;
end $mig$;
