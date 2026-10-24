-- ============================================================================
-- Phase T162 — Đưa các luồng PHÊ DUYỆT sẵn có vào chuông thông báo trong MES
-- (bảng cv_thong_bao của module Công việc T161) + sửa lỗi QLBP không duyệt
-- được Kế hoạch sản xuất tuần.
--
-- Hợp đồng với giao diện:
-- - cv_thong_bao thêm cột nguon ('cong_viec','khsx','bd_khuon','ipqc','ncp',
--   'tai_lieu'), lien_ket (URL tương đối, để nguyên chữ tiếng Việt), khoa
--   (khoá nhóm thông báo của 1 yêu cầu, vd 'khsx:2026-10-19:Đúc').
-- - loai mới: 'can_duyet' (chờ BẠN duyệt/xác nhận, can_xu_ly = true),
--   'da_duyet' (yêu cầu của bạn đã được duyệt xong), 'tu_choi_duyet' (bị từ
--   chối/trả lại, kèm lý do nếu có). cong_viec_id = null cho các nguồn này.
-- - RLS giữ nguyên (chỉ đọc dòng của mình); cv_doc_thong_bao dùng cho mọi nguồn.
--
-- Cơ chế: TRIGGER after insert/update trên các bảng trạng thái (không sửa RPC
-- nghiệp vụ, trừ mục 9 sửa lỗi KHSX). Thân trigger bọc exception → lỗi gửi
-- thông báo chỉ raise warning, KHÔNG bao giờ chặn thao tác duyệt gốc.
-- Không gửi cho chính người thao tác (auth.uid()). Trước khi báo bước mới,
-- đánh da_xu_ly các thông báo cũ của cùng khoá.
-- An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Cột mới + index
-- ---------------------------------------------------------------------------
alter table public.cv_thong_bao add column if not exists nguon text not null default 'cong_viec';
alter table public.cv_thong_bao add column if not exists lien_ket text;
alter table public.cv_thong_bao add column if not exists khoa text;

alter table public.cv_thong_bao drop constraint if exists cv_thong_bao_nguon_check;
alter table public.cv_thong_bao add constraint cv_thong_bao_nguon_check
  check (nguon in ('cong_viec', 'khsx', 'bd_khuon', 'ipqc', 'ncp', 'tai_lieu'));

create index if not exists idx_cv_thong_bao_khoa     on public.cv_thong_bao (khoa);
create index if not exists idx_cv_thong_bao_nhan_doc on public.cv_thong_bao (nguoi_nhan, da_doc);

-- ---------------------------------------------------------------------------
-- 2. Helper nội bộ
-- ---------------------------------------------------------------------------
-- Người nhận theo role (+ tuỳ chọn lọc bộ phận phụ trách).
create or replace function public.cv_pd_ds_role(p_roles text[], p_bo_phan text default null)
returns uuid[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct u.user_id), '{}')
  from user_roles u
  where u.role = any(coalesce(p_roles, '{}'))
    and (p_bo_phan is null or p_bo_phan = any(coalesce(u.bo_phan_phu_trach, '{}')));
$$;

-- Người nhận theo bộ phận phụ trách (mọi role).
create or replace function public.cv_pd_ds_bo_phan(p_bo_phan text)
returns uuid[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct u.user_id), '{}')
  from user_roles u
  where p_bo_phan is not null and p_bo_phan = any(coalesce(u.bo_phan_phu_trach, '{}'));
$$;

-- Người nhận theo TÊN (log cũ lưu text). Khớp mọi dạng tên MES đang ghi:
-- tên hiển thị (full_name → username → email), username, email,
-- "username_full_name" (MesAuth.getCurrentUserIdentity).
create or replace function public.cv_pd_ds_ten(p_ten text)
returns uuid[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct u.user_id), '{}')
  from user_roles u
  where nullif(trim(coalesce(p_ten, '')), '') is not null
    and (coalesce(nullif(trim(u.full_name), ''), nullif(trim(u.username), ''), u.email, '') = trim(p_ten)
         or nullif(trim(u.username), '') = trim(p_ten)
         or lower(u.email) = lower(trim(p_ten))
         or (nullif(trim(u.username), '') is not null and nullif(trim(u.full_name), '') is not null
             and trim(u.username) || '_' || trim(u.full_name) = trim(p_ten)));
$$;

-- Gửi thông báo phê duyệt cho danh sách uuid (trừ chính người thao tác,
-- chỉ tài khoản có thật). Với can_xu_ly: bỏ qua người đã có thông báo chưa xử
-- lý cùng khoá (idempotent). Trả số dòng đã gửi.
create or replace function public.cv_pd_gui(p_nguoi uuid[], p_nguon text, p_loai text, p_khoa text,
                                            p_lien_ket text, p_noi_dung text, p_can_xu_ly boolean default false)
