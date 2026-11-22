-- T307a: Điểm thay đổi chủ động công đoạn Đúc — bảng danh mục (51 mục), phiếu, giá trị chuẩn.
-- Chạy trước T307b. An toàn chạy lại (idempotent; danh mục chỉ nạp mục chưa có — không ghi đè chỉnh sửa của admin).
--
-- nhom       : dieu_kien | khuon | may | vat_lieu | khac
-- kieu_nhap  : so (2 ô số + đơn vị) | chu (2 ô chữ)
-- nguoi_duyet: khong | ky_thuat | thiet_bi | to_truong_khuon | qlbp_duc | qa
-- nguong_pct : có giá trị (VD 5) → trong ±ngưỡng so với GIÁ TRỊ CHUẨN thì trưởng ca tự chỉnh, vượt thì nguoi_duyet duyệt;
--              trống → luôn cần nguoi_duyet (trừ 'khong').
-- tu_chon    : mục "Khác" — trưởng ca tự chọn cần IPQC / người duyệt.

create table if not exists public.duc_thay_doi_mau (
  ma          text primary key,
  nhom        text not null check (nhom in ('dieu_kien', 'khuon', 'may', 'vat_lieu', 'khac')),
  thu_tu      int  not null default 0,
  ten         text not null check (btrim(ten) <> ''),
  kieu_nhap   text not null default 'chu' check (kieu_nhap in ('so', 'chu')),
  don_vi      text,
  can_ipqc    boolean not null default true,
  xac_nhan    text[] not null default '{}',
  nguoi_duyet text not null default 'khong' check (nguoi_duyet in ('khong', 'ky_thuat', 'thiet_bi', 'to_truong_khuon', 'qlbp_duc', 'qa')),
  nguong_pct  numeric check (nguong_pct is null or nguong_pct > 0),
  tu_chon     boolean not null default false,
  hieu_luc    boolean not null default true,
  updated_at  timestamptz not null default now(),
  nguoi_sua   text
);

create table if not exists public.duc_thay_doi (
  id                bigserial primary key,
  thoi_diem_ghi     timestamptz not null default now(),
  nguoi_ghi         text,
  nguoi_ghi_id      uuid,
  id_dong           text,
  ma_may            text not null,
  ma_sp             text,
  so_khuon          text,
  ngay              date,
  ca                text,
  chi_tiet          jsonb not null,            -- [{ma,nhom,ten,kieu,don_vi,truoc,sau,chuan,pct,vuot,can_ipqc,nguoi_duyet,xac_nhan[]}]
  ly_do             text,
  ma_loi            text,
  ghi_chu           text,
  anh_urls          jsonb not null default '[]',
  can_ipqc          boolean not null default false,
  can_duyet         text[] not null default '{}',
  da_duyet          jsonb not null default '[]', -- [{nhom,nguoi,luc,dong_y,ghi_chu}]
  ket_qua_duyet     text check (ket_qua_duyet in ('da_duyet', 'khong_duyet')),
  khan              boolean not null default false,
  ly_do_khan        text,
  trang_thai        text not null check (trang_thai in
                      ('cho_duyet', 'cho_ap_dung', 'cho_ipqc', 'ok', 'ng', 'khong_kiem', 'ghi_nhan', 'khong_duyet', 'huy')),
  thoi_diem_ap_dung timestamptz,
  id_checkpoint     text,
  ket_qua_ipqc      text,
  thoi_diem_ipqc    timestamptz,
  nguoi_kiem        text,
  xac_nhan_kq       jsonb,
  id_su_co          text,
  ly_do_huy         text,
  updated_at        timestamptz not null default now()
);
create index if not exists duc_thay_doi_may_tt_idx on public.duc_thay_doi (ma_may, trang_thai);
create index if not exists duc_thay_doi_cp_idx on public.duc_thay_doi (id_checkpoint) where id_checkpoint is not null;
create index if not exists duc_thay_doi_ghi_idx on public.duc_thay_doi (thoi_diem_ghi desc);

-- Giá trị chuẩn cho quy tắc ±ngưỡng: lần đầu = giá trị "Trước"; sau mỗi lần người duyệt đồng ý mục vượt ngưỡng = giá trị "Sau".
create table if not exists public.duc_thay_doi_chuan (
  ma_may       text not null,
  ma_sp        text not null,
  ma_muc       text not null,
  gia_tri      numeric not null,
  nguon        text not null default 'ban_dau' check (nguon in ('ban_dau', 'da_duyet')),
  id_phieu     bigint,
  cap_nhat_luc timestamptz not null default now(),
  nguoi        text,
  primary key (ma_may, ma_sp, ma_muc)
);

