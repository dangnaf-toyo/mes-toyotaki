-- ============================================================================
-- T133: IPQC — Bảng tuần kiểm kích thước theo mã SP + ghi kết quả đo từng lần
-- kiểm + giới hạn kiểm soát (biểu đồ I-MR / X̄-R) cho QC Manager.
-- Mẫu: "Excel file/Ví dụ form ghi kết quả IPQC.xlsx" (BIỂU KIỂM TRA TUẦN KIỂM
-- QP-82405-B): No / Hạng mục / Tiêu chuẩn / Dụng cụ KT / Tần suất / Phán định.
--
--   ipqc_btk            1 phiên bản bảng tuần kiểm của 1 mã (A, B, ...), chỉ 1
--                       phiên bản dang_dung / mã; bản vẽ + vị trí đo ①..⑤.
--   ipqc_btk_muc        hạng mục: kieu 'so' (đo số: danh nghĩa + dung sai) |
--                       'okng' (lắp ghép, ngoại quan...).
--   ipqc_do_lan         1 lần kiểm IPQC (id_checkpoint) có đo theo bảng tuần kiểm.
--   ipqc_do_kq          giá trị đo: (id_checkpoint, muc_no, mau) — so_mau mẫu/lần.
--   ipqc_gioi_han       giới hạn kiểm soát theo (ma_sp, muc_no): tự khoá sau 30
--                       lần đo đầu; QC Manager tính lại / nhập tay khi cải tiến.
-- Ghi chỉ qua RPC security definer. Lập/sửa bảng + giới hạn: qc_manager / admin.
-- ============================================================================

create table if not exists ipqc_btk (
  id               bigserial primary key,
  ma_sp            text not null,
  phien_ban        text not null,
  ngay_hieu_luc    date,
  so_mau           int not null default 1 check (so_mau between 1 and 5),
  tan_suat         text not null default '2h/lần',
  ma_bieu          text not null default 'QP-82405-B',
  ban_ve_url       text,
  ban_ve_vi_tri    jsonb not null default '[]'::jsonb,   -- [{no, x, y}] x,y theo % ảnh
  noi_dung_sua_doi text,
  nguoi_xac_nhan   text,
  nguoi_lap        text,
  nguoi_lap_uid    uuid,
  tao_luc          timestamptz not null default now(),
  dang_dung        boolean not null default true,
  unique (ma_sp, phien_ban)
);
create unique index if not exists ipqc_btk_dang_dung_uq on ipqc_btk (ma_sp) where dang_dung;

create table if not exists ipqc_btk_muc (
  id             bigserial primary key,
  id_btk         bigint not null references ipqc_btk(id) on delete cascade,
  muc_no         int not null,
  hang_muc       text not null,
  kieu           text not null check (kieu in ('so', 'okng')),
  danh_nghia     numeric,
  dung_sai_tren  numeric,          -- + (VD 0.1)
  dung_sai_duoi  numeric,          -- − độ lớn dương (VD 0.2 nghĩa là −0.2)
  tieu_chuan     text,             -- chữ hiển thị (bắt buộc với okng)
  dung_cu        text,
  tan_suat       text,
  unique (id_btk, muc_no),
  check (kieu = 'okng' or (danh_nghia is not null and (dung_sai_tren is not null or dung_sai_duoi is not null)))
);

create table if not exists ipqc_do_lan (
  id_checkpoint  text primary key references duc_ipqc_checkpoint(id_checkpoint) on delete cascade,
  id_btk         bigint not null references ipqc_btk(id),
  ma_sp          text not null,
  ma_may         text,
  so_khuon       text,
  thoi_diem      timestamptz not null default now(),
  nguoi          text,
  nguoi_uid      uuid,
  dat            boolean not null
);
create index if not exists ipqc_do_lan_sp_idx on ipqc_do_lan (ma_sp, thoi_diem);

create table if not exists ipqc_do_kq (
  id_checkpoint  text not null references ipqc_do_lan(id_checkpoint) on delete cascade,
  muc_no         int not null,
  mau            int not null default 1,
  gia_tri        numeric,
  dat            boolean not null,
  primary key (id_checkpoint, muc_no, mau)
);

