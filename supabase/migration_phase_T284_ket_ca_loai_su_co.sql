-- T284 (R27): Kết ca chuyển tiếp đúng ca + IPQC đổi khuôn cho ca tương lai + chuẩn hoá tên loại sự cố.
-- 1) duc_carry_over_shift: ca kế tiếp đã kết ca, hoặc đã trôi qua mà không có dòng KH → bỏ qua, chuyển tới
--    ca gần nhất còn dùng được (tránh dòng/sự cố bị kẹt ở ca đã có báo cáo). Tự kết ca xử lý theo thứ tự thời gian.
-- 2) duc_upsert_plan: gán KH cho ca chưa bắt đầu (>30 phút) → KHÔNG tạo kiểm IPQC đổi khuôn ngay; đánh dấu
--    ipqc_doi_khuon_cho, cron 10 phút tạo khi ca bắt đầu — bỏ qua nếu ca trước máy đó chạy cùng mã SP.
-- 3) Danh mục duc_loai_su_co + trigger chuẩn hoá "<mã> — <tên>" trên duc_su_co_log / duc_su_co_mo_them /
--    duc_ca_hien_tai; sửa dữ liệu cũ (sao lưu t284_loai_su_co_sao_luu); duc_change_product ghi "—".

-- ===================== 3. Danh mục loại sự cố =====================
create table if not exists public.duc_loai_su_co (
  ma text primary key, ten text not null, nhom text not null, thu_tu int not null default 0
);
alter table public.duc_loai_su_co enable row level security;
drop policy if exists duc_loai_su_co_doc on public.duc_loai_su_co;
create policy duc_loai_su_co_doc on public.duc_loai_su_co for select to authenticated using (true);

insert into public.duc_loai_su_co (ma, ten, nhom, thu_tu) values
  ('A1', 'Sự cố máy đúc', 'A — Sự cố', 1),
  ('A2', 'Sự cố khuôn', 'A — Sự cố', 2),
  ('A3', 'Sự cố hạ tầng (Điện, khí nén, nước...)', 'A — Sự cố', 3),
  ('B1', 'Chất lượng sản phẩm', 'B — Chất lượng', 4),
  ('F1', 'Chất lượng sản phẩm · IPQC phát hiện', 'B — Chất lượng', 5),
  ('B2', 'Sự cố CL nguyên liệu', 'B — Chất lượng', 6),
  ('C1', 'Thay đổi KHSX', 'C — Kế hoạch', 7),
  ('C2', 'Hết nguyên liệu', 'C — Kế hoạch', 8),
  ('C3', 'Đổi khuôn', 'C — Kế hoạch', 9),
  ('D1', 'Thiếu nhân lực', 'D — Nhân lực', 10),
  ('D2', 'Đào tạo / Người mới', 'D — Nhân lực', 11),
  ('E1', 'Bảo dưỡng khuôn KH', 'E — Theo kế hoạch', 12),
  ('E2', 'Vệ sinh theo KH', 'E — Theo kế hoạch', 13),
  ('E3', 'Kiểm kê định kỳ', 'E — Theo kế hoạch', 14)
on conflict (ma) do update set ten = excluded.ten, nhom = excluded.nhom, thu_tu = excluded.thu_tu;

create or replace function public.duc_chuan_loai_su_co(p text)
returns text language plpgsql stable set search_path to 'public' as $$
declare v_s text := btrim(coalesce(p, '')); v_ma text; v_ten text;
begin
  if v_s = '' then return p; end if;
  v_ma := upper(left(v_s, 2));
  if length(v_s) > 2 and substr(v_s, 3, 1) not in (' ', '-', '—', '–', ':', '.') then return p; end if;
  select ten into v_ten from duc_loai_su_co where ma = v_ma;
  if v_ten is null then return p; end if;
  return v_ma || ' — ' || v_ten;
end $$;

create or replace function public.duc_trg_chuan_loai_su_co()
returns trigger language plpgsql set search_path to 'public' as $$
begin
  if tg_table_name = 'duc_ca_hien_tai' then
    new.open_loai_su_co := duc_chuan_loai_su_co(new.open_loai_su_co);
  else
    new.loai_su_co := duc_chuan_loai_su_co(new.loai_su_co);
  end if;
  return new;
end $$;

drop trigger if exists trg_chuan_loai_su_co on public.duc_su_co_log;
create trigger trg_chuan_loai_su_co before insert or update of loai_su_co on public.duc_su_co_log
  for each row execute function public.duc_trg_chuan_loai_su_co();
