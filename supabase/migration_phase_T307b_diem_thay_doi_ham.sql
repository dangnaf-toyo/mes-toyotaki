-- T307b: Điểm thay đổi chủ động Đúc — hàm ghi / duyệt / đã chỉnh / huỷ + nối IPQC "Sau thay đổi". Chạy sau T307a.
--
-- Luồng: trưởng ca ghi (duc_td_ghi)
--   • không mục nào cần duyệt          → áp dụng ngay → chờ IPQC (hoặc ghi nhận)
--   • có mục cần duyệt                 → cho_duyet → người duyệt (duc_td_duyet) → cho_ap_dung → trưởng ca "Đã chỉnh" (duc_td_da_chinh) → chờ IPQC
--   • Ca đêm + "Áp dụng khẩn"          → áp dụng ngay + bắt buộc IPQC, người duyệt duyệt bù
--   IPQC kiểm (trigger trg_duc_td_cp)  → ok / ng (NG: hệ thống IPQC sẵn có tự mở F1)

-- 0) Chuông: thêm nguồn 'thay_doi'
alter table public.cv_thong_bao drop constraint if exists cv_thong_bao_nguon_check;
alter table public.cv_thong_bao add constraint cv_thong_bao_nguon_check
  check (nguon = any (array['cong_viec', 'khsx', 'bd_khuon', 'ipqc', 'ncp', 'tai_lieu', 'tieu_chuan', 'thay_doi']));

-- 1) Lần kiểm "sau_thay_doi" ưu tiên như sau sự cố: nuốt lần kiểm định kỳ đang chờ của cùng dòng.
create or replace function public.duc_request_ipqc_check(p_id_dong text, p_loai_kiem text, p_id_su_co_goc text DEFAULT NULL::text, p_moc_cho_override timestamp with time zone DEFAULT NULL::timestamp with time zone)
 returns jsonb language plpgsql security definer
as $function$
declare
  v_cht record;
  v_dup int;
  v_id text;
  v_han_kiem timestamptz;
  v_last_check timestamptz;
begin
  select ma_may, ma_sp, ngay, ca, phuong_an_ca into v_cht from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then return jsonb_build_object('ok', false, 'reason', 'khong_tim_thay_dong'); end if;
  if v_cht.ma_sp is null or v_cht.ma_sp = '' then return jsonb_build_object('ok', false, 'reason', 'dong_khong_co_sp'); end if;

  select count(*) into v_dup from duc_ipqc_checkpoint
    where id_dong = p_id_dong and loai_kiem = p_loai_kiem and trang_thai = 'cho_kiem';
  if v_dup > 0 then return jsonb_build_object('ok', false, 'reason', 'da_co_checkpoint_cho_kiem'); end if;

  -- Sự cố / đổi khuôn / sau thay đổi (T307) ưu tiên hơn định kỳ: nuốt luôn checkpoint 'dinh_ky'
  -- đang chờ của cùng dòng (thường là dòng định kỳ IPQC bấm vào rồi bỏ dở).
  if p_loai_kiem in ('sau_su_co', 'doi_khuon', 'sau_thay_doi') then
    update duc_ipqc_checkpoint
      set trang_thai = 'het_hieu_luc'
      where id_dong = p_id_dong and loai_kiem = 'dinh_ky' and trang_thai = 'cho_kiem';
  end if;

  -- Mốc bắt đầu tính "trễ": không bao giờ lùi trước lần kiểm HOÀN THÀNH gần
  -- nhất của chính dòng này (kiểm sự cố / đổi khuôn cũng là kiểm định kỳ).
  select max(thoi_diem_kiem_thuc_te) into v_last_check
    from duc_ipqc_checkpoint
    where id_dong = p_id_dong and trang_thai = 'da_kiem';

  v_han_kiem := coalesce(p_moc_cho_override, now());
  if v_last_check is not null and v_han_kiem < v_last_check then
    v_han_kiem := v_last_check;
  end if;
  if v_han_kiem > now() then
    v_han_kiem := now();
  end if;

  v_id := 'IPQC_' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DDMMYYYY_HH24MISS')
    || '_' || duc_normalize_name(v_cht.ma_may) || '_' || p_loai_kiem;

  insert into duc_ipqc_checkpoint (
    id_checkpoint, id_dong, ma_may, ma_sp, ngay, ca, phuong_an_ca, loai_kiem,
    id_su_co_goc, thoi_diem_tao, han_kiem, trang_thai
  ) values (
    v_id, p_id_dong, v_cht.ma_may, v_cht.ma_sp, v_cht.ngay, v_cht.ca, v_cht.phuong_an_ca,
    p_loai_kiem, p_id_su_co_goc, now(), v_han_kiem, 'cho_kiem'
  );

  return jsonb_build_object('ok', true, 'id_checkpoint', v_id);
