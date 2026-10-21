-- ============================================================================
-- T130: Bavia — quét QR tem Đúc ghi nhận sản lượng, đủ 1 thùng thì in TEM XUẤT
-- HÀNG (mẫu của khách) cho các mã FCC / Astemo / Soji / Mikasa / Cosmos mà
-- Bavia là công đoạn sản xuất cuối (bước kế tiếp trong lưu trình = OQC hoặc
-- Nhập kho). Màn hình: bavia-tem-xuat-hang.html.
--
-- Luồng:
--   1) Quét tem Đúc → bavia_xh_ghi_nhan(tag, SL OK, NG[], người): trừ
--      duc_tem.so_luong (OK + NG), NG ghi cd_ng_khai_bao (cong_doan 'Bavia'),
--      OK vào "kho gom" bavia_xh_ghi_nhan.sl_con_gom (theo mã SP), cộng vào
--      trạm Bavia hôm nay của mã đó nếu có (báo cáo ca).
--   2) Kho gom của mã ≥ SL/thùng (master_products.sl_thung_cong_doan->>'Bavia')
--      → tự tạo tem thành phẩm (duc_tem, Tag No 'TP…', trang_thai 'Đã đóng gói
--      TP', tram_cong_doan 'Bavia'), trừ kho gom FIFO, nối nguồn cd_tem_nguon
--      (truy xuất nguồn gốc), ghi cd_chuyen_cong_doan_log Bavia→Bavia đã xác
--      nhận (vị trí hiện tại = Bavia, chuyển tiếp OQC/Nhập kho như mọi tem).
--   3) Cuối lô: bavia_xh_dong_thung_le đóng thùng lẻ bằng toàn bộ kho gom.
--   4) Quét nhầm: bavia_xh_huy_ghi_nhan hoàn lại tem Đúc nếu phần OK chưa vào
--      thùng nào.
-- Ghi duc_tem chỉ qua RPC security definer (T109 đã revoke ghi trực tiếp).
-- ============================================================================

create table if not exists bavia_xh_ghi_nhan (
  id            bigserial primary key,
  thoi_diem     timestamptz not null default now(),
  ngay          date not null default (now() at time zone 'Asia/Ho_Chi_Minh')::date,
  tag_no        text not null,
  ma_sp         text not null,
  sl_ok         numeric not null default 0,
  sl_ng         numeric not null default 0,
  ng_chi_tiet   jsonb not null default '[]'::jsonb,   -- [{loai, so_luong}]
  ng_ids        bigint[] not null default '{}',       -- cd_ng_khai_bao.id
  sl_con_gom    numeric not null default 0,           -- phần OK chưa vào thùng
  id_tram       text,                                 -- trạm Bavia đã cộng sản lượng
  nguoi         text,
  nguoi_uid     uuid,
  da_huy        boolean not null default false,
  huy_luc       timestamptz,
  huy_boi       text
);
create index if not exists bavia_xh_ghi_nhan_gom_idx on bavia_xh_ghi_nhan (ma_sp, thoi_diem, id) where sl_con_gom > 0;
create index if not exists bavia_xh_ghi_nhan_ngay_idx on bavia_xh_ghi_nhan (ngay);
create index if not exists bavia_xh_ghi_nhan_tag_idx on bavia_xh_ghi_nhan (tag_no);

-- Thùng (tem TP) lấy từ lần quét nào bao nhiêu — để tính NG Bavia / in phiếu FCC.
create table if not exists bavia_xh_thung_nguon (
  tag_tp         text not null,
  id_ghi_nhan    bigint not null references bavia_xh_ghi_nhan(id),
  so_luong_lay   numeric not null,
  primary key (tag_tp, id_ghi_nhan)
);
create index if not exists bavia_xh_thung_nguon_gn_idx on bavia_xh_thung_nguon (id_ghi_nhan);