drop trigger if exists trg_chuan_loai_su_co on public.duc_su_co_mo_them;
create trigger trg_chuan_loai_su_co before insert or update of loai_su_co on public.duc_su_co_mo_them
  for each row execute function public.duc_trg_chuan_loai_su_co();
drop trigger if exists trg_chuan_loai_su_co on public.duc_ca_hien_tai;
create trigger trg_chuan_loai_su_co before insert or update of open_loai_su_co on public.duc_ca_hien_tai
  for each row execute function public.duc_trg_chuan_loai_su_co();

-- Dữ liệu cũ
create table if not exists public.t284_loai_su_co_sao_luu (bang text, khoa text, cu text, luc timestamptz default now());
alter table public.t284_loai_su_co_sao_luu enable row level security;

insert into public.t284_loai_su_co_sao_luu (bang, khoa, cu)
select 'duc_su_co_log', id_ban_ghi, loai_su_co from public.duc_su_co_log
 where loai_su_co is distinct from public.duc_chuan_loai_su_co(loai_su_co)
union all
select 'duc_su_co_mo_them', id::text, loai_su_co from public.duc_su_co_mo_them
 where loai_su_co is distinct from public.duc_chuan_loai_su_co(loai_su_co)
union all
select 'duc_ca_hien_tai', id_dong, open_loai_su_co from public.duc_ca_hien_tai
 where open_loai_su_co is distinct from public.duc_chuan_loai_su_co(open_loai_su_co);

alter table public.duc_su_co_log disable trigger trg_duc_su_co_nk_log;   -- không ghi nhật ký cho lần chuẩn hoá tên
update public.duc_su_co_log set van_de = 'Mất điện. ' || coalesce(van_de, '')
 where loai_su_co = 'A3 — Mất điện' and coalesce(van_de, '') not ilike '%mất điện%';
update public.duc_su_co_log set loai_su_co = public.duc_chuan_loai_su_co(loai_su_co)
 where loai_su_co is distinct from public.duc_chuan_loai_su_co(loai_su_co);
alter table public.duc_su_co_log enable trigger trg_duc_su_co_nk_log;
update public.duc_su_co_mo_them set loai_su_co = public.duc_chuan_loai_su_co(loai_su_co)
 where loai_su_co is distinct from public.duc_chuan_loai_su_co(loai_su_co);
update public.duc_ca_hien_tai set open_loai_su_co = public.duc_chuan_loai_su_co(open_loai_su_co)
 where open_loai_su_co is distinct from public.duc_chuan_loai_su_co(open_loai_su_co);

-- duc_change_product: ghi "C3 — Đổi khuôn" (trigger cũng tự chuẩn hoá)
do $$
declare v_def text := pg_get_functiondef('public.duc_change_product(text,text,text,text,numeric,numeric,timestamptz,text,text)'::regprocedure);
begin
  if position('''C3 - Đổi khuôn''' in v_def) > 0 then
    execute replace(v_def, '''C3 - Đổi khuôn''', '''C3 — Đổi khuôn''');
  end if;
end $$;

-- ===================== 1. Kết ca: chọn ca đích chuyển tiếp =====================
create or replace function public.duc_ca_chuyen_tiep_dich(p_ngay date, p_ca text, p_phuong_an_ca text)
returns jsonb language plpgsql stable set search_path to 'public' as $$
declare v jsonb; v_end timestamptz; v_bo int := 0;
begin
  v := duc_get_next_shift(p_ngay, p_ca, p_phuong_an_ca);
  while v is not null and v_bo < 120 loop
    if exists (select 1 from duc_bao_cao_ca where ngay = (v->>'ngay')::date and ca = v->>'ca') then
      null;   -- ca đã kết → bỏ qua
    else
      v_end := (duc_get_shift_window((v->>'ngay')::date, p_phuong_an_ca, v->>'ca')->>'end')::timestamptz;
      exit when v_end is null or v_end > now()
        or exists (select 1 from duc_ca_hien_tai where ngay = (v->>'ngay')::date and ca = v->>'ca');
    end if;
    v_bo := v_bo + 1;
    v := duc_get_next_shift((v->>'ngay')::date, v->>'ca', p_phuong_an_ca);
  end loop;
  if v is null then return null; end if;
  return v || jsonb_build_object('bo_qua', v_bo);
end $$;

