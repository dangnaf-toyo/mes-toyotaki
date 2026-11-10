-- =============================================================================
-- T232 (10/11/2026): Sự cố Đúc "không đóng được" — 4 việc
--   1. duc_su_co_dieu_kien_dong(ids): mỗi sự cố đang mở còn thiếu bước gì mới đóng
--      được (cùng quy tắc với duc_resolve_incident: T170/T172/T180/T188/T210) →
--      Dashboard Đúc / mobile hiện "đang chờ ai", nút Xong dẫn tới bước còn thiếu.
--   2. duc_ipqc_nhac_cham(): giao QC quá 60 phút mà IPQC chưa kiểm → chuông cho
--      QC Manager + trưởng ca (1 lần / lần giao; tự tắt khi IPQC kiểm xong).
--   3. Mỗi lần bấm Xong bị từ chối → ghi duc_su_co_nhat_ky su_kien 'tu_choi_dong'.
--   4. duc_ipqc_don_checkpoint_mo_coi(): phiếu IPQC chờ kiểm của dòng ca đã mất
--      (> 24h, quá khung T204 nhận lại) → het_hieu_luc.
--   Lịch pg_cron 'duc_ipqc_nhac_cham' mỗi 10 phút chạy (2) + (4).
-- Bối cảnh: 09–10/11 có ~45/63 lần bấm Xong bị từ chối (chưa giao QC / IPQC
--   chưa kiểm / chưa khai can thiệp khuôn); DC 10 chờ IPQC 13h sau giao QC;
--   8 phiếu IPQC mồ côi (dòng ca bị xoá khi máy đổi SP / dừng → T204 không chuyển).
-- Trạng thái: chạy prod (fgghikpzcxjqzahfiiil) + staging (jcjbleugnclzsghfpmvk) 10/11/2026.
-- =============================================================================

-- 0. Helper IPQC theo tham số (dùng được cho sự cố phụ T178). Logic giữ nguyên
--    duc_ipqc_trang_thai_su_co (T170/T174), thêm 'luc' = giờ lần kiểm mới nhất.
create or replace function public.duc_ipqc_trang_thai_su_co_ts(
  p_ma_may text, p_loai text, p_gio timestamptz, p_id_su_co text)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare v_kq text; v_luc timestamptz;
begin
  if p_gio is null
     or not (left(coalesce(p_loai, ''), 2) = any(array['A1','A2','A3','B1','B2','C3','E1','F1'])) then
    return jsonb_build_object('can_ipqc', false, 'ok', true);
  end if;
  select cp.ket_qua, cp.thoi_diem_kiem_thuc_te into v_kq, v_luc from duc_ipqc_checkpoint cp
   where cp.trang_thai = 'da_kiem' and cp.loai_kiem in ('sau_su_co', 'doi_khuon')
     and ((p_id_su_co is not null and cp.id_su_co_goc = p_id_su_co)
          or (cp.ma_may = p_ma_may and cp.thoi_diem_kiem_thuc_te >= p_gio))
   order by cp.thoi_diem_kiem_thuc_te desc nulls last
   limit 1;
  return jsonb_build_object('can_ipqc', true, 'ok', coalesce(v_kq in ('OK', 'CANH_BAO'), false),
                            'ket_qua', v_kq, 'id_su_co', p_id_su_co, 'luc', v_luc);
end $function$;
revoke execute on function public.duc_ipqc_trang_thai_su_co_ts(text, text, timestamptz, text) from public, anon, authenticated;

create or replace function public.duc_ipqc_trang_thai_su_co(p_id_dong text)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare v record;
begin
  select ma_may, open_loai_su_co, open_gio_phat_sinh, open_id_su_co into v
    from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then return jsonb_build_object('can_ipqc', false, 'ok', true); end if;
  return duc_ipqc_trang_thai_su_co_ts(v.ma_may, v.open_loai_su_co, v.open_gio_phat_sinh, v.open_id_su_co);
end $function$;
revoke execute on function public.duc_ipqc_trang_thai_su_co(text) from public, anon, authenticated;

