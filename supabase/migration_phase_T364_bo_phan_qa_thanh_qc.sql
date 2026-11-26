-- T364 — Bỏ bộ phận 'QA', thay bằng 'QC'.
-- user_roles.bo_phan_phu_trach: đổi 'QA' → 'QC' + cập nhật check constraint.
-- nvl_pdc_ds_bo_phan: danh sách bộ phận phiếu cấp NVL dùng 'QC'.
-- duc_td_nhom_ten: nhóm duyệt điểm thay đổi 'qa' hiển thị "QC" (giữ khoá 'qa').

alter table user_roles drop constraint if exists user_roles_bo_phan_phu_trach_check;

update user_roles
   set bo_phan_phu_trach = array_replace(bo_phan_phu_trach, 'QA', 'QC')
 where 'QA' = any(bo_phan_phu_trach);

alter table user_roles add constraint user_roles_bo_phan_phu_trach_check check (
  bo_phan_phu_trach is null
  or bo_phan_phu_trach <@ array['Đúc', 'Bavia', 'Gia Công', 'Cắt viền', 'Đánh bóng Kẽm', 'Sơn', 'OQC', 'Kỹ thuật', 'QC', 'Thiết bị']::text[]
);

update nvl_phieu_cap set bo_phan = 'QC' where bo_phan = 'QA';
update nvl_giao_dich set bo_phan_nhan = 'QC' where bo_phan_nhan = 'QA';

create or replace function public.nvl_pdc_ds_bo_phan()
 returns text[] language sql immutable as $$
  select array['Đúc', 'Bavia', 'Gia Công', 'Cắt viền', 'Đánh bóng Kẽm', 'Sơn', 'OQC', 'Kỹ thuật', 'QC', 'Thiết bị'];
$$;

create or replace function public.duc_td_nhom_ten(p_nhom text)
 returns text language sql immutable as $$
  select case p_nhom when 'ky_thuat' then 'Kỹ thuật' when 'thiet_bi' then 'Thiết bị' when 'to_truong_khuon' then 'Tổ trưởng khuôn'
                     when 'qlbp_duc' then 'QLBP Đúc' when 'qa' then 'QC' else coalesce(p_nhom, '') end;
$$;
