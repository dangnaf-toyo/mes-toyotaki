-- T327: ĐK đúc — thông số số ghi được KHOẢNG Min ~ Max đúng như QCP (không quy về tâm ±5% nữa).
-- duc_dk_gia_tri thêm cp_min, cp_max:
--   • Khoảng a ~ b (a < b): chuan = null, cp_min = a, cp_max = b → cho phép đúng [a, b].
--   • Giá trị cố định a (QCP ghi 1 số): chuan = a, cp_min = cp_max = a → phải đúng a.
--   • Chỉ có chuan (không khoảng): như cũ — cho phép Chuẩn ± ngưỡng % danh mục.
-- Sửa hàm: duc_dk_luu, duc_dk_kiem_thieu, duc_dk_lan_moi, duc_dk_xn_thong_so, duc_dk_xac_nhan_luu.

alter table public.duc_dk_gia_tri add column if not exists cp_min numeric;
alter table public.duc_dk_gia_tri add column if not exists cp_max numeric;
alter table public.duc_dk_gia_tri drop constraint if exists duc_dk_gia_tri_cp_check;
alter table public.duc_dk_gia_tri add constraint duc_dk_gia_tri_cp_check
  check ((cp_min is null) = (cp_max is null) and (cp_min is null or cp_min <= cp_max));

-- 1) Lưu phiếu: nhận {"chuan":..,"min":..,"max":..,"ghi_chu":..}
CREATE OR REPLACE FUNCTION public.duc_dk_luu(p_id bigint, p_ma_sp text, p_ma_may text, p_ly_do text, p_ma_nvl text, p_dung_cu jsonb, p_gia_tri jsonb, p_anh text[], p_tep text[])
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  p record; v_id bigint; v_lan int; v_loai text; k text; v jsonb; t record;
  v_chuan numeric; v_chu text; v_gc text; v_min numeric; v_max numeric; v_nvl text := nullif(btrim(coalesce(p_ma_nvl, '')), ''); u record;
