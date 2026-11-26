-- ============================================================================
-- T352: Phiếu đề nghị cấp NVL
--   Thống kê lập → Quản lý bộ phận (đúng bộ phận) xác nhận → Kho được xuất ngay
--   → Thủ kho xác nhận số thực cấp; Giám đốc hành chính duyệt bổ sung (sau khi QLBP xác nhận).
--   • Vai trò mới: giam_doc_hanh_chinh "Giám đốc hành chính".
--   • Xuất kho NVL (quét tem / thủ công) chọn được phiếu → giao dịch ghi phieu_cap_id,
--     chỉ nhận phiếu đã QLBP xác nhận, chưa đóng kho, mã NVL có trong phiếu.
--   • Chuông: nguon = 'nvl_cap'.
-- Chạy lại an toàn.
-- ============================================================================

-- 1) Vai trò mới
do $$ declare v text;
begin
  select pg_get_constraintdef(oid) into v from pg_constraint where conname = 'user_roles_role_check';
  if v not like '%giam_doc_hanh_chinh%' then
    if position('''ky_thuat_duc''::text]' in v) = 0 then raise exception 'T352: không thấy mốc role check'; end if;
    execute 'alter table public.user_roles drop constraint user_roles_role_check';
    execute 'alter table public.user_roles add constraint user_roles_role_check '
         || replace(v, '''ky_thuat_duc''::text]', '''ky_thuat_duc''::text, ''giam_doc_hanh_chinh''::text]');
  end if;

  select pg_get_constraintdef(oid) into v from pg_constraint where conname = 'cv_thong_bao_nguon_check';
  if v is not null and v not like '%''nvl_cap''%' then
    execute 'alter table public.cv_thong_bao drop constraint cv_thong_bao_nguon_check';
    execute 'alter table public.cv_thong_bao add constraint cv_thong_bao_nguon_check '
         || replace(v, '])))', ', ''nvl_cap''::text])))');
  end if;
end $$;

-- 2) Bảng
create table if not exists public.nvl_phieu_cap (
  id            bigserial primary key,
  so_phieu      text not null unique,
  ngay          date not null default ((now() at time zone 'Asia/Ho_Chi_Minh')::date),
  bo_phan       text not null,
  ghi_chu       text,
  trang_thai    text not null default 'cho_qlbp' check (trang_thai in ('cho_qlbp', 'tra_lai', 'da_xac_nhan', 'huy')),
  nguoi_lap     uuid, ten_lap text, lap_luc timestamptz,
  qlbp_id       uuid, qlbp_ten text, qlbp_luc timestamptz, ly_do_tra_lai text,
  kho_id        uuid, kho_ten text, kho_luc timestamptz, kho_ghi_chu text,
  gdhc_id       uuid, gdhc_ten text, gdhc_luc timestamptz,
  gdhc_ket_qua  text check (gdhc_ket_qua in ('duyet', 'khong_duyet')), gdhc_y_kien text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists nvl_phieu_cap_ngay_idx on public.nvl_phieu_cap (ngay desc);

create table if not exists public.nvl_phieu_cap_dong (
  id          bigserial primary key,
  phieu_id    bigint not null references public.nvl_phieu_cap(id) on delete cascade,
  stt         int not null default 1,
  ma_nvl      text not null references public.nvl_materials(ma_nvl) on update cascade,
  sl_de_nghi  numeric not null check (sl_de_nghi > 0),
  muc_dich    text not null,
  sl_thuc_cap numeric check (sl_thuc_cap >= 0)
);
create index if not exists nvl_phieu_cap_dong_phieu_idx on public.nvl_phieu_cap_dong (phieu_id);

alter table public.nvl_giao_dich add column if not exists phieu_cap_id bigint references public.nvl_phieu_cap(id);
create index if not exists nvl_giao_dich_phieu_cap_idx on public.nvl_giao_dich (phieu_cap_id) where phieu_cap_id is not null;

alter table public.nvl_phieu_cap enable row level security;
alter table public.nvl_phieu_cap_dong enable row level security;
drop policy if exists "doc dang nhap" on public.nvl_phieu_cap;
create policy "doc dang nhap" on public.nvl_phieu_cap for select to authenticated using (true);
drop policy if exists "doc dang nhap" on public.nvl_phieu_cap_dong;
create policy "doc dang nhap" on public.nvl_phieu_cap_dong for select to authenticated using (true);
revoke insert, update, delete, truncate on public.nvl_phieu_cap, public.nvl_phieu_cap_dong from anon, authenticated;
revoke all on public.nvl_phieu_cap, public.nvl_phieu_cap_dong from anon;
grant select on public.nvl_phieu_cap, public.nvl_phieu_cap_dong to authenticated;

-- 3) Hàm phụ
create or replace function public.nvl_pdc_ten() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select coalesce(nullif(trim(full_name), ''), nullif(trim(username), ''), email)
                   from user_roles where user_id = auth.uid()), auth.jwt()->>'email', '');
