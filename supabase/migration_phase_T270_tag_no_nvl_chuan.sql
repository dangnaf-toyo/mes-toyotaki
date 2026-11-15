-- ============================================================================
-- T270 (15/11/2026): Tag No tem NVL theo chuẩn chung của hệ thống
--   Chuẩn chung: <TIỀN TỐ><YYYYMMDD>-<NNNN>  (TKD, D-TKD, TP, PK, TKB … đều vậy)
--   NVL cũ "TYK-20260713-0002" lệch chuẩn (có gạch sau tiền tố, tiền tố tên công ty)
--   → tem mới: "NVL20261115-0001". YYYYMMDD = ngày nhập kho trên tem.
--   Số thứ tự lấy từ bộ đếm chung duc_tag_no_counter (khoá "NVL20261115"),
--   cộng 1 lần cho cả lô → 2 người in cùng lúc không trùng số.
--   QR trên tem chỉ chứa Tag No (qrContent = tag_no); màn quét tra DB theo Tag No.
--   Tem cũ TYK-… giữ nguyên (đã dán trên pallet), vẫn quét được.
-- ============================================================================

create or replace function public.nvl_create_tem(p_ma_nvl text, p_ten_nvl text, p_ngay_nhap date, p_don_vi text, p_ghi_chu text, p_so_luong_list jsonb, p_user text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_ten text;
  v_max_seq int;
  v_prefix text;
  v_tag_no text;
  v_item jsonb;
  v_so_luong numeric;
  v_ton_hien_tai numeric;
  v_ton_sau numeric;
  v_tems jsonb := '[]'::jsonb;
  v_now timestamptz := now();
  v_n int;
begin
  if auth.uid() is not null and not public.has_role(VARIADIC ARRAY['admin', 'kho_nvl', 'ke_hoach', 'qlsx_nhan_vien', 'qlsx_truong_phong']) then
    raise exception '⛔ Tài khoản không có quyền thực hiện thao tác này — cần vai trò: %', 'Kho NVL / Kế hoạch / QLSX' using errcode = '42501';
  end if;   -- T212
  p_user := public.duc_ten_nguoi_hien_tai(p_user);   -- T212: tên theo tài khoản
  if p_don_vi not in ('kg', 'pcs') then return jsonb_build_object('ok', false, 'error', 'Đơn vị phải là kg hoặc pcs'); end if;
  select ten_nvl into v_ten from nvl_materials where ma_nvl = p_ma_nvl;
  if not found then return jsonb_build_object('ok', false, 'error', 'Mã NVL không tồn tại trong danh mục: ' || p_ma_nvl); end if;
  v_ten := coalesce(nullif(trim(coalesce(p_ten_nvl, '')), ''), v_ten, p_ma_nvl);

  if p_so_luong_list is null or jsonb_array_length(p_so_luong_list) < 1 or jsonb_array_length(p_so_luong_list) > 100 then
    return jsonb_build_object('ok', false, 'error', 'Số tem phải từ 1-100');
  end if;
  if exists (select 1 from jsonb_array_elements(p_so_luong_list) v where (v.value::numeric) <= 0) then
    return jsonb_build_object('ok', false, 'error', 'Tất cả số lượng phải > 0');
  end if;

  -- T270: tiền tố chuẩn + bộ đếm chung (giữ khoá dòng tới hết giao dịch)
  v_n := jsonb_array_length(p_so_luong_list);
  v_prefix := 'NVL' || to_char(p_ngay_nhap, 'YYYYMMDD');
  insert into duc_tag_no_counter (prefix_ngay, last_seq) values (v_prefix, v_n)
  on conflict (prefix_ngay) do update set last_seq = duc_tag_no_counter.last_seq + v_n
  returning last_seq - v_n into v_max_seq;
  if v_max_seq + v_n > 9999 then
    raise exception 'Quá 9999 tem NVL trong ngày %', p_ngay_nhap;
  end if;

  perform 1 from nvl_ton_dau_ky where ma_nvl = p_ma_nvl for update;
  select coalesce(o.ton_dau_ky_kg, 0)
    + coalesce(sum(case when g.loai = 'IN' then g.so_luong_kg when g.loai = 'OUT' then -g.so_luong_kg else 0 end), 0)
  into v_ton_hien_tai
  from nvl_ton_dau_ky o
  left join nvl_giao_dich g on g.ma_nvl = o.ma_nvl and (o.ngay_dau_ky is null or g.ngay >= o.ngay_dau_ky)
  where o.ma_nvl = p_ma_nvl
  group by o.ton_dau_ky_kg;
  v_ton_hien_tai := coalesce(v_ton_hien_tai, 0);
  v_ton_sau := v_ton_hien_tai;

  for v_item in select * from jsonb_array_elements(p_so_luong_list)
  loop
    v_max_seq := v_max_seq + 1;
    v_so_luong := v_item::numeric;
    v_tag_no := v_prefix || '-' || lpad(v_max_seq::text, 4, '0');

    insert into nvl_tem (tag_no, ma_nvl, ten_nvl, ngay_nhap, so_luong, don_vi, ghi_chu, ts_goc, trang_thai)
    values (v_tag_no, p_ma_nvl, v_ten, p_ngay_nhap, v_so_luong, p_don_vi, coalesce(p_ghi_chu, ''), v_now, 'Đã nhập kho');

    -- pcs: không quy đổi/không cộng vào tồn kg, giữ nguyên hành vi bản gốc.
    v_ton_sau := v_ton_sau + (case when p_don_vi = 'kg' then v_so_luong else 0 end);

    insert into nvl_giao_dich (ngay, loai, ma_nvl, so_luong_kg, ghi_chu, ton_sau_kg, ts_goc)
    values (p_ngay_nhap, 'IN', p_ma_nvl, case when p_don_vi = 'kg' then v_so_luong else 0 end,
      '[Tem ' || v_tag_no || '] ' || coalesce(nullif(p_ghi_chu, ''), 'Nhập kho từ in tem'),
      v_ton_sau, v_now);

    v_tems := v_tems || jsonb_build_object(
      'tagNo', v_tag_no, 'material', p_ma_nvl, 'tenNVL', v_ten, 'ngayNhap', p_ngay_nhap,
      'soLuong', v_so_luong, 'donVi', p_don_vi, 'ghiChu', coalesce(p_ghi_chu, ''),
      'qrContent', v_tag_no   -- T270: QR chỉ chứa Tag No
    );
  end loop;

  return jsonb_build_object('ok', true, 'tems', v_tems, 'count', v_n);
end;
$function$;

revoke execute on function public.nvl_create_tem(text, text, date, text, text, jsonb, text) from public, anon;
grant execute on function public.nvl_create_tem(text, text, date, text, text, jsonb, text) to authenticated;