create table if not exists ipqc_gioi_han (
  id          bigserial primary key,
  ma_sp       text not null,
  muc_no      int not null,
  so_mau      int not null,
  cl          numeric not null,
  ucl         numeric not null,
  lcl         numeric not null,
  cl_r        numeric not null,      -- MR̄ (1 mẫu) hoặc R̄ (≥2 mẫu)
  ucl_r       numeric not null,
  n_lan       int not null,
  cach        text not null check (cach in ('tu_dong', 'tinh_lai', 'tay')),
  tu_luc      timestamptz,
  den_luc     timestamptz,
  ghi_chu     text,
  nguoi       text,
  tao_luc     timestamptz not null default now(),
  dang_dung   boolean not null default true
);
create unique index if not exists ipqc_gioi_han_dang_dung_uq on ipqc_gioi_han (ma_sp, muc_no) where dang_dung;

alter table ipqc_btk enable row level security;
alter table ipqc_btk_muc enable row level security;
alter table ipqc_do_lan enable row level security;
alter table ipqc_do_kq enable row level security;
alter table ipqc_gioi_han enable row level security;
do $$ declare t text; begin
  foreach t in array array['ipqc_btk','ipqc_btk_muc','ipqc_do_lan','ipqc_do_kq','ipqc_gioi_han'] loop
    execute format('drop policy if exists %I on %I', t || '_doc', t);
    execute format('create policy %I on %I for select to authenticated using (true)', t || '_doc', t);
    execute format('revoke insert, update, delete on %I from anon, authenticated', t);
    execute format('grant select on %I to authenticated', t);
  end loop;
end $$;

-- Ảnh bản vẽ vị trí đo — đọc công khai, upload qc_manager/admin.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ipqc-ban-ve', 'ipqc-ban-ve', true, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "public read ipqc-ban-ve" on storage.objects;
create policy "public read ipqc-ban-ve" on storage.objects for select using (bucket_id = 'ipqc-ban-ve');
drop policy if exists "qc upload ipqc-ban-ve" on storage.objects;
create policy "qc upload ipqc-ban-ve" on storage.objects
  for insert with check (bucket_id = 'ipqc-ban-ve' and public.has_role('qc_manager', 'admin'));

