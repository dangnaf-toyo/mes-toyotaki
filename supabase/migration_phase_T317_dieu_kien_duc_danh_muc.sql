-- T317 — Điều kiện đúc, Bước 1: danh mục thông số + danh mục dụng cụ đúc
--   * duc_dk_thong_so : 40 thông số chuẩn HPDC (VL/PE/NT/PT), gợi ý Nhôm/Kẽm, ngưỡng ±% trưởng ca tự chỉnh
--   * duc_dung_cu     : đầu típ, ống liệu, piston kẽm, xéc-măng, cổ ngỗng, vòi phun (mã <Loại>-<Φ3 số>-<STT2 số>)
--   * master_machines.loai_may = 'Đúc nhôm' (DC 3–11) / 'Đúc kẽm' (Kẽm 160T, 190T)
--     (Gia công chỉ đọc 'Phay CNC'/'Tiện CNC'/'Chuốt' + lọc bộ phận Gia công – không ảnh hưởng)
--   * Quyền: mọi người đọc; ghi = admin hoặc người phụ trách bộ phận 'Kỹ thuật'

-- ---------- Hàm quyền ----------
create or replace function public.duc_dk_la_ky_thuat()
returns boolean
language sql stable security definer
set search_path to 'public'
as $$
  select has_role('admin') or auth.uid() = any(cv_pd_ds_bo_phan('Kỹ thuật'));
$$;
revoke execute on function public.duc_dk_la_ky_thuat() from public, anon;
grant execute on function public.duc_dk_la_ky_thuat() to authenticated;

-- ---------- Danh mục thông số ----------
create table if not exists public.duc_dk_thong_so (
  ma_ts          text primary key,
  nhom           text not null check (nhom in ('VL','PE','NT','PT')),
  thu_tu         int  not null default 0,
  ten            text not null,
  don_vi         text,
  kieu           text not null default 'so' check (kieu in ('so','chu','co_khong','chon_nvl')),
  ap_dung        text not null default 'ca_hai' check (ap_dung in ('nhom','kem','ca_hai')),
  bat_buoc_nhom  boolean not null default false,
  bat_buoc_kem   boolean not null default false,
  phu_thuoc      text,                       -- vd PT01: chỉ bắt buộc khi PT01 = Có
  goi_y_nhom_min numeric, goi_y_nhom_max numeric,
  goi_y_kem_min  numeric, goi_y_kem_max  numeric,
  goi_y_chu      text,                       -- gợi ý dạng chữ: "theo SP", "≤ 85% lực máy"…
  nguong_pct     numeric not null default 5 check (nguong_pct >= 0 and nguong_pct <= 100),
  ma_muc_td      text,                       -- nối duc_thay_doi_mau.ma (T307)
  hien           boolean not null default true,
  updated_at     timestamptz not null default now(),
  nguoi_sua      uuid
);

-- ---------- Danh mục dụng cụ ----------
create table if not exists public.duc_dung_cu (
  ma               text primary key check (ma ~ '^(DT|OL|PK|XM|CN|VP)-[0-9]{3}-[0-9]{2}$'),
  loai             text not null check (loai in ('DT','OL','PK','XM','CN','VP')),
  ten              text not null,
  duong_kinh       numeric,
  chieu_dai        numeric,
  vat_lieu         text,
  nha_cung_cap     text,
  may_dung         text[] not null default '{}',
  tuoi_tho_du_kien int,
  anh              text[] not null default '{}',
  ghi_chu          text,
  hien             boolean not null default true,
  updated_at       timestamptz not null default now(),
  nguoi_sua        uuid,
  check (split_part(ma, '-', 1) = loai)
);

-- updated_at + nguoi_sua tự ghi
create or replace function public.duc_dk_dm_dong_dau()
returns trigger language plpgsql
set search_path to 'public'
as $$
begin
  new.updated_at := now();
  new.nguoi_sua  := auth.uid();
  return new;
end $$;

drop trigger if exists trg_duc_dk_thong_so_dau on public.duc_dk_thong_so;
create trigger trg_duc_dk_thong_so_dau before insert or update on public.duc_dk_thong_so
  for each row execute function public.duc_dk_dm_dong_dau();
drop trigger if exists trg_duc_dung_cu_dau on public.duc_dung_cu;
create trigger trg_duc_dung_cu_dau before insert or update on public.duc_dung_cu
  for each row execute function public.duc_dk_dm_dong_dau();

-- ---------- RLS ----------
alter table public.duc_dk_thong_so enable row level security;
alter table public.duc_dung_cu     enable row level security;

