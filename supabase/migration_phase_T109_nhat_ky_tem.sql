-- ============================================================================
-- T109 — Nhật ký tem + khoá sửa/xoá tem sau kết ca (user 2026-10-15, sau khi tra
-- cứu EXE-CEN-01: 8 tem bị xoá sáng 15/10 không còn cách nào biết nội dung).
--
--   1) duc_tem_nhat_ky: MỌI lần in / sửa / xoá / cập nhật tem (trigger trên
--      duc_tem) — lưu nguyên dòng tem (tem đã xoá vẫn tra được), các cột thay đổi
--      (cũ → mới), người, giờ, lý do, đường gọi (RPC nào).
--        su_kien: in | sua (người dùng sửa ở In tem) | xoa | cap_nhat (nghiệp
--        vụ: quét, chuyển công đoạn, tách tem, bavia...).
--   2) Sửa / xoá tem CHỈ qua RPC duc_tem_sua / duc_tem_xoa (bắt buộc lý do).
--      Tem thuộc ca ĐÃ KẾT (có dòng duc_lich_su_san_xuat cùng máy + mã chứa mốc
--      tem — cùng quy tắc duc_ls_dieu_chinh_tem) → chỉ admin. Sửa chuyển tem
--      SANG ca đã kết cũng chỉ admin.
--   3) Thu hồi quyền ghi trực tiếp bảng duc_tem của anon/authenticated (trước
--      đây In tem update/delete thẳng bảng). Mọi RPC nghiệp vụ đều security
--      definer nên không bị ảnh hưởng.
--
-- Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

-- 1) Ca đã kết chứa mốc tem → {ngay, ca} | null --------------------------------
create or replace function duc_tem_ca_da_ket(p_ma_may text, p_ma_sp text, p_moc timestamptz)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object('ngay', ls.ngay, 'ca', ls.ca)
  from duc_lich_su_san_xuat ls
  cross join lateral (select duc_get_shift_window(ls.ngay, ls.phuong_an_ca, ls.ca) as w) sw
  where p_ma_may is not null and p_ma_sp is not null and p_moc is not null
    and ls.ma_may = p_ma_may and ls.ma_sp = p_ma_sp
    and sw.w is not null
    and p_moc >= (sw.w->>'start')::timestamptz
    and p_moc < greatest((sw.w->>'end')::timestamptz,
                         least(ls.thoi_diem_ghi, (sw.w->>'end')::timestamptz + interval '2 hours'))
  order by (sw.w->>'start')::timestamptz desc
  limit 1;
$$;
revoke execute on function duc_tem_ca_da_ket(text, text, timestamptz) from public, anon;
grant execute on function duc_tem_ca_da_ket(text, text, timestamptz) to authenticated;

-- 2) Bảng nhật ký ------------------------------------------------------------------
create table if not exists duc_tem_nhat_ky (
  id          bigserial primary key,
  tag_no      text not null,
  su_kien     text not null check (su_kien in ('in', 'sua', 'xoa', 'cap_nhat')),
  thay_doi    jsonb,                      -- {cot: {cu, moi}} (sửa / cập nhật)
  du_lieu     jsonb not null,             -- nguyên dòng tem sau thao tác (xoá: trước khi xoá)
  ly_do       text not null default '',
  ca_da_ket   jsonb,                      -- sửa / xoá tem thuộc ca đã kết: {ngay, ca}
  nguoi       text not null default '',
  nguoi_uid   uuid,
  nguon       text not null default '',   -- đường gọi (VD /rpc/duc_tach_tem)
  thoi_diem   timestamptz not null default now()
);
create index if not exists duc_tem_nhat_ky_tag_idx on duc_tem_nhat_ky (tag_no, thoi_diem);
create index if not exists duc_tem_nhat_ky_tg_idx on duc_tem_nhat_ky (thoi_diem desc);
create index if not exists duc_tem_nhat_ky_sk_idx on duc_tem_nhat_ky (su_kien, thoi_diem desc);
alter table duc_tem_nhat_ky enable row level security;
drop policy if exists "authenticated read" on duc_tem_nhat_ky;
create policy "authenticated read" on duc_tem_nhat_ky for select to authenticated using (true);
revoke all on duc_tem_nhat_ky from anon, authenticated;
grant select on duc_tem_nhat_ky to authenticated;
revoke all on sequence duc_tem_nhat_ky_id_seq from anon, authenticated;

-- 3) Trigger ghi nhật ký --------------------------------------------------------------
create or replace function duc_tem_ghi_nhat_ky()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hd text := nullif(current_setting('mes.tem_hanh_dong', true), '');
  v_ly text := coalesce(current_setting('mes.tem_ly_do', true), '');
  v_ket jsonb := nullif(current_setting('mes.tem_ca_da_ket', true), '')::jsonb;
  v_nguon text := coalesce(nullif(current_setting('request.path', true), ''), 'sql');
  v_nguoi text; v_diff jsonb; v_sk text;
