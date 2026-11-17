-- ============================================================================
-- T292 — Khuôn nhiều SP (1 shot ra 2–N mã khác nhau), Đợt 1.
-- Ví dụ: khuôn 114 #1 ra IWT-114-01 (1 cav) + IWT-115-01 (2 cav) + IWT-116-01 (2 cav).
--
-- Trước đây khuôn kép nối từng ĐÔI qua duc_ca_hien_tai.khuon_kep_voi (chỉ 2 SP).
-- Nay:
--   - nhom_khuon: mọi dòng ra cùng 1 shot mang chung giá trị (= id_dong dòng
--     đầu nhóm theo row_seq). Giữ lại cả khi nhóm đã đóng (đổi SP) để kết ca
--     vẫn mirror shot / tính NG / đếm shot khuôn đúng.
--   - khuon_kep_voi: GIỮ, dạng "sao" — mọi dòng trỏ về dòng có row_seq lớn nhất
--     của nhóm, dòng đó trỏ về dòng đầu. Các màn hình IPQC / QC / mobile cũng
--     mở rộng active set bằng nhom_khuon để đưa đủ mọi mã trong nhóm vào xử lý.
--     khuon_kep_voi = null nghĩa là nhóm đã đóng (không còn chạy).
--   - duc_khuon_ho: danh mục khuôn nhiều SP (khuôn → các mã SP), để dashboard
--     tự điền đủ mã khi chọn khuôn / nạp KHSX tuần.
--
-- Chạy được nhiều lần. Phần vá hàm cũ dùng thay chuỗi trên định nghĩa hiện
-- có (kiểm tra chỗ vá tồn tại, không có thì báo lỗi).
-- Đã chạy thủ công trên STAGING và PROD ngày 17/11/2026.
-- ============================================================================

-- ---------------------------------------------------------------- 1. Dữ liệu
alter table duc_ca_hien_tai add column if not exists nhom_khuon text;
create index if not exists idx_duc_cht_nhom_khuon on duc_ca_hien_tai (nhom_khuon) where nhom_khuon is not null;

update duc_ca_hien_tai c set nhom_khuon = (
  select s.id_dong from duc_ca_hien_tai s where s.id_dong in (c.id_dong, c.khuon_kep_voi) order by s.row_seq limit 1)
where nullif(c.khuon_kep_voi, '') is not null and c.nhom_khuon is null;

create table if not exists duc_khuon_ho (
  ma_khuon text not null,
  ma_sp    text not null,
  thu_tu   int  not null default 1,
  primary key (ma_khuon, ma_sp)
);
alter table duc_khuon_ho enable row level security;
drop policy if exists duc_khuon_ho_doc on duc_khuon_ho;
create policy duc_khuon_ho_doc on duc_khuon_ho for select to authenticated using (true);
revoke all on duc_khuon_ho from anon;
grant select on duc_khuon_ho to authenticated;

insert into duc_khuon_ho (ma_khuon, ma_sp, thu_tu) values
  ('114 #1', 'IWT-114-01', 1), ('114 #1', 'IWT-115-01', 2), ('114 #1', 'IWT-116-01', 3)
on conflict (ma_khuon, ma_sp) do update set thu_tu = excluded.thu_tu;

-- ---------------------------------------------------------------- 2. Hàm nhóm
-- Nối các dòng thành 1 nhóm (theo row_seq). < 2 dòng → bỏ nhóm.
create or replace function duc_nhom_khuon_noi(p_ids text[])
returns void language plpgsql security definer set search_path = public as $$
declare v_ids text[]; v_dau text; v_cuoi text;
begin
  select array_agg(id_dong order by row_seq) into v_ids from duc_ca_hien_tai where id_dong = any(p_ids);
  if v_ids is null then return; end if;
  if array_length(v_ids, 1) < 2 then
    update duc_ca_hien_tai set nhom_khuon = null, khuon_kep_voi = null where id_dong = any(v_ids);
    return;
  end if;
  v_dau := v_ids[1]; v_cuoi := v_ids[array_length(v_ids, 1)];
  update duc_ca_hien_tai set
    nhom_khuon = v_dau,
    khuon_kep_voi = case when id_dong = v_cuoi then v_dau else v_cuoi end
  where id_dong = any(v_ids);
end $$;

-- Các dòng cùng nhóm với 1 dòng (kể cả chính nó). Không thuộc nhóm → {chính nó}.
create or replace function duc_nhom_khuon_ds(p_id_dong text)
returns text[] language sql stable security definer set search_path = public as $$
  select coalesce(
    (select array_agg(c.id_dong order by c.row_seq) from duc_ca_hien_tai s join duc_ca_hien_tai c on c.nhom_khuon = s.nhom_khuon
      where s.id_dong = p_id_dong and s.nhom_khuon is not null),
    (select array_remove(array[s.id_dong, nullif(s.khuon_kep_voi, '')], null) from duc_ca_hien_tai s where s.id_dong = p_id_dong),
    array[p_id_dong]);
