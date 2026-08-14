-- ============================================================================
-- Module Tồn kho NVL — bỏ hẳn Google (thay Web App Apps Script "Ton-kho-NVL",
-- code.js). Bổ sung RPC ghi cho schema đã có ở schema_nvl.sql (mới có đọc
-- công khai, chưa có ghi). Chạy trong Supabase SQL Editor. Idempotent.
--
-- QUYẾT ĐỊNH QUAN TRỌNG: nvl_materials (danh mục mã/tên NVL) từ nay là NGUỒN
-- CHÍNH THỨC DUY NHẤT, THAY HẲN việc đọc "KHSX Master" (Google Sheet, cột
-- V:W) mà code.js gốc dùng (getMasterMaterials/checkMasterMaterial). Đúng
-- tinh thần bỏ hẳn Google đã áp dụng cho master_products/master_machines/
-- master_employees ở khối Đúc — nvl_materials được quản lý trực tiếp qua
-- RPC nvl_upsert_material bên dưới (trang tĩnh có màn quản lý danh mục).
-- ============================================================================

-- ── nvl_giao_dich.sheet_row: trước đây chỉ dùng làm khoá import (vị trí dòng
-- vật lý trong sheet cũ) — từ nay ghi trực tiếp cần 1 nguồn sinh số tự động.
-- Tiếp nối đúng từ giá trị lớn nhất đã import, không đụng dữ liệu cũ.
create sequence if not exists nvl_giao_dich_sheet_row_seq;
select setval('nvl_giao_dich_sheet_row_seq', coalesce((select max(sheet_row) from nvl_giao_dich), 0) + 1, false);
alter table nvl_giao_dich alter column sheet_row set default nextval('nvl_giao_dich_sheet_row_seq');