begin
  select coalesce(nullif(trim(r.full_name), ''), r.email, r.username) into v_nguoi
  from user_roles r where r.user_id = auth.uid() limit 1;
  v_nguoi := coalesce(v_nguoi, nullif(auth.jwt()->>'email', ''), case when auth.uid() is null then 'Hệ thống' else '' end);

  if tg_op = 'INSERT' then
    insert into duc_tem_nhat_ky (tag_no, su_kien, du_lieu, nguoi, nguoi_uid, nguon)
    values (new.tag_no, 'in', to_jsonb(new), v_nguoi, auth.uid(), v_nguon);
    return new;
  elsif tg_op = 'DELETE' then
    insert into duc_tem_nhat_ky (tag_no, su_kien, du_lieu, ly_do, ca_da_ket, nguoi, nguoi_uid, nguon)
    values (old.tag_no, 'xoa', to_jsonb(old), v_ly, v_ket, v_nguoi, auth.uid(), v_nguon);
    return old;
  end if;

  select jsonb_object_agg(o.key, jsonb_build_object('cu', o.value, 'moi', n.value)) into v_diff
  from jsonb_each(to_jsonb(old)) o join jsonb_each(to_jsonb(new)) n using (key)
  where o.value is distinct from n.value;
  if v_diff is null then return new; end if;
  v_sk := case when v_hd = 'sua' then 'sua' else 'cap_nhat' end;
  insert into duc_tem_nhat_ky (tag_no, su_kien, thay_doi, du_lieu, ly_do, ca_da_ket, nguoi, nguoi_uid, nguon)
  values (new.tag_no, v_sk, v_diff, to_jsonb(new), case when v_sk = 'sua' then v_ly else '' end,
          case when v_sk = 'sua' then v_ket end, v_nguoi, auth.uid(), v_nguon);
  return new;
end $$;
revoke execute on function duc_tem_ghi_nhat_ky() from public, anon, authenticated;

drop trigger if exists trg_duc_tem_nhat_ky on duc_tem;
create trigger trg_duc_tem_nhat_ky
  after insert or update or delete on duc_tem
  for each row execute function duc_tem_ghi_nhat_ky();

