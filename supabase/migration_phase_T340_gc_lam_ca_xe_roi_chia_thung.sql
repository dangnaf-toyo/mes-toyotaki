-- T340 (23/11/2026): Gia công LÀM CẢ XE rồi mới chia thùng (thay cách T338 "chia xe trước khi gia công").
--
--   * Máy Gia công quét TEM XE (tem Đúc của xe Bavia chuyển nguyên) để bắt đầu — xe đi qua các bước CNC nguyên xe.
--   * NG / test ghi trên tem xe như thùng thường.
--   * Bấm Xong ở bước cuối → sản lượng cộng cả xe → quét lần lượt tem thùng QLSX in sẵn:
--     mỗi tem lấy đúng SL/thùng Gia Công trong danh mục (master_products.sl_thung_cong_doan->>'Gia Công');
--     xe còn ít hơn → tem cuối tự thành thùng lẻ.
--   * Không chia xe trước khi gia công nữa; xe chưa chia hết không chuyển công đoạn sau được.
--   * Tem thùng chia ra không quét lại vào máy Gia công. Đã chia thì không huỷ Xong được.

-- 1) Sửa hàm cũ bằng replace() (có kiểm tra đã thay được)
do $mig$
declare v_old text; v_new text;
begin
  -- 1a) gc_quet: nhận tem xe; chặn tem thùng đã chia từ xe
  v_old := pg_get_functiondef('public.gc_quet(text, text)'::regprocedure);
  if position('T340' in v_old) = 0 then
    v_new := replace(v_old,
      E'  if v_tem.tag_no not like ''TP%'' and exists (select 1 from bavia_thung where tag_tp = v_tem.tag_no and dang = 3) then -- T338\n'
      || E'    return jsonb_build_object(''ok'', false, ''error'', ''Tem '' || v_tem.tag_no || '' là tem xe Bavia, chưa chia thùng. Bấm "Chia xe" ở đầu trang.'');\n'
      || E'  end if;\n',
      E'  if v_tem.tag_no like ''TP%'' and exists (select 1 from cd_chuyen_cong_doan_log where tag_no = v_tem.tag_no and ghi_chu like ''T338 Chia xe %'') then -- T340\n'
      || E'    return jsonb_build_object(''ok'', false, ''error'', ''Tem '' || v_tem.tag_no || '' là thùng chia từ xe đã gia công xong, không quét lại vào máy.'');\n'
      || E'  end if;\n');
    if v_new = v_old then raise exception 'T340: không sửa được gc_quet'; end if;
    execute v_new;
  end if;

  -- 1b) gc_xong: báo UI mở Chia xe khi xong bước cuối của xe
  v_old := pg_get_functiondef('public.gc_xong(text, bigint)'::regprocedure);
  if position('chia_xe' in v_old) = 0 then
    v_new := replace(v_old,
      E'''buoc_cuoi'', b.buoc >= b.tong_buoc);',
      E'''buoc_cuoi'', b.buoc >= b.tong_buoc,\n'
      || E'    ''chia_xe'', b.buoc >= b.tong_buoc and v_sl > 0 and exists (select 1 from bavia_thung where tag_tp = b.tag_no and dang = 3)); -- T340');
    if v_new = v_old then raise exception 'T340: không sửa được gc_xong'; end if;
    execute v_new;
  end if;

  -- 1c) gc_xong_huy: xe đã chia thùng thì không huỷ Xong
  v_old := pg_get_functiondef('public.gc_xong_huy(bigint)'::regprocedure);
  if position('T340' in v_old) = 0 then
    v_new := replace(v_old,
      E'  select * into v_tram from cd_tram_hien_tai where id_tram = b.id_tram_xong for update;',
      E'  if exists (select 1 from cd_chuyen_cong_doan_log where ghi_chu = ''T338 Chia xe '' || b.tag_no) then -- T340\n'
      || E'    return jsonb_build_object(''ok'', false, ''error'', ''Xe '' || b.tag_no || '' đã chia thùng, không huỷ Xong được'');\n'
      || E'  end if;\n'
      || E'  select * into v_tram from cd_tram_hien_tai where id_tram = b.id_tram_xong for update;');
    if v_new = v_old then raise exception 'T340: không sửa được gc_xong_huy'; end if;
    execute v_new;
  end if;

  -- 1d) cd_kiem_xe_bavia: xe ở Gia Công phải chia thùng, không chuyển nguyên xe đi tiếp
  v_old := pg_get_functiondef('public.cd_kiem_xe_bavia(text, numeric)'::regprocedure);
  if position('T340' in v_old) = 0 then
    v_new := replace(v_old,
      E'  if cd_vi_tri_tem(v_tag) is distinct from ''Bavia'' then return null; end if;',
      E'  if cd_vi_tri_tem(v_tag) = ''Gia Công'' and exists (select 1 from bavia_thung where tag_tp = v_tag and dang = 3) then -- T340\n'
      || E'    return ''Xe '' || v_tag || '' phải gia công xong rồi chia thùng ở Bảng điều khiển Gia công (nút Chia xe), không chuyển nguyên xe.'';\n'
      || E'  end if;\n'
      || E'  if cd_vi_tri_tem(v_tag) is distinct from ''Bavia'' then return null; end if;');
    if v_new = v_old then raise exception 'T340: không sửa được cd_kiem_xe_bavia'; end if;
    execute v_new;
  end if;
