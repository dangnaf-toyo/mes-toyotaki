-- ============================================================================
-- T395 (27/11/2026) — Gia công: DÂY CHUYỀN máy (luân chuyển 1-1, chỉ quét tem ở máy cuối)
--
-- User chốt 27/11: làm theo đề xuất + có công tắc bật/tắt từng dây chuyền.
--   * Bảng gc_day_chuyen: tên, các máy theo thứ tự (máy cuối = máy quét tem), mã SP
--     áp dụng (trống = mọi mã), công tắc bat. 1 máy chỉ thuộc 1 dây chuyền.
--   * Dây chuyền "đang chạy" cho 1 máy khi: bat = true và mã máy đang chạy nằm trong
--     ds_ma_sp (hoặc ds_ma_sp trống). Tắt / mã khác → từng máy chạy riêng như cũ.
--   * gc_quet: máy giữa dây chuyền không quét được (báo quét ở máy cuối); máy cuối quét
--     1 lần = làm luôn n bước liên tiếp (bước của máy cuối = bước đầu + n − 1);
--     kiểm loại máy từng bước theo quy trình CNC; máy giữa phải mở cùng mã trong ca.
--     Mã chưa khai quy trình CNC: số bước = số máy dây chuyền.
--   * gc_may_luu: lưu máy cuối → tự mở các máy giữa cùng mã + người (KH ca để trống).
--   * gc_xong ở máy cuối → tự ghi "đã xong" cho từng máy giữa (gc_tem_buoc.dc_chinh = id
--     dòng máy cuối), SL ra máy i = SL ra cuối + NG ở các máy sau i; NG ghi theo máy
--     được chuyển sang dòng máy đó. Huỷ xong → xoá dòng máy giữa, NG trả về dòng chính.
--   * gc_ng_nhieu: mỗi dòng NG chọn được máy gây lỗi (r->>'may') trong dây chuyền →
--     ghi vào trạm (cd_tram_hien_tai) của máy đó.
--   * Dừng máy: báo dừng ở 1 máy dây chuyền → các máy khác (đã mở ca, chưa có dừng mở)
--     tự có lần dừng kèm (gc_su_co.dc_goc = id lần gốc); máy chạy lại / báo nhầm ở máy
--     gốc → các lần kèm đóng / huỷ theo. Không đóng/huỷ lẻ được lần kèm.
--   * Nút "Dừng" xe (gc_dung_xe) không ghi cho máy giữa (ít gặp).
-- Trạng thái: ĐÃ CHẠY PROD + STAGING 27/11/2026 (t395a, t395b1–b3, t395c). An toàn chạy lại.
-- ============================================================================

-- ── t395a: bảng + cột + hàm khai báo ───────────────────────────────────────
create table if not exists public.gc_day_chuyen (
  id            bigserial primary key,
  ten           text not null unique,
  ds_may        text[] not null,
  ds_ma_sp      text[] not null default '{}',
  bat           boolean not null default true,
  ghi_chu       text,
  cap_nhat_luc  timestamptz not null default now(),
  cap_nhat_boi  text
);
alter table public.gc_day_chuyen enable row level security;
drop policy if exists "doc gc_day_chuyen" on public.gc_day_chuyen;
create policy "doc gc_day_chuyen" on public.gc_day_chuyen for select to authenticated using (true);

alter table public.gc_tem_buoc add column if not exists dc_ten text;
alter table public.gc_tem_buoc add column if not exists dc_may text[];
alter table public.gc_tem_buoc add column if not exists dc_chinh bigint;
create index if not exists idx_gc_tem_buoc_dc_chinh on public.gc_tem_buoc (dc_chinh) where dc_chinh is not null;
alter table public.gc_su_co add column if not exists dc_goc bigint;
create index if not exists idx_gc_su_co_dc_goc on public.gc_su_co (dc_goc) where dc_goc is not null;

-- Dây chuyền đang chạy của 1 máy với 1 mã (null = chạy riêng)
create or replace function public.gc_dc_cua_may(p_ma_may text, p_ma_sp text)
returns public.gc_day_chuyen
language sql stable security definer set search_path = public as $$
  select * from gc_day_chuyen
  where bat and p_ma_may = any(ds_may) and (cardinality(ds_ma_sp) = 0 or p_ma_sp = any(ds_ma_sp))
  order by id limit 1;
$$;
revoke execute on function public.gc_dc_cua_may(text, text) from public, anon, authenticated;

