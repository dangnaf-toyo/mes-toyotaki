-- T319a: Điều kiện đúc Bước 3 — bảng phiếu (chạy trước T319b).
-- Phiếu theo cặp (Mã SP × Máy), nhiều lần ban hành, chỉ 1 lần Hiệu lực, chỉ 1 lần đang mở (nháp/chờ).
-- Chỉ ghi qua hàm (T319b); mọi người đăng nhập đọc.

create table if not exists public.duc_dk_phieu (
  id bigserial primary key,
  ma_sp text not null,
  ma_may text not null,
  lan int not null check (lan >= 1),
  trang_thai text not null default 'nhap'
    check (trang_thai in ('nhap', 'cho_kiem', 'cho_duyet', 'hieu_luc', 'het_hieu_luc')),
  ly_do text,                               -- bắt buộc từ lần 2 (kiểm lúc Gửi)
  ma_nvl text,                              -- VL01
  anh text[] not null default '{}',
  tep text[] not null default '{}',
  nguoi_lap uuid, lap_luc timestamptz not null default now(),
  gui_luc timestamptz,                      -- lần Gửi gần nhất
  cho_tu timestamptz,                       -- vào trạng thái chờ hiện tại lúc nào (nhắc 24 giờ)
  nguoi_kiem uuid, kiem_luc timestamptz, ghi_chu_kiem text,
  nguoi_duyet uuid, duyet_luc timestamptz, ghi_chu_duyet text,
  hieu_luc_tu timestamptz, het_hieu_luc_luc timestamptz,
  can_cap_nhat boolean not null default false,   -- Bước 7
  lich_su jsonb not null default '[]',      -- [{viec, nguoi, luc, ghi_chu}]
  updated_at timestamptz not null default now(),
  unique (ma_sp, ma_may, lan)
);
-- KHÔNG dùng ON CONFLICT trên 2 index một phần này.
create unique index if not exists duc_dk_phieu_1_hieu_luc on public.duc_dk_phieu (ma_sp, ma_may) where trang_thai = 'hieu_luc';
create unique index if not exists duc_dk_phieu_1_dang_mo on public.duc_dk_phieu (ma_sp, ma_may)
  where trang_thai in ('nhap', 'cho_kiem', 'cho_duyet');
create index if not exists duc_dk_phieu_may on public.duc_dk_phieu (ma_may, trang_thai);
create index if not exists duc_dk_phieu_cho on public.duc_dk_phieu (trang_thai) where trang_thai in ('cho_kiem', 'cho_duyet');

create table if not exists public.duc_dk_gia_tri (
  id_phieu bigint not null references public.duc_dk_phieu(id) on delete cascade,
  ma_ts text not null references public.duc_dk_thong_so(ma_ts),
  chuan numeric,                            -- kiểu số
  gia_tri_chu text,                         -- kiểu chữ; Có/Không = 'co' / 'khong'
  ghi_chu text,
  primary key (id_phieu, ma_ts)
);

create table if not exists public.duc_dk_dung_cu (
  id_phieu bigint not null references public.duc_dk_phieu(id) on delete cascade,
  loai text not null check (loai in ('DT', 'OL', 'PK', 'XM', 'CN', 'VP')),
  ma_dung_cu text not null references public.duc_dung_cu(ma),
  primary key (id_phieu, loai)
);

alter table public.duc_dk_phieu enable row level security;
alter table public.duc_dk_gia_tri enable row level security;
alter table public.duc_dk_dung_cu enable row level security;
drop policy if exists "dkp doc" on public.duc_dk_phieu;
drop policy if exists "dkgt doc" on public.duc_dk_gia_tri;
drop policy if exists "dkdc doc" on public.duc_dk_dung_cu;
create policy "dkp doc" on public.duc_dk_phieu for select to authenticated using (true);
create policy "dkgt doc" on public.duc_dk_gia_tri for select to authenticated using (true);
create policy "dkdc doc" on public.duc_dk_dung_cu for select to authenticated using (true);
revoke all on public.duc_dk_phieu, public.duc_dk_gia_tri, public.duc_dk_dung_cu from anon;
revoke insert, update, delete on public.duc_dk_phieu, public.duc_dk_gia_tri, public.duc_dk_dung_cu from authenticated;
grant select on public.duc_dk_phieu, public.duc_dk_gia_tri, public.duc_dk_dung_cu to authenticated;

-- Chuông: thêm nguồn 'dieu_kien_duc' (giữ mọi nguồn đang có)
do $$
declare v text;
begin
  select pg_get_constraintdef(oid) into v from pg_constraint where conname = 'cv_thong_bao_nguon_check';
  if v is not null and v not like '%dieu_kien_duc%' then
    execute 'alter table public.cv_thong_bao drop constraint cv_thong_bao_nguon_check';
    execute 'alter table public.cv_thong_bao add constraint cv_thong_bao_nguon_check '
      || replace(v, '])))', ', ''dieu_kien_duc''::text])))');
  end if;
end $$;