-- ── Lưu 1 phiên bản mới (luôn tạo bản mới, bản cũ thôi dùng) ───────────────
-- p_data: {phien_ban?, ngay_hieu_luc?, so_mau, tan_suat?, ma_bieu?, noi_dung_sua_doi,
--          nguoi_xac_nhan?, ban_ve_url?, ban_ve_vi_tri?, muc:[{muc_no, hang_muc, kieu,
--          danh_nghia?, dung_sai_tren?, dung_sai_duoi?, tieu_chuan?, dung_cu?, tan_suat?}]}
create or replace function ipqc_btk_luu(p_ma_sp text, p_data jsonb, p_nguoi text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_ma text := trim(coalesce(p_ma_sp, ''));
  v_cu ipqc_btk%rowtype;
  v_pb text := nullif(trim(coalesce(p_data ->> 'phien_ban', '')), '');
  v_id bigint;
  m jsonb;
  v_nos int[] := '{}';
  v_no int;
  v_kieu text;
begin
  if not public.has_role('qc_manager', 'admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ QC Manager / admin được lập bảng tuần kiểm');
  end if;
  if not exists (select 1 from master_products where ma_sp = v_ma) then
    return jsonb_build_object('ok', false, 'error', 'Mã SP không có trong danh mục: ' || v_ma);
  end if;
  if jsonb_array_length(coalesce(p_data -> 'muc', '[]'::jsonb)) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Cần ít nhất 1 hạng mục');
  end if;
  if coalesce((p_data ->> 'so_mau')::int, 1) not between 1 and 5 then
    return jsonb_build_object('ok', false, 'error', 'Số mẫu/lần phải từ 1 đến 5');
  end if;

  select * into v_cu from ipqc_btk where ma_sp = v_ma and dang_dung for update;
  if v_pb is null then
    v_pb := case when v_cu.id is null then 'A'
                 when v_cu.phien_ban ~ '^[A-Y]$' then chr(ascii(v_cu.phien_ban) + 1)
                 else v_cu.phien_ban || '.1' end;
  end if;
  if exists (select 1 from ipqc_btk where ma_sp = v_ma and phien_ban = v_pb) then
    return jsonb_build_object('ok', false, 'error', 'Mã ' || v_ma || ' đã có phiên bản ' || v_pb);
  end if;

  for m in select * from jsonb_array_elements(p_data -> 'muc') loop
    v_no := nullif(m ->> 'muc_no', '')::int;
    v_kieu := m ->> 'kieu';
    if v_no is null or v_no < 1 then return jsonb_build_object('ok', false, 'error', 'Thiếu số thứ tự (No) hạng mục'); end if;
    if v_no = any(v_nos) then return jsonb_build_object('ok', false, 'error', 'Trùng No ' || v_no); end if;
    v_nos := v_nos || v_no;
    if coalesce(trim(m ->> 'hang_muc'), '') = '' then return jsonb_build_object('ok', false, 'error', 'No ' || v_no || ': thiếu tên hạng mục'); end if;
    if v_kieu not in ('so', 'okng') then return jsonb_build_object('ok', false, 'error', 'No ' || v_no || ': kiểu phải là Đo số hoặc OK/NG'); end if;
    if v_kieu = 'so' and (nullif(m ->> 'danh_nghia', '') is null or (nullif(m ->> 'dung_sai_tren', '') is null and nullif(m ->> 'dung_sai_duoi', '') is null)) then
      return jsonb_build_object('ok', false, 'error', 'No ' || v_no || ': hạng mục đo số cần giá trị danh nghĩa + dung sai');
    end if;
    if v_kieu = 'okng' and coalesce(trim(m ->> 'tieu_chuan'), '') = '' then
      return jsonb_build_object('ok', false, 'error', 'No ' || v_no || ': hạng mục OK/NG cần ghi tiêu chuẩn');
    end if;
  end loop;

  update ipqc_btk set dang_dung = false where ma_sp = v_ma and dang_dung;
  insert into ipqc_btk (ma_sp, phien_ban, ngay_hieu_luc, so_mau, tan_suat, ma_bieu, ban_ve_url, ban_ve_vi_tri,
    noi_dung_sua_doi, nguoi_xac_nhan, nguoi_lap, nguoi_lap_uid)
  values (v_ma, v_pb, coalesce(nullif(p_data ->> 'ngay_hieu_luc', '')::date, (now() at time zone 'Asia/Ho_Chi_Minh')::date),
    coalesce((p_data ->> 'so_mau')::int, 1), coalesce(nullif(trim(p_data ->> 'tan_suat'), ''), '2h/lần'),
    coalesce(nullif(trim(p_data ->> 'ma_bieu'), ''), 'QP-82405-B'),
    coalesce(nullif(p_data ->> 'ban_ve_url', ''), v_cu.ban_ve_url),
    coalesce(p_data -> 'ban_ve_vi_tri', v_cu.ban_ve_vi_tri, '[]'::jsonb),
    coalesce(nullif(trim(p_data ->> 'noi_dung_sua_doi'), ''), case when v_cu.id is null then 'Lập mới' else 'Sửa đổi' end),
    nullif(trim(p_data ->> 'nguoi_xac_nhan'), ''), p_nguoi, auth.uid())
  returning id into v_id;

  insert into ipqc_btk_muc (id_btk, muc_no, hang_muc, kieu, danh_nghia, dung_sai_tren, dung_sai_duoi, tieu_chuan, dung_cu, tan_suat)
  select v_id, (j.v ->> 'muc_no')::int, trim(j.v ->> 'hang_muc'), j.v ->> 'kieu',
    case when j.v ->> 'kieu' = 'so' then nullif(j.v ->> 'danh_nghia', '')::numeric end,
    case when j.v ->> 'kieu' = 'so' then abs(nullif(j.v ->> 'dung_sai_tren', '')::numeric) end,
    case when j.v ->> 'kieu' = 'so' then abs(nullif(j.v ->> 'dung_sai_duoi', '')::numeric) end,
    nullif(trim(j.v ->> 'tieu_chuan'), ''), nullif(trim(j.v ->> 'dung_cu'), ''), nullif(trim(j.v ->> 'tan_suat'), '')
  from jsonb_array_elements(p_data -> 'muc') as j(v);

  return jsonb_build_object('ok', true, 'id', v_id, 'phien_ban', v_pb);
end $$;
revoke execute on function ipqc_btk_luu(text, jsonb, text) from public, anon;
grant execute on function ipqc_btk_luu(text, jsonb, text) to authenticated;

-- ── Cập nhật bản vẽ / vị trí đo của phiên bản đang dùng (không tạo bản mới) ──
create or replace function ipqc_btk_ban_ve(p_id_btk bigint, p_url text, p_vi_tri jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
begin
  if not public.has_role('qc_manager', 'admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ QC Manager / admin được sửa bản vẽ');
  end if;
  update ipqc_btk set ban_ve_url = coalesce(nullif(p_url, ''), ban_ve_url), ban_ve_vi_tri = coalesce(p_vi_tri, ban_ve_vi_tri)
  where id = p_id_btk;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy bảng tuần kiểm #' || p_id_btk); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function ipqc_btk_ban_ve(bigint, text, jsonb) from public, anon;
grant execute on function ipqc_btk_ban_ve(bigint, text, jsonb) to authenticated;

-- ── Tính giới hạn kiểm soát từ các lần đo trong khoảng (nội bộ) ────────────
-- 1 mẫu: I-MR (UCL = X̄ ± 2.66·MR̄, UCL_MR = 3.267·MR̄); ≥2 mẫu: X̄-R (A2, D4).
create or replace function ipqc_gioi_han_tinh(p_ma_sp text, p_muc_no int, p_tu timestamptz, p_den timestamptz, p_toi_da int)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_n int; v_cl numeric; v_r numeric; v_so_mau int; a2 numeric; d4 numeric;
begin
  with lan as (
    select l.thoi_diem, avg(k.gia_tri) x, max(k.gia_tri) - min(k.gia_tri) r, count(k.gia_tri) n
    from ipqc_do_lan l join ipqc_do_kq k on k.id_checkpoint = l.id_checkpoint and k.muc_no = p_muc_no
    join duc_ipqc_checkpoint c on c.id_checkpoint = l.id_checkpoint and c.ket_qua is not null
    where l.ma_sp = p_ma_sp and k.gia_tri is not null
      and (p_tu is null or l.thoi_diem >= p_tu) and (p_den is null or l.thoi_diem <= p_den)
    group by l.id_checkpoint, l.thoi_diem order by l.thoi_diem limit coalesce(p_toi_da, 100000)
  ), mr as (select x, r, n, abs(x - lag(x) over (order by thoi_diem)) mr from lan)
  select count(*), avg(x), round(avg(n))::int,
         case when round(avg(n)) <= 1 then avg(mr) else avg(r) end
    into v_n, v_cl, v_so_mau, v_r from mr;
  if coalesce(v_n, 0) < 2 or v_r is null then return null; end if;
  if v_so_mau <= 1 then
    return jsonb_build_object('so_mau', 1, 'cl', v_cl, 'ucl', v_cl + 2.66 * v_r, 'lcl', v_cl - 2.66 * v_r,
      'cl_r', v_r, 'ucl_r', 3.267 * v_r, 'n_lan', v_n);
  end if;
  a2 := (array[1.880, 1.023, 0.729, 0.577])[least(v_so_mau, 5) - 1];
  d4 := (array[3.267, 2.574, 2.282, 2.114])[least(v_so_mau, 5) - 1];
  return jsonb_build_object('so_mau', v_so_mau, 'cl', v_cl, 'ucl', v_cl + a2 * v_r, 'lcl', v_cl - a2 * v_r,
    'cl_r', v_r, 'ucl_r', d4 * v_r, 'n_lan', v_n);
end $$;
revoke execute on function ipqc_gioi_han_tinh(text, int, timestamptz, timestamptz, int) from public, anon, authenticated;

-- Tự khoá giới hạn sau 30 lần đo đầu (gọi sau mỗi lần lưu kết quả đo).
create or replace function ipqc_gioi_han_tu_khoa(p_ma_sp text)
returns void
language plpgsql security definer set search_path = public
as $$
declare m record; g jsonb;
begin
  for m in select mu.muc_no from ipqc_btk b join ipqc_btk_muc mu on mu.id_btk = b.id
           where b.ma_sp = p_ma_sp and b.dang_dung and mu.kieu = 'so'
             and not exists (select 1 from ipqc_gioi_han h where h.ma_sp = p_ma_sp and h.muc_no = mu.muc_no and h.dang_dung)
  loop
    g := ipqc_gioi_han_tinh(p_ma_sp, m.muc_no, null, null, 30);
    if g is not null and (g ->> 'n_lan')::int >= 30 then
      insert into ipqc_gioi_han (ma_sp, muc_no, so_mau, cl, ucl, lcl, cl_r, ucl_r, n_lan, cach, ghi_chu, nguoi)
      values (p_ma_sp, m.muc_no, (g ->> 'so_mau')::int, (g ->> 'cl')::numeric, (g ->> 'ucl')::numeric, (g ->> 'lcl')::numeric,
        (g ->> 'cl_r')::numeric, (g ->> 'ucl_r')::numeric, 30, 'tu_dong', 'Tự khoá sau 30 lần đo đầu', 'Hệ thống');
    end if;
  end loop;
end $$;
revoke execute on function ipqc_gioi_han_tu_khoa(text) from public, anon, authenticated;

-- ── IPQC lưu kết quả đo của 1 lần kiểm (gọi trước duc_submit_ipqc_session) ──
-- p_kq: [{muc_no, mau, gia_tri?, dat?}] — đo số: server tự phán định theo dung sai.
create or replace function ipqc_do_luu(p_id_checkpoint text, p_kq jsonb, p_nguoi text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  c duc_ipqc_checkpoint%rowtype;
  b ipqc_btk%rowtype;
  mu ipqc_btk_muc%rowtype;
  x jsonb;
  v_gt numeric; v_dat boolean; v_all boolean := true;
  v_thieu text[] := '{}';
  v_mau int;
  v_ng jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into c from duc_ipqc_checkpoint where id_checkpoint = p_id_checkpoint;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy điểm kiểm ' || coalesce(p_id_checkpoint, '')); end if;
  if c.ket_qua is not null then return jsonb_build_object('ok', false, 'error', 'Lần kiểm này đã nộp kết quả — không sửa được kết quả đo'); end if;
  select * into b from ipqc_btk where ma_sp = c.ma_sp and dang_dung;
  if not found then return jsonb_build_object('ok', false, 'error', 'Mã ' || c.ma_sp || ' chưa có bảng tuần kiểm'); end if;

  delete from ipqc_do_lan where id_checkpoint = c.id_checkpoint;
  insert into ipqc_do_lan (id_checkpoint, id_btk, ma_sp, ma_may, so_khuon, nguoi, nguoi_uid, dat)
  values (c.id_checkpoint, b.id, c.ma_sp, c.ma_may,
    (select so_khuon from duc_ca_hien_tai where id_dong = c.id_dong), p_nguoi, auth.uid(), true);

  for mu in select * from ipqc_btk_muc where id_btk = b.id order by muc_no loop
    for v_mau in 1 .. case when mu.kieu = 'so' then b.so_mau else 1 end loop
      x := null;
      select e.v into x from jsonb_array_elements(coalesce(p_kq, '[]'::jsonb)) as e(v)
      where (e.v ->> 'muc_no')::int = mu.muc_no and coalesce((e.v ->> 'mau')::int, 1) = v_mau limit 1;
      if mu.kieu = 'so' then
        v_gt := nullif(x ->> 'gia_tri', '')::numeric;
        if v_gt is null then v_thieu := v_thieu || (mu.muc_no || case when b.so_mau > 1 then '/' || v_mau else '' end); continue; end if;
        v_dat := (mu.dung_sai_tren is null or v_gt <= mu.danh_nghia + mu.dung_sai_tren)
             and (mu.dung_sai_duoi is null or v_gt >= mu.danh_nghia - mu.dung_sai_duoi);
      else
        v_gt := null;
        v_dat := (x ->> 'dat')::boolean;
        if v_dat is null then v_thieu := v_thieu || mu.muc_no::text; continue; end if;
      end if;
      insert into ipqc_do_kq (id_checkpoint, muc_no, mau, gia_tri, dat) values (c.id_checkpoint, mu.muc_no, v_mau, v_gt, v_dat);
      if not v_dat then
        v_all := false;
        v_ng := v_ng || jsonb_build_array(jsonb_build_object('muc_no', mu.muc_no, 'mau', v_mau, 'gia_tri', v_gt));
      end if;
    end loop;
  end loop;

  if array_length(v_thieu, 1) > 0 then
    raise exception 'Chưa nhập kết quả đo hạng mục: %', array_to_string(v_thieu, ', ');
  end if;
  update ipqc_do_lan set dat = v_all where id_checkpoint = c.id_checkpoint;
  return jsonb_build_object('ok', true, 'dat', v_all, 'ng', v_ng, 'phien_ban', b.phien_ban);
end $$;
revoke execute on function ipqc_do_luu(text, jsonb, text) from public, anon;
grant execute on function ipqc_do_luu(text, jsonb, text) to authenticated;

-- Sau khi lần kiểm được nộp (ket_qua có giá trị) → tự khoá giới hạn nếu đủ 30 lần.
create or replace function ipqc_do_sau_nop()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.ket_qua is not null and old.ket_qua is null and exists (select 1 from ipqc_do_lan where id_checkpoint = new.id_checkpoint) then
    perform ipqc_gioi_han_tu_khoa(new.ma_sp);
  end if;
  return new;
exception when others then
  return new;   -- không chặn việc nộp kết quả IPQC
end $$;
drop trigger if exists trg_ipqc_do_sau_nop on duc_ipqc_checkpoint;
create trigger trg_ipqc_do_sau_nop after update of ket_qua on duc_ipqc_checkpoint
  for each row execute function ipqc_do_sau_nop();

-- ── Dữ liệu cho IPQC (lịch sử gần nhất) và biểu đồ QC Manager ─────────────
-- Chỉ lấy lần kiểm đã nộp. p_so_lan: lấy N lần gần nhất (bỏ qua p_tu/p_den nếu có).
create or replace function ipqc_do_du_lieu(p_ma_sp text, p_tu timestamptz, p_den timestamptz, p_so_lan int)
returns jsonb
language sql stable security definer set search_path = public
as $$
  with b as (select * from ipqc_btk where ma_sp = p_ma_sp and dang_dung),
  lan as (
    select l.*, c.ket_qua from ipqc_do_lan l join duc_ipqc_checkpoint c on c.id_checkpoint = l.id_checkpoint and c.ket_qua is not null
    where l.ma_sp = p_ma_sp
      and (p_so_lan is not null or ((p_tu is null or l.thoi_diem >= p_tu) and (p_den is null or l.thoi_diem <= p_den)))
    order by l.thoi_diem desc limit coalesce(p_so_lan, 5000)
  )
  select jsonb_build_object(
    'btk', (select to_jsonb(b) from b),
    'muc', (select coalesce(jsonb_agg(to_jsonb(m) order by m.muc_no), '[]'::jsonb) from ipqc_btk_muc m where m.id_btk = (select id from b)),
    'gioi_han', (select coalesce(jsonb_agg(to_jsonb(h)), '[]'::jsonb) from ipqc_gioi_han h where h.ma_sp = p_ma_sp and h.dang_dung),
    'lan', (select coalesce(jsonb_agg(jsonb_build_object('id_checkpoint', l.id_checkpoint, 'thoi_diem', l.thoi_diem, 'ma_may', l.ma_may,
              'so_khuon', l.so_khuon, 'nguoi', l.nguoi, 'dat', l.dat, 'ket_qua', l.ket_qua,
              'kq', (select coalesce(jsonb_agg(jsonb_build_object('muc_no', k.muc_no, 'mau', k.mau, 'gia_tri', k.gia_tri, 'dat', k.dat)
                       order by k.muc_no, k.mau), '[]'::jsonb) from ipqc_do_kq k where k.id_checkpoint = l.id_checkpoint))
            order by l.thoi_diem), '[]'::jsonb) from lan l));
$$;
revoke execute on function ipqc_do_du_lieu(text, timestamptz, timestamptz, int) from public, anon;
grant execute on function ipqc_do_du_lieu(text, timestamptz, timestamptz, int) to authenticated;

-- ── QC Manager đặt lại giới hạn kiểm soát (cải tiến / điều chỉnh) ─────────
-- p_cach 'tinh_lai': tính từ các lần đo trong [p_tu, p_den] (tối đa 30 lần đầu của khoảng);
--        'tay': p_gt = {cl, ucl, lcl, cl_r, ucl_r}.
create or replace function ipqc_gioi_han_dat(p_ma_sp text, p_muc_no int, p_cach text, p_tu timestamptz, p_den timestamptz,
  p_gt jsonb, p_ghi_chu text, p_nguoi text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare g jsonb; v_so_mau int;
begin
  if not public.has_role('qc_manager', 'admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ QC Manager / admin được đặt giới hạn kiểm soát');
  end if;
  if coalesce(trim(p_ghi_chu), '') = '' then return jsonb_build_object('ok', false, 'error', 'Nhập lý do (cải tiến / điều chỉnh gì)'); end if;
  if p_cach = 'tinh_lai' then
    g := ipqc_gioi_han_tinh(p_ma_sp, p_muc_no, p_tu, p_den, 30);
    if g is null or (g ->> 'n_lan')::int < 10 then
      return jsonb_build_object('ok', false, 'error', 'Khoảng đã chọn có ít hơn 10 lần đo — chưa đủ để tính giới hạn');
    end if;
  elsif p_cach = 'tay' then
    select so_mau into v_so_mau from ipqc_btk where ma_sp = p_ma_sp and dang_dung;
    g := p_gt || jsonb_build_object('so_mau', coalesce(v_so_mau, 1), 'n_lan', 0);
    if (g ->> 'ucl')::numeric is null or (g ->> 'lcl')::numeric is null or (g ->> 'cl')::numeric is null
       or (g ->> 'ucl')::numeric <= (g ->> 'lcl')::numeric then
      return jsonb_build_object('ok', false, 'error', 'Giới hạn nhập tay không hợp lệ (cần CL, UCL > LCL)');
    end if;
  else
    return jsonb_build_object('ok', false, 'error', 'Cách đặt không hợp lệ');
  end if;
  update ipqc_gioi_han set dang_dung = false where ma_sp = p_ma_sp and muc_no = p_muc_no and dang_dung;
  insert into ipqc_gioi_han (ma_sp, muc_no, so_mau, cl, ucl, lcl, cl_r, ucl_r, n_lan, cach, tu_luc, den_luc, ghi_chu, nguoi)
  values (p_ma_sp, p_muc_no, (g ->> 'so_mau')::int, (g ->> 'cl')::numeric, (g ->> 'ucl')::numeric, (g ->> 'lcl')::numeric,
    coalesce((g ->> 'cl_r')::numeric, 0), coalesce((g ->> 'ucl_r')::numeric, 0), (g ->> 'n_lan')::int, p_cach,
    p_tu, p_den, trim(p_ghi_chu), p_nguoi);
  return jsonb_build_object('ok', true, 'gioi_han', g);
end $$;
revoke execute on function ipqc_gioi_han_dat(text, int, text, timestamptz, timestamptz, jsonb, text, text) from public, anon;
grant execute on function ipqc_gioi_han_dat(text, int, text, timestamptz, timestamptz, jsonb, text, text) to authenticated;
