-- ============================================================================
-- Phase T2 — Đóng gói lại theo công đoạn, routing theo mã SP, báo cáo NG cuối
-- ca ngoài Đúc (Bavia/Gia công/Sơn). Theo kế hoạch đã duyệt (Nhóm 3/4).
--
-- 3 phần:
--   1) master_products.quy_trinh_cong_doan — routing theo mã SP (text list
--      thứ tự công đoạn, cách nhau dấu phẩy, cùng quy ước với so_khuon).
--   2) cd_tem_nguon + cd_dong_goi_lai() — gộp nhiều tem nguồn (đơn vị đóng gói
--      công đoạn trước) thành N tem MỚI theo quy cách công đoạn sau (VD 1 sọt
--      1000sp Đúc → nhiều thùng 36sp Bavia). Đối xứng với duc_tach_tem (tách
--      1→2) nhưng theo chiều ngược: gộp N nguồn → phân bổ FIFO vào M đơn vị
--      mới, giữ trọn liên kết truy xuất qua cd_tem_nguon. Tem mới được coi là
--      "đã ở công đoạn hiện tại" ngay lúc tạo — ghi 1 dòng tự xác nhận vào
--      cd_chuyen_cong_doan_log (không cần bảng "vị trí" riêng, tái dùng đúng
--      view cd_v_vi_tri_hien_tai đã có).
--   3) cd_bao_cao_ca + cd_luu_bao_cao_ca() — báo cáo SẢN LƯỢNG/NG CUỐI CA theo
--      công đoạn (khác Đúc: không có máy/khuôn/shot), trưởng ca công đoạn đó
--      tổng hợp theo từng mã SP: nhận vào bao nhiêu, OK bao nhiêu, NG bao
--      nhiêu.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ── 1) Routing theo mã SP ────────────────────────────────────────────────────
alter table master_products add column if not exists quy_trinh_cong_doan text;

-- ── 2) Đóng gói lại — gộp tem nguồn thành tem mới theo quy cách công đoạn ────
create table if not exists cd_tem_nguon (
  tag_no_moi   text not null references duc_tem (tag_no) on delete cascade,
  tag_no_nguon text not null references duc_tem (tag_no),
  so_luong_lay numeric not null,
  thoi_diem    timestamptz not null default now(),
  primary key (tag_no_moi, tag_no_nguon)
);
create index if not exists idx_cd_tem_nguon_nguon on cd_tem_nguon (tag_no_nguon);

-- Sinh Tag No cho tem đóng gói lại — dùng chung bảng đếm duc_tag_no_counter,
-- prefix riêng "PK{yyyyMMdd}-{seq}" để phân biệt trực quan với tem gốc từ Đúc
-- (TKD/D-TKD) — biết ngay đây là đơn vị đóng gói lại, không phải sọt Đúc gốc.
create or replace function cd_next_tag_no_dong_goi()
returns text
language plpgsql
security definer
as $$
declare
  d date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  key text := 'PK' || to_char(d, 'YYYYMMDD');
  next_seq int;
begin
  insert into duc_tag_no_counter (prefix_ngay, last_seq)
  values (key, 1)
  on conflict (prefix_ngay) do update set last_seq = duc_tag_no_counter.last_seq + 1
  returning last_seq into next_seq;

  return key || '-' || lpad(next_seq::text, 4, '0');
end;
$$;