$$;

revoke execute on function duc_nhom_khuon_noi(text[]) from public, anon, authenticated;
revoke execute on function duc_nhom_khuon_ds(text) from public, anon, authenticated;

-- ------------------------------------------------- 3. Gán KH khuôn nhiều SP
-- p_ds = [{ma_sp, ten_sp, kh_ca, kh_tuan}, ...] (≥ 2 mã)
create or replace function duc_assign_group_plan(
  p_ngay date, p_ca text, p_phuong_an_ca text, p_ma_may text, p_so_khuon text,
  p_nv_ca_ngay text, p_nv_ca_dem text, p_ds jsonb, p_user text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_it jsonb; v_ma text; v_id text; v_ids text[] := '{}'; v_mas text[] := '{}';
  v_win jsonb; v_last_shot numeric; v_now timestamptz := now(); v_loi_ca text; v_n int; i int := 0;
begin
  p_user := public.duc_ten_nguoi_hien_tai(p_user);
  if p_so_khuon is null or trim(p_so_khuon) = '' then return jsonb_build_object('ok', false, 'error', 'Khuôn nhiều SP cần chọn số khuôn'); end if;
  v_n := case when jsonb_typeof(p_ds) = 'array' then jsonb_array_length(p_ds) else 0 end;
  if v_n < 2 then return jsonb_build_object('ok', false, 'error', 'Khuôn nhiều SP cần ít nhất 2 mã SP'); end if;

  for v_it in select * from jsonb_array_elements(p_ds) loop
    v_ma := trim(coalesce(v_it->>'ma_sp', ''));
    if v_ma = '' or coalesce(nullif(v_it->>'kh_ca', '')::numeric, 0) <= 0 then
      return jsonb_build_object('ok', false, 'error', 'Chưa nhập đủ Mã SP / KH ca cho SP thứ ' || (coalesce(array_length(v_mas, 1), 0) + 1));
    end if;
    if v_ma = any(v_mas) then return jsonb_build_object('ok', false, 'error', 'Mã SP ' || v_ma || ' bị nhập trùng'); end if;
    v_id := duc_make_id_dong(p_ngay, p_ca, p_ma_may, v_ma);
    if exists (select 1 from duc_ca_hien_tai where id_dong = v_id) then
      return jsonb_build_object('ok', false, 'error', 'Máy ' || p_ma_may || ' đã có dòng với SP ' || v_ma || ' trong ca này');
    end if;
    v_mas := v_mas || v_ma; v_ids := v_ids || v_id;
  end loop;

  v_loi_ca := duc_loi_gan_kh_ca_da_qua(p_ngay, p_ca, p_phuong_an_ca);
  if v_loi_ca is not null then return jsonb_build_object('ok', false, 'error', v_loi_ca); end if;

  v_win := duc_get_shift_window(p_ngay, p_phuong_an_ca, p_ca);
  select so_shot_cuoi_ca_gan_nhat into v_last_shot from duc_shot_may where ma_may = p_ma_may;

  for v_it in select * from jsonb_array_elements(p_ds) loop
    i := i + 1;
    insert into duc_ca_hien_tai (
      id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, kh_ca, kh_tuan, tt_ca, tt_tuan,
      nv_ca_ngay, nv_ca_dem, version, last_updated_by, last_updated_at, so_shot_nong_khuon, so_luong_ng, phan_loai_ng,
      sp_start_time, sp_end_time, so_shot_khuon_snapshot, so_shot_dau_ca, so_shot_cuoi_ca
    ) values (
      v_ids[i], p_ngay, p_ca, p_phuong_an_ca, duc_iso_week(p_ngay), p_ma_may, v_mas[i], coalesce(v_it->>'ten_sp', ''), trim(p_so_khuon),
      (v_it->>'kh_ca')::numeric, coalesce(nullif(v_it->>'kh_tuan', '')::numeric, 0), 0, 0,
      coalesce(p_nv_ca_ngay, ''), coalesce(p_nv_ca_dem, ''), 1, p_user, v_now, 0, 0, '',
      (v_win->>'start')::timestamptz, (v_win->>'end')::timestamptz, 0, v_last_shot, null
    );
  end loop;
  perform duc_nhom_khuon_noi(v_ids);

  for i in 1..v_n loop
    perform duc_ensure_mold_product_mapping(trim(p_so_khuon), v_mas[i]);
    begin perform duc_request_ipqc_check(v_ids[i], 'doi_khuon'); exception when others then null; end;
  end loop;

  return jsonb_build_object('ok', true, 'id_dong', to_jsonb(v_ids), 'ma_sp', to_jsonb(v_mas), 'ma_may', p_ma_may);
end $$;

-- ------------------------------------- 4. Đổi SP (cũ đơn/nhóm → mới 1..N mã)
-- p_ds = [{ma_sp, ten_sp, kh_ca, kh_tuan}, ...]. Sự cố C3 Đổi khuôn chỉ mở trên
-- dòng mới ĐẦU TIÊN (máy dừng 1 lần, không nhân thời gian dừng theo số mã).
create or replace function duc_change_product_group(
  p_old_id_dong text, p_so_khuon text, p_gio_bat_dau_doi_khuon timestamptz, p_dam_nhiem text, p_user text, p_ds jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_old record; v_old_ids text[]; v_old_mas text[]; v_it jsonb; v_ma text; v_id text; v_x text;
  v_ids text[] := '{}'; v_mas text[] := '{}'; v_win jsonb; v_carry_shot numeric; v_now timestamptz := now();
  v_id_su_co text; v_n int; v_nhan text; i int := 0;
begin
  p_user := public.duc_ten_nguoi_hien_tai(p_user);
  if p_so_khuon is null or trim(p_so_khuon) = '' then return jsonb_build_object('ok', false, 'error', 'Bắt buộc nhập số khuôn'); end if;
  if p_gio_bat_dau_doi_khuon is null then return jsonb_build_object('ok', false, 'error', 'Chưa nhập giờ bắt đầu đổi khuôn'); end if;
  if p_gio_bat_dau_doi_khuon > now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Giờ bắt đầu đổi khuôn không được ở tương lai'); end if;
  v_n := case when jsonb_typeof(p_ds) = 'array' then jsonb_array_length(p_ds) else 0 end;
  if v_n < 1 then return jsonb_build_object('ok', false, 'error', 'Chưa nhập mã SP mới'); end if;

  select * into v_old from duc_ca_hien_tai where id_dong = p_old_id_dong;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng SP cũ: ' || p_old_id_dong); end if;
  -- nhóm cũ đã đóng (khuon_kep_voi null) thì chỉ đổi chính dòng này
  v_old_ids := case when nullif(v_old.khuon_kep_voi, '') is not null then duc_nhom_khuon_ds(p_old_id_dong) else array[p_old_id_dong] end;
  select array_agg(trim(coalesce(ma_sp, '')) order by row_seq) into v_old_mas from duc_ca_hien_tai where id_dong = any(v_old_ids);

  for v_it in select * from jsonb_array_elements(p_ds) loop
    v_ma := trim(coalesce(v_it->>'ma_sp', ''));
    if v_ma = '' or coalesce(nullif(v_it->>'kh_ca', '')::numeric, 0) <= 0 then
      return jsonb_build_object('ok', false, 'error', 'Chưa nhập đủ Mã SP / KH ca cho SP mới thứ ' || (coalesce(array_length(v_mas, 1), 0) + 1));
    end if;
    if v_ma = any(v_mas) then return jsonb_build_object('ok', false, 'error', 'Mã SP ' || v_ma || ' bị nhập trùng'); end if;
    if v_ma = any(v_old_mas) then return jsonb_build_object('ok', false, 'error', 'SP mới ' || v_ma || ' trùng với SP đang chạy'); end if;
    v_id := duc_make_id_dong(v_old.ngay, v_old.ca, v_old.ma_may, v_ma);
    if exists (select 1 from duc_ca_hien_tai where id_dong = v_id) then
      return jsonb_build_object('ok', false, 'error', 'Máy ' || v_old.ma_may || ' đã có dòng với SP ' || v_ma || ' trong ca này');
    end if;
    v_mas := v_mas || v_ma; v_ids := v_ids || v_id;
  end loop;
  v_nhan := array_to_string(v_mas, ' + ');

  v_win := duc_get_shift_window(v_old.ngay, v_old.phuong_an_ca, v_old.ca);
  select max(so_shot_cuoi_ca) into v_carry_shot from duc_ca_hien_tai where id_dong = any(v_old_ids);
  if v_carry_shot is null then select so_shot_cuoi_ca_gan_nhat into v_carry_shot from duc_shot_may where ma_may = v_old.ma_may; end if;

  foreach v_x in array v_old_ids loop
    perform duc_doi_sp_dong_su_co(v_x, p_gio_bat_dau_doi_khuon, v_nhan, p_user);   -- T188
  end loop;
  v_id_su_co := duc_make_id_su_co(v_old.ma_may, p_gio_bat_dau_doi_khuon);

  for v_it in select * from jsonb_array_elements(p_ds) loop
    i := i + 1;
    insert into duc_ca_hien_tai (
      id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, kh_ca, kh_tuan, tt_ca, tt_tuan,
      nv_ca_ngay, nv_ca_dem, open_loai_su_co, open_gio_phat_sinh, open_van_de, open_noi_dung_xu_ly, open_dam_nhiem, open_id_su_co,
      version, last_updated_by, last_updated_at, so_shot_nong_khuon, so_luong_ng, phan_loai_ng,
      sp_start_time, sp_end_time, so_shot_khuon_snapshot, so_shot_dau_ca, so_shot_cuoi_ca
    ) values (
      v_ids[i], v_old.ngay, v_old.ca, v_old.phuong_an_ca, duc_iso_week(v_old.ngay), v_old.ma_may, v_mas[i], coalesce(v_it->>'ten_sp', ''), trim(p_so_khuon),
      (v_it->>'kh_ca')::numeric, coalesce(nullif(v_it->>'kh_tuan', '')::numeric, 0), 0, 0,
      coalesce(v_old.nv_ca_ngay, ''), coalesce(v_old.nv_ca_dem, ''),
      case when i = 1 then 'C3 — Đổi khuôn' end,
      case when i = 1 then p_gio_bat_dau_doi_khuon end,
      case when i = 1 then 'Đổi khuôn từ ' || array_to_string(v_old_mas, ' + ') end,
      case when i = 1 then 'Đang thực hiện đổi khuôn' end,
      case when i = 1 then coalesce(p_dam_nhiem, '') end,
      case when i = 1 then v_id_su_co end,
      1, p_user, v_now, 0, 0, '', p_gio_bat_dau_doi_khuon, (v_win->>'end')::timestamptz, 0, v_carry_shot, null
    );
  end loop;

  -- Đóng nhóm cũ: bỏ liên kết "đang chạy", GIỮ nhom_khuon để kết ca tính shot/NG đúng.
  update duc_ca_hien_tai set khuon_kep_voi = null where id_dong = any(v_old_ids) and khuon_kep_voi is not null;
  if v_n >= 2 then perform duc_nhom_khuon_noi(v_ids); end if;

  for i in 1..v_n loop
    perform duc_ensure_mold_product_mapping(trim(p_so_khuon), v_mas[i]);
    begin perform duc_request_ipqc_check(v_ids[i], 'doi_khuon', v_id_su_co, p_gio_bat_dau_doi_khuon); exception when others then null; end;
  end loop;

  return jsonb_build_object('ok', true, 'id_dong', to_jsonb(v_ids), 'ma_sp', to_jsonb(v_mas), 'new_id_dong', v_ids[1],
    'old_id_dong', to_jsonb(v_old_ids), 'old_ma_sp', array_to_string(v_old_mas, ' + '), 'new_ma_sp', v_nhan,
    'ma_may', v_old.ma_may, 'id_su_co', v_id_su_co);
end $$;

revoke execute on function duc_assign_group_plan(date, text, text, text, text, text, text, jsonb, text) from public, anon;
grant execute on function duc_assign_group_plan(date, text, text, text, text, text, text, jsonb, text) to authenticated;
revoke execute on function duc_change_product_group(text, text, timestamptz, text, text, jsonb) from public, anon;
grant execute on function duc_change_product_group(text, text, timestamptz, text, text, jsonb) to authenticated;

-- --------------------------- 5. Hàm khuôn kép 2 SP cũ → gọi sang hàm nhóm
create or replace function duc_assign_paired_plan(p_ngay date, p_ca text, p_phuong_an_ca text, p_ma_may text, p_so_khuon text,
  p_nv_ca_ngay text, p_nv_ca_dem text, p_sp_a_ma_sp text, p_sp_a_ten_sp text, p_sp_a_kh_ca numeric, p_sp_a_kh_tuan numeric,
  p_sp_b_ma_sp text, p_sp_b_ten_sp text, p_sp_b_kh_ca numeric, p_sp_b_kh_tuan numeric, p_user text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  v := duc_assign_group_plan(p_ngay, p_ca, p_phuong_an_ca, p_ma_may, p_so_khuon, p_nv_ca_ngay, p_nv_ca_dem, jsonb_build_array(
    jsonb_build_object('ma_sp', p_sp_a_ma_sp, 'ten_sp', p_sp_a_ten_sp, 'kh_ca', p_sp_a_kh_ca, 'kh_tuan', p_sp_a_kh_tuan),
    jsonb_build_object('ma_sp', p_sp_b_ma_sp, 'ten_sp', p_sp_b_ten_sp, 'kh_ca', p_sp_b_kh_ca, 'kh_tuan', p_sp_b_kh_tuan)), p_user);
  if not coalesce((v->>'ok')::boolean, false) then return v; end if;
  return v || jsonb_build_object('id_dong_a', v->'id_dong'->>0, 'id_dong_b', v->'id_dong'->>1, 'ma_sp_a', v->'ma_sp'->>0, 'ma_sp_b', v->'ma_sp'->>1);
end $$;

create or replace function duc_change_product_paired(p_old_id_dong text, p_so_khuon text, p_gio_bat_dau_doi_khuon timestamptz, p_dam_nhiem text,
  p_sp_a_ma_sp text, p_sp_a_ten_sp text, p_sp_a_kh_ca numeric, p_sp_a_kh_tuan numeric,
  p_sp_b_ma_sp text, p_sp_b_ten_sp text, p_sp_b_kh_ca numeric, p_sp_b_kh_tuan numeric, p_user text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if p_sp_b_ma_sp is null or trim(p_sp_b_ma_sp) = '' then return jsonb_build_object('ok', false, 'error', 'Chưa nhập đủ Mã SP B / KH ca B'); end if;
  v := duc_change_product_group(p_old_id_dong, p_so_khuon, p_gio_bat_dau_doi_khuon, p_dam_nhiem, p_user, jsonb_build_array(
    jsonb_build_object('ma_sp', p_sp_a_ma_sp, 'ten_sp', p_sp_a_ten_sp, 'kh_ca', p_sp_a_kh_ca, 'kh_tuan', p_sp_a_kh_tuan),
    jsonb_build_object('ma_sp', p_sp_b_ma_sp, 'ten_sp', p_sp_b_ten_sp, 'kh_ca', p_sp_b_kh_ca, 'kh_tuan', p_sp_b_kh_tuan)));
  if not coalesce((v->>'ok')::boolean, false) then return v; end if;
  return v || jsonb_build_object('id_dong_a', v->'id_dong'->>0, 'id_dong_b', v->'id_dong'->>1, 'ma_sp_a', v->'ma_sp'->>0, 'ma_sp_b', v->'ma_sp'->>1);
end $$;

create or replace function duc_change_product_pair_out(p_old_id_dong text, p_so_khuon text, p_gio_bat_dau_doi_khuon timestamptz, p_dam_nhiem text, p_user text,
  p_new_a_ma_sp text, p_new_a_ten_sp text, p_new_a_kh_ca numeric, p_new_a_kh_tuan numeric,
  p_new_b_ma_sp text default null, p_new_b_ten_sp text default null, p_new_b_kh_ca numeric default null, p_new_b_kh_tuan numeric default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb; v_ds jsonb;
begin
  v_ds := jsonb_build_array(jsonb_build_object('ma_sp', p_new_a_ma_sp, 'ten_sp', p_new_a_ten_sp, 'kh_ca', p_new_a_kh_ca, 'kh_tuan', p_new_a_kh_tuan));
  if p_new_b_ma_sp is not null and trim(p_new_b_ma_sp) <> '' then
    v_ds := v_ds || jsonb_build_array(jsonb_build_object('ma_sp', p_new_b_ma_sp, 'ten_sp', p_new_b_ten_sp, 'kh_ca', p_new_b_kh_ca, 'kh_tuan', p_new_b_kh_tuan));
  end if;
  v := duc_change_product_group(p_old_id_dong, p_so_khuon, p_gio_bat_dau_doi_khuon, p_dam_nhiem, p_user, v_ds);
  if not coalesce((v->>'ok')::boolean, false) then return v; end if;
  return v || jsonb_build_object('new_id_dong_a', v->'id_dong'->>0, 'new_id_dong_b', v->'id_dong'->>1,
    'new_ma_sp_a', v->'ma_sp'->>0, 'new_ma_sp_b', v->'ma_sp'->>1,
    'old_ma_sp_a', split_part(v->>'old_ma_sp', ' + ', 1), 'old_ma_sp_b', nullif(split_part(v->>'old_ma_sp', ' + ', 2), ''));
end $$;

-- ------------------------ 6. Nhập shot: mirror shot đầu/cuối/nóng cho CẢ nhóm
create or replace function duc_update_shift_inputs(p_id_dong text, p_so_shot_nong_khuon numeric, p_so_luong_ng numeric, p_phan_loai_ng text,
  p_so_shot_dau_ca numeric, p_so_shot_cuoi_ca numeric, p_user text)
returns jsonb language plpgsql security definer as $$
declare
  v_row record; v_pair record; v_cavity numeric; v_pair_cavity numeric;
  v_has_shot_range boolean; v_ng numeric; v_ng_auto boolean := false;
  v_shot_chay_that numeric; v_new_version bigint; v_now timestamptz := now();
begin
  if p_so_shot_nong_khuon is null or p_so_shot_nong_khuon < 0 then return jsonb_build_object('ok', false, 'error', 'Số shot nóng máy không hợp lệ'); end if;
  v_has_shot_range := p_so_shot_dau_ca is not null and p_so_shot_cuoi_ca is not null;
  if v_has_shot_range and p_so_shot_dau_ca < 0 then return jsonb_build_object('ok', false, 'error', 'Số shot đầu ca không hợp lệ'); end if;
  if v_has_shot_range and p_so_shot_cuoi_ca < 0 then return jsonb_build_object('ok', false, 'error', 'Số shot cuối ca không hợp lệ'); end if;

  select * into v_row from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng: ' || p_id_dong); end if;

  if v_has_shot_range then
    if p_so_shot_cuoi_ca < p_so_shot_dau_ca then return jsonb_build_object('ok', false, 'error', 'Số shot cuối ca phải ≥ số shot đầu ca'); end if;
    select cavity into v_cavity from master_products where ma_sp = v_row.ma_sp;
    v_shot_chay_that := p_so_shot_cuoi_ca - p_so_shot_dau_ca - p_so_shot_nong_khuon;
    if v_shot_chay_that < 0 then
      return jsonb_build_object('ok', false, 'error', 'Số shot nóng máy lớn hơn tổng số shot chạy trong ca (' || (p_so_shot_cuoi_ca - p_so_shot_dau_ca) || ') — kiểm tra lại số liệu');
    end if;
    if v_cavity is not null and v_cavity > 0 then
      v_ng := round(v_shot_chay_that * v_cavity - coalesce(v_row.tt_ca, 0));
      if v_ng < 0 then return jsonb_build_object('ok', false, 'error', 'NG tính ra âm (' || v_ng || ') — kiểm tra lại số shot đầu/cuối ca, shot nóng máy, hoặc TT ca'); end if;
      v_ng_auto := true;
    else
      v_ng := p_so_luong_ng;
      if v_ng is null or v_ng < 0 then return jsonb_build_object('ok', false, 'error', 'SP ' || v_row.ma_sp || ' chưa có cavity để tự tính NG — vui lòng nhập tay NG'); end if;
    end if;
  else
    v_ng := p_so_luong_ng;
    if v_ng is null or v_ng < 0 then return jsonb_build_object('ok', false, 'error', 'Số lượng NG không hợp lệ'); end if;
  end if;

  v_new_version := coalesce(v_row.version, 0) + 1;
  update duc_ca_hien_tai set
    so_shot_nong_khuon = p_so_shot_nong_khuon, so_luong_ng = v_ng, phan_loai_ng = coalesce(p_phan_loai_ng, ''),
    so_shot_dau_ca = case when v_has_shot_range then p_so_shot_dau_ca else so_shot_dau_ca end,
    so_shot_cuoi_ca = case when v_has_shot_range then p_so_shot_cuoi_ca else so_shot_cuoi_ca end,
    version = v_new_version, last_updated_by = p_user, last_updated_at = v_now
  where id_dong = p_id_dong;

  if v_has_shot_range then
    perform duc_set_last_machine_shot(v_row.ma_may, p_so_shot_cuoi_ca);
  end if;

  -- T292: khuôn nhiều SP — mirror shot đầu/cuối/nóng sang mọi dòng cùng nhóm, NG theo cavity riêng từng mã
  for v_pair in select * from duc_ca_hien_tai where id_dong = any(duc_nhom_khuon_ds(p_id_dong)) and id_dong <> p_id_dong loop
    if v_has_shot_range then
      select cavity into v_pair_cavity from master_products where ma_sp = v_pair.ma_sp;
      update duc_ca_hien_tai set
        so_shot_nong_khuon = p_so_shot_nong_khuon, so_shot_dau_ca = p_so_shot_dau_ca, so_shot_cuoi_ca = p_so_shot_cuoi_ca,
        so_luong_ng = case when v_pair_cavity is not null and v_pair_cavity > 0
          then greatest(0, round((p_so_shot_cuoi_ca - p_so_shot_dau_ca - p_so_shot_nong_khuon) * v_pair_cavity - coalesce(v_pair.tt_ca, 0)))
          else so_luong_ng end,
        version = coalesce(v_pair.version, 0) + 1, last_updated_by = p_user, last_updated_at = v_now
      where id_dong = v_pair.id_dong;
    else
      update duc_ca_hien_tai set so_shot_nong_khuon = p_so_shot_nong_khuon, version = coalesce(v_pair.version, 0) + 1,
        last_updated_by = p_user, last_updated_at = v_now
      where id_dong = v_pair.id_dong;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'version', v_new_version, 'so_luong_ng', v_ng, 'ng_auto_calc', v_ng_auto);
end $$;

-- -------------------- 7. Shot khuôn khi kết ca: nhóm tính 1 lần (shot lớn nhất)
create or replace function duc_update_mold_shots_from_shift(p_ngay date, p_ca text)
returns jsonb language plpgsql security definer as $$
declare
  v_row record; v_shot_by_khuon jsonb := '{}'::jsonb; v_nhom jsonb := '{}'::jsonb; v_g jsonb; v_key text;
  v_cavity numeric; v_shot_duc numeric; v_total numeric; v_existing record; v_now timestamptz := now();
  v_updated int := 0; v_warnings text[] := array[]::text[]; v_khuon text; v_info jsonb; v_new_total numeric; v_status text;
begin
  for v_row in
    select cht.id_dong, cht.so_khuon, cht.ma_sp, cht.tt_ca, cht.so_shot_nong_khuon, cht.nhom_khuon, mp.cavity
    from duc_ca_hien_tai cht
    left join master_products mp on mp.ma_sp = cht.ma_sp
    where cht.ngay = p_ngay and cht.ca = p_ca and cht.so_khuon is not null and cht.so_khuon <> ''
    order by cht.row_seq
  loop
    v_cavity := v_row.cavity;
    if v_cavity is null or v_cavity <= 0 then
      v_warnings := array_append(v_warnings, 'SP ' || v_row.ma_sp || ' (khuôn ' || v_row.so_khuon || '): không có cavity — shot đúc không được tính.');
      v_shot_duc := 0;
    else
      v_shot_duc := floor(coalesce(v_row.tt_ca, 0) / v_cavity);
    end if;
    v_total := coalesce(v_row.so_shot_nong_khuon, 0) + v_shot_duc;

    if v_row.nhom_khuon is not null then
      -- T292: 1 shot ra mọi mã trong nhóm → lấy số shot lớn nhất, không cộng dồn
      v_g := v_nhom->v_row.nhom_khuon;
      if v_g is null or (v_g->>'shot')::numeric < v_total then
        v_nhom := jsonb_set(v_nhom, array[v_row.nhom_khuon], jsonb_build_object('shot', v_total, 'khuon', v_row.so_khuon, 'ma_sp', v_row.ma_sp));
      end if;
      continue;
    end if;

    v_info := coalesce(v_shot_by_khuon->v_row.so_khuon, jsonb_build_object('shot', 0, 'ma_sp_last', null));
    v_info := jsonb_set(v_info, '{shot}', to_jsonb((v_info->>'shot')::numeric + v_total));
    if v_total > 0 then v_info := jsonb_set(v_info, '{ma_sp_last}', to_jsonb(v_row.ma_sp)); end if;
    v_shot_by_khuon := jsonb_set(v_shot_by_khuon, array[v_row.so_khuon], v_info);
  end loop;

  for v_key, v_g in select key, value from jsonb_each(v_nhom) loop
    v_info := coalesce(v_shot_by_khuon->(v_g->>'khuon'), jsonb_build_object('shot', 0, 'ma_sp_last', null));
    v_info := jsonb_set(v_info, '{shot}', to_jsonb((v_info->>'shot')::numeric + (v_g->>'shot')::numeric));
    if (v_g->>'shot')::numeric > 0 then v_info := jsonb_set(v_info, '{ma_sp_last}', v_g->'ma_sp'); end if;
    v_shot_by_khuon := jsonb_set(v_shot_by_khuon, array[v_g->>'khuon'], v_info);
  end loop;

  for v_khuon, v_info in select key, value from jsonb_each(v_shot_by_khuon) loop
    if (v_info->>'shot')::numeric = 0 then continue; end if;
    select tong_shot_luy_ke, nguong_bao_duong, nguong_lam_moi, shot_tai_lan_bao_duong_gan_nhat
    into v_existing from duc_shot_khuon where ma_khuon = v_khuon;
    if found then
      v_new_total := coalesce(v_existing.tong_shot_luy_ke, 0) + (v_info->>'shot')::numeric;
      v_status := duc_compute_mold_status(v_new_total, coalesce(v_existing.shot_tai_lan_bao_duong_gan_nhat, 0),
        coalesce(v_existing.nguong_bao_duong, 10000), coalesce(v_existing.nguong_lam_moi, 100000));
      update duc_shot_khuon set
        tong_shot_luy_ke = v_new_total, ten_sp_gan_nhat = coalesce(v_info->>'ma_sp_last', ten_sp_gan_nhat),
        trang_thai_khuon = v_status, last_updated_at = v_now
      where ma_khuon = v_khuon;
    else
      v_status := duc_compute_mold_status((v_info->>'shot')::numeric, 0, 10000, 100000);
      insert into duc_shot_khuon (ma_khuon, ten_sp_gan_nhat, tong_shot_luy_ke, nguong_bao_duong, nguong_lam_moi,
        shot_tai_lan_bao_duong_gan_nhat, trang_thai_khuon, ghi_chu, last_updated_at)
      values (v_khuon, v_info->>'ma_sp_last', (v_info->>'shot')::numeric, 10000, 100000, 0, v_status, '', v_now);
    end if;
    v_updated := v_updated + 1;
  end loop;

  return jsonb_build_object('updated', v_updated, 'warnings', to_jsonb(v_warnings));
end $$;

-- ------------------------------------------------ 8. Vá các hàm còn lại
do $$
declare v text; v_cu text; v_moi text;
begin
  -- 8a. Đổi phương án ca: đổi id_dong thì đổi luôn nhom_khuon trỏ tới nó
  v := pg_get_functiondef('duc_doi_phuong_an_ca(text,text,text)'::regprocedure);
  if position('nhom_khuon' in v) = 0 then
    v_cu := 'update duc_ca_hien_tai set khuon_kep_voi = v_new_id_dong where khuon_kep_voi = r.id_dong;';
    if position(v_cu in v) = 0 then raise exception 'T292: không tìm thấy chỗ vá duc_doi_phuong_an_ca'; end if;
    v := replace(v, v_cu, v_cu || E'\n    update duc_ca_hien_tai set nhom_khuon = v_new_id_dong where nhom_khuon = r.id_dong;   -- T292');
    execute v;
  end if;

  -- 8b. Đổi SP đơn: chặn khi dòng cũ đang chạy khuôn nhiều SP; không dùng lại dòng thuộc nhóm
  v := pg_get_functiondef('duc_change_product(text,text,text,text,numeric,numeric,timestamptz,text,text)'::regprocedure);
  if position('T292' in v) = 0 then
    v_cu := 'if nullif(v_exist.khuon_kep_voi, '''') is not null then';
    if position(v_cu in v) = 0 then raise exception 'T292: không tìm thấy chỗ vá duc_change_product (1)'; end if;
    v := replace(v, v_cu, 'if nullif(v_exist.khuon_kep_voi, '''') is not null or v_exist.nhom_khuon is not null then   -- T292');
    v_cu := '-- T188: đang có sự cố mở vẫn đổi SP được (duc_doi_sp_dong_su_co)';
    if position(v_cu in v) = 0 then raise exception 'T292: không tìm thấy chỗ vá duc_change_product (2)'; end if;
    v := replace(v, v_cu, v_cu || E'\n  if nullif(v_old.khuon_kep_voi, '''') is not null then   -- T292\n'
      || E'    return jsonb_build_object(''ok'', false, ''error'', ''Máy đang chạy khuôn nhiều SP — phải đổi cả nhóm (duc_change_product_group).'');\n  end if;');
    execute v;
  end if;

  -- 8c. Xoá KH 1 dòng trong nhóm đang chạy → nối lại các dòng còn lại
  v := pg_get_functiondef('duc_delete_plan(text,text,text)'::regprocedure);
  if position('T292' in v) = 0 then
    v_cu := 'delete from duc_ca_hien_tai where id_dong = p_id_dong;';
    if position(v_cu in v) = 0 then raise exception 'T292: không tìm thấy chỗ vá duc_delete_plan'; end if;
    v := replace(v, v_cu, v_cu || E'\n  if v_row.nhom_khuon is not null and nullif(v_row.khuon_kep_voi, '''') is not null then   -- T292\n'
      || E'    perform duc_nhom_khuon_noi(array(select id_dong from duc_ca_hien_tai where nhom_khuon = v_row.nhom_khuon));\n  end if;');
    execute v;
  end if;

  -- 8d. Chuyển tiếp ca: nối lại nhóm theo nhom_khuon (thay cách nối từng đôi)
  v := pg_get_functiondef('duc_carry_over_shift(date,text,text,jsonb)'::regprocedure);
  if position('T292' in v) = 0 then
    v_cu := 'update duc_ca_hien_tai set khuon_kep_voi = v_old_to_new->>v_old.khuon_kep_voi where id_dong = v_old_to_new->>v_old.id_dong;';
    if position(v_cu in v) = 0 then raise exception 'T292: không tìm thấy chỗ vá duc_carry_over_shift (1)'; end if;
    v := replace(v, v_cu, 'null;   -- T292: nối lại theo nhom_khuon ở dưới');
    v_cu := 'return jsonb_build_object(''carried'', v_carried,';
    if position(v_cu in v) = 0 then raise exception 'T292: không tìm thấy chỗ vá duc_carry_over_shift (2)'; end if;
    v_moi := E'declare v_g record; begin   -- T292: khuôn nhiều SP chuyển đủ cả nhóm thì nối lại nhóm ở ca sau\n'
      || E'    for v_g in select nhom_khuon, array_agg(id_dong) ids from duc_ca_hien_tai\n'
      || E'      where ngay = p_ngay and ca = p_ca and nhom_khuon is not null and nullif(khuon_kep_voi, '''') is not null group by nhom_khuon loop\n'
      || E'      if (select bool_and(v_old_to_new ? x) from unnest(v_g.ids) x) then\n'
      || E'        perform duc_nhom_khuon_noi(array(select v_old_to_new->>x from unnest(v_g.ids) x));\n'
      || E'      end if;\n'
      || E'    end loop;\n  end;\n  ';
    v := replace(v, v_cu, v_moi || v_cu);
    execute v;
  end if;
end $$;