alter table bavia_xh_ghi_nhan enable row level security;
alter table bavia_xh_thung_nguon enable row level security;
drop policy if exists bavia_xh_ghi_nhan_doc on bavia_xh_ghi_nhan;
create policy bavia_xh_ghi_nhan_doc on bavia_xh_ghi_nhan for select to authenticated using (true);
drop policy if exists bavia_xh_thung_nguon_doc on bavia_xh_thung_nguon;
create policy bavia_xh_thung_nguon_doc on bavia_xh_thung_nguon for select to authenticated using (true);
revoke insert, update, delete on bavia_xh_ghi_nhan, bavia_xh_thung_nguon from anon, authenticated;
grant select on bavia_xh_ghi_nhan, bavia_xh_thung_nguon to authenticated;

-- ── Mã SP có dùng tem xuất hàng Bavia không + thông số in ─────────────────
create or replace function bavia_xh_thong_tin_ma(p_ma_sp text)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  p master_products%rowtype;
  v_steps text[];
  v_i int;
  v_sau text;
  v_sl numeric;
  v_mau text;
begin
  select * into p from master_products where ma_sp = trim(p_ma_sp);
  if not found then return jsonb_build_object('ok', false, 'error', 'Mã SP không có trong danh mục: ' || coalesce(p_ma_sp, '')); end if;

  if coalesce(p.ten_khach_hang, '') !~* '(FCC|ASTEMO|SOJI|MIKASA|COSMOS)' then
    return jsonb_build_object('ok', false, 'ma_sp', p.ma_sp, 'error',
      'Mã ' || p.ma_sp || ' (khách hàng: ' || coalesce(nullif(p.ten_khach_hang, ''), 'chưa khai báo') ||
      ') không thuộc FCC / Astemo / Soji / Mikasa / Cosmos — không in tem xuất hàng tại Bavia');
  end if;

  select array_agg(trim(s) order by ord) into v_steps
  from unnest(string_to_array(coalesce(p.quy_trinh_cong_doan, ''), ',')) with ordinality as u(s, ord)
  where trim(s) <> '';
  v_i := array_position(v_steps, 'Bavia');
  if v_i is null then
    return jsonb_build_object('ok', false, 'ma_sp', p.ma_sp, 'error', 'Lưu trình của mã ' || p.ma_sp || ' không có công đoạn Bavia');
  end if;
  v_sau := v_steps[v_i + 1];
  if v_sau is not null and v_sau not in ('OQC', 'Nhập kho', 'Xuất hàng') then
    return jsonb_build_object('ok', false, 'ma_sp', p.ma_sp, 'error',
      'Mã ' || p.ma_sp || ' còn công đoạn "' || v_sau || '" sau Bavia — tem xuất hàng không in tại Bavia');
  end if;

  v_sl := nullif(p.sl_thung_cong_doan ->> 'Bavia', '')::numeric;
  if coalesce(v_sl, 0) <= 0 then
    return jsonb_build_object('ok', false, 'ma_sp', p.ma_sp, 'error',
      'Mã ' || p.ma_sp || ' chưa khai báo SL/thùng cho công đoạn Bavia (Danh mục SP → SL/thùng theo công đoạn)');
  end if;

  v_mau := case when p.ten_khach_hang ~* 'FCC' then 'fcc' else 'chung' end;
  return jsonb_build_object('ok', true, 'ma_sp', p.ma_sp, 'ten_sp', p.ten_sp,
    'ten_khach_hang', p.ten_khach_hang, 'ma_sp_khach_hang', p.ma_sp_khach_hang,
    'nguyen_lieu', p.nguyen_lieu, 'sl_thung', v_sl, 'mau', v_mau, 'buoc_sau', v_sau);
end $$;
revoke execute on function bavia_xh_thong_tin_ma(text) from public, anon;
grant execute on function bavia_xh_thong_tin_ma(text) to authenticated;