-- Quyền: mọi người đọc; phiếu + chuẩn chỉ ghi qua hàm (T307b); danh mục chỉ admin ghi.
alter table public.duc_thay_doi_mau   enable row level security;
alter table public.duc_thay_doi       enable row level security;
alter table public.duc_thay_doi_chuan enable row level security;
revoke all on public.duc_thay_doi_mau, public.duc_thay_doi, public.duc_thay_doi_chuan from anon, authenticated;
grant select on public.duc_thay_doi_mau, public.duc_thay_doi, public.duc_thay_doi_chuan to anon, authenticated;
grant insert, update, delete on public.duc_thay_doi_mau to authenticated;

drop policy if exists "td_mau doc" on public.duc_thay_doi_mau;
create policy "td_mau doc" on public.duc_thay_doi_mau for select to public using (true);
drop policy if exists "td_mau admin them" on public.duc_thay_doi_mau;
create policy "td_mau admin them" on public.duc_thay_doi_mau for insert to authenticated
  with check (public.has_role(variadic array['admin']));
drop policy if exists "td_mau admin sua" on public.duc_thay_doi_mau;
create policy "td_mau admin sua" on public.duc_thay_doi_mau for update to authenticated
  using (public.has_role(variadic array['admin'])) with check (public.has_role(variadic array['admin']));
drop policy if exists "td_mau admin xoa" on public.duc_thay_doi_mau;
create policy "td_mau admin xoa" on public.duc_thay_doi_mau for delete to authenticated
  using (public.has_role(variadic array['admin']));
drop policy if exists "td doc" on public.duc_thay_doi;
create policy "td doc" on public.duc_thay_doi for select to public using (true);
drop policy if exists "td_chuan doc" on public.duc_thay_doi_chuan;
create policy "td_chuan doc" on public.duc_thay_doi_chuan for select to public using (true);

create or replace function public.duc_thay_doi_mau_cham()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists trg_duc_thay_doi_mau_cham on public.duc_thay_doi_mau;
create trigger trg_duc_thay_doi_mau_cham before insert or update on public.duc_thay_doi_mau
  for each row execute function public.duc_thay_doi_mau_cham();