returns int language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  insert into cv_thong_bao (nguoi_nhan, loai, cong_viec_id, du_an_id, noi_dung, can_xu_ly, nguon, lien_ket, khoa)
  select distinct u, p_loai, null::bigint, null::bigint, p_noi_dung, coalesce(p_can_xu_ly, false), p_nguon, p_lien_ket, p_khoa
  from unnest(coalesce(p_nguoi, '{}')) u
  where u is not null and u is distinct from auth.uid()
    and exists (select 1 from user_roles r where r.user_id = u)
    and not (coalesce(p_can_xu_ly, false) and exists (
      select 1 from cv_thong_bao t
      where t.khoa = p_khoa and t.nguoi_nhan = u and t.can_xu_ly and not t.da_xu_ly));
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- "Xong theo khoá": đánh da_xu_ly mọi thông báo can_xu_ly của khoá.
-- p_tien_to = true → mọi khoá bắt đầu bằng p_khoa (vd 'dcr:<uuid>' + ':xn:...').
create or replace function public.cv_pd_xong(p_khoa text, p_tien_to boolean default false)
returns void language sql security definer set search_path = public as $$
  update cv_thong_bao set da_xu_ly = true
  where can_xu_ly and not da_xu_ly and khoa is not null and p_khoa is not null
    and (khoa = p_khoa or (p_tien_to and left(khoa, length(p_khoa)) = p_khoa));
$$;

-- Định dạng tuần "19/10".
create or replace function public.cv_pd_tuan(p date)
returns text language sql immutable set search_path = public as $$
  select to_char(p, 'DD/MM');
$$;

-- ---------------------------------------------------------------------------
-- 3. KHSX tuần (khsx_duyet)
-- ---------------------------------------------------------------------------
-- Gửi 'can_duyet' cho người duyệt bước hiện tại (không đánh xong — trigger
-- làm trước). Dùng chung cho trigger và backfill.
create or replace function public.cv_pd_khsx_bao(p_tuan date, p_cd text, p_tt text)
returns int language plpgsql security definer set search_path = public as $$
declare v_nguoi uuid[]; v_buoc text;
begin
  if p_tt = 'cho_truong_phong' then
    v_nguoi := cv_pd_ds_role(array['qlsx_truong_phong']); v_buoc := 'Trưởng phòng QLSX';
  elsif p_tt = 'cho_quan_ly_bo_phan' then
    v_nguoi := cv_pd_ds_role(array['quan_ly_bo_phan'], p_cd); v_buoc := 'Quản lý bộ phận';
  elsif p_tt = 'cho_giam_doc' then
    v_nguoi := cv_pd_ds_role(array['giam_doc_sx']); v_buoc := 'Giám đốc sản xuất';
  else
    return 0;
  end if;
  return cv_pd_gui(v_nguoi, 'khsx', 'can_duyet', 'khsx:' || p_tuan || ':' || p_cd,
    'khsx-tuan.html?cd=' || p_cd || '&tuan=' || p_tuan,
    'Kế hoạch sản xuất tuần ' || cv_pd_tuan(p_tuan) || ' – công đoạn ' || p_cd
      || ' đang chờ bạn duyệt (bước ' || v_buoc || ').', true);
end;
$$;

-- Người gửi duyệt gần nhất (log 'gui_duyet') → uuid[].
create or replace function public.cv_pd_khsx_nguoi_gui(p_tuan date, p_cd text)
returns uuid[] language sql stable security definer set search_path = public as $$
  select cv_pd_ds_ten((select l.nguoi_thuc_hien from khsx_thay_doi_log l
                       where l.tuan_bat_dau = p_tuan and l.cong_doan = p_cd and l.loai_su_kien = 'gui_duyet'
                       order by l.thoi_diem desc, l.id desc limit 1));
$$;

create or replace function public.cv_pd_trg_khsx()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_khoa text;
begin
  begin
    if tg_op = 'UPDATE' and old.trang_thai is not distinct from new.trang_thai then
      return new;
    end if;
    v_khoa := 'khsx:' || new.tuan_bat_dau || ':' || new.cong_doan;
    perform cv_pd_xong(v_khoa);
    if new.trang_thai in ('cho_truong_phong', 'cho_quan_ly_bo_phan', 'cho_giam_doc') then
      perform cv_pd_khsx_bao(new.tuan_bat_dau, new.cong_doan, new.trang_thai);
    elsif new.trang_thai = 'da_duyet' then
      perform cv_pd_gui(cv_pd_khsx_nguoi_gui(new.tuan_bat_dau, new.cong_doan), 'khsx', 'da_duyet', v_khoa,
        'khsx-tuan.html?cd=' || new.cong_doan || '&tuan=' || new.tuan_bat_dau,
        'Kế hoạch sản xuất tuần ' || cv_pd_tuan(new.tuan_bat_dau) || ' – công đoạn ' || new.cong_doan
          || ' đã được duyệt xong.', false);
    end if;
    -- Về 'nhap' (từ chối): báo người gửi ở trigger log (cần lý do, ghi sau).
  exception when others then
    raise warning 'T162 thông báo KHSX lỗi (bỏ qua, không chặn thao tác): %', sqlerrm;
  end;
  return new;
end;
$$;