end $mig$;

-- 2) SL/thùng Gia Công của mã (null nếu chưa khai)
create or replace function public.gc_sl_thung(p_ma_sp text)
returns numeric language sql stable security definer set search_path = public as $$
  select case when x ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' and x::numeric > 0 then x::numeric end
  from (select sl_thung_cong_doan->>'Gia Công' x from master_products where ma_sp = p_ma_sp) s;
$$;

-- 3) Gia công: Chia xe SAU khi gia công xong. p_tag_thung null = chỉ xem thông tin xe. p_cho_le giữ cho tương thích, không dùng.
create or replace function public.gc_chia_xe(p_tag_xe text, p_tag_thung text default null, p_cho_le boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_xe duc_tem%rowtype;
  v_th duc_tem%rowtype;
  v_b bavia_thung%rowtype;
  v_g gc_tem_buoc%rowtype;
  v_loc text;
  v_slt numeric;
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
  select * into v_g from gc_tem_buoc where tag_no = v_tag and bo_luc is null and xong_luc is null limit 1;
  if found then
    return jsonb_build_object('ok', false, 'error', 'Xe ' || v_tag || ' đang làm ở ' || v_g.ma_may || ' (bước ' || v_g.buoc || '/' || v_g.tong_buoc || '). Làm xong bước cuối rồi chia.');
  end if;
  select * into v_g from gc_tem_buoc where tag_no = v_tag and bo_luc is null and xong_luc is not null and buoc >= tong_buoc
  order by xong_luc desc limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Xe ' || v_tag || ' chưa gia công xong. Quét tem xe vào máy, làm xong bước cuối rồi chia thùng.');
  end if;
  v_slt := gc_sl_thung(v_xe.ma_sp);

  if v_tt <> '' then
    if coalesce(v_xe.so_luong, 0) <= 0 then
      return jsonb_build_object('ok', false, 'error', 'Xe ' || v_tag || ' đã chia hết');
    end if;
    if v_slt is null then
      return jsonb_build_object('ok', false, 'error', 'Mã ' || v_xe.ma_sp || ' chưa khai SL/thùng Gia Công. Khai ở Danh mục mã SP rồi quét lại.');
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
      return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tt || ' không phải tem thùng in sẵn (hoặc đã huỷ)');
    end if;
    v_sl := least(v_slt, v_xe.so_luong);

    update duc_tem set so_luong = so_luong - v_sl where tag_no = v_tag;
    insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay) values (v_tt, v_tag, v_sl)
      on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
    update duc_tem set so_luong = v_sl, so_luong_tt = v_sl, nguoi_tt = coalesce(nullif(v_g.nguoi_lam, ''), v_user), trang_thai = 'Đã đóng gói TP',
      ghi_chu_sl = 'Chia xe ' || v_tag || ' sau Gia công' || case when v_sl < v_slt then ' (thùng lẻ)' else '' end,
      ngay_gio_ghi_nhan = v_now, ngay_gio_xuat = v_now, thoi_diem_san_xuat = v_b.thoi_diem
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
    'sl_xe', v_g.sl_ra, 'sl_thung', v_slt, 'may', v_g.ma_may, 'thung', v_da,
    'tag_no', nullif(v_tt, ''), 'so_luong', v_sl, 'le', v_sl is not null and v_sl < v_slt);
end $$;

-- 4) Danh sách xe đã gia công xong, chưa chia hết
create or replace function public.gc_xe_cho_chia()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('xe', x.tag_tp, 'ma_sp', x.ma_sp, 'con', x.so_luong) order by x.xong_luc), '[]'::jsonb)
  from (
    select b.tag_tp, t.ma_sp, t.so_luong, max(g.xong_luc) xong_luc
    from bavia_thung b
    join duc_tem t on t.tag_no = b.tag_tp
    join gc_tem_buoc g on g.tag_no = b.tag_tp and g.bo_luc is null and g.xong_luc is not null and g.buoc >= g.tong_buoc
    where b.dang = 3 and coalesce(t.so_luong, 0) > 0
      and not exists (select 1 from gc_tem_buoc u where u.tag_no = b.tag_tp and u.bo_luc is null and u.xong_luc is null)
    group by b.tag_tp, t.ma_sp, t.so_luong
    order by 4 limit 50
  ) x
  where auth.uid() is not null;
$$;

revoke execute on function public.gc_sl_thung(text) from public, anon;
revoke execute on function public.gc_chia_xe(text, text, boolean) from public, anon;
revoke execute on function public.gc_xe_cho_chia() from public, anon;
grant execute on function public.gc_sl_thung(text) to authenticated;
grant execute on function public.gc_chia_xe(text, text, boolean) to authenticated;
grant execute on function public.gc_xe_cho_chia() to authenticated;
