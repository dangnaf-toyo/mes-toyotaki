-- ============================================================================
-- Phase T161 — Module "Quản lý công việc" (giao việc, chi tiết, Kanban, ma trận
-- ưu tiên, bình luận / góp ý, thông báo trong MES, việc của tôi).
-- Hợp đồng dữ liệu: docs/CONG_VIEC_THIET_KE.md (tên bảng/cột/hàm phải khớp).
--
-- - Bảng cv_* bật RLS, chỉ có policy SELECT. Mọi ghi đi qua RPC security
--   definer (revoke public/anon, grant authenticated).
-- - Ai xem được: hien_thi = 'cong_khai' → mọi tài khoản; 'han_che' → người
--   giao, người làm, người phối hợp, Ban giám đốc (admin / giam_doc_sx).
-- - Thông báo nằm ở cv_thong_bao (chuông navbar). Không gửi cho chính người
--   thao tác. Quét quá hạn mỗi giờ bằng pg_cron (job 'cv_quet_qua_han').
-- - Bucket "cong-viec": đọc công khai, ghi cho authenticated, đường dẫn
--   <cong_viec_id>/<tên file>.
-- An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Bảng
-- ---------------------------------------------------------------------------
create table if not exists public.cv_bo_phan (
  ten     text primary key,
  thu_tu  int not null default 0
);

insert into public.cv_bo_phan (ten, thu_tu) values
  ('Ban giám đốc', 1), ('Đúc', 2), ('Bavia', 3), ('Gia công CNC', 4), ('Sơn', 5),
  ('Chất lượng (QC)', 6), ('Kho', 7), ('Kế hoạch', 8), ('Bảo trì', 9), ('Kỹ thuật', 10),
  ('Hành chính – Nhân sự', 11), ('Kinh doanh', 12), ('Mua hàng', 13)
on conflict (ten) do update set thu_tu = excluded.thu_tu;

create table if not exists public.cv_du_an (
  id             bigserial primary key,
  ten            text not null,
  mo_ta          text,
  bo_phan        text references public.cv_bo_phan(ten) on update cascade,
  chu_du_an      uuid not null references auth.users(id),
  ngay_bat_dau   date,
  ngay_ket_thuc  date,
  trang_thai     text not null default 'dang_chay' check (trang_thai in ('dang_chay','tam_dung','hoan_thanh','huy')),
  created_at     timestamptz not null default now(),
  created_by     uuid
);

create table if not exists public.cv_cong_viec (
  id                  bigserial primary key,
  tieu_de             text not null,
  mo_ta               text,
  nguoi_giao          uuid not null,
  nguoi_lam           uuid not null,
  bo_phan             text not null references public.cv_bo_phan(ten) on update cascade,
  du_an_id            bigint references public.cv_du_an(id) on delete set null,
  quan_trong          boolean not null default false,
  gap                 boolean not null default false,
  han_ban_dau         timestamptz not null,
  han                 timestamptz not null,
  trang_thai          text not null default 'moi' check (trang_thai in ('moi','dang_lam','cho_duyet','hoan_thanh','huy')),
  can_duyet           boolean not null default true,
  hien_thi            text not null default 'cong_khai' check (hien_thi in ('cong_khai','han_che')),
  so_lan_tra_lai      int not null default 0,
  lien_ket            jsonb not null default '[]'::jsonb,
  gia_han_den         timestamptz,
  gia_han_ly_do       text,
  lap_lai             text not null default 'khong' check (lap_lai in ('khong','tuan','thang','quy')),
  nhan_luc            timestamptz,
  bao_xong_luc        timestamptz,
  hoan_thanh_luc      timestamptz,
  dung_han            boolean,
  qua_han_da_bao_luc  timestamptz,
  tu_gop_y_id         bigint,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index if not exists idx_cv_cong_viec_nguoi_lam  on public.cv_cong_viec (nguoi_lam);
create index if not exists idx_cv_cong_viec_nguoi_giao on public.cv_cong_viec (nguoi_giao);
create index if not exists idx_cv_cong_viec_trang_thai on public.cv_cong_viec (trang_thai);
create index if not exists idx_cv_cong_viec_bo_phan    on public.cv_cong_viec (bo_phan);
create index if not exists idx_cv_cong_viec_du_an      on public.cv_cong_viec (du_an_id);
create index if not exists idx_cv_cong_viec_han_mo     on public.cv_cong_viec (han) where trang_thai not in ('hoan_thanh','huy');

create table if not exists public.cv_nguoi_phoi_hop (
  cong_viec_id  bigint not null references public.cv_cong_viec(id) on delete cascade,
  user_id       uuid not null,
  primary key (cong_viec_id, user_id)
);
create index if not exists idx_cv_phoi_hop_user on public.cv_nguoi_phoi_hop (user_id);

create table if not exists public.cv_checklist (
  id            bigserial primary key,
  cong_viec_id  bigint not null references public.cv_cong_viec(id) on delete cascade,
  thu_tu        int not null default 0,
  noi_dung      text not null,
  xong          boolean not null default false,
  xong_luc      timestamptz,
  xong_boi      uuid
);
create index if not exists idx_cv_checklist_cv on public.cv_checklist (cong_viec_id, thu_tu);

create table if not exists public.cv_binh_luan (
  id                bigserial primary key,
  cong_viec_id      bigint references public.cv_cong_viec(id) on delete cascade,
  du_an_id          bigint references public.cv_du_an(id) on delete cascade,
  nguoi_viet        uuid not null,
  loai              text not null default 'binh_luan' check (loai in ('binh_luan','gop_y','cau_hoi','de_xuat','cap_nhat','tra_lai')),
  noi_dung          text not null,
  trang_thai_gop_y  text check (trang_thai_gop_y in ('dang_xem_xet','da_tiep_thu','da_tra_loi','khong_ap_dung')),
  tra_loi           text,
  cong_viec_tao_ra  bigint,
  created_at        timestamptz not null default now(),
  constraint cv_binh_luan_mot_dich check ((cong_viec_id is null) <> (du_an_id is null))
);
create index if not exists idx_cv_binh_luan_cv    on public.cv_binh_luan (cong_viec_id, created_at);
create index if not exists idx_cv_binh_luan_du_an on public.cv_binh_luan (du_an_id, created_at);

create table if not exists public.cv_dong_tinh (
  binh_luan_id  bigint not null references public.cv_binh_luan(id) on delete cascade,
  user_id       uuid not null,
  created_at    timestamptz not null default now(),
  primary key (binh_luan_id, user_id)
);

create table if not exists public.cv_tep (
  id            bigserial primary key,
  cong_viec_id  bigint not null references public.cv_cong_viec(id) on delete cascade,
  binh_luan_id  bigint references public.cv_binh_luan(id) on delete set null,
  duong_dan     text not null,
  ten_tep       text,
  loai_mime     text,
  created_by    uuid,
  created_at    timestamptz not null default now()
);
create index if not exists idx_cv_tep_cv on public.cv_tep (cong_viec_id);

create table if not exists public.cv_lich_su (
  id            bigserial primary key,
  cong_viec_id  bigint not null references public.cv_cong_viec(id) on delete cascade,
  nguoi         uuid,
  hanh_dong     text not null,
  noi_dung      text,
  created_at    timestamptz not null default now()
);
create index if not exists idx_cv_lich_su_cv on public.cv_lich_su (cong_viec_id, created_at);

create table if not exists public.cv_thong_bao (
  id            bigserial primary key,
  nguoi_nhan    uuid not null,
  loai          text not null,
  cong_viec_id  bigint references public.cv_cong_viec(id) on delete cascade,
  du_an_id      bigint references public.cv_du_an(id) on delete cascade,
  noi_dung      text not null,
  can_xu_ly     boolean not null default false,
  da_xu_ly      boolean not null default false,
  da_doc        boolean not null default false,
  da_doc_luc    timestamptz,
  created_at    timestamptz not null default now()
);
create index if not exists idx_cv_thong_bao_nhan_doc on public.cv_thong_bao (nguoi_nhan, da_doc);
create index if not exists idx_cv_thong_bao_nhan_tg  on public.cv_thong_bao (nguoi_nhan, created_at desc);
create index if not exists idx_cv_thong_bao_cv       on public.cv_thong_bao (cong_viec_id);

-- ---------------------------------------------------------------------------
-- 2. Hàm dùng chung (tên người, quyền xem)
-- ---------------------------------------------------------------------------
create or replace function public.cv_ten_nguoi(p_uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(trim(full_name), ''), nullif(trim(username), ''), email, '')
  from user_roles where user_id = p_uid;
$$;

create or replace function public.cv_la_bgd()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from user_roles where user_id = auth.uid() and role in ('admin', 'giam_doc_sx'));
$$;

