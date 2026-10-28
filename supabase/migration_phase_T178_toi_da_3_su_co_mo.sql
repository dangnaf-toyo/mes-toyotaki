-- T178 (27/10/2026): mỗi dòng máy (duc_ca_hien_tai) mở được TỐI ĐA 3 sự cố cùng lúc.
-- (Viết ban đầu với mã T176 — đổi sang T178 vì T176/T177 đồng đội đã dùng cho QC. DB staging đã chạy bản mang dấu "T176" trong chú thích hàm.)
--
-- Thiết kế (ít đụng code cũ nhất):
--  * Sự cố CHÍNH vẫn ở các cột open_* của duc_ca_hien_tai — mọi logic cũ (máy dừng/chạy, chặn đổi SP,
--    xoá kế hoạch, kết ca, IPQC T170/T174, quyền vượt T172/T173) giữ nguyên.
--  * Sự cố 2, 3 ở bảng mới duc_su_co_mo_them. Khi chỗ chính trống (đóng / xoá / F1 tự đóng) thì
--    duc_clear_incident_open tự đưa sự cố PHỤ sớm nhất lên chỗ chính → bất biến: có sự cố phụ ⇒ chỗ chính có.
--  * Đóng / sửa / xoá 1 sự cố phụ: đổi chỗ nó với sự cố chính (duc_su_co_doi_cho) rồi gọi ĐÚNG hàm cũ
--    (duc_resolve_incident / duc_edit_open_incident / duc_delete_incident) → chung 1 chỗ kiểm IPQC, ghi log.
--    Hàm mới *_x nhận p_id_su_co; giao diện cũ (cache) vẫn gọi hàm cũ = thao tác trên sự cố chính.
--  * Phút dừng MÁY tính 1 lần khi sự cố chồng giờ: cột duc_su_co_log.phut_dung_may (trigger tự tính, cùng
--    máy + mã SP, sự cố phát sinh trước được tính trước). thoi_gian_dung_phut giữ nguyên = phút của từng sự cố
--    (phân tích theo loại / vấn đề). Chỉ áp từ mốc duc_moc_phut_dung_may(); trước mốc phut_dung_may = thoi_gian_dung_phut
--    (dữ liệu cũ có 221 cặp chồng giờ do sửa giờ thủ công — không đổi số báo cáo quá khứ).
--  * Khoá các hàm nội bộ set/clear/close_f1 (trước đây authenticated gọi thẳng được → lách chặn IPQC).

-- ── 1. Bảng sự cố mở thêm ───────────────────────────────────────────────────
create table if not exists public.duc_su_co_mo_them (
  id bigserial primary key,
  id_dong text not null references public.duc_ca_hien_tai(id_dong) on update cascade on delete cascade,
  loai_su_co text not null,
  gio_phat_sinh timestamptz not null,
  van_de text not null default '',
  noi_dung_xu_ly text not null default '',
  dam_nhiem text not null default '',
  id_su_co text not null unique,
  tao_luc timestamptz not null default now()
);
create index if not exists duc_su_co_mo_them_id_dong_idx on public.duc_su_co_mo_them (id_dong);
alter table public.duc_su_co_mo_them enable row level security;
drop policy if exists "public read" on public.duc_su_co_mo_them;
create policy "public read" on public.duc_su_co_mo_them for select using (true);
grant select on public.duc_su_co_mo_them to anon, authenticated;
revoke insert, update, delete, truncate on public.duc_su_co_mo_them from anon, authenticated;

-- ── 2. Helper nội bộ ─────────────────────────────────────────────────────────
-- Mã sự cố không trùng sự cố đang mở / đã đóng (2 sự cố cùng máy cùng phút → thêm hậu tố -2, -3).
create or replace function public.duc_id_su_co_moi(p_ma_may text, p_gio timestamptz)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_goc text := duc_make_id_su_co(p_ma_may, p_gio); v_id text := v_goc; i int := 1;
begin
  while exists (select 1 from duc_ca_hien_tai where open_id_su_co = v_id)
     or exists (select 1 from duc_su_co_mo_them where id_su_co = v_id)
     or exists (select 1 from duc_su_co_log where id_su_co = v_id) loop
    i := i + 1; v_id := v_goc || '-' || i;
  end loop;
  return v_id;
