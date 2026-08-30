-- ============================================================================
-- Phase T24 — Bavia xử lý theo thùng (giai đoạn 1)
--
-- Bavia nhận thùng từ Đúc (tem QR duc_tem), làm bavia rồi CHIA NHỎ / GỘP LẠI
-- thành các thùng thành phẩm Bavia (tem tiền tố TKB), khai OK / NG phế / NG sửa.
--
-- Thêm:
--   - bavia_xu_ly       : 1 dòng / lần "Xử lý thùng" (header, audit + suy "đang dở")
--   - bavia_xu_ly_nguon : chi tiết mỗi thùng nguồn góp bao nhiêu (OK / NG phế / NG sửa)
--   - cd_tram_hien_tai.so_luong_ng_sua, cd_bao_cao_ca.so_luong_ng_sua
--   - bavia_next_tag_no()  → 'TKB{yyyyMMdd}-{seq}'
--   - bavia_xu_ly_thung()  → tạo tem TKB + phả hệ (cd_tem_nguon) + cộng line, 1 giao dịch
--
-- Sửa để mang NG sửa qua báo cáo (DROP/tạo lại vì đổi identity):
--   - cd_gop_tally_vao_bao_cao(+ p_ng_sua)
--   - cd_ket_ca_cong_doan   (+ cột so_luong_ng_sua ở RETURNS TABLE)
--   - cd_tram_doi_ma_sp / cd_tram_ket_thuc (CREATE OR REPLACE, đọc thêm cột row)
--
-- KHÔNG đụng cd_dong_goi_lai (Gia Công/Sơn/OQC vẫn dùng), cd_tram_nhap_sanluong,
-- cd_tram_tao.
--
-- Chạy trong Supabase SQL Editor. Idempotent.
-- ============================================================================

alter table cd_tram_hien_tai add column if not exists so_luong_ng_sua numeric default 0;
alter table cd_bao_cao_ca    add column if not exists so_luong_ng_sua numeric default 0;

create table if not exists bavia_xu_ly (
  id            bigserial primary key,
  id_tram       text references cd_tram_hien_tai(id_tram) on delete set null,
  ngay          date not null,
  ca            text not null,
  cong_doan     text not null,
  ma_sp         text not null,
  tong_ok       numeric not null default 0,
  tong_ng_phe   numeric not null default 0,
  tong_ng_sua   numeric not null default 0,
  ng_ly_do      text,
  nguoi         text,
  thoi_diem     timestamptz not null default now()
);
create index if not exists idx_bavia_xu_ly_loc on bavia_xu_ly (cong_doan, ngay, ca);

create table if not exists bavia_xu_ly_nguon (
  id_xu_ly      bigint not null references bavia_xu_ly(id) on delete cascade,
  tag_no_nguon  text not null references duc_tem(tag_no),
  sl_lay        numeric not null default 0,   -- tổng lấy khỏi thùng nguồn này
  sl_ng_phe     numeric not null default 0,
  sl_ng_sua     numeric not null default 0,   -- sl_ok = sl_lay - sl_ng_phe - sl_ng_sua
  primary key (id_xu_ly, tag_no_nguon)
);
create index if not exists idx_bavia_xu_ly_nguon_tag on bavia_xu_ly_nguon (tag_no_nguon);

alter table bavia_xu_ly       enable row level security;
alter table bavia_xu_ly_nguon enable row level security;
drop policy if exists "public read" on bavia_xu_ly;
drop policy if exists "public read" on bavia_xu_ly_nguon;
create policy "public read" on bavia_xu_ly       for select using (true);
create policy "public read" on bavia_xu_ly_nguon for select using (true);

-- ── Sinh Tag No thùng Bavia — prefix TKB ───────────────────────────────────
create or replace function bavia_next_tag_no()
returns text
language plpgsql
security definer
as $$
declare
  d date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  key text := 'TKB' || to_char(d, 'YYYYMMDD');
  next_seq int;
begin
  insert into duc_tag_no_counter (prefix_ngay, last_seq) values (key, 1)
  on conflict (prefix_ngay) do update set last_seq = duc_tag_no_counter.last_seq + 1
  returning last_seq into next_seq;
  return key || '-' || lpad(next_seq::text, 4, '0');
end;
$$;
revoke execute on function bavia_next_tag_no() from anon;
grant  execute on function bavia_next_tag_no() to authenticated;

