-- T353 phần 1: mã trên tem NCC + nguồn tem
alter table public.nvl_materials add column if not exists ma_tem_ncc text;
create unique index if not exists nvl_materials_ma_tem_ncc_uq on public.nvl_materials (upper(trim(ma_tem_ncc)))
  where ma_tem_ncc is not null and trim(ma_tem_ncc) <> '';
alter table public.nvl_tem add column if not exists nguon text not null default 'noi_bo';
alter table public.nvl_tem add column if not exists lot_ncc text;

create or replace function public.nvl_set_ma_tem_ncc(p_ma_nvl text, p_ma_tem_ncc text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_ma text := nullif(upper(trim(coalesce(p_ma_tem_ncc, ''))), ''); v_trung text;
begin
  if not public.has_role(VARIADIC ARRAY['admin', 'kho_nvl', 'ke_hoach', 'qlsx_nhan_vien', 'qlsx_truong_phong']) then
    raise exception '⛔ Tài khoản không có quyền — cần vai trò: Kho NVL / Kế hoạch / QLSX' using errcode = '42501';
  end if;
  if not exists (select 1 from nvl_materials where ma_nvl = p_ma_nvl) then
    return jsonb_build_object('ok', false, 'error', 'Không có mã NVL ' || coalesce(p_ma_nvl, ''));
  end if;
  if v_ma is not null then
    select ma_nvl into v_trung from nvl_materials where upper(trim(ma_tem_ncc)) = v_ma and ma_nvl <> p_ma_nvl limit 1;
    if found then return jsonb_build_object('ok', false, 'error', 'Mã tem NCC ' || v_ma || ' đã gán cho ' || v_trung); end if;
  end if;
  update nvl_materials set ma_tem_ncc = v_ma where ma_nvl = p_ma_nvl;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.nvl_set_ma_tem_ncc(text, text) from public, anon;
grant execute on function public.nvl_set_ma_tem_ncc(text, text) to authenticated;

update public.nvl_materials set ma_tem_ncc = '008-D39-121-2' where ma_nvl = 'C-PIN-39-001';
update public.nvl_materials set ma_tem_ncc = '008-D19-114A-V' where ma_nvl = 'C-BAC-19-001';
-- T353 phần 2: nhập kho bằng tem NCC (QR Astemo) — lần quét NHẬP đầu tiên tự tạo nvl_tem với tag_no = mã thùng NCC
CREATE OR REPLACE FUNCTION public.nvl_process_multi_transaction(p_loai text, p_items jsonb, p_user text, p_bo_phan text DEFAULT NULL::text, p_phieu_cap bigint DEFAULT NULL::bigint)
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
  v_part text;
  v_m record;
  v_sl numeric;
  v_dv text;
  v_lot text;
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
  if p_phieu_cap is not null then
    if p_loai <> 'OUT' then return jsonb_build_object('ok', false, 'error', 'Phiếu đề nghị chỉ dùng khi xuất kho'); end if;
    if not exists (select 1 from nvl_phieu_cap where id = p_phieu_cap and trang_thai = 'da_xac_nhan' and kho_luc is null) then
      return jsonb_build_object('ok', false, 'error', 'Phiếu đề nghị chưa được QL bộ phận xác nhận hoặc kho đã đóng phiếu');
    end if;
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Chưa có pallet nào để ghi nhận');
  end if;

  -- T353: tem NCC (QR nhà cung cấp) — NHẬP lần đầu tự tạo tem, tag_no = mã thùng NCC (T + số)
  if p_loai = 'IN' then
    for v_item in select * from jsonb_array_elements(p_items)
    loop
      v_tag_no := upper(trim(coalesce(v_item->>'tagNo', '')));
      if jsonb_typeof(v_item->'ncc') is distinct from 'object' or v_tag_no = '' then continue; end if;
      if exists (select 1 from nvl_tem where tag_no = v_tag_no) then continue; end if;
      if v_tag_no !~ '^T[0-9]{6,}$' then
        v_errors := v_errors || to_jsonb('Mã thùng NCC không hợp lệ: ' || v_tag_no); continue;
      end if;
      v_part := upper(trim(coalesce(v_item->'ncc'->>'partNo', '')));
      select ma_nvl, ten_nvl into v_m from nvl_materials
        where ma_tem_ncc is not null and upper(trim(ma_tem_ncc)) = v_part limit 1;
      if not found then
        v_errors := v_errors || to_jsonb('Tem ' || v_tag_no || ': mã NCC ' || v_part || ' chưa khai ở Danh mục (cột Mã tem NCC)'); continue;
      end if;
      v_sl := case when coalesce(v_item->'ncc'->>'soLuong', '') ~ '^[0-9]+(\.[0-9]+)?$' then (v_item->'ncc'->>'soLuong')::numeric end;
      if v_sl is null or v_sl <= 0 then
        v_errors := v_errors || to_jsonb('Tem ' || v_tag_no || ': số lượng không hợp lệ'); continue;
      end if;
      v_dv := lower(trim(coalesce(v_item->'ncc'->>'donVi', '')));
      if v_dv not in ('kg', 'pcs') then v_dv := 'pcs'; end if;
      v_lot := nullif(left(trim(coalesce(v_item->'ncc'->>'lot', '')), 40), '');
      insert into nvl_tem (tag_no, ma_nvl, ten_nvl, ngay_nhap, so_luong, don_vi, ghi_chu, ts_goc, trang_thai, nguon, lot_ncc)
      values (v_tag_no, v_m.ma_nvl, coalesce(v_m.ten_nvl, v_m.ma_nvl), v_today, v_sl, v_dv,
              'Tem NCC ' || v_part || coalesce(' · Lot ' || v_lot, ''), v_now, 'Chờ nhập kho', 'ncc', v_lot);
    end loop;
  end if;

  select array_agg(x order by x) into v_materials
  from (select distinct t.ma_nvl as x from jsonb_array_elements(p_items) i join nvl_tem t on t.tag_no = upper(trim(i->>'tagNo'))) s;
  if v_materials is not null then
    foreach v_mat in array v_materials loop
      perform 1 from nvl_ton_dau_ky where ma_nvl = v_mat for update;
    end loop;
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_tag_no := upper(trim(coalesce(v_item->>'tagNo', '')));
    if v_tag_no = '' then continue; end if;

    select * into v_tem from nvl_tem where tag_no = v_tag_no;
    if not found then
      if not (jsonb_typeof(v_item->'ncc') is not distinct from 'object' and p_loai = 'IN') then   -- lỗi tem NCC đã báo ở trên
        v_errors := v_errors || to_jsonb('Không tìm thấy tem: ' || v_tag_no
          || case when jsonb_typeof(v_item->'ncc') is not distinct from 'object' then ' (tem NCC chưa nhập kho)' else '' end);
      end if;
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

    if p_phieu_cap is not null and not exists (select 1 from nvl_phieu_cap_dong where phieu_id = p_phieu_cap and ma_nvl = v_tem.ma_nvl) then
      v_errors := v_errors || to_jsonb('Tem ' || v_tag_no || ': mã ' || v_tem.ma_nvl || ' không có trong phiếu đề nghị');
      continue;
    end if;
    v_new_status := case when p_loai = 'IN' then 'Đã nhập kho' else 'Đã xuất kho' end;
    update nvl_tem set trang_thai = v_new_status where tag_no = v_tag_no;

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

    insert into nvl_giao_dich (ngay, loai, ma_nvl, so_luong_kg, ghi_chu, ton_sau_kg, ts_goc, bo_phan_nhan, phieu_cap_id)
    values (v_today, p_loai, v_tem.ma_nvl, v_delta_kg,
      '[Tem ' || v_tem.tag_no || '] ' || coalesce(nullif(v_item->>'ghiChu', ''), nullif(v_tem.ghi_chu, ''), ''),
      v_ton_sau, v_now, p_bo_phan, p_phieu_cap);

    v_ok_list := v_ok_list || jsonb_build_object('tagNo', v_tem.tag_no, 'material', v_tem.ma_nvl);
  end loop;

  if jsonb_array_length(v_ok_list) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Không xử lý được pallet nào', 'errors', v_errors);
  end if;

  return jsonb_build_object('ok', true, 'processedCount', jsonb_array_length(v_ok_list), 'processed', v_ok_list,
    'errors', case when jsonb_array_length(v_errors) > 0 then v_errors else null end);
end;
$function$;
