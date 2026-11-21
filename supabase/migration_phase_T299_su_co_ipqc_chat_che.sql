-- =============================================================================
-- T299 (21/11/2026): Lý lịch sự cố Đúc phải đủ từ phát sinh → xử lý → IPQC OK mới chạy lại
-- Rà soát 29/10–21/11 (prod): 57/260 sự cố cần IPQC đóng mà không có IPQC OK của chính nó;
-- 107/203 khai giờ trở lại sớm hơn giờ IPQC OK (trung vị ~100 phút); 72/76 F1 tự đóng mất
-- nội dung xử lý; IPQC NG lúc máy đang có sự cố khác không ghi lại.
--   (1) Giờ trở lại không sớm hơn lần IPQC OK/Cảnh báo cho đóng (resolve tự chỉnh; sửa sau
--       đóng thì chặn).
--   (2) IPQC chỉ tính khi: gắn đúng mã sự cố VÀ kiểm sau lần giao QC đầu tiên; hoặc phiếu của
--       sự cố khác / đổi khuôn cùng máy có mẫu giao SAU lúc sự cố phát sinh (và sau lần giao QC
--       đầu của sự cố này nếu có). Hàm chung duc_ipqc_kiem_cua_su_co.
--   (3) F1 chỉ tự đóng khi IPQC OK hợp lệ sau lần giao QC + đủ can thiệp khuôn + có nội dung
--       xử lý & đảm nhiệm; giữ nội dung xử lý, chỉ nối dòng IPQC. Kiểm định kỳ OK không đóng F1.
--       F1 mở do IPQC NG không tự tạo phiếu "sau sự cố" nữa (phiếu tạo lúc giao QC).
--   (4) Giao QC / đóng sự cố bắt buộc có nội dung xử lý + người đảm nhiệm (trừ đóng do đổi SP).
--       duc_giao_qc_x thêm p_noi_dung, p_dam_nhiem; duc_resolve_incident_x thêm p_dam_nhiem.
--   (5) IPQC NG khi máy đang có sự cố khác → ghi sự kiện 'ipqc_ng' vào lý lịch sự cố đó + chuông
--       trưởng ca.
-- Chạy: prod (fgghikpzcxjqzahfiiil) + staging (jcjbleugnclzsghfpmvk).
-- =============================================================================

-- ── Phần 1: sự kiện mới + hàm chung IPQC ────────────────────────────────────
alter table public.duc_su_co_nhat_ky drop constraint if exists duc_su_co_nhat_ky_su_kien_check;
alter table public.duc_su_co_nhat_ky add constraint duc_su_co_nhat_ky_su_kien_check
  check (su_kien = any (array['mo','cap_nhat','chuyen_ca','dong','sua_sau_dong','xoa','giao_qc','tu_choi_dong','ipqc_ng']));

drop function if exists public.duc_ipqc_kiem_cua_su_co(text, timestamptz, text);
create or replace function public.duc_ipqc_kiem_cua_su_co(p_ma_may text, p_gio timestamptz, p_id_su_co text, p_loai text default null)
returns table(id_checkpoint text, ket_qua text, luc timestamptz, id_su_co_kiem text, nguoi_kiem text)
language sql stable security definer
set search_path to 'public'
as $function$
  with g as (select min(x.thoi_diem) dau from duc_su_co_giao_qc x where p_id_su_co is not null and x.id_su_co = p_id_su_co)
  select cp.id_checkpoint, cp.ket_qua, cp.thoi_diem_kiem_thuc_te, cp.id_su_co_goc, cp.nguoi_kiem
    from duc_ipqc_checkpoint cp cross join g
   where p_gio is not null
     and cp.trang_thai = 'da_kiem' and cp.loai_kiem in ('sau_su_co', 'doi_khuon')
     and cp.thoi_diem_kiem_thuc_te is not null
     and (
       -- phiếu của chính sự cố: đã giao QC thì phải kiểm sau lần giao đầu; F1 bắt buộc có giao QC
       -- (phiếu F1 tạo lúc IPQC NG = mẫu trước khi xử lý); sự cố trước mốc giao QC: như cũ.
       (p_id_su_co is not null and cp.id_su_co_goc = p_id_su_co
        and (p_gio < duc_moc_giao_qc()
             or (g.dau is not null and cp.thoi_diem_kiem_thuc_te > g.dau)
             or (g.dau is null and left(coalesce(p_loai, ''), 2) <> 'F1')))
       or
       -- phiếu khác cùng máy: mẫu lấy sau lúc sự cố phát sinh. Mốc mẫu = lần giao QC của sự cố
       -- kia; không có giao: phiếu đổi khuôn = lúc kiểm (mẫu đầu sau đổi khuôn), phiếu khác = lúc tạo.
       (cp.ma_may = p_ma_may and cp.id_su_co_goc is distinct from p_id_su_co
        and cp.thoi_diem_kiem_thuc_te >= p_gio
        and (g.dau is null or cp.thoi_diem_kiem_thuc_te > g.dau)
        and coalesce((select max(g2.thoi_diem) from duc_su_co_giao_qc g2
                       where g2.id_su_co = cp.id_su_co_goc and g2.thoi_diem <= cp.thoi_diem_kiem_thuc_te),
                     case when cp.loai_kiem = 'doi_khuon' then cp.thoi_diem_kiem_thuc_te else cp.thoi_diem_tao end) >= p_gio)
     )
$function$;
revoke execute on function public.duc_ipqc_kiem_cua_su_co(text, timestamptz, text, text) from public, anon, authenticated;

create or replace function public.duc_ipqc_trang_thai_su_co_ts(p_ma_may text, p_loai text, p_gio timestamptz, p_id_su_co text)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare v_kq text; v_luc timestamptz; v_cp text; v_sc text; v_ng text;
begin
  if p_gio is null
     or not (left(coalesce(p_loai, ''), 2) = any(array['A1','A2','A3','B1','B2','C3','E1','F1'])) then
    return jsonb_build_object('can_ipqc', false, 'ok', true);
  end if;
  select k.ket_qua, k.luc, k.id_checkpoint, k.id_su_co_kiem, k.nguoi_kiem into v_kq, v_luc, v_cp, v_sc, v_ng
    from duc_ipqc_kiem_cua_su_co(p_ma_may, p_gio, p_id_su_co, p_loai) k
   order by k.luc desc limit 1;
  return jsonb_build_object('can_ipqc', true, 'ok', coalesce(v_kq in ('OK', 'CANH_BAO'), false),
                            'ket_qua', v_kq, 'id_su_co', p_id_su_co, 'luc', v_luc,
                            'id_checkpoint', v_cp, 'id_su_co_kiem', v_sc, 'nguoi_kiem', v_ng);