create or replace function public.gc_day_chuyen_luu(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id bigint := nullif(p->>'id', '')::bigint;
  v_ten text := trim(coalesce(p->>'ten', ''));
  v_may text[]; v_ma text[]; m text; s text; v_khac text; v_mm master_machines%rowtype;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if not has_role('admin', 'quan_ly_bo_phan', 'qlsx_truong_phong') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ admin / quản lý bộ phận / QLSX được khai dây chuyền');
  end if;
  if v_ten = '' then return jsonb_build_object('ok', false, 'error', 'Nhập tên dây chuyền'); end if;
  select coalesce(array_agg(trim(x) order by o), '{}') into v_may
    from jsonb_array_elements_text(coalesce(p->'ds_may', '[]')) with ordinality as u(x, o) where trim(x) <> '';
  select coalesce(array_agg(distinct trim(x)), '{}') into v_ma
    from jsonb_array_elements_text(coalesce(p->'ds_ma_sp', '[]')) as u(x) where trim(x) <> '';
  if cardinality(v_may) < 2 then return jsonb_build_object('ok', false, 'error', 'Dây chuyền cần ít nhất 2 máy'); end if;
  if (select count(distinct x) from unnest(v_may) x) <> cardinality(v_may) then
    return jsonb_build_object('ok', false, 'error', 'Có máy bị chọn 2 lần');
  end if;
  foreach m in array v_may loop
    select * into v_mm from master_machines where ma_may = m and bo_phan = 'Gia công - Sơn';
    if not found then return jsonb_build_object('ok', false, 'error', m || ' không có trong danh mục máy Gia công'); end if;
    select ten into v_khac from gc_day_chuyen where m = any(ds_may) and id is distinct from v_id limit 1;
    if v_khac is not null then return jsonb_build_object('ok', false, 'error', m || ' đã thuộc dây chuyền ' || v_khac); end if;
    foreach s in array v_ma loop
      if not (s = any(coalesce(v_mm.ma_sp_dung, '{}'))) then
        return jsonb_build_object('ok', false, 'error', m || ' chưa khai làm được mã ' || s || ' (Quản lý danh mục → Máy-Line)');
      end if;
    end loop;
  end loop;
  foreach s in array v_ma loop
    if not exists (select 1 from master_products where ma_sp = s) then
      return jsonb_build_object('ok', false, 'error', 'Mã ' || s || ' không có trong Danh mục SP');
    end if;
  end loop;
  if exists (select 1 from gc_day_chuyen where ten = v_ten and id is distinct from v_id) then
    return jsonb_build_object('ok', false, 'error', 'Tên dây chuyền đã có');
  end if;
  if v_id is null then
    insert into gc_day_chuyen (ten, ds_may, ds_ma_sp, bat, ghi_chu, cap_nhat_boi)
    values (v_ten, v_may, v_ma, coalesce((p->>'bat')::boolean, true), nullif(trim(coalesce(p->>'ghi_chu', '')), ''), duc_su_co_nguoi_hien_tai())
    returning id into v_id;
  else
    update gc_day_chuyen set ten = v_ten, ds_may = v_may, ds_ma_sp = v_ma, bat = coalesce((p->>'bat')::boolean, bat),
      ghi_chu = nullif(trim(coalesce(p->>'ghi_chu', '')), ''), cap_nhat_luc = now(), cap_nhat_boi = duc_su_co_nguoi_hien_tai()
    where id = v_id;
    if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dây chuyền'); end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke execute on function public.gc_day_chuyen_luu(jsonb) from public, anon;
grant execute on function public.gc_day_chuyen_luu(jsonb) to authenticated;

create or replace function public.gc_day_chuyen_bat(p_id bigint, p_bat boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if not has_role('admin', 'quan_ly_bo_phan', 'qlsx_truong_phong') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ admin / quản lý bộ phận / QLSX được bật tắt dây chuyền');
  end if;
  update gc_day_chuyen set bat = coalesce(p_bat, false), cap_nhat_luc = now(), cap_nhat_boi = duc_su_co_nguoi_hien_tai() where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dây chuyền'); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.gc_day_chuyen_bat(bigint, boolean) from public, anon;
grant execute on function public.gc_day_chuyen_bat(bigint, boolean) to authenticated;

create or replace function public.gc_day_chuyen_xoa(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if not has_role('admin', 'quan_ly_bo_phan', 'qlsx_truong_phong') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ admin / quản lý bộ phận / QLSX được xoá dây chuyền');
  end if;
  delete from gc_day_chuyen where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dây chuyền'); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.gc_day_chuyen_xoa(bigint) from public, anon;
grant execute on function public.gc_day_chuyen_xoa(bigint) to authenticated;

-- ── t395b: quét / mở máy / xong / huỷ xong / NG ────────────────────────────
create or replace function public.gc_quet(p_id_tram text, p_tag text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tram cd_tram_hien_tai%rowtype; v_tem duc_tem%rowtype; v_tag text := upper(trim(coalesce(p_tag, '')));
  v_steps text[]; v_i int; v_j int; v_loc text; v_loai text; v_route record; v_tong int; v_buoc int; v_khac record; v_xong record;
  v_line_bavia text; v_id bigint; v_user text := duc_su_co_nguoi_hien_tai(); v_now timestamptz := now();
  v_dc gc_day_chuyen; v_n int := 1; v_bc int; v_k int; v_mk text; v_lk text; -- T395
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if v_tag = '' then return jsonb_build_object('ok', false, 'error', 'Chưa có mã quét'); end if;
  if v_tag ~ '^(TP|GC)' and exists (select 1 from duc_tem where tag_no = v_tag and trang_thai in ('Chờ đóng gói TP', 'Đã đóng gói TP') and tram_cong_doan = 'Gia Công') then -- T343
    return gc_dong_thung(p_id_tram, v_tag);
  end if;
  select * into v_tram from cd_tram_hien_tai where id_tram = p_id_tram and cong_doan = 'Gia Công';
  if not found then return jsonb_build_object('ok', false, 'error', 'Máy chưa được mở trong ca này'); end if;
  if gc_ca_da_ket(v_tram.ngay, v_tram.ca) then return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không ghi thêm được'); end if;

  -- T395: máy giữa dây chuyền không quét tem
  v_dc := gc_dc_cua_may(v_tram.ten_tram, v_tram.ma_sp);
  if v_dc.id is not null then
    v_n := cardinality(v_dc.ds_may);
    if v_dc.ds_may[v_n] <> v_tram.ten_tram then
      return jsonb_build_object('ok', false, 'error', v_tram.ten_tram || ' thuộc dây chuyền ' || v_dc.ten || ' — quét tem ở máy cuối ' || v_dc.ds_may[v_n]);
    end if;
  end if;

  select * into v_tem from duc_tem where tag_no = v_tag for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || v_tag); end if;
  if v_tem.ma_sp is distinct from v_tram.ma_sp then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' là mã ' || coalesce(v_tem.ma_sp, '?') || ', ' || v_tram.ten_tram || ' đang chạy mã ' || v_tram.ma_sp);
  end if;
  if duc_tem_id_ncp_cach_ly(v_tem.tag_no) is not null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang bị cách ly theo phiếu NCP ' || duc_tem_id_ncp_cach_ly(v_tem.tag_no) || '. Báo QC.');
  end if;
  if coalesce(v_tem.trang_thai, '') in ('Chờ sản xuất', 'NG chờ sửa', 'Chờ đóng gói TP') then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang ở trạng thái "' || v_tem.trang_thai || '", chưa dùng cho Gia công được');
  end if;
  if coalesce(v_tem.so_luong, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' không còn số lượng (đã dùng hết / NG hết)');
  end if;
  select ten_line into v_line_bavia from bavia_line_nguon where tag_no = v_tem.tag_no and bo_luc is null;
  if v_line_bavia is not null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang khai báo nguồn ở Bavia ' || v_line_bavia || '. Bavia bấm Bỏ trước.');
  end if;
  if v_tem.tag_no ~ '^(TP|GC)' and exists (select 1 from cd_chuyen_cong_doan_log where tag_no = v_tem.tag_no and ghi_chu like 'T338 Chia xe %') then -- T340
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' là thùng chia từ xe đã gia công xong, không quét lại vào máy.');
  end if;
  select ma_may into v_khac from gc_tem_buoc where tag_no = v_tem.tag_no and xong_luc is null and bo_luc is null;
  if found then
    if v_khac.ma_may = v_tram.ten_tram then
      return jsonb_build_object('ok', false, 'trung', true, 'error', 'Tem ' || v_tem.tag_no || ' đã quét ở ' || v_khac.ma_may);
    end if;
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang làm ở ' || v_khac.ma_may || '. Bấm Xong hoặc Bỏ ở ' || v_khac.ma_may || ' trước.');
  end if;

  v_loai := gc_loai_may(v_tram.ten_tram);
  select count(*) into v_tong from master_cnc_routing where ma_sp = v_tram.ma_sp;
  v_tong := greatest(v_tong, v_n); -- T395: mã chưa khai quy trình → số bước = số máy dây chuyền
  select max(buoc) mb, max(xong_luc) xl, (array_agg(ma_may order by xong_luc desc))[1] mm into v_xong
  from gc_tem_buoc where tag_no = v_tem.tag_no and bo_luc is null and xong_luc is not null;
  v_buoc := coalesce(v_xong.mb, 0) + 1;
  if v_buoc > v_tong then
    return jsonb_build_object('ok', false, 'error', 'Thùng ' || v_tem.tag_no || ' đã gia công xong (' || v_tong || '/' || v_tong || ' bước, lần cuối ở ' || coalesce(v_xong.mm, '?') || ' lúc '
      || coalesce(to_char(v_xong.xl at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'), '?') || ')');
  end if;
  v_bc := v_buoc + v_n - 1;
  if v_bc > v_tong then
    return jsonb_build_object('ok', false, 'error', 'Thùng ' || v_tem.tag_no || ' đang chờ bước ' || v_buoc || '/' || v_tong
      || ', dây chuyền ' || v_dc.ten || ' có ' || v_n || ' máy — vượt số bước còn lại. Kiểm tra quy trình CNC của mã.');
  end if;
  for v_k in 1..v_n loop
    v_mk := case when v_n = 1 then v_tram.ten_tram else v_dc.ds_may[v_k] end;
    v_lk := gc_loai_may(v_mk);
    select * into v_route from master_cnc_routing where ma_sp = v_tram.ma_sp order by buoc offset v_buoc + v_k - 2 limit 1;
    if found and not (v_route.loai_may = v_lk or (v_route.loai_may = 'phay_3_truc' and v_lk = 'phay_4_truc')) then
      return jsonb_build_object('ok', false, 'error', 'Thùng ' || v_tem.tag_no || ' đang chờ bước ' || (v_buoc + v_k - 1) || '/' || v_tong || ': ' || gc_ten_loai_may(v_route.loai_may) || '. ' || v_mk || ' là máy ' || gc_ten_loai_may(v_lk) || '.');
    end if;
    if v_n > 1 and v_k < v_n and not exists (select 1 from cd_tram_hien_tai t where t.cong_doan = 'Gia Công' and t.ngay = v_tram.ngay and t.ca = v_tram.ca
        and t.ten_tram = v_mk and t.ma_sp = v_tram.ma_sp) then
      return jsonb_build_object('ok', false, 'error', v_mk || ' (dây chuyền ' || v_dc.ten || ') chưa mở mã ' || v_tram.ma_sp || ' trong ca. Bấm "Sửa máy" ở ' || v_tram.ten_tram || ' → Lưu để mở cả dây chuyền.');
    end if;
  end loop;

  select array_agg(trim(s) order by ord) into v_steps
  from unnest(string_to_array(coalesce((select quy_trinh_cong_doan from master_products where ma_sp = v_tem.ma_sp), ''), ',')) with ordinality as u(s, ord)
  where trim(s) <> '';
  v_i := array_position(v_steps, 'Gia Công');
  select cong_doan_nhan into v_loc from cd_chuyen_cong_doan_log
  where tag_no = v_tem.tag_no and coalesce(trang_thai_xac_nhan, '') <> 'Đã từ chối' order by thoi_gian_chuyen desc limit 1;
  v_loc := coalesce(v_loc, case when v_tem.tag_no ~ '^(TP|GC)' then coalesce(nullif(v_tem.tram_cong_doan, ''), 'Đúc') else 'Đúc' end);
  v_j := array_position(v_steps, v_loc);
  if v_loc <> 'Gia Công' then
    -- T243 (R12): chỉ nhận từ công đoạn LIỀN TRƯỚC, không đi tắt (VD Đúc → Gia công bỏ qua Bavia)
    if v_i is null or v_j is null or v_j <> v_i - 1 then
      return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang ở công đoạn ' || v_loc
        || case when v_i is not null and v_i > 1 then ' — phải qua ' || v_steps[v_i - 1] || ' trước rồi mới tới Gia Công' else '' end
        || ' (lưu trình: ' || array_to_string(v_steps, ' → ') || ')');
    end if;
    insert into cd_chuyen_cong_doan_log (id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech, lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc,
      cong_doan_giao, cong_doan_nhan, nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan, ghi_chu)
    values (cd_next_transfer_id(), v_now, v_tem.tag_no, v_tem.ma_sp, v_tem.ten_sp, v_tem.so_luong, v_tem.so_luong, 0, coalesce(v_tem.lot, ''),
      coalesce(v_tem.so_khuon_tt, v_tem.so_khuon, ''), coalesce(v_tem.nguyen_lieu, ''), coalesce(v_tem.may_tt, v_tem.may_duc_chi_thi, ''), coalesce(v_tem.ngay::text, ''),
      v_loc, 'Gia Công', 'Tự nhận tại ' || v_tram.ten_tram, v_user, 'Đã xác nhận chuyển công đoạn',
      to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI:SS DD/MM/YYYY'), 'Quét tem ở Bảng điều khiển Gia công');
  end if;

  insert into gc_tem_buoc (tag_no, ma_sp, ma_may, loai_may, buoc, tong_buoc, id_tram, sl_vao, nguoi_quet, dc_ten, dc_may)
  values (v_tem.tag_no, v_tem.ma_sp, v_tram.ten_tram, v_loai, v_bc, v_tong, v_tram.id_tram, v_tem.so_luong, v_user,
    case when v_n > 1 then v_dc.ten end, case when v_n > 1 then v_dc.ds_may end)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'tag_no', v_tem.tag_no, 'so_luong', v_tem.so_luong, 'buoc', v_bc, 'tong_buoc', v_tong,
    'tu_nhan', v_loc <> 'Gia Công', 'tu_cong_doan', v_loc, 'day_chuyen', case when v_n > 1 then v_dc.ten end);
end $function$;

create or replace function public.gc_may_luu(p_ngay date, p_ca text, p_ma_may text, p_ma_sp text, p_kh_ca numeric, p_nguoi text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  m master_machines%rowtype;
  p master_products%rowtype;
  v_id text;
  v_do record;
  v_user text := duc_su_co_nguoi_hien_tai();
  v_dc gc_day_chuyen; v_mk text; v_r jsonb; v_cb text[] := '{}'; -- T395
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if p_ngay is null or coalesce(p_ca, '') not in ('Ca ngày', 'Ca đêm', 'Ca 1', 'Ca 2') then
    return jsonb_build_object('ok', false, 'error', 'Ngày / ca không hợp lệ');
  end if;
  if gc_ca_da_ket(p_ngay, p_ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không sửa máy được');
  end if;
  select * into m from master_machines where ma_may = p_ma_may and bo_phan = 'Gia công - Sơn';
  if not found then return jsonb_build_object('ok', false, 'error', coalesce(p_ma_may, '?') || ' không có trong danh mục máy Gia công'); end if;
  select * into p from master_products where ma_sp = trim(coalesce(p_ma_sp, ''));
  if not found then return jsonb_build_object('ok', false, 'error', 'Mã SP ' || coalesce(p_ma_sp, '') || ' không có trong Danh mục SP'); end if;
  if coalesce(p.quy_trinh_cong_doan, '') !~ 'Gia Công' then
    return jsonb_build_object('ok', false, 'error', 'Lưu trình mã ' || p.ma_sp || ' không có công đoạn Gia Công (Danh mục SP)');
  end if;
  if not (p.ma_sp = any(coalesce(m.ma_sp_dung, '{}'))) then
    return jsonb_build_object('ok', false, 'error', m.ma_may || ' chưa khai làm được mã ' || p.ma_sp
      || '. Admin bổ sung ở Quản lý danh mục → Máy-Line → cột "Dùng cho mã SP".');
  end if;
  if coalesce(p_kh_ca, 0) < 0 then return jsonb_build_object('ok', false, 'error', 'KH ca không hợp lệ'); end if;

  select b.ma_sp, count(*) n into v_do from gc_tem_buoc b
  where b.ma_may = m.ma_may and b.xong_luc is null and b.bo_luc is null and b.ma_sp <> p.ma_sp
  group by b.ma_sp limit 1;
  if found then
    return jsonb_build_object('ok', false, 'error', m.ma_may || ' còn ' || v_do.n || ' thùng mã ' || v_do.ma_sp
      || ' đang làm. Bấm Xong hoặc Bỏ các thùng đó trước khi đổi mã.');
  end if;

  v_id := duc_normalize_name('Gia Công') || '_' || to_char(p_ngay, 'DDMMYYYY') || '_'
          || duc_normalize_name(p_ca) || '_' || duc_normalize_name(m.ma_may);
  insert into cd_tram_hien_tai (id_tram, ngay, ca, cong_doan, ten_tram, ma_sp, ten_sp, kh_ca, nguoi_thao_tac,
    so_luong_ok, so_luong_ng, version, last_updated_by, last_updated_at)
  values (v_id, p_ngay, p_ca, 'Gia Công', m.ma_may, p.ma_sp, coalesce(p.ten_sp, ''), nullif(p_kh_ca, 0),
    trim(coalesce(p_nguoi, '')), 0, 0, 1, v_user, now())
  on conflict (id_tram) do update set
    ma_sp = excluded.ma_sp, ten_sp = excluded.ten_sp, kh_ca = excluded.kh_ca, nguoi_thao_tac = excluded.nguoi_thao_tac,
    version = cd_tram_hien_tai.version + 1, last_updated_by = v_user, last_updated_at = now();

  -- T395: máy cuối dây chuyền → tự mở các máy giữa cùng mã (máy đã mở đúng mã giữ nguyên)
  v_dc := gc_dc_cua_may(m.ma_may, p.ma_sp);
  if v_dc.id is not null and v_dc.ds_may[cardinality(v_dc.ds_may)] = m.ma_may then
    foreach v_mk in array v_dc.ds_may[1:cardinality(v_dc.ds_may) - 1] loop
      if not exists (select 1 from cd_tram_hien_tai where cong_doan = 'Gia Công' and ngay = p_ngay and ca = p_ca and ten_tram = v_mk and ma_sp = p.ma_sp) then
        v_r := gc_may_luu(p_ngay, p_ca, v_mk, p.ma_sp, 0, p_nguoi);
        if not coalesce((v_r->>'ok')::boolean, false) then v_cb := v_cb || (v_r->>'error'); end if;
      end if;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'id_tram', v_id, 'day_chuyen', v_dc.ten, 'canh_bao', to_jsonb(v_cb));
end $function$;

create or replace function public.gc_xong(p_id_tram text, p_id_buoc bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_chk jsonb;
  v_tram cd_tram_hien_tai%rowtype;
  b gc_tem_buoc%rowtype;
  v_sl numeric;
  v_user text := duc_su_co_nguoi_hien_tai();
  v_n int; v_k int; v_mk text; v_t cd_tram_hien_tai%rowtype; v_ng numeric[]; v_sau numeric; v_cid bigint; v_tong_ng numeric; -- T395
begin
  v_chk := gc_kiem_buoc(p_id_tram, p_id_buoc);
  if not (v_chk->>'ok')::boolean then return v_chk; end if;
  select * into v_tram from cd_tram_hien_tai where id_tram = p_id_tram for update;
  if coalesce(v_tram.nguoi_thao_tac, '') = '' then
    return jsonb_build_object('ok', false, 'error', v_tram.ten_tram || ' chưa gán người đứng máy. Bấm "Sửa máy" để chọn.');
  end if;
  if exists (select 1 from gc_hang_test where id_buoc = p_id_buoc and ket_thuc_luc is null) then
    return jsonb_build_object('ok', false, 'error', 'Thùng còn hàng test chưa kết thúc. Kết thúc test (nhập số trả lại) trước khi bấm Xong.');
  end if;
  select * into b from gc_tem_buoc where id = p_id_buoc for update;
  select coalesce(so_luong, 0) into v_sl from duc_tem where tag_no = b.tag_no for update;
  v_sl := v_sl + coalesce(b.sl_dong, 0); -- T343
  update gc_tem_buoc set xong_luc = now(), sl_ra = v_sl, id_tram_xong = p_id_tram, nguoi_xong = v_user,
    nguoi_lam = v_tram.nguoi_thao_tac
  where id = p_id_buoc;

  -- T395: dây chuyền → ghi "đã xong" cho từng máy giữa
  if b.dc_may is not null and cardinality(b.dc_may) > 1 then
    v_n := cardinality(b.dc_may);
    v_ng := array_fill(0::numeric, array[v_n]);
    select coalesce(sum(g.so_luong), 0) into v_tong_ng from cd_ng_khai_bao g where g.id_buoc = b.id;
    for v_k in 1..v_n - 1 loop
      select coalesce(sum(g.so_luong), 0) into v_sau
      from cd_ng_khai_bao g join cd_tram_hien_tai t on t.id_tram = g.id_tram
      where g.id_buoc = b.id and t.ten_tram = b.dc_may[v_k];
      v_ng[v_k] := v_sau;
    end loop;
    v_ng[v_n] := v_tong_ng - (select coalesce(sum(x), 0) from unnest(v_ng[1:v_n - 1]) x);
    for v_k in 1..v_n - 1 loop
      v_mk := b.dc_may[v_k];
      select * into v_t from cd_tram_hien_tai where cong_doan = 'Gia Công' and ngay = v_tram.ngay and ca = v_tram.ca and ten_tram = v_mk;
      if not found then
        perform gc_may_luu(v_tram.ngay, v_tram.ca, v_mk, b.ma_sp, 0, v_tram.nguoi_thao_tac);
        select * into v_t from cd_tram_hien_tai where cong_doan = 'Gia Công' and ngay = v_tram.ngay and ca = v_tram.ca and ten_tram = v_mk;
      end if;
      select coalesce(sum(x), 0) into v_sau from unnest(v_ng[v_k + 1:v_n]) x;
      insert into gc_tem_buoc (tag_no, ma_sp, ma_may, loai_may, buoc, tong_buoc, id_tram, id_tram_xong, sl_vao, sl_ra,
        bat_dau, xong_luc, nguoi_quet, nguoi_xong, nguoi_lam, dc_ten, dc_chinh)
      values (b.tag_no, b.ma_sp, v_mk, gc_loai_may(v_mk), b.buoc - (v_n - v_k), b.tong_buoc, coalesce(v_t.id_tram, b.id_tram), v_t.id_tram,
        v_sl + v_sau + v_ng[v_k], v_sl + v_sau, b.bat_dau, now(), b.nguoi_quet, v_user, coalesce(nullif(v_t.nguoi_thao_tac, ''), v_tram.nguoi_thao_tac),
        b.dc_ten, b.id)
      returning id into v_cid;
      update cd_ng_khai_bao g set id_buoc = v_cid
      from cd_tram_hien_tai t where t.id_tram = g.id_tram and g.id_buoc = b.id and t.ten_tram = v_mk;
    end loop;
  end if;

  if b.buoc >= b.tong_buoc and v_sl > 0 then
    perform cd_tram_nhap_sanluong(p_id_tram, v_sl, 0, null, v_user);
  end if;
  return jsonb_build_object('ok', true, 'tag_no', b.tag_no, 'sl_ra', v_sl, 'buoc', b.buoc, 'tong_buoc', b.tong_buoc,
    'buoc_cuoi', b.buoc >= b.tong_buoc,
    'chia_xe', false, 'sl_dong', coalesce(b.sl_dong, 0), 'con', v_sl - coalesce(b.sl_dong, 0), 'day_chuyen', b.dc_ten); -- T343 / T395
end $function$;

create or replace function public.gc_xong_huy(p_id_buoc bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  b gc_tem_buoc%rowtype;
  v_tram cd_tram_hien_tai%rowtype;
  v_user text := duc_su_co_nguoi_hien_tai();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into b from gc_tem_buoc where id = p_id_buoc for update;
  if not found or b.bo_luc is not null or b.xong_luc is null then
    return jsonb_build_object('ok', false, 'error', 'Thùng này chưa bấm Xong');
  end if;
  if b.dc_chinh is not null then -- T395
    return jsonb_build_object('ok', false, 'error', 'Thùng ' || b.tag_no || ' chạy theo dây chuyền ' || coalesce(b.dc_ten, '') || ' — Huỷ xong ở máy cuối '
      || coalesce((select ma_may from gc_tem_buoc where id = b.dc_chinh), '?'));
  end if;
  if exists (select 1 from gc_tem_buoc where tag_no = b.tag_no and bo_luc is null and id <> b.id and bat_dau > b.bat_dau) then
    return jsonb_build_object('ok', false, 'error', 'Thùng ' || b.tag_no || ' đã sang bước sau, không huỷ Xong được');
  end if;
  if exists (select 1 from gc_tem_buoc where tag_no = b.tag_no and xong_luc is null and bo_luc is null) then
    return jsonb_build_object('ok', false, 'error', 'Thùng ' || b.tag_no || ' đang làm ở máy khác');
  end if;
  if exists (select 1 from cd_chuyen_cong_doan_log where ghi_chu = 'T338 Chia xe ' || b.tag_no) or coalesce(b.sl_dong, 0) > 0
     or (b.buoc >= b.tong_buoc and exists (select 1 from cd_tem_nguon n where n.tag_no_nguon = b.tag_no and n.tag_no_moi ~ '^(TP|GC)')) then -- T340/T343
    return jsonb_build_object('ok', false, 'error', 'Xe ' || b.tag_no || ' đã chia thùng, không huỷ Xong được');
  end if;
  select * into v_tram from cd_tram_hien_tai where id_tram = b.id_tram_xong for update;
  if found and gc_ca_da_ket(v_tram.ngay, v_tram.ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca bấm Xong đã kết ca, không huỷ được');
  end if;
  if b.buoc >= b.tong_buoc and coalesce(b.sl_ra, 0) > 0 and v_tram.id_tram is not null then
    update cd_tram_hien_tai set so_luong_ok = greatest(0, so_luong_ok - b.sl_ra), version = version + 1,
      last_updated_by = v_user, last_updated_at = now()
    where id_tram = v_tram.id_tram;
  end if;
  -- T395: bỏ dòng máy giữa dây chuyền, NG trả về dòng chính
  update cd_ng_khai_bao set id_buoc = b.id where id_buoc in (select id from gc_tem_buoc where dc_chinh = b.id);
  delete from gc_tem_buoc where dc_chinh = b.id;
  update gc_tem_buoc set xong_luc = null, sl_ra = null, id_tram_xong = null, nguoi_xong = null, nguoi_lam = null
  where id = b.id;
  return jsonb_build_object('ok', true);
end $function$;

create or replace function public.gc_ng_nhieu(p_id_tram text, p_id_buoc bigint, p_ds jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_chk jsonb;
  b gc_tem_buoc%rowtype;
  v_tem duc_tem%rowtype;
  r jsonb;
  n int := 0;
  v_sl numeric;
  v_tong numeric := 0;
  v_user text := duc_su_co_nguoi_hien_tai();
  v_tram cd_tram_hien_tai%rowtype; v_may text; v_tr text; -- T395
begin
  v_chk := gc_kiem_buoc(p_id_tram, p_id_buoc);
  if not (v_chk->>'ok')::boolean then return v_chk; end if;
  if jsonb_typeof(p_ds) <> 'array' or jsonb_array_length(p_ds) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Nhập ít nhất 1 dòng NG');
  end if;
  select * into b from gc_tem_buoc where id = p_id_buoc;
  select * into v_tram from cd_tram_hien_tai where id_tram = p_id_tram;
  select * into v_tem from duc_tem where tag_no = b.tag_no for update;
  for r in select * from jsonb_array_elements(p_ds) loop
    n := n + 1;
    if coalesce(trim(r->>'loai'), '') = '' then
      return jsonb_build_object('ok', false, 'error', 'Dòng ' || n || ': chọn tên lỗi NG');
    end if;
    if trim(r->>'loai') in ('Khác', 'Z99 Khác') and length(trim(coalesce(r->>'ghi_chu', ''))) < 3 then
      return jsonb_build_object('ok', false, 'error', 'Dòng ' || n || ': lỗi "Khác" phải ghi rõ nguyên nhân');
    end if;
    if coalesce(r->>'so_luong', '') !~ '^\d+$' or (r->>'so_luong')::numeric <= 0 then
      return jsonb_build_object('ok', false, 'error', 'Dòng ' || n || ': số lượng NG phải là số nguyên lớn hơn 0');
    end if;
    v_may := nullif(trim(coalesce(r->>'may', '')), '');
    if v_may is not null and v_may <> v_tram.ten_tram and not (v_may = any(coalesce(b.dc_may, '{}'))) then
      return jsonb_build_object('ok', false, 'error', 'Dòng ' || n || ': máy ' || v_may || ' không thuộc dây chuyền của thùng này');
    end if;
    v_tong := v_tong + (r->>'so_luong')::numeric;
  end loop;
  if v_tong > coalesce(v_tem.so_luong, 0) then
    return jsonb_build_object('ok', false, 'error', 'Tổng NG ' || v_tong || ' vượt số còn trên tem (' || coalesce(v_tem.so_luong, 0) || ' pcs)');
  end if;

  for r in select * from jsonb_array_elements(p_ds) loop
    v_sl := (r->>'so_luong')::numeric;
    v_may := nullif(trim(coalesce(r->>'may', '')), '');
    v_tr := p_id_tram;
    if v_may is not null and v_may <> v_tram.ten_tram then -- T395: NG ở máy giữa dây chuyền → trạm của máy đó
      select coalesce((select id_tram from cd_tram_hien_tai where cong_doan = 'Gia Công' and ngay = v_tram.ngay and ca = v_tram.ca and ten_tram = v_may), p_id_tram) into v_tr;
    end if;
    insert into cd_ng_khai_bao (tag_no, ma_sp, ten_sp, cong_doan, loai_ng, so_luong, nguoi, id_tram, ghi_chu, id_buoc)
    values (v_tem.tag_no, v_tem.ma_sp, v_tem.ten_sp, 'Gia Công', trim(r->>'loai'), v_sl, v_user, v_tr,
      nullif(trim(coalesce(r->>'ghi_chu', '')), ''), p_id_buoc);
    perform cd_tram_nhap_sanluong(v_tr, 0, v_sl, null, v_user);
  end loop;
  update duc_tem set so_luong = so_luong - v_tong where tag_no = v_tem.tag_no;
  return jsonb_build_object('ok', true, 'so_dong', n, 'tong', v_tong, 'so_luong_con_lai', v_tem.so_luong - v_tong);
end $function$;

-- ── t395c: dừng máy theo dây chuyền + dữ liệu bảng điều khiển ──────────────
create or replace function public.gc_su_co_mo(p_id_tram text, p_loai text, p_bo_phan text, p_van_de text, p_gio_phat_sinh timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tram cd_tram_hien_tai%rowtype;
  v_gio timestamptz := coalesce(p_gio_phat_sinh, now());
  v_id bigint;
  v_dc gc_day_chuyen; v_t cd_tram_hien_tai%rowtype; v_mk text; v_kem int := 0; -- T395
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into v_tram from cd_tram_hien_tai where id_tram = p_id_tram and cong_doan = 'Gia Công';
  if not found then return jsonb_build_object('ok', false, 'error', 'Máy chưa được mở trong ca này'); end if;
  if gc_ca_da_ket(v_tram.ngay, v_tram.ca) then return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca'); end if;
  if coalesce(trim(p_loai), '') = '' then return jsonb_build_object('ok', false, 'error', 'Chọn lý do dừng'); end if;
  if length(trim(coalesce(p_van_de, ''))) < 3 then return jsonb_build_object('ok', false, 'error', 'Ghi rõ vấn đề (ít nhất 3 ký tự)'); end if;
  if v_gio > now() + interval '5 minutes' then return jsonb_build_object('ok', false, 'error', 'Giờ phát sinh không được ở tương lai'); end if;
  if v_gio < now() - interval '24 hours' then return jsonb_build_object('ok', false, 'error', 'Giờ phát sinh quá 24 giờ trước'); end if;
  if exists (select 1 from gc_su_co where ma_may = v_tram.ten_tram and gio_tro_lai is null and huy_luc is null) then
    return jsonb_build_object('ok', false, 'error', v_tram.ten_tram || ' đang có 1 lần dừng chưa đóng');
  end if;
  insert into gc_su_co (ma_may, id_tram, ngay, ca, ma_sp, loai_su_co, bo_phan_xu_ly, gio_phat_sinh, van_de, nguoi_bao)
  values (v_tram.ten_tram, v_tram.id_tram, v_tram.ngay, v_tram.ca, v_tram.ma_sp, trim(p_loai),
    nullif(trim(coalesce(p_bo_phan, '')), ''), v_gio, trim(p_van_de), duc_su_co_nguoi_hien_tai())
  returning id into v_id;

  -- T395: cả dây chuyền dừng theo
  v_dc := gc_dc_cua_may(v_tram.ten_tram, v_tram.ma_sp);
  if v_dc.id is not null then
    foreach v_mk in array v_dc.ds_may loop
      continue when v_mk = v_tram.ten_tram;
      select * into v_t from cd_tram_hien_tai where cong_doan = 'Gia Công' and ngay = v_tram.ngay and ca = v_tram.ca and ten_tram = v_mk;
      continue when not found;
      continue when v_t.ma_sp is distinct from v_tram.ma_sp;
      continue when exists (select 1 from gc_su_co where ma_may = v_mk and gio_tro_lai is null and huy_luc is null);
      insert into gc_su_co (ma_may, id_tram, ngay, ca, ma_sp, loai_su_co, bo_phan_xu_ly, gio_phat_sinh, van_de, nguoi_bao, dc_goc)
      values (v_mk, v_t.id_tram, v_t.ngay, v_t.ca, v_t.ma_sp, trim(p_loai), nullif(trim(coalesce(p_bo_phan, '')), ''), v_gio,
        'Dây chuyền ' || v_dc.ten || ' dừng do ' || v_tram.ten_tram || ': ' || trim(p_van_de), duc_su_co_nguoi_hien_tai(), v_id);
      v_kem := v_kem + 1;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'so_may_kem', v_kem, 'day_chuyen', v_dc.ten);
end $function$;

create or replace function public.gc_su_co_dong(p_id bigint, p_gio_tro_lai timestamp with time zone, p_noi_dung text, p_dam_nhiem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v gc_su_co%rowtype;
  v_gio timestamptz := coalesce(p_gio_tro_lai, now());
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into v from gc_su_co where id = p_id for update;
  if not found or v.huy_luc is not null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy lần dừng'); end if;
  if v.gio_tro_lai is not null then return jsonb_build_object('ok', false, 'error', 'Lần dừng này đã đóng'); end if;
  if v.dc_goc is not null then -- T395
    return jsonb_build_object('ok', false, 'error', 'Lần dừng theo dây chuyền — bấm "Máy chạy lại" ở máy '
      || coalesce((select ma_may from gc_su_co where id = v.dc_goc), '?'));
  end if;
  if length(trim(coalesce(p_noi_dung, ''))) < 3 then return jsonb_build_object('ok', false, 'error', 'Ghi nội dung xử lý (ít nhất 3 ký tự)'); end if;
  if coalesce(trim(p_dam_nhiem), '') = '' then return jsonb_build_object('ok', false, 'error', 'Chọn / ghi người xử lý'); end if;
  if v_gio < v.gio_phat_sinh then return jsonb_build_object('ok', false, 'error', 'Giờ chạy lại phải sau giờ dừng'); end if;
  if v_gio > now() + interval '5 minutes' then return jsonb_build_object('ok', false, 'error', 'Giờ chạy lại không được ở tương lai'); end if;
  update gc_su_co set gio_tro_lai = v_gio, phut_dung = round(extract(epoch from (v_gio - v.gio_phat_sinh)) / 60),
    noi_dung_xu_ly = trim(p_noi_dung), dam_nhiem = trim(p_dam_nhiem), nguoi_dong = duc_su_co_nguoi_hien_tai()
  where id = p_id;
  update gc_su_co set gio_tro_lai = greatest(v_gio, gio_phat_sinh), phut_dung = round(extract(epoch from (greatest(v_gio, gio_phat_sinh) - gio_phat_sinh)) / 60),
    noi_dung_xu_ly = trim(p_noi_dung), dam_nhiem = trim(p_dam_nhiem), nguoi_dong = duc_su_co_nguoi_hien_tai()
  where dc_goc = p_id and gio_tro_lai is null and huy_luc is null; -- T395
  return jsonb_build_object('ok', true, 'phut_dung', round(extract(epoch from (v_gio - v.gio_phat_sinh)) / 60));
end $function$;

create or replace function public.gc_su_co_huy(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_goc bigint;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select dc_goc into v_goc from gc_su_co where id = p_id;
  if v_goc is not null then -- T395
    return jsonb_build_object('ok', false, 'error', 'Lần dừng theo dây chuyền — huỷ ở máy ' || coalesce((select ma_may from gc_su_co where id = v_goc), '?'));
  end if;
  update gc_su_co set huy_luc = now(), huy_boi = duc_su_co_nguoi_hien_tai()
  where id = p_id and huy_luc is null and gio_tro_lai is null;
  if not found then return jsonb_build_object('ok', false, 'error', 'Chỉ huỷ được lần dừng đang mở (báo nhầm)'); end if;
  update gc_su_co set huy_luc = now(), huy_boi = duc_su_co_nguoi_hien_tai()
  where dc_goc = p_id and huy_luc is null and gio_tro_lai is null; -- T395
  return jsonb_build_object('ok', true);
end $function$;

-- gc_du_lieu: thêm danh sách dây chuyền + thông tin dây chuyền của dòng thùng
do $$
declare d text;
begin
  d := pg_get_functiondef('public.gc_du_lieu(date,text)'::regprocedure);
  if position('''day_chuyen''' in d) = 0 then
    d := replace(d, $x$'khung_ca', (select jsonb_build_object('tu', tu, 'den', den) from kc),$x$,
      $x$'khung_ca', (select jsonb_build_object('tu', tu, 'den', den) from kc),
    'day_chuyen', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ten', c.ten, 'ds_may', c.ds_may, 'ds_ma_sp', c.ds_ma_sp, 'bat', c.bat) order by c.ten), '[]'::jsonb) from gc_day_chuyen c), -- T395$x$);
    d := replace(d, $x$'sl_vao', b.sl_vao, 'con', d.so_luong,$x$, $x$'sl_vao', b.sl_vao, 'con', d.so_luong, 'dc_ten', b.dc_ten, 'dc_may', b.dc_may,$x$);
    d := replace(d, $x$'xong_luc', b.xong_luc, 'nguoi_lam', b.nguoi_lam,$x$, $x$'xong_luc', b.xong_luc, 'nguoi_lam', b.nguoi_lam, 'dc_ten', b.dc_ten, 'dc_chinh', b.dc_chinh,$x$);
    if position('''day_chuyen''' in d) = 0 or position('''dc_may''' in d) = 0 or position('''dc_chinh''' in d) = 0 then
      raise exception 'T395: không vá được gc_du_lieu';
    end if;
    execute d;
  end if;
end $$;
