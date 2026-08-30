-- ============================================================================
-- Phase T26 — Bavia GĐ4: đối soát thùng + UNDO
--
--   - bavia_xu_ly.ten_tram          : lưu tên line (để undo trỏ đúng dòng báo cáo)
--   - bavia_xu_ly_ra               : tem THÀNH PHẨM của mỗi lần xử lý (để undo
--                                     biết cần gỡ tem nào)
--   - bavia_sua_log.tag_ra text[]  : tem OK do 1 lần sửa hàng tạo ra
--   - bavia_xu_ly_thung()  tạo lại : ghi thêm ten_tram + bavia_xu_ly_ra
--   - bavia_sua_hang()     tạo lại : ghi thêm tag_ra
--   - bavia_undo_xu_ly(p_id, p_user)      : hoàn tác 1 lần "Xử lý thùng"
--   - bavia_undo_sua_hang(p_id, p_user)   : hoàn tác 1 lần "Sửa hàng"
--
-- UNDO chỉ chạy được khi các tem thành phẩm CHƯA bị dùng tiếp (so_luong còn
-- nguyên, chưa làm nguồn cho tách/đóng-gói/xử-lý/sửa nào). Không thì báo lỗi,
-- phải sửa tay DB.
--
-- Chạy trong Supabase SQL Editor. Idempotent.
-- ============================================================================

alter table bavia_xu_ly   add column if not exists ten_tram text;
alter table bavia_sua_log add column if not exists tag_ra text[];

create table if not exists bavia_xu_ly_ra (
  id_xu_ly  bigint not null references bavia_xu_ly(id) on delete cascade,
  tag_moi   text not null,
  so_luong  numeric not null,
  loai      text not null check (loai in ('ok', 'ng_sua', 'ok_gop')),
  primary key (id_xu_ly, tag_moi)
);
alter table bavia_xu_ly_ra enable row level security;
drop policy if exists "public read" on bavia_xu_ly_ra;
create policy "public read" on bavia_xu_ly_ra for select using (true);

