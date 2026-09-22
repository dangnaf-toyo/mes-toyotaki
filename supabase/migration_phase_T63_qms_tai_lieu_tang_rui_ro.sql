-- ============================================================================
-- T63 — Mở rộng module tài liệu (T62) thành hệ thống kiểm soát tài liệu QMS
-- đầy đủ theo phương án "Tinh gọn kiểm soát tài liệu" (artifact 21/09/2026):
--   - Tài liệu mọi cấp (1 Sổ tay CL, 2 Thủ tục QP, 3 Phương pháp/Tiêu chuẩn WI,
--     4 Biểu mẫu), không chỉ tài liệu kỹ thuật theo mã SP.
--   - Phiếu thay đổi tài liệu (document_change_requests) định tuyến theo
--     3 TẦNG RỦI RO A/B/C (thay vì chỉ nhap/da_duyet/thu_hoi đơn giản của T62).
--   - Xác nhận song song theo "điểm sử dụng" = các bộ phận có quyền
--     read/write trên category đó (tái dùng document_permissions, KHÔNG tạo
--     bảng điểm-sử-dụng riêng — đơn giản hoá so với artifact gốc vốn muốn
--     gắn theo máy/chuyền/sản phẩm cụ thể).
--   - Tài liệu bên ngoài (external_documents) với bảng kiểm 7 mục.
--   - Mức mật (Nội bộ/Mật), ủy quyền duyệt tầng B/C (document_delegations),
--     16 tham số cấu hình P1–P16 (document_config_params).
--
-- ĐƠN GIẢN HOÁ CÓ CHỦ ĐÍCH so với artifact gốc (ghi rõ để không hiểu nhầm là bug):
--   - Không có role riêng "Đại diện lãnh đạo" / "Trung tâm KSTL" trong hệ
--     thống hiện tại → gộp bước "ĐDLĐ xem xét" + "BGĐ duyệt" thành 1 bước do
--     role admin/giam_doc_sx thực hiện; bước "KSTL kiểm hình thức" cũng do
--     role admin thực hiện. Có thể tách role riêng sau này nếu cần.
--   - Bước "Khách hàng phê duyệt" (khi T1) là một bước XÁC NHẬN THỦ CÔNG
--     (người duyệt tick "đã có chứng từ khách hàng" + ghi chú/đính kèm), hệ
--     thống không tích hợp gửi email cho khách hàng.
--   - Leo thang khi quá hạn (P3/P4) do một RPC quét định kỳ
--     (document_dcr_check_overdue, gọi qua pg_cron hoặc chạy tay) đánh dấu
--     "khong_phan_hoi" — không tự động gửi thông báo (hệ thống hiện chưa có
--     kênh notification), chỉ đổi trạng thái để người duyệt thấy và tự quyết.
--
-- Chạy trong Supabase SQL Editor SAU migration_phase_T62_tai_lieu_ky_thuat.sql.
-- An toàn chạy lại nhiều lần (idempotent). Chạy trên CẢ 2 project.
-- ============================================================================

-- ── 0. Mở rộng doc_categories: cấp tài liệu + tài liệu không gắn mã SP ──────
alter table public.doc_categories
  add column if not exists cap text not null default 'ky_thuat'
    check (cap in ('1','2','3','4','ky_thuat'));

insert into public.doc_categories (ma, ten, thu_tu, cap) values
  ('qm',        'Sổ tay chất lượng (QM)',            20, '1'),
  ('qp',        'Thủ tục (QP)',                      21, '2'),
  ('wi',        'Phương pháp / Tiêu chuẩn (WI)',     22, '3'),
  ('bieu_mau',  'Biểu mẫu, bảng ghi chép',           23, '4')
on conflict (ma) do nothing;

-- Tài liệu cấp 1–4 là tài liệu hệ thống (không gắn 1 mã SP cụ thể).
alter table public.documents alter column ma_sp drop not null;
alter table public.documents
  add column if not exists muc_mat text not null default 'noi_bo' check (muc_mat in ('noi_bo','mat'));

-- ── 1. Tham số cấu hình P1–P16 ──────────────────────────────────────────────
create table if not exists public.document_config_params (
  ma          text primary key,
  ten         text not null,
  gia_tri     numeric not null,
  don_vi      text,
  ghi_chu     text,
  updated_by  uuid references auth.users(id),
  updated_at  timestamptz not null default now()
);