$$;

-- Bộ phận lập phiếu = danh sách bộ phận của tài khoản (để khớp Quản lý bộ phận).
create or replace function public.nvl_pdc_ds_bo_phan() returns text[]
language sql immutable as $$
  select array['Đúc', 'Bavia', 'Gia Công', 'Cắt viền', 'Đánh bóng Kẽm', 'Sơn', 'OQC', 'Kỹ thuật', 'QA', 'Thiết bị'];
$$;

create or replace function public.nvl_pdc_la_qlbp(p_bo_phan text) returns boolean
language sql stable security definer set search_path = public as $$
  select has_role('admin') or auth.uid() = any(cv_pd_ds_role(array['quan_ly_bo_phan'], p_bo_phan));
$$;

create or replace function public.nvl_pdc_tb(p_nguoi uuid[], p_loai text, p_khoa text, p_id bigint, p_nd text, p_xu_ly boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform cv_pd_gui(p_nguoi, 'nvl_cap', p_loai, p_khoa, 'phieu-cap-nvl.html?id=' || p_id, p_nd, p_xu_ly);
exception when others then raise warning 'nvl_pdc_tb: %', sqlerrm;
end $$;

create or replace function public.nvl_pdc_tb_xong(p_khoa text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform cv_pd_xong(p_khoa, false);
exception when others then raise warning 'nvl_pdc_tb_xong: %', sqlerrm;
end $$;

-- 4) Quyền của người đang đăng nhập (giao diện dùng để hiện nút)
create or replace function public.nvl_pdc_quyen() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'lap',   has_role('admin', 'nhan_vien_thong_ke'),
    'admin', has_role('admin'),
    'qlbp',  case when has_role('admin') then to_jsonb(nvl_pdc_ds_bo_phan())
                  else coalesce((select to_jsonb(bo_phan_phu_trach) from user_roles
                                 where user_id = auth.uid() and role = 'quan_ly_bo_phan'), '[]'::jsonb) end,
    'kho',   has_role('admin', 'kho_nvl'),
    'gdhc',  has_role('admin', 'giam_doc_hanh_chinh'),
    'uid',   auth.uid());
$$;

