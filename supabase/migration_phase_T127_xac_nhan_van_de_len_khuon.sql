-- ============================================================================
-- T127 — Xác nhận vấn đề lần sản xuất trước khi LÊN KHUÔN (user duyệt 2026-10-20)
--
-- Bước 1 — Trưởng ca: lên khuôn (gán KH / đổi SP / đổi khuôn) mà khuôn còn vấn đề
--   chưa đóng (duc_van_de_khuon) → phải xem danh sách và bấm "Đã nắm thông tin"
--   (RPC duc_khuon_xac_nhan_nam_van_de, hiệu lực 12h cho đúng khuôn + máy, phải
--   bao trùm mọi vấn đề đang mở). Không có → trigger CHẶN CỨNG lên khuôn.
--   Khuôn chạy tiếp trên cùng máy (duc_khuon_dang_tren_may) không hỏi lại.
-- Bước 2 — IPQC kiểm sản phẩm đầu sau lên khuôn (checkpoint doi_khuon, hoặc
--   sau_su_co của sự cố C3 - Đổi khuôn): bắt buộc trả lời từng vấn đề:
--     khong_tai_phat → đóng vấn đề (Xác nhận OK)
--     tai_phat_cb    → tái phát, cho sản xuất tiếp — kết quả lần kiểm ≥ CẢNH BÁO
--     tai_phat_ng    → tái phát, NG dừng sản xuất — kết quả lần kiểm phải NG
--     chua_kiem      → chưa kiểm được (bắt buộc lý do) — hỏi lại ở lần kiểm IPQC sau
--   Trả lời lưu trước qua RPC duc_ipqc_vd_luu; trigger trên duc_ipqc_checkpoint
--   chặn lưu kết quả nếu thiếu / sai mức, và áp dụng khi lần kiểm hoàn tất (hoạt
--   động với cả duc_submit_ipqc_check lẫn duc_submit_ipqc_session).
--   Tái phát: vấn đề cũ mở lại (+1 lần tái phát); khi lần kiểm tự sinh vấn đề
--   mới (NG / Cảnh báo) thì vấn đề cũ được đóng "gộp vào vấn đề mới" để không trùng.
-- Phạm vi: sự cố A2 / B1 / F1 trên khuôn nay cũng tự tạo vấn đề khuôn (trigger
--   duc_su_co_log; F1 do IPQC sinh đã có sẵn thì bỏ qua).
-- Bắt đầu sạch: ĐÓNG TỰ ĐỘNG mọi vấn đề khuôn đang tồn, lưu bản chụp từng dòng
--   ở duc_van_de_khuon_dong_tu_dong (lan = 'T127'), ghi_chu + nguoi_xac_nhan =
--   'Đóng tự động' để truy xuất.
-- Công tắc tắt khẩn cấp (duc_cau_hinh): chan_khuon_chua_nam_van_de,
--   ipqc_bat_buoc_xac_nhan_tai_phat — đặt gia_tri = 'false'.
-- Chạy trên CẢ 2 project. Idempotent (phần đóng tự động chỉ đóng dòng còn mở).
-- ============================================================================

alter table duc_van_de_khuon add column if not exists id_su_co text;
create index if not exists duc_van_de_khuon_mk_tt_idx on duc_van_de_khuon (ma_khuon, trang_thai);

insert into duc_cau_hinh (khoa, gia_tri, ghi_chu) values
  ('chan_khuon_chua_nam_van_de', 'true'::jsonb, 'T127: chặn lên khuôn khi trưởng ca chưa xác nhận đã nắm vấn đề lần SX trước'),
  ('ipqc_bat_buoc_xac_nhan_tai_phat', 'true'::jsonb, 'T127: IPQC kiểm SP đầu sau lên khuôn phải xác nhận tái phát từng vấn đề')
on conflict (khoa) do nothing;