-- ── bavia_xu_ly_thung — tạo lại: + ten_tram + bavia_xu_ly_ra ───────────────
create or replace function bavia_xu_ly_thung(
  p_id_tram    text,
  p_tag_nguon  text[],
  p_ok         numeric,
  p_ng_phe     numeric,
  p_ng_sua     numeric,
  p_ng_ly_do   text,
  p_cach_dong  text,
  p_quy_cach   numeric,
  p_tag_gop    text,
  p_nguoi      text,
  p_user       text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_tram   cd_tram_hien_tai%rowtype;
  v_src    duc_tem%rowtype;
  v_ok     numeric := coalesce(p_ok, 0);
  v_phe    numeric := coalesce(p_ng_phe, 0);
  v_sua    numeric := coalesce(p_ng_sua, 0);
  v_can    numeric;
  v_avail  numeric := 0;
  v_n      int;
  v_rem    numeric[];
  v_lay    numeric[];
  v_phe_i  numeric[];
  v_sua_i  numeric[];
  v_ngay_moi date;
  v_lot text[] := '{}'; v_khu text[] := '{}'; v_nl text[] := '{}'; v_may text[] := '{}';
  v_ma_sp text; v_ten_sp text;
  v_pos text;
  v_out_qty numeric[] := '{}';
  v_out_tag text[]  := '{}';
  v_id_xu_ly bigint;
  v_now timestamptz := now();
  v_tag text; v_q numeric; v_take numeric; v_need numeric;
  i int; j int; k int;
  v_tems jsonb := '[]'::jsonb;
  v_static_lot text; v_static_khu text; v_static_nl text; v_static_may text;
  v_ng_sua_tag text;
  v_gop_ma text;
begin
  if v_ok < 0 or v_phe < 0 or v_sua < 0 then raise exception 'Số lượng không được âm'; end if;
  v_can := v_ok + v_phe + v_sua;
  if v_can <= 0 then raise exception 'Chưa nhập OK / NG phế / NG sửa'; end if;
  if p_tag_nguon is null or array_length(p_tag_nguon, 1) is null then raise exception 'Chưa quét thùng nguồn'; end if;
  if (select count(*) from unnest(p_tag_nguon)) <> (select count(distinct x) from unnest(p_tag_nguon) x) then
    raise exception 'Có thùng nguồn bị quét trùng';
  end if;
  if (v_phe > 0 or v_sua > 0) and coalesce(trim(p_ng_ly_do), '') = '' then
    raise exception 'Có NG — phải nhập lý do';
  end if;

  select * into v_tram from cd_tram_hien_tai where id_tram = p_id_tram for update;
  if not found then raise exception 'Không tìm thấy line %', p_id_tram; end if;

  v_n := array_length(p_tag_nguon, 1);
  v_rem   := array_fill(0::numeric, array[v_n]);
  v_lay   := array_fill(0::numeric, array[v_n]);
  v_phe_i := array_fill(0::numeric, array[v_n]);
  v_sua_i := array_fill(0::numeric, array[v_n]);

  for i in 1 .. v_n loop
    select * into v_src from duc_tem where tag_no = p_tag_nguon[i] for update;
    if not found then raise exception 'Không tìm thấy tem %', p_tag_nguon[i]; end if;
    if coalesce(v_src.so_luong, 0) <= 0 then raise exception 'Tem % đã hết số lượng', p_tag_nguon[i]; end if;
    if v_src.ma_sp is distinct from v_tram.ma_sp then
      raise exception 'Tem % (mã %) khác mã SP đang chạy của line (%)', p_tag_nguon[i], v_src.ma_sp, v_tram.ma_sp;
    end if;

    v_ma_sp := v_src.ma_sp; v_ten_sp := coalesce(v_src.ten_sp, v_ten_sp);
    if v_ngay_moi is null or (v_src.ngay is not null and v_src.ngay < v_ngay_moi) then v_ngay_moi := v_src.ngay; end if;
    if coalesce(v_src.lot,'')          <> '' and not (v_src.lot = any(v_lot)) then v_lot := array_append(v_lot, v_src.lot); end if;
    if coalesce(v_src.so_khuon,'')     <> '' and not (v_src.so_khuon = any(v_khu)) then v_khu := array_append(v_khu, v_src.so_khuon); end if;
    if coalesce(v_src.nguyen_lieu,'')  <> '' and not (v_src.nguyen_lieu = any(v_nl)) then v_nl := array_append(v_nl, v_src.nguyen_lieu); end if;
    if coalesce(v_src.may_duc_chi_thi,'') <> '' and not (v_src.may_duc_chi_thi = any(v_may)) then v_may := array_append(v_may, v_src.may_duc_chi_thi); end if;

    v_rem[i] := v_src.so_luong;
    v_avail := v_avail + v_src.so_luong;

    select vi_tri_hien_tai into v_pos from cd_v_vi_tri_hien_tai where tag_no = p_tag_nguon[i];
    if v_pos is distinct from v_tram.cong_doan then
      insert into cd_chuyen_cong_doan_log (
        id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
        lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan,
        nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan
      ) values (
        cd_next_transfer_id(), v_now, p_tag_nguon[i], v_src.ma_sp, v_src.ten_sp, v_src.so_luong, v_src.so_luong, 0,
        v_src.lot, v_src.so_khuon, v_src.nguyen_lieu, v_src.may_duc_chi_thi, coalesce(v_src.ngay::text, ''),
        coalesce(v_pos, 'Đúc'), v_tram.cong_doan,
        coalesce(nullif(trim(p_nguoi), ''), p_user), coalesce(nullif(trim(p_nguoi), ''), p_user),
        'Đã xác nhận chuyển công đoạn', to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
      );
    end if;
  end loop;

  if v_can > v_avail then
    raise exception 'OK + NG (%) vượt tổng SL thùng nguồn còn lại (%)', v_can, v_avail;
  end if;

  v_static_lot := array_to_string(v_lot, ', ');
  v_static_khu := array_to_string(v_khu, ', ');
  v_static_nl  := array_to_string(v_nl, ', ');
  v_static_may := array_to_string(v_may, ', ');

  insert into bavia_xu_ly (id_tram, ten_tram, ngay, ca, cong_doan, ma_sp, tong_ok, tong_ng_phe, tong_ng_sua, ng_ly_do, nguoi)
  values (p_id_tram, v_tram.ten_tram, v_tram.ngay, v_tram.ca, v_tram.cong_doan, v_ma_sp, v_ok, v_phe, v_sua,
          nullif(trim(p_ng_ly_do), ''), coalesce(nullif(trim(p_nguoi), ''), p_user))
  returning id into v_id_xu_ly;

  if v_ok > 0 then
    if p_cach_dong = 'gop' then
      if coalesce(trim(p_tag_gop), '') = '' then raise exception 'Chọn "gộp" thì phải chọn thùng đích'; end if;
      select ma_sp into v_gop_ma from duc_tem where tag_no = p_tag_gop for update;
      if not found then raise exception 'Không tìm thấy thùng gộp %', p_tag_gop; end if;
      if v_gop_ma is distinct from v_ma_sp then raise exception 'Thùng gộp % khác mã SP', p_tag_gop; end if;
      v_out_qty := array[v_ok];
      v_out_tag := array[p_tag_gop];
    elsif p_cach_dong = 'quy_cach' then
      if coalesce(p_quy_cach, 0) <= 0 then raise exception 'Quy cách (pcs/thùng) không hợp lệ'; end if;
      v_need := v_ok;
      while v_need > 0 loop
        v_q := least(v_need, p_quy_cach);
        v_out_qty := array_append(v_out_qty, v_q);
        v_out_tag := array_append(v_out_tag, bavia_next_tag_no());
        v_need := v_need - v_q;
      end loop;
    else
      v_out_qty := array[v_ok];
      v_out_tag := array[bavia_next_tag_no()];
    end if;

    if p_cach_dong <> 'gop' then
      for j in 1 .. array_length(v_out_tag, 1) loop
        insert into duc_tem (
          tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
          may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
          nguoi_tt, trang_thai, ghi_chu_sl, tram_cong_doan, thoi_diem_san_xuat
        ) values (
          v_out_tag[j], v_ten_sp, v_ma_sp, v_out_qty[j], v_ngay_moi,
          v_static_lot, v_static_khu, v_static_nl, v_static_may,
          'Bavia xử lý thùng tại ' || v_tram.cong_doan, v_now, v_static_khu, v_out_qty[j], v_static_may,
          coalesce(nullif(trim(p_nguoi), ''), p_user), 'Bavia', 'Bavia xử lý từ ' || array_to_string(p_tag_nguon, ', '),
          v_tram.ten_tram, v_now
        );
        insert into bavia_xu_ly_ra (id_xu_ly, tag_moi, so_luong, loai) values (v_id_xu_ly, v_out_tag[j], v_out_qty[j], 'ok');
      end loop;
    else
      insert into bavia_xu_ly_ra (id_xu_ly, tag_moi, so_luong, loai) values (v_id_xu_ly, p_tag_gop, v_ok, 'ok_gop');
    end if;
  end if;

  if v_sua > 0 then
    v_ng_sua_tag := bavia_next_tag_no();
    insert into duc_tem (
      tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
      may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
      nguoi_tt, trang_thai, ghi_chu_sl, tram_cong_doan, thoi_diem_san_xuat
    ) values (
      v_ng_sua_tag, v_ten_sp, v_ma_sp, v_sua, v_ngay_moi,
      v_static_lot, v_static_khu, v_static_nl, v_static_may,
      'NG chờ sửa (Bavia) — ' || coalesce(trim(p_ng_ly_do), ''), v_now, v_static_khu, v_sua, v_static_may,
      coalesce(nullif(trim(p_nguoi), ''), p_user), 'NG chờ sửa', 'Bavia xử lý từ ' || array_to_string(p_tag_nguon, ', '),
      v_tram.ten_tram, v_now
    );
    insert into bavia_xu_ly_ra (id_xu_ly, tag_moi, so_luong, loai) values (v_id_xu_ly, v_ng_sua_tag, v_sua, 'ng_sua');
    v_out_tag := array_append(v_out_tag, v_ng_sua_tag);
    v_out_qty := array_append(v_out_qty, 0::numeric);
  end if;

  k := 1;

  if v_ok > 0 then
    for j in 1 .. (case when p_cach_dong = 'gop' then 1 else array_length(v_out_qty, 1) end) loop
      exit when v_out_qty[j] is null;
      v_need := v_out_qty[j];
      continue when v_need = 0;
      while v_need > 0 loop
        if k > v_n then raise exception 'Lỗi phân bổ nguồn (OK)'; end if;
        if v_rem[k] > 0 then
          v_take := least(v_need, v_rem[k]);
          v_rem[k] := v_rem[k] - v_take; v_lay[k] := v_lay[k] + v_take; v_need := v_need - v_take;
          insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay)
          values (v_out_tag[j], p_tag_nguon[k], v_take)
          on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
        end if;
        if v_rem[k] <= 0 then k := k + 1; end if;
      end loop;
    end loop;
    if p_cach_dong = 'gop' then
      update duc_tem set so_luong = coalesce(so_luong, 0) + v_ok where tag_no = p_tag_gop;
    end if;
  end if;

  if v_sua > 0 then
    v_tag := v_ng_sua_tag;
    v_need := v_sua;
    while v_need > 0 loop
      if k > v_n then raise exception 'Lỗi phân bổ nguồn (NG sửa)'; end if;
      if v_rem[k] > 0 then
        v_take := least(v_need, v_rem[k]);
        v_rem[k] := v_rem[k] - v_take; v_lay[k] := v_lay[k] + v_take; v_sua_i[k] := v_sua_i[k] + v_take; v_need := v_need - v_take;
        insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay)
        values (v_tag, p_tag_nguon[k], v_take)
        on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
      end if;
      if v_rem[k] <= 0 then k := k + 1; end if;
    end loop;
  end if;

  if v_phe > 0 then
    v_need := v_phe;
    while v_need > 0 loop
      if k > v_n then raise exception 'Lỗi phân bổ nguồn (NG phế)'; end if;
      if v_rem[k] > 0 then
        v_take := least(v_need, v_rem[k]);
        v_rem[k] := v_rem[k] - v_take; v_lay[k] := v_lay[k] + v_take; v_phe_i[k] := v_phe_i[k] + v_take; v_need := v_need - v_take;
      end if;
      if v_rem[k] <= 0 then k := k + 1; end if;
    end loop;
  end if;

  for i in 1 .. v_n loop
    update duc_tem set so_luong = v_rem[i] where tag_no = p_tag_nguon[i];
    if v_lay[i] > 0 then
      insert into bavia_xu_ly_nguon (id_xu_ly, tag_no_nguon, sl_lay, sl_ng_phe, sl_ng_sua)
      values (v_id_xu_ly, p_tag_nguon[i], v_lay[i], v_phe_i[i], v_sua_i[i]);
    end if;
  end loop;

  if array_length(v_out_tag, 1) is not null then
    for j in 1 .. array_length(v_out_tag, 1) loop
      if p_cach_dong = 'gop' and v_out_tag[j] = p_tag_gop then continue; end if;
      insert into cd_chuyen_cong_doan_log (
        id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
        lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan,
        nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan
      )
      select cd_next_transfer_id(), v_now, v_out_tag[j], v_ma_sp, v_ten_sp, t.so_luong, t.so_luong, 0,
        v_static_lot, v_static_khu, v_static_nl, v_static_may, coalesce(v_ngay_moi::text, ''),
        v_tram.cong_doan, v_tram.cong_doan,
        coalesce(nullif(trim(p_nguoi), ''), p_user), coalesce(nullif(trim(p_nguoi), ''), p_user),
        'Đã xác nhận chuyển công đoạn', to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
      from duc_tem t where t.tag_no = v_out_tag[j];
    end loop;
  end if;

  update cd_tram_hien_tai set
    so_luong_ok     = so_luong_ok + v_ok,
    so_luong_ng     = so_luong_ng + v_phe,
    so_luong_ng_sua = coalesce(so_luong_ng_sua, 0) + v_sua,
    ghi_chu = coalesce(nullif(ghi_chu, ''), '') ||
              (case when coalesce(ghi_chu, '') <> '' then E'\n' else '' end) ||
              '[' || to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM HH24:MI') || '] Xử lý thùng: OK ' || v_ok ||
              (case when v_phe > 0 then ', NG phế ' || v_phe else '' end) ||
              (case when v_sua > 0 then ', NG sửa ' || v_sua else '' end),
    version = version + 1, last_updated_by = p_user, last_updated_at = now()
  where id_tram = p_id_tram;

  if array_length(v_out_tag, 1) is not null then
    for j in 1 .. array_length(v_out_tag, 1) loop
      if p_cach_dong = 'gop' and v_out_tag[j] = p_tag_gop then
        v_tems := v_tems || jsonb_build_object('tag', p_tag_gop, 'so_luong', v_ok, 'loai', 'ok_gop');
      else
        v_tems := v_tems || (
          select jsonb_build_object('tag', t.tag_no, 'so_luong', t.so_luong,
                   'loai', case when t.trang_thai = 'NG chờ sửa' then 'ng_sua' else 'ok' end)
          from duc_tem t where t.tag_no = v_out_tag[j]
        );
      end if;
    end loop;
  end if;

  return jsonb_build_object('ok', true, 'id_xu_ly', v_id_xu_ly, 'tems', v_tems, 'tong_lay', v_ok + v_phe + v_sua);