-- 5) Lập / sửa / gửi lại phiếu
create or replace function public.nvl_pdc_luu(p_id bigint, p_ngay date, p_bo_phan text, p_ghi_chu text, p_dong jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v public.nvl_phieu_cap; v_id bigint; v_so text; v_n int; d jsonb; i int := 0;
        v_ngay date := coalesce(p_ngay, (now() at time zone 'Asia/Ho_Chi_Minh')::date);
begin
  if not has_role('admin', 'nhan_vien_thong_ke') then
    raise exception '⛔ Chỉ Thống kê được lập phiếu đề nghị cấp NVL.' using errcode = '42501';
  end if;
  p_bo_phan := nullif(trim(coalesce(p_bo_phan, '')), '');
  if p_bo_phan is null or not (p_bo_phan = any(nvl_pdc_ds_bo_phan())) then raise exception 'Chọn bộ phận yêu cầu.'; end if;
  if p_dong is null or jsonb_typeof(p_dong) <> 'array' or jsonb_array_length(p_dong) = 0 then
    raise exception 'Phiếu chưa có dòng NVL nào.';
  end if;
  for d in select * from jsonb_array_elements(p_dong) loop
    if not exists (select 1 from nvl_materials where ma_nvl = d->>'ma_nvl') then
      raise exception 'Mã NVL không có trong danh mục: %', coalesce(d->>'ma_nvl', '(trống)');
    end if;
    if coalesce((d->>'sl_de_nghi')::numeric, 0) <= 0 then raise exception 'Số lượng đề nghị mã % phải > 0.', d->>'ma_nvl'; end if;
    if nullif(trim(coalesce(d->>'muc_dich', '')), '') is null then raise exception 'Nhập mục đích cấp cho mã %.', d->>'ma_nvl'; end if;
  end loop;

  if p_id is null then
    perform pg_advisory_xact_lock(hashtext('nvl_pdc_so_phieu'));
    select count(*) + 1 into v_n from nvl_phieu_cap where so_phieu like 'DN' || to_char(v_ngay, 'YYMMDD') || '-%';
    v_so := 'DN' || to_char(v_ngay, 'YYMMDD') || '-' || lpad(v_n::text, 2, '0');
    while exists (select 1 from nvl_phieu_cap where so_phieu = v_so) loop
      v_n := v_n + 1; v_so := 'DN' || to_char(v_ngay, 'YYMMDD') || '-' || lpad(v_n::text, 2, '0');
    end loop;
    insert into nvl_phieu_cap (so_phieu, ngay, bo_phan, ghi_chu, nguoi_lap, ten_lap, lap_luc)
    values (v_so, v_ngay, p_bo_phan, nullif(trim(coalesce(p_ghi_chu, '')), ''), auth.uid(), nvl_pdc_ten(), now())
    returning id into v_id;
  else
    select * into v from nvl_phieu_cap where id = p_id for update;
    if not found then raise exception 'Không tìm thấy phiếu.'; end if;
    if v.trang_thai not in ('cho_qlbp', 'tra_lai') then raise exception '🔒 Phiếu đã xác nhận, không sửa được.'; end if;
    if v.nguoi_lap is distinct from auth.uid() and not has_role('admin') then
      raise exception '⛔ Chỉ người lập được sửa phiếu.' using errcode = '42501';
    end if;
    v_id := p_id; v_so := v.so_phieu;
    if v.bo_phan <> p_bo_phan then perform nvl_pdc_tb_xong('nvlcap:' || v_id || ':qlbp'); end if;
    update nvl_phieu_cap set ngay = v_ngay, bo_phan = p_bo_phan, ghi_chu = nullif(trim(coalesce(p_ghi_chu, '')), ''),
      trang_thai = 'cho_qlbp', ly_do_tra_lai = null, updated_at = now() where id = v_id;
    delete from nvl_phieu_cap_dong where phieu_id = v_id;
  end if;

  for d in select * from jsonb_array_elements(p_dong) loop
    i := i + 1;
    insert into nvl_phieu_cap_dong (phieu_id, stt, ma_nvl, sl_de_nghi, muc_dich)
    values (v_id, i, d->>'ma_nvl', (d->>'sl_de_nghi')::numeric, trim(d->>'muc_dich'));
  end loop;

  perform nvl_pdc_tb(cv_pd_ds_role(array['quan_ly_bo_phan'], p_bo_phan), 'can_duyet', 'nvlcap:' || v_id || ':qlbp', v_id,
    'Xác nhận phiếu cấp NVL ' || v_so || ' (' || p_bo_phan || ')', true);
  return v_id;
end $$;

-- 6) Quản lý bộ phận xác nhận / trả lại
create or replace function public.nvl_pdc_qlbp(p_id bigint, p_dong_y boolean, p_ly_do text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v public.nvl_phieu_cap;
begin
  select * into v from nvl_phieu_cap where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  if not nvl_pdc_la_qlbp(v.bo_phan) then
    raise exception '⛔ Chỉ Quản lý bộ phận % được xác nhận phiếu này.', v.bo_phan using errcode = '42501';
  end if;
  if v.trang_thai <> 'cho_qlbp' then raise exception 'Phiếu không ở trạng thái chờ xác nhận.'; end if;
  perform nvl_pdc_tb_xong('nvlcap:' || p_id || ':qlbp');
  if p_dong_y then
    update nvl_phieu_cap set trang_thai = 'da_xac_nhan', qlbp_id = auth.uid(), qlbp_ten = nvl_pdc_ten(), qlbp_luc = now(),
      updated_at = now() where id = p_id;
    perform nvl_pdc_tb(cv_pd_ds_role(array['kho_nvl'], null), 'can_duyet', 'nvlcap:' || p_id || ':kho', p_id,
      'Cấp NVL theo phiếu ' || v.so_phieu || ' (' || v.bo_phan || ')', true);
    perform nvl_pdc_tb(cv_pd_ds_role(array['giam_doc_hanh_chinh'], null), 'can_duyet', 'nvlcap:' || p_id || ':gdhc', p_id,
      'Duyệt phiếu cấp NVL ' || v.so_phieu || ' (' || v.bo_phan || ')', true);
    perform nvl_pdc_tb(array[v.nguoi_lap], 'da_duyet', 'nvlcap:' || p_id, p_id,
      'Phiếu cấp NVL ' || v.so_phieu || ' đã được QL bộ phận xác nhận', false);
  else
    if nullif(trim(coalesce(p_ly_do, '')), '') is null then raise exception 'Nhập lý do trả lại.'; end if;
    update nvl_phieu_cap set trang_thai = 'tra_lai', ly_do_tra_lai = trim(p_ly_do), updated_at = now() where id = p_id;
    perform nvl_pdc_tb(array[v.nguoi_lap], 'tu_choi_duyet', 'nvlcap:' || p_id, p_id,
      'Phiếu cấp NVL ' || v.so_phieu || ' bị trả lại: ' || trim(p_ly_do), false);
  end if;
end $$;

-- 7) Thủ kho xác nhận số thực cấp (p_dong = [{id, sl_thuc_cap}])
create or replace function public.nvl_pdc_kho(p_id bigint, p_dong jsonb, p_ghi_chu text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v public.nvl_phieu_cap; d jsonb;
begin
  if not has_role('admin', 'kho_nvl') then raise exception '⛔ Chỉ Thủ kho NVL được xác nhận cấp.' using errcode = '42501'; end if;
  select * into v from nvl_phieu_cap where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  if v.trang_thai <> 'da_xac_nhan' then raise exception 'Phiếu chưa được Quản lý bộ phận xác nhận.'; end if;
  if v.kho_luc is not null then raise exception 'Thủ kho đã xác nhận phiếu này rồi.'; end if;
  for d in select * from jsonb_array_elements(coalesce(p_dong, '[]'::jsonb)) loop
    if coalesce((d->>'sl_thuc_cap')::numeric, -1) < 0 then raise exception 'Số thực cấp không hợp lệ.'; end if;
    update nvl_phieu_cap_dong set sl_thuc_cap = (d->>'sl_thuc_cap')::numeric
    where id = (d->>'id')::bigint and phieu_id = p_id;
  end loop;
  update nvl_phieu_cap_dong set sl_thuc_cap = 0 where phieu_id = p_id and sl_thuc_cap is null;
  update nvl_phieu_cap set kho_id = auth.uid(), kho_ten = nvl_pdc_ten(), kho_luc = now(),
    kho_ghi_chu = nullif(trim(coalesce(p_ghi_chu, '')), ''), updated_at = now() where id = p_id;
  perform nvl_pdc_tb_xong('nvlcap:' || p_id || ':kho');
  perform nvl_pdc_tb(array[v.nguoi_lap], 'da_duyet', 'nvlcap:' || p_id, p_id,
    'Kho đã cấp NVL theo phiếu ' || v.so_phieu, false);
end $$;

-- 8) Giám đốc hành chính duyệt (sau khi QLBP xác nhận, trước hoặc sau Thủ kho)
create or replace function public.nvl_pdc_gdhc(p_id bigint, p_duyet boolean, p_y_kien text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v public.nvl_phieu_cap;
begin
  if not has_role('admin', 'giam_doc_hanh_chinh') then
    raise exception '⛔ Chỉ Giám đốc hành chính được duyệt.' using errcode = '42501';
  end if;
  select * into v from nvl_phieu_cap where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  if v.trang_thai <> 'da_xac_nhan' then raise exception 'Phiếu chưa được Quản lý bộ phận xác nhận.'; end if;
  if v.gdhc_luc is not null then raise exception 'Phiếu đã được Giám đốc hành chính xử lý.'; end if;
  if not p_duyet and nullif(trim(coalesce(p_y_kien, '')), '') is null then raise exception 'Nhập ý kiến khi không duyệt.'; end if;
  update nvl_phieu_cap set gdhc_id = auth.uid(), gdhc_ten = nvl_pdc_ten(), gdhc_luc = now(),
    gdhc_ket_qua = case when p_duyet then 'duyet' else 'khong_duyet' end,
    gdhc_y_kien = nullif(trim(coalesce(p_y_kien, '')), ''), updated_at = now() where id = p_id;
  perform nvl_pdc_tb_xong('nvlcap:' || p_id || ':gdhc');
  perform nvl_pdc_tb(array[v.nguoi_lap] || cv_pd_ds_role(array['quan_ly_bo_phan'], v.bo_phan),
    case when p_duyet then 'da_duyet' else 'tu_choi_duyet' end, 'nvlcap:' || p_id, p_id,
    'Phiếu cấp NVL ' || v.so_phieu || case when p_duyet then ' đã được GĐ hành chính duyệt'
      else ' không được GĐ hành chính duyệt: ' || trim(p_y_kien) end, false);
end $$;

-- 9) Huỷ phiếu (người lập / admin, khi chưa xác nhận)
create or replace function public.nvl_pdc_huy(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v public.nvl_phieu_cap;
begin
  select * into v from nvl_phieu_cap where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  if v.nguoi_lap is distinct from auth.uid() and not has_role('admin') then
    raise exception '⛔ Chỉ người lập được huỷ phiếu.' using errcode = '42501';
  end if;
  if v.trang_thai not in ('cho_qlbp', 'tra_lai') then raise exception '🔒 Phiếu đã xác nhận, không huỷ được.'; end if;
  update nvl_phieu_cap set trang_thai = 'huy', updated_at = now() where id = p_id;
  perform nvl_pdc_tb_xong('nvlcap:' || p_id || ':qlbp');
end $$;

-- 10) Xuất kho NVL nhận thêm tham số phiếu (p_phieu_cap)
do $$
declare d text; ck text :=
  E'  if p_phieu_cap is not null then\n' ||
  E'    if p_loai <> ''OUT'' then return jsonb_build_object(''ok'', false, ''error'', ''Phiếu đề nghị chỉ dùng khi xuất kho''); end if;\n' ||
  E'    if not exists (select 1 from nvl_phieu_cap where id = p_phieu_cap and trang_thai = ''da_xac_nhan'' and kho_luc is null) then\n' ||
  E'      return jsonb_build_object(''ok'', false, ''error'', ''Phiếu đề nghị chưa được QL bộ phận xác nhận hoặc kho đã đóng phiếu'');\n' ||
  E'    end if;\n' ||
  E'  end if;\n';