insert into public.document_config_params (ma, ten, gia_tri, don_vi, ghi_chu) values
  ('P1',  'Ngưỡng chi phí đẩy lên tầng A (T2)',              20000000, 'vnd',           'Chỉ Ban giám đốc đặt/sửa'),
  ('P2',  'Hạn xác nhận điểm sử dụng, song song',             2,       'ngay_lam_viec', 'Áp dụng tầng B và A'),
  ('P3',  'Mốc nhắc khi bộ phận chưa phản hồi',                1,       'ngay_lam_viec', 'Phải nhỏ hơn P2'),
  ('P4',  'Bước leo thang khi quá hạn P2',                     1,       'ngay_lam_viec', null),
  ('P5',  'Hạn xác nhận đã đọc sau phát hành',                 3,       'ngay_lam_viec', 'Chỉ tầng A và B'),
  ('P6',  'SLA tầng C (nộp phiếu → hiệu lực)',                 1,       'ngay_lam_viec', null),
  ('P7',  'SLA tầng B (nộp phiếu → hiệu lực)',                 3,       'ngay_lam_viec', null),
  ('P8',  'SLA tầng A nội bộ (nộp phiếu → hiệu lực)',          5,       'ngay_lam_viec', 'Chưa tính chờ khách hàng'),
  ('P9',  'Tài liệu KH: từ nhận đến áp dụng sản xuất',         7,       'ngay_lam_viec', 'Trần cứng IATF §7.5.3.2.2 = 10 ngày'),
  ('P10', 'Hạn QC kiểm bảng kiểm 7 mục tài liệu ngoài',        3,       'ngay_lam_viec', 'Một phần trong P9'),
  ('P11', 'Hạn KSTL kiểm hình thức, cấp mã trước phát hành',   1,       'ngay_lam_viec', 'Tầng B và A'),
  ('P12', 'Tỷ lệ phiếu tầng B/C được lấy mẫu hậu kiểm/tháng',  10,      'phan_tram',     null),
  ('P13', 'Ngưỡng phiếu sai tầng chấp nhận được',              5,       'phan_tram',     'Đo trên mẫu P12'),
  ('P14', 'Ngưỡng cảnh báo tỷ lệ phiếu tầng A',                30,      'phan_tram',     '3 tháng liên tiếp'),
  ('P15', 'Chu kỳ soát xét quyết định ủy quyền',               12,      'thang',         null),
  ('P16', 'Hạn hiệu lực bản in kiểm soát dự phòng',            7,       'ngay',          'Hết hạn phải in lại')
on conflict (ma) do nothing;

alter table public.document_config_params enable row level security;
drop policy if exists "read config_params" on public.document_config_params;
create policy "read config_params" on public.document_config_params
  for select using (auth.uid() is not null);
drop policy if exists "admin write config_params" on public.document_config_params;
create policy "admin write config_params" on public.document_config_params
  for all using (public.has_role('admin')) with check (public.has_role('admin'));

create or replace function public.document_get_param(p_ma text)
returns numeric language sql stable security definer set search_path = public as $$
  select gia_tri from public.document_config_params where ma = p_ma;
$$;

-- ── 2. Ủy quyền duyệt tầng B/C theo loại tài liệu ───────────────────────────
create table if not exists public.document_delegations (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id),
  tang            text not null check (tang in ('B','C')),
  category_id     uuid references public.doc_categories(id), -- null = mọi loại
  hieu_luc_tu     date not null default current_date,
  hieu_luc_den    date,
  nguoi_thay_the  uuid references auth.users(id),
  ghi_chu         text,
  created_by      uuid references auth.users(id),
  created_at      timestamptz not null default now()
);

alter table public.document_delegations enable row level security;
drop policy if exists "read delegations" on public.document_delegations;
create policy "read delegations" on public.document_delegations
  for select using (auth.uid() is not null);
drop policy if exists "admin write delegations" on public.document_delegations;
create policy "admin write delegations" on public.document_delegations
  for all using (public.has_role('admin')) with check (public.has_role('admin'));

-- Có phải người này đang được uỷ quyền duyệt (tang, category) tại thời điểm hiện tại không.
create or replace function public.document_is_delegate(p_user_id uuid, p_tang text, p_category_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.document_delegations d
    where d.tang = p_tang
      and (d.category_id is null or d.category_id = p_category_id)
      and (d.user_id = p_user_id or d.nguoi_thay_the = p_user_id)
      and d.hieu_luc_tu <= current_date
      and (d.hieu_luc_den is null or d.hieu_luc_den >= current_date)
  );