-- 1. Điều kiện đóng từng sự cố đang mở (chỉ đọc). Trả {id_su_co: {buoc, thong_bao, cho_tu, ...}}
--    buoc: duoc_dong | can_thiep | giao_qc | cho_ipqc | giao_lai | xu_ly_lai
create or replace function public.duc_su_co_dieu_kien_dong(p_ids text[])
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare
  s record; v_ipqc jsonb; v_ct text; v_ct_gq text; v_giao timestamptz; v_lan int;
  v_kq text; v_luc timestamptz; v_buoc text; v_tb text; v_cho_tu timestamptz;
  v_out jsonb := '{}'::jsonb;
  v_quyen_vuot boolean := public.has_role('admin', 'qc_manager')
    or exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role = 'quan_ly_bo_phan'
               and 'Thiết bị' = any(coalesce(ur.bo_phan_phu_trach, '{}')));
begin
  if auth.uid() is null or p_ids is null then return v_out; end if;
  for s in
    select c.ma_may, c.open_id_su_co id, c.open_loai_su_co loai, c.open_gio_phat_sinh gio
      from duc_ca_hien_tai c
     where c.open_id_su_co = any(p_ids) and c.open_gio_phat_sinh is not null
    union all
    select c.ma_may, t.id_su_co, t.loai_su_co, t.gio_phat_sinh
      from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong
     where t.id_su_co = any(p_ids)
  loop
    v_buoc := null; v_tb := null; v_cho_tu := null; v_ct := null; v_ct_gq := null;
    v_ipqc := duc_ipqc_trang_thai_su_co_ts(s.ma_may, s.loai, s.gio, s.id);
    v_kq := v_ipqc->>'ket_qua';
    v_luc := (v_ipqc->>'luc')::timestamptz;
    select max(g.thoi_diem), count(*) into v_giao, v_lan from duc_su_co_giao_qc g where g.id_su_co = s.id;
    if left(coalesce(s.loai, ''), 2) in ('A2', 'B1', 'F1') then
      v_ct := duc_khuon_ct_kiem('xlbt', s.id, 'dong');
      v_ct_gq := duc_khuon_ct_kiem('xlbt', s.id, 'giao_qc');
    end if;

    if v_ct is not null then                                   -- T210: chặn cả người có quyền vượt
      v_buoc := 'can_thiep'; v_tb := v_ct;
    elsif not (v_ipqc->>'can_ipqc')::boolean then
      v_buoc := 'duoc_dong';
    elsif (v_ipqc->>'ok')::boolean then
      v_buoc := 'duoc_dong';
      v_tb := 'IPQC kiểm ' || case v_kq when 'OK' then 'OK' else 'Cảnh báo' end || ' lúc '
              || to_char(v_luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ' — bấm ✓ Xong để kết thúc sự cố.';
    elsif v_giao is null and s.gio >= duc_moc_giao_qc() then   -- T180
      if v_ct_gq is not null then
        v_buoc := 'can_thiep'; v_tb := v_ct_gq;
      else
        v_buoc := 'giao_qc';
        v_tb := case when v_kq = 'NG' then 'IPQC kiểm NG lúc ' || to_char(v_luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI') || '. ' else '' end
                || 'Chưa giao QC — xử lý xong, lấy mẫu rồi bấm "📦 Hoàn thành mẫu & giao QC" để IPQC kiểm.';
      end if;
    elsif v_giao is not null and (v_luc is null or v_luc <= v_giao) then
      v_buoc := 'cho_ipqc'; v_cho_tu := v_giao;
      v_tb := 'Đã giao QC lúc ' || to_char(v_giao at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM')
              || ' — đang chờ IPQC kiểm. IPQC kiểm OK hoặc Cảnh báo thì bấm ✓ Xong.';
    elsif v_giao is not null then                              -- IPQC kiểm NG sau lần giao gần nhất
      if v_ct_gq is not null then
        v_buoc := 'can_thiep'; v_tb := v_ct_gq;
      else
        v_buoc := 'giao_lai';
        v_tb := 'IPQC kiểm NG lúc ' || to_char(v_luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM')
                || ' — xử lý tiếp, lấy mẫu mới rồi bấm "Giao lại" để IPQC kiểm lại.';
      end if;
    elsif v_kq is null then                                    -- sự cố trước mốc giao QC
      v_buoc := 'cho_ipqc'; v_cho_tu := s.gio;
      v_tb := 'Đang chờ IPQC kiểm sau sự cố. IPQC kiểm OK hoặc Cảnh báo thì bấm ✓ Xong.';
    else
      v_buoc := 'xu_ly_lai';
      v_tb := 'IPQC kiểm NG lúc ' || to_char(v_luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM')
              || ' — xử lý tiếp rồi nhờ IPQC kiểm lại.';
    end if;

    v_out := v_out || jsonb_build_object(s.id, jsonb_build_object(
      'buoc', v_buoc, 'thong_bao', v_tb, 'cho_tu', v_cho_tu, 'ket_qua_ipqc', v_kq,
      'lan_giao', v_lan, 'duoc_vuot', v_quyen_vuot and v_ct is null and v_buoc <> 'duoc_dong'));
  end loop;
  return v_out;
end $function$;
revoke execute on function public.duc_su_co_dieu_kien_dong(text[]) from public, anon;
grant execute on function public.duc_su_co_dieu_kien_dong(text[]) to authenticated;

-- 3. Ghi lần bấm Xong bị từ chối.
alter table public.duc_su_co_nhat_ky drop constraint if exists duc_su_co_nhat_ky_su_kien_check;
alter table public.duc_su_co_nhat_ky add constraint duc_su_co_nhat_ky_su_kien_check
  check (su_kien = any (array['mo','cap_nhat','chuyen_ca','dong','sua_sau_dong','xoa','giao_qc','tu_choi_dong']));

create or replace function public.duc_resolve_incident_x(p_id_dong text, p_id_su_co text, p_gio_tro_lai timestamptz,
  p_bonus_note text, p_truong_ca text, p_user text)
returns jsonb
language plpgsql security definer
set search_path to 'public'
as $function$
declare v_chinh text; v_xuong text; r jsonb; v_id text;
begin
  select open_id_su_co into v_chinh from duc_ca_hien_tai where id_dong = p_id_dong;
  if p_id_su_co is null or p_id_su_co = coalesce(v_chinh, '') then
    r := duc_resolve_incident(p_id_dong, p_gio_tro_lai, p_bonus_note, p_truong_ca, p_user);
  else
    v_xuong := duc_su_co_doi_cho(p_id_dong, p_id_su_co);
    if v_xuong is null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố ' || p_id_su_co || ' đang mở trên dòng này — tải lại trang.'); end if;
    r := duc_resolve_incident(p_id_dong, p_gio_tro_lai, p_bonus_note, p_truong_ca, p_user);
    if not coalesce((r->>'ok')::boolean, false) then perform duc_su_co_doi_cho(p_id_dong, v_xuong); end if;
  end if;

  -- T232: ghi lại lần bị từ chối để thống kê điểm nghẽn (lỗi ghi không được chặn kết quả).
  v_id := coalesce(p_id_su_co, v_chinh);
  if not coalesce((r->>'ok')::boolean, false) and v_id is not null then
    begin
      insert into duc_su_co_nhat_ky (id_su_co, su_kien, id_dong, ngay, ca, du_lieu, nguoi, nguoi_uid, nguon)
      select v_id, 'tu_choi_dong', p_id_dong, c.ngay, c.ca,
             jsonb_build_object(
               'ly_do', case when (r->>'chan_ct')::boolean then 'can_thiep'
                             when (r->>'chan_giao_qc')::boolean then 'giao_qc'
                             when (r->>'chan_ipqc')::boolean then 'ipqc' else 'khac' end,
               'loi', r->>'error', 'ket_qua_ipqc', r->>'ket_qua_ipqc', 'gio_tro_lai', p_gio_tro_lai),
             coalesce(nullif(duc_su_co_nguoi_hien_tai(), ''), p_user, ''), auth.uid(), '/rpc/duc_resolve_incident_x'
        from duc_ca_hien_tai c where c.id_dong = p_id_dong;
    exception when others then raise warning 'duc_resolve_incident_x ghi tu_choi_dong: %', sqlerrm;
    end;
  end if;
  return r;
end $function$;

-- 2. Nhắc IPQC kiểm chậm.
create or replace function public.duc_ipqc_nhac_cham()
returns integer
language plpgsql security definer
set search_path to 'public'
as $function$
declare s record; v_n int := 0; v_phut int; v_khoa text; v_nd text; v_td record;
begin
  select * into v_td from duc_ipqc_tam_dung order by id desc limit 1;
  if found and v_td.thoi_diem_bat_dau is null then return 0; end if;   -- IPQC đang tạm dừng ngày làm việc
  for s in
    with mo as (
      select c.ma_may, c.open_id_su_co id, c.open_loai_su_co loai, c.open_gio_phat_sinh gio
        from duc_ca_hien_tai c where c.open_id_su_co is not null and c.open_gio_phat_sinh is not null
      union all
      select c.ma_may, t.id_su_co, t.loai_su_co, t.gio_phat_sinh
        from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong where t.id_su_co is not null
    )
    select mo.*, g.giao, g.lan from mo
      cross join lateral (select max(thoi_diem) giao, count(*) lan from duc_su_co_giao_qc where id_su_co = mo.id) g
     where g.giao is not null and g.giao < now() - interval '60 minutes'
  loop
    if exists (select 1 from duc_ipqc_checkpoint cp
                where cp.trang_thai = 'da_kiem' and cp.loai_kiem in ('sau_su_co', 'doi_khuon')
                  and (cp.id_su_co_goc = s.id or (cp.ma_may = s.ma_may and cp.thoi_diem_kiem_thuc_te >= s.gio))
                  and cp.thoi_diem_kiem_thuc_te > s.giao) then
      continue;
    end if;
    -- khoá bắt đầu bằng 'giao_qc:<máy>:' → duc_giao_qc_tb_xong_cp_trg tự tắt chuông khi IPQC kiểm xong
    v_khoa := 'giao_qc:' || s.ma_may || ':' || s.id || ':cham:' || to_char(s.giao at time zone 'UTC', 'YYYYMMDDHH24MISS');
    if exists (select 1 from cv_thong_bao where khoa in (v_khoa || ':qc', v_khoa || ':tc')) then continue; end if;
    v_phut := floor(extract(epoch from now() - s.giao) / 60);
    v_nd := '⏰ Máy ' || s.ma_may || ' đã giao mẫu sau sự cố ' || coalesce(left(s.loai, 2), '') || ' (' || s.id || ') lúc '
            || to_char(s.giao at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM')
            || case when s.lan > 1 then ' (lần ' || s.lan || ')' else '' end
            || ' — đã ' || case when v_phut >= 120 then (v_phut / 60) || ' giờ ' || (v_phut % 60) || ' phút' else v_phut || ' phút' end
            || ' IPQC chưa kiểm, máy chưa được chạy lại.';
    v_n := v_n + cv_pd_gui(cv_pd_ds_role(array['qc_manager']), 'ipqc', 'giao_mau_cham', v_khoa || ':qc', 'ipqc.html', v_nd, true);
    v_n := v_n + cv_pd_gui(cv_pd_ds_role(array['truong_ca']), 'ipqc', 'giao_mau_cham', v_khoa || ':tc', 'duc-dashboard.html', v_nd, true);
  end loop;
  return v_n;
end $function$;
revoke execute on function public.duc_ipqc_nhac_cham() from public, anon, authenticated;

-- 4. Dọn phiếu IPQC chờ kiểm mồ côi (dòng ca không còn, quá 24h — T204 chỉ nhận lại trong 24h).
create or replace function public.duc_ipqc_don_checkpoint_mo_coi()
returns integer
language plpgsql security definer
set search_path to 'public'
as $function$
declare v_n int;
begin
  update duc_ipqc_checkpoint cp
     set trang_thai = 'het_hieu_luc',
         ghi_chu = concat_ws(E'\n', nullif(cp.ghi_chu, ''), '[T232: dòng ca ' || cp.id_dong || ' không còn (máy đổi SP / dừng) — tự hết hiệu lực]')
   where cp.trang_thai = 'cho_kiem' and cp.id_dong is not null
     and cp.thoi_diem_tao < now() - interval '24 hours'
     and not exists (select 1 from duc_ca_hien_tai c where c.id_dong = cp.id_dong)
     and not exists (select 1 from duc_ipqc_inspection_session ss where ss.checkpoint_id = cp.id_checkpoint and ss.completed_at is null)
     and (cp.id_su_co_goc is null
          or (not exists (select 1 from duc_ca_hien_tai c where c.open_id_su_co = cp.id_su_co_goc)
              and not exists (select 1 from duc_su_co_mo_them t where t.id_su_co = cp.id_su_co_goc)));
  get diagnostics v_n = row_count;
  return v_n;
end $function$;
revoke execute on function public.duc_ipqc_don_checkpoint_mo_coi() from public, anon, authenticated;

-- Lịch chạy (pg_cron) mỗi 10 phút.
select cron.unschedule(jobid) from cron.job where jobname = 'duc_ipqc_nhac_cham';
select cron.schedule('duc_ipqc_nhac_cham', '*/10 * * * *',
  'select public.duc_ipqc_nhac_cham(); select public.duc_ipqc_don_checkpoint_mo_coi();');