-- ── 1) Bước 1: trưởng ca "Đã nắm thông tin" ────────────────────────────────────
create table if not exists duc_khuon_nam_van_de (
  id            bigserial primary key,
  ma_khuon      text not null,
  ma_may        text not null,
  ds_id_van_de  text[] not null default '{}',
  nguoi         text not null default '',
  nguoi_uid     uuid,
  thoi_diem     timestamptz not null default now(),
  het_han       timestamptz not null default now() + interval '12 hours'
);
create index if not exists duc_khuon_nam_van_de_mk_idx on duc_khuon_nam_van_de (ma_khuon, thoi_diem desc);
alter table duc_khuon_nam_van_de enable row level security;
drop policy if exists "authenticated read" on duc_khuon_nam_van_de;
create policy "authenticated read" on duc_khuon_nam_van_de for select to authenticated using (true);
revoke all on duc_khuon_nam_van_de from anon, authenticated;
grant select on duc_khuon_nam_van_de to authenticated;

-- Danh sách vấn đề chưa đóng của khuôn (dùng chung bước 1 và 2).
create or replace function duc_khuon_vd_mo(p_ma_khuon text)
returns setof duc_van_de_khuon
language sql stable security definer set search_path = public
as $$
  select * from duc_van_de_khuon
  where trim(ma_khuon) = trim(p_ma_khuon) and trang_thai <> 'Đã đóng'
  order by ngay_phat_hien, id_van_de;
$$;
revoke execute on function duc_khuon_vd_mo(text) from public, anon, authenticated;