-- p_tag_no_nguon: mảng tag_no các tem nguồn quét vào (dùng TOÀN BỘ số lượng
-- còn lại của mỗi tem — muốn dùng 1 phần thì tách tem (duc_tach_tem) trước).
-- p_so_luong_moi: mảng số lượng cho từng đơn vị đóng gói mới, 1 phần tử = 1
-- tem mới sẽ tạo. Phân bổ nguồn vào từng đơn vị mới theo thứ tự quét (FIFO
-- trong nội bộ lô đang đóng gói) — tem nguồn nào cạn thì lấy tiếp tem sau.
-- Tổng đơn vị mới có thể NHỎ HƠN tổng nguồn (phần dư giữ lại trên tem nguồn
-- cuối cùng còn dư, dùng cho lượt đóng gói sau), không được VƯỢT tổng nguồn.
create or replace function cd_dong_goi_lai(
  p_cong_doan text, p_tag_no_nguon text[], p_so_luong_moi numeric[], p_nguoi text
)
returns table(tag_no_moi text, so_luong numeric, ma_sp text, ten_sp text, ngay date, lot text, so_khuon text, nguyen_lieu text, may_duc text)
language plpgsql
security definer
as $$
declare
  v_src duc_tem%rowtype;
  v_ma_sp text;
  v_ten_sp text;
  v_ngay_moi date;
  v_lot_moi text[] := array[]::text[];
  v_so_khuon_moi text[] := array[]::text[];
  v_nl_moi text[] := array[]::text[];
  v_may_moi text[] := array[]::text[];
  v_remaining numeric[];
  v_total_available numeric := 0;
  v_total_requested numeric := 0;
  v_n_src int;
  v_n_out int;
  i int;
  j int;
  v_need numeric;
  v_take numeric;
  v_new_tag text;
  v_now timestamptz := now();
