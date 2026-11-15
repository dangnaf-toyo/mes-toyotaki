-- T264: Kho NVL — XUẤT kho bắt buộc khai báo bộ phận nhận (danh sách cv_bo_phan).
-- Cột mới nvl_giao_dich.bo_phan_nhan; 2 RPC thêm p_bo_phan (mặc định null, chỉ bắt buộc khi OUT).

alter table public.nvl_giao_dich add column if not exists bo_phan_nhan text;

drop function if exists public.nvl_add_transaction(date, text, text, numeric, text, text);
drop function if exists public.nvl_process_multi_transaction(text, jsonb, text);

CREATE OR REPLACE FUNCTION public.nvl_add_transaction(p_ngay date, p_loai text, p_ma_nvl text, p_so_luong_kg numeric, p_ghi_chu text, p_user text, p_bo_phan text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ton_hien_tai numeric;
  v_ton_sau numeric;
begin
  if auth.uid() is not null and not public.has_role(VARIADIC ARRAY['admin', 'kho_nvl', 'ke_hoach', 'qlsx_nhan_vien', 'qlsx_truong_phong']) then
    raise exception '⛔ Tài khoản không có quyền thực hiện thao tác này — cần vai trò: %', 'Kho NVL / Kế hoạch / QLSX' using errcode = '42501';
  end if;   -- T212
  p_user := public.duc_ten_nguoi_hien_tai(p_user);   -- T212: tên theo tài khoản
  if p_loai not in ('IN', 'OUT') then return jsonb_build_object('ok', false, 'error', 'Loại giao dịch phải là IN hoặc OUT'); end if;
  -- T264: xuất kho phải có bộ phận nhận
  p_bo_phan := nullif(trim(coalesce(p_bo_phan, '')), '');
  if p_loai = 'OUT' then
    if p_bo_phan is null then return jsonb_build_object('ok', false, 'error', 'Chọn bộ phận nhận khi xuất kho'); end if;
    if not exists (select 1 from cv_bo_phan where ten = p_bo_phan) then
      return jsonb_build_object('ok', false, 'error', 'Bộ phận không có trong danh sách: ' || p_bo_phan);
    end if;
  else
    p_bo_phan := null;
  end if;
  if not exists (select 1 from nvl_materials where ma_nvl = p_ma_nvl) then
    return jsonb_build_object('ok', false, 'error', 'Mã NVL không tồn tại trong danh mục: ' || p_ma_nvl);
  end if;
  if p_so_luong_kg is null or p_so_luong_kg <= 0 then return jsonb_build_object('ok', false, 'error', 'Khối lượng phải > 0'); end if;

  perform 1 from nvl_ton_dau_ky where ma_nvl = p_ma_nvl for update;

  select coalesce(o.ton_dau_ky_kg, 0)
    + coalesce(sum(case when g.loai = 'IN' then g.so_luong_kg when g.loai = 'OUT' then -g.so_luong_kg else 0 end), 0)
  into v_ton_hien_tai
  from nvl_ton_dau_ky o
  left join nvl_giao_dich g on g.ma_nvl = o.ma_nvl and (o.ngay_dau_ky is null or g.ngay >= o.ngay_dau_ky)
  where o.ma_nvl = p_ma_nvl
  group by o.ton_dau_ky_kg;

  v_ton_hien_tai := coalesce(v_ton_hien_tai, 0);
  v_ton_sau := greatest(0, v_ton_hien_tai + (case when p_loai = 'IN' then p_so_luong_kg else -p_so_luong_kg end));

  insert into nvl_giao_dich (ngay, loai, ma_nvl, so_luong_kg, ghi_chu, ton_sau_kg, ts_goc, bo_phan_nhan)
  values (coalesce(p_ngay, current_date), p_loai, p_ma_nvl, p_so_luong_kg, coalesce(p_ghi_chu, ''), v_ton_sau, now(), p_bo_phan);

  return jsonb_build_object('ok', true, 'ton_sau_kg', v_ton_sau);
end;
$function$;

CREATE OR REPLACE FUNCTION public.nvl_process_multi_transaction(p_loai text, p_items jsonb, p_user text, p_bo_phan text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item jsonb;
  v_tag_no text;
  v_tem record;
  v_delta_kg numeric;
  v_ton_hien_tai numeric;
  v_ton_sau numeric;
  v_new_status text;
  v_ok_list jsonb := '[]'::jsonb;
  v_errors jsonb := '[]'::jsonb;
  v_now timestamptz := now();
  v_today date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  v_materials text[];
  v_mat text;
begin
  if auth.uid() is not null and not public.has_role(VARIADIC ARRAY['admin', 'kho_nvl', 'ke_hoach', 'qlsx_nhan_vien', 'qlsx_truong_phong']) then
    raise exception '⛔ Tài khoản không có quyền thực hiện thao tác này — cần vai trò: %', 'Kho NVL / Kế hoạch / QLSX' using errcode = '42501';
  end if;   -- T212
  p_user := public.duc_ten_nguoi_hien_tai(p_user);   -- T212: tên theo tài khoản
  if p_loai not in ('IN', 'OUT') then return jsonb_build_object('ok', false, 'error', 'Loại giao dịch phải là IN hoặc OUT'); end if;
  -- T264: xuất kho phải có bộ phận nhận
  p_bo_phan := nullif(trim(coalesce(p_bo_phan, '')), '');
  if p_loai = 'OUT' then
    if p_bo_phan is null then return jsonb_build_object('ok', false, 'error', 'Chọn bộ phận nhận khi xuất kho'); end if;
    if not exists (select 1 from cv_bo_phan where ten = p_bo_phan) then
      return jsonb_build_object('ok', false, 'error', 'Bộ phận không có trong danh sách: ' || p_bo_phan);
    end if;
  else
    p_bo_phan := null;
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Chưa có pallet nào để ghi nhận');
  end if;

  -- Khoá trước theo mã (tránh 2 lần gọi song song tính sai tồn) — khoá mọi mã liên quan,
  -- theo thứ tự cố định (bảng chữ cái) để tránh deadlock giữa 2 lệnh gọi chồng chéo mã.
  select array_agg(x order by x) into v_materials
  from (select distinct t.ma_nvl as x from jsonb_array_elements(p_items) i join nvl_tem t on t.tag_no = i->>'tagNo') s;
  if v_materials is not null then
    foreach v_mat in array v_materials loop
      perform 1 from nvl_ton_dau_ky where ma_nvl = v_mat for update;
    end loop;
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_tag_no := v_item->>'tagNo';
    if v_tag_no is null or v_tag_no = '' then continue; end if;

    select * into v_tem from nvl_tem where tag_no = v_tag_no;
    if not found then
      v_errors := v_errors || to_jsonb('Không tìm thấy tem: ' || v_tag_no);
      continue;
    end if;
    if p_loai = 'OUT' and v_tem.trang_thai <> 'Đã nhập kho' then
      v_errors := v_errors || to_jsonb('Tem ' || v_tag_no || ' không ở trạng thái "Đã nhập kho" (hiện: ' || coalesce(v_tem.trang_thai, '') || ')');
      continue;
    end if;
    if p_loai = 'IN' and v_tem.trang_thai = 'Đã nhập kho' then
      v_errors := v_errors || to_jsonb('Tem ' || v_tag_no || ' đã ở trạng thái "Đã nhập kho" rồi');
      continue;
    end if;

    v_new_status := case when p_loai = 'IN' then 'Đã nhập kho' else 'Đã xuất kho' end;
    update nvl_tem set trang_thai = v_new_status where tag_no = v_tag_no;

    -- Tem tính tồn theo kg — đơn vị "pcs" không có quy đổi hợp lệ nên KHÔNG tính vào
    -- tồn kg (đúng hành vi bản gốc: chỉ giao dịch kg mới cộng/trừ vào Tồn Hiện Tại).
    v_delta_kg := case when v_tem.don_vi = 'kg' then v_tem.so_luong else 0 end;

    select coalesce(o.ton_dau_ky_kg, 0)
      + coalesce(sum(case when g.loai = 'IN' then g.so_luong_kg when g.loai = 'OUT' then -g.so_luong_kg else 0 end), 0)
    into v_ton_hien_tai
    from nvl_ton_dau_ky o
    left join nvl_giao_dich g on g.ma_nvl = o.ma_nvl and (o.ngay_dau_ky is null or g.ngay >= o.ngay_dau_ky)
    where o.ma_nvl = v_tem.ma_nvl
    group by o.ton_dau_ky_kg;
    v_ton_hien_tai := coalesce(v_ton_hien_tai, 0);
    v_ton_sau := greatest(0, v_ton_hien_tai + (case when p_loai = 'IN' then v_delta_kg else -v_delta_kg end));

    insert into nvl_giao_dich (ngay, loai, ma_nvl, so_luong_kg, ghi_chu, ton_sau_kg, ts_goc, bo_phan_nhan)
    values (v_today, p_loai, v_tem.ma_nvl, v_delta_kg,
      '[Tem ' || v_tem.tag_no || '] ' || coalesce(nullif(v_item->>'ghiChu', ''), nullif(v_tem.ghi_chu, ''), ''),
      v_ton_sau, v_now, p_bo_phan);

    v_ok_list := v_ok_list || jsonb_build_object('tagNo', v_tem.tag_no, 'material', v_tem.ma_nvl);
  end loop;

  if jsonb_array_length(v_ok_list) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Không xử lý được pallet nào', 'errors', v_errors);
  end if;

  return jsonb_build_object('ok', true, 'processedCount', jsonb_array_length(v_ok_list), 'processed', v_ok_list,
    'errors', case when jsonb_array_length(v_errors) > 0 then v_errors else null end);
end;
$function$;

revoke execute on function public.nvl_add_transaction(date, text, text, numeric, text, text, text) from public, anon;
revoke execute on function public.nvl_process_multi_transaction(text, jsonb, text, text) from public, anon;
grant execute on function public.nvl_add_transaction(date, text, text, numeric, text, text, text) to authenticated, service_role;
grant execute on function public.nvl_process_multi_transaction(text, jsonb, text, text) to authenticated, service_role;