drop policy if exists "dkts doc"  on public.duc_dk_thong_so;
drop policy if exists "dkts them" on public.duc_dk_thong_so;
drop policy if exists "dkts sua"  on public.duc_dk_thong_so;
drop policy if exists "dkts xoa"  on public.duc_dk_thong_so;
create policy "dkts doc"  on public.duc_dk_thong_so for select to authenticated using (true);
create policy "dkts them" on public.duc_dk_thong_so for insert to authenticated with check (duc_dk_la_ky_thuat());
create policy "dkts sua"  on public.duc_dk_thong_so for update to authenticated using (duc_dk_la_ky_thuat()) with check (duc_dk_la_ky_thuat());
create policy "dkts xoa"  on public.duc_dk_thong_so for delete to authenticated using (has_role('admin'));

drop policy if exists "dungcu doc"  on public.duc_dung_cu;
drop policy if exists "dungcu them" on public.duc_dung_cu;
drop policy if exists "dungcu sua"  on public.duc_dung_cu;
drop policy if exists "dungcu xoa"  on public.duc_dung_cu;
create policy "dungcu doc"  on public.duc_dung_cu for select to authenticated using (true);
create policy "dungcu them" on public.duc_dung_cu for insert to authenticated with check (duc_dk_la_ky_thuat());
create policy "dungcu sua"  on public.duc_dung_cu for update to authenticated using (duc_dk_la_ky_thuat()) with check (duc_dk_la_ky_thuat());
create policy "dungcu xoa"  on public.duc_dung_cu for delete to authenticated using (has_role('admin'));

revoke all on public.duc_dk_thong_so, public.duc_dung_cu from anon;
grant select, insert, update, delete on public.duc_dk_thong_so, public.duc_dung_cu to authenticated;

-- ---------- Nạp 40 thông số ----------
insert into public.duc_dk_thong_so
  (ma_ts, nhom, thu_tu, ten, don_vi, kieu, ap_dung, bat_buoc_nhom, bat_buoc_kem, phu_thuoc,
   goi_y_nhom_min, goi_y_nhom_max, goi_y_kem_min, goi_y_kem_max, goi_y_chu, ma_muc_td)