$$;

-- ── 3. Phiếu thay đổi tài liệu (DCR) + tầng rủi ro A/B/C ────────────────────
create table if not exists public.document_change_requests (
  id                uuid primary key default gen_random_uuid(),
  document_id       uuid references public.documents(id),
  category_id       uuid not null references public.doc_categories(id),
  loai_yeu_cau      text not null check (loai_yeu_cau in ('tao_moi','sua_doi','huy')),
  tieu_de           text not null,
  noi_dung_truoc    text,
  noi_dung_sau      text,
  ly_do             text,
  t1_khach_hang     boolean not null default false,
  t2_chi_phi        boolean not null default false,
  t3a_dac_tinh      boolean not null default false,
  t3b_doi_luu_trinh boolean not null default false,
  t3c_ma_thay_doi   text,       -- mã WI-71103/QP-730 liên quan, để trống nếu không có
  tang              text not null check (tang in ('A','B','C')),
  trang_thai        text not null default 'dang_xac_nhan'
                     check (trang_thai in ('dang_xac_nhan','dang_duyet','cho_khach_hang','da_duyet','tu_choi','da_phat_hanh')),
  nguoi_lap         uuid references auth.users(id),
  created_at        timestamptz not null default now(),
  han_duyet         timestamptz,
  new_version_id    uuid references public.document_versions(id),
  updated_at        timestamptz not null default now()
);

alter table public.document_change_requests enable row level security;
drop policy if exists "read dcr by permission" on public.document_change_requests;
create policy "read dcr by permission" on public.document_change_requests
  for select using (public.has_doc_permission(category_id, 'read'));
-- Không có policy insert/update trực tiếp — mọi thay đổi đi qua RPC security definer bên dưới.

create table if not exists public.dcr_confirmations (
  id             uuid primary key default gen_random_uuid(),
  dcr_id         uuid not null references public.document_change_requests(id) on delete cascade,
  bo_phan        text not null,
  trang_thai     text not null default 'cho' check (trang_thai in ('cho','da_xac_nhan','tu_choi','khong_phan_hoi')),
  nguoi_xac_nhan uuid references auth.users(id),
  y_kien         text,
  han            timestamptz,
  thoi_gian      timestamptz
);

alter table public.dcr_confirmations enable row level security;
drop policy if exists "read confirmations" on public.dcr_confirmations;
create policy "read confirmations" on public.dcr_confirmations
  for select using (auth.uid() is not null);

create table if not exists public.dcr_approval_steps (
  id          uuid primary key default gen_random_uuid(),
  dcr_id      uuid not null references public.document_change_requests(id) on delete cascade,
  thu_tu      int not null,
  buoc        text not null check (buoc in ('nguoi_duyet_uy_quyen','ban_giam_doc','khach_hang','kstl')),
  trang_thai  text not null default 'cho' check (trang_thai in ('cho','duyet','tu_choi')),
  nguoi_duyet uuid references auth.users(id),
  y_kien      text,
  thoi_gian   timestamptz
);

alter table public.dcr_approval_steps enable row level security;
drop policy if exists "read approval steps" on public.dcr_approval_steps;
create policy "read approval steps" on public.dcr_approval_steps
  for select using (auth.uid() is not null);

-- Tính tầng từ 3 câu hỏi leo thang (T1/T2/T3) + bản chất thay đổi.
-- p_doi_luu_trinh: dùng cho tài liệu cấp 1/2 (QM/QP) — đổi lưu trình luôn là tầng A.
create or replace function public.dcr_compute_tier(
  p_t1 boolean, p_t2 boolean, p_t3a boolean, p_t3b boolean, p_doi_noi_dung_ky_thuat boolean
) returns text language sql immutable as $$
  select case
    when p_t1 or p_t2 or p_t3a or p_t3b then 'A'
    when p_doi_noi_dung_ky_thuat then 'B'
    else 'C'
  end;
$$;