-- Từ chối: khsx_tu_choi ghi log 'tu_choi' (kèm lý do) ngay sau khi đổi trạng thái.
create or replace function public.cv_pd_trg_khsx_log()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    if new.loai_su_kien = 'tu_choi' then
      perform cv_pd_xong('khsx:' || new.tuan_bat_dau || ':' || new.cong_doan);
      perform cv_pd_gui(cv_pd_khsx_nguoi_gui(new.tuan_bat_dau, new.cong_doan), 'khsx', 'tu_choi_duyet',
        'khsx:' || new.tuan_bat_dau || ':' || new.cong_doan,
        'khsx-tuan.html?cd=' || new.cong_doan || '&tuan=' || new.tuan_bat_dau,
        'Kế hoạch sản xuất tuần ' || cv_pd_tuan(new.tuan_bat_dau) || ' – công đoạn ' || new.cong_doan
          || ' bị từ chối' || coalesce(': ' || nullif(trim(new.ly_do), ''), '') || '.', false);
    end if;
  exception when others then
    raise warning 'T162 thông báo KHSX (từ chối) lỗi (bỏ qua, không chặn thao tác): %', sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists trg_cv_pd_khsx on public.khsx_duyet;
create trigger trg_cv_pd_khsx after insert or update of trang_thai on public.khsx_duyet
  for each row execute function public.cv_pd_trg_khsx();
drop trigger if exists trg_cv_pd_khsx_log on public.khsx_thay_doi_log;
create trigger trg_cv_pd_khsx_log after insert on public.khsx_thay_doi_log
  for each row when (new.loai_su_kien = 'tu_choi') execute function public.cv_pd_trg_khsx_log();

-- ---------------------------------------------------------------------------
-- 4. Kế hoạch bảo dưỡng khuôn tuần (duc_khuon_bd_duyet)
-- ---------------------------------------------------------------------------
create or replace function public.cv_pd_bd_bao(p_tuan date, p_tt text)
returns int language plpgsql security definer set search_path = public as $$
begin
  if p_tt = 'cho_kiem_tra' then
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
$$;

create or replace function public.cv_pd_trg_bd()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_khoa text; v_lk text; v_cu text;
begin
  begin
    v_cu := case when tg_op = 'UPDATE' then old.trang_thai end;
    if tg_op = 'UPDATE' and v_cu is not distinct from new.trang_thai then
      return new;
    end if;
    v_khoa := 'bd_khuon:' || new.tuan_bat_dau;
    v_lk := 'bao-duong-khuon-tuan.html?tuan=' || new.tuan_bat_dau;
    perform cv_pd_xong(v_khoa);
    if new.trang_thai in ('cho_kiem_tra', 'cho_phe_duyet') then
      perform cv_pd_bd_bao(new.tuan_bat_dau, new.trang_thai);
    elsif new.trang_thai = 'da_duyet' then
      perform cv_pd_gui(cv_pd_ds_ten(new.nguoi_lap), 'bd_khuon', 'da_duyet', v_khoa, v_lk,
        'Kế hoạch bảo dưỡng khuôn tuần ' || cv_pd_tuan(new.tuan_bat_dau) || ' đã được phê duyệt.', false);
    elsif new.trang_thai = 'nhap' and v_cu in ('cho_kiem_tra', 'cho_phe_duyet') then
      perform cv_pd_gui(cv_pd_ds_ten(new.nguoi_lap), 'bd_khuon', 'tu_choi_duyet', v_khoa, v_lk,
        'Kế hoạch bảo dưỡng khuôn tuần ' || cv_pd_tuan(new.tuan_bat_dau) || ' bị từ chối'
          || coalesce(': ' || nullif(trim(new.ly_do_tu_choi), ''), '') || '.', false);
    end if;
  exception when others then
    raise warning 'T162 thông báo BD khuôn lỗi (bỏ qua, không chặn thao tác): %', sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists trg_cv_pd_bd on public.duc_khuon_bd_duyet;
create trigger trg_cv_pd_bd after insert or update of trang_thai on public.duc_khuon_bd_duyet
  for each row execute function public.cv_pd_trg_bd();

-- ---------------------------------------------------------------------------
-- 5. Duyệt tiếp tục sản xuất IPQC (duc_ipqc_continue_request)
-- ---------------------------------------------------------------------------
create or replace function public.cv_pd_ipqc_mo_ta(r public.duc_ipqc_continue_request)
returns text language sql stable set search_path = public as $$
  select 'Yêu cầu tiếp tục sản xuất IPQC ' || coalesce(r.request_code, '#' || r.id)
    || ' (máy ' || coalesce(nullif(trim(r.machine), ''), '?')
    || ', mã SP ' || coalesce(nullif(trim(r.product_code), ''), '?') || ')';
$$;

create or replace function public.cv_pd_ipqc_bao(p_id bigint)
returns int language plpgsql security definer set search_path = public as $$
declare r duc_ipqc_continue_request%rowtype; v_buoc text;
begin
  select * into r from duc_ipqc_continue_request where id = p_id;
  if not found or r.status not in ('Chờ duyệt', 'Đang duyệt') then return 0; end if;
  v_buoc := case r.current_step when 1 then 'QL Chất lượng' when 2 then 'KHSX' when 3 then 'QL Đúc/Bộ phận sản xuất'
                                when 4 then 'GĐ Sản xuất' else 'bước ' || r.current_step end;
  return cv_pd_gui(cv_pd_ds_role(duc_ipqc_step_roles(r.current_step)), 'ipqc', 'can_duyet', 'ipqc:' || r.id,
    'ipqc-approval.html?requestId=' || r.id,
    cv_pd_ipqc_mo_ta(r) || ' đang chờ bạn duyệt (bước ' || r.current_step || ': ' || v_buoc || ').', true);
