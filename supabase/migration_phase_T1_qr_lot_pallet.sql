-- ============================================================================
-- Phase T1 — Chuẩn hoá QR/lot/pallet (Nhóm 3 kế hoạch KE_HOACH_TINH_NANG_MOI.md)
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
--
-- 3 phần độc lập, đóng 3 khoảng trống trong chuỗi liên kết lệnh SX → ca/máy/
-- khuôn → lot NVL → sọt/pallet → công đoạn → thành phẩm:
--   1) duc_tem_nvl_lot — liên kết NHIỀU-NHIỀU giữa tem đúc và lot NVL (nvl_tem).
--      Không phải 1-1 vì 2 lò nung tập trung dùng chung nhiều lot ingot trước
--      khi robot múc phân phối ra từng máy đúc — người vận hành chọn thủ công
--      lot NVL đang mở tại thời điểm in tem, không tự động suy ra tuyệt đối.
--   2) duc_tem_tach + duc_tach_tem() — tách 1 tag_no thành tag_no con (hậu tố
--      -A/-B/...) khi chia sọt hoặc số lượng thực chuyển < số lượng trên tem.
--   3) oqc_pallet/oqc_pallet_item — gom nhiều tag_no thành 1 pallet ở OQC,
--      đóng gói xong mới coi là nhập kho thành phẩm.
-- ============================================================================

-- ── 1) Liên kết tem đúc ↔ lot NVL ───────────────────────────────────────────
create table if not exists duc_tem_nvl_lot (
  tag_no       text not null references duc_tem (tag_no) on delete cascade,
  nvl_tag_no   text not null references nvl_tem (tag_no),
  thoi_diem_gan timestamptz not null default now(),
  nguoi_gan     text,
  primary key (tag_no, nvl_tag_no)
);

-- Thay toàn bộ danh sách lot NVL gắn với 1 tag_no (xoá cũ, ghi mới) — dùng khi
-- in tem lần đầu hoặc sửa lại lựa chọn lot NVL trong tab tra cứu.
create or replace function duc_gan_lot_nvl(
  p_tag_no text, p_nvl_tag_nos text[], p_nguoi text
)
returns void
language plpgsql
security definer
as $$
begin
  delete from duc_tem_nvl_lot where tag_no = p_tag_no;
  if p_nvl_tag_nos is not null then
    insert into duc_tem_nvl_lot (tag_no, nvl_tag_no, nguoi_gan)
    select p_tag_no, unnest(p_nvl_tag_nos), p_nguoi;
  end if;
end;
$$;

-- ── 2) Tách tem (sọt) ────────────────────────────────────────────────────────
create table if not exists duc_tem_tach (
  id             bigserial primary key,
  tag_no_cha     text not null references duc_tem (tag_no),
  tag_no_con     text not null unique references duc_tem (tag_no),
  so_luong_con   numeric not null,
  ly_do          text,
  nguoi_thao_tac text,
  thoi_diem      timestamptz not null default now()
);
create index if not exists idx_duc_tem_tach_cha on duc_tem_tach (tag_no_cha);

-- Tách p_so_luong_tach từ tag_no_cha ra 1 tag_no con mới (hậu tố -A/-B/...),
-- trừ số lượng còn lại trên tem cha, copy các trường tĩnh (SP/khuôn/nguyên
-- liệu/máy/lot NVL đã gán) sang tem con, ghi lịch sử vào duc_tem_tach.
create or replace function duc_tach_tem(
  p_tag_no_cha text, p_so_luong_tach numeric, p_ly_do text, p_nguoi text
)
returns text
language plpgsql
security definer
as $$
declare
  v_cha       duc_tem%rowtype;
  v_so_con    int;
  v_letter    text;
  v_tag_con   text;
begin
  select * into v_cha from duc_tem where tag_no = p_tag_no_cha for update;
  if not found then
    raise exception 'Không tìm thấy tem %', p_tag_no_cha;
  end if;
  if p_so_luong_tach is null or p_so_luong_tach <= 0 then
    raise exception 'Số lượng tách phải lớn hơn 0';
  end if;
  if v_cha.so_luong is not null and p_so_luong_tach > v_cha.so_luong then
    raise exception 'Số lượng tách (%) vượt quá số lượng còn lại trên tem cha (%)', p_so_luong_tach, v_cha.so_luong;
  end if;

  select count(*) into v_so_con from duc_tem_tach where tag_no_cha = p_tag_no_cha;
  if v_so_con >= 26 then
    raise exception 'Tem % đã tách quá 26 lần, không tự sinh thêm hậu tố được', p_tag_no_cha;
  end if;
  v_letter := chr(65 + v_so_con); -- A, B, C, ...
  v_tag_con := p_tag_no_cha || '-' || v_letter;

  insert into duc_tem (
    tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
    may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
    nguoi_tt, trang_thai, ghi_chu_sl
  ) values (
    v_tag_con, v_cha.ten_sp, v_cha.ma_sp, p_so_luong_tach, v_cha.ngay, v_cha.lot, v_cha.so_khuon, v_cha.nguyen_lieu,
    v_cha.may_duc_chi_thi, v_cha.ghi_chu, now(), v_cha.so_khuon_tt, p_so_luong_tach, v_cha.may_tt,
    p_nguoi, v_cha.trang_thai, 'Tách từ ' || p_tag_no_cha
  );

  update duc_tem set so_luong = so_luong - p_so_luong_tach where tag_no = p_tag_no_cha;

  insert into duc_tem_tach (tag_no_cha, tag_no_con, so_luong_con, ly_do, nguoi_thao_tac)
  values (p_tag_no_cha, v_tag_con, p_so_luong_tach, p_ly_do, p_nguoi);

  insert into duc_tem_nvl_lot (tag_no, nvl_tag_no, nguoi_gan)
  select v_tag_con, nvl_tag_no, p_nguoi from duc_tem_nvl_lot where tag_no = p_tag_no_cha;

  return v_tag_con;