CREATE OR REPLACE FUNCTION public.duc_carry_over_shift(p_ngay date, p_ca text, p_phuong_an_ca text, p_carry_over_list jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_next jsonb; v_item jsonb; v_old record; v_dich record; v_new_id_dong text; v_win jsonb; v_kh_ca_moi numeric; v_carry_shot numeric;
  v_old_to_new jsonb := '{}'::jsonb; v_now timestamptz := now(); v_carried jsonb := '[]'::jsonb; v_ghep boolean;
  v_nd text; v_bo int;
begin
  if p_carry_over_list is null or jsonb_array_length(p_carry_over_list) = 0 then
    return jsonb_build_object('carried', '[]'::jsonb, 'next_ngay', null, 'next_ca', null);
  end if;
  -- T284 (R27): ca kế tiếp đã kết ca / đã trôi qua không có KH → chuyển tới ca gần nhất còn dùng được
  v_next := duc_ca_chuyen_tiep_dich(p_ngay, p_ca, p_phuong_an_ca);
  if v_next is null then raise exception 'Không xác định được ca kế tiếp cho % / %', p_phuong_an_ca, p_ca; end if;
  v_bo := coalesce((v_next->>'bo_qua')::int, 0);

  for v_item in select * from jsonb_array_elements(p_carry_over_list) loop
    select * into v_old from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and ma_may = (v_item->>'ma_may') and ma_sp = (v_item->>'ma_sp');
    if not found then continue; end if;
    v_new_id_dong := duc_make_id_dong((v_next->>'ngay')::date, v_next->>'ca', v_old.ma_may, v_old.ma_sp);
    v_nd := '[Chuyển tiếp từ ' || p_ca || ' ' || to_char(p_ngay, 'DD/MM/YYYY')
      || case when v_bo > 0 then ', bỏ qua ' || v_bo || ' ca đã qua' else '' end || ']';
    v_ghep := false; v_kh_ca_moi := null; v_dich := null;   -- reset mỗi máy, tránh rò kh_ca/dòng đích của máy trước

    select * into v_dich from duc_ca_hien_tai where id_dong = v_new_id_dong for update;
    if found then
      -- T243 (R8): ca sau đã có dòng KH → đưa sự cố đang mở sang dòng đó, không được mất
      v_ghep := true;
      if v_old.open_gio_phat_sinh is not null then
        if v_dich.open_gio_phat_sinh is null then
          update duc_ca_hien_tai set
            open_loai_su_co = v_old.open_loai_su_co, open_gio_phat_sinh = v_old.open_gio_phat_sinh, open_van_de = v_old.open_van_de,
            open_noi_dung_xu_ly = coalesce(v_old.open_noi_dung_xu_ly, '') || case when coalesce(v_old.open_noi_dung_xu_ly, '') <> '' then E'\n' else '' end || v_nd,
            open_dam_nhiem = v_old.open_dam_nhiem, open_id_su_co = v_old.open_id_su_co,
            version = coalesce(version, 0) + 1, last_updated_by = 'system@carry-over', last_updated_at = v_now
          where id_dong = v_new_id_dong;
        else
          insert into duc_su_co_mo_them (id_dong, loai_su_co, gio_phat_sinh, van_de, noi_dung_xu_ly, dam_nhiem, id_su_co)
          values (v_new_id_dong, coalesce(nullif(v_old.open_loai_su_co, ''), '?'), v_old.open_gio_phat_sinh, coalesce(v_old.open_van_de, ''),
                  coalesce(v_old.open_noi_dung_xu_ly, '') || case when coalesce(v_old.open_noi_dung_xu_ly, '') <> '' then E'\n' else '' end || v_nd,
                  coalesce(v_old.open_dam_nhiem, ''), coalesce(v_old.open_id_su_co, duc_make_id_su_co(v_old.ma_may, v_old.open_gio_phat_sinh)));
        end if;
      end if;
    else
      v_win := duc_get_shift_window((v_next->>'ngay')::date, p_phuong_an_ca, v_next->>'ca');
      v_kh_ca_moi := coalesce((v_item->>'kh_ca_moi')::numeric, v_old.kh_ca, 0);
      v_carry_shot := v_old.so_shot_cuoi_ca;
      if v_carry_shot is null then select so_shot_cuoi_ca_gan_nhat into v_carry_shot from duc_shot_may where ma_may = v_old.ma_may; end if;
      insert into duc_ca_hien_tai (
        id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, kh_ca, kh_tuan, tt_ca, tt_tuan, nv_ca_ngay, nv_ca_dem,
        open_loai_su_co, open_gio_phat_sinh, open_van_de, open_noi_dung_xu_ly, open_dam_nhiem, open_id_su_co,
        version, last_updated_by, last_updated_at, so_shot_nong_khuon, so_luong_ng, phan_loai_ng, sp_start_time, sp_end_time, so_shot_khuon_snapshot,
        so_shot_dau_ca, so_shot_cuoi_ca
      ) values (
        v_new_id_dong, (v_next->>'ngay')::date, v_next->>'ca', p_phuong_an_ca, duc_iso_week((v_next->>'ngay')::date),
        v_old.ma_may, v_old.ma_sp, v_old.ten_sp, v_old.so_khuon, v_kh_ca_moi, coalesce((v_item->>'kh_tuan_moi')::numeric, v_old.kh_tuan, 0), 0, 0,
        v_old.nv_ca_ngay, v_old.nv_ca_dem,
        case when v_old.open_gio_phat_sinh is not null then v_old.open_loai_su_co else null end, v_old.open_gio_phat_sinh, v_old.open_van_de,
        case when v_old.open_gio_phat_sinh is not null
          then coalesce(v_old.open_noi_dung_xu_ly, '') || case when coalesce(v_old.open_noi_dung_xu_ly, '') <> '' then E'\n' else '' end || v_nd else null end,
        v_old.open_dam_nhiem, case when v_old.open_gio_phat_sinh is not null then v_old.open_id_su_co else null end,
        1, 'system@carry-over', v_now, 0, 0, '', coalesce((v_win->>'start')::timestamptz, v_now), (v_win->>'end')::timestamptz, 0, v_carry_shot, null
      );
    end if;

    -- sự cố phụ (T178) đi theo sang ca sau (cả 2 trường hợp)
    update duc_su_co_mo_them set id_dong = v_new_id_dong,
      noi_dung_xu_ly = noi_dung_xu_ly || case when noi_dung_xu_ly <> '' then E'\n' else '' end || v_nd
    where id_dong = v_old.id_dong;
    v_old_to_new := jsonb_set(v_old_to_new, array[v_old.id_dong], to_jsonb(v_new_id_dong));
    v_carried := v_carried || jsonb_build_array(jsonb_build_object('ma_may', v_old.ma_may, 'ma_sp', v_old.ma_sp,
      'kh_ca', coalesce(v_kh_ca_moi, v_dich.kh_ca), 'has_open_incident', v_old.open_gio_phat_sinh is not null, 'ghep_dong_co_san', v_ghep));
  end loop;

  for v_old in select id_dong, khuon_kep_voi from duc_ca_hien_tai where ngay = p_ngay and ca = p_ca and khuon_kep_voi is not null and khuon_kep_voi <> '' loop
    if v_old_to_new ? v_old.id_dong and v_old_to_new ? v_old.khuon_kep_voi then
      update duc_ca_hien_tai set khuon_kep_voi = v_old_to_new->>v_old.khuon_kep_voi where id_dong = v_old_to_new->>v_old.id_dong;
    end if;
  end loop;
  return jsonb_build_object('carried', v_carried, 'next_ngay', v_next->>'ngay', 'next_ca', v_next->>'ca', 'bo_qua_ca', v_bo);
end;
$function$;

-- Tự kết ca: xử lý ca cũ trước (ca sau mới nhận được phần chuyển tiếp)
CREATE OR REPLACE FUNCTION public.duc_auto_close_forgotten_shifts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_row record; v_shift_window jsonb; v_result jsonb; v_closed jsonb := '[]'::jsonb; v_skipped jsonb := '[]'::jsonb; v_carry jsonb;
begin
  for v_row in
    select ngay, ca, phuong_an_ca from (
      select ngay, ca, min(phuong_an_ca) as phuong_an_ca from duc_ca_hien_tai where ma_sp is not null and ma_sp <> '' group by ngay, ca) g
    order by (duc_get_shift_window(ngay, phuong_an_ca, ca)->>'start')::timestamptz nulls last, ngay, ca
  loop
    v_shift_window := duc_get_shift_window(v_row.ngay, v_row.phuong_an_ca, v_row.ca);
    if v_shift_window is null then continue; end if;
    if (now() - (v_shift_window->>'end')::timestamptz) < interval '12 hours' then continue; end if;
    if exists (select 1 from duc_bao_cao_ca where ngay = v_row.ngay and ca = v_row.ca) then continue; end if;
    -- T243 (R14): máy còn sự cố mở → tự tick chuyển tiếp (giữ KH ca cũ) để vẫn kết ca được
    select coalesce(jsonb_agg(jsonb_build_object('ma_may', ma_may, 'ma_sp', ma_sp, 'kh_ca_moi', coalesce(kh_ca, 0))), '[]'::jsonb)
    into v_carry from duc_ca_hien_tai where ngay = v_row.ngay and ca = v_row.ca and open_gio_phat_sinh is not null;
    begin
      v_result := duc_end_shift(v_row.ngay, v_row.ca, v_row.phuong_an_ca, 'Hệ thống (tự động)', v_carry,
        'Tự động kết ca — trưởng ca chưa kết ca quá 12 tiếng sau giờ kết thúc ca. Kiểm tra lại nếu số liệu bất thường.'
        || case when jsonb_array_length(v_carry) > 0 then ' Sự cố đang mở tự chuyển tiếp ca sau.' else '' end,
        'system@auto_close_shift');
      if coalesce((v_result->>'ok')::boolean, false) then
        v_closed := v_closed || jsonb_build_array(jsonb_build_object('ngay', v_row.ngay, 'ca', v_row.ca, 'id_bao_cao', v_result->>'id_bao_cao'));
      else
        v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('ngay', v_row.ngay, 'ca', v_row.ca, 'error', v_result->>'error'));
      end if;
    exception when others then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('ngay', v_row.ngay, 'ca', v_row.ca, 'error', sqlerrm));
    end;
  end loop;
  return jsonb_build_object('closed', v_closed, 'skipped', v_skipped);