-- ── Tạo 1 thùng từ kho gom (nội bộ) ─────────────────────────────────────────
create or replace function bavia_xh_tao_thung(p_ma_sp text, p_sl numeric, p_nguoi text, p_le boolean)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  p master_products%rowtype;
  v_tag text;
  v_need numeric := p_sl;
  v_take numeric;
  g record;
  v_src duc_tem%rowtype;
  v_lot text[] := '{}'; v_khuon text[] := '{}'; v_nl text[] := '{}'; v_may text[] := '{}';
  v_ngay date;
  v_now timestamptz := now();
begin
  select * into p from master_products where ma_sp = p_ma_sp;
  v_tag := cd_next_tag_no_thanh_pham();

  -- Tem trước, nguồn sau (cd_tem_nguon/bavia_xh_thung_nguon tham chiếu tag mới).
  insert into duc_tem (tag_no, ten_sp, ma_sp, so_luong, so_luong_tt, ngay, lot,
    ma_sp_khach_hang, ten_khach_hang, ghi_chu, ngay_gio_in, ngay_gio_ghi_nhan, nguoi_tt,
    trang_thai, ghi_chu_sl, tram_cong_doan, thoi_diem_san_xuat)
  values (v_tag, p.ten_sp, p_ma_sp, p_sl, p_sl, null, null,
    p.ma_sp_khach_hang, p.ten_khach_hang,
    'Tem xuất hàng Bavia' || case when p_le then ' — thùng lẻ' else '' end, v_now, v_now, p_nguoi,
    'Đã đóng gói TP', 'Đã ghi nhận thành phẩm', 'Bavia', v_now);

  for g in select * from bavia_xh_ghi_nhan
           where ma_sp = p_ma_sp and sl_con_gom > 0 and not da_huy
           order by thoi_diem, id for update
  loop
    exit when v_need <= 0;
    v_take := least(v_need, g.sl_con_gom);
    update bavia_xh_ghi_nhan set sl_con_gom = sl_con_gom - v_take where id = g.id;
    insert into bavia_xh_thung_nguon (tag_tp, id_ghi_nhan, so_luong_lay) values (v_tag, g.id, v_take);
    insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay) values (v_tag, g.tag_no, v_take)
      on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
    select * into v_src from duc_tem where tag_no = g.tag_no;
    if found then
      if v_ngay is null or v_src.ngay < v_ngay then v_ngay := v_src.ngay; end if;
      if coalesce(v_src.lot, '') <> '' and not v_src.lot = any(v_lot) then v_lot := v_lot || v_src.lot; end if;
      if coalesce(v_src.so_khuon, '') <> '' and not v_src.so_khuon = any(v_khuon) then v_khuon := v_khuon || v_src.so_khuon; end if;
      if coalesce(v_src.nguyen_lieu, '') <> '' and not v_src.nguyen_lieu = any(v_nl) then v_nl := v_nl || v_src.nguyen_lieu; end if;
      if coalesce(v_src.may_duc_chi_thi, '') <> '' and not v_src.may_duc_chi_thi = any(v_may) then v_may := v_may || v_src.may_duc_chi_thi; end if;
    end if;
    v_need := v_need - v_take;
  end loop;
  if v_need > 0 then raise exception 'Kho gom mã % không đủ % pcs để đóng thùng', p_ma_sp, p_sl; end if;

  update duc_tem set ngay = v_ngay, lot = array_to_string(v_lot, ', '), so_khuon = array_to_string(v_khuon, ', '),
    so_khuon_tt = array_to_string(v_khuon, ', '),
    nguyen_lieu = coalesce(nullif(array_to_string(v_nl, ', '), ''), p.nguyen_lieu),
    may_duc_chi_thi = array_to_string(v_may, ', ')
  where tag_no = v_tag;

  insert into cd_chuyen_cong_doan_log (id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
    lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan,
    nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan, ghi_chu)
  values (cd_next_transfer_id(), v_now, v_tag, p_ma_sp, p.ten_sp, p_sl, p_sl, 0,
    array_to_string(v_lot, ', '), array_to_string(v_khuon, ', '), array_to_string(v_nl, ', '),
    array_to_string(v_may, ', '), coalesce(v_ngay::text, ''), 'Bavia', 'Bavia',
    p_nguoi, p_nguoi, 'Đã xác nhận chuyển công đoạn', to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI:SS DD/MM/YYYY'),
    'Đóng thùng tem xuất hàng tại Bavia' || case when p_le then ' (thùng lẻ)' else '' end);
  return v_tag;