end;
$$;
revoke execute on function bavia_xu_ly_thung(text, text[], numeric, numeric, numeric, text, text, numeric, text, text, text) from anon;
grant  execute on function bavia_xu_ly_thung(text, text[], numeric, numeric, numeric, text, text, numeric, text, text, text) to authenticated;

-- ── bavia_sua_hang — tạo lại: + tag_ra ────────────────────────────────────
create or replace function bavia_sua_hang(
  p_tag_ng text, p_ngay date, p_ca text, p_cong_doan text,
  p_ok numeric, p_ng_phe numeric, p_ng_ly_do text,
  p_cach_dong text, p_quy_cach numeric, p_tag_gop text,
  p_nguoi text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_t     duc_tem%rowtype;
  v_gop   duc_tem%rowtype;
  v_ok    numeric := coalesce(p_ok, 0);
  v_phe   numeric := coalesce(p_ng_phe, 0);
  v_can   numeric;
  v_out_tag text[] := '{}';
  v_out_qty numeric[] := '{}';
  v_tag text; v_need numeric; v_q numeric;
  j int;
  v_tems jsonb := '[]'::jsonb;
  v_lot text; v_khu text; v_nl text; v_may text; v_ngay date; v_ten_sp text; v_ma_sp text;
  v_now timestamptz := now();
  v_ra text[] := '{}';
begin
  if v_ok < 0 or v_phe < 0 then raise exception 'Số lượng không được âm'; end if;
  v_can := v_ok + v_phe;
  if v_can <= 0 then raise exception 'Chưa nhập OK / NG phế'; end if;
  if p_ngay is null or coalesce(trim(p_ca), '') = '' or coalesce(trim(p_cong_doan), '') = '' then
    raise exception 'Thiếu ngày / ca / công đoạn';
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
        v_out_tag := array[bavia_next_tag_no()];
        v_out_qty := array[v_ok];
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
    p_ngay, p_ca, p_cong_doan, v_ma_sp, v_ten_sp, coalesce(v_t.tram_cong_doan, ''),
    v_ok, v_phe, 'Sửa hàng từ ' || p_tag_ng || case when coalesce(trim(p_ng_ly_do),'') <> '' then ' — ' || trim(p_ng_ly_do) else '' end,
    -(v_ok + v_phe)
  );

  insert into bavia_sua_log (tag_ng, ngay, ca, cong_doan, ma_sp, so_ok, so_ng_phe, ly_do, nguoi, tag_ra)
  values (p_tag_ng, p_ngay, p_ca, p_cong_doan, v_ma_sp, v_ok, v_phe, nullif(trim(p_ng_ly_do), ''),
          coalesce(nullif(trim(p_nguoi), ''), p_user), case when array_length(v_ra,1) is null then null else v_ra end);

  return jsonb_build_object('ok', true, 'tems', v_tems, 'con_lai_tem_ng', greatest(0, coalesce(v_t.so_luong, 0) - v_can));