-- 4) RPC sửa tem -----------------------------------------------------------------------
create or replace function duc_tem_sua(p_tag_no text, p_data jsonb, p_ly_do text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old duc_tem; v_admin boolean := has_role('admin');
  v_ly text := trim(coalesce(p_ly_do, ''));
  v_ma text; v_may text; v_sl numeric; v_moc timestamptz; v_gn timestamptz;
  v_ket_cu jsonb; v_ket_moi jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if length(v_ly) < 3 then return jsonb_build_object('ok', false, 'error', 'Nhập lý do sửa tem'); end if;
  select * into v_old from duc_tem where lower(tag_no) = lower(trim(coalesce(p_tag_no, ''))) for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || coalesce(p_tag_no, '')); end if;

  v_ma  := case when p_data ? 'ma_sp' then trim(coalesce(p_data->>'ma_sp', '')) else v_old.ma_sp end;
  v_may := case when p_data ? 'may_duc_chi_thi' then trim(coalesce(p_data->>'may_duc_chi_thi', '')) else v_old.may_tt end;
  v_sl  := case when p_data ? 'so_luong' then nullif(p_data->>'so_luong', '')::numeric else v_old.so_luong_tt end;
  v_gn  := case when p_data ? 'ngay_gio_ghi_nhan' then nullif(p_data->>'ngay_gio_ghi_nhan', '')::timestamptz else v_old.ngay_gio_ghi_nhan end;
  if coalesce(v_ma, '') = '' then return jsonb_build_object('ok', false, 'error', 'Chọn Mã sản phẩm'); end if;
  if coalesce(v_may, '') = '' and v_old.may_tt is not null then return jsonb_build_object('ok', false, 'error', 'Chọn Máy đúc'); end if;
  if v_sl is null or v_sl <= 0 then return jsonb_build_object('ok', false, 'error', 'Số lượng phải > 0'); end if;
  if v_gn > now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Ngày giờ SX thực tế không được ở tương lai'); end if;
  v_moc := coalesce(v_gn, v_old.ngay_gio_in);

  v_ket_cu := duc_tem_ca_da_ket(v_old.may_tt, v_old.ma_sp, coalesce(v_old.ngay_gio_ghi_nhan, v_old.ngay_gio_in));
  v_ket_moi := duc_tem_ca_da_ket(nullif(v_may, ''), v_ma, v_moc);
  if (v_ket_cu is not null or v_ket_moi is not null) and not v_admin then
    return jsonb_build_object('ok', false, 'error',
      'Tem thuộc ' || (select coalesce(k->>'ca', '') || ' ' || to_char((k->>'ngay')::date, 'DD/MM/YYYY') from (select coalesce(v_ket_cu, v_ket_moi) k) x)
      || ' đã kết ca — chỉ admin được sửa.');
  end if;

  perform set_config('mes.tem_hanh_dong', 'sua', true);
  perform set_config('mes.tem_ly_do', v_ly, true);
  perform set_config('mes.tem_ca_da_ket', coalesce(coalesce(v_ket_cu, v_ket_moi)::text, ''), true);
  update duc_tem set
    ten_sp = case when p_data ? 'ten_sp' then p_data->>'ten_sp' else ten_sp end,
    ma_sp = v_ma,
    so_luong = v_sl, so_luong_tt = v_sl,
    lot = case when p_data ? 'lot' then p_data->>'lot' else lot end,
    so_khuon = case when p_data ? 'so_khuon' then p_data->>'so_khuon' else so_khuon end,
    so_khuon_tt = case when p_data ? 'so_khuon' then p_data->>'so_khuon' else so_khuon_tt end,
    nguyen_lieu = case when p_data ? 'nguyen_lieu' then p_data->>'nguyen_lieu' else nguyen_lieu end,
    may_duc_chi_thi = case when p_data ? 'may_duc_chi_thi' then nullif(v_may, '') else may_duc_chi_thi end,
    may_tt = case when p_data ? 'may_duc_chi_thi' then nullif(v_may, '') else may_tt end,
    ghi_chu = case when p_data ? 'ghi_chu' then p_data->>'ghi_chu' else ghi_chu end,
    nguoi_tt = case when p_data ? 'nguoi_tt' then p_data->>'nguoi_tt' else nguoi_tt end,
    ngay_gio_ghi_nhan = v_gn
  where tag_no = v_old.tag_no;
  perform set_config('mes.tem_hanh_dong', '', true);
  perform set_config('mes.tem_ly_do', '', true);
  perform set_config('mes.tem_ca_da_ket', '', true);
  return jsonb_build_object('ok', true, 'tag_no', v_old.tag_no, 'ca_da_ket', coalesce(v_ket_cu, v_ket_moi));
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
  return jsonb_build_object('ok', false, 'error', 'Dữ liệu không hợp lệ: ' || sqlerrm);
end $$;
revoke execute on function duc_tem_sua(text, jsonb, text) from public, anon;
grant execute on function duc_tem_sua(text, jsonb, text) to authenticated;

-- 5) RPC xoá tem -----------------------------------------------------------------------
create or replace function duc_tem_xoa(p_tag_no text, p_ly_do text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old duc_tem; v_ly text := trim(coalesce(p_ly_do, '')); v_ket jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if length(v_ly) < 3 then return jsonb_build_object('ok', false, 'error', 'Nhập lý do xoá tem'); end if;
  select * into v_old from duc_tem where lower(tag_no) = lower(trim(coalesce(p_tag_no, ''))) for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || coalesce(p_tag_no, '')); end if;
  v_ket := duc_tem_ca_da_ket(v_old.may_tt, v_old.ma_sp, coalesce(v_old.ngay_gio_ghi_nhan, v_old.ngay_gio_in));
  if v_ket is not null and not has_role('admin') then
    return jsonb_build_object('ok', false, 'error',
      'Tem thuộc ' || coalesce(v_ket->>'ca', '') || ' ' || to_char((v_ket->>'ngay')::date, 'DD/MM/YYYY') || ' đã kết ca — chỉ admin được xoá.');
  end if;
  perform set_config('mes.tem_hanh_dong', 'xoa', true);
  perform set_config('mes.tem_ly_do', v_ly, true);
  perform set_config('mes.tem_ca_da_ket', coalesce(v_ket::text, ''), true);
  delete from duc_tem where tag_no = v_old.tag_no;
  perform set_config('mes.tem_hanh_dong', '', true);
  perform set_config('mes.tem_ly_do', '', true);
  perform set_config('mes.tem_ca_da_ket', '', true);
  return jsonb_build_object('ok', true, 'tag_no', v_old.tag_no, 'ca_da_ket', v_ket);
end $$;
revoke execute on function duc_tem_xoa(text, text) from public, anon;
grant execute on function duc_tem_xoa(text, text) to authenticated;

-- 6) Thu hồi ghi trực tiếp bảng duc_tem ------------------------------------------------
drop policy if exists "duc_tem authenticated delete" on duc_tem;
drop policy if exists "duc_tem authenticated update" on duc_tem;
revoke insert, update, delete, truncate, trigger, references on duc_tem from anon, authenticated;