begin
  if not exists (select 1 from pg_proc where proname = 'nvl_process_multi_transaction' and pronamespace = 'public'::regnamespace
                 and pg_get_function_arguments(oid) like '%p_phieu_cap%') then
    d := pg_get_functiondef('public.nvl_process_multi_transaction(text,jsonb,text,text)'::regprocedure);
    if position('p_bo_phan text DEFAULT NULL::text)' in d) = 0
       or position('  if p_items is null or jsonb_array_length(p_items) = 0 then' in d) = 0
       or position('    v_new_status := case when p_loai' in d) = 0
       or position('ts_goc, bo_phan_nhan)' in d) = 0
       or position('v_ton_sau, v_now, p_bo_phan);' in d) = 0 then raise exception 'T352: không thấy mốc multi_transaction'; end if;
    d := replace(d, 'p_bo_phan text DEFAULT NULL::text)', 'p_bo_phan text DEFAULT NULL::text, p_phieu_cap bigint DEFAULT NULL::bigint)');
    d := replace(d, '  if p_items is null or jsonb_array_length(p_items) = 0 then', ck || '  if p_items is null or jsonb_array_length(p_items) = 0 then');
    d := replace(d, '    v_new_status := case when p_loai',
      E'    if p_phieu_cap is not null and not exists (select 1 from nvl_phieu_cap_dong where phieu_id = p_phieu_cap and ma_nvl = v_tem.ma_nvl) then\n' ||
      E'      v_errors := v_errors || to_jsonb(''Tem '' || v_tag_no || '': mã '' || v_tem.ma_nvl || '' không có trong phiếu đề nghị'');\n' ||
      E'      continue;\n' ||
      E'    end if;\n' ||
      '    v_new_status := case when p_loai');
    d := replace(d, 'ts_goc, bo_phan_nhan)', 'ts_goc, bo_phan_nhan, phieu_cap_id)');
    d := replace(d, 'v_ton_sau, v_now, p_bo_phan);', 'v_ton_sau, v_now, p_bo_phan, p_phieu_cap);');
    drop function public.nvl_process_multi_transaction(text, jsonb, text, text);
    execute d;
  end if;

  if not exists (select 1 from pg_proc where proname = 'nvl_add_transaction' and pronamespace = 'public'::regnamespace
                 and pg_get_function_arguments(oid) like '%p_phieu_cap%') then
    d := pg_get_functiondef('public.nvl_add_transaction(date,text,text,numeric,text,text,text)'::regprocedure);
    if position('p_bo_phan text DEFAULT NULL::text)' in d) = 0
       or position('  if not exists (select 1 from nvl_materials where ma_nvl = p_ma_nvl) then' in d) = 0
       or position('ts_goc, bo_phan_nhan)' in d) = 0
       or position('now(), p_bo_phan);' in d) = 0 then raise exception 'T352: không thấy mốc add_transaction'; end if;
    d := replace(d, 'p_bo_phan text DEFAULT NULL::text)', 'p_bo_phan text DEFAULT NULL::text, p_phieu_cap bigint DEFAULT NULL::bigint)');
    d := replace(d, '  if not exists (select 1 from nvl_materials where ma_nvl = p_ma_nvl) then',
      ck ||
      E'  if p_phieu_cap is not null and not exists (select 1 from nvl_phieu_cap_dong where phieu_id = p_phieu_cap and ma_nvl = p_ma_nvl) then\n' ||
      E'    return jsonb_build_object(''ok'', false, ''error'', ''Mã '' || p_ma_nvl || '' không có trong phiếu đề nghị'');\n' ||
      E'  end if;\n' ||
      '  if not exists (select 1 from nvl_materials where ma_nvl = p_ma_nvl) then');
    d := replace(d, 'ts_goc, bo_phan_nhan)', 'ts_goc, bo_phan_nhan, phieu_cap_id)');
    d := replace(d, 'now(), p_bo_phan);', 'now(), p_bo_phan, p_phieu_cap);');
    drop function public.nvl_add_transaction(date, text, text, numeric, text, text, text);
    execute d;
  end if;
