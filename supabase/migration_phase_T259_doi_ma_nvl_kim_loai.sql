-- T259: Đổi 6 mã NVL kim loại cũ sang mẫu N-LLL-QQ-STT (Quy tắc đặt tên T257)
--   ADC12-CHT → K-NHN-12-001   ADC12-DAK → K-NHN-12-002   ADC6-CHT → K-NHN-06-001
--   EZDA3-HDT → K-KEN-A3-001   EZDA3-MET → K-KEN-A3-002   HD2-HDT  → K-NHN-S1-001
-- Đổi ở mọi bảng đang lưu mã (danh mục, tồn đầu kỳ, kế hoạch, giao dịch, tem NVL, cài đặt,
-- BOM, sản phẩm, tem đúc, nhật ký chuyển công đoạn). Tắt trigger trong giao dịch (chỉ đổi tên,
-- không đổi số liệu → không cần tính lại tồn / nhật ký tem). Bảng sao lưu *_bk_* giữ nguyên.
begin;
set local session_replication_role = replica;

create temp table _map (cu text primary key, moi text not null) on commit drop;
insert into _map values
  ('ADC12-CHT','K-NHN-12-001'), ('ADC12-DAK','K-NHN-12-002'), ('ADC6-CHT','K-NHN-06-001'),
  ('EZDA3-HDT','K-KEN-A3-001'), ('EZDA3-MET','K-KEN-A3-002'), ('HD2-HDT','K-NHN-S1-001');

update public.nvl_materials     x set ma_nvl = m.moi from _map m where x.ma_nvl = m.cu;
update public.nvl_ton_dau_ky    x set ma_nvl = m.moi from _map m where x.ma_nvl = m.cu;
update public.nvl_ke_hoach_ngay x set ma_nvl = m.moi from _map m where x.ma_nvl = m.cu;
update public.nvl_giao_dich     x set ma_nvl = m.moi from _map m where x.ma_nvl = m.cu;
update public.nvl_tem           x set ma_nvl = m.moi from _map m where x.ma_nvl = m.cu;
update public.nvl_cai_dat       x set ma_nvl = m.moi from _map m where x.ma_nvl = m.cu;
update public.iqc_nvl_phan_loai x set ma_nvl = m.moi from _map m where x.ma_nvl = m.cu;
update public.iqc_lots          x set ma_nvl = m.moi from _map m where x.ma_nvl = m.cu;
update public.ipqc_btk          x set ma_nvl = m.moi from _map m where x.ma_nvl = m.cu;
update public.bom_versions      x set ma_nhom = m.moi from _map m where x.ma_nhom = m.cu;
update public.master_products   x set nguyen_lieu = m.moi from _map m where x.nguyen_lieu = m.cu;
update public.duc_tem           x set nguyen_lieu = m.moi from _map m where x.nguyen_lieu = m.cu;
update public.cd_chuyen_cong_doan_log x set nguyen_lieu = m.moi from _map m where x.nguyen_lieu = m.cu;

commit;

-- View trọng lượng SP: nhận kẽm theo mã mới K-KEN-… (giữ EZDA% cho dữ liệu cũ nếu còn)
create or replace view public.v_sp_trong_luong_hien_tai
with (security_invoker = true) as
select distinct on (t.ma_sp)
  t.ma_sp, p.ten_sp, p.ten_khach_hang, p.nguyen_lieu,
  case when p.nguyen_lieu ilike 'K-KEN-%' or p.nguyen_lieu ilike 'EZDA%' then 'kem'
       when p.nguyen_lieu is null then null else 'nhom' end as loai_kim_loai,
  t.ngay_can, t.trong_luong_kg,
  round(t.trong_luong_kg * 1.03, 5) as dinh_muc_kg,
  (select count(*) from public.sp_trong_luong x where x.ma_sp = t.ma_sp) as so_lan_can
from public.sp_trong_luong t
join public.master_products p on p.ma_sp = t.ma_sp
order by t.ma_sp, t.ngay_can desc;
revoke all on public.v_sp_trong_luong_hien_tai from anon;
grant select on public.v_sp_trong_luong_hien_tai to authenticated;