begin
  if p_cong_doan is null or trim(p_cong_doan) = '' then
    raise exception 'Thiếu công đoạn';
  end if;
  if p_tag_no_nguon is null or array_length(p_tag_no_nguon, 1) is null then
    raise exception 'Chưa quét tem nguồn nào';
  end if;
  if p_so_luong_moi is null or array_length(p_so_luong_moi, 1) is null then
    raise exception 'Chưa nhập đơn vị đóng gói mới nào';
  end if;
  if (select count(*) from unnest(p_tag_no_nguon) t) <> (select count(distinct t) from unnest(p_tag_no_nguon) t) then
    raise exception 'Có tem nguồn bị quét trùng lặp';
  end if;

  v_n_src := array_length(p_tag_no_nguon, 1);
  v_n_out := array_length(p_so_luong_moi, 1);
  v_remaining := array_fill(0::numeric, array[v_n_src]);

  for i in 1 .. v_n_src loop
    select * into v_src from duc_tem where tag_no = p_tag_no_nguon[i] for update;
    if not found then
      raise exception 'Không tìm thấy tem %', p_tag_no_nguon[i];
    end if;
    if coalesce(v_src.so_luong, 0) <= 0 then
      raise exception 'Tem % đã hết số lượng, không dùng làm nguồn được', p_tag_no_nguon[i];
    end if;

    if v_ma_sp is null then
      v_ma_sp := v_src.ma_sp; v_ten_sp := v_src.ten_sp;
    elsif v_ma_sp <> v_src.ma_sp then
      raise exception 'Các tem nguồn không cùng mã SP (% và %)', v_ma_sp, v_src.ma_sp;
    end if;

    if v_ngay_moi is null or (v_src.ngay is not null and v_src.ngay < v_ngay_moi) then
      v_ngay_moi := v_src.ngay;
    end if;
    if v_src.lot is not null and v_src.lot <> '' and not (v_src.lot = any(v_lot_moi)) then v_lot_moi := array_append(v_lot_moi, v_src.lot); end if;
    if v_src.so_khuon is not null and v_src.so_khuon <> '' and not (v_src.so_khuon = any(v_so_khuon_moi)) then v_so_khuon_moi := array_append(v_so_khuon_moi, v_src.so_khuon); end if;
    if v_src.nguyen_lieu is not null and v_src.nguyen_lieu <> '' and not (v_src.nguyen_lieu = any(v_nl_moi)) then v_nl_moi := array_append(v_nl_moi, v_src.nguyen_lieu); end if;
    if v_src.may_duc_chi_thi is not null and v_src.may_duc_chi_thi <> '' and not (v_src.may_duc_chi_thi = any(v_may_moi)) then v_may_moi := array_append(v_may_moi, v_src.may_duc_chi_thi); end if;

    v_remaining[i] := v_src.so_luong;
    v_total_available := v_total_available + v_src.so_luong;
  end loop;

  for j in 1 .. v_n_out loop
    if p_so_luong_moi[j] is null or p_so_luong_moi[j] <= 0 then
      raise exception 'Số lượng đơn vị đóng gói thứ % không hợp lệ', j;
    end if;
    v_total_requested := v_total_requested + p_so_luong_moi[j];
  end loop;

  if v_total_requested > v_total_available then
    raise exception 'Tổng số lượng đóng gói (%) vượt quá tổng số lượng tem nguồn (%)', v_total_requested, v_total_available;
  end if;

  i := 1;
  for j in 1 .. v_n_out loop
    v_new_tag := cd_next_tag_no_dong_goi();

    insert into duc_tem (
      tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
      may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
      nguoi_tt, trang_thai, ghi_chu_sl
    ) values (
      v_new_tag, v_ten_sp, v_ma_sp, p_so_luong_moi[j], v_ngay_moi,
      array_to_string(v_lot_moi, ', '), array_to_string(v_so_khuon_moi, ', '), array_to_string(v_nl_moi, ', '),
      array_to_string(v_may_moi, ', '), 'Đóng gói lại tại ' || p_cong_doan, v_now,
      array_to_string(v_so_khuon_moi, ', '), p_so_luong_moi[j], array_to_string(v_may_moi, ', '),
      p_nguoi, 'Đóng gói lại', 'Đóng gói tại ' || p_cong_doan
    );

    -- Vị trí hiện tại = p_cong_doan ngay khi tạo — ghi 1 dòng "tự chuyển nội
    -- bộ", đã xác nhận, để cd_v_vi_tri_hien_tai suy ra đúng ngay lập tức.
    insert into cd_chuyen_cong_doan_log (
      id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
      lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan,
      nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan
    ) values (
      cd_next_transfer_id(), v_now, v_new_tag, v_ma_sp, v_ten_sp, p_so_luong_moi[j], p_so_luong_moi[j], 0,
      array_to_string(v_lot_moi, ', '), array_to_string(v_so_khuon_moi, ', '), array_to_string(v_nl_moi, ', '),
      array_to_string(v_may_moi, ', '), coalesce(v_ngay_moi::text, ''), p_cong_doan, p_cong_doan,
      p_nguoi, p_nguoi, 'Đã xác nhận chuyển công đoạn', to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
    );

    v_need := p_so_luong_moi[j];
    while v_need > 0 loop
      if i > v_n_src then
        raise exception 'Lỗi phân bổ số lượng nguồn cho tem % — liên hệ kỹ thuật', v_new_tag;
      end if;
      if v_remaining[i] > 0 then
        v_take := least(v_need, v_remaining[i]);
        v_remaining[i] := v_remaining[i] - v_take;
        v_need := v_need - v_take;
        insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay)
        values (v_new_tag, p_tag_no_nguon[i], v_take)
        on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
      end if;
      if v_remaining[i] <= 0 then i := i + 1; end if;
    end loop;

    tag_no_moi := v_new_tag; so_luong := p_so_luong_moi[j]; ma_sp := v_ma_sp; ten_sp := v_ten_sp;
    ngay := v_ngay_moi; lot := array_to_string(v_lot_moi, ', '); so_khuon := array_to_string(v_so_khuon_moi, ', ');
    nguyen_lieu := array_to_string(v_nl_moi, ', '); may_duc := array_to_string(v_may_moi, ', ');
    return next;
  end loop;

  for i in 1 .. v_n_src loop
    update duc_tem set so_luong = v_remaining[i] where tag_no = p_tag_no_nguon[i];
  end loop;

  return;
end;
$$;

-- ── 3) Báo cáo sản lượng/NG cuối ca theo công đoạn (ngoài Đúc) ──────────────
create table if not exists cd_bao_cao_ca (
  id_bao_cao         text primary key,
  ngay               date not null,
  ca                 text not null,
  cong_doan          text not null,
  ma_sp              text not null,
  ten_sp             text default '',
  to_san_xuat        text not null default '',
  so_luong_nhan_vao  numeric default 0,
  so_luong_ok        numeric default 0,
  so_luong_ng        numeric default 0,
  nguoi_bao_cao      text,
  ghi_chu            text,
  thoi_diem_luu      timestamptz not null default now()
);
create index if not exists idx_cd_bao_cao_ca_loc on cd_bao_cao_ca (cong_doan, ngay);

