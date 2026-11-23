-- T319b: Điều kiện đúc Bước 3 — hàm phiếu + chuông + nhắc 24 giờ. Chạy sau T319a.
--
-- Luồng: Kỹ thuật lập (duc_dk_luu) → Gửi (duc_dk_gui) → QLBP Đúc kiểm tra (duc_dk_kiem)
--        → GĐSX duyệt (duc_dk_duyet) → Hiệu lực; lần cũ → Hết hiệu lực.
--        Trả lại ở bước nào cũng về Nháp, giữ ghi chú. Người kiểm / duyệt ≠ người lập.
-- Chuông nguồn 'dieu_kien_duc', khoá 'dkd:<id>:<việc>'. Chờ > 24 giờ nhắc lại mỗi 24 giờ (cron duc_dk_nhac).

-- ── Hàm phụ ────────────────────────────────────────────────────────────────
create or replace function public.duc_dk_ten(p_uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(full_name, ''), nullif(username, ''), email, '') from user_roles where user_id = p_uid;
$$;

create or replace function public.duc_dk_loai_may(p_ma_may text)   -- 'nhom' | 'kem' | null
returns text language sql stable security definer set search_path = public as $$
  select case loai_may when 'Đúc nhôm' then 'nhom' when 'Đúc kẽm' then 'kem' end from master_machines where ma_may = p_ma_may;
$$;

create or replace function public.duc_dk_ds_kiem()
returns uuid[] language sql stable security definer set search_path = public as $$
  select cv_pd_ds_role(array['quan_ly_bo_phan'], 'Đúc');
$$;

create or replace function public.duc_dk_ds_duyet()
returns uuid[] language sql stable security definer set search_path = public as $$
  select cv_pd_ds_role(array['giam_doc_sx'], null);
$$;

-- Quyền người đang đăng nhập (giao diện hiện nút)
create or replace function public.duc_dk_quyen()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('lap', duc_dk_la_ky_thuat(),
                            'kiem', coalesce(auth.uid() = any(duc_dk_ds_kiem()), false),
                            'duyet', has_role('giam_doc_sx'),
                            'admin', has_role('admin'));
$$;

create or replace function public.duc_dk_ls(p_id bigint, p_viec text, p_ghi_chu text default null)
returns void language sql security definer set search_path = public as $$
  update duc_dk_phieu set
    lich_su = lich_su || jsonb_build_array(jsonb_build_object('viec', p_viec, 'nguoi', duc_dk_ten(auth.uid()),
                                                              'luc', now(), 'ghi_chu', nullif(btrim(coalesce(p_ghi_chu, '')), ''))),
    updated_at = now()
  where id = p_id;
$$;

create or replace function public.duc_dk_nhan(p_id bigint)   -- "DC 5 · EXE-OUT-01 (lần 2)"
returns text language sql stable security definer set search_path = public as $$
  select ma_may || ' · ' || ma_sp || ' (lần ' || lan || ')' from duc_dk_phieu where id = p_id;
$$;

-- Danh sách thiếu / sai trước khi Gửi (rỗng = gửi được). Giao diện gọi để hiện trước.
create or replace function public.duc_dk_kiem_thieu(p_id bigint)
returns text[] language plpgsql stable security definer set search_path = public as $$
declare
  p record; v_loai text; r record; v_loi text[] := '{}'; v_pe01 numeric; v_dc record; v_phi numeric;
