-- T204b (03/11/2026, CHỈ PROD — dọn dữ liệu): xoá 10 dòng duc_ca_hien_tai sót từ tháng 9
-- (21/09 DC4-DC8, 23/09 + 25/09 DC10 & Kẽm 190T). Ca của các dòng đều đã kết (có duc_bao_cao_ca),
-- không sự cố mở, không sự cố phụ. Bản sao lưu: duc_ca_hien_tai_sao_luu_t204 (RLS bật, không cấp quyền).
-- Cùng đợt: 545 điểm kiểm IPQC tồn được đóng 'het_hieu_luc', ghi duc_ipqc_dong_ton_log (nguoi_dong = Claude).
create table if not exists public.duc_ca_hien_tai_sao_luu_t204 as
  select now() as thoi_diem_sao_luu, c.* from public.duc_ca_hien_tai c where false;
alter table public.duc_ca_hien_tai_sao_luu_t204 enable row level security;
revoke all on public.duc_ca_hien_tai_sao_luu_t204 from anon, authenticated;

insert into public.duc_ca_hien_tai_sao_luu_t204
  select now(), c.* from public.duc_ca_hien_tai c
  where c.ngay < date '2026-10-01'
    and exists (select 1 from public.duc_bao_cao_ca b where b.ngay = c.ngay and b.ca = c.ca)
    and c.open_gio_phat_sinh is null
    and not exists (select 1 from public.duc_su_co_mo_them t where t.id_dong = c.id_dong);

delete from public.duc_ca_hien_tai c
 where c.id_dong in (select id_dong from public.duc_ca_hien_tai_sao_luu_t204);