end;
$function$;

-- 2) Người duyệt theo nhóm (GĐSX luôn duyệt thay được)
create or replace function public.duc_td_ds_duyet(p_nhom text)
returns uuid[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct u), '{}') from unnest(
    (case p_nhom
       when 'ky_thuat'        then cv_pd_ds_role(array['quan_ly_bo_phan'], 'Kỹ thuật')
       when 'thiet_bi'        then cv_pd_ds_role(array['quan_ly_bo_phan'], 'Thiết bị')
       when 'to_truong_khuon' then cv_pd_ds_role(array['to_truong_khuon'], null)
       when 'qlbp_duc'        then cv_pd_ds_role(array['quan_ly_bo_phan'], 'Đúc')
       when 'qa'              then cv_pd_ds_role(array['qc_manager'], null)
       else '{}'::uuid[] end)
    || cv_pd_ds_role(array['giam_doc_sx'], null)) u;
$$;

create or replace function public.duc_td_nhom_ten(p_nhom text)
returns text language sql immutable as $$
  select case p_nhom when 'ky_thuat' then 'Kỹ thuật' when 'thiet_bi' then 'Thiết bị' when 'to_truong_khuon' then 'Tổ trưởng khuôn'
                     when 'qlbp_duc' then 'QLBP Đúc' when 'qa' then 'QA' else coalesce(p_nhom, '') end;
$$;

-- Tóm tắt "Tốc độ pha 2 2.8→3.2 m/s; Áp suất tăng áp 80→90 MPa"
create or replace function public.duc_td_tom_tat(p_chi_tiet jsonb)
returns text language sql immutable as $$
  select coalesce(string_agg(
    (e->>'ten') || ' ' || coalesce(nullif(e->>'truoc', '') || '→', '→') || coalesce(e->>'sau', '') || coalesce(' ' || nullif(e->>'don_vi', ''), ''),
    '; '), '')
  from jsonb_array_elements(coalesce(p_chi_tiet, '[]')) e;
$$;

-- Quyền của người đang đăng nhập (giao diện dùng để hiện nút)
create or replace function public.duc_td_quyen()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'ghi', public.has_role('truong_ca'),
    'duyet', coalesce((select jsonb_agg(n) from unnest(array['ky_thuat', 'thiet_bi', 'to_truong_khuon', 'qlbp_duc', 'qa']) n
                       where auth.uid() = any(public.duc_td_ds_duyet(n))), '[]'),
    'huy_moi', public.has_role('admin') or auth.uid() = any(cv_pd_ds_role(array['quan_ly_bo_phan'], 'Đúc')));
$$;

