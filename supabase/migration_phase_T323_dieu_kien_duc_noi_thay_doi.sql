-- T323: Điều kiện đúc Bước 7 — nối phiếu ĐK đúc với Điểm thay đổi Đúc (T307).
-- • Phiếu Hiệu lực → Chuẩn các thông số số có mã mục thay đổi (duc_dk_thong_so.ma_muc_td) ghi vào duc_thay_doi_chuan,
--   nguồn 'phieu_dk' (id_phieu = duc_dk_phieu.id), ghi đè chuẩn "lần đầu"/"đã duyệt" đang có.
-- • Giữ quy tắc ±ngưỡng của T307, gốc so = Chuẩn của phiếu: thay đổi vượt ngưỡng đã duyệt KHÔNG đổi chuẩn nguồn
--   'phieu_dk' (lần sau vẫn so với phiếu) → bật duc_dk_phieu.can_cap_nhat + chuông Kỹ thuật "cập nhật phiếu".
-- • Lần mới được duyệt → chuông "cập nhật phiếu" của lần cũ tự tắt.
-- Chạy lại được.

-- 0) Nguồn chuẩn mới
alter table public.duc_thay_doi_chuan drop constraint if exists duc_thay_doi_chuan_nguon_check;
alter table public.duc_thay_doi_chuan add constraint duc_thay_doi_chuan_nguon_check
  check (nguon in ('ban_dau', 'da_duyet', 'phieu_dk'));

-- 1) Ghi Chuẩn của phiếu Hiệu lực sang duc_thay_doi_chuan
create or replace function public.duc_dk_ghi_chuan(p_id bigint)
returns int language plpgsql security definer set search_path = public as $$
declare p record; n int;
begin
  select * into p from duc_dk_phieu where id = p_id;
  if not found or p.trang_thai <> 'hieu_luc' then return 0; end if;
  -- Bỏ chuẩn của lần phiếu cũ mà lần này không còn giá trị
  delete from duc_thay_doi_chuan c
   where c.ma_may = p.ma_may and c.ma_sp = p.ma_sp and c.nguon = 'phieu_dk' and c.id_phieu is distinct from p_id;
  insert into duc_thay_doi_chuan (ma_may, ma_sp, ma_muc, gia_tri, nguon, id_phieu, cap_nhat_luc, nguoi)
  select distinct on (t.ma_muc_td) p.ma_may, p.ma_sp, t.ma_muc_td, g.chuan, 'phieu_dk', p_id, now(),
         'Phiếu ĐK đúc lần ' || p.lan
    from duc_dk_gia_tri g
    join duc_dk_thong_so t on t.ma_ts = g.ma_ts
    join duc_thay_doi_mau m on m.ma = t.ma_muc_td and m.kieu_nhap = 'so'
   where g.id_phieu = p_id and t.kieu = 'so' and g.chuan is not null
   order by t.ma_muc_td, t.thu_tu
  on conflict (ma_may, ma_sp, ma_muc) do update
    set gia_tri = excluded.gia_tri, nguon = 'phieu_dk', id_phieu = excluded.id_phieu,
        cap_nhat_luc = now(), nguoi = excluded.nguoi;
  get diagnostics n = row_count;
  return n;
end $$;