end;
$$;

create or replace function public.cv_pd_trg_ipqc()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_khoa text; v_lk text; v_cu text; v_ly_do text;
begin
  begin
    v_cu := case when tg_op = 'UPDATE' then old.status end;
    if tg_op = 'UPDATE' and old.status is not distinct from new.status
       and old.current_step is not distinct from new.current_step then
      return new;
    end if;
    v_khoa := 'ipqc:' || new.id;
    v_lk := 'ipqc-approval.html?requestId=' || new.id;
    if new.status in ('Chờ duyệt', 'Đang duyệt') then
      perform cv_pd_xong(v_khoa);
      perform cv_pd_ipqc_bao(new.id);
    elsif new.status in ('Đã duyệt', 'Đang có hiệu lực') then
      perform cv_pd_xong(v_khoa);
      if tg_op = 'INSERT' or v_cu in ('Chờ duyệt', 'Đang duyệt') then
        perform cv_pd_gui(array[new.requester_id], 'ipqc', 'da_duyet', v_khoa, v_lk,
          cv_pd_ipqc_mo_ta(new) || ' đã được duyệt' || coalesce(': ' || nullif(trim(new.approved_scope), ''), '') || '.', false);
      end if;
    elsif new.status = 'Từ chối' then
      perform cv_pd_xong(v_khoa);
      if v_cu is distinct from 'Từ chối' then
        select nullif(trim(a.note), '') into v_ly_do from duc_ipqc_continue_approval a
        where a.request_id = new.id and a.decision = 'Từ chối' order by a.decided_at desc nulls last limit 1;
        perform cv_pd_gui(array[new.requester_id], 'ipqc', 'tu_choi_duyet', v_khoa, v_lk,
          cv_pd_ipqc_mo_ta(new) || ' bị từ chối' || coalesce(': ' || v_ly_do, '') || '.', false);
      end if;
    else
      perform cv_pd_xong(v_khoa);   -- Đã hủy / Hết hiệu lực: chỉ đánh xong
    end if;
  exception when others then
    raise warning 'T162 thông báo IPQC lỗi (bỏ qua, không chặn thao tác): %', sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists trg_cv_pd_ipqc on public.duc_ipqc_continue_request;
create trigger trg_cv_pd_ipqc after insert or update of status, current_step on public.duc_ipqc_continue_request
  for each row execute function public.cv_pd_trg_ipqc();

-- ---------------------------------------------------------------------------
-- 6. NCP (duc_ncp): (a) duyệt Nguyên nhân & Đối sách, (b) duyệt báo phế
-- ---------------------------------------------------------------------------
create or replace function public.cv_pd_ncp_mo_ta(r public.duc_ncp)
returns text language sql stable set search_path = public as $$
  select 'phiếu NCP ' || r.id_ncp
    || ' (máy ' || coalesce(nullif(trim(r.ma_may), ''), '?')
    || ', mã SP ' || coalesce(nullif(trim(r.ma_sp), ''), '?') || ')';
$$;

create or replace function public.cv_pd_ncp_bao(p_id text)
returns int language plpgsql security definer set search_path = public as $$
declare r duc_ncp%rowtype; v_n int := 0;
begin
  select * into r from duc_ncp where id_ncp = p_id;
  if not found then return 0; end if;
  if r.rc_trang_thai_duyet = 'cho_duyet' then
    v_n := v_n + cv_pd_gui(cv_pd_ds_role(array['qc_manager']), 'ncp', 'can_duyet', 'ncp_rc:' || r.id_ncp,
      'ncp-detail.html?id=' || r.id_ncp,
      'Nguyên nhân & đối sách của ' || cv_pd_ncp_mo_ta(r) || ' đang chờ bạn duyệt.', true);
  end if;
  if r.trang_thai = 'cho_duyet_phe' then
    v_n := v_n + cv_pd_gui(cv_pd_ds_role(array['qc_manager']), 'ncp', 'can_duyet', 'ncp_phe:' || r.id_ncp,
      'qc-manager.html',
      'Đề nghị báo phế ' || coalesce(r.so_luong_de_nghi_phe::text, '?') || ' SP của ' || cv_pd_ncp_mo_ta(r)
        || ' đang chờ bạn duyệt' || coalesce(' (lý do: ' || nullif(trim(r.ly_do_phe), '') || ')', '') || '.', true);
  end if;
  return v_n;
end;
$$;