begin
  select * into p from duc_dk_phieu where id = p_id;
  if not found then return array['Không tìm thấy phiếu']; end if;
  v_loai := duc_dk_loai_may(p.ma_may);
  if v_loai is null then return array['Máy ' || p.ma_may || ' chưa đặt loại Đúc nhôm / Đúc kẽm']; end if;
  if p.lan > 1 and nullif(btrim(coalesce(p.ly_do, '')), '') is null then v_loi := v_loi || 'Lý do ban hành lần mới'::text; end if;
  if cardinality(p.anh) = 0 then v_loi := v_loi || 'Ảnh màn hình cài đặt máy (ít nhất 1)'::text; end if;

  -- Thông số ★ (và thông số phụ thuộc khi thông số gốc = Có)
  for r in
    select t.*, g.chuan, g.gia_tri_chu from duc_dk_thong_so t
      left join duc_dk_gia_tri g on g.id_phieu = p_id and g.ma_ts = t.ma_ts
    where t.hien and t.ap_dung in ('ca_hai', v_loai)
      and case when t.phu_thuoc is null
               then (case v_loai when 'nhom' then t.bat_buoc_nhom else t.bat_buoc_kem end)
               else exists (select 1 from duc_dk_gia_tri g2 where g2.id_phieu = p_id and g2.ma_ts = t.phu_thuoc and g2.gia_tri_chu = 'co') end
    order by t.nhom, t.thu_tu
  loop
    if (r.kieu = 'so' and r.chuan is null)
       or (r.kieu = 'chu' and nullif(btrim(coalesce(r.gia_tri_chu, '')), '') is null)
       or (r.kieu = 'co_khong' and coalesce(r.gia_tri_chu, '') not in ('co', 'khong'))
       or (r.kieu = 'chon_nvl' and p.ma_nvl is null) then
      v_loi := v_loi || (r.ma_ts || ' ' || r.ten);
    end if;
  end loop;

  -- Dụng cụ bắt buộc: Nhôm DT + OL, Kẽm PK + VP
  for r in select unnest(case v_loai when 'nhom' then array['DT', 'OL'] else array['PK', 'VP'] end) l loop
    if not exists (select 1 from duc_dk_dung_cu where id_phieu = p_id and loai = r.l) then
      v_loi := v_loi || ('Dụng cụ ' || case r.l when 'DT' then 'Đầu típ' when 'OL' then 'Ống liệu'
                                               when 'PK' then 'Piston kẽm' else 'Vòi phun' end);
    end if;
  end loop;
  -- Dụng cụ dùng được trên máy này + Φ đầu típ = Φ ống liệu = PE01
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
end $$;