-- Đã có xác nhận còn hiệu lực bao trùm mọi vấn đề đang mở của khuôn trên máy này?
create or replace function duc_khuon_da_nam_van_de(p_ma_khuon text, p_ma_may text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select not exists (select 1 from duc_khuon_vd_mo(p_ma_khuon))
      or exists (select 1 from duc_khuon_nam_van_de n
                 where trim(n.ma_khuon) = trim(p_ma_khuon)
                   and replace(n.ma_may, ' ', '') = replace(p_ma_may, ' ', '')
                   and n.het_han > now()
                   and n.ds_id_van_de @> (select coalesce(array_agg(id_van_de), '{}') from duc_khuon_vd_mo(p_ma_khuon)));
$$;
revoke execute on function duc_khuon_da_nam_van_de(text, text) from public, anon, authenticated;

-- Dữ liệu cho hộp "Vấn đề lần sản xuất trước" khi lên khuôn.
create or replace function duc_khuon_vd_lan_truoc(p_ma_khuon text, p_ma_may text)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare v_ngay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  return jsonb_build_object('ok', true,
    'bat', coalesce((select gia_tri = 'true'::jsonb from duc_cau_hinh where khoa = 'chan_khuon_chua_nam_van_de'), false),
    'chay_tiep', duc_khuon_dang_tren_may(p_ma_khuon, p_ma_may, v_ngay, null),
    'da_nam', duc_khuon_da_nam_van_de(p_ma_khuon, p_ma_may),
    'van_de', (select coalesce(jsonb_agg(jsonb_build_object(
        'id_van_de', v.id_van_de, 'mo_ta', v.mo_ta, 'ngay_phat_hien', v.ngay_phat_hien, 'ca', v.ca_phat_hien,
        'ma_may', v.ma_may, 'ma_sp', v.ma_sp, 'trang_thai', v.trang_thai, 'noi_dung_xu_ly', v.noi_dung_xu_ly,
        'nguoi_xu_ly', v.nguoi_xu_ly, 'ngay_xu_ly', v.ngay_xu_ly, 'lan_tai_phat', v.lan_tai_phat, 'id_su_co', v.id_su_co)
        order by v.ngay_phat_hien, v.id_van_de), '[]'::jsonb) from duc_khuon_vd_mo(p_ma_khuon) v));
end $$;
revoke execute on function duc_khuon_vd_lan_truoc(text, text) from public, anon;
grant execute on function duc_khuon_vd_lan_truoc(text, text) to authenticated;

create or replace function duc_khuon_xac_nhan_nam_van_de(p_ma_khuon text, p_ma_may text, p_ids text[])
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_mo text[]; v_id bigint;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if coalesce(trim(p_ma_khuon), '') = '' or coalesce(trim(p_ma_may), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu khuôn / máy');
  end if;
  select coalesce(array_agg(id_van_de), '{}') into v_mo from duc_khuon_vd_mo(p_ma_khuon);
  if not (coalesce(p_ids, '{}') @> v_mo) then
    return jsonb_build_object('ok', false, 'error', 'Danh sách vấn đề của khuôn vừa thay đổi — đóng hộp và mở lại để xem bản mới nhất');
  end if;
  insert into duc_khuon_nam_van_de (ma_khuon, ma_may, ds_id_van_de, nguoi, nguoi_uid)
  values (trim(p_ma_khuon), trim(p_ma_may), v_mo, duc_su_co_nguoi_hien_tai(), auth.uid())
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'so_van_de', cardinality(v_mo));
end $$;
revoke execute on function duc_khuon_xac_nhan_nam_van_de(text, text, text[]) from public, anon;
grant execute on function duc_khuon_xac_nhan_nam_van_de(text, text, text[]) to authenticated;

-- Trigger chặn lên khuôn (cùng điều kiện "lên khuôn mới" với T100).
create or replace function duc_ca_hien_tai_chan_khuon_chua_nam_vd()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare v_mk text := trim(coalesce(new.so_khuon, '')); v_n int;
begin
  if v_mk = '' then return new; end if;
  if tg_op = 'UPDATE' and new.so_khuon is not distinct from old.so_khuon then return new; end if;
  if not coalesce((select gia_tri = 'true'::jsonb from duc_cau_hinh where khoa = 'chan_khuon_chua_nam_van_de'), false) then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.ma_may is not distinct from old.ma_may
     and not exists (select 1 from duc_shot_khuon where ma_khuon = trim(coalesce(old.so_khuon, ''))) then
    return new;   -- đổi tên khuôn
  end if;
  if duc_khuon_dang_tren_may(v_mk, new.ma_may, new.ngay, new.id_dong) then return new; end if;
  if duc_khuon_da_nam_van_de(v_mk, new.ma_may) then return new; end if;
  select count(*) into v_n from duc_khuon_vd_mo(v_mk);
  raise exception 'Khuôn % còn % vấn đề của lần sản xuất trước chưa đóng. Trưởng ca phải xem danh sách và bấm "Đã nắm thông tin" trước khi lên khuôn (gán lại khuôn trên Dashboard Đúc / mobile để mở hộp xác nhận).',
    v_mk, v_n;
end $$;
revoke execute on function duc_ca_hien_tai_chan_khuon_chua_nam_vd() from public, anon, authenticated;

drop trigger if exists trg_duc_ca_hien_tai_chan_khuon_chua_nam_vd on duc_ca_hien_tai;
create trigger trg_duc_ca_hien_tai_chan_khuon_chua_nam_vd
  before insert or update of so_khuon, ma_may on duc_ca_hien_tai
  for each row execute function duc_ca_hien_tai_chan_khuon_chua_nam_vd();

-- ── 2) Bước 2: IPQC xác nhận tái phát ─────────────────────────────────────────
create table if not exists duc_ipqc_vd_xac_nhan (
  id             bigserial primary key,
  id_checkpoint  text not null,
  id_van_de      text not null,
  ket_qua        text not null check (ket_qua in ('khong_tai_phat', 'tai_phat_cb', 'tai_phat_ng', 'chua_kiem')),
  ly_do          text not null default '',
  nguoi          text not null default '',
  nguoi_uid      uuid,
  thoi_diem      timestamptz not null default now(),
  da_ap_dung     boolean not null default false,
  unique (id_checkpoint, id_van_de)
);
create index if not exists duc_ipqc_vd_xac_nhan_vd_idx on duc_ipqc_vd_xac_nhan (id_van_de, thoi_diem desc);
alter table duc_ipqc_vd_xac_nhan enable row level security;
drop policy if exists "authenticated read" on duc_ipqc_vd_xac_nhan;
create policy "authenticated read" on duc_ipqc_vd_xac_nhan for select to authenticated using (true);
revoke all on duc_ipqc_vd_xac_nhan from anon, authenticated;
grant select on duc_ipqc_vd_xac_nhan to authenticated;

