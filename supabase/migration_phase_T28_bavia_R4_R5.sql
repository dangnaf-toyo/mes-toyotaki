-- ============================================================================
-- Phase T28 — Bavia: xử lý R4 (sửa hàng chéo ca) + R5 (gom tem NG chờ sửa)
--
-- R4: bavia_sua_hang trước credit cd_bao_cao_ca theo ngày/ca ĐANG CHỌN → sửa
--     sang ca khác thì dòng báo cáo ca đó bị ng_sua âm. Nay credit về ĐÚNG
--     ngày/ca GỐC nơi tem "NG chờ sửa" được tạo (tra bavia_xu_ly_ra→bavia_xu_ly).
--     Lưu credit_ngay/credit_ca/credit_to vào bavia_sua_log để undo đảo đúng chỗ.
--
-- R5: bavia_gom_ng_cho_sua(p_tags[]) — gom nhiều tem "NG chờ sửa" cùng mã SP
--     thành 1 tem TKB "NG chờ sửa" (giữ phả hệ qua cd_tem_nguon), các tem cũ
--     -> so_luong=0, trang_thai='Đã gộp NG'. KHÔNG đụng cd_bao_cao_ca (cùng số
--     sp, ng_sua tổng không đổi). bavia_gom_log + bavia_undo_gom_ng.
--
-- Chạy trong Supabase SQL Editor. Idempotent.
-- ============================================================================

alter table bavia_sua_log add column if not exists credit_ngay date;
alter table bavia_sua_log add column if not exists credit_ca   text;
alter table bavia_sua_log add column if not exists credit_to   text;