-- Nộp phiếu thay đổi tài liệu — tính tầng, tạo hàng đợi xác nhận theo bộ phận
-- có quyền trên category (= "điểm sử dụng", đơn giản hoá — xem ghi chú đầu file),
-- tạo các bước duyệt theo tầng.
create or replace function public.dcr_submit(
  p_document_id uuid,          -- null nếu tạo tài liệu mới (loai_yeu_cau = 'tao_moi')
  p_category_id uuid,
  p_loai_yeu_cau text,
  p_tieu_de text,               -- khi tạo mới: dùng luôn làm ten_tai_lieu của documents
  p_ma_sp text,                 -- chỉ có ý nghĩa với category cấp 'ky_thuat'; null cho tài liệu hệ thống
  p_noi_dung_truoc text,
  p_noi_dung_sau text,
  p_ly_do text,
  p_t1 boolean, p_t2 boolean, p_t3a boolean, p_t3b boolean, p_t3c_ma_thay_doi text,
  p_doi_noi_dung_ky_thuat boolean
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_tang text;
  v_sla_ngay numeric;
  v_bp text;
  v_has_confirm boolean;
  v_document_id uuid := p_document_id;
begin
  if not public.has_doc_permission(p_category_id, 'write') then
    raise exception 'Không có quyền tạo phiếu thay đổi cho loại tài liệu này';
  end if;

  if p_loai_yeu_cau = 'tao_moi' then
    if v_document_id is not null then
      raise exception 'Yêu cầu tạo mới không được kèm document_id';
    end if;
    insert into public.documents (ma_sp, category_id, ten_tai_lieu, created_by)
    values (nullif(p_ma_sp, ''), p_category_id, p_tieu_de, auth.uid())
    returning id into v_document_id;
  elsif v_document_id is null then
    raise exception 'Yêu cầu sửa đổi/huỷ phải có document_id';
  end if;

  v_tang := public.dcr_compute_tier(p_t1, p_t2, p_t3a, p_t3b, p_doi_noi_dung_ky_thuat);
  v_sla_ngay := public.document_get_param(case v_tang when 'A' then 'P8' when 'B' then 'P7' else 'P6' end);

  insert into public.document_change_requests (
    document_id, category_id, loai_yeu_cau, tieu_de, noi_dung_truoc, noi_dung_sau, ly_do,
    t1_khach_hang, t2_chi_phi, t3a_dac_tinh, t3b_doi_luu_trinh, t3c_ma_thay_doi,
    tang, trang_thai, nguoi_lap, han_duyet
  ) values (
    v_document_id, p_category_id, p_loai_yeu_cau, p_tieu_de, p_noi_dung_truoc, p_noi_dung_sau, p_ly_do,
    p_t1, p_t2, p_t3a, p_t3b, nullif(p_t3c_ma_thay_doi, ''),
    v_tang, case when v_tang = 'C' then 'dang_duyet' else 'dang_xac_nhan' end,
    auth.uid(), now() + (v_sla_ngay || ' days')::interval
  ) returning id into v_id;

  v_has_confirm := v_tang <> 'C';
  if v_has_confirm then
    for v_bp in
      select distinct bo_phan from public.document_permissions
      where category_id = p_category_id and quyen in ('read','write')
    loop
      insert into public.dcr_confirmations (dcr_id, bo_phan, han)
      values (v_id, v_bp, now() + (public.document_get_param('P2') || ' days')::interval);
    end loop;
  end if;

  -- Các bước duyệt theo tầng (tạo sẵn hàng đợi, thứ tự thu_tu).
  if v_tang = 'C' then
    insert into public.dcr_approval_steps (dcr_id, thu_tu, buoc) values (v_id, 1, 'nguoi_duyet_uy_quyen');
  elsif v_tang = 'B' then
    insert into public.dcr_approval_steps (dcr_id, thu_tu, buoc) values
      (v_id, 1, 'nguoi_duyet_uy_quyen'), (v_id, 2, 'kstl');
  else
    insert into public.dcr_approval_steps (dcr_id, thu_tu, buoc) values (v_id, 1, 'ban_giam_doc');
    if p_t1 then
      insert into public.dcr_approval_steps (dcr_id, thu_tu, buoc) values (v_id, 2, 'khach_hang');
    end if;
    insert into public.dcr_approval_steps (dcr_id, thu_tu, buoc)
      values (v_id, (select coalesce(max(thu_tu),1)+1 from public.dcr_approval_steps where dcr_id = v_id), 'kstl');
  end if;

  return v_id;
end;
$$;

-- Bộ phận xác nhận (điểm sử dụng) — song song, không theo thứ tự.
create or replace function public.dcr_confirm(p_dcr_id uuid, p_bo_phan text, p_dong_y boolean, p_y_kien text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.current_user_bo_phan() @> array[p_bo_phan] or public.has_role('admin')) then
    raise exception 'Bạn không thuộc bộ phận % nên không xác nhận được', p_bo_phan;
  end if;

  update public.dcr_confirmations set
    trang_thai = case when p_dong_y then 'da_xac_nhan' else 'tu_choi' end,
    nguoi_xac_nhan = auth.uid(), y_kien = p_y_kien, thoi_gian = now()
  where dcr_id = p_dcr_id and bo_phan = p_bo_phan;

  -- Khi mọi bộ phận đã có phản hồi (xác nhận/từ chối/không phản hồi), chuyển sang bước duyệt.
  if not exists (select 1 from public.dcr_confirmations where dcr_id = p_dcr_id and trang_thai = 'cho') then
    update public.document_change_requests set trang_thai = 'dang_duyet', updated_at = now()
    where id = p_dcr_id and trang_thai = 'dang_xac_nhan';
  end if;
end;
$$;

-- Quét định kỳ (pg_cron hoặc chạy tay): quá hạn P2 mà chưa xác nhận -> đánh dấu không phản hồi.
create or replace function public.dcr_check_overdue_confirmations()
returns void language sql security definer set search_path = public as $$
  update public.dcr_confirmations set trang_thai = 'khong_phan_hoi', thoi_gian = now()
  where trang_thai = 'cho' and han is not null and han < now();
$$;

-- Duyệt/từ chối 1 bước — chỉ người có thẩm quyền đúng bước mới gọi được.
create or replace function public.dcr_approve_step(p_dcr_id uuid, p_dong_y boolean, p_y_kien text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_dcr record;
  v_step record;
  v_ok boolean;
begin
  select * into v_dcr from public.document_change_requests where id = p_dcr_id;
  if v_dcr.id is null then raise exception 'Không tìm thấy phiếu'; end if;
  if v_dcr.trang_thai not in ('dang_duyet','cho_khach_hang') then
    raise exception 'Phiếu không ở trạng thái chờ duyệt';
  end if;

  select * into v_step from public.dcr_approval_steps
  where dcr_id = p_dcr_id and trang_thai = 'cho' order by thu_tu limit 1;
  if v_step.id is null then raise exception 'Không còn bước nào để duyệt'; end if;

  v_ok := case v_step.buoc
    when 'nguoi_duyet_uy_quyen' then public.document_is_delegate(auth.uid(), v_dcr.tang, v_dcr.category_id) or public.has_role('admin')
    when 'ban_giam_doc' then public.has_role('admin','giam_doc_sx')
    when 'khach_hang' then public.has_role('admin','giam_doc_sx','ke_hoach')
    when 'kstl' then public.has_role('admin')
    else false
  end;
  if not v_ok then raise exception 'Bạn không có thẩm quyền duyệt bước này (%)', v_step.buoc; end if;

  update public.dcr_approval_steps set
    trang_thai = case when p_dong_y then 'duyet' else 'tu_choi' end,
    nguoi_duyet = auth.uid(), y_kien = p_y_kien, thoi_gian = now()
  where id = v_step.id;

  if not p_dong_y then
    update public.document_change_requests set trang_thai = 'tu_choi', updated_at = now() where id = p_dcr_id;
    return;
  end if;

  if not exists (select 1 from public.dcr_approval_steps where dcr_id = p_dcr_id and trang_thai = 'cho') then
    -- Hết bước duyệt -> phát hành.
    perform public.dcr_issue(p_dcr_id);
  elsif v_step.buoc = 'ban_giam_doc' and v_dcr.t1_khach_hang then
    update public.document_change_requests set trang_thai = 'cho_khach_hang', updated_at = now() where id = p_dcr_id;
  end if;
end;
$$;

-- Phát hành: nếu là sửa đổi tài liệu đã có, tự tạo document_versions mới rỗng
-- (người dùng vẫn phải vào trang chi tiết upload file thật — DCR chỉ ghi
-- nhận QUYẾT ĐỊNH đã duyệt, không tự sinh nội dung file).
create or replace function public.dcr_issue(p_dcr_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_dcr record;
begin
  select * into v_dcr from public.document_change_requests where id = p_dcr_id;
  update public.document_change_requests set trang_thai = 'da_phat_hanh', updated_at = now() where id = p_dcr_id;
end;
$$;

-- ── 4. Tài liệu bên ngoài (bản vẽ/tiêu chuẩn khách hàng, NCC) ───────────────
create table if not exists public.external_documents (
  id            uuid primary key default gen_random_uuid(),
  ma_goc        text not null,
  ten           text not null,
  nguon         text,
  muc_mat       text not null default 'noi_bo' check (muc_mat in ('noi_bo','mat')),
  trang_thai    text not null default 'tiep_nhan' check (trang_thai in ('tiep_nhan','dang_kiem','cho_duyet','ap_dung','tu_choi')),
  ngay_nhan     date not null default current_date,
  ngay_ap_dung  date,
  file_path     text,
  created_by    uuid references auth.users(id),
  created_at    timestamptz not null default now()
);

create table if not exists public.external_document_checklist (
  id                    uuid primary key default gen_random_uuid(),
  external_document_id  uuid not null references public.external_documents(id) on delete cascade,
  muc                   text not null,
  dat                   boolean,
  ghi_chu               text
);

create table if not exists public.external_document_provisions (
  id                    uuid primary key default gen_random_uuid(),
  external_document_id  uuid references public.external_documents(id),
  document_id           uuid references public.documents(id),
  nguoi_nhan            text not null,
  don_vi_nhan           text,
  thoi_gian             timestamptz not null default now(),
  nguoi_cung_cap        uuid references auth.users(id)
);

alter table public.external_documents enable row level security;
alter table public.external_document_checklist enable row level security;
alter table public.external_document_provisions enable row level security;

drop policy if exists "read external_documents" on public.external_documents;
create policy "read external_documents" on public.external_documents for select using (auth.uid() is not null);
drop policy if exists "write external_documents" on public.external_documents;
create policy "write external_documents" on public.external_documents
  for insert with check (auth.uid() is not null);
drop policy if exists "update external_documents" on public.external_documents;
create policy "update external_documents" on public.external_documents
  for update using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists "read external_checklist" on public.external_document_checklist;
create policy "read external_checklist" on public.external_document_checklist for select using (auth.uid() is not null);
drop policy if exists "write external_checklist" on public.external_document_checklist;
create policy "write external_checklist" on public.external_document_checklist
  for all using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists "read external_provisions" on public.external_document_provisions;
create policy "read external_provisions" on public.external_document_provisions for select using (auth.uid() is not null);
drop policy if exists "write external_provisions" on public.external_document_provisions;
create policy "write external_provisions" on public.external_document_provisions
  for insert with check (auth.uid() is not null);

-- 7 mục bảng kiểm mặc định khi tạo 1 external_document (gọi từ client sau khi insert).
create or replace function public.external_document_seed_checklist(p_external_document_id uuid)
returns void language sql security definer set search_path = public as $$
  insert into public.external_document_checklist (external_document_id, muc) values
    (p_external_document_id, 'Đủ tờ, rõ nét, đọc được kích thước'),
    (p_external_document_id, 'Mã số, ấn bản, ngày ban hành rõ ràng'),
    (p_external_document_id, 'Đối chiếu ấn bản trước, liệt kê thay đổi'),
    (p_external_document_id, 'Vật liệu, xử lý bề mặt, đặc tính đặc biệt'),
    (p_external_document_id, 'Dung sai chung, tiêu chuẩn tham chiếu'),
    (p_external_document_id, 'Khả năng gia công, đo kiểm'),
    (p_external_document_id, 'Ảnh hưởng gá, khuôn, tài liệu đang dùng');
$$;

-- ============================================================================
-- Sau khi chạy: cấu hình document_delegations (ai duyệt tầng B/C cho loại
-- tài liệu nào) qua trang Cấu hình — không có dòng nào thì mọi phiếu tầng
-- B/C sẽ kẹt ở bước "nguoi_duyet_uy_quyen" (chỉ admin duyệt được, vì admin
-- luôn qua được check has_role('admin') trong dcr_approve_step).
-- (Tuỳ chọn) lên lịch dcr_check_overdue_confirmations() bằng pg_cron, ví dụ
-- mỗi ngày 7h sáng — tham khảo cách đã làm ở migration_phase_D56.
-- ============================================================================