create or replace function public.cv_pd_trg_ncp()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_rc_cu text; v_tt_cu text; v_lk text;
begin
  begin
    v_rc_cu := case when tg_op = 'UPDATE' then old.rc_trang_thai_duyet end;
    v_tt_cu := case when tg_op = 'UPDATE' then old.trang_thai end;
    v_lk := 'ncp-detail.html?id=' || new.id_ncp;
    -- (a) Nguyên nhân & đối sách
    if tg_op = 'INSERT' or v_rc_cu is distinct from new.rc_trang_thai_duyet then
      perform cv_pd_xong('ncp_rc:' || new.id_ncp);
      if new.rc_trang_thai_duyet = 'cho_duyet' then
        perform cv_pd_gui(cv_pd_ds_role(array['qc_manager']), 'ncp', 'can_duyet', 'ncp_rc:' || new.id_ncp, v_lk,
          'Nguyên nhân & đối sách của ' || cv_pd_ncp_mo_ta(new) || ' đang chờ bạn duyệt.', true);
      elsif v_rc_cu = 'cho_duyet' and new.rc_trang_thai_duyet = 'da_duyet' then
        perform cv_pd_gui(cv_pd_ds_ten(new.rc_nguoi_gui_duyet), 'ncp', 'da_duyet', 'ncp_rc:' || new.id_ncp, v_lk,
          'Nguyên nhân & đối sách của ' || cv_pd_ncp_mo_ta(new) || ' đã được duyệt.', false);
      elsif v_rc_cu = 'cho_duyet' and new.rc_trang_thai_duyet = 'tu_choi' then
        perform cv_pd_gui(cv_pd_ds_ten(new.rc_nguoi_gui_duyet), 'ncp', 'tu_choi_duyet', 'ncp_rc:' || new.id_ncp, v_lk,
          'Nguyên nhân & đối sách của ' || cv_pd_ncp_mo_ta(new) || ' bị từ chối'
            || coalesce(': ' || nullif(trim(new.rc_ghi_chu_duyet), ''), '') || '.', false);
      end if;
    end if;
    -- (b) Đề nghị báo phế
    if tg_op = 'INSERT' or v_tt_cu is distinct from new.trang_thai then
      if new.trang_thai = 'cho_duyet_phe' then
        perform cv_pd_xong('ncp_phe:' || new.id_ncp);
        perform cv_pd_gui(cv_pd_ds_role(array['qc_manager']), 'ncp', 'can_duyet', 'ncp_phe:' || new.id_ncp, 'qc-manager.html',
          'Đề nghị báo phế ' || coalesce(new.so_luong_de_nghi_phe::text, '?') || ' SP của ' || cv_pd_ncp_mo_ta(new)
            || ' đang chờ bạn duyệt' || coalesce(' (lý do: ' || nullif(trim(new.ly_do_phe), '') || ')', '') || '.', true);
      elsif v_tt_cu = 'cho_duyet_phe' then
        perform cv_pd_xong('ncp_phe:' || new.id_ncp);
        if new.ket_qua_duyet_phe = 'Duyet' then
          perform cv_pd_gui(cv_pd_ds_ten(new.nguoi_de_nghi_phe), 'ncp', 'da_duyet', 'ncp_phe:' || new.id_ncp, v_lk,
            'Đề nghị báo phế ' || coalesce(new.so_luong_de_nghi_phe::text, '?') || ' SP của ' || cv_pd_ncp_mo_ta(new)
              || ' đã được duyệt.', false);
        elsif new.ket_qua_duyet_phe = 'Tu_choi' then
          perform cv_pd_gui(cv_pd_ds_ten(new.nguoi_de_nghi_phe), 'ncp', 'tu_choi_duyet', 'ncp_phe:' || new.id_ncp, v_lk,
            'Đề nghị báo phế ' || coalesce(new.so_luong_de_nghi_phe::text, '?') || ' SP của ' || cv_pd_ncp_mo_ta(new)
              || ' bị từ chối.', false);
        end if;
      end if;
    end if;
  exception when others then
    raise warning 'T162 thông báo NCP lỗi (bỏ qua, không chặn thao tác): %', sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists trg_cv_pd_ncp on public.duc_ncp;
create trigger trg_cv_pd_ncp after insert or update of rc_trang_thai_duyet, trang_thai on public.duc_ncp
  for each row execute function public.cv_pd_trg_ncp();

-- ---------------------------------------------------------------------------
-- 7. Phiếu thay đổi tài liệu (document_change_requests + dcr_confirmations
--    + dcr_approval_steps)
-- ---------------------------------------------------------------------------
-- Báo bước duyệt tới lượt (bước 'cho' thu_tu nhỏ nhất khi phiếu dang_duyet /
-- cho_khach_hang). p_moi = true → đánh xong thông báo bước cũ trước.
create or replace function public.cv_pd_dcr_bao_buoc(p_dcr uuid, p_moi boolean default false)
returns int language plpgsql security definer set search_path = public as $$
declare d document_change_requests%rowtype; s dcr_approval_steps%rowtype; v_nguoi uuid[]; v_buoc text;
begin
  select * into d from document_change_requests where id = p_dcr;
  if not found then return 0; end if;
  if p_moi then perform cv_pd_xong('dcr:' || d.id); end if;
  if d.trang_thai not in ('dang_duyet', 'cho_khach_hang') then return 0; end if;
  select * into s from dcr_approval_steps where dcr_id = d.id and trang_thai = 'cho' order by thu_tu limit 1;
  if not found then return 0; end if;
  if s.buoc = 'nguoi_duyet_uy_quyen' then
    select coalesce(array_agg(distinct u.user_id), '{}') into v_nguoi
    from user_roles u where document_is_delegate(u.user_id, d.tang, d.category_id);
    if cardinality(v_nguoi) = 0 then v_nguoi := cv_pd_ds_role(array['admin']); end if;  -- chưa khai uỷ quyền
    v_buoc := 'Người duyệt được uỷ quyền';
  elsif s.buoc = 'ban_giam_doc' then
    v_nguoi := cv_pd_ds_role(array['giam_doc_sx']); v_buoc := 'Ban giám đốc';
  elsif s.buoc = 'khach_hang' then
    v_nguoi := cv_pd_ds_role(array['ke_hoach', 'giam_doc_sx']); v_buoc := 'Xác nhận của khách hàng';
  elsif s.buoc = 'kstl' then
    v_nguoi := cv_pd_ds_role(array['admin']); v_buoc := 'Kiểm soát tài liệu';
  else
    return 0;
  end if;
  return cv_pd_gui(v_nguoi, 'tai_lieu', 'can_duyet', 'dcr:' || d.id, 'phieu-thay-doi-chi-tiet.html?id=' || d.id,
    'Phiếu thay đổi tài liệu "' || coalesce(nullif(trim(d.tieu_de), ''), '(không tiêu đề)')
      || '" đang chờ bạn duyệt (bước ' || v_buoc || ').', true);
