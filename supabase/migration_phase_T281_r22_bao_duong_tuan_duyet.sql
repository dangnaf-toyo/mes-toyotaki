-- ============================================================================
-- T281 (R22) — Phê duyệt Kế hoạch bảo dưỡng khuôn tuần không còn là thủ tục.
--
-- User 15/11/2026 chọn (đổi lại quyết định D67 ngày 12/10, vì nay prod đã có
-- 4 tài khoản nhan_vien_bao_duong_khuon để lập):
--   1) CHẶN tự kiểm tra: ai đã lập / sửa / xoá / gửi kế hoạch tuần đó
--      (nguoi_lap hoặc duc_khuon_bd_duyet_log) thì không được KIỂM TRA tuần đó.
--   2) Kế hoạch có Quản lý bộ phận Đúc tham gia lập/sửa → Giám đốc SX được
--      KIỂM TRA THAY (rồi phê duyệt như thường). Chuông "chờ kiểm tra" khi đó
--      gửi Giám đốc SX thay vì QLBP Đúc.
--   3) Nhắc thứ Hai 07:30: kế hoạch tuần này chưa duyệt xong → chuông người
--      đang phải kiểm tra / phê duyệt; chưa gửi → chuông người lập.
--   4) Trạng thái mới 'luu_tru' (tuần đã qua, chưa duyệt). 3 tuần dở
--      05/10, 19/10 (chưa gửi), 02/11 (chờ kiểm tra) → Lưu trữ.
--      Tuần Lưu trữ: không gửi duyệt; sửa lịch vẫn cần lý do, giữ Lưu trữ.
--
-- Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

-- 1) Trạng thái + sự kiện mới -------------------------------------------------
alter table public.duc_khuon_bd_duyet drop constraint if exists duc_khuon_bd_duyet_trang_thai_check;
alter table public.duc_khuon_bd_duyet add constraint duc_khuon_bd_duyet_trang_thai_check
  check (trang_thai in ('nhap', 'cho_kiem_tra', 'cho_phe_duyet', 'da_duyet', 'luu_tru'));
alter table public.duc_khuon_bd_duyet_log drop constraint if exists duc_khuon_bd_duyet_log_su_kien_check;
alter table public.duc_khuon_bd_duyet_log add constraint duc_khuon_bd_duyet_log_su_kien_check
  check (su_kien in ('them', 'sua', 'xoa', 'gui_duyet', 'kiem_tra', 'phe_duyet', 'tu_choi', 'luu_tru'));

-- 2) Helper: tên hiển thị (giống duc_khuon_bd_nguoi_hien_tai) ------------------
create or replace function public.duc_khuon_bd_ten(p_full_name text, p_username text, p_email text)
returns text language sql immutable as $$
  select coalesce(nullif(trim(p_full_name), ''), nullif(trim(p_username), ''), p_email, '');
$$;
revoke execute on function public.duc_khuon_bd_ten(text, text, text) from public, anon, authenticated;

-- Người p_ten đã tham gia lập kế hoạch tuần p_tuan?
create or replace function public.duc_khuon_bd_da_lap(p_tuan date, p_ten text)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce(trim(p_ten), '') <> '' and (
    exists (select 1 from duc_khuon_bd_duyet d where d.tuan_bat_dau = p_tuan and d.nguoi_lap = p_ten)
    or exists (select 1 from duc_khuon_bd_duyet_log l where l.tuan_bat_dau = p_tuan
                 and l.su_kien in ('them', 'sua', 'xoa', 'gui_duyet') and l.nguoi = p_ten));
$$;
revoke execute on function public.duc_khuon_bd_da_lap(date, text) from public, anon, authenticated;

-- Kế hoạch tuần có QLBP Đúc tham gia lập → Giám đốc SX kiểm tra thay.
-- Đọc được từ trang (chỉ trả true/false).
create or replace function public.duc_khuon_bd_kiem_thay(p_tuan date)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (
    select 1 from user_roles u
    where u.role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(u.bo_phan_phu_trach, '{}'))
      and duc_khuon_bd_da_lap(p_tuan, duc_khuon_bd_ten(u.full_name, u.username, u.email)));
$$;
revoke execute on function public.duc_khuon_bd_kiem_thay(date) from public, anon;
grant execute on function public.duc_khuon_bd_kiem_thay(date) to authenticated;