end;
$$;

-- ── 3) Pallet đóng gói ở OQC ─────────────────────────────────────────────────
create table if not exists oqc_pallet_counter (
  prefix_ngay text primary key,   -- "PLT20260815"
  last_seq    int not null default 0
);

create table if not exists oqc_pallet (
  id_pallet          text primary key,        -- "PLT{yyyyMMdd}-{seq 3 chữ số}"
  ngay               date not null,
  trang_thai         text not null default 'dang_dong_goi'
                       check (trang_thai in ('dang_dong_goi', 'da_nhap_kho')),
  tong_so_luong      numeric not null default 0,
  nguoi_dong_goi     text,
  thoi_diem_tao      timestamptz not null default now(),
  thoi_diem_nhap_kho timestamptz
);

create table if not exists oqc_pallet_item (
  id_pallet     text not null references oqc_pallet (id_pallet) on delete cascade,
  tag_no        text not null references duc_tem (tag_no),
  so_luong      numeric not null,
  nguoi_quet    text,
  thoi_diem_quet timestamptz not null default now(),
  primary key (id_pallet, tag_no)
);

create or replace function oqc_next_pallet_id()
returns text
language plpgsql
security definer
as $$
declare
  d date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  key text := 'PLT' || to_char(d, 'YYYYMMDD');
  next_seq int;
begin
  insert into oqc_pallet_counter (prefix_ngay, last_seq)
  values (key, 1)
  on conflict (prefix_ngay) do update set last_seq = oqc_pallet_counter.last_seq + 1
  returning last_seq into next_seq;

  return key || '-' || lpad(next_seq::text, 3, '0');
end;
$$;

create or replace function oqc_tao_pallet(p_nguoi text)
returns text
language plpgsql
security definer
as $$
declare
  v_id text := oqc_next_pallet_id();
begin
  insert into oqc_pallet (id_pallet, ngay, nguoi_dong_goi)
  values (v_id, (now() at time zone 'Asia/Ho_Chi_Minh')::date, p_nguoi);
  return v_id;
end;
$$;

create or replace function oqc_them_tem_vao_pallet(
  p_id_pallet text, p_tag_no text, p_so_luong numeric, p_nguoi text
)
returns void
language plpgsql
security definer
as $$
declare
  v_trang_thai text;
begin
  select trang_thai into v_trang_thai from oqc_pallet where id_pallet = p_id_pallet for update;
  if not found then
    raise exception 'Không tìm thấy pallet %', p_id_pallet;
  end if;
  if v_trang_thai <> 'dang_dong_goi' then
    raise exception 'Pallet % đã đóng, không thêm được nữa', p_id_pallet;
  end if;

  insert into oqc_pallet_item (id_pallet, tag_no, so_luong, nguoi_quet)
  values (p_id_pallet, p_tag_no, p_so_luong, p_nguoi)
  on conflict (id_pallet, tag_no) do update set so_luong = excluded.so_luong, nguoi_quet = excluded.nguoi_quet, thoi_diem_quet = now();

  update oqc_pallet set tong_so_luong = (
    select coalesce(sum(so_luong), 0) from oqc_pallet_item where id_pallet = p_id_pallet
  ) where id_pallet = p_id_pallet;
end;
$$;

create or replace function oqc_dong_pallet(p_id_pallet text)
returns void
language plpgsql
security definer
as $$
begin
  update oqc_pallet
  set trang_thai = 'da_nhap_kho', thoi_diem_nhap_kho = now()
  where id_pallet = p_id_pallet and trang_thai = 'dang_dong_goi';
  if not found then
    raise exception 'Không tìm thấy pallet đang đóng gói %', p_id_pallet;
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- Row Level Security: đọc công khai, ghi chỉ qua RPC (security definer) —
-- theo đúng pattern đã dùng cho toàn bộ RPC ghi khác trong dự án.
-- ----------------------------------------------------------------------------
do $$
declare t text;
begin
  for t in select unnest(array[
    'duc_tem_nvl_lot', 'duc_tem_tach', 'oqc_pallet_counter', 'oqc_pallet', 'oqc_pallet_item'
  ])
  loop
    execute format('alter table %I enable row level security;', t);
    execute format('drop policy if exists "public read" on %I;', t);
    execute format('create policy "public read" on %I for select using (true);', t);
  end loop;
end $$;

revoke execute on function duc_gan_lot_nvl(text, text[], text) from anon;
grant execute on function duc_gan_lot_nvl(text, text[], text) to authenticated;

revoke execute on function duc_tach_tem(text, numeric, text, text) from anon;
grant execute on function duc_tach_tem(text, numeric, text, text) to authenticated;

revoke execute on function oqc_next_pallet_id() from anon;
grant execute on function oqc_next_pallet_id() to authenticated;

revoke execute on function oqc_tao_pallet(text) from anon;
grant execute on function oqc_tao_pallet(text) to authenticated;

revoke execute on function oqc_them_tem_vao_pallet(text, text, numeric, text) from anon;
grant execute on function oqc_them_tem_vao_pallet(text, text, numeric, text) to authenticated;

revoke execute on function oqc_dong_pallet(text) from anon;
grant execute on function oqc_dong_pallet(text) to authenticated;