end;
$function$;

-- ===================== 2. IPQC đổi khuôn cho ca tương lai =====================
alter table public.duc_ca_hien_tai add column if not exists ipqc_doi_khuon_cho boolean not null default false;

create or replace function public.duc_get_prev_shift(p_ngay date, p_ca text, p_phuong_an_ca text)
returns jsonb language plpgsql immutable as $$
begin
  if p_phuong_an_ca = '2 ca 12h' then
    if p_ca = 'Ca đêm' then return jsonb_build_object('ngay', p_ngay, 'ca', 'Ca ngày'); end if;
    if p_ca = 'Ca ngày' then return jsonb_build_object('ngay', p_ngay - 1, 'ca', 'Ca đêm'); end if;
  elsif p_phuong_an_ca = '2 ca 8h' then
    if p_ca = 'Ca 2' then return jsonb_build_object('ngay', p_ngay, 'ca', 'Ca 1'); end if;
    if p_ca = 'Ca 1' then return jsonb_build_object('ngay', p_ngay - 1, 'ca', 'Ca 2'); end if;
  end if;
  return null;
end $$;

CREATE OR REPLACE FUNCTION public.duc_upsert_plan(p_ngay date, p_ca text, p_phuong_an_ca text, p_ma_may text, p_ma_sp text, p_ten_sp text, p_so_khuon text, p_kh_ca numeric, p_kh_tuan numeric, p_nv_ca_ngay text, p_nv_ca_dem text, p_user text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id_dong text;
  v_existing_version bigint;
  v_new_version bigint;
  v_win jsonb;
  v_last_shot numeric;
  v_now timestamptz := now();
  v_loi_ca text;
  v_hoan boolean;
begin
  if p_so_khuon is null or trim(p_so_khuon) = '' then
    return jsonb_build_object('ok', false, 'error', 'Bắt buộc nhập số khuôn');
  end if;

  v_id_dong := duc_make_id_dong(p_ngay, p_ca, p_ma_may, p_ma_sp);
  select version into v_existing_version from duc_ca_hien_tai where id_dong = v_id_dong;

  if found then
    v_new_version := coalesce(v_existing_version, 0) + 1;
    update duc_ca_hien_tai set
      ten_sp = coalesce(p_ten_sp, ten_sp), so_khuon = coalesce(p_so_khuon, so_khuon),
      kh_ca = coalesce(p_kh_ca, kh_ca), kh_tuan = coalesce(p_kh_tuan, kh_tuan),
      nv_ca_ngay = coalesce(p_nv_ca_ngay, nv_ca_ngay), nv_ca_dem = coalesce(p_nv_ca_dem, nv_ca_dem),
      version = v_new_version, last_updated_by = p_user, last_updated_at = v_now
    where id_dong = v_id_dong;

    if p_so_khuon is not null and p_ma_sp is not null then perform duc_ensure_mold_product_mapping(p_so_khuon, p_ma_sp); end if;
    return jsonb_build_object('ok', true, 'id_dong', v_id_dong, 'version', v_new_version, 'created', false);
  else
    v_loi_ca := duc_loi_gan_kh_ca_da_qua(p_ngay, p_ca, p_phuong_an_ca);
    if v_loi_ca is not null then
      return jsonb_build_object('ok', false, 'error', v_loi_ca);
    end if;

    v_win := duc_get_shift_window(p_ngay, p_phuong_an_ca, p_ca);
    select so_shot_cuoi_ca_gan_nhat into v_last_shot from duc_shot_may where ma_may = p_ma_may;
    -- T284 (R27): ca chưa bắt đầu → hoãn kiểm IPQC đổi khuôn tới khi ca bắt đầu (cron duc_ipqc_doi_khuon_ca_moi)
    v_hoan := coalesce((v_win->>'start')::timestamptz > v_now + interval '30 minutes', false);

    insert into duc_ca_hien_tai (
      id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon,
      kh_ca, kh_tuan, tt_ca, tt_tuan, nv_ca_ngay, nv_ca_dem, version, last_updated_by, last_updated_at,
      so_shot_nong_khuon, so_luong_ng, phan_loai_ng, sp_start_time, sp_end_time, so_shot_khuon_snapshot,
      so_shot_dau_ca, so_shot_cuoi_ca, ipqc_doi_khuon_cho
    ) values (
      v_id_dong, p_ngay, p_ca, p_phuong_an_ca, duc_iso_week(p_ngay), p_ma_may, coalesce(p_ma_sp, ''), coalesce(p_ten_sp, ''), coalesce(p_so_khuon, ''),
      p_kh_ca, p_kh_tuan, 0, 0, coalesce(p_nv_ca_ngay, ''), coalesce(p_nv_ca_dem, ''), 1, p_user, v_now,
      0, 0, '', (v_win->>'start')::timestamptz, (v_win->>'end')::timestamptz, 0, v_last_shot, null, v_hoan
    );

    if p_so_khuon is not null and p_ma_sp is not null then perform duc_ensure_mold_product_mapping(p_so_khuon, p_ma_sp); end if;
    if not v_hoan then
      begin perform duc_request_ipqc_check(v_id_dong, 'doi_khuon'); exception when others then null; end;
    end if;

    return jsonb_build_object('ok', true, 'id_dong', v_id_dong, 'version', 1, 'created', true, 'ipqc_hoan', v_hoan);
  end if;
end;
$function$;

create or replace function public.duc_ipqc_doi_khuon_ca_moi()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r record; v_prev jsonb; v_tao int := 0; v_bo int := 0;
begin
  for r in
    select c.id_dong, c.ngay, c.ca, c.phuong_an_ca, c.ma_may, c.ma_sp from duc_ca_hien_tai c
     where c.ipqc_doi_khuon_cho
       and coalesce((duc_get_shift_window(c.ngay, c.phuong_an_ca, c.ca)->>'start')::timestamptz, now()) <= now()
     for update skip locked
  loop
    update duc_ca_hien_tai set ipqc_doi_khuon_cho = false where id_dong = r.id_dong;
    if coalesce(r.ma_sp, '') = '' then continue; end if;
    v_prev := duc_get_prev_shift(r.ngay, r.ca, r.phuong_an_ca);
    -- ca trước máy này chạy cùng mã SP → không đổi khuôn, không cần kiểm
    if v_prev is not null and (
         exists (select 1 from duc_lich_su_san_xuat where ngay = (v_prev->>'ngay')::date and ca = v_prev->>'ca' and ma_may = r.ma_may and ma_sp = r.ma_sp)
      or exists (select 1 from duc_ca_hien_tai where ngay = (v_prev->>'ngay')::date and ca = v_prev->>'ca' and ma_may = r.ma_may and ma_sp = r.ma_sp)) then
      v_bo := v_bo + 1; continue;
    end if;
    begin perform duc_request_ipqc_check(r.id_dong, 'doi_khuon'); v_tao := v_tao + 1; exception when others then null; end;
  end loop;
  return jsonb_build_object('tao', v_tao, 'bo_qua', v_bo);
end $$;

revoke execute on function public.duc_ipqc_doi_khuon_ca_moi() from public, anon, authenticated;
revoke execute on function public.duc_ca_chuyen_tiep_dich(date, text, text) from public, anon;

select cron.schedule('duc_ipqc_nhac_cham', '*/10 * * * *',
  'select public.duc_ipqc_nhac_cham(); select public.duc_ipqc_don_checkpoint_mo_coi(); select public.duc_ipqc_continue_quet_treo(); select public.duc_ipqc_doi_khuon_ca_moi();');