end $function$;
revoke execute on function public.duc_ipqc_trang_thai_su_co_ts(text, text, timestamptz, text) from public, anon, authenticated;

-- ── Phần 2: giao QC bắt buộc nội dung xử lý + đảm nhiệm ─────────────────────
drop function if exists public.duc_giao_qc_x(text, text, text);
create or replace function public.duc_giao_qc_x(p_id_dong text, p_id_su_co text, p_user text,
  p_noi_dung text default null, p_dam_nhiem text default null)
returns jsonb
language plpgsql security definer
set search_path to 'public'
as $function$
declare
  c record; v_id text; v_loai text; v_gio timestamptz; v_chinh boolean; v_xl text; v_dn text;
  v_lan_cuoi timestamptz; v_kq_sau text; v_lan int; v_now timestamptz := now(); v_ct_loi text;
  v_nd text := nullif(trim(coalesce(p_noi_dung, '')), ''); v_dn_moi text := nullif(trim(coalesce(p_dam_nhiem, '')), '');
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into c from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found or c.open_gio_phat_sinh is null then
    return jsonb_build_object('ok', false, 'error', 'Dòng này không có sự cố đang mở — tải lại trang.');
  end if;
  v_chinh := p_id_su_co is null or p_id_su_co = coalesce(c.open_id_su_co, '');
  if v_chinh then
    v_id := c.open_id_su_co; v_loai := c.open_loai_su_co; v_gio := c.open_gio_phat_sinh;
    v_xl := c.open_noi_dung_xu_ly; v_dn := c.open_dam_nhiem;
  else
    select id_su_co, loai_su_co, gio_phat_sinh, noi_dung_xu_ly, dam_nhiem into v_id, v_loai, v_gio, v_xl, v_dn
      from duc_su_co_mo_them where id_dong = p_id_dong and id_su_co = p_id_su_co;
    if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố ' || p_id_su_co || ' đang mở — tải lại trang.'); end if;
  end if;
  if v_id is null then return jsonb_build_object('ok', false, 'error', 'Sự cố chưa có mã nên chưa giao QC được.'); end if;
  if not (left(coalesce(v_loai, ''), 2) = any(array['A1','A2','A3','B1','B2','C3','E1','F1'])) then
    return jsonb_build_object('ok', false, 'error', 'Loại sự cố này không cần IPQC xác nhận — bấm "Xong" để đóng.');
  end if;

  -- T210: phải khai can thiệp khuôn (hoặc "không tác động") và được duyệt trước khi giao QC.
  if left(coalesce(v_loai, ''), 2) in ('A2', 'B1', 'F1') then
    v_ct_loi := duc_khuon_ct_kiem('xlbt', v_id, 'giao_qc');
    if v_ct_loi is not null then return jsonb_build_object('ok', false, 'chan_ct', true, 'error', v_ct_loi); end if;
  end if;

  select max(thoi_diem) into v_lan_cuoi from duc_su_co_giao_qc where id_su_co = v_id;
  if v_lan_cuoi is not null then
    select k.ket_qua into v_kq_sau from duc_ipqc_kiem_cua_su_co(c.ma_may, v_gio, v_id) k
     where k.luc > v_lan_cuoi order by k.luc desc limit 1;
    if v_kq_sau is null then
      return jsonb_build_object('ok', false, 'error', 'Đã giao QC lúc '
        || to_char(v_lan_cuoi at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI') || ' — đang chờ IPQC kiểm.');
    end if;
    if v_kq_sau in ('OK', 'CANH_BAO') then
      return jsonb_build_object('ok', false, 'error', 'IPQC đã kiểm đạt (' || v_kq_sau || ') — bấm "Xong" để kết thúc sự cố.');
    end if;
  end if;

  -- T299 (4): ghi nội dung xử lý / đảm nhiệm gửi kèm, rồi bắt buộc đủ cả hai.
  if v_nd is not null or (v_dn_moi is not null and coalesce(trim(v_dn), '') = '') then
    v_xl := concat_ws(E'\n', nullif(trim(coalesce(v_xl, '')), ''), v_nd);
    v_dn := coalesce(nullif(trim(coalesce(v_dn, '')), ''), v_dn_moi);
    if v_chinh then
      update duc_ca_hien_tai set open_noi_dung_xu_ly = v_xl, open_dam_nhiem = v_dn where id_dong = p_id_dong;
    else
      update duc_su_co_mo_them set noi_dung_xu_ly = v_xl, dam_nhiem = v_dn where id_dong = p_id_dong and id_su_co = v_id;
    end if;
  end if;
  if coalesce(trim(v_xl), '') = '' or coalesce(trim(v_dn), '') = '' then
    return jsonb_build_object('ok', false,
      'thieu_xu_ly', coalesce(trim(v_xl), '') = '', 'thieu_dam_nhiem', coalesce(trim(v_dn), '') = '',
      'error', '⛔ Chưa có ' || concat_ws(' và ',
        case when coalesce(trim(v_xl), '') = '' then 'nội dung xử lý' end,
        case when coalesce(trim(v_dn), '') = '' then 'người đảm nhiệm' end) || ' — nhập trước khi giao QC.');
  end if;

  insert into duc_su_co_giao_qc (id_su_co, id_dong, ma_may, thoi_diem, nguoi, nguoi_uid)
  values (v_id, p_id_dong, c.ma_may, v_now, coalesce(nullif(duc_su_co_nguoi_hien_tai(), ''), p_user, ''), auth.uid());
  select count(*) into v_lan from duc_su_co_giao_qc where id_su_co = v_id;

  insert into duc_su_co_nhat_ky (id_su_co, su_kien, id_dong, ngay, ca, du_lieu, nguoi, nguoi_uid, nguon)
  values (v_id, 'giao_qc', p_id_dong, c.ngay, c.ca, jsonb_build_object('lan', v_lan, 'loai', v_loai),
          coalesce(nullif(duc_su_co_nguoi_hien_tai(), ''), p_user, ''), auth.uid(), '/rpc/duc_giao_qc_x');

  -- T182: chuông MES cho mọi tài khoản IPQC — lỗi thông báo không được chặn việc giao QC.
  begin
    perform cv_pd_gui(cv_pd_ds_role(array['ipqc']), 'ipqc', 'giao_mau', 'giao_qc:' || c.ma_may || ':' || v_id, 'ipqc.html',
      '📦 Máy ' || c.ma_may || ' đã hoàn thành mẫu sau sự cố ' || coalesce(v_loai, '') ||
      case when v_lan > 1 then ' (giao lại lần ' || v_lan || ')' else '' end || ' — mời IPQC đến máy kiểm ngay.', true);
  exception when others then raise warning 'duc_giao_qc_x thông báo: %', sqlerrm;
  end;

  if not exists (select 1 from duc_ipqc_checkpoint
                 where id_dong = p_id_dong and trang_thai = 'cho_kiem' and loai_kiem in ('sau_su_co', 'doi_khuon')) then
    begin
      perform duc_request_ipqc_check(p_id_dong, 'sau_su_co', v_id, null);
    exception when unique_violation then null;
    end;
  end if;

  return jsonb_build_object('ok', true, 'id_su_co', v_id, 'thoi_diem', v_now, 'lan', v_lan);
end $function$;
revoke execute on function public.duc_giao_qc_x(text, text, text, text, text) from public, anon;
grant execute on function public.duc_giao_qc_x(text, text, text, text, text) to authenticated;

-- ── Phần 3: đóng sự cố (bấm Xong) ───────────────────────────────────────────
create or replace function public.duc_resolve_incident(p_id_dong text, p_gio_tro_lai timestamptz, p_bonus_note text, p_truong_ca text, p_user text)
returns jsonb
language plpgsql security definer
set search_path to 'public'
as $function$
declare
  v_cht record; v_noi_dung_combined text; v_kq jsonb; v_canh_bao_ipqc boolean := false; v_canh_bao_ipqc_loai text;
  v_ipqc jsonb; v_vuot_ipqc boolean := false; v_ct_loi text; v_doi_sp text := nullif(current_setting('duc.doi_sp_dong', true), '');
  v_luc_ok timestamptz; v_chinh_gio boolean := false;
begin
  select ngay, ca, phuong_an_ca, ma_may, ma_sp, ten_sp, so_khuon, open_loai_su_co,
         open_gio_phat_sinh, open_noi_dung_xu_ly, open_van_de, open_dam_nhiem, open_id_su_co
  into v_cht from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng Ca_hien_tai: ' || p_id_dong); end if;
  if v_cht.open_gio_phat_sinh is null then return jsonb_build_object('ok', false, 'error', 'Dòng này không có sự cố đang mở'); end if;
  if p_gio_tro_lai < v_cht.open_gio_phat_sinh then return jsonb_build_object('ok', false, 'error', 'Giờ trở lại phải sau giờ phát sinh'); end if;
  if p_gio_tro_lai > now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Giờ trở lại không được ở tương lai'); end if;

  if v_doi_sp is null and v_cht.open_id_su_co is not null and left(coalesce(v_cht.open_loai_su_co, ''), 2) in ('A2', 'B1', 'F1') then
    v_ct_loi := duc_khuon_ct_kiem('xlbt', v_cht.open_id_su_co, 'dong');
    if v_ct_loi is not null then return jsonb_build_object('ok', false, 'chan_ct', true, 'error', v_ct_loi); end if;
  end if;

  v_ipqc := duc_ipqc_trang_thai_su_co(p_id_dong);
  v_vuot_ipqc := (v_ipqc->>'can_ipqc')::boolean and not (v_ipqc->>'ok')::boolean
                 and (public.has_role('admin', 'qc_manager')
                      or exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role = 'quan_ly_bo_phan'
                                   and 'Thiết bị' = any(coalesce(ur.bo_phan_phu_trach, '{}'))));
  if (v_ipqc->>'can_ipqc')::boolean and not (v_ipqc->>'ok')::boolean
     and not v_vuot_ipqc and v_doi_sp is null and v_cht.open_id_su_co is not null
     and v_cht.open_gio_phat_sinh >= duc_moc_giao_qc()
     and not exists (select 1 from duc_su_co_giao_qc g where g.id_su_co = v_cht.open_id_su_co) then
    return jsonb_build_object('ok', false, 'chan_giao_qc', true, 'error',
      '⛔ Sự cố ' || v_cht.open_id_su_co || ' chưa bấm "📦 Hoàn thành mẫu & giao QC" (IPQC cũng chưa kiểm OK). Xử lý xong, lấy mẫu thì bấm nút đó để IPQC kiểm; IPQC kiểm OK hoặc Cảnh báo rồi bấm "Xong".');
  end if;

  if (v_ipqc->>'can_ipqc')::boolean and not (v_ipqc->>'ok')::boolean and not v_vuot_ipqc and v_doi_sp is null then
    if not exists (select 1 from duc_ipqc_checkpoint where id_dong = p_id_dong and trang_thai = 'cho_kiem' and loai_kiem in ('sau_su_co', 'doi_khuon')) then
      begin
        perform duc_request_ipqc_check(p_id_dong, 'sau_su_co', v_cht.open_id_su_co, null);
      exception when unique_violation then null;
      end;
    end if;
    return jsonb_build_object('ok', false, 'chan_ipqc', true, 'ket_qua_ipqc', v_ipqc->>'ket_qua', 'error',
      case when v_ipqc->>'ket_qua' is null then
        '⛔ Chưa có kết quả IPQC cho sự cố ' || coalesce(v_cht.open_id_su_co, '') || ' — máy CHƯA được chạy lại. Đã gửi yêu cầu kiểm sang IPQC; khi IPQC kiểm OK hoặc Cảnh báo thì bấm "Xử lý xong" lại.'
      else
        '⛔ IPQC kiểm sự cố ' || coalesce(v_cht.open_id_su_co, '') || ' KHÔNG ĐẠT (' || (v_ipqc->>'ket_qua') || ') — máy CHƯA được chạy lại. Xử lý tiếp rồi nhờ IPQC kiểm lại; chỉ khi lần kiểm mới nhất là OK hoặc Cảnh báo mới kết thúc được sự cố.'
      end);
  end if;

  -- T299 (4): bắt buộc nội dung xử lý + người đảm nhiệm (trừ đóng tự động lúc đổi SP).
  if v_doi_sp is null then
    if coalesce(trim(v_cht.open_noi_dung_xu_ly), '') = '' and coalesce(trim(p_bonus_note), '') = '' then
      return jsonb_build_object('ok', false, 'thieu_xu_ly', true,
        'error', '⛔ Chưa có nội dung xử lý — ghi vào ô "Nội dung xử lý" rồi lưu lại.');
    end if;
    if coalesce(trim(v_cht.open_dam_nhiem), '') = '' then
      return jsonb_build_object('ok', false, 'thieu_dam_nhiem', true,
        'error', '⛔ Chưa có người đảm nhiệm — nhập ô "Đảm nhiệm" rồi lưu lại.');
    end if;
  end if;

  -- T299 (1): máy chỉ chạy lại sau IPQC OK/Cảnh báo → giờ trở lại không sớm hơn lần kiểm đó.
  if (v_ipqc->>'can_ipqc')::boolean and (v_ipqc->>'ok')::boolean and v_doi_sp is null then
    v_luc_ok := (v_ipqc->>'luc')::timestamptz;
    if v_luc_ok is not null and p_gio_tro_lai < v_luc_ok then
      p_gio_tro_lai := v_luc_ok; v_chinh_gio := true;
    end if;
  end if;

  v_noi_dung_combined := coalesce(v_cht.open_noi_dung_xu_ly, '');
  if p_bonus_note is not null and trim(p_bonus_note) <> '' then
    v_noi_dung_combined := case when v_noi_dung_combined <> '' then v_noi_dung_combined || E'\n[BS] ' || trim(p_bonus_note) else trim(p_bonus_note) end;
  end if;
  -- T299 (2): đóng nhờ phiếu IPQC của sự cố khác / đổi khuôn → ghi rõ phiếu nào.
  if (v_ipqc->>'can_ipqc')::boolean and (v_ipqc->>'ok')::boolean and v_doi_sp is null
     and (v_ipqc->>'id_su_co_kiem') is distinct from v_cht.open_id_su_co then
    v_noi_dung_combined := case when v_noi_dung_combined <> '' then v_noi_dung_combined || E'\n' else '' end
      || '[IPQC ' || case v_ipqc->>'ket_qua' when 'OK' then 'OK' else 'Cảnh báo' end || ' lúc '
      || to_char((v_ipqc->>'luc')::timestamptz at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM')
      || ' theo mẫu ' || coalesce('sự cố ' || (v_ipqc->>'id_su_co_kiem'), 'đổi khuôn')
      || coalesce(' — ' || nullif(v_ipqc->>'nguoi_kiem', ''), '') || ']';
  end if;
  if v_vuot_ipqc then
    v_noi_dung_combined := case when v_noi_dung_combined <> '' then v_noi_dung_combined || E'\n' else '' end
      || '[Đóng khi IPQC chưa OK (' || coalesce(v_ipqc->>'ket_qua', 'chưa kiểm') || ') — ' || coalesce(nullif(p_user, ''), p_truong_ca, 'admin/QC Manager') || ']';
  end if;
  if v_doi_sp is not null then
    v_noi_dung_combined := case when v_noi_dung_combined <> '' then v_noi_dung_combined || E'\n' else '' end
      || '[Chưa xử lý xong — kết thúc sự cố lúc đổi sang SP ' || v_doi_sp || '. Khuôn ' || coalesce(nullif(trim(v_cht.so_khuon), ''), '?') || ' xuống máy, tổ khuôn xử lý dứt điểm]';
  end if;

  v_kq := public.duc_su_co_ghi_log_theo_ca(p_id_dong, p_gio_tro_lai, v_noi_dung_combined, v_cht.open_dam_nhiem, p_truong_ca);
  perform duc_clear_incident_open(p_id_dong, coalesce(p_truong_ca, p_user, 'system'));
  return jsonb_build_object(
    'ok', true, 'id_ban_ghi', v_kq->>'last_id', 'id_ban_ghi_list', v_kq->'ids',
    'thoi_gian_dung_phut', (v_kq->>'tong_phut')::int, 'canh_bao_ipqc', v_canh_bao_ipqc,
    'canh_bao_ipqc_loai', v_canh_bao_ipqc_loai, 'id_su_co', v_cht.open_id_su_co, 'vuot_ipqc', v_vuot_ipqc,
    'gio_tro_lai', p_gio_tro_lai, 'chinh_gio', v_chinh_gio);
end;
$function$;

drop function if exists public.duc_resolve_incident_x(text, text, timestamptz, text, text, text);
create or replace function public.duc_resolve_incident_x(p_id_dong text, p_id_su_co text, p_gio_tro_lai timestamptz,
  p_bonus_note text, p_truong_ca text, p_user text, p_dam_nhiem text default null)
returns jsonb
language plpgsql security definer
set search_path to 'public'
as $function$
declare v_chinh text; v_xuong text; r jsonb; v_id text; v_dn text := nullif(trim(coalesce(p_dam_nhiem, '')), '');
begin
  select open_id_su_co into v_chinh from duc_ca_hien_tai where id_dong = p_id_dong;
  if p_id_su_co is not null and p_id_su_co <> coalesce(v_chinh, '') then
    v_xuong := duc_su_co_doi_cho(p_id_dong, p_id_su_co);
    if v_xuong is null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố ' || p_id_su_co || ' đang mở trên dòng này — tải lại trang.'); end if;
  end if;
  -- T299 (4): người đảm nhiệm nhập ở form Xong (chỉ điền khi đang trống)
  if v_dn is not null then
    update duc_ca_hien_tai set open_dam_nhiem = v_dn
     where id_dong = p_id_dong and open_gio_phat_sinh is not null and coalesce(trim(open_dam_nhiem), '') = '';
  end if;
  r := duc_resolve_incident(p_id_dong, p_gio_tro_lai, p_bonus_note, p_truong_ca, p_user);
  if v_xuong is not null and not coalesce((r->>'ok')::boolean, false) then perform duc_su_co_doi_cho(p_id_dong, v_xuong); end if;

  v_id := coalesce(p_id_su_co, v_chinh);
  if not coalesce((r->>'ok')::boolean, false) and v_id is not null then
    begin
      insert into duc_su_co_nhat_ky (id_su_co, su_kien, id_dong, ngay, ca, du_lieu, nguoi, nguoi_uid, nguon)
      select v_id, 'tu_choi_dong', p_id_dong, c.ngay, c.ca,
             jsonb_build_object(
               'ly_do', case when (r->>'chan_ct')::boolean then 'can_thiep'
                             when (r->>'chan_giao_qc')::boolean then 'giao_qc'
                             when (r->>'chan_ipqc')::boolean then 'ipqc'
                             when coalesce((r->>'thieu_xu_ly')::boolean, false) or coalesce((r->>'thieu_dam_nhiem')::boolean, false) then 'thieu_noi_dung'
                             else 'khac' end,
               'loi', r->>'error', 'ket_qua_ipqc', r->>'ket_qua_ipqc', 'gio_tro_lai', p_gio_tro_lai),
             coalesce(nullif(duc_su_co_nguoi_hien_tai(), ''), p_user, ''), auth.uid(), '/rpc/duc_resolve_incident_x'
        from duc_ca_hien_tai c where c.id_dong = p_id_dong;
    exception when others then raise warning 'duc_resolve_incident_x ghi tu_choi_dong: %', sqlerrm;
    end;
  end if;
  return r;
end $function$;
revoke execute on function public.duc_resolve_incident_x(text, text, timestamptz, text, text, text, text) from public, anon;
grant execute on function public.duc_resolve_incident_x(text, text, timestamptz, text, text, text, text) to authenticated;

-- ── Phần 4: điều kiện đóng (giao diện) + nhắc IPQC chậm ─────────────────────
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
    select c.ma_may, c.open_id_su_co id, c.open_loai_su_co loai, c.open_gio_phat_sinh gio,
           c.open_noi_dung_xu_ly xl, c.open_dam_nhiem dn
      from duc_ca_hien_tai c
     where c.open_id_su_co = any(p_ids) and c.open_gio_phat_sinh is not null
    union all
    select c.ma_may, t.id_su_co, t.loai_su_co, t.gio_phat_sinh, t.noi_dung_xu_ly, t.dam_nhiem
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

    if v_ct is not null then
      v_buoc := 'can_thiep'; v_tb := v_ct;
    elsif not (v_ipqc->>'can_ipqc')::boolean then
      v_buoc := 'duoc_dong';
    elsif (v_ipqc->>'ok')::boolean then
      v_buoc := 'duoc_dong';
      v_tb := 'IPQC kiểm ' || case v_kq when 'OK' then 'OK' else 'Cảnh báo' end || ' lúc '
              || to_char(v_luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM')
              || case when (v_ipqc->>'id_su_co_kiem') is distinct from s.id
                      then ' (mẫu ' || coalesce('sự cố ' || (v_ipqc->>'id_su_co_kiem'), 'đổi khuôn') || ')' else '' end
              || ' — bấm ✓ Xong để kết thúc sự cố.';
    elsif v_giao is null and s.gio >= duc_moc_giao_qc() then
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
    elsif v_giao is not null then
      if v_ct_gq is not null then
        v_buoc := 'can_thiep'; v_tb := v_ct_gq;
      else
        v_buoc := 'giao_lai';
        v_tb := 'IPQC kiểm NG lúc ' || to_char(v_luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM')
                || ' — xử lý tiếp, lấy mẫu mới rồi bấm "Giao lại" để IPQC kiểm lại.';
      end if;
    elsif v_kq is null then
      v_buoc := 'cho_ipqc'; v_cho_tu := s.gio;
      v_tb := 'Đang chờ IPQC kiểm sau sự cố. IPQC kiểm OK hoặc Cảnh báo thì bấm ✓ Xong.';
    else
      v_buoc := 'xu_ly_lai';
      v_tb := 'IPQC kiểm NG lúc ' || to_char(v_luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM')
              || ' — xử lý tiếp rồi nhờ IPQC kiểm lại.';
    end if;

    v_out := v_out || jsonb_build_object(s.id, jsonb_build_object(
      'buoc', v_buoc, 'thong_bao', v_tb, 'cho_tu', v_cho_tu, 'ket_qua_ipqc', v_kq,
      'lan_giao', v_lan, 'duoc_vuot', v_quyen_vuot and v_ct is null and v_buoc <> 'duoc_dong',
      'luc_ipqc', case when (v_ipqc->>'can_ipqc')::boolean and (v_ipqc->>'ok')::boolean then v_luc end,
      'thieu_xu_ly', coalesce(trim(s.xl), '') = '', 'thieu_dam_nhiem', coalesce(trim(s.dn), '') = ''));
  end loop;
  return v_out;
end $function$;
revoke execute on function public.duc_su_co_dieu_kien_dong(text[]) from public, anon;
grant execute on function public.duc_su_co_dieu_kien_dong(text[]) to authenticated;

create or replace function public.duc_ipqc_nhac_cham()
returns integer
language plpgsql security definer
set search_path to 'public'
as $function$
declare s record; v_n int := 0; v_phut int; v_khoa text; v_nd text; v_td record;
begin
  select * into v_td from duc_ipqc_tam_dung order by id desc limit 1;
  if found and v_td.thoi_diem_bat_dau is null then return 0; end if;
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
    if exists (select 1 from duc_ipqc_kiem_cua_su_co(s.ma_may, s.gio, s.id) k where k.luc > s.giao) then   -- T299
      continue;
    end if;
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

-- ── Phần 5: F1 tự đóng chặt + IPQC NG lúc đang có sự cố khác ────────────────
create or replace function public.duc_close_f1_incident_if_open(p_id_dong text, p_nguoi_kiem text)
returns boolean
language plpgsql security definer
set search_path to 'public'
as $function$
declare c record; v_id text; v_gio timestamptz; v_xl text; v_dn text; v_chinh boolean;
        v_ipqc jsonb; v_giao timestamptz; v_luc timestamptz; v_kq jsonb;
begin
  select * into c from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found or c.open_gio_phat_sinh is null then return false; end if;
  if left(coalesce(c.open_loai_su_co, ''), 2) = 'F1' then
    v_chinh := true; v_id := c.open_id_su_co; v_gio := c.open_gio_phat_sinh; v_xl := c.open_noi_dung_xu_ly; v_dn := c.open_dam_nhiem;
  else
    select t.id_su_co, t.gio_phat_sinh, t.noi_dung_xu_ly, t.dam_nhiem into v_id, v_gio, v_xl, v_dn
      from duc_su_co_mo_them t where t.id_dong = p_id_dong and left(t.loai_su_co, 2) = 'F1'
     order by t.gio_phat_sinh, t.id limit 1;
    if not found then return false; end if;
    v_chinh := false;
  end if;
  if v_id is null then return false; end if;

  -- T299 (3): chỉ tự đóng khi đủ điều kiện như bấm Xong; thiếu gì thì để trưởng ca bấm Xong.
  v_ipqc := duc_ipqc_trang_thai_su_co_ts(c.ma_may, 'F1', v_gio, v_id);
  if coalesce(v_ipqc->>'ket_qua', '') <> 'OK' then return false; end if;
  v_luc := (v_ipqc->>'luc')::timestamptz;
  select max(thoi_diem) into v_giao from duc_su_co_giao_qc where id_su_co = v_id;
  if v_gio >= duc_moc_giao_qc() and (v_giao is null or v_luc <= v_giao) then return false; end if;
  if duc_khuon_ct_kiem('xlbt', v_id, 'dong') is not null then return false; end if;
  if coalesce(trim(v_xl), '') = '' or coalesce(trim(v_dn), '') = '' then return false; end if;

  if not v_chinh then perform duc_su_co_doi_cho(p_id_dong, v_id); end if;
  v_kq := public.duc_su_co_ghi_log_theo_ca(p_id_dong, greatest(now(), v_gio),
    trim(v_xl) || E'\n[IPQC kiểm lại OK lúc ' || to_char(v_luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM')
      || coalesce(' — ' || nullif(p_nguoi_kiem, ''), '') || ' — cho chạy lại]',
    trim(v_dn), '');
  perform duc_clear_incident_open(p_id_dong, coalesce(p_nguoi_kiem, 'system'));
  return true;
end;
$function$;
revoke execute on function public.duc_close_f1_incident_if_open(text, text) from public, anon, authenticated;

create or replace function public.duc_submit_ipqc_check(p_id_checkpoint text, p_checklist jsonb, p_ket_qua text, p_anh_urls jsonb, p_ghi_chu text, p_thoi_gian_kiem_giay numeric, p_nguoi_kiem text)
returns jsonb
language plpgsql security definer
set search_path to 'public'
as $function$
declare
  v_cp record;
  v_cht record;
  v_note text := '';
  v_issue_text text;
  v_vdk_id text;
  v_open_result jsonb;
  v_all_pass boolean;
  v_any_fail boolean;
  v_now timestamptz := now();
begin
  if p_ket_qua not in ('OK', 'NG', 'CANH_BAO') then
    return jsonb_build_object('ok', false, 'error', 'Kết quả phải là OK, NG hoặc CANH_BAO');
  end if;
  if p_anh_urls is null or jsonb_array_length(p_anh_urls) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Bắt buộc có ít nhất 1 ảnh bằng chứng');
  end if;
  if jsonb_array_length(p_anh_urls) > 10 then
    return jsonb_build_object('ok', false, 'error', 'Tối đa 10 ảnh cho 1 lần kiểm tra');
  end if;
  if p_nguoi_kiem is null or trim(p_nguoi_kiem) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu người kiểm');
  end if;

  select
    bool_and((elem->>'dat')::boolean is true) filter (where jsonb_array_length(coalesce(p_checklist,'[]'::jsonb)) > 0)
      and jsonb_array_length(coalesce(p_checklist,'[]'::jsonb)) > 0,
    bool_or((elem->>'dat') = 'false')
  into v_all_pass, v_any_fail
  from jsonb_array_elements(coalesce(p_checklist, '[]'::jsonb)) elem;
  v_all_pass := coalesce(v_all_pass, false);
  v_any_fail := coalesce(v_any_fail, false);

  if p_ket_qua = 'OK' and not v_all_pass then
    return jsonb_build_object('ok', false, 'error', 'Chỉ được chọn OK khi tất cả các mục kiểm đều Đạt');
  end if;
  if p_ket_qua in ('NG', 'CANH_BAO') and not v_any_fail then
    return jsonb_build_object('ok', false, 'error', 'NG / Cảnh báo cần ít nhất 1 mục kiểm Không đạt');
  end if;
  if p_ket_qua in ('NG', 'CANH_BAO') and (p_ghi_chu is null or trim(p_ghi_chu) = '') then
    return jsonb_build_object('ok', false, 'error', 'NG / Cảnh báo bắt buộc phải nhập ghi chú');
  end if;

  select id_dong, ma_may, ma_sp, loai_kiem, id_su_co_goc into v_cp from duc_ipqc_checkpoint where id_checkpoint = p_id_checkpoint;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy checkpoint: ' || p_id_checkpoint); end if;

  if (select trang_thai from duc_ipqc_checkpoint where id_checkpoint = p_id_checkpoint) = 'da_kiem' then
    return jsonb_build_object('ok', false, 'error', 'Điểm kiểm này đã được xử lý trước đó');
  end if;

  update duc_ipqc_checkpoint set
    trang_thai = 'da_kiem', thoi_diem_kiem_thuc_te = now(), nguoi_kiem = p_nguoi_kiem,
    ket_qua = p_ket_qua, checklist_json = coalesce(p_checklist, '[]'::jsonb),
    anh_bang_chung_url = p_anh_urls, thoi_gian_kiem_giay = p_thoi_gian_kiem_giay,
    ghi_chu = coalesce(p_ghi_chu, '')
  where id_checkpoint = p_id_checkpoint;

  -- Một máy chỉ 1 điểm kiểm sống: lượt kiểm này xong thì cho hết hiệu lực mọi
  -- checkpoint 'dinh_ky' khác còn 'cho_kiem' của cùng dòng. Đồng hồ định kỳ
  -- tự tính lại từ thoi_diem_kiem_thuc_te vừa ghi qua duc_get_ipqc_periodic_due.
  update duc_ipqc_checkpoint set trang_thai = 'het_hieu_luc'
  where id_dong = v_cp.id_dong and loai_kiem = 'dinh_ky'
    and trang_thai = 'cho_kiem' and id_checkpoint <> p_id_checkpoint;

  select ngay, ca, so_khuon, open_gio_phat_sinh, open_loai_su_co, open_id_su_co into v_cht from duc_ca_hien_tai where id_dong = v_cp.id_dong;
  if not found then
    return jsonb_build_object('ok', true, 'id_checkpoint', p_id_checkpoint, 'ket_qua', p_ket_qua, 'note', 'Dòng Ca_hien_tai gốc không còn — bỏ qua liên kết ngược.');
  end if;

  v_issue_text := duc_build_ipqc_issue_text(p_ket_qua, v_cp.loai_kiem, p_checklist, p_ghi_chu);

  if p_ket_qua = 'NG' then
    -- T241: mỗi máy chỉ 1 sự cố mở — máy đang có sự cố thì không tự mở thêm F1.
    if v_cht.open_gio_phat_sinh is not null then
      v_note := case
        when v_cp.loai_kiem in ('sau_su_co', 'doi_khuon') then 'Không mở thêm sự cố F1 — máy đang dừng vì sự cố chờ IPQC; sự cố đó chỉ kết thúc được khi IPQC kiểm lại OK / Cảnh báo.'
        when left(coalesce(v_cht.open_loai_su_co, ''), 2) = 'F1' then 'Không mở thêm sự cố F1 — máy đã có sự cố F1 đang mở; kết quả NG đã ghi vào lý lịch sự cố đó.'
        else 'Không mở thêm sự cố F1 — máy đang có sự cố khác mở; kết quả NG đã ghi vào lý lịch sự cố đó và báo trưởng ca.' end;
      -- T299 (5): NG không thuộc sự cố đang mở → ghi vào lý lịch sự cố đó + chuông trưởng ca.
      if v_cht.open_id_su_co is not null and v_cp.id_su_co_goc is distinct from v_cht.open_id_su_co then
        begin
          insert into duc_su_co_nhat_ky (id_su_co, su_kien, id_dong, ngay, ca, du_lieu, nguoi, nguoi_uid, nguon)
          values (v_cht.open_id_su_co, 'ipqc_ng', v_cp.id_dong, v_cht.ngay, v_cht.ca,
                  jsonb_build_object('id_checkpoint', p_id_checkpoint, 'loai_kiem', v_cp.loai_kiem,
                                     'id_su_co_kiem', v_cp.id_su_co_goc, 'noi_dung', v_issue_text),
                  p_nguoi_kiem, auth.uid(), '/rpc/duc_submit_ipqc_check');
          perform cv_pd_gui(cv_pd_ds_role(array['truong_ca']), 'ipqc', 'ipqc_ng_dang_su_co', 'ipqc_ng:' || p_id_checkpoint,
            'duc-dashboard.html',
            '🧪 IPQC kiểm NG máy ' || v_cp.ma_may || ' trong lúc đang có sự cố ' || v_cht.open_id_su_co || ' — ' || left(coalesce(v_issue_text, ''), 200),
            false);
        exception when others then raise warning 'duc_submit_ipqc_check ghi ipqc_ng: %', sqlerrm;
        end;
      end if;
    else
      v_open_result := duc_set_incident_open(v_cp.id_dong, 'F1', v_now, v_issue_text, '', p_nguoi_kiem);
      if not (v_open_result->>'ok')::boolean then
        v_note := 'Lỗi mở sự cố F1 tự động: ' || (v_open_result->>'error');
      end if;
      -- T299 (3): không tạo phiếu "sau sự cố" ngay — phiếu tạo khi trưởng ca xử lý xong và giao QC.
    end if;
    if v_cht.so_khuon is not null and v_cht.so_khuon <> '' then
      v_vdk_id := duc_report_mold_issue(v_cht.so_khuon, v_cp.ma_may, v_cp.ma_sp, v_issue_text, p_nguoi_kiem, v_cht.ngay, v_cht.ca);
      update duc_ipqc_checkpoint set id_van_de_lien_quan = v_vdk_id where id_checkpoint = p_id_checkpoint;
    end if;
  elsif p_ket_qua = 'CANH_BAO' then
    if v_cht.so_khuon is null or v_cht.so_khuon = '' then
      v_note := 'Không tạo được báo cáo vấn đề khuôn — dòng chưa gán số khuôn.';
    else
      v_vdk_id := duc_report_mold_issue(v_cht.so_khuon, v_cp.ma_may, v_cp.ma_sp, v_issue_text, p_nguoi_kiem, v_cht.ngay, v_cht.ca);
      update duc_ipqc_checkpoint set id_van_de_lien_quan = v_vdk_id where id_checkpoint = p_id_checkpoint;
    end if;
  else
    perform duc_close_f1_incident_if_open(v_cp.id_dong, p_nguoi_kiem);
  end if;

  return jsonb_build_object('ok', true, 'id_checkpoint', p_id_checkpoint, 'ket_qua', p_ket_qua, 'note', v_note);
end;
$function$;
revoke execute on function public.duc_submit_ipqc_check(text, jsonb, text, jsonb, text, numeric, text) from public, anon, authenticated;

-- ── Phần 6: sửa sự cố đã đóng — không kéo giờ trở lại sớm hơn IPQC OK ─────
create or replace function public.duc_edit_incident(p_id_ban_ghi text, p_loai_su_co text, p_gio_phat_sinh timestamptz, p_gio_tro_lai timestamptz,
  p_van_de text, p_noi_dung_xu_ly text, p_dam_nhiem text, p_ghi_chu text, p_user text)
returns jsonb
language plpgsql security definer
set search_path to 'public'
as $function$
declare
  v_row record; v_final_ps timestamptz; v_final_tl timestamptz; v_stamp text; v_audit text;
  v_current_gc text; v_user_gc text; v_new_gc text; v_now timestamptz := now(); v_luc_ok timestamptz;
begin
  if auth.uid() is not null and not public.has_role(VARIADIC ARRAY['admin', 'truong_ca', 'quan_ly_bo_phan', 'qlsx_truong_phong']) then
    raise exception '⛔ Tài khoản không có quyền thực hiện thao tác này — cần vai trò: %', 'Trưởng ca / QLBP / TP QLSX' using errcode = '42501';
  end if;   -- T212
  p_user := public.duc_ten_nguoi_hien_tai(p_user);   -- T212: tên theo tài khoản
  if auth.uid() is not null and not public.has_role('admin', 'quan_ly_bo_phan', 'qlsx_truong_phong')
     and exists (select 1 from duc_su_co_log l join duc_bao_cao_ca b on b.ngay = l.ngay and b.ca = l.ca where l.id_ban_ghi = p_id_ban_ghi) then
    raise exception '⛔ Ca của sự cố này đã chốt báo cáo — chỉ QLBP / Trưởng phòng QLSX / admin được sửa' using errcode = '42501';
  end if;   -- T212
  if p_gio_phat_sinh is not null and p_gio_tro_lai is not null and p_gio_tro_lai - p_gio_phat_sinh > interval '14 hours' then
    raise exception '⛔ Thời gian dừng một bản ghi không quá 14 giờ (1 ca) — kiểm tra lại giờ phát sinh / giờ trở lại';
  end if;   -- T212
  select * into v_row from duc_su_co_log where id_ban_ghi = p_id_ban_ghi;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy bản ghi sự cố: ' || p_id_ban_ghi); end if;

  if p_gio_tro_lai is not null and p_gio_tro_lai > now() + interval '1 minute' then
    return jsonb_build_object('ok', false, 'error', 'Giờ trở lại không được ở tương lai');
  end if;

  v_final_ps := coalesce(p_gio_phat_sinh, case when p_gio_tro_lai is not null and p_gio_phat_sinh is null then v_row.gio_phat_sinh else null end);
  v_final_tl := coalesce(p_gio_tro_lai, case when p_gio_phat_sinh is not null and p_gio_tro_lai is null then v_row.gio_tro_lai else null end);
  if v_final_ps is not null and v_final_tl is not null and v_final_tl < v_final_ps then
    return jsonb_build_object('ok', false, 'error', 'Giờ trở lại phải sau giờ phát sinh (sau khi kết hợp giờ hiện tại)');
  end if;

  -- T299 (1): phần cuối của sự cố cần IPQC — giờ trở lại không được kéo sớm hơn lần IPQC OK đã cho đóng.
  if p_gio_tro_lai is not null and v_row.id_su_co is not null and v_final_tl < v_row.gio_tro_lai
     and left(coalesce(nullif(p_loai_su_co, ''), v_row.loai_su_co, ''), 2) = any(array['A1','A2','A3','B1','B2','C3','E1','F1'])
     and v_row.gio_tro_lai = (select max(l.gio_tro_lai) from duc_su_co_log l where l.id_su_co = v_row.id_su_co) then
    select max(k.luc) into v_luc_ok
      from duc_ipqc_kiem_cua_su_co(v_row.ma_may,
             (select min(l.gio_phat_sinh) from duc_su_co_log l where l.id_su_co = v_row.id_su_co), v_row.id_su_co) k
     where k.ket_qua in ('OK', 'CANH_BAO') and k.luc <= greatest(v_row.gio_tro_lai, v_row.thoi_diem_luu);
    if v_luc_ok is not null and v_final_tl < v_luc_ok then
      return jsonb_build_object('ok', false, 'error', '⛔ Giờ trở lại không được sớm hơn lúc IPQC kiểm đạt ('
        || to_char(v_luc_ok at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ') — máy chỉ chạy lại sau khi IPQC OK.');
    end if;
  end if;

  v_stamp := to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM');
  v_audit := '[edited ' || v_stamp || ' by ' || coalesce(p_user, 'unknown') || ']';
  v_current_gc := coalesce(v_row.ghi_chu, '');
  v_user_gc := trim(coalesce(p_ghi_chu, ''));
  v_new_gc := case when v_user_gc <> '' then v_user_gc || E'\n' || v_audit else v_audit end;
  -- Bảo tồn các audit-stamp trước đó (nếu có) — nối thêm vào cuối, giống bản gốc.
  if v_current_gc ~ '\[edited [0-9:/ ]+ by [^\]]+\]' then
    v_new_gc := v_new_gc || E'\n' || (
      select string_agg(m[1], E'\n') from regexp_matches(v_current_gc, '(\[edited [0-9:/ ]+ by [^\]]+\])', 'g') m
    );
  end if;

  update duc_su_co_log set
    loai_su_co = case when p_loai_su_co is not null and p_loai_su_co <> '' then p_loai_su_co else loai_su_co end,
    gio_phat_sinh = coalesce(v_final_ps, gio_phat_sinh),
    gio_tro_lai = coalesce(v_final_tl, gio_tro_lai),
    thoi_gian_dung_phut = case when v_final_ps is not null and v_final_tl is not null and (p_gio_phat_sinh is not null or p_gio_tro_lai is not null)
      then round(extract(epoch from (v_final_tl - v_final_ps)) / 60) else thoi_gian_dung_phut end,
    van_de = coalesce(p_van_de, van_de),
    noi_dung_xu_ly = coalesce(p_noi_dung_xu_ly, noi_dung_xu_ly),
    dam_nhiem = coalesce(p_dam_nhiem, dam_nhiem),
    ghi_chu = v_new_gc, van_de_edited = 'Yes'
  where id_ban_ghi = p_id_ban_ghi;

  return jsonb_build_object('ok', true, 'id_ban_ghi', p_id_ban_ghi, 'van_de_edited', 'Yes');
end;
$function$;