end;
$$;
revoke execute on function bavia_sua_hang(text, date, text, text, numeric, numeric, text, text, numeric, text, text, text) from anon;
grant  execute on function bavia_sua_hang(text, date, text, text, numeric, numeric, text, text, numeric, text, text, text) to authenticated;

-- ── Helper: 1 tem đã bị "dùng tiếp" chưa ─────────────────────────────────
create or replace function bavia_tem_da_dung(p_tag text)
returns boolean
language sql
stable
as $$
  select exists(select 1 from cd_tem_nguon where tag_no_nguon = p_tag)
      or exists(select 1 from duc_tem_tach   where tag_no_cha  = p_tag)
      or exists(select 1 from bavia_xu_ly_nguon where tag_no_nguon = p_tag)
      or exists(select 1 from bavia_sua_log where tag_ng = p_tag);
$$;

-- ── bavia_undo_xu_ly ─────────────────────────────────────────────────────
create or replace function bavia_undo_xu_ly(p_id bigint, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_e   bavia_xu_ly%rowtype;
  v_ra  bavia_xu_ly_ra%rowtype;
  v_bn  bavia_xu_ly_nguon%rowtype;
  v_cur duc_tem%rowtype;
  v_tram_ton boolean;
begin
  select * into v_e from bavia_xu_ly where id = p_id for update;
  if not found then raise exception 'Không tìm thấy lần xử lý %', p_id; end if;

  -- Kiểm: mọi tem thành phẩm phải còn nguyên & chưa bị dùng tiếp
  for v_ra in select * from bavia_xu_ly_ra where id_xu_ly = p_id loop
    select * into v_cur from duc_tem where tag_no = v_ra.tag_moi for update;
    if v_ra.loai = 'ok_gop' then
      if not found or coalesce(v_cur.so_luong, 0) < v_ra.so_luong then
        raise exception 'Thùng gộp % đã bị dùng bớt — không undo được', v_ra.tag_moi;
      end if;
    else
      if not found then raise exception 'Tem % không còn — không undo được', v_ra.tag_moi; end if;
      if coalesce(v_cur.so_luong, 0) <> v_ra.so_luong then
        raise exception 'Tem % đã đổi số lượng (còn %) — không undo được', v_ra.tag_moi, v_cur.so_luong;
      end if;
      if bavia_tem_da_dung(v_ra.tag_moi) then
        raise exception 'Tem % đã được dùng ở bước sau — không undo được', v_ra.tag_moi;
      end if;
    end if;
  end loop;

  -- Gỡ tem thành phẩm
  for v_ra in select * from bavia_xu_ly_ra where id_xu_ly = p_id loop
    if v_ra.loai = 'ok_gop' then
      update duc_tem set so_luong = so_luong - v_ra.so_luong where tag_no = v_ra.tag_moi;
      -- Trừ phần góp của LẦN NÀY khỏi phả hệ (không xoá cả dòng — nguồn có thể góp ở lần khác)
      for v_bn in select * from bavia_xu_ly_nguon where id_xu_ly = p_id loop
        update cd_tem_nguon set so_luong_lay = so_luong_lay - (v_bn.sl_lay - v_bn.sl_ng_phe - v_bn.sl_ng_sua)
          where tag_no_moi = v_ra.tag_moi and tag_no_nguon = v_bn.tag_no_nguon;
        delete from cd_tem_nguon where tag_no_moi = v_ra.tag_moi and tag_no_nguon = v_bn.tag_no_nguon and so_luong_lay <= 0;
      end loop;
    else
      delete from cd_tem_nguon where tag_no_moi = v_ra.tag_moi;
      delete from cd_chuyen_cong_doan_log where tag_no = v_ra.tag_moi;
      delete from duc_tem where tag_no = v_ra.tag_moi;
    end if;
  end loop;

  -- Trả SL về thùng nguồn
  for v_bn in select * from bavia_xu_ly_nguon where id_xu_ly = p_id loop
    update duc_tem set so_luong = coalesce(so_luong, 0) + v_bn.sl_lay where tag_no = v_bn.tag_no_nguon;
  end loop;

  -- Trừ lại sản lượng: line còn thì trừ trên line, không thì trừ ở báo cáo
  select exists(select 1 from cd_tram_hien_tai where id_tram = v_e.id_tram) into v_tram_ton;
  if v_tram_ton then
    update cd_tram_hien_tai set
      so_luong_ok     = so_luong_ok - v_e.tong_ok,
      so_luong_ng     = so_luong_ng - v_e.tong_ng_phe,
      so_luong_ng_sua = coalesce(so_luong_ng_sua, 0) - v_e.tong_ng_sua,
      version = version + 1, last_updated_by = p_user, last_updated_at = now()
    where id_tram = v_e.id_tram;
  else
    perform cd_gop_tally_vao_bao_cao(v_e.ngay, v_e.ca, v_e.cong_doan, v_e.ma_sp, null, coalesce(v_e.ten_tram, ''),
      -v_e.tong_ok, -v_e.tong_ng_phe, 'UNDO xử lý thùng #' || p_id, -v_e.tong_ng_sua);
  end if;

  delete from bavia_xu_ly where id = p_id;   -- cascade: nguon + ra

  return jsonb_build_object('ok', true, 'undo', p_id);
end;
$$;
revoke execute on function bavia_undo_xu_ly(bigint, text) from anon;
grant  execute on function bavia_undo_xu_ly(bigint, text) to authenticated;

-- ── bavia_undo_sua_hang ─────────────────────────────────────────────────
create or replace function bavia_undo_sua_hang(p_id bigint, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_s   bavia_sua_log%rowtype;
  v_tag text;
  v_cur duc_tem%rowtype;
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

  -- Trả SL về tem NG + khôi phục trạng thái
  update duc_tem set
    so_luong = coalesce(so_luong, 0) + (v_s.so_ok + v_s.so_ng_phe),
    trang_thai = 'NG chờ sửa'
  where tag_no = v_s.tag_ng;

  -- Đảo ghi nhận báo cáo
  perform cd_gop_tally_vao_bao_cao(v_s.ngay, v_s.ca, v_s.cong_doan, v_s.ma_sp, null, '',
    -v_s.so_ok, -v_s.so_ng_phe, 'UNDO sửa hàng #' || p_id, (v_s.so_ok + v_s.so_ng_phe));

  delete from bavia_sua_log where id = p_id;
  return jsonb_build_object('ok', true, 'undo', p_id);
end;
$$;
revoke execute on function bavia_undo_sua_hang(bigint, text) from anon;
grant  execute on function bavia_undo_sua_hang(bigint, text) to authenticated;

-- Kiểm tra nhanh
-- select * from bavia_xu_ly_ra where id_xu_ly = (select max(id) from bavia_xu_ly);