-- 3) Trước khi sửa: tuần Lưu trữ giữ nguyên trạng thái ---------------------------
create or replace function public.duc_khuon_bd_truoc_khi_sua(p_tuan date, p_ly_do text, out o_loi text, out o_ten text)
returns record language plpgsql security definer set search_path to 'public' as $function$
declare
  v_me record; v_tt text;
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  o_ten := coalesce(v_me.o_ten, '');
  if not duc_khuon_bd_la_nguoi_lap(v_me.o_role, v_me.o_bo_phan) then
    o_loi := 'Chỉ nhân viên bảo dưỡng khuôn / Quản lý bộ phận Đúc được sửa kế hoạch bảo dưỡng'; return;
  end if;
  select trang_thai into v_tt from duc_khuon_bd_duyet where tuan_bat_dau = p_tuan for update;
  if coalesce(v_tt, 'nhap') <> 'nhap' then
    if coalesce(trim(p_ly_do), '') = '' then
      o_loi := case when v_tt = 'luu_tru' then 'Tuần đã lưu trữ — bắt buộc nhập lý do sửa'
                    else 'Kế hoạch đã gửi duyệt — bắt buộc nhập lý do sửa (kế hoạch sẽ phải kiểm tra & duyệt lại)' end;
      return;
    end if;
    if v_tt <> 'luu_tru' then
      update duc_khuon_bd_duyet set trang_thai = 'cho_kiem_tra',
        nguoi_kiem_tra = '', thoi_diem_kiem_tra = null, nguoi_phe_duyet = '', thoi_diem_phe_duyet = null,
        updated_at = now()
      where tuan_bat_dau = p_tuan;
    end if;
  end if;
end;
$function$;
revoke execute on function public.duc_khuon_bd_truoc_khi_sua(date, text) from public, anon, authenticated;

-- 4) Gửi duyệt: chặn tuần Lưu trữ -------------------------------------------------
create or replace function public.duc_khuon_bd_gui_duyet(p_tuan date)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_me record; v_tt text;
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  if not duc_khuon_bd_la_nguoi_lap(v_me.o_role, v_me.o_bo_phan) then
    return jsonb_build_object('ok', false, 'error', 'Chỉ nhân viên bảo dưỡng khuôn / Quản lý bộ phận Đúc (người lập) được gửi duyệt');
  end if;
  if not exists (select 1 from duc_khuon_bd_kh_tuan where tuan_bat_dau = p_tuan) then
    return jsonb_build_object('ok', false, 'error', 'Tuần này chưa có lịch bảo dưỡng nào để gửi duyệt');
  end if;
  insert into duc_khuon_bd_duyet (tuan_bat_dau) values (p_tuan) on conflict do nothing;
  select trang_thai into v_tt from duc_khuon_bd_duyet where tuan_bat_dau = p_tuan for update;
  if v_tt = 'luu_tru' then
    return jsonb_build_object('ok', false, 'error', 'Tuần đã lưu trữ, không gửi duyệt được');
  end if;
  if v_tt <> 'nhap' then
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch đã gửi duyệt rồi');
  end if;
  update duc_khuon_bd_duyet set trang_thai = 'cho_kiem_tra',
    nguoi_lap = v_me.o_ten, thoi_diem_lap = now(),
    nguoi_kiem_tra = '', thoi_diem_kiem_tra = null, nguoi_phe_duyet = '', thoi_diem_phe_duyet = null,
    nguoi_tu_choi = '', thoi_diem_tu_choi = null, ly_do_tu_choi = '', updated_at = now()
  where tuan_bat_dau = p_tuan;
  insert into duc_khuon_bd_duyet_log (tuan_bat_dau, su_kien, nguoi) values (p_tuan, 'gui_duyet', v_me.o_ten);
  return jsonb_build_object('ok', true, 'trang_thai_moi', 'cho_kiem_tra');
end;
$function$;
revoke execute on function public.duc_khuon_bd_gui_duyet(date) from public, anon;
grant execute on function public.duc_khuon_bd_gui_duyet(date) to authenticated;