end $$;
revoke execute on function bavia_xh_tao_thung(text, numeric, text, boolean) from public, anon, authenticated;

-- ── Quét 1 tem Đúc ──────────────────────────────────────────────────────────
create or replace function bavia_xh_ghi_nhan(p_tag_no text, p_sl_ok numeric, p_ng jsonb, p_nguoi text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_tem duc_tem%rowtype;
  v_info jsonb;
  v_ok numeric := coalesce(p_sl_ok, 0);
  v_ng numeric := 0;
  v_ng_ct jsonb := '[]'::jsonb;
  v_ng_ids bigint[] := '{}';
  v_id_ng bigint;
  x jsonb;
  v_sl_x numeric;
  v_ncp text;
  v_id bigint;
  v_tram text;
  v_sl_thung numeric;
  v_gom numeric;
  v_tems text[] := '{}';
  v_nguoi text := coalesce(nullif(trim(p_nguoi), ''), 'Không rõ');
  v_ngay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into v_tem from duc_tem where tag_no = trim(coalesce(p_tag_no, '')) for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || coalesce(p_tag_no, '')); end if;
  if v_tem.trang_thai in ('Chờ đóng gói TP', 'Đã đóng gói TP') then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' là tem thành phẩm / tem xuất hàng — hãy quét tem Đúc');
  end if;
  v_ncp := duc_tem_id_ncp_cach_ly(v_tem.tag_no);
  if v_ncp is not null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang bị cách ly theo phiếu NCP ' || v_ncp);
  end if;

  v_info := bavia_xh_thong_tin_ma(v_tem.ma_sp);
  if not (v_info ->> 'ok')::boolean then return v_info; end if;
  v_sl_thung := (v_info ->> 'sl_thung')::numeric;

  for x in select * from jsonb_array_elements(coalesce(p_ng, '[]'::jsonb)) loop
    v_sl_x := coalesce(nullif(x ->> 'so_luong', '')::numeric, 0);
    if v_sl_x < 0 then return jsonb_build_object('ok', false, 'error', 'Số lượng NG không được âm'); end if;
    if v_sl_x > 0 then
      if coalesce(trim(x ->> 'loai'), '') = '' then return jsonb_build_object('ok', false, 'error', 'Chọn loại NG cho dòng ' || v_sl_x || ' pcs'); end if;
      v_ng := v_ng + v_sl_x;
      v_ng_ct := v_ng_ct || jsonb_build_array(jsonb_build_object('loai', trim(x ->> 'loai'), 'so_luong', v_sl_x));
    end if;
  end loop;
  if v_ok < 0 then return jsonb_build_object('ok', false, 'error', 'Số lượng OK không được âm'); end if;
  if v_ok + v_ng <= 0 then return jsonb_build_object('ok', false, 'error', 'Nhập số lượng OK hoặc NG'); end if;
  if v_ok + v_ng > coalesce(v_tem.so_luong, 0) then
    return jsonb_build_object('ok', false, 'error', 'OK + NG (' || (v_ok + v_ng) || ') vượt số còn lại trên tem ' || v_tem.tag_no || ' (' || coalesce(v_tem.so_luong, 0) || ' pcs)');
  end if;

  update duc_tem set so_luong = so_luong - v_ok - v_ng where tag_no = v_tem.tag_no;

  for x in select * from jsonb_array_elements(v_ng_ct) loop
    insert into cd_ng_khai_bao (tag_no, ma_sp, ten_sp, cong_doan, loai_ng, so_luong, nguoi)
    values (v_tem.tag_no, v_tem.ma_sp, v_tem.ten_sp, 'Bavia', x ->> 'loai', (x ->> 'so_luong')::numeric, v_nguoi)
    returning id into v_id_ng;
    v_ng_ids := v_ng_ids || v_id_ng;
  end loop;

  -- Cộng vào trạm Bavia hôm nay của mã này (nếu tổ có gán kế hoạch trạm) → báo cáo ca.
  select id_tram into v_tram from cd_tram_hien_tai
  where cong_doan = 'Bavia' and ngay = v_ngay and ma_sp = v_tem.ma_sp order by id_tram limit 1;
  if v_tram is not null then
    perform cd_tram_nhap_sanluong(v_tram, v_ok, v_ng, 'Tem xuất hàng Bavia — quét ' || v_tem.tag_no, v_nguoi);
  end if;

  insert into bavia_xh_ghi_nhan (ngay, tag_no, ma_sp, sl_ok, sl_ng, ng_chi_tiet, ng_ids, sl_con_gom, id_tram, nguoi, nguoi_uid)
  values (v_ngay, v_tem.tag_no, v_tem.ma_sp, v_ok, v_ng, v_ng_ct, v_ng_ids, v_ok, v_tram, v_nguoi, auth.uid())
  returning id into v_id;

  loop
    select coalesce(sum(sl_con_gom), 0) into v_gom from bavia_xh_ghi_nhan where ma_sp = v_tem.ma_sp and sl_con_gom > 0 and not da_huy;
    exit when v_gom < v_sl_thung;
    v_tems := v_tems || bavia_xh_tao_thung(v_tem.ma_sp, v_sl_thung, v_nguoi, false);
  end loop;

  return jsonb_build_object('ok', true, 'id', v_id, 'tag_no', v_tem.tag_no, 'ma_sp', v_tem.ma_sp,
    'sl_ok', v_ok, 'sl_ng', v_ng, 'so_luong_con_lai_tem', coalesce(v_tem.so_luong, 0) - v_ok - v_ng,
    'gom', v_gom, 'sl_thung', v_sl_thung, 'tem_moi', to_jsonb(v_tems), 'id_tram', v_tram);