-- ── R4: bavia_sua_hang — credit về ngày/ca GỐC ──────────────────────────
create or replace function bavia_sua_hang(
  p_tag_ng text, p_ngay date, p_ca text, p_cong_doan text,
  p_ok numeric, p_ng_phe numeric, p_ng_ly_do text,
  p_cach_dong text, p_quy_cach numeric, p_tag_gop text,
  p_nguoi text, p_user text, p_client_key text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_t duc_tem%rowtype; v_gop duc_tem%rowtype;
  v_ok numeric := coalesce(p_ok, 0); v_phe numeric := coalesce(p_ng_phe, 0);
  v_can numeric;
  v_out_tag text[] := '{}'; v_out_qty numeric[] := '{}';
  v_tag text; v_need numeric; v_q numeric; j int;
  v_tems jsonb := '[]'::jsonb;
  v_lot text; v_khu text; v_nl text; v_may text; v_ngay date; v_ten_sp text; v_ma_sp text;
  v_now timestamptz := now();
  v_ra text[] := '{}';
  v_key text := nullif(trim(p_client_key), '');
  v_cr_ngay date; v_cr_ca text; v_cr_to text;
begin
  if v_ok < 0 or v_phe < 0 then raise exception 'Số lượng không được âm'; end if;
  v_can := v_ok + v_phe;
  if v_can <= 0 then raise exception 'Chưa nhập OK / NG phế'; end if;
  if p_ngay is null or coalesce(trim(p_ca), '') = '' or coalesce(trim(p_cong_doan), '') = '' then
    raise exception 'Thiếu ngày / ca / công đoạn';
  end if;

  if v_key is not null and exists(select 1 from bavia_sua_log where client_key = v_key) then
    select coalesce(jsonb_agg(jsonb_build_object('tag', t, 'so_luong',
      (select d.so_luong from duc_tem d where d.tag_no = t), 'loai', 'ok')), '[]'::jsonb)
      into v_tems
      from (select unnest(tag_ra) as t from bavia_sua_log where client_key = v_key) s;
    return jsonb_build_object('ok', true, 'tems', v_tems, 'duplicate', true);
  end if;

  select * into v_t from duc_tem where tag_no = p_tag_ng for update;
  if not found then raise exception 'Không tìm thấy tem %', p_tag_ng; end if;
  if v_t.trang_thai is distinct from 'NG chờ sửa' then
    raise exception 'Tem % không phải "NG chờ sửa" (đang: %)', p_tag_ng, coalesce(v_t.trang_thai, '—');
  end if;
  if coalesce(v_t.so_luong, 0) <= 0 then raise exception 'Tem % đã hết số lượng', p_tag_ng; end if;
  if v_can > v_t.so_luong then
    raise exception 'OK + NG phế (%) vượt SL còn lại của tem (%)', v_can, v_t.so_luong;
  end if;

  v_lot := v_t.lot; v_khu := v_t.so_khuon; v_nl := v_t.nguyen_lieu; v_may := v_t.may_duc_chi_thi;
  v_ngay := v_t.ngay; v_ten_sp := v_t.ten_sp; v_ma_sp := v_t.ma_sp;

  -- R4: credit về ngày/ca/line GỐC (nơi tem NG-sửa được sinh ra); không có
  -- (tem gộp NG hoặc tạo trước T26) → dùng ngày/ca người dùng đang chọn.
  select bx.ngay, bx.ca, coalesce(nullif(bx.ten_tram, ''), '')
    into v_cr_ngay, v_cr_ca, v_cr_to
  from bavia_xu_ly_ra r join bavia_xu_ly bx on bx.id = r.id_xu_ly
  where r.tag_moi = p_tag_ng and r.loai = 'ng_sua'
  order by bx.id desc limit 1;
  v_cr_ngay := coalesce(v_cr_ngay, p_ngay);
  v_cr_ca   := coalesce(nullif(trim(v_cr_ca), ''), p_ca);
  v_cr_to   := coalesce(v_cr_to, coalesce(v_t.tram_cong_doan, ''));

  if v_ok > 0 then
    if p_cach_dong = 'gop' then
      if coalesce(trim(p_tag_gop), '') = '' then raise exception 'Chọn "gộp" thì phải chọn thùng đích'; end if;
      select * into v_gop from duc_tem where tag_no = p_tag_gop for update;
      if not found then raise exception 'Không tìm thấy thùng gộp %', p_tag_gop; end if;
      if v_gop.ma_sp is distinct from v_ma_sp then raise exception 'Thùng gộp % khác mã SP', p_tag_gop; end if;
      update duc_tem set so_luong = coalesce(so_luong, 0) + v_ok where tag_no = p_tag_gop;
      insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay)
      values (p_tag_gop, p_tag_ng, v_ok)
      on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
      v_tems := v_tems || jsonb_build_object('tag', p_tag_gop, 'so_luong', v_ok, 'loai', 'ok_gop');
    else
      if p_cach_dong = 'quy_cach' then
        if coalesce(p_quy_cach, 0) <= 0 then raise exception 'Quy cách không hợp lệ'; end if;
        v_need := v_ok;
        while v_need > 0 loop
          v_q := least(v_need, p_quy_cach);
          v_out_tag := array_append(v_out_tag, bavia_next_tag_no());
          v_out_qty := array_append(v_out_qty, v_q);
          v_need := v_need - v_q;
        end loop;
      else
        v_out_tag := array[bavia_next_tag_no()]; v_out_qty := array[v_ok];
      end if;

      for j in 1 .. array_length(v_out_tag, 1) loop
        insert into duc_tem (
          tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
          may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
          nguoi_tt, trang_thai, ghi_chu_sl, tram_cong_doan, thoi_diem_san_xuat
        ) values (
          v_out_tag[j], v_ten_sp, v_ma_sp, v_out_qty[j], v_ngay,
          v_lot, v_khu, v_nl, v_may, 'Sửa hàng từ ' || p_tag_ng, v_now, v_khu, v_out_qty[j], v_may,
          coalesce(nullif(trim(p_nguoi), ''), p_user), 'Bavia', 'Sửa từ ' || p_tag_ng,
          coalesce(v_t.tram_cong_doan, p_cong_doan), v_now
        );
        insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay)
        values (v_out_tag[j], p_tag_ng, v_out_qty[j])
        on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;

        insert into cd_chuyen_cong_doan_log (
          id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
          lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan,
          nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan
        ) values (
          cd_next_transfer_id(), v_now, v_out_tag[j], v_ma_sp, v_ten_sp, v_out_qty[j], v_out_qty[j], 0,
          v_lot, v_khu, v_nl, v_may, coalesce(v_ngay::text, ''), p_cong_doan, p_cong_doan,
          coalesce(nullif(trim(p_nguoi), ''), p_user), coalesce(nullif(trim(p_nguoi), ''), p_user),
          'Đã xác nhận chuyển công đoạn', to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
        );
        v_ra := array_append(v_ra, v_out_tag[j]);
        v_tems := v_tems || jsonb_build_object('tag', v_out_tag[j], 'so_luong', v_out_qty[j], 'loai', 'ok');
      end loop;
    end if;
  end if;

  update duc_tem set
    so_luong = coalesce(so_luong, 0) - v_can,
    trang_thai = case when coalesce(so_luong, 0) - v_can <= 0 then 'Đã sửa xong' else 'NG chờ sửa' end
  where tag_no = p_tag_ng;

  perform cd_gop_tally_vao_bao_cao(
    v_cr_ngay, v_cr_ca, p_cong_doan, v_ma_sp, v_ten_sp, v_cr_to,
    v_ok, v_phe, 'Sửa hàng từ ' || p_tag_ng || case when coalesce(trim(p_ng_ly_do),'') <> '' then ' — ' || trim(p_ng_ly_do) else '' end,
    -(v_ok + v_phe)
  );

  insert into bavia_sua_log (tag_ng, ngay, ca, cong_doan, ma_sp, so_ok, so_ng_phe, ly_do, nguoi, tag_ra, client_key, credit_ngay, credit_ca, credit_to)
  values (p_tag_ng, p_ngay, p_ca, p_cong_doan, v_ma_sp, v_ok, v_phe, nullif(trim(p_ng_ly_do), ''),
          coalesce(nullif(trim(p_nguoi), ''), p_user),
          case when array_length(v_ra,1) is null then null else v_ra end, v_key,
          v_cr_ngay, v_cr_ca, v_cr_to);

  return jsonb_build_object('ok', true, 'tems', v_tems, 'con_lai_tem_ng', greatest(0, coalesce(v_t.so_luong, 0) - v_can));