-- 5) Kiểm tra / Phê duyệt: chặn tự kiểm tra, GĐSX kiểm tra thay ------------------
create or replace function public.duc_khuon_bd_xu_ly_duyet(p_tuan date, p_dong_y boolean, p_ly_do text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_me record; v_tt text; v_moi text;
  v_qlbp boolean; v_gd boolean; v_tu_lap boolean;
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  select trang_thai into v_tt from duc_khuon_bd_duyet where tuan_bat_dau = p_tuan for update;
  if v_tt is null or v_tt not in ('cho_kiem_tra', 'cho_phe_duyet') then
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch không ở trạng thái chờ kiểm tra/phê duyệt');
  end if;
  v_qlbp := coalesce(v_me.o_role, '') = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(v_me.o_bo_phan, '{}'));
  v_gd := coalesce(v_me.o_role, '') = 'giam_doc_sx' or public.has_role('giam_doc_sx');   -- T211
  v_tu_lap := duc_khuon_bd_da_lap(p_tuan, v_me.o_ten);

  if v_tt = 'cho_kiem_tra' then
    if v_tu_lap then
      return jsonb_build_object('ok', false, 'error',
        'Bạn đã lập/sửa kế hoạch tuần này nên không tự kiểm tra được — Giám đốc SX kiểm tra thay');
    end if;
    if not (v_qlbp or (v_gd and duc_khuon_bd_kiem_thay(p_tuan))) then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Quản lý bộ phận Đúc được kiểm tra bước này');
    end if;
  elsif not v_gd then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Giám đốc sản xuất được phê duyệt bước này');
  end if;

  if not p_dong_y then
    if coalesce(trim(p_ly_do), '') = '' then
      return jsonb_build_object('ok', false, 'error', 'Cần nhập lý do từ chối');
    end if;
    update duc_khuon_bd_duyet set trang_thai = 'nhap',
      nguoi_kiem_tra = '', thoi_diem_kiem_tra = null, nguoi_phe_duyet = '', thoi_diem_phe_duyet = null,
      nguoi_tu_choi = v_me.o_ten, thoi_diem_tu_choi = now(), ly_do_tu_choi = trim(p_ly_do), updated_at = now()
    where tuan_bat_dau = p_tuan;
    insert into duc_khuon_bd_duyet_log (tuan_bat_dau, su_kien, noi_dung, ly_do, nguoi)
    values (p_tuan, 'tu_choi', case when v_tt = 'cho_kiem_tra' then 'Bước kiểm tra' else 'Bước phê duyệt' end, trim(p_ly_do), v_me.o_ten);
    return jsonb_build_object('ok', true, 'trang_thai_moi', 'nhap');
  end if;

  if v_tt = 'cho_kiem_tra' then
    v_moi := 'cho_phe_duyet';
    update duc_khuon_bd_duyet set trang_thai = v_moi, nguoi_kiem_tra = v_me.o_ten, thoi_diem_kiem_tra = now(), updated_at = now()
    where tuan_bat_dau = p_tuan;
  else
    v_moi := 'da_duyet';
    update duc_khuon_bd_duyet set trang_thai = v_moi, nguoi_phe_duyet = v_me.o_ten, thoi_diem_phe_duyet = now(), updated_at = now()
    where tuan_bat_dau = p_tuan;
  end if;
  insert into duc_khuon_bd_duyet_log (tuan_bat_dau, su_kien, noi_dung, ly_do, nguoi)
  values (p_tuan, case when v_tt = 'cho_kiem_tra' then 'kiem_tra' else 'phe_duyet' end,
    case when v_tt = 'cho_kiem_tra' and not v_qlbp then 'Giám đốc SX kiểm tra thay' else '' end,
    coalesce(trim(p_ly_do), ''), v_me.o_ten);
  return jsonb_build_object('ok', true, 'trang_thai_moi', v_moi);
end;
$function$;
revoke execute on function public.duc_khuon_bd_xu_ly_duyet(date, boolean, text) from public, anon;
grant execute on function public.duc_khuon_bd_xu_ly_duyet(date, boolean, text) to authenticated;

-- 6) Chuông chờ kiểm tra: QLBP Đúc đã lập → gửi Giám đốc SX ----------------------
-- (người đang thao tác là QLBP Đúc cũng tính, vì log 'sua'/'gui_duyet' ghi sau
--  khi trigger trạng thái chạy)
create or replace function public.cv_pd_bd_bao(p_tuan date, p_tt text)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare v_me record; v_thay boolean;
begin
  if p_tt = 'cho_kiem_tra' then
    select * into v_me from duc_khuon_bd_nguoi_hien_tai();
    v_thay := duc_khuon_bd_kiem_thay(p_tuan)
      or (coalesce(v_me.o_role, '') = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(v_me.o_bo_phan, '{}')));
    if v_thay then
      return cv_pd_gui(cv_pd_ds_role(array['giam_doc_sx']), 'bd_khuon', 'can_duyet', 'bd_khuon:' || p_tuan,
        'bao-duong-khuon-tuan.html?tuan=' || p_tuan,
        'Kế hoạch bảo dưỡng khuôn tuần ' || cv_pd_tuan(p_tuan) || ' chờ bạn kiểm tra thay (Quản lý bộ phận Đúc đã lập).', true);
    end if;
    return cv_pd_gui(cv_pd_ds_role(array['quan_ly_bo_phan'], 'Đúc'), 'bd_khuon', 'can_duyet', 'bd_khuon:' || p_tuan,
      'bao-duong-khuon-tuan.html?tuan=' || p_tuan,
      'Kế hoạch bảo dưỡng khuôn tuần ' || cv_pd_tuan(p_tuan) || ' đang chờ bạn kiểm tra (bước Quản lý bộ phận Đúc).', true);
  elsif p_tt = 'cho_phe_duyet' then
    return cv_pd_gui(cv_pd_ds_role(array['giam_doc_sx']), 'bd_khuon', 'can_duyet', 'bd_khuon:' || p_tuan,
      'bao-duong-khuon-tuan.html?tuan=' || p_tuan,
      'Kế hoạch bảo dưỡng khuôn tuần ' || cv_pd_tuan(p_tuan) || ' đang chờ bạn phê duyệt (bước Giám đốc sản xuất).', true);
  end if;
  return 0;