-- Khuôn của 1 checkpoint (theo dòng ca) + có phải lần kiểm sản phẩm đầu sau lên khuôn.
create or replace function duc_ipqc_vd_ngu_canh(p_id_checkpoint text, out o_ma_khuon text, out o_len_khuon boolean)
language plpgsql stable security definer set search_path = public
as $$
declare v_cp record;
begin
  select id_dong, loai_kiem, id_su_co_goc into v_cp from duc_ipqc_checkpoint where id_checkpoint = p_id_checkpoint;
  if not found then return; end if;
  select nullif(trim(so_khuon), '') into o_ma_khuon from duc_ca_hien_tai where id_dong = v_cp.id_dong;
  o_len_khuon := v_cp.loai_kiem = 'doi_khuon'
    or (v_cp.loai_kiem = 'sau_su_co' and v_cp.id_su_co_goc is not null and (
          exists (select 1 from duc_ca_hien_tai c where c.open_id_su_co = v_cp.id_su_co_goc and left(coalesce(c.open_loai_su_co, ''), 2) = 'C3')
       or exists (select 1 from duc_su_co_log l where l.id_su_co = v_cp.id_su_co_goc and left(coalesce(l.loai_su_co, ''), 2) = 'C3')));
end $$;
revoke execute on function duc_ipqc_vd_ngu_canh(text) from public, anon, authenticated;

-- Vấn đề checkpoint này BẮT BUỘC trả lời: lần kiểm SP đầu sau lên khuôn → mọi vấn đề
-- chưa đóng của khuôn; lần kiểm khác → vấn đề có câu trả lời gần nhất là "chưa kiểm được".
create or replace function duc_ipqc_vd_can_xac_nhan(p_id_checkpoint text)
returns setof text
language plpgsql stable security definer set search_path = public
as $$
declare v record;
begin
  select * into v from duc_ipqc_vd_ngu_canh(p_id_checkpoint);
  if v.o_ma_khuon is null then return; end if;
  if v.o_len_khuon then
    return query select id_van_de from duc_khuon_vd_mo(v.o_ma_khuon);
  else
    return query select m.id_van_de from duc_khuon_vd_mo(v.o_ma_khuon) m
      where (select x.ket_qua from duc_ipqc_vd_xac_nhan x where x.id_van_de = m.id_van_de and x.da_ap_dung
             order by x.thoi_diem desc limit 1) = 'chua_kiem';
  end if;
end $$;
revoke execute on function duc_ipqc_vd_can_xac_nhan(text) from public, anon, authenticated;