end;
$$;

-- Báo bộ phận cần xác nhận (dòng dcr_confirmations đang 'cho').
create or replace function public.cv_pd_dcr_bao_xn(p_dcr uuid, p_bo_phan text)
returns int language plpgsql security definer set search_path = public as $$
declare d document_change_requests%rowtype;
begin
  select * into d from document_change_requests where id = p_dcr;
  if not found or d.trang_thai <> 'dang_xac_nhan' then return 0; end if;
  return cv_pd_gui(cv_pd_ds_bo_phan(p_bo_phan), 'tai_lieu', 'can_duyet', 'dcr:' || d.id || ':xn:' || p_bo_phan,
    'phieu-thay-doi-chi-tiet.html?id=' || d.id,
    'Phiếu thay đổi tài liệu "' || coalesce(nullif(trim(d.tieu_de), ''), '(không tiêu đề)')
      || '" đang chờ bộ phận ' || p_bo_phan || ' xác nhận.', true);
end;
$$;

create or replace function public.cv_pd_trg_dcr()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_cu text; v_lk text; v_ten text; v_ly_do text;
begin
  begin
    v_cu := case when tg_op = 'UPDATE' then old.trang_thai end;
    if tg_op = 'UPDATE' and v_cu is not distinct from new.trang_thai then
      return new;
    end if;
    v_lk := 'phieu-thay-doi-chi-tiet.html?id=' || new.id;
    v_ten := coalesce(nullif(trim(new.tieu_de), ''), '(không tiêu đề)');
    if new.trang_thai in ('dang_duyet', 'cho_khach_hang') then
      perform cv_pd_dcr_bao_buoc(new.id, false);
    elsif new.trang_thai in ('da_duyet', 'da_phat_hanh', 'tu_choi') then
      perform cv_pd_xong('dcr:' || new.id, true);
      if coalesce(v_cu, '') not in ('da_duyet', 'da_phat_hanh', 'tu_choi') then
        if new.trang_thai = 'tu_choi' then
          select nullif(trim(s.y_kien), '') into v_ly_do from dcr_approval_steps s
          where s.dcr_id = new.id and s.trang_thai = 'tu_choi' order by s.thoi_gian desc nulls last limit 1;
          perform cv_pd_gui(array[new.nguoi_lap], 'tai_lieu', 'tu_choi_duyet', 'dcr:' || new.id, v_lk,
            'Phiếu thay đổi tài liệu "' || v_ten || '" bị từ chối' || coalesce(': ' || v_ly_do, '') || '.', false);
        else
          perform cv_pd_gui(array[new.nguoi_lap], 'tai_lieu', 'da_duyet', 'dcr:' || new.id, v_lk,
            'Phiếu thay đổi tài liệu "' || v_ten || '" đã được duyệt'
              || case when new.trang_thai = 'da_phat_hanh' then ' và phát hành' else '' end || '.', false);
        end if;
      end if;
    end if;
  exception when others then
    raise warning 'T162 thông báo phiếu thay đổi tài liệu lỗi (bỏ qua, không chặn thao tác): %', sqlerrm;
  end;
  return new;
end;
$$;

create or replace function public.cv_pd_trg_dcr_xn()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    if tg_op = 'UPDATE' and old.trang_thai is not distinct from new.trang_thai then
      return new;
    end if;
    if new.trang_thai = 'cho' then
      perform cv_pd_dcr_bao_xn(new.dcr_id, new.bo_phan);
    else
      perform cv_pd_xong('dcr:' || new.dcr_id || ':xn:' || new.bo_phan);
    end if;
  exception when others then
    raise warning 'T162 thông báo xác nhận phiếu thay đổi lỗi (bỏ qua, không chặn thao tác): %', sqlerrm;
  end;
  return new;
end;
$$;

create or replace function public.cv_pd_trg_dcr_buoc()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    if tg_op = 'UPDATE' and old.trang_thai is not distinct from new.trang_thai then
      return new;
    end if;
    if tg_op = 'INSERT' then
      if new.trang_thai = 'cho' then perform cv_pd_dcr_bao_buoc(new.dcr_id, false); end if;
    elsif new.trang_thai = 'tu_choi' then
      perform cv_pd_xong('dcr:' || new.dcr_id);          -- phiếu sắp chuyển tu_choi, không báo bước sau
    else
      perform cv_pd_dcr_bao_buoc(new.dcr_id, true);       -- bước xong → báo bước kế (nếu còn)
    end if;
  exception when others then
    raise warning 'T162 thông báo bước duyệt phiếu thay đổi lỗi (bỏ qua, không chặn thao tác): %', sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists trg_cv_pd_dcr on public.document_change_requests;