end;
$function$;
revoke execute on function public.cv_pd_bd_bao(date, text) from public, anon, authenticated;

-- 7) Nhắc thứ Hai 07:30 -----------------------------------------------------------
create or replace function public.duc_khuon_bd_nhac_thu_hai()
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare
  v_tuan date := date_trunc('week', (now() at time zone 'Asia/Ho_Chi_Minh'))::date;
  v_tt text; v_khoa text := 'bd_khuon:' || v_tuan;
begin
  select trang_thai into v_tt from duc_khuon_bd_duyet where tuan_bat_dau = v_tuan;
  v_tt := coalesce(v_tt, 'nhap');
  if v_tt in ('da_duyet', 'luu_tru') then return 0; end if;
  perform cv_pd_xong(v_khoa);   -- chuông cũ xong, gửi chuông mới
  if v_tt in ('cho_kiem_tra', 'cho_phe_duyet') then
    return cv_pd_bd_bao(v_tuan, v_tt);
  end if;
  return cv_pd_gui(cv_pd_ds_role(array['nhan_vien_bao_duong_khuon', 'to_truong_khuon'])
                     || cv_pd_ds_role(array['quan_ly_bo_phan'], 'Đúc'),
    'bd_khuon', 'can_duyet', v_khoa, 'bao-duong-khuon-tuan.html?tuan=' || v_tuan,
    'Kế hoạch bảo dưỡng khuôn tuần ' || cv_pd_tuan(v_tuan) || ' chưa gửi kiểm tra — tuần đã bắt đầu.', true);
end;
$function$;
revoke execute on function public.duc_khuon_bd_nhac_thu_hai() from public, anon, authenticated;

select cron.unschedule('duc_khuon_bd_nhac_thu_hai') where exists (select 1 from cron.job where jobname = 'duc_khuon_bd_nhac_thu_hai');
select cron.schedule('duc_khuon_bd_nhac_thu_hai', '30 0 * * 1', 'select public.duc_khuon_bd_nhac_thu_hai();');  -- 07:30 giờ VN thứ Hai

-- 8) Dữ liệu: tuần đã qua mà chưa duyệt xong → Lưu trữ (prod: 05/10, 19/10, 02/11)
do $$
declare r record; v_today date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  for r in
    select w.tuan_bat_dau, d.trang_thai from (
      select distinct tuan_bat_dau from duc_khuon_bd_kh_tuan
      union select tuan_bat_dau from duc_khuon_bd_duyet) w
    left join duc_khuon_bd_duyet d on d.tuan_bat_dau = w.tuan_bat_dau
    where w.tuan_bat_dau + 7 <= v_today and coalesce(d.trang_thai, 'nhap') not in ('da_duyet', 'luu_tru')
  loop
    insert into duc_khuon_bd_duyet (tuan_bat_dau) values (r.tuan_bat_dau) on conflict do nothing;
    update duc_khuon_bd_duyet set trang_thai = 'luu_tru', updated_at = now() where tuan_bat_dau = r.tuan_bat_dau;
    insert into duc_khuon_bd_duyet_log (tuan_bat_dau, su_kien, noi_dung, nguoi)
    values (r.tuan_bat_dau, 'luu_tru', 'Tuần đã qua, ' || case coalesce(r.trang_thai, 'nhap') when 'nhap' then 'chưa gửi kiểm tra'
      when 'cho_kiem_tra' then 'còn chờ kiểm tra' else 'còn chờ phê duyệt' end, 'Hệ thống (R22)');
  end loop;
end $$;