-- ── Nạp 51 mục (chỉ thêm mục chưa có) ───────────────────────────────────────
insert into public.duc_thay_doi_mau (ma, nhom, thu_tu, ten, kieu_nhap, don_vi, can_ipqc, xac_nhan, nguoi_duyet, nguong_pct, tu_chon) values
  ('D01','dieu_kien', 1,'Tốc độ pha 1','so','m/s',true, array['Ngoại quan 5 SP đầu','Cắt 1 SP kiểm rỗ khí vùng cuối dòng chảy'],'ky_thuat',5,false),
  ('D02','dieu_kien', 2,'Tốc độ pha 2','so','m/s',true, array['Điền đầy, nguội hàn ở cuối dòng chảy','Bavia mặt phân khuôn'],'ky_thuat',5,false),
  ('D03','dieu_kien', 3,'Điểm chuyển pha','so','mm',true, array['Điền đầy','Cắt 1 SP kiểm rỗ khí','Bavia'],'ky_thuat',5,false),
  ('D04','dieu_kien', 4,'Áp suất tăng áp','so','MPa',true, array['Cắt 1 SP kiểm co ngót vùng dày','Bavia mặt phân khuôn','Kiểm kín khí (nếu có)'],'ky_thuat',5,false),
  ('D05','dieu_kien', 5,'Thời gian trễ tăng áp','so','ms',true, array['Cắt 1 SP kiểm co ngót vùng dày'],'ky_thuat',5,false),
  ('D06','dieu_kien', 6,'Chiều dày bánh cặn','so','mm',true, array['Đo bánh cặn trong tiêu chuẩn','Điền đầy','Co ngót'],'ky_thuat',5,false),
  ('D07','dieu_kien', 7,'Nhiệt độ nhôm lò giữ nhiệt','so','°C',true, array['Đo nhiệt nhôm thực tế','Nguội hàn, dính khuôn'],'ky_thuat',5,false),
  ('D08','dieu_kien', 8,'Nhiệt độ cài máy gia nhiệt khuôn','so','°C',true, array['Đo nhiệt mặt khuôn','Nguội hàn, dính khuôn'],'ky_thuat',5,false),
  ('D09','dieu_kien', 9,'Thời gian làm nguội trong khuôn','so','giây',true, array['Đo cong vênh / độ phẳng','Nứt','Dính khuôn'],'ky_thuat',5,false),
  ('D10','dieu_kien',10,'Chu kỳ máy','so','giây',true, array['Nhiệt mặt khuôn ổn định','Nguội hàn','Kích thước chính'],'ky_thuat',5,false),
  ('D11','dieu_kien',11,'Thời gian phun chất tách khuôn','so','giây',true, array['Dính khuôn','Vết phun, đốm trắng','Cắt 1 SP kiểm rỗ khí'],'ky_thuat',5,false),
  ('D12','dieu_kien',12,'Nồng độ pha chất tách khuôn','so','%',true, array['Dính khuôn','Vết phun, đốm trắng','Cắt 1 SP kiểm rỗ khí'],'ky_thuat',5,false),
  ('D13','dieu_kien',13,'Đổi loại chất tách khuôn','chu',null,true, array['Dính khuôn','Vết bẩn bề mặt','Bám sơn (SP có sơn)','Rỗ khí'],'ky_thuat',null,false),
  ('D14','dieu_kien',14,'Đóng / mở / chỉnh nước làm mát','chu',null,true, array['Nhiệt mặt khuôn','Dính khuôn','Co ngót','Nứt'],'khong',null,false),
  ('D15','dieu_kien',15,'Hút chân không: bật / tắt / đổi thời điểm','chu',null,true, array['Cắt 1 SP kiểm rỗ khí','Độ chân không đạt'],'ky_thuat',null,false),
  ('D16','dieu_kien',16,'Ép cục bộ: thời điểm / áp','chu',null,true, array['Cắt kiểm co ngót tại vị trí ép','Kín khí'],'ky_thuat',null,false),
  ('D17','dieu_kien',17,'Loại / lượng dầu bôi trơn piston','chu',null,true, array['Cắt 1 SP kiểm rỗ khí','Vết dầu bề mặt'],'khong',null,false),
  ('K01','khuon', 1,'Mài, đánh bóng lòng khuôn','chu',null,true, array['Ngoại quan bề mặt vùng sửa','Dính khuôn','Kích thước vùng sửa'],'to_truong_khuon',null,false),
  ('K02','khuon', 2,'Hàn đắp, sửa biên dạng','chu',null,true, array['Đo toàn bộ kích thước vùng sửa','Bavia','Nứt vùng hàn'],'ky_thuat',null,false),
  ('K03','khuon', 3,'Thay lõi / ty lõi','chu',null,true, array['Kích thước, vị trí lỗ','Lệch tâm'],'to_truong_khuon',null,false),
  ('K04','khuon', 4,'Thay ty đẩy','chu',null,true, array['Vết ty (lồi / lõm)','Cong vênh'],'khong',null,false),
  ('K05','khuon', 5,'Thay tấm chèn / con trượt','chu',null,true, array['Kích thước vùng chèn','Bavia khe trượt'],'to_truong_khuon',null,false),
  ('K06','khuon', 6,'Sửa rãnh thoát khí / túi xỉ','chu',null,true, array['Cắt 1 SP kiểm rỗ khí','Điền đầy'],'ky_thuat',null,false),
  ('K07','khuon', 7,'Sửa kênh dẫn / cổng rót','chu',null,true, array['Điền đầy','Rỗ khí','Bẻ cuống không sứt SP'],'ky_thuat',null,false),
  ('K08','khuon', 8,'Sửa / đổi đường nước làm mát khuôn','chu',null,true, array['Nhiệt mặt khuôn','Dính khuôn','Nứt','Co ngót'],'ky_thuat',null,false),
  ('K09','khuon', 9,'Bịt bớt / mở lại lòng khuôn','chu',null,true, array['Đúng số lòng','Điền đầy các lòng còn lại','Ghi rõ lòng bịt'],'ky_thuat',null,false),
  ('K10','khuon',10,'Thay bạc cuống','chu',null,true, array['Bavia cuống','Rỗ khí'],'khong',null,false),
  ('K11','khuon',11,'Xử lý bề mặt khuôn (thấm nitơ, phủ)','chu',null,true, array['Dính khuôn','Kích thước chính','Ngoại quan'],'ky_thuat',null,false),
  ('M01','may', 1,'Thay đầu piston','chu',null,true, array['Cắt 1 SP kiểm rỗ khí','Bánh cặn ổn định'],'khong',null,false),
  ('M02','may', 2,'Thay ống bơm','chu',null,true, array['Cắt 1 SP kiểm rỗ khí','Điền đầy'],'thiet_bi',null,false),
  ('M03','may', 3,'Đổi cỡ piston','so','mm',true, array['Điền đầy','Rỗ khí','Bavia','Kích thước'],'ky_thuat',null,false),
  ('M04','may', 4,'Nạp khí bình tăng áp / chỉnh hệ tăng áp','chu',null,true, array['Cắt 1 SP kiểm co ngót','Bavia'],'thiet_bi',null,false),
  ('M05','may', 5,'Chỉnh / thay muôi rót, robot rót','chu',null,true, array['Bánh cặn ổn định','Điền đầy'],'khong',null,false),
  ('M06','may', 6,'Chỉnh / thay robot phun khuôn','chu',null,true, array['Dính khuôn','Vết phun'],'khong',null,false),
  ('M07','may', 7,'Chỉnh / thay tay gắp lấy SP','chu',null,true, array['Cong vênh','Vết va đập'],'khong',null,false),
  ('M08','may', 8,'Thay / sửa máy gia nhiệt khuôn','chu',null,true, array['Đo nhiệt mặt khuôn','Nguội hàn','Dính khuôn'],'thiet_bi',null,false),
  ('M09','may', 9,'Bảo dưỡng định kỳ máy đúc','chu',null,true, array['Bavia mặt phân khuôn','Lệch khuôn','Kích thước chính'],'thiet_bi',null,false),
  ('V01','vat_lieu',1,'Lô thỏi mới (cùng mác, cùng nhà cung cấp)','chu',null,false, '{}','khong',null,false),
  ('V02','vat_lieu',2,'Đổi nhà cung cấp thỏi','chu',null,true, array['Phiếu IQC lô mới đạt','Cắt 1 SP kiểm rỗ khí, xỉ'],'qa',null,false),
  ('V03','vat_lieu',3,'Đổi mác hợp kim','chu',null,true, array['BOM / bản vẽ cho phép mác mới','Rỗ khí, xỉ','Kích thước'],'ky_thuat',null,false),
  ('V04','vat_lieu',4,'Tỷ lệ phế liệu hồi lò','so','%',true, array['Cắt 1 SP kiểm rỗ khí, xỉ'],'ky_thuat',null,false),
  ('V05','vat_lieu',5,'Đổi chất trợ dung / khử khí, thời gian khử khí','chu',null,true, array['Cắt 1 SP kiểm rỗ khí, xỉ'],'ky_thuat',null,false),
  ('V06','vat_lieu',6,'Vệ sinh / đổi lò giữ nhiệt, nồi nấu','chu',null,true, array['Đo nhiệt nhôm','Xỉ trên SP'],'khong',null,false),
  ('N01','khac', 1,'Thợ lần đầu đứng máy / mã này','chu',null,false, '{}','qlbp_duc',null,false),
  ('N02','khac', 2,'Đổi thợ trong ca (thay tạm)','chu',null,false, '{}','khong',null,false),
  ('N03','khac', 3,'Đổi thao tác / tiêu chuẩn công việc','chu',null,false, '{}','qlbp_duc',null,false),
  ('N04','khac', 4,'Đổi / hiệu chuẩn lại dụng cụ đo, dưỡng','chu',null,false, '{}','qa',null,false),
  ('N05','khac', 5,'Đổi khay, thùng, cách xếp SP','chu',null,false, '{}','khong',null,false),
  ('N06','khac', 6,'Chạy thử nghiệm / mẫu khách','chu',null,true, array['Theo nội dung yêu cầu thử (ghi trong phiếu)'],'ky_thuat',null,false),
  ('N07','khac', 7,'Đổi chương trình máy (cùng điều kiện)','chu',null,true, array['Đối chiếu điều kiện trên màn hình máy','Điền đầy, bavia'],'ky_thuat',null,false),
  ('Z99','khac',99,'Khác (tự ghi)','chu',null,false, '{}','khong',null,true)
on conflict (ma) do nothing;
