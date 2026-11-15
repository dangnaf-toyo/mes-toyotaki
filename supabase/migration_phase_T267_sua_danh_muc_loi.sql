-- T267: Sửa danh mục lỗi chung (sau T265)
--  • Bẻ lõm sâu B02 → D19, Dập lệch B04 → D20 (lỗi của bộ phận Đúc)
--  • Gộp D03 Thiếu nhôm cạnh răng vào D02 Thiếu nhôm (số liệu cũ đổi tên, giá trị cũ lưu t265_loi_sao_luu)
--  • Bỏ D16 Bắn nhôm, Z01 Hủy để kiểm tra (không có số liệu dùng)
begin;

-- 1. Chuyển nhóm B → D (giữ code để phiếu OQC cũ vẫn khớp)
update public.quality_defect_catalog set ma_loi = 'D19', label = 'D19 Bẻ lõm sâu', sort_order = 119, updated_at = now()
 where ma_loi = 'B02';
update public.quality_defect_catalog set ma_loi = 'D20', label = 'D20 Dập lệch', sort_order = 120, updated_at = now()
 where ma_loi = 'B04';

-- 2. Gộp D03 → D02: D02 nhận thêm công đoạn của D03; hàng D03 giữ cho phiếu cũ, bỏ công đoạn
update public.quality_defect_catalog d set processes = (
  select array(select distinct unnest(d.processes || c.processes)) from public.quality_defect_catalog c where c.code = 'D03'),
  updated_at = now()
 where d.code = 'D02';
update public.quality_defect_catalog set ma_loi = 'D02', label = 'D02 Thiếu nhôm', processes = '{}',
  mo_ta = 'Đã gộp vào D02', updated_at = now()
 where code = 'D03';

-- 3. Bỏ D16, Z01
update public.quality_defect_catalog set is_active = false, processes = '{}', updated_at = now()
 where ma_loi in ('D16', 'Z01');

-- 4. Bảng đối chiếu tên cũ
update public.loi_anh_xa set ma_loi = 'D02' where ma_loi = 'D03';
update public.loi_anh_xa set ma_loi = 'D19' where ma_loi = 'B02';
update public.loi_anh_xa set ma_loi = 'D20' where ma_loi = 'B04';
delete from public.loi_anh_xa where ma_loi in ('D16', 'Z01');

-- 5. Đổi tên trong số liệu cũ (lưu giá trị cũ trước)
create temp table t267_ten(cu text, moi text) on commit drop;
insert into t267_ten values ('D03 Thiếu nhôm cạnh răng', 'D02 Thiếu nhôm'),
  ('B02 Bẻ lõm sâu', 'D19 Bẻ lõm sâu'), ('B04 Dập lệch', 'D20 Dập lệch');

insert into public.t265_loi_sao_luu(bang, khoa, gia_tri_cu, gia_tri_moi)
select 'T267 bavia_ng_qua_khu', q.id::text, to_jsonb(q.loai_ng), t.moi
from public.bavia_ng_qua_khu q join t267_ten t on t.cu = q.loai_ng;
update public.bavia_ng_qua_khu q set loai_ng = t.moi from t267_ten t where t.cu = q.loai_ng;

insert into public.t265_loi_sao_luu(bang, khoa, gia_tri_cu, gia_tri_moi)
select 'T267 cd_ng_khai_bao', g.id::text, to_jsonb(g.loai_ng), t.moi
from public.cd_ng_khai_bao g join t267_ten t on t.cu = g.loai_ng;
update public.cd_ng_khai_bao g set loai_ng = t.moi from t267_ten t where t.cu = g.loai_ng;

insert into public.t265_loi_sao_luu(bang, khoa, gia_tri_cu, gia_tri_moi)
select 'T267 duc_kanban_ng_log', k.id::text, to_jsonb(k.loai_ng), t.moi
from public.duc_kanban_ng_log k join t267_ten t on t.cu = k.loai_ng;
update public.duc_kanban_ng_log k set loai_ng = t.moi from t267_ten t where t.cu = k.loai_ng;

commit;

-- Kiểm tra:
-- select ma_loi, label, processes from quality_defect_catalog where processes <> '{}' and is_active order by sort_order; -- 48 dòng