end $$;
revoke execute on function bavia_xh_ghi_nhan(text, numeric, jsonb, text) from public, anon;
grant execute on function bavia_xh_ghi_nhan(text, numeric, jsonb, text) to authenticated;

-- ── Đóng thùng lẻ (cuối lô / cuối ca) ───────────────────────────────────────
create or replace function bavia_xh_dong_thung_le(p_ma_sp text, p_nguoi text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_gom numeric;
  v_tag text;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  perform 1 from bavia_xh_ghi_nhan where ma_sp = trim(p_ma_sp) and sl_con_gom > 0 and not da_huy for update;
  select coalesce(sum(sl_con_gom), 0) into v_gom from bavia_xh_ghi_nhan where ma_sp = trim(p_ma_sp) and sl_con_gom > 0 and not da_huy;
  if v_gom <= 0 then return jsonb_build_object('ok', false, 'error', 'Mã ' || p_ma_sp || ' không còn hàng đang gom'); end if;
  v_tag := bavia_xh_tao_thung(trim(p_ma_sp), v_gom, coalesce(nullif(trim(p_nguoi), ''), 'Không rõ'), true);
  return jsonb_build_object('ok', true, 'tem_moi', jsonb_build_array(v_tag), 'so_luong', v_gom);
end $$;
revoke execute on function bavia_xh_dong_thung_le(text, text) from public, anon;
grant execute on function bavia_xh_dong_thung_le(text, text) to authenticated;

-- ── Huỷ 1 lần quét nhầm (chỉ khi phần OK chưa vào thùng nào) ───────────────
create or replace function bavia_xh_huy_ghi_nhan(p_id bigint, p_nguoi text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare g bavia_xh_ghi_nhan%rowtype;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into g from bavia_xh_ghi_nhan where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy lần ghi nhận #' || p_id); end if;
  if g.da_huy then return jsonb_build_object('ok', false, 'error', 'Lần ghi nhận này đã huỷ'); end if;
  if g.sl_con_gom < g.sl_ok then
    return jsonb_build_object('ok', false, 'error', 'Đã có ' || (g.sl_ok - g.sl_con_gom) || ' pcs của lần quét này vào thùng — không huỷ được');
  end if;
  update duc_tem set so_luong = so_luong + g.sl_ok + g.sl_ng where tag_no = g.tag_no;
  delete from cd_ng_khai_bao where id = any(g.ng_ids);
  if g.id_tram is not null then
    update cd_tram_hien_tai set so_luong_ok = greatest(0, so_luong_ok - g.sl_ok), so_luong_ng = greatest(0, so_luong_ng - g.sl_ng),
      version = version + 1, last_updated_by = p_nguoi, last_updated_at = now()
    where id_tram = g.id_tram;
  end if;
  update bavia_xh_ghi_nhan set da_huy = true, sl_con_gom = 0, huy_luc = now(), huy_boi = coalesce(nullif(trim(p_nguoi), ''), 'Không rõ')
  where id = g.id;
  return jsonb_build_object('ok', true, 'tag_no', g.tag_no);
end $$;
revoke execute on function bavia_xh_huy_ghi_nhan(bigint, text) from public, anon;
grant execute on function bavia_xh_huy_ghi_nhan(bigint, text) to authenticated;

-- ── Dữ liệu in (cả in lại) ──────────────────────────────────────────────────
create or replace function bavia_xh_du_lieu_in(p_tags text[])
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'tag_no', t.tag_no, 'ma_sp', t.ma_sp, 'ten_sp', t.ten_sp, 'so_luong', t.so_luong_tt,
      'ma_sp_khach_hang', coalesce(t.ma_sp_khach_hang, p.ma_sp_khach_hang),
      'ten_khach_hang', coalesce(t.ten_khach_hang, p.ten_khach_hang),
      'nguyen_lieu', t.nguyen_lieu, 'lot', t.lot, 'ngay', t.ngay, 'so_khuon', t.so_khuon,
      'may', t.may_duc_chi_thi, 'nguoi', t.nguoi_tt, 'luc', t.ngay_gio_ghi_nhan,
      'thung_le', t.ghi_chu like '%thùng lẻ%',
      'mau', case when coalesce(t.ten_khach_hang, p.ten_khach_hang) ~* 'FCC' then 'fcc' else 'chung' end,
      'nguon', (select coalesce(jsonb_agg(jsonb_build_object('tag_no', s.tag_no, 'so_luong_lay', n.so_luong_lay,
                  'ngay', s.ngay, 'may', coalesce(s.may_tt, s.may_duc_chi_thi), 'nguoi', s.nguoi_tt, 'so_khuon', s.so_khuon,
                  'ngay_gio_in', s.ngay_gio_in) order by s.ngay, s.tag_no), '[]'::jsonb)
                from cd_tem_nguon n join duc_tem s on s.tag_no = n.tag_no_nguon where n.tag_no_moi = t.tag_no),
      -- NG Bavia: tính cho thùng ĐẦU TIÊN lấy từ mỗi lần quét.
      'ng_bavia', (select coalesce(sum(g.sl_ng), 0) from bavia_xh_thung_nguon tn join bavia_xh_ghi_nhan g on g.id = tn.id_ghi_nhan
                   where tn.tag_tp = t.tag_no
                     and tn.tag_tp = (select min(x.tag_tp) from bavia_xh_thung_nguon x where x.id_ghi_nhan = g.id)),
      'nguoi_bavia', (select string_agg(distinct g.nguoi, ', ') from bavia_xh_thung_nguon tn join bavia_xh_ghi_nhan g on g.id = tn.id_ghi_nhan
                      where tn.tag_tp = t.tag_no)
    ) order by t.tag_no), '[]'::jsonb)
  from duc_tem t left join master_products p on p.ma_sp = t.ma_sp
  where t.tag_no = any(p_tags);
$$;
revoke execute on function bavia_xh_du_lieu_in(text[]) from public, anon;
grant execute on function bavia_xh_du_lieu_in(text[]) to authenticated;