end $$;

-- Chỗ chính trống mà còn sự cố phụ → đưa sự cố phụ phát sinh sớm nhất lên.
create or replace function public.duc_su_co_phu_len_chinh(p_id_dong text)
returns void language plpgsql security definer set search_path = public as $$
declare x record;
begin
  if exists (select 1 from duc_ca_hien_tai where id_dong = p_id_dong and open_gio_phat_sinh is not null) then return; end if;
  select * into x from duc_su_co_mo_them where id_dong = p_id_dong order by gio_phat_sinh, id limit 1;
  if not found then return; end if;
  update duc_ca_hien_tai set
    open_loai_su_co = x.loai_su_co, open_gio_phat_sinh = x.gio_phat_sinh, open_van_de = x.van_de,
    open_noi_dung_xu_ly = x.noi_dung_xu_ly, open_dam_nhiem = x.dam_nhiem, open_id_su_co = x.id_su_co,
    version = coalesce(version, 0) + 1, last_updated_at = now()
  where id_dong = p_id_dong;
  delete from duc_su_co_mo_them where id = x.id;
end $$;

-- Đổi chỗ sự cố phụ p_id_su_co với sự cố chính của dòng. Trả về mã sự cố vừa bị đẩy xuống phụ
-- (để đổi lại), null nếu không đổi được. p_id_su_co đã là sự cố chính → trả về chính nó.
create or replace function public.duc_su_co_doi_cho(p_id_dong text, p_id_su_co text)
returns text language plpgsql security definer set search_path = public as $$
declare c record; x record; v_id_chinh text;
begin
  select * into c from duc_ca_hien_tai where id_dong = p_id_dong for update;
  if not found or c.open_gio_phat_sinh is null then return null; end if;
  if c.open_id_su_co = p_id_su_co then return p_id_su_co; end if;
  select * into x from duc_su_co_mo_them where id_dong = p_id_dong and id_su_co = p_id_su_co for update;
  if not found then return null; end if;
  v_id_chinh := coalesce(c.open_id_su_co, duc_id_su_co_moi(c.ma_may, c.open_gio_phat_sinh));   -- dòng cũ chưa có mã
  update duc_su_co_mo_them set
    loai_su_co = coalesce(nullif(c.open_loai_su_co, ''), '?'), gio_phat_sinh = c.open_gio_phat_sinh,
    van_de = coalesce(c.open_van_de, ''), noi_dung_xu_ly = coalesce(c.open_noi_dung_xu_ly, ''),
    dam_nhiem = coalesce(c.open_dam_nhiem, ''), id_su_co = v_id_chinh
  where id = x.id;
  update duc_ca_hien_tai set
    open_loai_su_co = x.loai_su_co, open_gio_phat_sinh = x.gio_phat_sinh, open_van_de = x.van_de,
    open_noi_dung_xu_ly = x.noi_dung_xu_ly, open_dam_nhiem = x.dam_nhiem, open_id_su_co = x.id_su_co
  where id_dong = p_id_dong;
  return v_id_chinh;
end $$;