values
-- VL — Vật liệu & rót
('VL01','VL',1,'NVL kim loại',null,'chon_nvl','ca_hai',true,true,null,null,null,null,null,'Tự lấy từ BOM','V03'),
('VL02','VL',2,'Nhiệt độ kim loại lò giữ nhiệt / nồi kẽm','°C','so','ca_hai',true,true,null,650,690,410,430,null,'D07'),
('VL03','VL',3,'Lượng rót 1 lần','kg','so','nhom',true,false,null,null,null,null,null,'Theo SP',null),
('VL04','VL',4,'Khối lượng 1 lần bắn (SP + cuống + túi tràn)','g','so','ca_hai',false,false,null,null,null,null,null,'Theo SP',null),
('VL05','VL',5,'Tỷ lệ hồi liệu tối đa','%','so','ca_hai',false,false,null,0,50,0,50,null,'V04'),
('VL06','VL',6,'Nhiệt độ vòi phun','°C','so','kem',false,true,null,null,null,430,480,null,null),
-- PE — Phun ép
('PE01','PE',1,'Cỡ piston (Φ)','mm','so','ca_hai',true,true,null,40,100,40,70,null,'M03'),
('PE02','PE',2,'Tốc độ pha 1 (chậm)','m/s','so','ca_hai',true,true,null,0.1,0.4,0.3,0.8,null,'D01'),
('PE03','PE',3,'Tốc độ pha 2 (nhanh)','m/s','so','ca_hai',true,true,null,1.5,5.0,1.5,4.0,null,'D02'),
('PE04','PE',4,'Điểm chuyển pha','mm','so','ca_hai',true,true,null,null,null,null,null,'Theo SP','D03'),
('PE05','PE',5,'Tổng hành trình piston','mm','so','ca_hai',false,false,null,null,null,null,null,'Theo SP',null),
('PE06','PE',6,'Áp suất tăng áp (Nhôm) / áp phun (Kẽm)','MPa','so','ca_hai',true,true,null,50,100,10,30,null,'D04'),
('PE07','PE',7,'Áp cài trên máy (đồng hồ)','bar','so','ca_hai',false,false,null,null,null,null,null,'Theo máy',null),
('PE08','PE',8,'Thời gian trễ tăng áp','ms','so','nhom',false,false,null,0,40,null,null,null,'D05'),
('PE09','PE',9,'Thời gian lên áp','ms','so','nhom',false,false,null,10,30,null,null,null,null),
('PE10','PE',10,'Chiều dày bánh cặn','mm','so','nhom',true,false,null,15,30,null,null,null,'D06'),
('PE11','PE',11,'Áp khí N₂ bình tích áp','bar','so','ca_hai',false,false,null,null,null,null,null,'Theo máy','M04'),
('PE12','PE',12,'Lực khoá khuôn cài','tấn','so','ca_hai',false,false,null,null,null,null,null,'≤ 85% lực máy',null),
('PE13','PE',13,'Tỷ lệ điền ống liệu','%','so','nhom',false,false,null,30,60,null,null,null,null),
('PE14','PE',14,'Tốc độ cổng rót (tính)','m/s','so','ca_hai',false,false,null,20,60,30,50,null,null),
-- NT — Nhiệt độ & thời gian
('NT01','NT',1,'Nhiệt cài máy gia nhiệt — khuôn tĩnh','°C','so','ca_hai',true,true,null,150,250,120,200,null,'D08'),
('NT02','NT',2,'Nhiệt cài máy gia nhiệt — khuôn động','°C','so','ca_hai',false,false,null,150,250,120,200,null,'D08'),
('NT03','NT',3,'Nhiệt mặt khuôn đo trước phun','°C','so','ca_hai',false,false,null,180,280,150,220,null,null),
('NT04','NT',4,'Thời gian làm nguội trong khuôn','giây','so','ca_hai',true,true,null,3,15,1,5,null,'D09'),
('NT05','NT',5,'Chu kỳ máy','giây','so','ca_hai',true,true,null,30,120,8,40,null,'D10'),
('NT06','NT',6,'Thời gian phun chất tách khuôn','giây','so','ca_hai',true,true,null,1,5,0.5,3,null,'D11'),
('NT07','NT',7,'Thời gian thổi khí','giây','so','ca_hai',false,false,null,1,5,0.5,3,null,null),
('NT08','NT',8,'Nồng độ chất tách khuôn','%','so','ca_hai',true,true,null,0.5,2,0.5,2,null,'D12'),
('NT09','NT',9,'Loại chất tách khuôn',null,'chu','ca_hai',true,true,null,null,null,null,null,null,'D13'),
('NT10','NT',10,'Dầu bôi trơn piston: loại / lượng',null,'chu','ca_hai',false,false,null,null,null,null,null,null,'D17'),
('NT11','NT',11,'Nhiệt dầu thuỷ lực máy','°C','so','ca_hai',false,false,null,35,55,35,55,null,null),
-- PT — Phụ trợ
('PT01','PT',1,'Hút chân không',null,'co_khong','ca_hai',false,false,null,null,null,null,null,null,'D15'),
('PT02','PT',2,'Độ chân không đạt','kPa','so','nhom',false,false,'PT01',0,10,null,null,null,'D15'),
('PT03','PT',3,'Điểm bắt đầu hút','mm','so','nhom',false,false,'PT01',null,null,null,null,'Theo SP','D15'),
('PT04','PT',4,'Ép cục bộ',null,'co_khong','nhom',false,false,null,null,null,null,null,null,'D16'),
('PT05','PT',5,'Thời gian trễ ép cục bộ','ms','so','nhom',false,false,'PT04',null,null,null,null,'Theo SP','D16'),
('PT06','PT',6,'Áp ép cục bộ','MPa','so','nhom',false,false,'PT04',null,null,null,null,'Theo SP','D16'),
('PT07','PT',7,'Nước làm mát: đường mở / đóng',null,'chu','ca_hai',false,false,null,null,null,null,null,null,'D14'),
('PT08','PT',8,'Lưu lượng nước làm mát','l/phút','so','ca_hai',false,false,null,null,null,null,null,'Theo khuôn','D14'),
('PT09','PT',9,'Thời gian đẩy sản phẩm','giây','so','ca_hai',false,false,null,null,null,null,null,'Theo SP',null)
on conflict (ma_ts) do nothing;

-- ---------- Loại máy Đúc ----------
update public.master_machines set loai_may = 'Đúc nhôm'
 where ma_may in ('DC 3','DC 4','DC 5','DC 6','DC 7','DC 8','DC 9','DC 10','DC 11') and loai_may is null;
update public.master_machines set loai_may = 'Đúc kẽm'
 where ma_may in ('Kẽm 160T','Kẽm 190T') and loai_may is null;