end;
$$;
revoke execute on function bavia_sua_hang(text, date, text, text, numeric, numeric, text, text, numeric, text, text, text, text) from anon;
grant  execute on function bavia_sua_hang(text, date, text, text, numeric, numeric, text, text, numeric, text, text, text, text) to authenticated;

-- ── R4: bavia_undo_sua_hang — đảo đúng dòng đã credit ────────────────────
create or replace function bavia_undo_sua_hang(p_id bigint, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_s bavia_sua_log%rowtype; v_tag text; v_cur duc_tem%rowtype;
begin
  select * into v_s from bavia_sua_log where id = p_id for update;
  if not found then raise exception 'Không tìm thấy lần sửa %', p_id; end if;

  if v_s.tag_ra is not null then
    foreach v_tag in array v_s.tag_ra loop
      select * into v_cur from duc_tem where tag_no = v_tag for update;
      if not found then raise exception 'Tem % không còn — không undo được', v_tag; end if;
      if bavia_tem_da_dung(v_tag) then raise exception 'Tem % đã dùng ở bước sau — không undo được', v_tag; end if;
    end loop;
    foreach v_tag in array v_s.tag_ra loop
      delete from cd_tem_nguon where tag_no_moi = v_tag;
      delete from cd_chuyen_cong_doan_log where tag_no = v_tag;
      delete from duc_tem where tag_no = v_tag;
    end loop;
  end if;

  update duc_tem set
    so_luong = coalesce(so_luong, 0) + (v_s.so_ok + v_s.so_ng_phe),
    trang_thai = 'NG chờ sửa'
  where tag_no = v_s.tag_ng;

  perform cd_gop_tally_vao_bao_cao(
    coalesce(v_s.credit_ngay, v_s.ngay), coalesce(v_s.credit_ca, v_s.ca), v_s.cong_doan,
    v_s.ma_sp, null, coalesce(v_s.credit_to, ''),
    -v_s.so_ok, -v_s.so_ng_phe, 'UNDO sửa hàng #' || p_id, (v_s.so_ok + v_s.so_ng_phe));

  delete from bavia_sua_log where id = p_id;
  return jsonb_build_object('ok', true, 'undo', p_id);
end;
$$;
revoke execute on function bavia_undo_sua_hang(bigint, text) from anon;
grant  execute on function bavia_undo_sua_hang(bigint, text) to authenticated;

-- ── R5: gom tem "NG chờ sửa" ────────────────────────────────────────────
create table if not exists bavia_gom_log (
  id         bigserial primary key,
  tag_moi    text not null references duc_tem(tag_no),
  tags_goc   text[] not null,
  ma_sp      text,
  so_luong   numeric,
  nguoi      text,
  client_key text,
  thoi_diem  timestamptz not null default now()
);
create unique index if not exists ux_bavia_gom_ckey on bavia_gom_log(client_key) where client_key is not null;
alter table bavia_gom_log enable row level security;
drop policy if exists "public read" on bavia_gom_log;
create policy "public read" on bavia_gom_log for select using (true);

create or replace function bavia_gom_ng_cho_sua(
  p_tags text[], p_nguoi text, p_user text, p_client_key text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_key text := nullif(trim(p_client_key), '');
  v_t   duc_tem%rowtype;
  v_n   int;
  v_tong numeric := 0;
  v_ma_sp text; v_ten_sp text; v_ngay date; v_tram_cd text;
  v_lot text[] := '{}'; v_khu text[] := '{}'; v_nl text[] := '{}'; v_may text[] := '{}';
  v_new text; v_pos text;
  v_now timestamptz := now();
  i int;
begin
  if p_tags is null or array_length(p_tags, 1) is null or array_length(p_tags, 1) < 2 then
    raise exception 'Chọn ít nhất 2 tem NG chờ sửa để gom';
  end if;
  if (select count(*) from unnest(p_tags)) <> (select count(distinct x) from unnest(p_tags) x) then
    raise exception 'Có tem chọn trùng';
  end if;

  if v_key is not null and exists(select 1 from bavia_gom_log where client_key = v_key) then
    return (select jsonb_build_object('ok', true, 'duplicate', true, 'tag_moi', g.tag_moi, 'so_luong', g.so_luong)
            from bavia_gom_log g where g.client_key = v_key);
  end if;

  v_n := array_length(p_tags, 1);
  for i in 1 .. v_n loop
    select * into v_t from duc_tem where tag_no = p_tags[i] for update;
    if not found then raise exception 'Không tìm thấy tem %', p_tags[i]; end if;
    if v_t.trang_thai is distinct from 'NG chờ sửa' then
      raise exception 'Tem % không phải "NG chờ sửa"', p_tags[i];
    end if;
    if coalesce(v_t.so_luong, 0) <= 0 then raise exception 'Tem % đã hết số lượng', p_tags[i]; end if;
    if v_ma_sp is null then v_ma_sp := v_t.ma_sp; v_ten_sp := v_t.ten_sp; v_tram_cd := v_t.tram_cong_doan;
    elsif v_ma_sp is distinct from v_t.ma_sp then raise exception 'Các tem khác mã SP (% và %)', v_ma_sp, v_t.ma_sp; end if;
    if v_ngay is null or (v_t.ngay is not null and v_t.ngay < v_ngay) then v_ngay := v_t.ngay; end if;
    if coalesce(v_t.lot,'')            <> '' and not (v_t.lot = any(v_lot)) then v_lot := array_append(v_lot, v_t.lot); end if;
    if coalesce(v_t.so_khuon,'')       <> '' and not (v_t.so_khuon = any(v_khu)) then v_khu := array_append(v_khu, v_t.so_khuon); end if;
    if coalesce(v_t.nguyen_lieu,'')    <> '' and not (v_t.nguyen_lieu = any(v_nl)) then v_nl := array_append(v_nl, v_t.nguyen_lieu); end if;
    if coalesce(v_t.may_duc_chi_thi,'')<> '' and not (v_t.may_duc_chi_thi = any(v_may)) then v_may := array_append(v_may, v_t.may_duc_chi_thi); end if;
    v_tong := v_tong + v_t.so_luong;
  end loop;

  select vi_tri_hien_tai into v_pos from cd_v_vi_tri_hien_tai where tag_no = p_tags[1];
  v_pos := coalesce(v_pos, 'Bavia');
  v_new := bavia_next_tag_no();

  insert into duc_tem (
    tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
    may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
    nguoi_tt, trang_thai, ghi_chu_sl, tram_cong_doan, thoi_diem_san_xuat
  ) values (
    v_new, v_ten_sp, v_ma_sp, v_tong, v_ngay,
    array_to_string(v_lot, ', '), array_to_string(v_khu, ', '), array_to_string(v_nl, ', '),
    array_to_string(v_may, ', '), 'Gom NG chờ sửa từ ' || array_to_string(p_tags, ', '), v_now,
    array_to_string(v_khu, ', '), v_tong, array_to_string(v_may, ', '),
    coalesce(nullif(trim(p_nguoi), ''), p_user), 'NG chờ sửa',
    'Gom từ ' || array_to_string(p_tags, ', '), v_tram_cd, v_now
  );

  for i in 1 .. v_n loop
    insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay)
    select v_new, p_tags[i], d.so_luong from duc_tem d where d.tag_no = p_tags[i];
    update duc_tem set so_luong = 0, trang_thai = 'Đã gộp NG' where tag_no = p_tags[i];
  end loop;

  insert into cd_chuyen_cong_doan_log (
    id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
    lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan,
    nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan
  ) values (
    cd_next_transfer_id(), v_now, v_new, v_ma_sp, v_ten_sp, v_tong, v_tong, 0,
    array_to_string(v_lot, ', '), array_to_string(v_khu, ', '), array_to_string(v_nl, ', '),
    array_to_string(v_may, ', '), coalesce(v_ngay::text, ''), v_pos, v_pos,
    coalesce(nullif(trim(p_nguoi), ''), p_user), coalesce(nullif(trim(p_nguoi), ''), p_user),
    'Đã xác nhận chuyển công đoạn', to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
  );

  insert into bavia_gom_log (tag_moi, tags_goc, ma_sp, so_luong, nguoi, client_key)
  values (v_new, p_tags, v_ma_sp, v_tong, coalesce(nullif(trim(p_nguoi), ''), p_user), v_key);

  return jsonb_build_object('ok', true, 'tag_moi', v_new, 'so_luong', v_tong);
end;
$$;
revoke execute on function bavia_gom_ng_cho_sua(text[], text, text, text) from anon;
grant  execute on function bavia_gom_ng_cho_sua(text[], text, text, text) to authenticated;

create or replace function bavia_undo_gom_ng(p_id bigint, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_g bavia_gom_log%rowtype;
  v_tag text;
begin
  select * into v_g from bavia_gom_log where id = p_id for update;
  if not found then raise exception 'Không tìm thấy lần gom %', p_id; end if;
  if bavia_tem_da_dung(v_g.tag_moi) then
    raise exception 'Tem gộp % đã dùng ở bước sau — không undo được', v_g.tag_moi;
  end if;

  foreach v_tag in array v_g.tags_goc loop
    update duc_tem set
      so_luong = (select so_luong_lay from cd_tem_nguon where tag_no_moi = v_g.tag_moi and tag_no_nguon = v_tag),
      trang_thai = 'NG chờ sửa'
    where tag_no = v_tag;
  end loop;

  delete from cd_tem_nguon where tag_no_moi = v_g.tag_moi;
  delete from cd_chuyen_cong_doan_log where tag_no = v_g.tag_moi;
  delete from duc_tem where tag_no = v_g.tag_moi;
  delete from bavia_gom_log where id = p_id;

  return jsonb_build_object('ok', true, 'undo', p_id);
end;
$$;
revoke execute on function bavia_undo_gom_ng(bigint, text) from anon;
grant  execute on function bavia_undo_gom_ng(bigint, text) to authenticated;