-- Gửi chuông theo trạng thái hiện tại của phiếu
create or replace function public.duc_dk_bao(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare p record; v_nhan text;
begin
  select * into p from duc_dk_phieu where id = p_id;
  if not found then return; end if;
  v_nhan := duc_dk_nhan(p_id);
  if p.trang_thai = 'cho_kiem' then
    perform cv_pd_gui(duc_dk_ds_kiem(), 'dieu_kien_duc', 'can_duyet', 'dkd:' || p_id || ':cho_kiem',
      'dieu-kien-duc.html?id=' || p_id, 'Cần kiểm tra điều kiện đúc: ' || v_nhan, true);
  elsif p.trang_thai = 'cho_duyet' then
    perform cv_pd_gui(duc_dk_ds_duyet(), 'dieu_kien_duc', 'can_duyet', 'dkd:' || p_id || ':cho_duyet',
      'dieu-kien-duc.html?id=' || p_id, 'Cần duyệt điều kiện đúc: ' || v_nhan, true);
  end if;
end $$;

-- ── 1) Lập / sửa nháp ──────────────────────────────────────────────────────
-- p_dung_cu: {"DT":"DT-060-01","OL":"OL-060-01"}
-- p_gia_tri: {"PE02":0.3, "NT09":"Chất A", "PT01":"co", "PE03":{"chuan":2.5,"ghi_chu":"..."}}
create or replace function public.duc_dk_luu(
  p_id bigint, p_ma_sp text, p_ma_may text, p_ly_do text, p_ma_nvl text,
  p_dung_cu jsonb, p_gia_tri jsonb, p_anh text[], p_tep text[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  p record; v_id bigint; v_lan int; v_loai text; k text; v jsonb; t record;
  v_chuan numeric; v_chu text; v_gc text; v_nvl text := nullif(btrim(coalesce(p_ma_nvl, '')), ''); u record;
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

  -- Giá trị thông số
  delete from duc_dk_gia_tri where id_phieu = v_id;
  for k, v in select * from jsonb_each(coalesce(p_gia_tri, '{}')) loop
    select * into t from duc_dk_thong_so where ma_ts = k;
    if not found then raise exception 'Thông số % không có trong danh mục.', k; end if;
    v_chuan := null; v_chu := null; v_gc := null;
    if jsonb_typeof(v) = 'object' then
      v_gc := nullif(btrim(coalesce(v->>'ghi_chu', '')), '');
      v_chu := nullif(btrim(coalesce(v->>'chu', '')), '');
      if jsonb_typeof(v->'chuan') = 'number' then v_chuan := (v->>'chuan')::numeric;
      elsif nullif(btrim(coalesce(v->>'chuan', '')), '') is not null then v_chu := coalesce(v_chu, btrim(v->>'chuan')); end if;
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
    elsif t.kieu = 'co_khong' then
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
    if v_chuan is not null or v_chu is not null or v_gc is not null then
      insert into duc_dk_gia_tri (id_phieu, ma_ts, chuan, gia_tri_chu, ghi_chu) values (v_id, k, v_chuan, v_chu, v_gc);
    end if;
  end loop;

  -- Dụng cụ
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
end $$;

-- ── 2) Gửi ─────────────────────────────────────────────────────────────────
create or replace function public.duc_dk_gui(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p record; v_thieu text[];
begin
  if not duc_dk_la_ky_thuat() then raise exception '⛔ Chỉ bộ phận Kỹ thuật (hoặc admin) gửi phiếu.' using errcode = '42501'; end if;
  select * into p from duc_dk_phieu where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  if p.trang_thai <> 'nhap' then raise exception 'Phiếu không còn là nháp.'; end if;
  v_thieu := duc_dk_kiem_thieu(p_id);
  if cardinality(v_thieu) > 0 then raise exception 'Chưa gửi được — thiếu / sai: %', array_to_string(v_thieu, '; '); end if;
  update duc_dk_phieu set trang_thai = 'cho_kiem', gui_luc = now(), cho_tu = now(),
    nguoi_kiem = null, kiem_luc = null, nguoi_duyet = null, duyet_luc = null, updated_at = now()
  where id = p_id;
  perform duc_dk_ls(p_id, 'gui');
  perform cv_pd_xong('dkd:' || p_id || ':tra_lai', false);
  perform duc_dk_bao(p_id);
  return jsonb_build_object('ok', true, 'trang_thai', 'cho_kiem');
end $$;

-- ── 3) Kiểm tra (QLBP Đúc) ─────────────────────────────────────────────────
create or replace function public.duc_dk_kiem(p_id bigint, p_dong_y boolean, p_ghi_chu text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p record; v_gc text := nullif(btrim(coalesce(p_ghi_chu, '')), '');
begin
  select * into p from duc_dk_phieu where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  if p.trang_thai <> 'cho_kiem' then raise exception 'Phiếu không còn chờ kiểm tra.'; end if;
  if not (auth.uid() = any(duc_dk_ds_kiem())) then
    raise exception '⛔ Chỉ QLBP Đúc kiểm tra phiếu điều kiện đúc.' using errcode = '42501';
  end if;
  if auth.uid() = p.nguoi_lap then raise exception '⛔ Người lập không tự kiểm tra phiếu của mình.' using errcode = '42501'; end if;
  if not coalesce(p_dong_y, false) and v_gc is null then raise exception 'Ghi lý do trả lại.'; end if;
  perform cv_pd_xong('dkd:' || p_id || ':cho_kiem', false);
  update duc_dk_phieu set nguoi_kiem = auth.uid(), kiem_luc = now(), ghi_chu_kiem = v_gc,
    trang_thai = case when p_dong_y then 'cho_duyet' else 'nhap' end,
    cho_tu = case when p_dong_y then now() else null end, updated_at = now()
  where id = p_id;
  perform duc_dk_ls(p_id, case when p_dong_y then 'kiem_dong_y' else 'kiem_tra_lai' end, v_gc);
  if p_dong_y then
    perform duc_dk_bao(p_id);
  else
    perform cv_pd_gui(array[p.nguoi_lap], 'dieu_kien_duc', 'tu_choi_duyet', 'dkd:' || p_id || ':tra_lai',
      'dieu-kien-duc.html?id=' || p_id, '↩ QLBP Đúc trả lại điều kiện đúc ' || duc_dk_nhan(p_id) || ' — ' || v_gc, true);
  end if;
  return jsonb_build_object('ok', true, 'trang_thai', case when p_dong_y then 'cho_duyet' else 'nhap' end);
end $$;

-- ── 4) Duyệt (GĐSX) ────────────────────────────────────────────────────────
create or replace function public.duc_dk_duyet(p_id bigint, p_dong_y boolean, p_ghi_chu text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p record; v_gc text := nullif(btrim(coalesce(p_ghi_chu, '')), ''); v_cu bigint;
begin
  select * into p from duc_dk_phieu where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  if p.trang_thai <> 'cho_duyet' then raise exception 'Phiếu không còn chờ duyệt.'; end if;
  if not has_role('giam_doc_sx') then raise exception '⛔ Chỉ GĐSX duyệt phiếu điều kiện đúc.' using errcode = '42501'; end if;
  if auth.uid() = p.nguoi_lap then raise exception '⛔ Người lập không tự duyệt phiếu của mình.' using errcode = '42501'; end if;
  if not coalesce(p_dong_y, false) and v_gc is null then raise exception 'Ghi lý do trả lại.'; end if;
  perform cv_pd_xong('dkd:' || p_id || ':cho_duyet', false);

  if not p_dong_y then
    update duc_dk_phieu set nguoi_duyet = auth.uid(), duyet_luc = now(), ghi_chu_duyet = v_gc,
      trang_thai = 'nhap', cho_tu = null, updated_at = now() where id = p_id;
    perform duc_dk_ls(p_id, 'duyet_tra_lai', v_gc);
    perform cv_pd_gui(array[p.nguoi_lap], 'dieu_kien_duc', 'tu_choi_duyet', 'dkd:' || p_id || ':tra_lai',
      'dieu-kien-duc.html?id=' || p_id, '↩ GĐSX trả lại điều kiện đúc ' || duc_dk_nhan(p_id) || ' — ' || v_gc, true);
    return jsonb_build_object('ok', true, 'trang_thai', 'nhap');
  end if;

  -- Lần đang hiệu lực → hết hiệu lực (trước, để không vướng index 1 hiệu lực)
  update duc_dk_phieu set trang_thai = 'het_hieu_luc', het_hieu_luc_luc = now(), updated_at = now()
  where ma_sp = p.ma_sp and ma_may = p.ma_may and trang_thai = 'hieu_luc' and id <> p_id
  returning id into v_cu;
  if v_cu is not null then perform duc_dk_ls(v_cu, 'het_hieu_luc', 'Thay bằng lần ' || p.lan); end if;
  update duc_dk_phieu set nguoi_duyet = auth.uid(), duyet_luc = now(), ghi_chu_duyet = v_gc,
    trang_thai = 'hieu_luc', hieu_luc_tu = now(), cho_tu = null, can_cap_nhat = false, updated_at = now()
  where id = p_id;
  perform duc_dk_ls(p_id, 'duyet_dong_y', v_gc);
  -- (Bước 7 sẽ ghi Chuẩn sang duc_thay_doi_chuan ở đây)
  perform cv_pd_gui(array[p.nguoi_lap] || duc_dk_ds_kiem(), 'dieu_kien_duc', 'da_duyet', 'dkd:' || p_id || ':hieu_luc',
    'dieu-kien-duc.html?id=' || p_id, '✅ Điều kiện đúc ' || duc_dk_nhan(p_id) || ' đã hiệu lực', false);
  return jsonb_build_object('ok', true, 'trang_thai', 'hieu_luc');
end $$;

-- ── 5) Lần mới: chép 1 lần đã ban hành thành nháp lần kế ──────────────────
create or replace function public.duc_dk_lan_moi(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
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
  insert into duc_dk_gia_tri (id_phieu, ma_ts, chuan, gia_tri_chu, ghi_chu)
    select v_id, ma_ts, chuan, gia_tri_chu, ghi_chu from duc_dk_gia_tri where id_phieu = p_id;
  insert into duc_dk_dung_cu (id_phieu, loai, ma_dung_cu)
    select v_id, loai, ma_dung_cu from duc_dk_dung_cu where id_phieu = p_id;
  perform duc_dk_ls(v_id, 'lan_moi', 'Chép từ lần ' || p.lan);
  return jsonb_build_object('ok', true, 'id', v_id, 'lan', v_lan);
end $$;

-- ── 6) Huỷ nháp ────────────────────────────────────────────────────────────
create or replace function public.duc_dk_huy_nhap(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p record;
begin
  select * into p from duc_dk_phieu where id = p_id for update;
  if not found then raise exception 'Không tìm thấy phiếu.'; end if;
  if p.trang_thai <> 'nhap' then raise exception 'Chỉ huỷ được nháp chưa gửi.'; end if;
  if not (auth.uid() = p.nguoi_lap or has_role('admin')) then
    raise exception '⛔ Chỉ người lập hoặc admin huỷ nháp.' using errcode = '42501';
  end if;
  perform cv_pd_xong('dkd:' || p_id || ':', true);
  delete from duc_dk_phieu where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- ── 7) Nhắc chờ > 24 giờ (cron mỗi giờ :07) ───────────────────────────────
create or replace function public.duc_dk_nhac()
returns int language plpgsql security definer set search_path = public as $$
declare r record; v_khoa text; n int := 0;
begin
  for r in
    select id, trang_thai, cho_tu from duc_dk_phieu
    where trang_thai in ('cho_kiem', 'cho_duyet') and cho_tu < now() - interval '23 hours 50 minutes'
  loop
    v_khoa := 'dkd:' || r.id || ':' || r.trang_thai;
    continue when exists (select 1 from cv_thong_bao t where t.khoa = v_khoa
                            and t.created_at >= now() - interval '23 hours 50 minutes');
    perform cv_pd_xong(v_khoa, false);
    perform cv_pd_gui(case r.trang_thai when 'cho_kiem' then duc_dk_ds_kiem() else duc_dk_ds_duyet() end,
      'dieu_kien_duc', 'can_duyet', v_khoa, 'dieu-kien-duc.html?id=' || r.id,
      'Chờ bạn ' || case r.trang_thai when 'cho_kiem' then 'kiểm tra' else 'duyệt' end || ' '
        || greatest(1, floor(extract(epoch from now() - r.cho_tu) / 86400)::int) || ' ngày: điều kiện đúc ' || duc_dk_nhan(r.id),
      true);
    n := n + 1;
  end loop;
  return n;
end $$;

do $$ begin
  perform cron.unschedule('duc_dk_nhac') where exists (select 1 from cron.job where jobname = 'duc_dk_nhac');
  perform cron.schedule('duc_dk_nhac', '7 * * * *', 'select public.duc_dk_nhac();');
end $$;

-- ── Quyền gọi hàm ──────────────────────────────────────────────────────────
revoke execute on function public.duc_dk_ten(uuid), public.duc_dk_loai_may(text), public.duc_dk_ds_kiem(), public.duc_dk_ds_duyet(),
  public.duc_dk_ls(bigint, text, text), public.duc_dk_nhan(bigint), public.duc_dk_bao(bigint), public.duc_dk_nhac()
  from public, anon, authenticated;
revoke execute on function public.duc_dk_quyen(), public.duc_dk_kiem_thieu(bigint),
  public.duc_dk_luu(bigint, text, text, text, text, jsonb, jsonb, text[], text[]),
  public.duc_dk_gui(bigint), public.duc_dk_kiem(bigint, boolean, text), public.duc_dk_duyet(bigint, boolean, text),
  public.duc_dk_lan_moi(bigint), public.duc_dk_huy_nhap(bigint)
  from public, anon;
grant execute on function public.duc_dk_quyen(), public.duc_dk_kiem_thieu(bigint),
  public.duc_dk_luu(bigint, text, text, text, text, jsonb, jsonb, text[], text[]),
  public.duc_dk_gui(bigint), public.duc_dk_kiem(bigint, boolean, text), public.duc_dk_duyet(bigint, boolean, text),
  public.duc_dk_lan_moi(bigint), public.duc_dk_huy_nhap(bigint)
  to authenticated;