-- ── cd_gop_tally_vao_bao_cao (+ p_ng_sua) ──────────────────────────────────
drop function if exists cd_gop_tally_vao_bao_cao(date, text, text, text, text, text, numeric, numeric, text);
create or replace function cd_gop_tally_vao_bao_cao(
  p_ngay date, p_ca text, p_cong_doan text, p_ma_sp text, p_ten_sp text, p_to text,
  p_ok numeric, p_ng numeric, p_ghi_chu text, p_ng_sua numeric default 0
)
returns void
language plpgsql
security definer
as $$
declare
  v_id text;
  v_stamp text;
  v_note text;
  v_ng_sua numeric := coalesce(p_ng_sua, 0);
begin
  v_id := to_char(p_ngay, 'DDMMYYYY') || '_' || duc_normalize_name(p_ca) || '_' || duc_normalize_name(p_cong_doan) || '_' || duc_normalize_name(p_ma_sp) ||
    case when coalesce(p_to, '') <> '' then '_' || duc_normalize_name(p_to) else '' end;
  v_stamp := to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DD/MM HH24:MI');
  v_note := case when coalesce(p_ghi_chu, '') <> '' then '[' || v_stamp || '] ' || trim(p_ghi_chu) else null end;

  insert into cd_bao_cao_ca (
    id_bao_cao, ngay, ca, cong_doan, ma_sp, ten_sp, to_san_xuat,
    so_luong_nhan_vao, so_luong_ok, so_luong_ng, so_luong_ng_sua, ghi_chu, thoi_diem_luu
  ) values (
    v_id, p_ngay, p_ca, p_cong_doan, p_ma_sp, coalesce(p_ten_sp, ''), coalesce(p_to, ''),
    coalesce(p_ok, 0) + coalesce(p_ng, 0) + v_ng_sua, coalesce(p_ok, 0), coalesce(p_ng, 0), v_ng_sua, v_note, now()
  )
  on conflict (id_bao_cao) do update set
    so_luong_nhan_vao = cd_bao_cao_ca.so_luong_nhan_vao + excluded.so_luong_nhan_vao,
    so_luong_ok       = cd_bao_cao_ca.so_luong_ok + excluded.so_luong_ok,
    so_luong_ng       = cd_bao_cao_ca.so_luong_ng + excluded.so_luong_ng,
    so_luong_ng_sua   = coalesce(cd_bao_cao_ca.so_luong_ng_sua, 0) + excluded.so_luong_ng_sua,
    ten_sp = coalesce(nullif(excluded.ten_sp, ''), cd_bao_cao_ca.ten_sp),
    ghi_chu = case when v_note is null then cd_bao_cao_ca.ghi_chu
                   when coalesce(cd_bao_cao_ca.ghi_chu, '') = '' then v_note
                   else cd_bao_cao_ca.ghi_chu || E'\n' || v_note end,
    thoi_diem_luu = now();
end;
$$;
revoke execute on function cd_gop_tally_vao_bao_cao(date, text, text, text, text, text, numeric, numeric, text, numeric) from anon;
grant  execute on function cd_gop_tally_vao_bao_cao(date, text, text, text, text, text, numeric, numeric, text, numeric) to authenticated;