create or replace function duc_ipqc_vd_danh_sach(p_id_checkpoint text)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare v record;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into v from duc_ipqc_vd_ngu_canh(p_id_checkpoint);
  return jsonb_build_object('ok', true,
    'bat', coalesce((select gia_tri = 'true'::jsonb from duc_cau_hinh where khoa = 'ipqc_bat_buoc_xac_nhan_tai_phat'), false),
    'ma_khuon', v.o_ma_khuon, 'len_khuon', coalesce(v.o_len_khuon, false),
    'van_de', (select coalesce(jsonb_agg(jsonb_build_object(
        'id_van_de', d.id_van_de, 'mo_ta', d.mo_ta, 'ngay_phat_hien', d.ngay_phat_hien, 'ca', d.ca_phat_hien,
        'ma_may', d.ma_may, 'ma_sp', d.ma_sp, 'trang_thai', d.trang_thai, 'noi_dung_xu_ly', d.noi_dung_xu_ly,
        'nguoi_xu_ly', d.nguoi_xu_ly, 'lan_tai_phat', d.lan_tai_phat, 'id_su_co', d.id_su_co,
        'anh', (select c.anh_bang_chung_url from duc_ipqc_checkpoint c where c.id_van_de_lien_quan = d.id_van_de limit 1),
        'lan_truoc', (select jsonb_build_object('ket_qua', x.ket_qua, 'ly_do', x.ly_do, 'nguoi', x.nguoi, 'thoi_diem', x.thoi_diem)
                      from duc_ipqc_vd_xac_nhan x where x.id_van_de = d.id_van_de and x.da_ap_dung order by x.thoi_diem desc limit 1),
        'da_tra_loi', (select jsonb_build_object('ket_qua', x.ket_qua, 'ly_do', x.ly_do)
                       from duc_ipqc_vd_xac_nhan x where x.id_van_de = d.id_van_de and x.id_checkpoint = p_id_checkpoint))
        order by d.ngay_phat_hien, d.id_van_de), '[]'::jsonb)
      from duc_van_de_khuon d where d.id_van_de in (select duc_ipqc_vd_can_xac_nhan(p_id_checkpoint))));
end $$;
revoke execute on function duc_ipqc_vd_danh_sach(text) from public, anon;
grant execute on function duc_ipqc_vd_danh_sach(text) to authenticated;

-- p_tra_loi: [{id_van_de, ket_qua, ly_do}]
create or replace function duc_ipqc_vd_luu(p_id_checkpoint text, p_tra_loi jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_tt text; v_can text[]; e jsonb; v_n int := 0; v_nguoi text := duc_su_co_nguoi_hien_tai();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select trang_thai into v_tt from duc_ipqc_checkpoint where id_checkpoint = p_id_checkpoint;
  if v_tt is null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy điểm kiểm'); end if;
  if v_tt = 'da_kiem' then return jsonb_build_object('ok', false, 'error', 'Điểm kiểm này đã được xử lý trước đó'); end if;
  select coalesce(array_agg(x), '{}') into v_can from duc_ipqc_vd_can_xac_nhan(p_id_checkpoint) x;
  for e in select * from jsonb_array_elements(coalesce(p_tra_loi, '[]'::jsonb)) loop
    if not (e->>'id_van_de' = any(v_can)) then continue; end if;
    if coalesce(e->>'ket_qua', '') not in ('khong_tai_phat', 'tai_phat_cb', 'tai_phat_ng', 'chua_kiem') then
      return jsonb_build_object('ok', false, 'error', 'Câu trả lời không hợp lệ');
    end if;
    if e->>'ket_qua' = 'chua_kiem' and coalesce(trim(e->>'ly_do'), '') = '' then
      return jsonb_build_object('ok', false, 'error', '"Chưa kiểm được" phải ghi lý do');
    end if;
    insert into duc_ipqc_vd_xac_nhan (id_checkpoint, id_van_de, ket_qua, ly_do, nguoi, nguoi_uid)
    values (p_id_checkpoint, e->>'id_van_de', e->>'ket_qua', coalesce(trim(e->>'ly_do'), ''), v_nguoi, auth.uid())
    on conflict (id_checkpoint, id_van_de) do update set ket_qua = excluded.ket_qua, ly_do = excluded.ly_do,
      nguoi = excluded.nguoi, nguoi_uid = excluded.nguoi_uid, thoi_diem = now();
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'so_luu', v_n);
end $$;
revoke execute on function duc_ipqc_vd_luu(text, jsonb) from public, anon;
grant execute on function duc_ipqc_vd_luu(text, jsonb) to authenticated;