end $$;

-- 11) Quyền gọi hàm
revoke all on function public.nvl_pdc_ten(), public.nvl_pdc_la_qlbp(text),
  public.nvl_pdc_tb(uuid[], text, text, bigint, text, boolean), public.nvl_pdc_tb_xong(text)
  from public, anon, authenticated;
revoke all on function public.nvl_pdc_quyen(), public.nvl_pdc_luu(bigint, date, text, text, jsonb),
  public.nvl_pdc_qlbp(bigint, boolean, text), public.nvl_pdc_kho(bigint, jsonb, text),
  public.nvl_pdc_gdhc(bigint, boolean, text), public.nvl_pdc_huy(bigint),
  public.nvl_process_multi_transaction(text, jsonb, text, text, bigint),
  public.nvl_add_transaction(date, text, text, numeric, text, text, text, bigint)
  from public, anon;
grant execute on function public.nvl_pdc_quyen(), public.nvl_pdc_luu(bigint, date, text, text, jsonb),
  public.nvl_pdc_qlbp(bigint, boolean, text), public.nvl_pdc_kho(bigint, jsonb, text),
  public.nvl_pdc_gdhc(bigint, boolean, text), public.nvl_pdc_huy(bigint),
  public.nvl_process_multi_transaction(text, jsonb, text, text, bigint),
  public.nvl_add_transaction(date, text, text, numeric, text, text, text, bigint)
  to authenticated;

notify pgrst, 'reload schema';