-- 3) Chuông cho người duyệt các nhóm còn chờ
create or replace function public.duc_td_bao_duyet(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v record; g text;
begin
  select * into v from duc_thay_doi where id = p_id;
  if not found then return; end if;
  foreach g in array v.can_duyet loop
    if exists (select 1 from jsonb_array_elements(v.da_duyet) d where d->>'nhom' = g and (d->>'dong_y')::boolean) then continue; end if;
    perform cv_pd_gui(duc_td_ds_duyet(g), 'thay_doi', 'can_duyet', 'td_duyet:' || p_id || ':' || g,
      'diem-thay-doi.html?id=' || p_id,
      case when v.khan then '⚡ Đã áp dụng khẩn — cần duyệt bù (' else 'Cần duyệt thay đổi (' end || duc_td_nhom_ten(g) || '): '
        || v.ma_may || ' · ' || coalesce(v.ma_sp, '') || ' — ' || duc_td_tom_tat(v.chi_tiet)
        || ' · trưởng ca ' || coalesce(v.nguoi_ghi, ''), true);
  end loop;
end $$;

-- 4) Gắn lần kiểm IPQC: dùng chung lần kiểm sau sự cố / đổi khuôn / sau thay đổi đang chờ của dòng, không có thì tạo mới
create or replace function public.duc_td_tao_kiem(p_id bigint)
returns text language plpgsql security definer set search_path = public as $$
declare v record; v_cp text; r jsonb;
begin
  select * into v from duc_thay_doi where id = p_id;
  select c.id_checkpoint into v_cp from duc_ipqc_checkpoint c
   where c.id_dong = v.id_dong and c.trang_thai = 'cho_kiem' and c.loai_kiem in ('sau_su_co', 'doi_khuon', 'sau_thay_doi')
   order by c.thoi_diem_tao desc limit 1;
  if v_cp is null then
    r := duc_request_ipqc_check(v.id_dong, 'sau_thay_doi', null, null);
    if not coalesce((r->>'ok')::boolean, false) then
      raise exception 'Không tạo được lần kiểm IPQC (%).', coalesce(r->>'reason', '?');
    end if;
    v_cp := r->>'id_checkpoint';
  end if;
  update duc_thay_doi set id_checkpoint = v_cp, trang_thai = 'cho_ipqc', updated_at = now() where id = p_id;
  perform cv_pd_gui(cv_pd_ds_role(array['ipqc', 'qc_manager'], null), 'thay_doi', 'thay_doi', 'td:' || p_id, 'ipqc.html',
    '🔄 ' || v.ma_may || ' · ' || coalesce(v.ma_sp, '') || ' có thay đổi — kiểm SP sau thay đổi: ' || duc_td_tom_tat(v.chi_tiet), true);
  return v_cp;
end $$;