create or replace function public.cv_xem_duoc(p_cong_viec_id bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (
    select 1 from cv_cong_viec c
    where c.id = p_cong_viec_id
      and (c.hien_thi = 'cong_khai'
           or c.nguoi_giao = auth.uid()
           or c.nguoi_lam = auth.uid()
           or exists (select 1 from cv_nguoi_phoi_hop p where p.cong_viec_id = c.id and p.user_id = auth.uid())
           or public.cv_la_bgd())
  );
$$;

-- Nội bộ: định dạng giờ VN, đổi text → uuid/timestamptz an toàn.
create or replace function public.cv_fmt(p_ts timestamptz)
returns text language sql immutable set search_path = public as $$
  select to_char(p_ts at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI');
$$;

create or replace function public.cv_uuid(p text)
returns uuid language plpgsql immutable set search_path = public as $$
begin
  if p is null or trim(p) = '' then return null; end if;
  return trim(p)::uuid;
exception when others then
  return null;
end;
$$;

create or replace function public.cv_ts(p text)
returns timestamptz language plpgsql stable set search_path = public as $$
begin
  if p is null or trim(p) = '' then return null; end if;
  return trim(p)::timestamptz;
exception when others then
  raise exception 'Thời gian "%" không hợp lệ.', p;
end;
$$;

-- Nội bộ: mảng jsonb uuid → uuid[] (bỏ trùng, chỉ tài khoản có thật).
create or replace function public.cv_ds_uuid(p jsonb)
returns uuid[] language plpgsql stable security definer set search_path = public as $$
declare v uuid[];
begin
  if p is null or jsonb_typeof(p) = 'null' then return '{}'; end if;
  if jsonb_typeof(p) <> 'array' then raise exception 'Danh sách người phối hợp không hợp lệ.'; end if;
  if exists (select 1 from jsonb_array_elements_text(p) x where cv_uuid(x) is null
             or not exists (select 1 from user_roles r where r.user_id = cv_uuid(x))) then
    raise exception 'Danh sách người phối hợp có tài khoản không hợp lệ.';
  end if;
  select coalesce(array_agg(distinct cv_uuid(x)), '{}') into v from jsonb_array_elements_text(p) x;
  return v;
end;
$$;

-- Nội bộ: gửi thông báo cho danh sách người (trừ chính người thao tác).
create or replace function public.cv_gui_tb(p_nguoi uuid[], p_loai text, p_cong_viec_id bigint, p_du_an_id bigint,
                                            p_noi_dung text, p_can_xu_ly boolean default false)
returns void language sql security definer set search_path = public as $$
  insert into cv_thong_bao (nguoi_nhan, loai, cong_viec_id, du_an_id, noi_dung, can_xu_ly)
  select distinct u, p_loai, p_cong_viec_id, p_du_an_id, p_noi_dung, coalesce(p_can_xu_ly, false)
  from unnest(p_nguoi) u
  where u is not null and u is distinct from auth.uid()
    and exists (select 1 from user_roles r where r.user_id = u);
$$;

-- Nội bộ: đánh da_xu_ly các thông báo can_xu_ly cũ của 1 việc.
-- p_nguoi null = mọi người nhận (dùng khi tình huống đã hết, vd việc đã đóng).
create or replace function public.cv_xong_tb(p_cong_viec_id bigint, p_loai text[], p_nguoi uuid)
returns void language sql security definer set search_path = public as $$
  update cv_thong_bao set da_xu_ly = true
  where cong_viec_id = p_cong_viec_id and can_xu_ly and not da_xu_ly
    and (p_loai is null or loai = any(p_loai))
    and (p_nguoi is null or nguoi_nhan = p_nguoi);
$$;

-- Nội bộ: ghi lịch sử + cập nhật updated_at.
create or replace function public.cv_ghi_ls(p_cong_viec_id bigint, p_hanh_dong text, p_noi_dung text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into cv_lich_su (cong_viec_id, nguoi, hanh_dong, noi_dung) values (p_cong_viec_id, auth.uid(), p_hanh_dong, p_noi_dung);
  update cv_cong_viec set updated_at = now() where id = p_cong_viec_id;
end;
$$;

-- Nội bộ: lấy việc (khoá dòng), báo lỗi nếu chưa đăng nhập / không có / không được xem.
create or replace function public.cv_lay_viec(p_id bigint)
returns public.cv_cong_viec language plpgsql security definer set search_path = public as $$
declare v cv_cong_viec;
begin
  if auth.uid() is null then raise exception 'Bạn cần đăng nhập.'; end if;
  select * into v from cv_cong_viec where id = p_id for update;
  if not found or not cv_xem_duoc(p_id) then raise exception 'Không tìm thấy công việc.'; end if;
  return v;
end;
$$;

-- Nội bộ: người giao hoặc Ban giám đốc.
create or replace function public.cv_quyen_giao(p_nguoi_giao uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_nguoi_giao = auth.uid() or public.cv_la_bgd();
$$;

-- Nội bộ: người làm + người phối hợp của 1 việc.
create or replace function public.cv_nguoi_lam_va_ph(p_id bigint)
returns uuid[] language sql stable security definer set search_path = public as $$
  select array(select nguoi_lam from cv_cong_viec where id = p_id
               union select user_id from cv_nguoi_phoi_hop where cong_viec_id = p_id);
$$;

-- ---------------------------------------------------------------------------
-- 3. RLS — chỉ SELECT, ghi qua RPC
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['cv_bo_phan','cv_du_an','cv_cong_viec','cv_nguoi_phoi_hop','cv_checklist',
                           'cv_binh_luan','cv_dong_tinh','cv_tep','cv_lich_su','cv_thong_bao'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

drop policy if exists "cv_bo_phan doc" on public.cv_bo_phan;
create policy "cv_bo_phan doc" on public.cv_bo_phan for select to authenticated using (true);

drop policy if exists "cv_du_an doc" on public.cv_du_an;
create policy "cv_du_an doc" on public.cv_du_an for select to authenticated using (true);

drop policy if exists "cv_cong_viec doc" on public.cv_cong_viec;
create policy "cv_cong_viec doc" on public.cv_cong_viec for select to authenticated
  using (hien_thi = 'cong_khai' or nguoi_giao = auth.uid() or nguoi_lam = auth.uid() or public.cv_xem_duoc(id));

drop policy if exists "cv_nguoi_phoi_hop doc" on public.cv_nguoi_phoi_hop;
create policy "cv_nguoi_phoi_hop doc" on public.cv_nguoi_phoi_hop for select to authenticated
  using (public.cv_xem_duoc(cong_viec_id));

drop policy if exists "cv_checklist doc" on public.cv_checklist;
create policy "cv_checklist doc" on public.cv_checklist for select to authenticated
  using (public.cv_xem_duoc(cong_viec_id));

drop policy if exists "cv_binh_luan doc" on public.cv_binh_luan;
create policy "cv_binh_luan doc" on public.cv_binh_luan for select to authenticated
  using (case when cong_viec_id is not null then public.cv_xem_duoc(cong_viec_id) else true end);

drop policy if exists "cv_dong_tinh doc" on public.cv_dong_tinh;
create policy "cv_dong_tinh doc" on public.cv_dong_tinh for select to authenticated
  using (exists (select 1 from public.cv_binh_luan b where b.id = binh_luan_id));

drop policy if exists "cv_tep doc" on public.cv_tep;
create policy "cv_tep doc" on public.cv_tep for select to authenticated
  using (public.cv_xem_duoc(cong_viec_id));

drop policy if exists "cv_lich_su doc" on public.cv_lich_su;
create policy "cv_lich_su doc" on public.cv_lich_su for select to authenticated
  using (public.cv_xem_duoc(cong_viec_id));

drop policy if exists "cv_thong_bao doc" on public.cv_thong_bao;
create policy "cv_thong_bao doc" on public.cv_thong_bao for select to authenticated
  using (nguoi_nhan = auth.uid());

-- ---------------------------------------------------------------------------
-- 4. View cv_cong_viec_v (security_invoker → RLS của người xem)
-- ---------------------------------------------------------------------------
create or replace view public.cv_cong_viec_v with (security_invoker = true) as
select c.*,
  public.cv_ten_nguoi(c.nguoi_giao) as ten_nguoi_giao,
  public.cv_ten_nguoi(c.nguoi_lam)  as ten_nguoi_lam,
  coalesce(ph.ids, '{}'::uuid[])    as phoi_hop,
  coalesce(ph.tens, '{}'::text[])   as ten_phoi_hop,
  g.gap_hieu_luc,
  case when c.quan_trong and g.gap_hieu_luc then 1
       when c.quan_trong then 2
       when g.gap_hieu_luc then 3
       else 4 end                   as nhom,
  (c.trang_thai not in ('hoan_thanh','huy') and now() > c.han) as qua_han,
  coalesce(ck.so_buoc, 0)           as so_buoc,
  coalesce(ck.so_buoc_xong, 0)      as so_buoc_xong,
  coalesce(bl.n, 0)                 as so_binh_luan,
  d.ten                             as ten_du_an,
  round((extract(epoch from (c.han - now())) / 3600.0)::numeric, 1) as con_gio
from public.cv_cong_viec c
cross join lateral (
  select (c.gap or (c.trang_thai not in ('hoan_thanh','huy') and c.han <= now() + interval '2 days')) as gap_hieu_luc
) g
left join lateral (
  select array_agg(p.user_id order by p.user_id) as ids,
         array_agg(public.cv_ten_nguoi(p.user_id) order by p.user_id) as tens
  from public.cv_nguoi_phoi_hop p where p.cong_viec_id = c.id
) ph on true
left join lateral (
  select count(*)::int as so_buoc, (count(*) filter (where k.xong))::int as so_buoc_xong
  from public.cv_checklist k where k.cong_viec_id = c.id
) ck on true
left join lateral (
  select count(*)::int as n from public.cv_binh_luan b where b.cong_viec_id = c.id
) bl on true
left join public.cv_du_an d on d.id = c.du_an_id;

revoke all on public.cv_cong_viec_v from public, anon, authenticated;
grant select on public.cv_cong_viec_v to authenticated;

-- ---------------------------------------------------------------------------
-- 5. RPC cho giao diện
-- ---------------------------------------------------------------------------

-- Danh sách tài khoản để chọn người làm / phối hợp / @tên.
create or replace function public.cv_danh_sach_nguoi()
returns table (user_id uuid, ten text, username text, role text)
language sql stable security definer set search_path = public as $$
  select r.user_id,
         coalesce(nullif(trim(r.full_name), ''), nullif(trim(r.username), ''), r.email, '') as ten,
         r.username, r.role
  from user_roles r
  where auth.uid() is not null
  order by 2;
$$;

-- Giao việc mới. nguoi_giao = auth.uid().
create or replace function public.cv_tao_viec(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_id bigint;
  v_tieu_de text := trim(coalesce(p->>'tieu_de', ''));
  v_lam uuid := cv_uuid(p->>'nguoi_lam');
  v_bo_phan text := nullif(trim(coalesce(p->>'bo_phan', '')), '');
  v_han timestamptz := cv_ts(p->>'han');
  v_qt boolean := coalesce((p->>'quan_trong')::boolean, false);
  v_gap boolean := coalesce((p->>'gap')::boolean, false);
  v_duyet boolean := coalesce((p->>'can_duyet')::boolean, true);
  v_hien_thi text := coalesce(nullif(p->>'hien_thi', ''), 'cong_khai');
  v_lap_lai text := coalesce(nullif(p->>'lap_lai', ''), 'khong');
  v_lk jsonb := coalesce(p->'lien_ket', '[]'::jsonb);
  v_du_an bigint := nullif(p->>'du_an_id', '')::bigint;
  v_gop_y bigint := nullif(p->>'tu_gop_y_id', '')::bigint;
  v_ph uuid[];
  x text;
  i int := 0;
begin
  if v_uid is null then raise exception 'Bạn cần đăng nhập.'; end if;
  if v_tieu_de = '' then raise exception 'Hãy nhập tiêu đề công việc.'; end if;
  if v_lam is null or not exists (select 1 from user_roles where user_id = v_lam) then
    raise exception 'Hãy chọn người làm chính hợp lệ.';
  end if;
  if v_bo_phan is null or not exists (select 1 from cv_bo_phan where ten = v_bo_phan) then
    raise exception 'Hãy chọn bộ phận hợp lệ.';
  end if;
  if v_han is null then raise exception 'Hãy chọn hạn hoàn thành.'; end if;
  if v_han <= now() then raise exception 'Hạn hoàn thành phải sau thời điểm hiện tại.'; end if;
  if v_hien_thi not in ('cong_khai', 'han_che') then raise exception 'Chế độ hiển thị không hợp lệ.'; end if;
  if v_lap_lai not in ('khong', 'tuan', 'thang', 'quy') then raise exception 'Kiểu lặp lại không hợp lệ.'; end if;
  if jsonb_typeof(v_lk) = 'null' then v_lk := '[]'::jsonb; end if;
  if jsonb_typeof(v_lk) <> 'array' then raise exception 'Liên kết dữ liệu không hợp lệ.'; end if;
  if v_du_an is not null and not exists (select 1 from cv_du_an where id = v_du_an) then
    raise exception 'Không tìm thấy dự án đã chọn.';
  end if;
  if v_qt then v_duyet := true; end if;   -- việc Quan trọng luôn cần duyệt
  v_ph := array_remove(cv_ds_uuid(p->'phoi_hop'), v_lam);

  insert into cv_cong_viec (tieu_de, mo_ta, nguoi_giao, nguoi_lam, bo_phan, du_an_id, quan_trong, gap,
                            han_ban_dau, han, can_duyet, hien_thi, lien_ket, lap_lai, tu_gop_y_id)
  values (v_tieu_de, nullif(trim(coalesce(p->>'mo_ta', '')), ''), v_uid, v_lam, v_bo_phan, v_du_an, v_qt, v_gap,
          v_han, v_han, v_duyet, v_hien_thi, v_lk, v_lap_lai, v_gop_y)
  returning id into v_id;

  insert into cv_nguoi_phoi_hop (cong_viec_id, user_id) select v_id, u from unnest(v_ph) u on conflict do nothing;

  if p->'checklist' is not null and jsonb_typeof(p->'checklist') = 'array' then
    for x in select jsonb_array_elements_text(p->'checklist') loop
      if trim(x) <> '' then
        i := i + 1;
        insert into cv_checklist (cong_viec_id, thu_tu, noi_dung) values (v_id, i, trim(x));
      end if;
    end loop;
  end if;

  if v_gop_y is not null then
    update cv_binh_luan set cong_viec_tao_ra = v_id where id = v_gop_y and cong_viec_tao_ra is null;
  end if;

  perform cv_ghi_ls(v_id, 'tao', cv_ten_nguoi(v_uid) || ' giao việc cho ' || coalesce(cv_ten_nguoi(v_lam), '')
                     || ', hạn ' || cv_fmt(v_han) || '.');
  perform cv_gui_tb(array[v_lam], 'giao_viec', v_id, null,
                    cv_ten_nguoi(v_uid) || ' giao cho bạn: ' || v_tieu_de || ' (hạn ' || cv_fmt(v_han) || ')', true);
  perform cv_gui_tb(v_ph, 'giao_viec', v_id, null,
                    cv_ten_nguoi(v_uid) || ' thêm bạn phối hợp: ' || v_tieu_de || ' (hạn ' || cv_fmt(v_han) || ')', false);
  return v_id;
end;
$$;

-- Sửa việc (chỉ key có mặt mới đổi). Người giao / BGĐ, khi chưa hoàn thành / huỷ.
create or replace function public.cv_sua_viec(p_id bigint, p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v cv_cong_viec;
  n cv_cong_viec;
  v_uid uuid := auth.uid();
  v_ph_cu uuid[];
  v_ph uuid[];
  v_doi text[] := '{}';
  v_tb text[] := '{}';
begin
  v := cv_lay_viec(p_id);
  if not cv_quyen_giao(v.nguoi_giao) then
    raise exception 'Chỉ người giao việc hoặc Ban giám đốc mới được sửa việc này.';
  end if;
  if v.trang_thai in ('hoan_thanh', 'huy') then
    raise exception 'Việc đã hoàn thành hoặc đã huỷ, không sửa được.';
  end if;
  n := v;
  p := coalesce(p, '{}'::jsonb);

  if p ? 'tieu_de' then
    n.tieu_de := trim(coalesce(p->>'tieu_de', ''));
    if n.tieu_de = '' then raise exception 'Hãy nhập tiêu đề công việc.'; end if;
  end if;
  if p ? 'mo_ta' then n.mo_ta := nullif(trim(coalesce(p->>'mo_ta', '')), ''); end if;
  if p ? 'nguoi_lam' then
    n.nguoi_lam := cv_uuid(p->>'nguoi_lam');
    if n.nguoi_lam is null or not exists (select 1 from user_roles where user_id = n.nguoi_lam) then
      raise exception 'Hãy chọn người làm chính hợp lệ.';
    end if;
  end if;
  if p ? 'bo_phan' then
    n.bo_phan := nullif(trim(coalesce(p->>'bo_phan', '')), '');
    if n.bo_phan is null or not exists (select 1 from cv_bo_phan where ten = n.bo_phan) then
      raise exception 'Hãy chọn bộ phận hợp lệ.';
    end if;
  end if;
  if p ? 'du_an_id' then
    n.du_an_id := nullif(p->>'du_an_id', '')::bigint;
    if n.du_an_id is not null and not exists (select 1 from cv_du_an where id = n.du_an_id) then
      raise exception 'Không tìm thấy dự án đã chọn.';
    end if;
  end if;
  if p ? 'quan_trong' then n.quan_trong := coalesce((p->>'quan_trong')::boolean, false); end if;
  if p ? 'gap' then n.gap := coalesce((p->>'gap')::boolean, false); end if;
  if p ? 'han' then
    n.han := cv_ts(p->>'han');
    if n.han is null then raise exception 'Hãy chọn hạn hoàn thành.'; end if;
  end if;
  if p ? 'can_duyet' then n.can_duyet := coalesce((p->>'can_duyet')::boolean, true); end if;
  if n.quan_trong then n.can_duyet := true; end if;
  if p ? 'hien_thi' then
    n.hien_thi := coalesce(nullif(p->>'hien_thi', ''), 'cong_khai');
    if n.hien_thi not in ('cong_khai', 'han_che') then raise exception 'Chế độ hiển thị không hợp lệ.'; end if;
  end if;
  if p ? 'lien_ket' then
    n.lien_ket := coalesce(p->'lien_ket', '[]'::jsonb);
    if jsonb_typeof(n.lien_ket) = 'null' then n.lien_ket := '[]'::jsonb; end if;
    if jsonb_typeof(n.lien_ket) <> 'array' then raise exception 'Liên kết dữ liệu không hợp lệ.'; end if;
  end if;
  if p ? 'lap_lai' then
    n.lap_lai := coalesce(nullif(p->>'lap_lai', ''), 'khong');
    if n.lap_lai not in ('khong', 'tuan', 'thang', 'quy') then raise exception 'Kiểu lặp lại không hợp lệ.'; end if;
  end if;
  if p ? 'tu_gop_y_id' then n.tu_gop_y_id := nullif(p->>'tu_gop_y_id', '')::bigint; end if;

  if n.tieu_de is distinct from v.tieu_de then v_doi := v_doi || 'tiêu đề'::text; end if;
  if n.mo_ta is distinct from v.mo_ta then v_doi := v_doi || 'mô tả'::text; end if;
  if n.bo_phan is distinct from v.bo_phan then v_doi := v_doi || ('bộ phận → ' || n.bo_phan); end if;
  if n.du_an_id is distinct from v.du_an_id then v_doi := v_doi || 'dự án'::text; end if;
  if n.can_duyet is distinct from v.can_duyet then v_doi := v_doi || (case when n.can_duyet then 'cần duyệt' else 'không cần duyệt' end); end if;
  if n.hien_thi is distinct from v.hien_thi then v_doi := v_doi || (case when n.hien_thi = 'han_che' then 'hiển thị hạn chế' else 'hiển thị công khai' end); end if;
  if n.lien_ket is distinct from v.lien_ket then v_doi := v_doi || 'liên kết'::text; end if;
  if n.lap_lai is distinct from v.lap_lai then v_doi := v_doi || 'lặp lại'::text; end if;
  if n.quan_trong is distinct from v.quan_trong or n.gap is distinct from v.gap then
    v_tb := v_tb || ('ưu tiên → ' || case when n.quan_trong then 'Quan trọng' else 'Ít quan trọng' end
                     || ' · ' || case when n.gap then 'Gấp' else 'Chưa gấp' end);
  end if;
  if n.han is distinct from v.han then v_tb := v_tb || ('hạn → ' || cv_fmt(n.han)); end if;
  if n.nguoi_lam is distinct from v.nguoi_lam then
    v_tb := v_tb || ('người làm: ' || coalesce(cv_ten_nguoi(v.nguoi_lam), '') || ' → ' || coalesce(cv_ten_nguoi(n.nguoi_lam), ''));
  end if;

  update cv_cong_viec set
    tieu_de = n.tieu_de, mo_ta = n.mo_ta, nguoi_lam = n.nguoi_lam, bo_phan = n.bo_phan, du_an_id = n.du_an_id,
    quan_trong = n.quan_trong, gap = n.gap, han = n.han, can_duyet = n.can_duyet, hien_thi = n.hien_thi,
    lien_ket = n.lien_ket, lap_lai = n.lap_lai, tu_gop_y_id = n.tu_gop_y_id, updated_at = now()
  where id = p_id;

  -- Người phối hợp
  select coalesce(array_agg(user_id), '{}') into v_ph_cu from cv_nguoi_phoi_hop where cong_viec_id = p_id;
  if p ? 'phoi_hop' then
    v_ph := array_remove(cv_ds_uuid(p->'phoi_hop'), n.nguoi_lam);
    delete from cv_nguoi_phoi_hop where cong_viec_id = p_id and not (user_id = any(v_ph));
    insert into cv_nguoi_phoi_hop (cong_viec_id, user_id) select p_id, u from unnest(v_ph) u on conflict do nothing;
    if exists (select 1 from unnest(v_ph) u where not (u = any(v_ph_cu)))
       or exists (select 1 from unnest(v_ph_cu) u where not (u = any(v_ph))) then
      v_doi := v_doi || 'người phối hợp'::text;
    end if;
    perform cv_gui_tb(array(select u from unnest(v_ph) u where not (u = any(v_ph_cu))), 'giao_viec', p_id, null,
                      cv_ten_nguoi(v_uid) || ' thêm bạn phối hợp: ' || n.tieu_de || ' (hạn ' || cv_fmt(n.han) || ')', false);
  elsif n.nguoi_lam is distinct from v.nguoi_lam then
    delete from cv_nguoi_phoi_hop where cong_viec_id = p_id and user_id = n.nguoi_lam;
  end if;

  if cardinality(v_doi) = 0 and cardinality(v_tb) = 0 then return; end if;
  perform cv_ghi_ls(p_id, 'sua', cv_ten_nguoi(v_uid) || ' sửa việc: ' || array_to_string(v_tb || v_doi, '; ') || '.');

  if cardinality(v_tb) > 0 then
    perform cv_gui_tb(array[n.nguoi_lam, case when n.nguoi_lam is distinct from v.nguoi_lam then v.nguoi_lam end],
                      'cap_nhat_viec', p_id, null,
                      cv_ten_nguoi(v_uid) || ' cập nhật "' || n.tieu_de || '": ' || array_to_string(v_tb, '; '), false);
  end if;
  if n.nguoi_lam is distinct from v.nguoi_lam then
    -- Người làm cũ không còn phải xử lý; người làm mới cần nhận / làm.
    perform cv_xong_tb(p_id, array['giao_viec','tra_lai','nhac_viec','qua_han'], v.nguoi_lam);
  end if;
end;
$$;

-- Người làm nhận việc (moi → dang_lam).
create or replace function public.cv_nhan_viec(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v cv_cong_viec;
begin
  v := cv_lay_viec(p_id);
  if v.nguoi_lam <> auth.uid() then raise exception 'Chỉ người làm chính mới nhận được việc này.'; end if;
  if v.trang_thai <> 'moi' then raise exception 'Việc này đã được nhận hoặc không còn ở trạng thái Mới.'; end if;
  update cv_cong_viec set trang_thai = 'dang_lam', nhan_luc = now(), updated_at = now() where id = p_id;
  perform cv_ghi_ls(p_id, 'nhan_viec', cv_ten_nguoi(auth.uid()) || ' đã nhận việc.');
  perform cv_gui_tb(array[v.nguoi_giao], 'nhan_viec', p_id, null, cv_ten_nguoi(auth.uid()) || ' đã nhận việc: ' || v.tieu_de, false);
  perform cv_xong_tb(p_id, array['giao_viec'], auth.uid());
end;
$$;

-- Thêm / xoá bước checklist (người giao, người làm hoặc BGĐ; việc chưa đóng).
create or replace function public.cv_them_buoc(p_id bigint, p_noi_dung text)
returns bigint language plpgsql security definer set search_path = public as $$
declare v cv_cong_viec; v_bid bigint; v_nd text := trim(coalesce(p_noi_dung, ''));
begin
  v := cv_lay_viec(p_id);
  if not (v.nguoi_lam = auth.uid() or cv_quyen_giao(v.nguoi_giao)) then
    raise exception 'Chỉ người giao hoặc người làm mới thêm được bước.';
  end if;
  if v.trang_thai in ('hoan_thanh', 'huy') then raise exception 'Việc đã hoàn thành hoặc đã huỷ, không thêm bước được.'; end if;
  if v_nd = '' then raise exception 'Hãy nhập nội dung bước.'; end if;
  insert into cv_checklist (cong_viec_id, thu_tu, noi_dung)
  values (p_id, coalesce((select max(thu_tu) from cv_checklist where cong_viec_id = p_id), 0) + 1, v_nd)
  returning id into v_bid;
  perform cv_ghi_ls(p_id, 'them_buoc', cv_ten_nguoi(auth.uid()) || ' thêm bước: ' || v_nd);
  return v_bid;
end;
$$;

create or replace function public.cv_xoa_buoc(p_buoc_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare b cv_checklist; v cv_cong_viec;
begin
  if auth.uid() is null then raise exception 'Bạn cần đăng nhập.'; end if;
  select * into b from cv_checklist where id = p_buoc_id;
  if not found then raise exception 'Không tìm thấy bước này.'; end if;
  v := cv_lay_viec(b.cong_viec_id);
  if not (v.nguoi_lam = auth.uid() or cv_quyen_giao(v.nguoi_giao)) then
    raise exception 'Chỉ người giao hoặc người làm mới xoá được bước.';
  end if;
  if v.trang_thai in ('hoan_thanh', 'huy') then raise exception 'Việc đã hoàn thành hoặc đã huỷ, không xoá bước được.'; end if;
  delete from cv_checklist where id = p_buoc_id;
  perform cv_ghi_ls(v.id, 'xoa_buoc', cv_ten_nguoi(auth.uid()) || ' xoá bước: ' || b.noi_dung);
end;
$$;

-- Người làm tick / bỏ tick bước (việc đang làm).
create or replace function public.cv_tick_buoc(p_buoc_id bigint, p_xong boolean)
returns void language plpgsql security definer set search_path = public as $$
declare b cv_checklist; v cv_cong_viec;
begin
  if auth.uid() is null then raise exception 'Bạn cần đăng nhập.'; end if;
  select * into b from cv_checklist where id = p_buoc_id;
  if not found then raise exception 'Không tìm thấy bước này.'; end if;
  v := cv_lay_viec(b.cong_viec_id);
  if v.nguoi_lam <> auth.uid() then raise exception 'Chỉ người làm chính mới đánh dấu được bước.'; end if;
  if v.trang_thai = 'moi' then raise exception 'Hãy bấm "Nhận việc" trước khi đánh dấu bước.'; end if;
  if v.trang_thai <> 'dang_lam' then raise exception 'Chỉ đánh dấu bước khi việc đang làm.'; end if;
  if coalesce(p_xong, false) = b.xong then return; end if;
  update cv_checklist set xong = coalesce(p_xong, false),
    xong_luc = case when p_xong then now() end, xong_boi = case when p_xong then auth.uid() end
  where id = p_buoc_id;
  perform cv_ghi_ls(v.id, case when p_xong then 'tick_buoc' else 'bo_tick_buoc' end,
                    cv_ten_nguoi(auth.uid()) || case when p_xong then ' hoàn thành bước: ' else ' bỏ đánh dấu bước: ' end || b.noi_dung);
end;
$$;

-- Người làm báo hoàn thành → cho_duyet (nếu can_duyet) hoặc hoan_thanh.
create or replace function public.cv_bao_xong(p_id bigint, p_ghi_chu text default null)
returns text language plpgsql security definer set search_path = public as $$
declare v cv_cong_viec; v_con int; v_moi text; v_gc text := nullif(trim(coalesce(p_ghi_chu, '')), '');
begin
  v := cv_lay_viec(p_id);
  if v.nguoi_lam <> auth.uid() then raise exception 'Chỉ người làm chính mới báo hoàn thành được.'; end if;
  if v.trang_thai = 'moi' then raise exception 'Hãy bấm "Nhận việc" trước khi báo hoàn thành.'; end if;
  if v.trang_thai <> 'dang_lam' then raise exception 'Chỉ báo hoàn thành được khi việc đang làm.'; end if;
  select count(*) into v_con from cv_checklist where cong_viec_id = p_id and not xong;
  if v_con > 0 then
    raise exception 'Còn % bước chưa xong. Hãy hoàn thành hết các bước trước khi báo hoàn thành.', v_con;
  end if;

  if v_gc is not null then
    insert into cv_binh_luan (cong_viec_id, nguoi_viet, loai, noi_dung) values (p_id, auth.uid(), 'cap_nhat', v_gc);
  end if;

  if v.can_duyet then
    v_moi := 'cho_duyet';
    update cv_cong_viec set trang_thai = 'cho_duyet', bao_xong_luc = now(), updated_at = now() where id = p_id;
    perform cv_ghi_ls(p_id, 'bao_xong', cv_ten_nguoi(auth.uid()) || ' báo hoàn thành, chờ duyệt.'
                      || coalesce(' Ghi chú: ' || v_gc, ''));
    perform cv_gui_tb(array[v.nguoi_giao], 'cho_duyet', p_id, null,
                      cv_ten_nguoi(auth.uid()) || ' báo hoàn thành, chờ bạn duyệt: ' || v.tieu_de, true);
  else
    v_moi := 'hoan_thanh';
    update cv_cong_viec set trang_thai = 'hoan_thanh', bao_xong_luc = now(), hoan_thanh_luc = now(),
      dung_han = (now() <= han), gia_han_den = null, gia_han_ly_do = null, updated_at = now()
    where id = p_id;
    perform cv_ghi_ls(p_id, 'hoan_thanh', cv_ten_nguoi(auth.uid()) || ' báo hoàn thành ('
                      || case when now() <= v.han then 'đúng hạn' else 'trễ hạn' end || ').'
                      || coalesce(' Ghi chú: ' || v_gc, ''));
    perform cv_gui_tb(array[v.nguoi_giao], 'hoan_thanh', p_id, null,
                      cv_ten_nguoi(auth.uid()) || ' đã hoàn thành: ' || v.tieu_de, false);
    perform cv_xong_tb(p_id, null, null);   -- việc đã đóng
  end if;
  perform cv_xong_tb(p_id, array['giao_viec','tra_lai','nhac_viec','qua_han'], auth.uid());
  return v_moi;
end;
$$;

-- Người giao / BGĐ duyệt (cho_duyet → hoan_thanh).
create or replace function public.cv_duyet(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v cv_cong_viec;
begin
  v := cv_lay_viec(p_id);
  if not cv_quyen_giao(v.nguoi_giao) then raise exception 'Chỉ người giao việc hoặc Ban giám đốc mới được duyệt.'; end if;
  if v.trang_thai <> 'cho_duyet' then raise exception 'Việc này không ở trạng thái Chờ duyệt.'; end if;
  update cv_cong_viec set trang_thai = 'hoan_thanh', hoan_thanh_luc = now(),
    dung_han = (coalesce(bao_xong_luc, now()) <= han), gia_han_den = null, gia_han_ly_do = null, updated_at = now()
  where id = p_id;
  perform cv_ghi_ls(p_id, 'duyet', cv_ten_nguoi(auth.uid()) || ' đã duyệt hoàn thành ('
                    || case when coalesce(v.bao_xong_luc, now()) <= v.han then 'đúng hạn' else 'trễ hạn' end || ').');
  perform cv_gui_tb(cv_nguoi_lam_va_ph(p_id), 'hoan_thanh', p_id, null,
                    cv_ten_nguoi(auth.uid()) || ' đã duyệt hoàn thành: ' || v.tieu_de, false);
  perform cv_xong_tb(p_id, null, null);   -- việc đã đóng: hết mọi việc cần xử lý
end;
$$;

-- Người giao / BGĐ trả lại (cho_duyet → dang_lam), bắt buộc lý do.
create or replace function public.cv_tra_lai(p_id bigint, p_ly_do text)
returns void language plpgsql security definer set search_path = public as $$
declare v cv_cong_viec; v_ld text := trim(coalesce(p_ly_do, ''));
begin
  v := cv_lay_viec(p_id);
  if not cv_quyen_giao(v.nguoi_giao) then raise exception 'Chỉ người giao việc hoặc Ban giám đốc mới được trả lại.'; end if;
  if v.trang_thai <> 'cho_duyet' then raise exception 'Việc này không ở trạng thái Chờ duyệt.'; end if;
  if v_ld = '' then raise exception 'Hãy nhập lý do trả lại.'; end if;
  update cv_cong_viec set trang_thai = 'dang_lam', so_lan_tra_lai = so_lan_tra_lai + 1, bao_xong_luc = null, updated_at = now()
  where id = p_id;
  insert into cv_binh_luan (cong_viec_id, nguoi_viet, loai, noi_dung) values (p_id, auth.uid(), 'tra_lai', v_ld);
  perform cv_ghi_ls(p_id, 'tra_lai', cv_ten_nguoi(auth.uid()) || ' trả lại (lần ' || (v.so_lan_tra_lai + 1) || '). Lý do: ' || v_ld);
  perform cv_gui_tb(array[v.nguoi_lam], 'tra_lai', p_id, null,
                    cv_ten_nguoi(auth.uid()) || ' trả lại việc "' || v.tieu_de || '": ' || v_ld, true);
  perform cv_xong_tb(p_id, array['cho_duyet'], null);
end;
$$;

-- Người làm xin gia hạn.
create or replace function public.cv_xin_gia_han(p_id bigint, p_den timestamptz, p_ly_do text)
returns void language plpgsql security definer set search_path = public as $$
declare v cv_cong_viec; v_ld text := trim(coalesce(p_ly_do, ''));
begin
  v := cv_lay_viec(p_id);
  if v.nguoi_lam <> auth.uid() then raise exception 'Chỉ người làm chính mới xin gia hạn được.'; end if;
  if v.trang_thai not in ('moi', 'dang_lam') then raise exception 'Chỉ xin gia hạn được khi việc mới hoặc đang làm.'; end if;
  if v.gia_han_den is not null then raise exception 'Đã có một yêu cầu gia hạn đang chờ trả lời.'; end if;
  if p_den is null or p_den <= v.han then raise exception 'Hạn mới phải sau hạn hiện tại (%).', cv_fmt(v.han); end if;
  if v_ld = '' then raise exception 'Hãy nhập lý do xin gia hạn.'; end if;
  update cv_cong_viec set gia_han_den = p_den, gia_han_ly_do = v_ld, updated_at = now() where id = p_id;
  perform cv_ghi_ls(p_id, 'xin_gia_han', cv_ten_nguoi(auth.uid()) || ' xin gia hạn đến ' || cv_fmt(p_den) || '. Lý do: ' || v_ld);
  perform cv_gui_tb(array[v.nguoi_giao], 'xin_gia_han', p_id, null,
                    cv_ten_nguoi(auth.uid()) || ' xin gia hạn "' || v.tieu_de || '" đến ' || cv_fmt(p_den) || ': ' || v_ld, true);
end;
$$;

-- Người giao / BGĐ trả lời gia hạn.
create or replace function public.cv_tra_loi_gia_han(p_id bigint, p_dong_y boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v cv_cong_viec;
begin
  v := cv_lay_viec(p_id);
  if not cv_quyen_giao(v.nguoi_giao) then raise exception 'Chỉ người giao việc hoặc Ban giám đốc mới trả lời gia hạn được.'; end if;
  if v.gia_han_den is null then raise exception 'Không có yêu cầu gia hạn nào đang chờ.'; end if;
  if p_dong_y is null then raise exception 'Hãy chọn đồng ý hoặc không đồng ý.'; end if;
  update cv_cong_viec set han = case when p_dong_y then v.gia_han_den else han end,
    gia_han_den = null, gia_han_ly_do = null, updated_at = now()
  where id = p_id;
  perform cv_ghi_ls(p_id, 'tra_loi_gia_han', cv_ten_nguoi(auth.uid())
                    || case when p_dong_y then ' đồng ý gia hạn đến ' || cv_fmt(v.gia_han_den) || '.'
                            else ' không đồng ý gia hạn, giữ hạn ' || cv_fmt(v.han) || '.' end);
  perform cv_gui_tb(array[v.nguoi_lam], 'tra_loi_gia_han', p_id, null,
                    cv_ten_nguoi(auth.uid()) || case when p_dong_y then ' đồng ý gia hạn "' || v.tieu_de || '" đến ' || cv_fmt(v.gia_han_den)
                                                     else ' không đồng ý gia hạn "' || v.tieu_de || '", hạn vẫn là ' || cv_fmt(v.han) end, false);
  perform cv_xong_tb(p_id, case when p_dong_y then array['xin_gia_han','qua_han'] else array['xin_gia_han'] end, null);
end;
$$;

-- Người giao / BGĐ nhắc việc.
create or replace function public.cv_nhac_viec(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v cv_cong_viec;
begin
  v := cv_lay_viec(p_id);
  if not cv_quyen_giao(v.nguoi_giao) then raise exception 'Chỉ người giao việc hoặc Ban giám đốc mới nhắc việc được.'; end if;
  if v.trang_thai in ('hoan_thanh', 'huy') then raise exception 'Việc đã hoàn thành hoặc đã huỷ.'; end if;
  perform cv_ghi_ls(p_id, 'nhac_viec', cv_ten_nguoi(auth.uid()) || ' nhắc việc.');
  perform cv_gui_tb(array[v.nguoi_lam], 'nhac_viec', p_id, null,
                    cv_ten_nguoi(auth.uid()) || ' nhắc bạn: ' || v.tieu_de || ' (hạn ' || cv_fmt(v.han) || ')', true);
end;
$$;

-- Người giao / BGĐ mở lại việc đã hoàn thành.
create or replace function public.cv_mo_lai(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare v cv_cong_viec;
begin
  v := cv_lay_viec(p_id);
  if not cv_quyen_giao(v.nguoi_giao) then raise exception 'Chỉ người giao việc hoặc Ban giám đốc mới mở lại được.'; end if;
  if v.trang_thai <> 'hoan_thanh' then raise exception 'Chỉ mở lại được việc đã hoàn thành.'; end if;
  update cv_cong_viec set trang_thai = 'dang_lam', bao_xong_luc = null, hoan_thanh_luc = null, dung_han = null, updated_at = now()
  where id = p_id;
  perform cv_ghi_ls(p_id, 'mo_lai', cv_ten_nguoi(auth.uid()) || ' mở lại việc.');
  perform cv_gui_tb(array[v.nguoi_lam], 'mo_lai', p_id, null, cv_ten_nguoi(auth.uid()) || ' mở lại việc: ' || v.tieu_de, false);
end;
$$;

-- Người giao / BGĐ huỷ việc (chưa hoàn thành).
create or replace function public.cv_huy_viec(p_id bigint, p_ly_do text)
returns void language plpgsql security definer set search_path = public as $$
declare v cv_cong_viec; v_ld text := nullif(trim(coalesce(p_ly_do, '')), '');
begin
  v := cv_lay_viec(p_id);
  if not cv_quyen_giao(v.nguoi_giao) then raise exception 'Chỉ người giao việc hoặc Ban giám đốc mới huỷ được.'; end if;
  if v.trang_thai = 'hoan_thanh' then raise exception 'Việc đã hoàn thành, không huỷ được.'; end if;
  if v.trang_thai = 'huy' then raise exception 'Việc này đã bị huỷ.'; end if;
  update cv_cong_viec set trang_thai = 'huy', gia_han_den = null, gia_han_ly_do = null, updated_at = now() where id = p_id;
  perform cv_ghi_ls(p_id, 'huy', cv_ten_nguoi(auth.uid()) || ' huỷ việc.' || coalesce(' Lý do: ' || v_ld, ''));
  perform cv_gui_tb(array[v.nguoi_lam], 'huy_viec', p_id, null,
                    cv_ten_nguoi(auth.uid()) || ' huỷ việc: ' || v.tieu_de || coalesce(' — ' || v_ld, ''), false);
  perform cv_xong_tb(p_id, null, null);
end;
$$;

-- Viết bình luận / góp ý (vào việc HOẶC dự án). p_nhac = uuid được gắn @tên.
create or replace function public.cv_viet_binh_luan(p_cong_viec_id bigint, p_du_an_id bigint, p_loai text,
                                                    p_noi_dung text, p_nhac uuid[] default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_id bigint;
  v_nd text := trim(coalesce(p_noi_dung, ''));
  v_loai text := coalesce(nullif(p_loai, ''), 'binh_luan');
  v cv_cong_viec;
  v_tieu_de text;
  v_nhan uuid[];
  v_nhac uuid[] := '{}';
  v_ten text := cv_ten_nguoi(auth.uid());
  v_trich text;
begin
  if v_uid is null then raise exception 'Bạn cần đăng nhập.'; end if;
  if (p_cong_viec_id is null) = (p_du_an_id is null) then raise exception 'Bình luận phải gắn với một công việc hoặc một dự án.'; end if;
  if v_loai not in ('binh_luan', 'gop_y', 'cau_hoi', 'de_xuat', 'cap_nhat') then raise exception 'Loại bình luận không hợp lệ.'; end if;
  if v_nd = '' then raise exception 'Hãy nhập nội dung.'; end if;
  v_trich := left(v_nd, 140) || case when length(v_nd) > 140 then '…' else '' end;

  if p_cong_viec_id is not null then
    if not cv_xem_duoc(p_cong_viec_id) then raise exception 'Không tìm thấy công việc.'; end if;
    select * into v from cv_cong_viec where id = p_cong_viec_id;
    v_tieu_de := v.tieu_de;
    v_nhan := array[v.nguoi_giao] || cv_nguoi_lam_va_ph(p_cong_viec_id);
  else
    select ten, array[chu_du_an] into v_tieu_de, v_nhan from cv_du_an where id = p_du_an_id;
    if not found then raise exception 'Không tìm thấy dự án.'; end if;
  end if;

  insert into cv_binh_luan (cong_viec_id, du_an_id, nguoi_viet, loai, noi_dung, trang_thai_gop_y)
  values (p_cong_viec_id, p_du_an_id, v_uid, v_loai, v_nd,
          case when v_loai in ('gop_y', 'de_xuat') then 'dang_xem_xet' end)
  returning id into v_id;

  -- @tên: chỉ người xem được việc (việc hạn chế → người liên quan + BGĐ).
  if p_nhac is not null then
    select coalesce(array_agg(distinct u), '{}') into v_nhac
    from unnest(p_nhac) u
    where u is not null and u is distinct from v_uid
      and exists (select 1 from user_roles r where r.user_id = u)
      and (p_cong_viec_id is null or v.hien_thi = 'cong_khai' or u = any(v_nhan)
           or exists (select 1 from user_roles r where r.user_id = u and r.role in ('admin', 'giam_doc_sx')));
    perform cv_gui_tb(v_nhac, 'nhac_ten', p_cong_viec_id, p_du_an_id,
                      v_ten || ' nhắc đến bạn trong "' || v_tieu_de || '": ' || v_trich, false);
  end if;

  perform cv_gui_tb(array(select u from unnest(v_nhan) u where not (u = any(v_nhac))),
                    case when v_loai in ('gop_y', 'de_xuat') then 'gop_y' else 'binh_luan' end,
                    p_cong_viec_id, p_du_an_id,
                    v_ten || case v_loai when 'gop_y' then ' góp ý' when 'de_xuat' then ' đề xuất'
                                         when 'cau_hoi' then ' hỏi' when 'cap_nhat' then ' cập nhật' else ' bình luận' end
                          || ' "' || v_tieu_de || '": ' || v_trich, false);
  return v_id;
end;
$$;

-- Đồng tình (bật / tắt) → trạng thái mới.
create or replace function public.cv_dong_tinh(p_binh_luan_id bigint)
returns boolean language plpgsql security definer set search_path = public as $$
declare b cv_binh_luan;
begin
  if auth.uid() is null then raise exception 'Bạn cần đăng nhập.'; end if;
  select * into b from cv_binh_luan where id = p_binh_luan_id;
  if not found or (b.cong_viec_id is not null and not cv_xem_duoc(b.cong_viec_id)) then
    raise exception 'Không tìm thấy bình luận.';
  end if;
  if exists (select 1 from cv_dong_tinh where binh_luan_id = p_binh_luan_id and user_id = auth.uid()) then
    delete from cv_dong_tinh where binh_luan_id = p_binh_luan_id and user_id = auth.uid();
    return false;
  end if;
  insert into cv_dong_tinh (binh_luan_id, user_id) values (p_binh_luan_id, auth.uid());
  return true;
end;
$$;

-- Xử lý góp ý / đề xuất: người giao việc / chủ dự án / BGĐ.
create or replace function public.cv_xu_ly_gop_y(p_binh_luan_id bigint, p_trang_thai text, p_tra_loi text default null)
returns void language plpgsql security definer set search_path = public as $$
declare b cv_binh_luan; v_ok boolean; v_tl text := nullif(trim(coalesce(p_tra_loi, '')), ''); v_tieu_de text;
begin
  if auth.uid() is null then raise exception 'Bạn cần đăng nhập.'; end if;
  select * into b from cv_binh_luan where id = p_binh_luan_id for update;
  if not found or (b.cong_viec_id is not null and not cv_xem_duoc(b.cong_viec_id)) then
    raise exception 'Không tìm thấy góp ý.';
  end if;
  if b.loai not in ('gop_y', 'de_xuat') then raise exception 'Chỉ xử lý được góp ý hoặc đề xuất.'; end if;
  if p_trang_thai not in ('dang_xem_xet', 'da_tiep_thu', 'da_tra_loi', 'khong_ap_dung') then
    raise exception 'Trạng thái góp ý không hợp lệ.';
  end if;
  if b.cong_viec_id is not null then
    select cv_quyen_giao(nguoi_giao), tieu_de into v_ok, v_tieu_de from cv_cong_viec where id = b.cong_viec_id;
  else
    select chu_du_an = auth.uid() or cv_la_bgd(), ten into v_ok, v_tieu_de from cv_du_an where id = b.du_an_id;
  end if;
  if not coalesce(v_ok, false) then
    raise exception 'Chỉ người giao việc, chủ dự án hoặc Ban giám đốc mới xử lý được góp ý.';
  end if;
  if p_trang_thai = 'da_tra_loi' and v_tl is null and b.tra_loi is null then raise exception 'Hãy nhập câu trả lời.'; end if;
  update cv_binh_luan set trang_thai_gop_y = p_trang_thai, tra_loi = coalesce(v_tl, tra_loi) where id = p_binh_luan_id;
  if b.cong_viec_id is not null then
    perform cv_ghi_ls(b.cong_viec_id, 'xu_ly_gop_y', cv_ten_nguoi(auth.uid()) || ' xử lý góp ý của '
                      || coalesce(cv_ten_nguoi(b.nguoi_viet), '') || ': '
                      || case p_trang_thai when 'da_tiep_thu' then 'đã tiếp thu' when 'da_tra_loi' then 'đã trả lời'
                                           when 'khong_ap_dung' then 'không áp dụng' else 'đang xem xét' end
                      || coalesce('. ' || v_tl, '') || '.');
  end if;
  perform cv_gui_tb(array[b.nguoi_viet], 'gop_y', b.cong_viec_id, b.du_an_id,
                    cv_ten_nguoi(auth.uid()) || ' phản hồi góp ý của bạn trong "' || v_tieu_de || '": '
                    || case p_trang_thai when 'da_tiep_thu' then 'Đã tiếp thu' when 'da_tra_loi' then 'Đã trả lời'
                                         when 'khong_ap_dung' then 'Không áp dụng' else 'Đang xem xét' end
                    || coalesce(' — ' || v_tl, ''), false);
end;
$$;

-- Đánh dấu đã đọc (null = tất cả của tôi).
create or replace function public.cv_doc_thong_bao(p_ids bigint[] default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Bạn cần đăng nhập.'; end if;
  update cv_thong_bao set da_doc = true, da_doc_luc = now()
  where nguoi_nhan = auth.uid() and not da_doc and (p_ids is null or id = any(p_ids));
end;
$$;

-- Tạo dự án (chu_du_an = auth.uid()).
create or replace function public.cv_tao_du_an(p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_ten text := trim(coalesce(p->>'ten', '')); v_bp text := nullif(trim(coalesce(p->>'bo_phan', '')), '');
        v_bd date; v_kt date;
begin
  if auth.uid() is null then raise exception 'Bạn cần đăng nhập.'; end if;
  if v_ten = '' then raise exception 'Hãy nhập tên dự án.'; end if;
  if v_bp is not null and not exists (select 1 from cv_bo_phan where ten = v_bp) then raise exception 'Bộ phận không hợp lệ.'; end if;
  begin
    v_bd := nullif(p->>'ngay_bat_dau', '')::date;
    v_kt := nullif(p->>'ngay_ket_thuc', '')::date;
  exception when others then
    raise exception 'Ngày bắt đầu / kết thúc không hợp lệ.';
  end;
  if v_bd is not null and v_kt is not null and v_kt < v_bd then raise exception 'Ngày kết thúc phải sau ngày bắt đầu.'; end if;
  insert into cv_du_an (ten, mo_ta, bo_phan, chu_du_an, ngay_bat_dau, ngay_ket_thuc, created_by)
  values (v_ten, nullif(trim(coalesce(p->>'mo_ta', '')), ''), v_bp, auth.uid(), v_bd, v_kt, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

-- Ghi tệp đã tải lên bucket "cong-viec" (đường dẫn <cong_viec_id>/<tên file>).
create or replace function public.cv_ghi_tep(p_cong_viec_id bigint, p_duong_dan text, p_ten_tep text, p_loai_mime text)
returns bigint language plpgsql security definer set search_path = public as $$
declare v cv_cong_viec; v_id bigint; v_dd text := trim(coalesce(p_duong_dan, ''));
begin
  v := cv_lay_viec(p_cong_viec_id);
  if v_dd = '' then raise exception 'Thiếu đường dẫn tệp.'; end if;
  if position((p_cong_viec_id::text || '/') in v_dd) = 0 then raise exception 'Đường dẫn tệp không đúng thư mục của việc.'; end if;
  insert into cv_tep (cong_viec_id, duong_dan, ten_tep, loai_mime, created_by)
  values (p_cong_viec_id, v_dd, nullif(trim(coalesce(p_ten_tep, '')), ''), nullif(trim(coalesce(p_loai_mime, '')), ''), auth.uid())
  returning id into v_id;
  perform cv_ghi_ls(p_cong_viec_id, 'them_tep', cv_ten_nguoi(auth.uid()) || ' thêm tệp: ' || coalesce(nullif(trim(p_ten_tep), ''), v_dd));
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Quét quá hạn (nội bộ, pg_cron mỗi giờ). 1 lần / việc / mốc hạn.
-- ---------------------------------------------------------------------------
create or replace function public.cv_quet_qua_han()
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in
    select id, tieu_de, han, nguoi_lam, nguoi_giao from cv_cong_viec
    where trang_thai not in ('hoan_thanh', 'huy') and han < now()
      and (qua_han_da_bao_luc is null or qua_han_da_bao_luc < han)
    for update skip locked
  loop
    perform cv_gui_tb(array[r.nguoi_lam, r.nguoi_giao], 'qua_han', r.id, null,
                      'Quá hạn: ' || r.tieu_de || ' (hạn ' || cv_fmt(r.han) || ')', true);
    update cv_cong_viec set qua_han_da_bao_luc = now() where id = r.id;
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Quyền thực thi
-- ---------------------------------------------------------------------------
-- RPC + hàm view/policy cần: chỉ authenticated.
revoke execute on function public.cv_ten_nguoi(uuid) from public, anon;
grant  execute on function public.cv_ten_nguoi(uuid) to authenticated;
revoke execute on function public.cv_xem_duoc(bigint) from public, anon;
grant  execute on function public.cv_xem_duoc(bigint) to authenticated;
revoke execute on function public.cv_danh_sach_nguoi() from public, anon;
grant  execute on function public.cv_danh_sach_nguoi() to authenticated;
revoke execute on function public.cv_tao_viec(jsonb) from public, anon;
grant  execute on function public.cv_tao_viec(jsonb) to authenticated;
revoke execute on function public.cv_sua_viec(bigint, jsonb) from public, anon;
grant  execute on function public.cv_sua_viec(bigint, jsonb) to authenticated;
revoke execute on function public.cv_nhan_viec(bigint) from public, anon;
grant  execute on function public.cv_nhan_viec(bigint) to authenticated;
revoke execute on function public.cv_them_buoc(bigint, text) from public, anon;
grant  execute on function public.cv_them_buoc(bigint, text) to authenticated;
revoke execute on function public.cv_xoa_buoc(bigint) from public, anon;
grant  execute on function public.cv_xoa_buoc(bigint) to authenticated;
revoke execute on function public.cv_tick_buoc(bigint, boolean) from public, anon;
grant  execute on function public.cv_tick_buoc(bigint, boolean) to authenticated;
revoke execute on function public.cv_bao_xong(bigint, text) from public, anon;
grant  execute on function public.cv_bao_xong(bigint, text) to authenticated;
revoke execute on function public.cv_duyet(bigint) from public, anon;
grant  execute on function public.cv_duyet(bigint) to authenticated;
revoke execute on function public.cv_tra_lai(bigint, text) from public, anon;
grant  execute on function public.cv_tra_lai(bigint, text) to authenticated;
revoke execute on function public.cv_xin_gia_han(bigint, timestamptz, text) from public, anon;
grant  execute on function public.cv_xin_gia_han(bigint, timestamptz, text) to authenticated;
revoke execute on function public.cv_tra_loi_gia_han(bigint, boolean) from public, anon;
grant  execute on function public.cv_tra_loi_gia_han(bigint, boolean) to authenticated;
revoke execute on function public.cv_nhac_viec(bigint) from public, anon;
grant  execute on function public.cv_nhac_viec(bigint) to authenticated;
revoke execute on function public.cv_mo_lai(bigint) from public, anon;
grant  execute on function public.cv_mo_lai(bigint) to authenticated;
revoke execute on function public.cv_huy_viec(bigint, text) from public, anon;
grant  execute on function public.cv_huy_viec(bigint, text) to authenticated;
revoke execute on function public.cv_viet_binh_luan(bigint, bigint, text, text, uuid[]) from public, anon;
grant  execute on function public.cv_viet_binh_luan(bigint, bigint, text, text, uuid[]) to authenticated;
revoke execute on function public.cv_dong_tinh(bigint) from public, anon;
grant  execute on function public.cv_dong_tinh(bigint) to authenticated;
revoke execute on function public.cv_xu_ly_gop_y(bigint, text, text) from public, anon;
grant  execute on function public.cv_xu_ly_gop_y(bigint, text, text) to authenticated;
revoke execute on function public.cv_doc_thong_bao(bigint[]) from public, anon;
grant  execute on function public.cv_doc_thong_bao(bigint[]) to authenticated;
revoke execute on function public.cv_tao_du_an(jsonb) from public, anon;
grant  execute on function public.cv_tao_du_an(jsonb) to authenticated;
revoke execute on function public.cv_ghi_tep(bigint, text, text, text) from public, anon;
grant  execute on function public.cv_ghi_tep(bigint, text, text, text) to authenticated;

-- Hàm nội bộ: không role client nào gọi trực tiếp được.
revoke execute on function public.cv_la_bgd() from public, anon, authenticated;
revoke execute on function public.cv_fmt(timestamptz) from public, anon, authenticated;
revoke execute on function public.cv_uuid(text) from public, anon, authenticated;
revoke execute on function public.cv_ts(text) from public, anon, authenticated;
revoke execute on function public.cv_ds_uuid(jsonb) from public, anon, authenticated;
revoke execute on function public.cv_gui_tb(uuid[], text, bigint, bigint, text, boolean) from public, anon, authenticated;
revoke execute on function public.cv_xong_tb(bigint, text[], uuid) from public, anon, authenticated;
revoke execute on function public.cv_ghi_ls(bigint, text, text) from public, anon, authenticated;
revoke execute on function public.cv_lay_viec(bigint) from public, anon, authenticated;
revoke execute on function public.cv_quyen_giao(uuid) from public, anon, authenticated;
revoke execute on function public.cv_nguoi_lam_va_ph(bigint) from public, anon, authenticated;
revoke execute on function public.cv_quet_qua_han() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. Storage bucket "cong-viec" (đọc công khai như su-co-duc, ghi: authenticated)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('cong-viec', 'cong-viec', true, 20971520)
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit;

drop policy if exists "public read cong-viec" on storage.objects;
create policy "public read cong-viec" on storage.objects
  for select using (bucket_id = 'cong-viec');
drop policy if exists "auth upload cong-viec" on storage.objects;
create policy "auth upload cong-viec" on storage.objects
  for insert to authenticated with check (bucket_id = 'cong-viec');

-- ---------------------------------------------------------------------------
-- 9. Lịch pg_cron mỗi giờ (phút 05) — chỉ khi có extension pg_cron
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'cv_quet_qua_han') then
      perform cron.unschedule('cv_quet_qua_han');
    end if;
    perform cron.schedule('cv_quet_qua_han', '5 * * * *', 'select public.cv_quet_qua_han();');
  end if;
end $$;