-- Lưu nhiều dòng báo cáo 1 lượt (mỗi dòng = 1 mã SP trong ca) — upsert theo
-- (ngay, ca, cong_doan, ma_sp, to_san_xuat), id_bao_cao sinh xác định từ các
-- trường đó (không random) để việc lưu lại/sửa lại luôn đúng đè lên dòng cũ.
create or replace function cd_luu_bao_cao_ca(p_rows jsonb, p_nguoi text)
returns integer
language plpgsql
security definer
as $$
declare
  v_row jsonb;
  v_id text;
  v_count integer := 0;
  v_ngay date;
  v_ca text;
  v_cong_doan text;
  v_ma_sp text;
  v_to text;
begin
  if p_rows is null or jsonb_array_length(p_rows) = 0 then
    raise exception 'Không có dòng nào để lưu';
  end if;

  for v_row in select * from jsonb_array_elements(p_rows) loop
    v_ngay := (v_row->>'ngay')::date;
    v_ca := v_row->>'ca';
    v_cong_doan := v_row->>'cong_doan';
    v_ma_sp := v_row->>'ma_sp';
    v_to := coalesce(v_row->>'to_san_xuat', '');
    if v_ngay is null or v_ca is null or trim(coalesce(v_ca,'')) = '' or v_cong_doan is null or trim(coalesce(v_cong_doan,'')) = ''
       or v_ma_sp is null or trim(v_ma_sp) = '' then
      raise exception 'Thiếu ngày/ca/công đoạn/mã SP ở 1 dòng báo cáo';
    end if;

    v_id := to_char(v_ngay, 'DDMMYYYY') || '_' || duc_normalize_name(v_ca) || '_' || duc_normalize_name(v_cong_doan) || '_' || duc_normalize_name(v_ma_sp) ||
      case when v_to <> '' then '_' || duc_normalize_name(v_to) else '' end;

    insert into cd_bao_cao_ca (
      id_bao_cao, ngay, ca, cong_doan, ma_sp, ten_sp, to_san_xuat,
      so_luong_nhan_vao, so_luong_ok, so_luong_ng, nguoi_bao_cao, ghi_chu, thoi_diem_luu
    ) values (
      v_id, v_ngay, v_ca, v_cong_doan, v_ma_sp, coalesce(v_row->>'ten_sp', ''), v_to,
      coalesce((v_row->>'so_luong_nhan_vao')::numeric, 0), coalesce((v_row->>'so_luong_ok')::numeric, 0), coalesce((v_row->>'so_luong_ng')::numeric, 0),
      p_nguoi, v_row->>'ghi_chu', now()
    )
    on conflict (id_bao_cao) do update set
      ten_sp = excluded.ten_sp, so_luong_nhan_vao = excluded.so_luong_nhan_vao,
      so_luong_ok = excluded.so_luong_ok, so_luong_ng = excluded.so_luong_ng,
      nguoi_bao_cao = excluded.nguoi_bao_cao, ghi_chu = excluded.ghi_chu, thoi_diem_luu = now();

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- ----------------------------------------------------------------------------
-- Row Level Security + quyền thực thi RPC — theo đúng pattern các module khác.
-- ----------------------------------------------------------------------------
do $$
declare t text;
begin
  for t in select unnest(array['cd_tem_nguon', 'cd_bao_cao_ca'])
  loop
    execute format('alter table %I enable row level security;', t);
    execute format('drop policy if exists "public read" on %I;', t);
    execute format('create policy "public read" on %I for select using (true);', t);
  end loop;
end $$;

revoke execute on function cd_next_tag_no_dong_goi() from anon;
grant execute on function cd_next_tag_no_dong_goi() to authenticated;

revoke execute on function cd_dong_goi_lai(text, text[], numeric[], text) from anon;
grant execute on function cd_dong_goi_lai(text, text[], numeric[], text) to authenticated;

revoke execute on function cd_luu_bao_cao_ca(jsonb, text) from anon;
grant execute on function cd_luu_bao_cao_ca(jsonb, text) to authenticated;