-- Chặn lưu kết quả kiểm khi thiếu / sai mức (BEFORE UPDATE).
create or replace function duc_ipqc_vd_kiem_tra()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare v_thieu int; v_ng boolean; v_cb boolean;
begin
  if not (new.trang_thai = 'da_kiem' and old.trang_thai is distinct from 'da_kiem') then return new; end if;
  if not coalesce((select gia_tri = 'true'::jsonb from duc_cau_hinh where khoa = 'ipqc_bat_buoc_xac_nhan_tai_phat'), false) then
    return new;
  end if;
  select count(*) into v_thieu from duc_ipqc_vd_can_xac_nhan(new.id_checkpoint) c
  where not exists (select 1 from duc_ipqc_vd_xac_nhan x where x.id_checkpoint = new.id_checkpoint and x.id_van_de = c);
  if v_thieu > 0 then
    raise exception 'Còn % vấn đề của lần sản xuất trước chưa xác nhận tái phát hay không — chọn cho từng vấn đề ở khung "Vấn đề lần sản xuất trước" rồi lưu lại.', v_thieu;
  end if;
  select bool_or(ket_qua = 'tai_phat_ng'), bool_or(ket_qua = 'tai_phat_cb') into v_ng, v_cb
  from duc_ipqc_vd_xac_nhan x where x.id_checkpoint = new.id_checkpoint
    and x.id_van_de in (select duc_ipqc_vd_can_xac_nhan(new.id_checkpoint));
  if coalesce(v_ng, false) and new.ket_qua is distinct from 'NG' then
    raise exception 'Có vấn đề tái phát được đánh giá NG (dừng sản xuất) — kết quả lần kiểm phải là NG.';
  end if;
  if coalesce(v_cb, false) and coalesce(new.ket_qua, '') not in ('NG', 'CANH_BAO') then
    raise exception 'Có vấn đề tái phát — kết quả lần kiểm phải là Cảnh báo hoặc NG, không được OK.';
  end if;
  return new;
end $$;
revoke execute on function duc_ipqc_vd_kiem_tra() from public, anon, authenticated;

drop trigger if exists trg_duc_ipqc_vd_kiem_tra on duc_ipqc_checkpoint;
create trigger trg_duc_ipqc_vd_kiem_tra
  before update of trang_thai on duc_ipqc_checkpoint
  for each row execute function duc_ipqc_vd_kiem_tra();