-- 5) Trưởng ca ghi phiếu
create or replace function public.duc_td_ghi(
  p_id_dong text, p_chi_tiet jsonb, p_ly_do text, p_ma_loi text default null, p_ghi_chu text default null,
  p_anh jsonb default '[]', p_khan boolean default false, p_ly_do_khan text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_dong record; v_ten text; e jsonb; m record;
  v_items jsonb := '[]'; v_duyet text[] := '{}'; v_ipqc boolean := false; v_seen text[] := '{}';
  v_truoc numeric; v_sau numeric; v_chuan numeric; v_pct numeric; v_vuot boolean; v_nhom text; v_ip boolean; v_xn text[];
  v_id bigint; v_khan boolean := false;
begin
  if not public.has_role('truong_ca') then
    raise exception '⛔ Chỉ trưởng ca được ghi phiếu thay đổi.' using errcode = '42501';
  end if;
  select id_dong, ma_may, ma_sp, so_khuon, ngay, ca into v_dong from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then raise exception 'Không tìm thấy dòng máy.'; end if;
  if coalesce(v_dong.ma_sp, '') = '' then raise exception 'Máy chưa chạy mã nào.'; end if;
  if p_chi_tiet is null or jsonb_typeof(p_chi_tiet) <> 'array' or jsonb_array_length(p_chi_tiet) = 0 then
    raise exception 'Chọn ít nhất 1 mục thay đổi.';
  end if;
  if coalesce(btrim(p_ly_do), '') = '' then raise exception 'Chọn lý do thay đổi.'; end if;
  select coalesce(nullif(full_name, ''), nullif(username, ''), email) into v_ten from user_roles where user_id = auth.uid();

  for e in select * from jsonb_array_elements(p_chi_tiet) loop
    select * into m from duc_thay_doi_mau where ma = e->>'ma' and hieu_luc;
    if not found then raise exception 'Mục thay đổi không hợp lệ: %', coalesce(e->>'ma', '?'); end if;
    if m.ma = any(v_seen) then raise exception 'Mục "%" bị chọn trùng.', m.ten; end if;
    v_seen := v_seen || m.ma;
    v_chuan := null; v_pct := null; v_vuot := false; v_truoc := null; v_sau := null;

    if m.kieu_nhap = 'so' then
      begin
        v_truoc := nullif(btrim(e->>'truoc'), '')::numeric;
        v_sau   := nullif(btrim(e->>'sau'), '')::numeric;
      exception when others then
        raise exception '%: Trước và Sau phải là số.', m.ten;
      end;
      if v_truoc is null or v_sau is null then raise exception '%: nhập đủ Trước và Sau.', m.ten; end if;
      if v_truoc = v_sau then raise exception '%: giá trị Sau phải khác Trước.', m.ten; end if;
    elsif coalesce(btrim(e->>'sau'), '') = '' then
      raise exception '%: nhập nội dung Sau.', m.ten;
    end if;

    if m.tu_chon then
      v_ip   := coalesce((e->>'can_ipqc')::boolean, false);
      v_nhom := coalesce(nullif(e->>'nguoi_duyet', ''), 'khong');
      if v_nhom not in ('khong', 'ky_thuat', 'thiet_bi', 'to_truong_khuon', 'qlbp_duc', 'qa') then
        raise exception 'Người duyệt không hợp lệ.';
      end if;
      v_nhom := nullif(v_nhom, 'khong');
      v_xn := case when v_ip then array['Theo nội dung thay đổi: ' || btrim(e->>'sau')] else '{}' end;
    else
      v_ip   := m.can_ipqc;
      v_nhom := nullif(m.nguoi_duyet, 'khong');
      v_xn   := case when v_ip then m.xac_nhan else '{}' end;
      if m.kieu_nhap = 'so' and m.nguong_pct is not null then
        select gia_tri into v_chuan from duc_thay_doi_chuan
         where ma_may = v_dong.ma_may and ma_sp = v_dong.ma_sp and ma_muc = m.ma;
        if v_chuan is null then   -- lần đầu: giá trị "Trước" làm chuẩn
          v_chuan := v_truoc;
          insert into duc_thay_doi_chuan (ma_may, ma_sp, ma_muc, gia_tri, nguon, nguoi)
          values (v_dong.ma_may, v_dong.ma_sp, m.ma, v_truoc, 'ban_dau', v_ten) on conflict do nothing;
        end if;
        v_pct  := case when v_chuan = 0 then 100 else round(abs(v_sau - v_chuan) / abs(v_chuan) * 100, 1) end;
        v_vuot := v_pct > m.nguong_pct;
        if not v_vuot then v_nhom := null; end if;
      end if;
    end if;

    if v_nhom is not null and not (v_nhom = any(v_duyet)) then v_duyet := v_duyet || v_nhom; end if;
    v_ipqc := v_ipqc or v_ip;
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'ma', m.ma, 'nhom', m.nhom, 'ten', m.ten, 'kieu', m.kieu_nhap, 'don_vi', m.don_vi,
      'truoc', case when m.kieu_nhap = 'so' then to_jsonb(v_truoc) else to_jsonb(nullif(btrim(coalesce(e->>'truoc', '')), '')) end,
      'sau',   case when m.kieu_nhap = 'so' then to_jsonb(v_sau)   else to_jsonb(btrim(e->>'sau')) end,
      'chuan', v_chuan, 'pct', v_pct, 'nguong', m.nguong_pct, 'vuot', v_vuot,
      'can_ipqc', v_ip, 'nguoi_duyet', v_nhom, 'xac_nhan', to_jsonb(coalesce(v_xn, '{}'))));
  end loop;

  if cardinality(v_duyet) > 0 and coalesce(p_khan, false) then
    if v_dong.ca is distinct from 'Ca đêm' then raise exception 'Áp dụng khẩn chỉ dùng cho Ca đêm.'; end if;
    if coalesce(btrim(p_ly_do_khan), '') = '' then raise exception 'Ghi lý do áp dụng khẩn.'; end if;
    v_khan := true;
    v_ipqc := true;   -- áp dụng khẩn bắt buộc IPQC
  end if;

  insert into duc_thay_doi (nguoi_ghi, nguoi_ghi_id, id_dong, ma_may, ma_sp, so_khuon, ngay, ca, chi_tiet, ly_do, ma_loi, ghi_chu,
                            anh_urls, can_ipqc, can_duyet, khan, ly_do_khan, trang_thai, thoi_diem_ap_dung)
  values (v_ten, auth.uid(), v_dong.id_dong, v_dong.ma_may, v_dong.ma_sp, v_dong.so_khuon, v_dong.ngay, v_dong.ca, v_items,
          btrim(p_ly_do), nullif(btrim(coalesce(p_ma_loi, '')), ''), nullif(btrim(coalesce(p_ghi_chu, '')), ''),
          coalesce(p_anh, '[]'), v_ipqc, v_duyet, v_khan, case when v_khan then btrim(p_ly_do_khan) end,
          case when cardinality(v_duyet) > 0 and not v_khan then 'cho_duyet' else 'cho_ap_dung' end,
          case when cardinality(v_duyet) > 0 and not v_khan then null else now() end)
  returning id into v_id;

  if cardinality(v_duyet) = 0 or v_khan then   -- áp dụng ngay
    if v_ipqc then perform duc_td_tao_kiem(v_id);
    else update duc_thay_doi set trang_thai = 'ghi_nhan', updated_at = now() where id = v_id;
    end if;
  end if;
  if cardinality(v_duyet) > 0 then perform duc_td_bao_duyet(v_id); end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'can_duyet', to_jsonb(v_duyet), 'khan', v_khan,
    'trang_thai', (select trang_thai from duc_thay_doi where id = v_id));