-- 2) Thay đổi đã duyệt có mục nằm trên phiếu Hiệu lực → cần cập nhật phiếu
create or replace function public.duc_dk_danh_dau_cap_nhat(p_td bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v record; p record; v_tom text;
begin
  select * into v from duc_thay_doi where id = p_td;
  if not found or v.ma_sp is null then return; end if;
  select * into p from duc_dk_phieu where ma_may = v.ma_may and ma_sp = v.ma_sp and trang_thai = 'hieu_luc';
  if not found then return; end if;
  select string_agg((e->>'ten') || ' ' || coalesce(nullif(e->>'truoc', '') || '→', '→') || coalesce(e->>'sau', '')
                    || coalesce(' ' || nullif(e->>'don_vi', ''), ''), '; ')
    into v_tom
    from jsonb_array_elements(v.chi_tiet) e
   where nullif(e->>'nguoi_duyet', '') is not null
     and exists (select 1 from duc_dk_thong_so t where t.ma_muc_td = e->>'ma');
  if v_tom is null then return; end if;
  update duc_dk_phieu set can_cap_nhat = true,
    lich_su = lich_su || jsonb_build_array(jsonb_build_object('viec', 'can_cap_nhat', 'nguoi', duc_dk_ten(auth.uid()),
                                                              'luc', now(), 'td', p_td, 'ghi_chu', 'TD-' || p_td || ': ' || v_tom)),
    updated_at = now()
  where id = p.id;
  perform cv_pd_gui(cv_pd_ds_bo_phan('Kỹ thuật') || array[p.nguoi_lap], 'dieu_kien_duc', 'cap_nhat_viec',
    'dkd:' || p.id || ':cap_nhat:' || p_td, 'dieu-kien-duc.html?id=' || p.id,
    '📋 Cập nhật phiếu ĐK đúc ' || duc_dk_nhan(p.id) || ' — thay đổi đã duyệt: ' || v_tom, true);
end $$;

-- 3) duc_dk_duyet (T319b) + ghi chuẩn + tắt chuông "cập nhật phiếu" của lần cũ
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
  if v_cu is not null then
    perform duc_dk_ls(v_cu, 'het_hieu_luc', 'Thay bằng lần ' || p.lan);
    perform cv_pd_xong('dkd:' || v_cu || ':cap_nhat', true);
  end if;
  update duc_dk_phieu set nguoi_duyet = auth.uid(), duyet_luc = now(), ghi_chu_duyet = v_gc,
    trang_thai = 'hieu_luc', hieu_luc_tu = now(), cho_tu = null, can_cap_nhat = false, updated_at = now()
  where id = p_id;
  perform duc_dk_ls(p_id, 'duyet_dong_y', v_gc);
  perform duc_dk_ghi_chuan(p_id);   -- Bước 7
  perform cv_pd_gui(array[p.nguoi_lap] || duc_dk_ds_kiem(), 'dieu_kien_duc', 'da_duyet', 'dkd:' || p_id || ':hieu_luc',
    'dieu-kien-duc.html?id=' || p_id, '✅ Điều kiện đúc ' || duc_dk_nhan(p_id) || ' đã hiệu lực', false);
  return jsonb_build_object('ok', true, 'trang_thai', 'hieu_luc');
end $$;

-- 4) duc_td_duyet (T307b): chuẩn nguồn phiếu không bị ghi đè; đánh dấu phiếu cần cập nhật
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
    -- Mục vượt ngưỡng đã được duyệt → giá trị Sau thành chuẩn mới, TRỪ khi chuẩn lấy từ phiếu ĐK đúc (T323)
    insert into duc_thay_doi_chuan (ma_may, ma_sp, ma_muc, gia_tri, nguon, id_phieu, cap_nhat_luc, nguoi)
    select v.ma_may, v.ma_sp, e->>'ma', (e->>'sau')::numeric, 'da_duyet', p_id, now(), v_ten
      from jsonb_array_elements(v.chi_tiet) e
     where coalesce((e->>'vuot')::boolean, false) and v.ma_sp is not null
    on conflict (ma_may, ma_sp, ma_muc) do update
      set gia_tri = excluded.gia_tri, nguon = 'da_duyet', id_phieu = excluded.id_phieu, cap_nhat_luc = now(), nguoi = excluded.nguoi
      where duc_thay_doi_chuan.nguon <> 'phieu_dk';
    perform duc_dk_danh_dau_cap_nhat(p_id);   -- T323
    if v.trang_thai = 'cho_duyet' then
      perform cv_pd_gui(array[v.nguoi_ghi_id], 'thay_doi', 'da_duyet', 'td_ap_dung:' || p_id, 'duc-dashboard.html',
        '✅ Đã duyệt thay đổi ' || v.ma_may || ' · ' || duc_td_tom_tat(v.chi_tiet)
          || ' — chỉnh máy xong bấm "Đã chỉnh" trên Bảng điều khiển Đúc.', true);
    end if;
  end if;
  return jsonb_build_object('ok', true, 'trang_thai', (select trang_thai from duc_thay_doi where id = p_id),
                            'ket_qua_duyet', (select ket_qua_duyet from duc_thay_doi where id = p_id));
end $$;

-- 5) Quyền: 2 hàm phụ chỉ gọi nội bộ
revoke execute on function public.duc_dk_ghi_chuan(bigint), public.duc_dk_danh_dau_cap_nhat(bigint) from public, anon, authenticated;

-- 6) Bù cho phiếu đã Hiệu lực trước T323 (23/11 chưa có phiếu nào)
select public.duc_dk_ghi_chuan(id) from public.duc_dk_phieu where trang_thai = 'hieu_luc';