-- Áp dụng câu trả lời khi lần kiểm hoàn tất (AFTER UPDATE).
create or replace function duc_ipqc_vd_ap_dung()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare r record; v_stamp text := to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI'); v_nguoi text;
begin
  -- (a) Lần kiểm vừa hoàn tất → áp dụng từng câu trả lời.
  if new.trang_thai = 'da_kiem' and old.trang_thai is distinct from 'da_kiem' then
    v_nguoi := coalesce(nullif(new.nguoi_kiem, ''), duc_su_co_nguoi_hien_tai());
    for r in select x.* from duc_ipqc_vd_xac_nhan x where x.id_checkpoint = new.id_checkpoint and not x.da_ap_dung loop
      if r.ket_qua = 'khong_tai_phat' then
        update duc_van_de_khuon set trang_thai = 'Đã đóng', ket_qua_xac_nhan = 'OK', nguoi_xac_nhan = v_nguoi,
          ngay_xac_nhan = (now() at time zone 'Asia/Ho_Chi_Minh')::date, last_updated_at = now(),
          ghi_chu = coalesce(nullif(ghi_chu, '') || E'\n', '') || '[' || v_stamp || '] IPQC xác nhận KHÔNG tái phát khi lên khuôn (' || v_nguoi || ', ' || new.id_checkpoint || ')'
        where id_van_de = r.id_van_de and trang_thai <> 'Đã đóng';
      elsif r.ket_qua in ('tai_phat_cb', 'tai_phat_ng') then
        update duc_van_de_khuon set trang_thai = 'Mở', ket_qua_xac_nhan = 'Tái phát', lan_tai_phat = coalesce(lan_tai_phat, 0) + 1,
          nguoi_xac_nhan = v_nguoi, ngay_xac_nhan = (now() at time zone 'Asia/Ho_Chi_Minh')::date, last_updated_at = now(),
          ghi_chu = coalesce(nullif(ghi_chu, '') || E'\n', '') || '[' || v_stamp || '] IPQC xác nhận TÁI PHÁT khi lên khuôn — '
            || case when r.ket_qua = 'tai_phat_ng' then 'NG dừng sản xuất' else 'Cảnh báo, cho sản xuất tiếp' end
            || ' (' || v_nguoi || ', ' || new.id_checkpoint || ')'
        where id_van_de = r.id_van_de and trang_thai <> 'Đã đóng';
      else
        update duc_van_de_khuon set last_updated_at = now(),
          ghi_chu = coalesce(nullif(ghi_chu, '') || E'\n', '') || '[' || v_stamp || '] IPQC chưa kiểm được tái phát khi lên khuôn: ' || r.ly_do
            || ' (' || v_nguoi || ', ' || new.id_checkpoint || ')'
        where id_van_de = r.id_van_de;
      end if;
      update duc_ipqc_vd_xac_nhan set da_ap_dung = true where id = r.id;
    end loop;
  end if;
  -- (b) Lần kiểm tự sinh vấn đề mới (NG / Cảnh báo) → vấn đề cũ tái phát gộp vào đó, không để trùng.
  if new.id_van_de_lien_quan is not null and old.id_van_de_lien_quan is distinct from new.id_van_de_lien_quan then
    update duc_van_de_khuon m set
      lan_tai_phat = greatest(coalesce(m.lan_tai_phat, 0),
        (select max(coalesce(o.lan_tai_phat, 0)) from duc_van_de_khuon o join duc_ipqc_vd_xac_nhan x on x.id_van_de = o.id_van_de
         where x.id_checkpoint = new.id_checkpoint and x.ket_qua in ('tai_phat_cb', 'tai_phat_ng'))),
      ghi_chu = coalesce(nullif(m.ghi_chu, '') || E'\n', '') || 'Tái phát của: ' ||
        (select string_agg(x.id_van_de, ', ') from duc_ipqc_vd_xac_nhan x where x.id_checkpoint = new.id_checkpoint and x.ket_qua in ('tai_phat_cb', 'tai_phat_ng'))
    where m.id_van_de = new.id_van_de_lien_quan
      and exists (select 1 from duc_ipqc_vd_xac_nhan x where x.id_checkpoint = new.id_checkpoint and x.ket_qua in ('tai_phat_cb', 'tai_phat_ng'));
    update duc_van_de_khuon o set trang_thai = 'Đã đóng', last_updated_at = now(),
      ghi_chu = coalesce(nullif(o.ghi_chu, '') || E'\n', '') || '[' || v_stamp || '] Gộp vào vấn đề mới ' || new.id_van_de_lien_quan || ' (tái phát)'
    from duc_ipqc_vd_xac_nhan x
    where x.id_checkpoint = new.id_checkpoint and x.ket_qua in ('tai_phat_cb', 'tai_phat_ng')
      and o.id_van_de = x.id_van_de and o.id_van_de <> new.id_van_de_lien_quan and o.trang_thai <> 'Đã đóng';
  end if;
  return null;
end $$;
revoke execute on function duc_ipqc_vd_ap_dung() from public, anon, authenticated;

drop trigger if exists trg_duc_ipqc_vd_ap_dung on duc_ipqc_checkpoint;
create trigger trg_duc_ipqc_vd_ap_dung
  after update of trang_thai, id_van_de_lien_quan on duc_ipqc_checkpoint
  for each row execute function duc_ipqc_vd_ap_dung();