create trigger trg_cv_pd_dcr after insert or update of trang_thai on public.document_change_requests
  for each row execute function public.cv_pd_trg_dcr();
drop trigger if exists trg_cv_pd_dcr_xn on public.dcr_confirmations;
create trigger trg_cv_pd_dcr_xn after insert or update of trang_thai on public.dcr_confirmations
  for each row execute function public.cv_pd_trg_dcr_xn();
drop trigger if exists trg_cv_pd_dcr_buoc on public.dcr_approval_steps;
create trigger trg_cv_pd_dcr_buoc after insert or update of trang_thai on public.dcr_approval_steps
  for each row execute function public.cv_pd_trg_dcr_buoc();

-- ---------------------------------------------------------------------------
-- 8. Quyền: helper + trigger function chỉ dùng nội bộ
-- ---------------------------------------------------------------------------
revoke execute on function public.cv_pd_ds_role(text[], text) from public, anon, authenticated;
revoke execute on function public.cv_pd_ds_bo_phan(text) from public, anon, authenticated;
revoke execute on function public.cv_pd_ds_ten(text) from public, anon, authenticated;
revoke execute on function public.cv_pd_gui(uuid[], text, text, text, text, text, boolean) from public, anon, authenticated;
revoke execute on function public.cv_pd_xong(text, boolean) from public, anon, authenticated;
revoke execute on function public.cv_pd_tuan(date) from public, anon, authenticated;
revoke execute on function public.cv_pd_khsx_bao(date, text, text) from public, anon, authenticated;
revoke execute on function public.cv_pd_khsx_nguoi_gui(date, text) from public, anon, authenticated;
revoke execute on function public.cv_pd_trg_khsx() from public, anon, authenticated;
revoke execute on function public.cv_pd_trg_khsx_log() from public, anon, authenticated;
revoke execute on function public.cv_pd_bd_bao(date, text) from public, anon, authenticated;
revoke execute on function public.cv_pd_trg_bd() from public, anon, authenticated;
revoke execute on function public.cv_pd_ipqc_mo_ta(public.duc_ipqc_continue_request) from public, anon, authenticated;
revoke execute on function public.cv_pd_ipqc_bao(bigint) from public, anon, authenticated;
revoke execute on function public.cv_pd_trg_ipqc() from public, anon, authenticated;
revoke execute on function public.cv_pd_ncp_mo_ta(public.duc_ncp) from public, anon, authenticated;
revoke execute on function public.cv_pd_ncp_bao(text) from public, anon, authenticated;
revoke execute on function public.cv_pd_trg_ncp() from public, anon, authenticated;
revoke execute on function public.cv_pd_dcr_bao_buoc(uuid, boolean) from public, anon, authenticated;
revoke execute on function public.cv_pd_dcr_bao_xn(uuid, text) from public, anon, authenticated;
revoke execute on function public.cv_pd_trg_dcr() from public, anon, authenticated;
revoke execute on function public.cv_pd_trg_dcr_xn() from public, anon, authenticated;
revoke execute on function public.cv_pd_trg_dcr_buoc() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 9. Sửa lỗi KHSX: khsx_duyet / khsx_tu_choi (T16) khai báo v_bp text trong khi
--    bo_phan_phu_trach là text[] → QLBP không duyệt/từ chối được bước
--    cho_quan_ly_bo_phan. Giữ nguyên mọi logic T16 (admin KHÔNG duyệt hộ),
--    chỉ đổi v_bp text[] và so p_cong_doan = any(coalesce(v_bp,'{}')).
-- ---------------------------------------------------------------------------
create or replace function public.khsx_duyet(p_tuan date, p_cong_doan text, p_user text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text; v_bp text[]; v_trang_thai text; v_buoc text; v_moi text;
begin
  select role, bo_phan_phu_trach into v_role, v_bp from public.user_roles where user_id = auth.uid();
  select trang_thai into v_trang_thai from khsx_duyet where tuan_bat_dau = p_tuan and cong_doan = p_cong_doan;
  if v_trang_thai is null then
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch chưa được gửi duyệt');
  end if;

  if v_trang_thai = 'cho_truong_phong' then
    if coalesce(v_role,'') <> 'qlsx_truong_phong' then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Trưởng phòng QLSX được duyệt bước này');
    end if;
    v_buoc := 'duyet_truong_phong'; v_moi := 'cho_quan_ly_bo_phan';
  elsif v_trang_thai = 'cho_quan_ly_bo_phan' then
    if not (coalesce(v_role,'') = 'quan_ly_bo_phan' and p_cong_doan = any(coalesce(v_bp, '{}'))) then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Quản lý bộ phận ' || p_cong_doan || ' được duyệt bước này');
    end if;
    v_buoc := 'duyet_quan_ly_bo_phan'; v_moi := 'cho_giam_doc';
  elsif v_trang_thai = 'cho_giam_doc' then
    if coalesce(v_role,'') <> 'giam_doc_sx' then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Giám đốc sản xuất được duyệt bước này');
    end if;
    v_buoc := 'duyet_giam_doc'; v_moi := 'da_duyet';
  else
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch không ở trạng thái chờ duyệt (' || v_trang_thai || ')');
  end if;

  update khsx_duyet set trang_thai = v_moi, updated_by = p_user, updated_at = now()
  where tuan_bat_dau = p_tuan and cong_doan = p_cong_doan;

  insert into khsx_thay_doi_log (tuan_bat_dau, cong_doan, loai_su_kien, nguoi_thuc_hien)
  values (p_tuan, p_cong_doan, v_buoc, p_user);

  return jsonb_build_object('ok', true, 'trang_thai_moi', v_moi);
end;
$$;

create or replace function public.khsx_tu_choi(p_tuan date, p_cong_doan text, p_ly_do text, p_user text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text; v_bp text[]; v_trang_thai text;
begin
  if p_ly_do is null or trim(p_ly_do) = '' then
    return jsonb_build_object('ok', false, 'error', 'Cần nhập lý do từ chối');
  end if;

  select role, bo_phan_phu_trach into v_role, v_bp from public.user_roles where user_id = auth.uid();
  select trang_thai into v_trang_thai from khsx_duyet where tuan_bat_dau = p_tuan and cong_doan = p_cong_doan;
  if v_trang_thai is null then
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch chưa được gửi duyệt');
  end if;

  if v_trang_thai = 'cho_truong_phong' then
    if coalesce(v_role,'') <> 'qlsx_truong_phong' then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Trưởng phòng QLSX được từ chối bước này');
    end if;
  elsif v_trang_thai = 'cho_quan_ly_bo_phan' then
    if not (coalesce(v_role,'') = 'quan_ly_bo_phan' and p_cong_doan = any(coalesce(v_bp, '{}'))) then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Quản lý bộ phận ' || p_cong_doan || ' được từ chối bước này');
    end if;
  elsif v_trang_thai = 'cho_giam_doc' then
    if coalesce(v_role,'') <> 'giam_doc_sx' then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Giám đốc sản xuất được từ chối bước này');
    end if;
  else
    return jsonb_build_object('ok', false, 'error', 'Kế hoạch không ở trạng thái chờ duyệt (' || v_trang_thai || ')');
  end if;

  update khsx_duyet set trang_thai = 'nhap', updated_by = p_user, updated_at = now()
  where tuan_bat_dau = p_tuan and cong_doan = p_cong_doan;

  insert into khsx_thay_doi_log (tuan_bat_dau, cong_doan, loai_su_kien, ly_do, nguoi_thuc_hien)
  values (p_tuan, p_cong_doan, 'tu_choi', p_ly_do, p_user);

  return jsonb_build_object('ok', true, 'trang_thai_moi', 'nhap');
end;
$$;

revoke execute on function public.khsx_duyet(date, text, text) from public, anon;
grant  execute on function public.khsx_duyet(date, text, text) to authenticated;
revoke execute on function public.khsx_tu_choi(date, text, text, text) from public, anon;
grant  execute on function public.khsx_tu_choi(date, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Backfill: 'can_duyet' cho mọi yêu cầu ĐANG CHỜ ở 5 luồng (người nhận
--     theo bước hiện tại). Idempotent nhờ cv_pd_gui bỏ qua người đã có thông
--     báo chưa xử lý cùng khoá.
-- ---------------------------------------------------------------------------
do $$
declare r record; v_n int := 0;
begin
  for r in select tuan_bat_dau, cong_doan, trang_thai from khsx_duyet
           where trang_thai in ('cho_truong_phong', 'cho_quan_ly_bo_phan', 'cho_giam_doc') loop
    v_n := v_n + cv_pd_khsx_bao(r.tuan_bat_dau, r.cong_doan, r.trang_thai);
  end loop;
  for r in select tuan_bat_dau, trang_thai from duc_khuon_bd_duyet
           where trang_thai in ('cho_kiem_tra', 'cho_phe_duyet') loop
    v_n := v_n + cv_pd_bd_bao(r.tuan_bat_dau, r.trang_thai);
  end loop;
  for r in select id from duc_ipqc_continue_request where status in ('Chờ duyệt', 'Đang duyệt') loop
    v_n := v_n + cv_pd_ipqc_bao(r.id);
  end loop;
  for r in select id_ncp from duc_ncp where rc_trang_thai_duyet = 'cho_duyet' or trang_thai = 'cho_duyet_phe' loop
    v_n := v_n + cv_pd_ncp_bao(r.id_ncp);
  end loop;
  for r in select c.dcr_id, c.bo_phan from dcr_confirmations c
           join document_change_requests d on d.id = c.dcr_id
           where c.trang_thai = 'cho' and d.trang_thai = 'dang_xac_nhan' loop
    v_n := v_n + cv_pd_dcr_bao_xn(r.dcr_id, r.bo_phan);
  end loop;
  for r in select id from document_change_requests where trang_thai in ('dang_duyet', 'cho_khach_hang') loop
    v_n := v_n + cv_pd_dcr_bao_buoc(r.id, false);
  end loop;
  raise notice 'T162 backfill: đã tạo % thông báo can_duyet', v_n;
end $$;