-- ── cd_tram_doi_ma_sp — gộp thêm so_luong_ng_sua, reset về 0 ────────────────
create or replace function cd_tram_doi_ma_sp(
  p_id_tram text, p_ma_sp_moi text, p_ten_sp_moi text, p_kh_ca_moi numeric, p_kh_tuan_moi numeric, p_nguoi_moi text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row cd_tram_hien_tai%rowtype;
begin
  if p_ma_sp_moi is null or trim(p_ma_sp_moi) = '' then raise exception 'Thiếu mã SP mới'; end if;

  select * into v_row from cd_tram_hien_tai where id_tram = p_id_tram for update;
  if not found then raise exception 'Không tìm thấy: %', p_id_tram; end if;

  if coalesce(v_row.so_luong_ok, 0) > 0 or coalesce(v_row.so_luong_ng, 0) > 0 or coalesce(v_row.so_luong_ng_sua, 0) > 0 then
    perform cd_gop_tally_vao_bao_cao(v_row.ngay, v_row.ca, v_row.cong_doan, v_row.ma_sp, v_row.ten_sp, v_row.ten_tram,
      v_row.so_luong_ok, v_row.so_luong_ng, v_row.ghi_chu, coalesce(v_row.so_luong_ng_sua, 0));
  end if;

  update cd_tram_hien_tai set
    ma_sp = p_ma_sp_moi, ten_sp = coalesce(p_ten_sp_moi, ''), kh_ca = p_kh_ca_moi, kh_tuan = p_kh_tuan_moi,
    nguoi_thao_tac = coalesce(nullif(p_nguoi_moi, ''), nguoi_thao_tac),
    so_luong_ok = 0, so_luong_ng = 0, so_luong_ng_sua = 0, ghi_chu = '',
    version = version + 1, last_updated_by = p_user, last_updated_at = now()
  where id_tram = p_id_tram;

  return jsonb_build_object('ok', true, 'id_tram', p_id_tram);
end;
$$;

-- ── cd_tram_ket_thuc — gộp thêm so_luong_ng_sua ────────────────────────────
create or replace function cd_tram_ket_thuc(p_id_tram text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row cd_tram_hien_tai%rowtype;
begin
  select * into v_row from cd_tram_hien_tai where id_tram = p_id_tram for update;
  if not found then raise exception 'Không tìm thấy trạm %', p_id_tram; end if;

  if coalesce(v_row.so_luong_ok, 0) > 0 or coalesce(v_row.so_luong_ng, 0) > 0 or coalesce(v_row.so_luong_ng_sua, 0) > 0 then
    perform cd_gop_tally_vao_bao_cao(v_row.ngay, v_row.ca, v_row.cong_doan, v_row.ma_sp, v_row.ten_sp, v_row.ten_tram,
      v_row.so_luong_ok, v_row.so_luong_ng, v_row.ghi_chu, coalesce(v_row.so_luong_ng_sua, 0));
  end if;

  delete from cd_tram_hien_tai where id_tram = p_id_tram;
  return jsonb_build_object('ok', true);
end;
$$;

-- ── cd_ket_ca_cong_doan — thêm cột so_luong_ng_sua ─────────────────────────
drop function if exists cd_ket_ca_cong_doan(date, text, text, text);
create or replace function cd_ket_ca_cong_doan(p_ngay date, p_ca text, p_cong_doan text, p_user text)
returns table(ma_sp text, ten_sp text, so_luong_nhan_vao numeric, so_luong_ok numeric, so_luong_ng numeric, so_luong_ng_sua numeric)
language plpgsql
security definer
as $$
declare
  v_tram cd_tram_hien_tai%rowtype;
begin
  for v_tram in select * from cd_tram_hien_tai where ngay = p_ngay and ca = p_ca and cong_doan = p_cong_doan loop
    if coalesce(v_tram.so_luong_ok, 0) > 0 or coalesce(v_tram.so_luong_ng, 0) > 0 or coalesce(v_tram.so_luong_ng_sua, 0) > 0 then
      perform cd_gop_tally_vao_bao_cao(v_tram.ngay, v_tram.ca, v_tram.cong_doan, v_tram.ma_sp, v_tram.ten_sp, v_tram.ten_tram,
        v_tram.so_luong_ok, v_tram.so_luong_ng, v_tram.ghi_chu, coalesce(v_tram.so_luong_ng_sua, 0));
    end if;
  end loop;

  delete from cd_tram_hien_tai where ngay = p_ngay and ca = p_ca and cong_doan = p_cong_doan;

  return query
    select b.ma_sp, max(b.ten_sp), sum(b.so_luong_nhan_vao), sum(b.so_luong_ok), sum(b.so_luong_ng), sum(coalesce(b.so_luong_ng_sua, 0))
    from cd_bao_cao_ca b
    where b.ngay = p_ngay and b.ca = p_ca and b.cong_doan = p_cong_doan
    group by b.ma_sp
    order by b.ma_sp;
end;
$$;
revoke execute on function cd_ket_ca_cong_doan(date, text, text, text) from anon;
grant  execute on function cd_ket_ca_cong_doan(date, text, text, text) to authenticated;

-- ── bavia_xu_ly_thung — lõi giai đoạn 1 ────────────────────────────────────
create or replace function bavia_xu_ly_thung(
  p_id_tram    text,
  p_tag_nguon  text[],
  p_ok         numeric,
  p_ng_phe     numeric,
  p_ng_sua     numeric,
  p_ng_ly_do   text,
  p_cach_dong  text,          -- 'nguyen' | 'quy_cach' | 'gop'
  p_quy_cach   numeric,       -- bắt buộc khi 'quy_cach'
  p_tag_gop    text,          -- bắt buộc khi 'gop'
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
  v_rem    numeric[];           -- SL còn lấy được của từng nguồn
  v_lay    numeric[];           -- tổng đã lấy khỏi từng nguồn (audit)
  v_phe_i  numeric[];
  v_sua_i  numeric[];
  v_ngay_moi date;
  v_lot text[] := '{}'; v_khu text[] := '{}'; v_nl text[] := '{}'; v_may text[] := '{}';
  v_ma_sp text; v_ten_sp text;
  v_pos text;
  v_out_qty numeric[] := '{}'; -- SL từng thùng OK mới cần tạo
  v_out_tag text[]  := '{}';
  v_id_xu_ly bigint;
  v_now timestamptz := now();
  v_tag text; v_q numeric; v_take numeric; v_need numeric;
  i int; j int; k int;
  v_tems jsonb := '[]'::jsonb;
  v_static_lot text; v_static_khu text; v_static_nl text; v_static_may text;
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

    -- Đảm bảo thùng đã "về" công đoạn này (để cd_v_vi_tri_hien_tai đúng)
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

  insert into bavia_xu_ly (id_tram, ngay, ca, cong_doan, ma_sp, tong_ok, tong_ng_phe, tong_ng_sua, ng_ly_do, nguoi)
  values (p_id_tram, v_tram.ngay, v_tram.ca, v_tram.cong_doan, v_ma_sp, v_ok, v_phe, v_sua, nullif(trim(p_ng_ly_do), ''),
          coalesce(nullif(trim(p_nguoi), ''), p_user))
  returning id into v_id_xu_ly;

  -- ── Danh sách thùng OK cần tạo (hoặc gộp) ────────────────────────────────
  if v_ok > 0 then
    if p_cach_dong = 'gop' then
      if coalesce(trim(p_tag_gop), '') = '' then raise exception 'Chọn "gộp" thì phải chọn thùng đích'; end if;
      perform 1 from duc_tem where tag_no = p_tag_gop for update;
      if not found then raise exception 'Không tìm thấy thùng gộp %', p_tag_gop; end if;
      v_out_qty := array[v_ok];
      v_out_tag := array[p_tag_gop];
    elsif p_cach_dong = 'quy_cach' then
      if coalesce(p_quy_cach, 0) <= 0 then raise exception 'Quy cách (pcs/thùng) không hợp lệ'; end if;
      v_need := v_ok;
      while v_need > 0 loop
        v_q := least(v_need, p_quy_cach);
        v_tag := bavia_next_tag_no();
        v_out_qty := array_append(v_out_qty, v_q);
        v_out_tag := array_append(v_out_tag, v_tag);
        v_need := v_need - v_q;
      end loop;
    else  -- 'nguyen'
      v_tag := bavia_next_tag_no();
      v_out_qty := array[v_ok];
      v_out_tag := array[v_tag];
    end if;

    -- Tạo tem TKB cho các thùng "nguyen"/"quy_cach" (gộp thì thùng đã có sẵn)
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
      end loop;
    end if;
  end if;

  -- Tem NG chờ sửa (1 thùng gom)
  if v_sua > 0 then
    v_tag := bavia_next_tag_no();
    insert into duc_tem (
      tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
      may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
      nguoi_tt, trang_thai, ghi_chu_sl, tram_cong_doan, thoi_diem_san_xuat
    ) values (
      v_tag, v_ten_sp, v_ma_sp, v_sua, v_ngay_moi,
      v_static_lot, v_static_khu, v_static_nl, v_static_may,
      'NG chờ sửa (Bavia) — ' || coalesce(trim(p_ng_ly_do), ''), v_now, v_static_khu, v_sua, v_static_may,
      coalesce(nullif(trim(p_nguoi), ''), p_user), 'NG chờ sửa', 'Bavia xử lý từ ' || array_to_string(p_tag_nguon, ', '),
      v_tram.ten_tram, v_now
    );
    v_out_tag := array_append(v_out_tag, v_tag);
    v_out_qty := array_append(v_out_qty, 0::numeric);  -- không phân bổ như OK (xử lý riêng bên dưới)
  end if;

  -- ── Phân bổ FIFO: OK trước → NG sửa → NG phế ────────────────────────────
  k := 1;  -- con trỏ nguồn hiện tại

  -- OK: từng thùng OK (gồm cả 'gop')
  if v_ok > 0 then
    for j in 1 .. (case when p_cach_dong = 'gop' then 1 else array_length(v_out_qty, 1) end) loop
      exit when v_out_qty[j] is null;
      v_need := v_out_qty[j];
      -- với NG-sửa được append cuối mảng out với qty 0 → bỏ qua ở nhánh này
      continue when v_need = 0;
      while v_need > 0 loop
        if k > v_n then raise exception 'Lỗi phân bổ nguồn (OK)'; end if;
        if v_rem[k] > 0 then
          v_take := least(v_need, v_rem[k]);
          v_rem[k] := v_rem[k] - v_take;
          v_lay[k] := v_lay[k] + v_take;
          v_need := v_need - v_take;
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

  -- NG sửa: gắn phả hệ vào tem NG-sửa (tag cuối mảng out)
  if v_sua > 0 then
    v_tag := v_out_tag[array_length(v_out_tag, 1)];
    v_need := v_sua;
    while v_need > 0 loop
      if k > v_n then raise exception 'Lỗi phân bổ nguồn (NG sửa)'; end if;
      if v_rem[k] > 0 then
        v_take := least(v_need, v_rem[k]);
        v_rem[k] := v_rem[k] - v_take;
        v_lay[k] := v_lay[k] + v_take;
        v_sua_i[k] := v_sua_i[k] + v_take;
        v_need := v_need - v_take;
        insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay)
        values (v_tag, p_tag_nguon[k], v_take)
        on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
      end if;
      if v_rem[k] <= 0 then k := k + 1; end if;
    end loop;
  end if;

  -- NG phế: không tạo tem, chỉ ghi phân bổ
  if v_phe > 0 then
    v_need := v_phe;
    while v_need > 0 loop
      if k > v_n then raise exception 'Lỗi phân bổ nguồn (NG phế)'; end if;
      if v_rem[k] > 0 then
        v_take := least(v_need, v_rem[k]);
        v_rem[k] := v_rem[k] - v_take;
        v_lay[k] := v_lay[k] + v_take;
        v_phe_i[k] := v_phe_i[k] + v_take;
        v_need := v_need - v_take;
      end if;
      if v_rem[k] <= 0 then k := k + 1; end if;
    end loop;
  end if;

  -- ── Trừ SL thùng nguồn + ghi chi tiết + tem OK vào log vị trí ────────────
  for i in 1 .. v_n loop
    update duc_tem set so_luong = v_rem[i] where tag_no = p_tag_nguon[i];
    if v_lay[i] > 0 then
      insert into bavia_xu_ly_nguon (id_xu_ly, tag_no_nguon, sl_lay, sl_ng_phe, sl_ng_sua)
      values (v_id_xu_ly, p_tag_nguon[i], v_lay[i], v_phe_i[i], v_sua_i[i]);
    end if;
  end loop;

  -- Log vị trí cho các tem TKB mới (OK 'nguyen'/'quy_cach' + NG-sửa) → ở Bavia
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

  -- ── Cộng sản lượng vào line ────────────────────────────────────────────
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

  -- ── Kết quả ────────────────────────────────────────────────────────────
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

  return jsonb_build_object(
    'ok', true, 'id_xu_ly', v_id_xu_ly, 'tems', v_tems,
    'tong_lay', v_ok + v_phe + v_sua
  );
end;
$$;
revoke execute on function bavia_xu_ly_thung(text, text[], numeric, numeric, numeric, text, text, numeric, text, text, text) from anon;
grant  execute on function bavia_xu_ly_thung(text, text[], numeric, numeric, numeric, text, text, numeric, text, text, text) to authenticated;

-- Kiểm tra nhanh
-- select tag_no, so_luong, trang_thai from duc_tem where tag_no like 'TKB%';
-- select * from bavia_xu_ly order by id desc limit 5;
-- select * from bavia_xu_ly_nguon where id_xu_ly = (select max(id) from bavia_xu_ly);