end $$;

-- 6) Người duyệt: Duyệt / Không duyệt (cả duyệt bù phiếu áp dụng khẩn)
create or replace function public.duc_td_duyet(p_id bigint, p_dong_y boolean, p_ghi_chu text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record; v_cho text[]; v_cua_toi text[]; g text; v_ten text; v_gc text := nullif(btrim(coalesce(p_ghi_chu, '')), '');
begin
  select * into v from duc_thay_doi where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  if not (v.trang_thai = 'cho_duyet' or (v.khan and v.ket_qua_duyet is null and v.trang_thai <> 'huy')) then
    raise exception 'Phiếu không còn chờ duyệt.';
  end if;
  v_cho := array(select x from unnest(v.can_duyet) x
                 where not exists (select 1 from jsonb_array_elements(v.da_duyet) d where d->>'nhom' = x and (d->>'dong_y')::boolean));
  v_cua_toi := array(select x from unnest(v_cho) x where auth.uid() = any(duc_td_ds_duyet(x)));
  if cardinality(v_cua_toi) = 0 then
    raise exception '⛔ Bạn không phải người duyệt của phiếu này.' using errcode = '42501';
  end if;
  if not p_dong_y and v_gc is null then raise exception 'Ghi lý do không duyệt.'; end if;
  select coalesce(nullif(full_name, ''), nullif(username, ''), email) into v_ten from user_roles where user_id = auth.uid();

  update duc_thay_doi set
    da_duyet = da_duyet || (select jsonb_agg(jsonb_build_object('nhom', x, 'nguoi', v_ten, 'luc', now(), 'dong_y', p_dong_y, 'ghi_chu', v_gc))
                            from unnest(v_cua_toi) x),
    updated_at = now()
  where id = p_id;
  foreach g in array v_cua_toi loop perform cv_pd_xong('td_duyet:' || p_id || ':' || g, false); end loop;

  if not p_dong_y then
    perform cv_pd_xong('td_duyet:' || p_id || ':', true);
    update duc_thay_doi set ket_qua_duyet = 'khong_duyet',
      trang_thai = case when trang_thai = 'cho_duyet' then 'khong_duyet' else trang_thai end
    where id = p_id;
    perform cv_pd_gui(array[v.nguoi_ghi_id] || case when v.khan then cv_pd_ds_role(array['quan_ly_bo_phan'], 'Đúc') else '{}'::uuid[] end,
      'thay_doi', 'tu_choi_duyet', 'td_kq:' || p_id, 'diem-thay-doi.html?id=' || p_id,
      case when v.khan then '⛔ Không duyệt bù thay đổi đã áp dụng khẩn — đưa máy về điều kiện cũ: '
           else '⛔ Không duyệt thay đổi: ' end
        || v.ma_may || ' · ' || duc_td_tom_tat(v.chi_tiet) || ' — ' || v_gc, v.khan);
  elsif cardinality(v_cho) = cardinality(v_cua_toi) then   -- đủ người duyệt
    update duc_thay_doi set ket_qua_duyet = 'da_duyet',
      trang_thai = case when trang_thai = 'cho_duyet' then 'cho_ap_dung' else trang_thai end
    where id = p_id;
    -- Mục vượt ngưỡng đã được duyệt → giá trị Sau thành giá trị chuẩn mới
    insert into duc_thay_doi_chuan (ma_may, ma_sp, ma_muc, gia_tri, nguon, id_phieu, cap_nhat_luc, nguoi)
    select v.ma_may, v.ma_sp, e->>'ma', (e->>'sau')::numeric, 'da_duyet', p_id, now(), v_ten
      from jsonb_array_elements(v.chi_tiet) e
     where coalesce((e->>'vuot')::boolean, false) and v.ma_sp is not null
    on conflict (ma_may, ma_sp, ma_muc) do update
      set gia_tri = excluded.gia_tri, nguon = 'da_duyet', id_phieu = excluded.id_phieu, cap_nhat_luc = now(), nguoi = excluded.nguoi;
    if v.trang_thai = 'cho_duyet' then
      perform cv_pd_gui(array[v.nguoi_ghi_id], 'thay_doi', 'da_duyet', 'td_ap_dung:' || p_id, 'duc-dashboard.html',
        '✅ Đã duyệt thay đổi ' || v.ma_may || ' · ' || duc_td_tom_tat(v.chi_tiet)
          || ' — chỉnh máy xong bấm "Đã chỉnh" trên Bảng điều khiển Đúc.', true);
    end if;
  end if;
  return jsonb_build_object('ok', true, 'trang_thai', (select trang_thai from duc_thay_doi where id = p_id),
                            'ket_qua_duyet', (select ket_qua_duyet from duc_thay_doi where id = p_id));
end $$;

-- 7) Trưởng ca bấm "Đã chỉnh" sau khi được duyệt
create or replace function public.duc_td_da_chinh(p_id bigint, p_id_dong text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record; d record;
begin
  if not public.has_role('truong_ca') then
    raise exception '⛔ Chỉ trưởng ca được xác nhận đã chỉnh.' using errcode = '42501';
  end if;
  select * into v from duc_thay_doi where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  if v.trang_thai <> 'cho_ap_dung' then raise exception 'Phiếu không ở bước chờ chỉnh.'; end if;
  select id_dong, ma_may, ma_sp, so_khuon, ngay, ca into d from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found or d.ma_may <> v.ma_may then raise exception 'Không đúng máy của phiếu.'; end if;
  if coalesce(d.ma_sp, '') <> coalesce(v.ma_sp, '') then
    raise exception 'Máy đang chạy mã khác (%) — huỷ phiếu và ghi lại.', d.ma_sp;
  end if;
  update duc_thay_doi set id_dong = d.id_dong, so_khuon = d.so_khuon, ngay = d.ngay, ca = d.ca,
         thoi_diem_ap_dung = now(), updated_at = now()
   where id = p_id;
  perform cv_pd_xong('td_ap_dung:' || p_id, false);
  if v.can_ipqc then perform duc_td_tao_kiem(p_id);
  else update duc_thay_doi set trang_thai = 'ghi_nhan', updated_at = now() where id = p_id;
  end if;
  return jsonb_build_object('ok', true, 'trang_thai', (select trang_thai from duc_thay_doi where id = p_id));
end $$;

-- 8) Huỷ phiếu ghi nhầm (người ghi / QLBP Đúc / admin), khi chưa có kết quả
create or replace function public.duc_td_huy(p_id bigint, p_ly_do text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record;
begin
  select * into v from duc_thay_doi where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  if v.trang_thai not in ('cho_duyet', 'cho_ap_dung', 'cho_ipqc') then raise exception 'Phiếu đã kết thúc, không huỷ được.'; end if;
  if not (auth.uid() = v.nguoi_ghi_id or public.has_role('admin')
          or auth.uid() = any(cv_pd_ds_role(array['quan_ly_bo_phan'], 'Đúc'))) then
    raise exception '⛔ Chỉ người ghi phiếu hoặc QLBP Đúc được huỷ.' using errcode = '42501';
  end if;
  if coalesce(btrim(p_ly_do), '') = '' then raise exception 'Ghi lý do huỷ.'; end if;
  update duc_thay_doi set trang_thai = 'huy', ly_do_huy = btrim(p_ly_do), updated_at = now() where id = p_id;
  -- Lần kiểm riêng của phiếu (chưa ai bắt đầu kiểm, không phiếu khác dùng chung) → hết hiệu lực
  if v.id_checkpoint is not null then
    update duc_ipqc_checkpoint c set trang_thai = 'het_hieu_luc',
           ghi_chu = concat_ws(E'\n', nullif(c.ghi_chu, ''), '[T307: huỷ phiếu thay đổi TD-' || p_id || ']')
     where c.id_checkpoint = v.id_checkpoint and c.loai_kiem = 'sau_thay_doi' and c.trang_thai = 'cho_kiem'
       and not exists (select 1 from duc_thay_doi t where t.id_checkpoint = c.id_checkpoint and t.trang_thai = 'cho_ipqc')
       and not exists (select 1 from duc_ipqc_inspection_session s where s.checkpoint_id = c.id_checkpoint and s.completed_at is null);
  end if;
  perform cv_pd_xong('td:' || p_id, false);
  perform cv_pd_xong('td_duyet:' || p_id || ':', true);
  perform cv_pd_xong('td_ap_dung:' || p_id, false);
  return jsonb_build_object('ok', true);
end $$;

-- 9) IPQC kiểm xong / lần kiểm hết hiệu lực → cập nhật phiếu.
-- Trigger hoãn tới cuối giao dịch: lúc đó sự cố F1 (nếu NG) đã được mở → ghi được mã sự cố.
create or replace function public.duc_td_cp_trg()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; v_cp text; v_sc text;
begin
  if new.trang_thai is not distinct from old.trang_thai then return null; end if;
  if new.trang_thai = 'da_kiem' then
    if new.ket_qua = 'NG' then select open_id_su_co into v_sc from duc_ca_hien_tai where id_dong = new.id_dong; end if;
    for r in select id from duc_thay_doi where id_checkpoint = new.id_checkpoint and trang_thai = 'cho_ipqc' loop
      update duc_thay_doi set
        trang_thai = case when new.ket_qua = 'NG' then 'ng' else 'ok' end,
        ket_qua_ipqc = new.ket_qua, thoi_diem_ipqc = coalesce(new.thoi_diem_kiem_thuc_te, now()), nguoi_kiem = new.nguoi_kiem,
        xac_nhan_kq = (select jsonb_agg(e) from jsonb_array_elements(coalesce(new.checklist_json, '[]')) e
                        where e->>'code' = 'thay_doi' and e->>'td_id' = r.id::text),
        id_su_co = case when new.ket_qua = 'NG' then v_sc end,
        updated_at = now()
      where id = r.id;
      perform cv_pd_xong('td:' || r.id, false);
    end loop;
  elsif new.trang_thai = 'het_hieu_luc' then
    for r in select id from duc_thay_doi where id_checkpoint = new.id_checkpoint and trang_thai = 'cho_ipqc' loop
      select c.id_checkpoint into v_cp from duc_ipqc_checkpoint c
       where c.ma_may = new.ma_may and c.trang_thai = 'cho_kiem' and c.id_checkpoint <> new.id_checkpoint
         and c.loai_kiem in ('sau_su_co', 'doi_khuon', 'sau_thay_doi')
       order by c.thoi_diem_tao desc limit 1;
      if v_cp is not null then
        update duc_thay_doi set id_checkpoint = v_cp, updated_at = now() where id = r.id;
      else
        update duc_thay_doi set trang_thai = 'khong_kiem', updated_at = now() where id = r.id;
        perform cv_pd_xong('td:' || r.id, false);
      end if;
    end loop;
  end if;
  return null;
exception when others then
  raise warning 'duc_td_cp_trg: %', sqlerrm;
  return null;
end $$;
drop trigger if exists trg_duc_td_cp on public.duc_ipqc_checkpoint;
create constraint trigger trg_duc_td_cp after update of trang_thai on public.duc_ipqc_checkpoint
  deferrable initially deferred for each row execute function public.duc_td_cp_trg();

-- 10) Quyền gọi hàm
revoke execute on function public.duc_td_ds_duyet(text), public.duc_td_bao_duyet(bigint), public.duc_td_tao_kiem(bigint),
  public.duc_td_cp_trg() from public, anon, authenticated;
revoke execute on function public.duc_td_quyen(),
  public.duc_td_ghi(text, jsonb, text, text, text, jsonb, boolean, text),
  public.duc_td_duyet(bigint, boolean, text), public.duc_td_da_chinh(bigint, text), public.duc_td_huy(bigint, text)
  from public, anon;
grant execute on function public.duc_td_quyen(),
  public.duc_td_ghi(text, jsonb, text, text, text, jsonb, boolean, text),
  public.duc_td_duyet(bigint, boolean, text), public.duc_td_da_chinh(bigint, text), public.duc_td_huy(bigint, text)
  to authenticated;