begin
  if not duc_dk_la_ky_thuat() then
    raise exception '⛔ Chỉ bộ phận Kỹ thuật (hoặc admin) lập phiếu điều kiện đúc.' using errcode = '42501';
  end if;

  if p_id is null then
    p_ma_sp := upper(btrim(coalesce(p_ma_sp, ''))); p_ma_may := btrim(coalesce(p_ma_may, ''));
    if not exists (select 1 from master_products where ma_sp = p_ma_sp) then raise exception 'Mã SP % không có trong danh mục.', p_ma_sp; end if;
    v_loai := duc_dk_loai_may(p_ma_may);
    if v_loai is null then raise exception 'Máy % không phải máy Đúc nhôm / Đúc kẽm.', p_ma_may; end if;
    perform pg_advisory_xact_lock(hashtext('duc_dk:' || p_ma_sp || '|' || p_ma_may));
    select id, lan, trang_thai into p from duc_dk_phieu
      where ma_sp = p_ma_sp and ma_may = p_ma_may and trang_thai in ('nhap', 'cho_kiem', 'cho_duyet');
    if found then raise exception 'Cặp % · % đang có lần % (%) chưa xong — sửa lần đó.', p_ma_may, p_ma_sp, p.lan, p.trang_thai; end if;
    select coalesce(max(lan), 0) + 1 into v_lan from duc_dk_phieu where ma_sp = p_ma_sp and ma_may = p_ma_may;
    insert into duc_dk_phieu (ma_sp, ma_may, lan, nguoi_lap, lap_luc)
      values (p_ma_sp, p_ma_may, v_lan, auth.uid(), now()) returning id into v_id;
    perform duc_dk_ls(v_id, 'lap');
  else
    select * into p from duc_dk_phieu where id = p_id for update;
    if not found then raise exception 'Không tìm thấy phiếu.'; end if;
    if p.trang_thai <> 'nhap' then raise exception 'Phiếu không còn là nháp — không sửa được.'; end if;
    if (p_ma_sp is not null and upper(btrim(p_ma_sp)) <> p.ma_sp) or (p_ma_may is not null and btrim(p_ma_may) <> p.ma_may) then
      raise exception 'Không đổi Máy / Mã SP của phiếu đã lập — huỷ nháp rồi lập phiếu mới.';
    end if;
    v_id := p_id; v_lan := p.lan; v_loai := duc_dk_loai_may(p.ma_may);
    perform duc_dk_ls(v_id, 'sua');
  end if;

  delete from duc_dk_gia_tri where id_phieu = v_id;
  for k, v in select * from jsonb_each(coalesce(p_gia_tri, '{}')) loop
    select * into t from duc_dk_thong_so where ma_ts = k;
    if not found then raise exception 'Thông số % không có trong danh mục.', k; end if;
    v_chuan := null; v_chu := null; v_gc := null; v_min := null; v_max := null;
    if jsonb_typeof(v) = 'object' then
      v_gc := nullif(btrim(coalesce(v->>'ghi_chu', '')), '');
      v_chu := nullif(btrim(coalesce(v->>'chu', '')), '');
      if jsonb_typeof(v->'chuan') = 'number' then v_chuan := (v->>'chuan')::numeric;
      elsif nullif(btrim(coalesce(v->>'chuan', '')), '') is not null then v_chu := coalesce(v_chu, btrim(v->>'chuan')); end if;
      if jsonb_typeof(v->'min') = 'number' then v_min := (v->>'min')::numeric; end if;
      if jsonb_typeof(v->'max') = 'number' then v_max := (v->>'max')::numeric; end if;
    elsif jsonb_typeof(v) = 'number' then v_chuan := (v #>> '{}')::numeric;
    elsif jsonb_typeof(v) = 'string' then v_chu := nullif(btrim(v #>> '{}'), '');
    elsif jsonb_typeof(v) = 'boolean' then v_chu := case when (v #>> '{}')::boolean then 'co' else 'khong' end;
    end if;
    if t.kieu = 'so' then
      if v_chuan is null and v_chu is not null then
        begin v_chuan := replace(v_chu, ',', '.')::numeric;
        exception when others then raise exception '% %: "%" không phải số.', t.ma_ts, t.ten, v_chu; end;
      end if;
      v_chu := null;
      if (v_min is null) <> (v_max is null) then raise exception '% %: khoảng cần đủ Min ~ Max.', t.ma_ts, t.ten; end if;
      if v_min is not null and v_min > v_max then raise exception '% %: Min lớn hơn Max.', t.ma_ts, t.ten; end if;
      if v_min is not null and v_min = v_max then v_chuan := v_min; end if;             -- cố định
      if v_min is not null and v_min < v_max then v_chuan := null; end if;              -- khoảng: không có tâm
    else
      v_min := null; v_max := null;
      if t.kieu = 'co_khong' then
        v_chu := case lower(coalesce(v_chu, '')) when 'co' then 'co' when 'có' then 'co' when 'true' then 'co'
                                                 when 'khong' then 'khong' when 'không' then 'khong' when 'false' then 'khong'
                                                 when '' then null else 'x' end;
        if v_chu = 'x' then raise exception '% %: chọn Có hoặc Không.', t.ma_ts, t.ten; end if;
        v_chuan := null;
      elsif t.kieu = 'chon_nvl' then
        v_nvl := coalesce(v_nvl, v_chu); v_chu := null; v_chuan := null;
      else
        v_chuan := null;
      end if;
    end if;
    if v_chuan is not null or v_min is not null or v_chu is not null or v_gc is not null then
      insert into duc_dk_gia_tri (id_phieu, ma_ts, chuan, cp_min, cp_max, gia_tri_chu, ghi_chu) values (v_id, k, v_chuan, v_min, v_max, v_chu, v_gc);
    end if;
  end loop;

  delete from duc_dk_dung_cu where id_phieu = v_id;
  for k, v in select * from jsonb_each(coalesce(p_dung_cu, '{}')) loop
    continue when nullif(btrim(coalesce(v #>> '{}', '')), '') is null;
    select * into u from duc_dung_cu where ma = upper(btrim(v #>> '{}'));
    if not found then raise exception 'Dụng cụ % không có trong danh mục.', v #>> '{}'; end if;
    if u.loai <> upper(k) then raise exception 'Dụng cụ % không phải loại %.', u.ma, upper(k); end if;
    insert into duc_dk_dung_cu (id_phieu, loai, ma_dung_cu) values (v_id, u.loai, u.ma);
  end loop;

  if v_nvl is not null and not exists (select 1 from nvl_materials where ma_nvl = v_nvl) then
    raise exception 'Mã NVL % không có trong danh mục.', v_nvl;
  end if;
  update duc_dk_phieu set
    ly_do = nullif(btrim(coalesce(p_ly_do, '')), ''), ma_nvl = v_nvl,
    anh = coalesce(p_anh, '{}'), tep = coalesce(p_tep, '{}'), updated_at = now()
  where id = v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'lan', v_lan, 'thieu', to_jsonb(duc_dk_kiem_thieu(v_id)));
end $function$;

-- 2) Kiểm thiếu: thông số số có Chuẩn HOẶC khoảng là đủ
CREATE OR REPLACE FUNCTION public.duc_dk_kiem_thieu(p_id bigint)
 RETURNS text[] LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  p record; v_loai text; r record; v_loi text[] := '{}'; v_pe01 numeric; v_dc record; v_phi numeric;
begin
  select * into p from duc_dk_phieu where id = p_id;
  if not found then return array['Không tìm thấy phiếu']; end if;
  v_loai := duc_dk_loai_may(p.ma_may);
  if v_loai is null then return array['Máy ' || p.ma_may || ' chưa đặt loại Đúc nhôm / Đúc kẽm']; end if;
  if p.lan > 1 and nullif(btrim(coalesce(p.ly_do, '')), '') is null then v_loi := v_loi || 'Lý do ban hành lần mới'::text; end if;
  if cardinality(p.anh) = 0 then v_loi := v_loi || 'Ảnh màn hình cài đặt máy (ít nhất 1)'::text; end if;

  for r in
    select t.*, g.chuan, g.cp_min, g.gia_tri_chu from duc_dk_thong_so t
      left join duc_dk_gia_tri g on g.id_phieu = p_id and g.ma_ts = t.ma_ts
    where t.hien and t.ap_dung in ('ca_hai', v_loai)
      and case when t.phu_thuoc is null
               then (case v_loai when 'nhom' then t.bat_buoc_nhom else t.bat_buoc_kem end)
               else exists (select 1 from duc_dk_gia_tri g2 where g2.id_phieu = p_id and g2.ma_ts = t.phu_thuoc and g2.gia_tri_chu = 'co') end
    order by t.nhom, t.thu_tu
  loop
    if (r.kieu = 'so' and r.chuan is null and r.cp_min is null)
       or (r.kieu = 'chu' and nullif(btrim(coalesce(r.gia_tri_chu, '')), '') is null)
       or (r.kieu = 'co_khong' and coalesce(r.gia_tri_chu, '') not in ('co', 'khong'))
       or (r.kieu = 'chon_nvl' and p.ma_nvl is null) then
      v_loi := v_loi || (r.ma_ts || ' ' || r.ten);
    end if;
  end loop;

  for r in select unnest(case v_loai when 'nhom' then array['DT', 'OL'] else array['PK', 'VP'] end) l loop
    if not exists (select 1 from duc_dk_dung_cu where id_phieu = p_id and loai = r.l) then
      v_loi := v_loi || ('Dụng cụ ' || case r.l when 'DT' then 'Đầu típ' when 'OL' then 'Ống liệu'
                                               when 'PK' then 'Piston kẽm' else 'Vòi phun' end);
    end if;
  end loop;
  select chuan into v_pe01 from duc_dk_gia_tri where id_phieu = p_id and ma_ts = 'PE01';
  for v_dc in
    select d.loai, u.ma, u.duong_kinh, u.may_dung, u.hien from duc_dk_dung_cu d join duc_dung_cu u on u.ma = d.ma_dung_cu
    where d.id_phieu = p_id
  loop
    if not (p.ma_may = any(coalesce(v_dc.may_dung, '{}'))) then
      v_loi := v_loi || (v_dc.ma || ' không dùng được trên ' || p.ma_may);
    end if;
    if not v_dc.hien then v_loi := v_loi || (v_dc.ma || ' đã ẩn'); end if;
    if v_dc.loai in ('DT', 'OL') then
      if v_phi is not null and v_dc.duong_kinh is distinct from v_phi then
        v_loi := v_loi || 'Đầu típ và ống liệu khác Φ'::text;
      end if;
      v_phi := v_dc.duong_kinh;
      if v_pe01 is not null and v_dc.duong_kinh is distinct from v_pe01 then
        v_loi := v_loi || (v_dc.ma || ' Φ' || v_dc.duong_kinh || ' khác Cỡ piston PE01 Φ' || v_pe01);
      end if;
    end if;
  end loop;
  return v_loi;
end $function$;

-- 3) Lần mới: chép cả khoảng
CREATE OR REPLACE FUNCTION public.duc_dk_lan_moi(p_id bigint)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare p record; v_id bigint; v_lan int; o record;
begin
  if not duc_dk_la_ky_thuat() then raise exception '⛔ Chỉ bộ phận Kỹ thuật (hoặc admin) lập lần mới.' using errcode = '42501'; end if;
  select * into p from duc_dk_phieu where id = p_id;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  if p.trang_thai not in ('hieu_luc', 'het_hieu_luc') then raise exception 'Chỉ chép từ lần đã ban hành.'; end if;
  perform pg_advisory_xact_lock(hashtext('duc_dk:' || p.ma_sp || '|' || p.ma_may));
  select id, lan, trang_thai into o from duc_dk_phieu
    where ma_sp = p.ma_sp and ma_may = p.ma_may and trang_thai in ('nhap', 'cho_kiem', 'cho_duyet');
  if found then raise exception 'Đang có lần % (%) chưa xong — sửa lần đó.', o.lan, o.trang_thai; end if;
  select max(lan) + 1 into v_lan from duc_dk_phieu where ma_sp = p.ma_sp and ma_may = p.ma_may;
  insert into duc_dk_phieu (ma_sp, ma_may, lan, ma_nvl, anh, tep, nguoi_lap, lap_luc)
    values (p.ma_sp, p.ma_may, v_lan, p.ma_nvl, p.anh, p.tep, auth.uid(), now()) returning id into v_id;
  insert into duc_dk_gia_tri (id_phieu, ma_ts, chuan, cp_min, cp_max, gia_tri_chu, ghi_chu)
    select v_id, ma_ts, chuan, cp_min, cp_max, gia_tri_chu, ghi_chu from duc_dk_gia_tri where id_phieu = p_id;
  insert into duc_dk_dung_cu (id_phieu, loai, ma_dung_cu)
    select v_id, loai, ma_dung_cu from duc_dk_dung_cu where id_phieu = p_id;
  perform duc_dk_ls(v_id, 'lan_moi', 'Chép từ lần ' || p.lan);
  return jsonb_build_object('ok', true, 'id', v_id, 'lan', v_lan);
end $function$;

-- 4) Thông số cần xác nhận khi lên khuôn: trả kèm min/max
CREATE OR REPLACE FUNCTION public.duc_dk_xn_thong_so(p_id bigint)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  with p as (select *, duc_dk_loai_may(ma_may) loai from duc_dk_phieu where id = p_id)
  select coalesce(jsonb_agg(jsonb_build_object(
      'ma_ts', t.ma_ts, 'nhom', t.nhom, 'ten', t.ten, 'don_vi', t.don_vi, 'kieu', t.kieu,
      'chuan', g.chuan, 'min', g.cp_min, 'max', g.cp_max,
      'chu', case when t.kieu = 'chon_nvl' then p.ma_nvl else g.gia_tri_chu end,
      'nguong', t.nguong_pct,
      'td', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'gia_tri', (e->>'sau')::numeric) order by d.id), '[]'::jsonb)
               from duc_thay_doi d, jsonb_array_elements(d.chi_tiet) e
              where t.kieu = 'so' and t.ma_muc_td is not null
                and d.ma_may = p.ma_may and upper(d.ma_sp) = p.ma_sp
                and d.thoi_diem_ghi >= coalesce(p.hieu_luc_tu, p.duyet_luc, p.lap_luc)
                and e->>'ma' = t.ma_muc_td and (e->>'sau') ~ '^-?[0-9]+(\.[0-9]+)?$'
                and (d.ket_qua_duyet = 'da_duyet'
                     or (d.khan and d.trang_thai <> 'huy' and d.ket_qua_duyet is distinct from 'khong_duyet')))
    ) order by t.nhom, t.thu_tu), '[]'::jsonb)
    from p
    join duc_dk_thong_so t on t.hien and t.ap_dung in (p.loai, 'ca_hai')
                          and case p.loai when 'kem' then t.bat_buoc_kem else t.bat_buoc_nhom end
    left join duc_dk_gia_tri g on g.id_phieu = p.id and g.ma_ts = t.ma_ts
   where (t.kieu = 'so' and (g.chuan is not null or g.cp_min is not null))
      or (t.kieu in ('chu', 'co_khong') and nullif(btrim(g.gia_tri_chu), '') is not null)
      or (t.kieu = 'chon_nvl' and nullif(btrim(p.ma_nvl), '') is not null);
$function$;

-- 5) Lưu xác nhận lên khuôn: có khoảng thì kiểm theo [min, max]
CREATE OR REPLACE FUNCTION public.duc_dk_xac_nhan_luu(p_ma_may text, p_ma_sp text, p_gia_tri jsonb, p_dung_cu jsonb, p_id_dong text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_sp text := upper(trim(coalesce(p_ma_sp, ''))); p record; t jsonb; d record;
        v_loi text[] := '{}'; v_lech jsonb := '[]'; v_so numeric; v_chuan numeric; v_lo numeric; v_hi numeric; v_td jsonb;
        v_gt jsonb := '{}'; v_id bigint; v_raw text; v_chon text; v_cai record; v_r jsonb; v_lap bigint[] := '{}';
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into p from duc_dk_phieu where ma_may = p_ma_may and ma_sp = v_sp and trang_thai = 'hieu_luc';
  if not found then return jsonb_build_object('ok', false, 'error', 'Máy này chưa có phiếu ĐK đúc hiệu lực cho mã SP này'); end if;
  for d in select dc.loai, dc.ma_dung_cu from duc_dk_dung_cu dc where dc.id_phieu = p.id loop
    v_chon := btrim(coalesce(p_dung_cu->>d.loai, ''));
    if split_part(v_chon, '/', 1) <> d.ma_dung_cu then
      v_loi := v_loi || ('Dụng cụ ' || d.loai || ': phải là ' || d.ma_dung_cu);
      continue;
    end if;
    if position('/' in v_chon) > 0 then
      select * into v_cai from duc_dung_cu_cai where ma_cai = v_chon;
      if not found then v_loi := v_loi || ('Không có ' || v_chon); continue; end if;
      if v_cai.trang_thai = 'hong' then v_loi := v_loi || (v_chon || ' đã báo hỏng'); continue; end if;
      v_lap := v_lap || v_cai.id;
    elsif exists (select 1 from duc_dung_cu_cai where ma_dung_cu = d.ma_dung_cu and trang_thai <> 'hong') then
      v_loi := v_loi || ('Dụng cụ ' || d.loai || ': chọn đúng cái đang lắp (' || d.ma_dung_cu || '/..)');
    end if;
  end loop;
  for t in select * from jsonb_array_elements(duc_dk_xn_thong_so(p.id)) loop
    v_raw := btrim(coalesce(p_gia_tri->>(t->>'ma_ts'), ''));
    if t->>'kieu' = 'so' then
      if v_raw !~ '^-?[0-9]+([.,][0-9]+)?$' then
        v_loi := v_loi || ((t->>'ten') || ': chưa nhập số'); continue;
      end if;
      v_so := replace(v_raw, ',', '.')::numeric;
      v_chuan := (t->>'chuan')::numeric;
      if t->>'min' is not null then
        v_lo := (t->>'min')::numeric; v_hi := (t->>'max')::numeric;
      else
        v_lo := v_chuan - abs(v_chuan) * coalesce((t->>'nguong')::numeric, 5) / 100;
        v_hi := v_chuan + abs(v_chuan) * coalesce((t->>'nguong')::numeric, 5) / 100;
      end if;
      v_gt := v_gt || jsonb_build_object(t->>'ma_ts', v_so);
      if v_so >= v_lo - 1e-9 and v_so <= v_hi + 1e-9 then continue; end if;
      v_td := null;
      select e into v_td from jsonb_array_elements(t->'td') e
       where abs(v_so - (e->>'gia_tri')::numeric) <= abs((e->>'gia_tri')::numeric) * coalesce((t->>'nguong')::numeric, 5) / 100 + 1e-9
       order by (e->>'id')::bigint desc limit 1;
      if v_td is not null then
        v_lech := v_lech || jsonb_build_array(jsonb_build_object('ma_ts', t->>'ma_ts', 'gia_tri', v_so, 'chuan', v_chuan,
                    'min', t->'min', 'max', t->'max', 'td', v_td->'id'));
      else
        v_loi := v_loi || ((t->>'ten') || ' ' || trim_scale(v_so) || ' ngoài ' || trim_scale(round(v_lo, 3)) || ' – ' || trim_scale(round(v_hi, 3)));
      end if;
    else
      if v_raw <> 'dung' then v_loi := v_loi || ((t->>'ten') || ': chưa tick Đúng'); continue; end if;
      v_gt := v_gt || jsonb_build_object(t->>'ma_ts', 'dung');
    end if;
  end loop;
  if cardinality(v_loi) > 0 then
    return jsonb_build_object('ok', false, 'error', array_to_string(v_loi, '; '), 'loi', to_jsonb(v_loi));
  end if;
  for i in 1..coalesce(cardinality(v_lap), 0) loop
    v_r := duc_dc_lap_noi(v_lap[i], p_ma_may, 'xac_nhan', null);
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '%', v_r->>'error';
    end if;
  end loop;
  insert into duc_dk_xac_nhan (ma_may, ma_sp, id_phieu, id_dong, gia_tri, dung_cu, lech, nguoi, nguoi_ten)
  values (p_ma_may, v_sp, p.id, nullif(btrim(coalesce(p_id_dong, '')), ''), v_gt, coalesce(p_dung_cu, '{}'), v_lech,
          auth.uid(), duc_dk_ten(auth.uid()))
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'lech', v_lech);
end $function$;