-- ── Quản lý danh mục NVL (thay KHSX Master) ────────────────────────────────
create or replace function nvl_upsert_material(p_ma_nvl text, p_ten_nvl text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
begin
  if p_ma_nvl is null or trim(p_ma_nvl) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu mã NVL');
  end if;
  insert into nvl_materials (ma_nvl, ten_nvl) values (trim(p_ma_nvl), coalesce(trim(p_ten_nvl), trim(p_ma_nvl)))
  on conflict (ma_nvl) do update set ten_nvl = excluded.ten_nvl;
  return jsonb_build_object('ok', true, 'ma_nvl', trim(p_ma_nvl));
end;
$$;
revoke execute on function nvl_upsert_material(text, text, text) from anon;
grant execute on function nvl_upsert_material(text, text, text) to authenticated;

-- ── addTransaction — ghi 1 giao dịch nhập/xuất, tính tồn sau atomic ────────
-- Khoá theo material (select ... for update trên nvl_ton_dau_ky) để 2 giao
-- dịch cùng mã gọi đồng thời không tính sai tồn sau (thay LockService cũ).
create or replace function nvl_add_transaction(
  p_ngay date, p_loai text, p_ma_nvl text, p_so_luong_kg numeric, p_ghi_chu text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_ton_hien_tai numeric;
  v_ton_sau numeric;
begin
  if p_loai not in ('IN', 'OUT') then return jsonb_build_object('ok', false, 'error', 'Loại giao dịch phải là IN hoặc OUT'); end if;
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

  insert into nvl_giao_dich (ngay, loai, ma_nvl, so_luong_kg, ghi_chu, ton_sau_kg, ts_goc)
  values (coalesce(p_ngay, current_date), p_loai, p_ma_nvl, p_so_luong_kg, coalesce(p_ghi_chu, ''), v_ton_sau, now());

  return jsonb_build_object('ok', true, 'ton_sau_kg', v_ton_sau);
end;
$$;
revoke execute on function nvl_add_transaction(date, text, text, numeric, text, text) from anon;
grant execute on function nvl_add_transaction(date, text, text, numeric, text, text) to authenticated;

-- ── updateOpening ───────────────────────────────────────────────────────
create or replace function nvl_update_opening(p_ma_nvl text, p_ngay_dau_ky date, p_ton_dau_ky_kg numeric, p_user text)
returns jsonb
language plpgsql
security definer
as $$
begin
  if not exists (select 1 from nvl_materials where ma_nvl = p_ma_nvl) then
    return jsonb_build_object('ok', false, 'error', 'Mã NVL không hợp lệ: ' || p_ma_nvl);
  end if;
  insert into nvl_ton_dau_ky (ma_nvl, ngay_dau_ky, ton_dau_ky_kg) values (p_ma_nvl, p_ngay_dau_ky, p_ton_dau_ky_kg)
  on conflict (ma_nvl) do update set
    ngay_dau_ky = coalesce(p_ngay_dau_ky, nvl_ton_dau_ky.ngay_dau_ky),
    ton_dau_ky_kg = coalesce(p_ton_dau_ky_kg, nvl_ton_dau_ky.ton_dau_ky_kg);
  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function nvl_update_opening(text, date, numeric, text) from anon;
grant execute on function nvl_update_opening(text, date, numeric, text) to authenticated;

-- ── updateSettings (bề rộng / ngưỡng cảnh báo tồn) ─────────────────────────
create or replace function nvl_update_settings(p_ma_nvl text, p_be_rong_kg numeric, p_user text)
returns jsonb
language plpgsql
security definer
as $$
begin
  if not exists (select 1 from nvl_materials where ma_nvl = p_ma_nvl) then
    return jsonb_build_object('ok', false, 'error', 'Mã NVL không hợp lệ: ' || p_ma_nvl);
  end if;
  insert into nvl_cai_dat (ma_nvl, be_rong_kg) values (p_ma_nvl, coalesce(p_be_rong_kg, 5))
  on conflict (ma_nvl) do update set be_rong_kg = coalesce(p_be_rong_kg, nvl_cai_dat.be_rong_kg);
  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function nvl_update_settings(text, numeric, text) from anon;
grant execute on function nvl_update_settings(text, numeric, text) to authenticated;

-- ── updatePlanNhap — ghi kế hoạch nhập 30 ngày + tính lại tồn dự kiến ──────
-- p_updates: jsonb array [{"ngay":"2026-08-01","nhap_kg":1000,"tieu_hao_kg":800}, ...]
-- ngày đầu tiên (nhỏ nhất) giữ nguyên ton_du_kien_kg đã có làm baseline (đúng
-- convention "ô đầu tiên = tồn đầu kỳ nhập tay" của bản gốc); nếu chưa có
-- dòng nào cho ngày đó thì baseline = 0.
create or replace function nvl_update_plan_nhap(p_ma_nvl text, p_updates jsonb, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_item jsonb;
  v_baseline numeric;
  v_first_ngay date;
  v_running numeric;
  v_row record;
  v_is_first boolean;
  v_ngay date;
  v_nhap numeric;
begin
  if not exists (select 1 from nvl_materials where ma_nvl = p_ma_nvl) then
    return jsonb_build_object('ok', false, 'error', 'Mã NVL không hợp lệ: ' || p_ma_nvl);
  end if;
  if p_updates is null or jsonb_array_length(p_updates) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Thiếu dữ liệu kế hoạch');
  end if;

  select min((elem->>'ngay')::date) into v_first_ngay from jsonb_array_elements(p_updates) elem;
  select ton_du_kien_kg into v_baseline from nvl_ke_hoach_ngay where ma_nvl = p_ma_nvl and ngay = v_first_ngay;
  v_baseline := coalesce(v_baseline, 0);

  -- Upsert nhap_kg (+ tieu_hao_kg nếu có gửi kèm) cho từng ngày
  for v_item in select * from jsonb_array_elements(p_updates) order by (value->>'ngay')::date
  loop
    v_ngay := (v_item->>'ngay')::date;
    v_nhap := coalesce((v_item->>'nhap_kg')::numeric, 0);
    insert into nvl_ke_hoach_ngay (ma_nvl, ngay, nhap_kg, tieu_hao_kg, ton_du_kien_kg)
    values (p_ma_nvl, v_ngay, v_nhap, 0, 0)
    on conflict (ma_nvl, ngay) do update set nhap_kg = v_nhap;
    if v_item ? 'tieu_hao_kg' then
      update nvl_ke_hoach_ngay set tieu_hao_kg = coalesce((v_item->>'tieu_hao_kg')::numeric, 0) where ma_nvl = p_ma_nvl and ngay = v_ngay;
    end if;
  end loop;

  -- Tính lại chuỗi tồn dự kiến: ngày đầu = baseline, ngày sau = trước + nhập - tiêu hao
  v_running := v_baseline;
  v_is_first := true;
  for v_row in
    select ngay, coalesce(nhap_kg, 0) as nhap, coalesce(tieu_hao_kg, 0) as tieu_hao from nvl_ke_hoach_ngay
    where ma_nvl = p_ma_nvl and ngay >= v_first_ngay order by ngay
  loop
    if v_is_first then
      v_running := v_baseline;
      v_is_first := false;
    else
      v_running := v_running + v_row.nhap - v_row.tieu_hao;
    end if;
    update nvl_ke_hoach_ngay set ton_du_kien_kg = v_running where ma_nvl = p_ma_nvl and ngay = v_row.ngay;
  end loop;

  return jsonb_build_object('ok', true, 'ton_dau_ky', v_baseline, 'ton_cuoi_ky', v_running);
end;
$$;
revoke execute on function nvl_update_plan_nhap(text, jsonb, text) from anon;
grant execute on function nvl_update_plan_nhap(text, jsonb, text) to authenticated;

-- ── recalcAllPlanStock ─────────────────────────────────────────────────────
create or replace function nvl_recalc_all_plan_stock(p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_ma text;
  v_first_ngay date;
  v_baseline numeric;
  v_running numeric;
  v_is_first boolean;
  v_row record;
  v_results jsonb := '[]'::jsonb;
begin
  for v_ma in select distinct ma_nvl from nvl_ke_hoach_ngay loop
    select min(ngay) into v_first_ngay from nvl_ke_hoach_ngay where ma_nvl = v_ma;
    select ton_du_kien_kg into v_baseline from nvl_ke_hoach_ngay where ma_nvl = v_ma and ngay = v_first_ngay;
    v_baseline := coalesce(v_baseline, 0);
    v_running := v_baseline;
    v_is_first := true;
    for v_row in
      select ngay, coalesce(nhap_kg, 0) as nhap, coalesce(tieu_hao_kg, 0) as tieu_hao from nvl_ke_hoach_ngay where ma_nvl = v_ma order by ngay
    loop
      if v_is_first then v_running := v_baseline; v_is_first := false;
      else v_running := v_running + v_row.nhap - v_row.tieu_hao; end if;
      update nvl_ke_hoach_ngay set ton_du_kien_kg = v_running where ma_nvl = v_ma and ngay = v_row.ngay;
    end loop;
    v_results := v_results || jsonb_build_object('ma_nvl', v_ma, 'ton_dau_ky', v_baseline, 'ton_cuoi_ky', v_running);
  end loop;
  return jsonb_build_object('ok', true, 'results', v_results);
end;
$$;
revoke execute on function nvl_recalc_all_plan_stock(text) from anon;
grant execute on function nvl_recalc_all_plan_stock(text) to authenticated;

-- ── createTem — sinh N tem QR + tự ghi giao dịch nhập kho tương ứng ────────
-- p_so_luong_list: jsonb array số (kg hoặc pcs tuỳ p_don_vi).
create or replace function nvl_create_tem(
  p_ma_nvl text, p_ten_nvl text, p_ngay_nhap date, p_don_vi text, p_ghi_chu text,
  p_so_luong_list jsonb, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
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
begin
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

  v_prefix := 'TYK-' || to_char(p_ngay_nhap, 'YYYYMMDD') || '-';
  select coalesce(max((substring(tag_no from length(v_prefix) + 1))::int), 0) into v_max_seq
  from nvl_tem where tag_no like v_prefix || '%';

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
    v_tag_no := v_prefix || lpad(v_max_seq::text, 4, '0');

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
      'qrContent', v_tag_no || '>' || p_ma_nvl || '>' || v_ten || '>' || p_ngay_nhap || '>' || v_so_luong || '>' || p_don_vi
    );
  end loop;

  return jsonb_build_object('ok', true, 'tems', v_tems, 'count', jsonb_array_length(p_so_luong_list));
end;
$$;
revoke execute on function nvl_create_tem(text, text, date, text, text, jsonb, text) from anon;
grant execute on function nvl_create_tem(text, text, date, text, text, jsonb, text) to authenticated;

-- ── processMultiTransaction — giỏ hàng quét QR (nhiều tem 1 lần) ───────────
-- p_items: jsonb array [{"tagNo":"TYK-...", "ghiChu":"..."}, ...]
create or replace function nvl_process_multi_transaction(p_loai text, p_items jsonb, p_user text)
returns jsonb
language plpgsql
security definer
as $$
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
  if p_loai not in ('IN', 'OUT') then return jsonb_build_object('ok', false, 'error', 'Loại giao dịch phải là IN hoặc OUT'); end if;
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

    insert into nvl_giao_dich (ngay, loai, ma_nvl, so_luong_kg, ghi_chu, ton_sau_kg, ts_goc)
    values (v_today, p_loai, v_tem.ma_nvl, v_delta_kg,
      '[Tem ' || v_tem.tag_no || '] ' || coalesce(nullif(v_item->>'ghiChu', ''), nullif(v_tem.ghi_chu, ''), ''),
      v_ton_sau, v_now);

    v_ok_list := v_ok_list || jsonb_build_object('tagNo', v_tem.tag_no, 'material', v_tem.ma_nvl);
  end loop;

  if jsonb_array_length(v_ok_list) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Không xử lý được pallet nào', 'errors', v_errors);
  end if;

  return jsonb_build_object('ok', true, 'processedCount', jsonb_array_length(v_ok_list), 'processed', v_ok_list,
    'errors', case when jsonb_array_length(v_errors) > 0 then v_errors else null end);
end;
$$;
revoke execute on function nvl_process_multi_transaction(text, jsonb, text) from anon;
grant execute on function nvl_process_multi_transaction(text, jsonb, text) to authenticated;

-- ── checkFIFO — đọc tổng hợp, public (không cần đăng nhập) ─────────────────
create or replace function nvl_check_fifo(p_tag_no text)
returns jsonb
language plpgsql
stable
as $$
declare
  v_target record;
  v_older jsonb;
begin
  select * into v_target from nvl_tem where tag_no = p_tag_no;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem: ' || p_tag_no); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'tagNo', t.tag_no, 'material', t.ma_nvl, 'ngayNhap', t.ngay_nhap, 'soLuong', t.so_luong, 'donVi', t.don_vi
  ) order by t.ngay_nhap asc), '[]'::jsonb)
  into v_older
  from nvl_tem t
  where t.ma_nvl = v_target.ma_nvl and t.trang_thai = 'Đã nhập kho' and t.tag_no <> p_tag_no
    and t.ngay_nhap < v_target.ngay_nhap;

  return jsonb_build_object('ok', true,
    'target', jsonb_build_object('tagNo', v_target.tag_no, 'material', v_target.ma_nvl, 'ngayNhap', v_target.ngay_nhap),
    'olderPallets', v_older, 'olderCount', jsonb_array_length(v_older));
end;
$$;