-- ── 3. Mở sự cố: chỗ chính bận → sự cố phụ (tối đa 2 phụ = 3 sự cố) ─────────
create or replace function public.duc_set_incident_open(p_id_dong text, p_loai text, p_gio_phat_sinh timestamptz, p_van_de text, p_noi_dung_xu_ly text, p_dam_nhiem text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_current record;
  v_new_version bigint;
  v_id_su_co text;
begin
  select ma_may, open_gio_phat_sinh, version into v_current from duc_ca_hien_tai where id_dong = p_id_dong for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng: ' || p_id_dong);
  end if;

  v_id_su_co := duc_id_su_co_moi(v_current.ma_may, p_gio_phat_sinh);
  v_new_version := coalesce(v_current.version, 0) + 1;

  if v_current.open_gio_phat_sinh is not null then
    -- T178: đã có sự cố chính → thêm sự cố phụ (tối đa 3 sự cố đang mở / dòng)
    if (select count(*) from duc_su_co_mo_them where id_dong = p_id_dong) >= 2 then
      return jsonb_build_object('ok', false, 'error', 'Máy này đã có 3 sự cố đang mở (tối đa 3). Xử lý xong 1 sự cố rồi mới thêm được.');
    end if;
    insert into duc_su_co_mo_them (id_dong, loai_su_co, gio_phat_sinh, van_de, noi_dung_xu_ly, dam_nhiem, id_su_co)
    values (p_id_dong, p_loai, p_gio_phat_sinh, coalesce(p_van_de, ''), coalesce(p_noi_dung_xu_ly, ''), coalesce(p_dam_nhiem, ''), v_id_su_co);
    update duc_ca_hien_tai set version = v_new_version, last_updated_by = coalesce(p_dam_nhiem, 'system'), last_updated_at = now()
    where id_dong = p_id_dong;
    return jsonb_build_object('ok', true, 'id_dong', p_id_dong, 'version', v_new_version, 'id_su_co', v_id_su_co, 'su_co_phu', true);
  end if;

  update duc_ca_hien_tai set
    open_loai_su_co = p_loai, open_gio_phat_sinh = p_gio_phat_sinh,
    open_van_de = coalesce(p_van_de, ''), open_noi_dung_xu_ly = coalesce(p_noi_dung_xu_ly, ''),
    open_dam_nhiem = coalesce(p_dam_nhiem, ''), open_id_su_co = v_id_su_co,
    version = v_new_version, last_updated_by = coalesce(p_dam_nhiem, 'system'), last_updated_at = now()
  where id_dong = p_id_dong;

  return jsonb_build_object('ok', true, 'id_dong', p_id_dong, 'version', v_new_version, 'id_su_co', v_id_su_co);
end $$;

-- ── 4. Xoá chỗ chính → đưa sự cố phụ lên ────────────────────────────────────
create or replace function public.duc_clear_incident_open(p_id_dong text, p_user text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update duc_ca_hien_tai set
    open_loai_su_co = '', open_gio_phat_sinh = null, open_van_de = '',
    open_noi_dung_xu_ly = '', open_dam_nhiem = '', open_id_su_co = null,
    version = coalesce(version, 0) + 1, last_updated_by = p_user, last_updated_at = now()
  where id_dong = p_id_dong;
  perform duc_su_co_phu_len_chinh(p_id_dong);   -- T178
end $$;

-- ── 5. Đóng / sửa / xoá theo mã sự cố (giao diện mới) ───────────────────────
create or replace function public.duc_resolve_incident_x(p_id_dong text, p_id_su_co text, p_gio_tro_lai timestamptz, p_bonus_note text, p_truong_ca text, p_user text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_chinh text; v_xuong text; r jsonb;
begin
  select open_id_su_co into v_chinh from duc_ca_hien_tai where id_dong = p_id_dong;
  if p_id_su_co is null or p_id_su_co = coalesce(v_chinh, '') then
    return duc_resolve_incident(p_id_dong, p_gio_tro_lai, p_bonus_note, p_truong_ca, p_user);
  end if;
  v_xuong := duc_su_co_doi_cho(p_id_dong, p_id_su_co);
  if v_xuong is null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố ' || p_id_su_co || ' đang mở trên dòng này — tải lại trang.'); end if;
  r := duc_resolve_incident(p_id_dong, p_gio_tro_lai, p_bonus_note, p_truong_ca, p_user);
  if not coalesce((r->>'ok')::boolean, false) then perform duc_su_co_doi_cho(p_id_dong, v_xuong); end if;   -- trả chỗ cũ
  return r;
end $$;

create or replace function public.duc_edit_open_incident_x(p_id_dong text, p_id_su_co text, p_loai text, p_gio_phat_sinh timestamptz, p_van_de text, p_noi_dung_xu_ly text, p_dam_nhiem text, p_user text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_chinh text; v_xuong text; r jsonb;
begin
  select open_id_su_co into v_chinh from duc_ca_hien_tai where id_dong = p_id_dong;
  if p_id_su_co is null or p_id_su_co = coalesce(v_chinh, '') then
    return duc_edit_open_incident(p_id_dong, p_loai, p_gio_phat_sinh, p_van_de, p_noi_dung_xu_ly, p_dam_nhiem, p_user);
  end if;
  v_xuong := duc_su_co_doi_cho(p_id_dong, p_id_su_co);
  if v_xuong is null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố ' || p_id_su_co || ' đang mở trên dòng này — tải lại trang.'); end if;
  r := duc_edit_open_incident(p_id_dong, p_loai, p_gio_phat_sinh, p_van_de, p_noi_dung_xu_ly, p_dam_nhiem, p_user);
  perform duc_su_co_doi_cho(p_id_dong, v_xuong);   -- sửa xong (hay lỗi) đều trả về chỗ phụ
  return r;
end $$;

create or replace function public.duc_delete_open_incident_x(p_id_dong text, p_id_su_co text, p_user text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_chinh text; v_xuong text; r jsonb;
begin
  select open_id_su_co into v_chinh from duc_ca_hien_tai where id_dong = p_id_dong;
  if p_id_su_co is null or p_id_su_co = coalesce(v_chinh, '') then
    return duc_delete_incident('open', p_id_dong, null, p_user);
  end if;
  v_xuong := duc_su_co_doi_cho(p_id_dong, p_id_su_co);
  if v_xuong is null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố ' || p_id_su_co || ' đang mở trên dòng này — tải lại trang.'); end if;
  r := duc_delete_incident('open', p_id_dong, null, p_user);
  if not coalesce((r->>'ok')::boolean, false) then perform duc_su_co_doi_cho(p_id_dong, v_xuong); end if;
  return r;
end $$;

-- ── 6. Vá hàm cũ (replace trên định nghĩa đang chạy) ────────────────────────
do $$
declare d text;
begin
  -- 6a. IPQC OK tự đóng F1: F1 nằm ở chỗ phụ thì đổi lên chỗ chính trước
  d := replace(pg_get_functiondef('public.duc_close_f1_incident_if_open'::regproc), E'\r\n', E'\n');
  if strpos(d, 'T178') = 0 then
    d := replace(d, E'begin\n  select ngay, ca, ma_may, ma_sp, ten_sp, so_khuon, open_loai_su_co, open_gio_phat_sinh,',
      E'begin\n  -- T178: sự cố F1 đang ở chỗ phụ → đổi lên chỗ chính để đóng\n' ||
      E'  if exists (select 1 from duc_ca_hien_tai where id_dong = p_id_dong and left(coalesce(open_loai_su_co, ''''), 2) <> ''F1'') then\n' ||
      E'    perform duc_su_co_doi_cho(p_id_dong, (select id_su_co from duc_su_co_mo_them where id_dong = p_id_dong and left(loai_su_co, 2) = ''F1'' order by gio_phat_sinh, id limit 1));\n' ||
      E'  end if;\n  select ngay, ca, ma_may, ma_sp, ten_sp, so_khuon, open_loai_su_co, open_gio_phat_sinh,');
    if strpos(d, 'T178') = 0 then raise exception 'T178: không vá được duc_close_f1_incident_if_open'; end if;
    execute d;
  end if;

  -- 6b. Kết ca chuyển tiếp: sự cố phụ đi theo dòng sang ca sau
  d := replace(pg_get_functiondef('public.duc_carry_over_shift'::regproc), E'\r\n', E'\n');
  if strpos(d, 'T178') = 0 then
    d := replace(d, E'    v_old_to_new := jsonb_set(v_old_to_new, array[v_old.id_dong], to_jsonb(v_new_id_dong));',
      E'    -- T178: sự cố mở thêm (2, 3) đi theo dòng sang ca sau\n' ||
      E'    update duc_su_co_mo_them set id_dong = v_new_id_dong,\n' ||
      E'      noi_dung_xu_ly = noi_dung_xu_ly || case when noi_dung_xu_ly <> '''' then E''\\n'' else '''' end || ''[Chuyển tiếp từ '' || p_ca || '' '' || to_char(p_ngay, ''DD/MM/YYYY'') || '']''\n' ||
      E'    where id_dong = v_old.id_dong;\n' ||
      E'    v_old_to_new := jsonb_set(v_old_to_new, array[v_old.id_dong], to_jsonb(v_new_id_dong));');
    if strpos(d, 'T178') = 0 then raise exception 'T178: không vá được duc_carry_over_shift'; end if;
    execute d;
  end if;

  -- 6c. Thêm ảnh: chấp nhận mã sự cố phụ
  d := pg_get_functiondef('public.duc_su_co_them_anh'::regproc);
  if strpos(d, 'T178') = 0 then
    d := replace(d, 'if not exists (select 1 from duc_ca_hien_tai where open_id_su_co = v_id)',
      'if not exists (select 1 from duc_ca_hien_tai where open_id_su_co = v_id)' || E'\n' ||
      '     and not exists (select 1 from duc_su_co_mo_them where id_su_co = v_id)   -- T178');
    if strpos(d, 'T178') = 0 then raise exception 'T178: không vá được duc_su_co_them_anh'; end if;
    execute d;
  end if;
end $$;

-- ── 7. Phút dừng máy tính 1 lần (sự cố chồng giờ trên cùng máy + mã SP) ──────
alter table public.duc_su_co_log add column if not exists phut_dung_may numeric;
comment on column public.duc_su_co_log.phut_dung_may is
  'T178: phút dừng MÁY của bản ghi sau khi trừ phần chồng giờ với sự cố phát sinh trước (cùng máy + mã SP). Tổng theo máy/ca = thời gian dừng thực tế. thoi_gian_dung_phut = phút của riêng sự cố.';

create or replace function public.duc_moc_phut_dung_may()
returns timestamptz language sql immutable as $$ select timestamptz '2026-10-27 00:00:00+07' $$;

create or replace function public.duc_tinh_phut_dung_may(p_ma_may text, p_ma_sp text)
returns void language plpgsql security definer set search_path = public as $$
declare r record; acc tstzmultirange := '{}'; rg tstzrange; ov numeric; v numeric; v_moc timestamptz := duc_moc_phut_dung_may();
begin
  for r in
    select id_ban_ghi, gio_phat_sinh, gio_tro_lai, thoi_gian_dung_phut, phut_dung_may from duc_su_co_log
     where ma_may = p_ma_may and ma_sp is not distinct from p_ma_sp
       and (gio_phat_sinh >= v_moc or phut_dung_may is distinct from thoi_gian_dung_phut)
     order by gio_phat_sinh nulls last, id_ban_ghi
  loop
    if r.gio_phat_sinh is null or r.gio_phat_sinh < v_moc or r.gio_tro_lai is null or r.gio_tro_lai <= r.gio_phat_sinh then
      v := r.thoi_gian_dung_phut;
    else
      rg := tstzrange(r.gio_phat_sinh, r.gio_tro_lai);
      select coalesce(sum(extract(epoch from upper(x) - lower(x))), 0) into ov from unnest(acc * tstzmultirange(rg)) x;
      v := greatest(0, coalesce(r.thoi_gian_dung_phut, 0) - round(ov / 60));
      acc := acc + tstzmultirange(rg);
    end if;
    if r.phut_dung_may is distinct from v then
      update duc_su_co_log set phut_dung_may = v where id_ban_ghi = r.id_ban_ghi;
    end if;
  end loop;
end $$;

create or replace function public.duc_su_co_log_phut_dung_may_trg()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then perform duc_tinh_phut_dung_may(old.ma_may, old.ma_sp); end if;
  if tg_op in ('INSERT', 'UPDATE') then perform duc_tinh_phut_dung_may(new.ma_may, new.ma_sp); end if;
  return null;
end $$;

drop trigger if exists trg_duc_su_co_log_phut_dung_may on public.duc_su_co_log;
create trigger trg_duc_su_co_log_phut_dung_may
  after insert or delete or update of gio_phat_sinh, gio_tro_lai, thoi_gian_dung_phut, ma_may, ma_sp
  on public.duc_su_co_log for each row execute function public.duc_su_co_log_phut_dung_may_trg();

-- Backfill: trước mốc = giữ nguyên; từ mốc = tính theo chồng giờ
update public.duc_su_co_log set phut_dung_may = thoi_gian_dung_phut where phut_dung_may is null and gio_phat_sinh < duc_moc_phut_dung_may();
do $$ declare k record; begin
  for k in select distinct ma_may, ma_sp from duc_su_co_log where gio_phat_sinh >= duc_moc_phut_dung_may() or phut_dung_may is null loop
    perform duc_tinh_phut_dung_may(k.ma_may, k.ma_sp);
  end loop;
end $$;

-- ── 8. Kết ca: phút dừng = hợp các khoảng (đã đóng + đang mở chính/phụ), không cộng trùng ──
do $$
declare d text;
begin
  d := replace(pg_get_functiondef('public.duc_end_shift'::regproc), E'\r\n', E'\n');
  if strpos(d, 'T178') > 0 then return; end if;
  d := replace(d, '    select ma_may, ma_sp, sum(coalesce(thoi_gian_dung_phut, 0)) * 60 as sec',
                  '    select ma_may, ma_sp, sum(coalesce(phut_dung_may, thoi_gian_dung_phut, 0)) * 60 as sec   -- T178');
  d := replace(d,
E'  for v_row in select ma_may, ma_sp, open_gio_phat_sinh from duc_ca_hien_tai
    where ngay = p_ngay and ca = p_ca and open_gio_phat_sinh is not null
  loop
    v_key := v_row.ma_may || \'|\' || v_row.ma_sp;
    v_open_start := v_row.open_gio_phat_sinh;
    v_seg_start := greatest(v_open_start, (v_shift_window->>\'start\')::timestamptz);
    v_seg_end := least(v_now, (v_shift_window->>\'end\')::timestamptz);
    v_downtime_by_key := jsonb_set(v_downtime_by_key, array[v_key],
      to_jsonb(coalesce((v_downtime_by_key->>v_key)::numeric, 0) + greatest(0, extract(epoch from (v_seg_end - v_seg_start)))));
    v_tong_phut_open := v_tong_phut_open + greatest(0, round(extract(epoch from (v_seg_end - v_seg_start)) / 60));
  end loop;',
E'  -- T178: phần trong ca của các sự cố còn mở (chính + phụ), lấy HỢP các khoảng rồi trừ phần đã nằm
  -- trong sự cố đã đóng của ca → máy dừng bao lâu tính bấy nhiêu, không cộng trùng.
  for v_row in
    with w as (select (v_shift_window->>\'start\')::timestamptz s, least(v_now, (v_shift_window->>\'end\')::timestamptz) e),
    mo as (
      select c.ma_may, c.ma_sp, tstzrange(greatest(c.open_gio_phat_sinh, w.s), w.e) r
        from duc_ca_hien_tai c, w
       where c.ngay = p_ngay and c.ca = p_ca and c.open_gio_phat_sinh is not null and greatest(c.open_gio_phat_sinh, w.s) < w.e
      union all
      select c.ma_may, c.ma_sp, tstzrange(greatest(t.gio_phat_sinh, w.s), w.e)
        from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong, w
       where c.ngay = p_ngay and c.ca = p_ca and greatest(t.gio_phat_sinh, w.s) < w.e),
    dong as (
      select ma_may, ma_sp, range_agg(tstzrange(gio_phat_sinh, gio_tro_lai)) mr from duc_su_co_log
       where ngay = p_ngay and ca = p_ca and gio_tro_lai > gio_phat_sinh group by ma_may, ma_sp),
    g as (select ma_may, ma_sp, range_agg(r) mr from mo group by ma_may, ma_sp)
    select g.ma_may, g.ma_sp,
           (select coalesce(sum(extract(epoch from upper(x) - lower(x))), 0) from unnest(g.mr - coalesce(dong.mr, \'{}\'::tstzmultirange)) x) as sec
      from g left join dong on dong.ma_may = g.ma_may and dong.ma_sp is not distinct from g.ma_sp
  loop
    v_key := v_row.ma_may || \'|\' || v_row.ma_sp;
    v_downtime_by_key := jsonb_set(v_downtime_by_key, array[v_key],
      to_jsonb(coalesce((v_downtime_by_key->>v_key)::numeric, 0) + v_row.sec));
    v_tong_phut_open := v_tong_phut_open + round(v_row.sec / 60);
  end loop;');
  d := replace(d, '  select coalesce(sum(thoi_gian_dung_phut), 0) into v_tong_phut_resolved from duc_su_co_log where ngay = p_ngay and ca = p_ca;',
                  '  select coalesce(sum(coalesce(phut_dung_may, thoi_gian_dung_phut)), 0) into v_tong_phut_resolved from duc_su_co_log where ngay = p_ngay and ca = p_ca;');
  d := replace(d, '  select count(*) into v_so_su_co_dang_do from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and open_gio_phat_sinh is not null;',
                  '  select count(*) + (select count(*) from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong where c.ngay = p_ngay and c.ca = p_ca)
    into v_so_su_co_dang_do from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and open_gio_phat_sinh is not null;');
  if (length(d) - length(replace(d, 'T178', ''))) / 4 < 2 or strpos(d, 'coalesce(phut_dung_may, thoi_gian_dung_phut)), 0) into v_tong_phut_resolved') = 0
     or strpos(d, 'from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong where c.ngay = p_ngay') = 0 then
    raise exception 'T178: không vá đủ 4 chỗ trong duc_end_shift';
  end if;
  execute d;
end $$;

-- ── 9. Quyền ─────────────────────────────────────────────────────────────────
revoke execute on function public.duc_id_su_co_moi(text, timestamptz) from public, anon, authenticated;
revoke execute on function public.duc_su_co_phu_len_chinh(text) from public, anon, authenticated;
revoke execute on function public.duc_su_co_doi_cho(text, text) from public, anon, authenticated;
revoke execute on function public.duc_tinh_phut_dung_may(text, text) from public, anon, authenticated;
revoke execute on function public.duc_su_co_log_phut_dung_may_trg() from public, anon, authenticated;
revoke execute on function public.duc_set_incident_open(text, text, timestamptz, text, text, text) from public, anon, authenticated;
revoke execute on function public.duc_clear_incident_open(text, text) from public, anon, authenticated;
revoke execute on function public.duc_close_f1_incident_if_open(text, text) from public, anon, authenticated;
revoke execute on function public.duc_resolve_incident_x(text, text, timestamptz, text, text, text) from public, anon;
revoke execute on function public.duc_edit_open_incident_x(text, text, text, timestamptz, text, text, text, text) from public, anon;
revoke execute on function public.duc_delete_open_incident_x(text, text, text) from public, anon;
grant execute on function public.duc_resolve_incident_x(text, text, timestamptz, text, text, text) to authenticated;
grant execute on function public.duc_edit_open_incident_x(text, text, text, timestamptz, text, text, text, text) to authenticated;
grant execute on function public.duc_delete_open_incident_x(text, text, text) to authenticated;