-- ── 3) Sự cố A2 / B1 / F1 trên khuôn → vấn đề khuôn ─────────────────────────────
create or replace function duc_su_co_tao_van_de_khuon()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare v_ma text := left(coalesce(new.loai_su_co, ''), 2); v_mk text := trim(coalesce(new.so_khuon, '')); v_id text; v_nguoi text;
begin
  if new.id_su_co is null or v_mk = '' or v_ma not in ('A2', 'B1', 'F1') then return null; end if;
  v_id := 'VDK_SC_' || new.id_su_co || '_' || duc_normalize_name(v_mk);
  if exists (select 1 from duc_van_de_khuon where id_van_de = v_id) then return null; end if;
  -- F1 do IPQC sinh đã có vấn đề khuôn cùng nội dung → bỏ qua.
  if v_ma = 'F1' and exists (select 1 from duc_van_de_khuon where trim(ma_khuon) = v_mk and mo_ta = new.van_de) then return null; end if;
  select k.nguoi into v_nguoi from duc_su_co_nhat_ky k where k.id_su_co = new.id_su_co and k.su_kien = 'mo' order by k.thoi_diem limit 1;
  insert into duc_van_de_khuon (id_van_de, ma_khuon, ngay_phat_hien, ca_phat_hien, ma_may, ma_sp, mo_ta, nguoi_phat_hien,
                                trang_thai, lan_tai_phat, ghi_chu, id_su_co, last_updated_at)
  values (v_id, v_mk, new.ngay, new.ca, new.ma_may, new.ma_sp,
          new.loai_su_co || ': ' || coalesce(nullif(trim(new.van_de), ''), '(không mô tả)'),
          coalesce(v_nguoi, nullif(new.truong_ca, ''), ''), 'Mở', 0,
          'Tự tạo từ sự cố ' || new.id_su_co || case when coalesce(trim(new.noi_dung_xu_ly), '') <> '' then '. Sản xuất đã xử lý: ' || trim(new.noi_dung_xu_ly) else '' end,
          new.id_su_co, now());
  return null;
exception when others then
  raise warning 'duc_su_co_tao_van_de_khuon: %', sqlerrm;
  return null;
end $$;
revoke execute on function duc_su_co_tao_van_de_khuon() from public, anon, authenticated;

drop trigger if exists trg_duc_su_co_tao_van_de_khuon on duc_su_co_log;
create trigger trg_duc_su_co_tao_van_de_khuon
  after insert on duc_su_co_log
  for each row execute function duc_su_co_tao_van_de_khuon();

-- ── 4) Bắt đầu sạch: đóng tự động mọi vấn đề khuôn đang tồn (có bản chụp) ──────
create table if not exists duc_van_de_khuon_dong_tu_dong (
  id          bigserial primary key,
  lan         text not null,
  thoi_diem   timestamptz not null default now(),
  id_van_de   text not null,
  du_lieu     jsonb not null      -- nguyên dòng duc_van_de_khuon TRƯỚC khi đóng
);
alter table duc_van_de_khuon_dong_tu_dong enable row level security;
drop policy if exists "authenticated read" on duc_van_de_khuon_dong_tu_dong;
create policy "authenticated read" on duc_van_de_khuon_dong_tu_dong for select to authenticated using (true);
revoke all on duc_van_de_khuon_dong_tu_dong from anon, authenticated;
grant select on duc_van_de_khuon_dong_tu_dong to authenticated;

insert into duc_van_de_khuon_dong_tu_dong (lan, id_van_de, du_lieu)
select 'T127', v.id_van_de, to_jsonb(v) from duc_van_de_khuon v where v.trang_thai <> 'Đã đóng';

update duc_van_de_khuon set
  ghi_chu = coalesce(nullif(ghi_chu, '') || E'\n', '') || '[' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
    || '] Đóng tự động khi bắt đầu quy trình xác nhận vấn đề lúc lên khuôn (T127) — trạng thái trước: ' || trang_thai,
  trang_thai = 'Đã đóng', ket_qua_xac_nhan = 'Đóng tự động', nguoi_xac_nhan = 'Đóng tự động',
  ngay_xac_nhan = (now() at time zone 'Asia/Ho_Chi_Minh')::date, last_updated_at = now()
where trang_thai <> 'Đã đóng';
