-- T265 (15/11/2026): Danh mục lỗi chung toàn nhà máy.
-- Mã lỗi = 1 chữ nhóm + 2 số: D đúc · B bavia/hoàn thiện · G gia công · S sơn ·
-- T thao tác/vận chuyển/bảo quản · Z khác. Tên hiển thị = "<mã> <tên>", vd "D01 Rỗ khí".
-- Nguồn duy nhất: quality_defect_catalog (thêm cột ma_loi, mo_ta). Cột processes
-- ghi công đoạn dùng: DUC, DUC_KEM, BAVIA, GIA_CONG, SON, OQC, OQC_SON, IQC, IPQC.
-- Mã cũ của bảng (ro_khi, iqc_…, son_…) GIỮ NGUYÊN để phiếu OQC/IQC cũ vẫn khớp;
-- lỗi trùng nghĩa giữ hàng nhưng bỏ hết công đoạn (processes = '{}') → không hiện để chọn,
-- phiếu cũ vẫn hiện tên chuẩn.
-- Số liệu cũ lưu bằng chữ (Bavia, Gia công, Đúc kẽm, Đánh bóng) đổi sang tên chuẩn theo
-- bảng loi_anh_xa; giá trị cũ chép vào t265_loi_sao_luu.
-- Hàm bavia_ng / gc_ng_nhieu / bavia_ng_theo_tem nhận thêm "Z99 Khác".
-- Chạy trên PROD (fgghikpzcxjqzahfiiil) và STAGING (jcjbleugnclzsghfpmvk).

begin;

-- 1. Cột mới
alter table public.quality_defect_catalog add column if not exists ma_loi text;
alter table public.quality_defect_catalog add column if not exists mo_ta text;
create index if not exists quality_defect_catalog_ma_loi_idx on public.quality_defect_catalog(ma_loi);

-- 2. Sao lưu
create table if not exists public.t265_loi_sao_luu(
  id bigserial primary key, bang text not null, khoa text not null,
  gia_tri_cu jsonb, gia_tri_moi text, luc timestamptz not null default now());
alter table public.t265_loi_sao_luu enable row level security;
revoke all on public.t265_loi_sao_luu from public, anon, authenticated;

insert into public.t265_loi_sao_luu(bang, khoa, gia_tri_cu)
select 'quality_defect_catalog', code, to_jsonb(c) from public.quality_defect_catalog c
where not exists (select 1 from public.t265_loi_sao_luu s where s.bang = 'quality_defect_catalog' and s.khoa = c.code);

-- 3. Danh mục chuẩn: (code, ma_loi, label, nhóm OQC, công đoạn, thứ tự, mô tả)
create temp table t265_dm(code text, ma text, label text, grp text, cd text[], so int, mo_ta text) on commit drop;
insert into t265_dm values
 ('ro_khi','D01','D01 Rỗ khí','NG ngoại quan','{DUC,DUC_KEM,BAVIA,GIA_CONG,OQC,IQC,IPQC,OQC_SON}',101,'Lỗ khí trên bề mặt hoặc lộ ra sau gia công'),
 ('D02','D02','D02 Thiếu nhôm','NG ngoại quan','{DUC,DUC_KEM,BAVIA,GIA_CONG,OQC,IPQC}',102,'Điền khuôn không đầy (kẽm: thiếu kẽm)'),
 ('D03','D03','D03 Thiếu nhôm cạnh răng','NG ngoại quan','{BAVIA,GIA_CONG,OQC}',103,'Thiếu nhôm ở răng / cạnh mỏng'),
 ('nhan','D04','D04 Nhăn','NG ngoại quan','{DUC,BAVIA,GIA_CONG,OQC,IPQC}',104,'Vết nhăn, vân dòng chảy'),
 ('bong_nhom','D05','D05 Bong nhôm','NG ngoại quan','{BAVIA,GIA_CONG,OQC,IPQC}',105,'Lớp nhôm bong tróc'),
 ('D06','D06','D06 Dính nhôm','NG ngoại quan','{BAVIA,GIA_CONG,OQC}',106,'Nhôm bám khuôn để lại vết'),
 ('nut','D07','D07 Nứt','NG ngoại quan','{DUC,DUC_KEM,BAVIA,GIA_CONG,OQC,IQC,IPQC}',107,'Nứt, rạn'),
 ('D08','D08','D08 Phồng','NG ngoại quan','{DUC,DUC_KEM,BAVIA,OQC}',108,'Phồng rộp bề mặt (nhôm / kẽm)'),
 ('D09','D09','D09 Lõm pin','NG ngoại quan','{BAVIA,GIA_CONG,OQC}',109,'Lõm tại vị trí pin đẩy'),
 ('iqc_9169e9fb762f','D10','D10 Lồi, lõm bề mặt','NG ngoại quan','{BAVIA,GIA_CONG,OQC,IQC}',110,'Bề mặt lồi, lõm, co ngót'),
 ('D11','D11','D11 Bã trầu','NG ngoại quan','{BAVIA,OQC}',111,null),
 ('D12','D12','D12 Mỏng cuống','NG ngoại quan','{BAVIA}',112,null),
 ('di_vat','D13','D13 Tạp chất, dị vật','NG ngoại quan','{BAVIA,GIA_CONG,OQC,IQC,IPQC}',113,'Tạp chất lẫn trong kim loại'),
 ('cong_venh','D14','D14 Biến dạng (cong, vênh, méo)','NG ngoại quan','{DUC,BAVIA,GIA_CONG,OQC,IQC,IPQC}',114,null),
 ('D15','D15','D15 Mờ lot mark','NG ngoại quan','{BAVIA,GIA_CONG,OQC}',115,'Ký hiệu lô mờ, không đọc được'),
 ('D16','D16','D16 Bắn nhôm','NG ngoại quan','{BAVIA,OQC}',116,'Nhôm bắn bám lên sản phẩm'),
 ('D17','D17','D17 Nhẹ cân','NG ngoại quan','{DUC_KEM}',117,'Khối lượng dưới tiêu chuẩn'),
 ('D18','D18','D18 Sai kích thước đúc','NG kích thước','{DUC,BAVIA}',118,'Kích thước phôi đúc ngoài dung sai (trước gia công)'),
 ('bavia','B01','B01 Sót bavia','NG ngoại quan','{BAVIA,GIA_CONG,OQC,IPQC}',201,'Còn bavia chưa cắt / mài sạch'),
 ('B02','B02','B02 Bẻ lõm sâu','NG ngoại quan','{BAVIA,OQC}',202,'Bẻ cuống quá sâu vào sản phẩm'),
 ('sut','B03','B03 Sứt, mẻ','NG ngoại quan','{DUC_KEM,BAVIA,GIA_CONG,OQC,OQC_SON,IQC,IPQC}',203,'Sứt cạnh, mẻ góc'),
 ('dap_lech','B04','B04 Dập lệch','NG ngoại quan','{BAVIA,OQC,IPQC}',204,null),
 ('ng_kich_thuoc','G01','G01 Sai kích thước gia công','NG kích thước','{GIA_CONG,OQC,IQC,IPQC}',301,'Kích thước sau gia công ngoài dung sai'),
 ('loi_ren','G02','G02 Lỗi ren','NG kích thước','{GIA_CONG,OQC,IQC,IPQC}',302,'Ren chật, rộng, nông, sâu, thiếu, thủng'),
 ('ga_lech','G03','G03 Gá lệch, lệch tâm','NG ngoại quan','{GIA_CONG,OQC,IPQC}',303,null),
 ('vat_c','G04','G04 Cắt vát, vát C','NG ngoại quan','{GIA_CONG,OQC,IQC,IPQC}',304,null),
 ('khong_gia_cong','G05','G05 Thiếu nguyên công','NG ngoại quan','{GIA_CONG,OQC,IPQC}',305,'Bỏ sót nguyên công, gia công không hết'),
 ('chat_jig','G06','G06 Chật JIG, không lọt JIG','NG kích thước','{GIA_CONG,OQC,IQC,IPQC}',306,null),
 ('G07','G07','G07 Sót phoi','NG ngoại quan','{GIA_CONG,OQC}',307,null),
 ('G08','G08','G08 Độ nhám không đạt','NG ngoại quan','{GIA_CONG,OQC}',308,null),
 ('G09','G09','G09 Tụt chốt','NG ngoại quan','{GIA_CONG,OQC}',309,null),
 ('son_ro_son','S01','S01 Rỗ sơn','NG ngoại quan','{SON,OQC_SON}',401,null),
 ('son_mun_son','S02','S02 Mụn sơn','NG ngoại quan','{SON,OQC_SON}',402,null),
 ('son_thieu_son','S03','S03 Thiếu sơn','NG ngoại quan','{SON,OQC_SON}',403,null),
 ('son_san_son','S04','S04 Sần sơn','NG ngoại quan','{SON,OQC_SON}',404,null),
 ('son_nhan_son','S05','S05 Nhăn sơn','NG ngoại quan','{SON,OQC_SON}',405,null),
 ('son_bavia_son','S06','S06 Bavia sơn','NG ngoại quan','{SON,OQC_SON}',406,null),
 ('son_day_mong_son','S07','S07 Dày, mỏng sơn','NG ngoại quan','{SON,OQC_SON}',407,null),
 ('son_khac_mau','S08','S08 Khác màu','NG ngoại quan','{SON,OQC_SON,IQC}',408,'Màu lệch mẫu'),
 ('son_tap_chat','S09','S09 Tạp chất trong sơn','NG ngoại quan','{SON,OQC_SON}',409,null),
 ('son_mop_meo_chan','S10','S10 Móp méo chân','NG ngoại quan','{SON,OQC_SON}',410,null),
 ('son_venh_chan','S11','S11 Vênh chân','NG ngoại quan','{SON,OQC_SON}',411,null),
 ('son_lom','S12','S12 Lõm sơn','NG ngoại quan','{SON,OQC_SON}',412,'Lõm từ phôi đúc thì chọn D10'),
 ('va_dap','T01','T01 Va đập','NG ngoại quan','{DUC,DUC_KEM,BAVIA,GIA_CONG,SON,OQC,OQC_SON,IQC,IPQC}',501,'Móp do va chạm khi cầm, xếp, chuyển'),
 ('xuoc','T02','T02 Xước bề mặt','NG ngoại quan','{DUC,DUC_KEM,BAVIA,GIA_CONG,SON,OQC,OQC_SON,IQC,IPQC}',502,null),
 ('T03','T03','T03 Sản phẩm rơi','NG ngoại quan','{DUC,DUC_KEM,BAVIA,GIA_CONG,SON,OQC,OQC_SON}',503,null),
 ('iqc_331ad79eee0d','T04','T04 Dính dầu, bẩn','NG ngoại quan','{DUC,DUC_KEM,BAVIA,GIA_CONG,SON,OQC,OQC_SON,IQC}',504,null),
 ('iqc_78760804ecad','T05','T05 Mốc, ố, rỉ, oxi hóa','NG ngoại quan','{DUC_KEM,BAVIA,GIA_CONG,SON,OQC,OQC_SON,IQC}',505,'Do bảo quản'),
 ('Z01','Z01','Z01 Hủy để kiểm tra','NG khác','{BAVIA,GIA_CONG,OQC}',901,'Cắt / gia công mẫu để kiểm (vd. kiểm rỗ khí) — không tính tỷ lệ lỗi'),
 ('Z02','Z02','Z02 Hàng chỉnh máy','NG khác','{GIA_CONG}',902,'Hàng chạy thử khi chỉnh máy / thay dao — không tính tỷ lệ lỗi'),
 ('iqc_06c1f85a451e','Z99','Z99 Khác','NG ngoại quan','{DUC,DUC_KEM,BAVIA,GIA_CONG,SON,OQC,OQC_SON,IQC}',999,'Bắt buộc ghi rõ; lặp ≥ 3 lần/tháng thì tạo mã mới'),
 -- Trùng nghĩa: giữ hàng cho phiếu cũ, bỏ công đoạn
 ('iqc_9ca41bd50229','T02','T02 Xước bề mặt','NG ngoại quan','{}',502,'Đã gộp vào xuoc'),
 ('iqc_d60b1f2d2c45','S08','S08 Khác màu','NG ngoại quan','{}',408,'Đã gộp vào son_khac_mau'),
 ('iqc_7f55011aff5e','G01','G01 Sai kích thước gia công','NG ngoại quan','{}',301,'Đã gộp vào ng_kich_thuoc'),
 ('son_sut_me','B03','B03 Sứt, mẻ','NG ngoại quan','{}',203,'Đã gộp vào sut'),
 ('son_dinh_dau','T04','T04 Dính dầu, bẩn','NG ngoại quan','{}',504,'Đã gộp vào iqc_331ad79eee0d');

insert into public.quality_defect_catalog(code, label, defect_group, processes, is_active, sort_order, ma_loi, mo_ta, updated_at)
select code, label, grp, cd, true, so, ma, mo_ta, now() from t265_dm
on conflict (code) do update set label = excluded.label, defect_group = excluded.defect_group,
  processes = excluded.processes, is_active = true, sort_order = excluded.sort_order,
  ma_loi = excluded.ma_loi, mo_ta = excluded.mo_ta, updated_at = now();

-- 4. Bảng đối chiếu tên cũ (lưu bằng chữ) → mã chuẩn
create table if not exists public.loi_anh_xa(
  nguon text not null, ten_cu text not null, ma_loi text not null,
  primary key (nguon, ten_cu));
alter table public.loi_anh_xa enable row level security;
drop policy if exists "loi anh xa doc" on public.loi_anh_xa;
create policy "loi anh xa doc" on public.loi_anh_xa for select to authenticated using (true);
revoke insert, update, delete on public.loi_anh_xa from anon, authenticated;

insert into public.loi_anh_xa(nguon, ten_cu, ma_loi) values
 ('BAVIA','rỗ khí','D01'),('BAVIA','thiếu nhôm','D02'),('BAVIA','thiếu nhôm bề mặt','D02'),('BAVIA','lõm pin','D09'),
 ('BAVIA','biến dạng','D14'),('BAVIA','dính dầu','T04'),('BAVIA','nhăn','D04'),('BAVIA','bắn nhôm','D16'),('BAVIA','bẩn nhôm','D16'),
 ('BAVIA','va đập','T01'),('BAVIA','rạn nứt','D07'),('BAVIA','nứt','D07'),('BAVIA','sản phẩm rơi','T03'),('BAVIA','rơi','T03'),
 ('BAVIA','ng kích thước','D18'),('BAVIA','thiếu nhôm cạnh răng','D03'),('BAVIA','mờ lot mark','D15'),('BAVIA','mờ lotmax','D15'),
 ('BAVIA','bã trầu','D11'),('BAVIA','ba trấu','D11'),('BAVIA','bẻ lõm sâu','B02'),('BAVIA','bề lõm sâu','B02'),
 ('BAVIA','dính nhôm','D06'),('BAVIA','bong nhôm','D05'),('BAVIA','tạp chất','D13'),('BAVIA','xước bề mặt','T02'),
 ('BAVIA','mỏng cuống','D12'),('BAVIA','gia công kiểm tra rỗ khí','Z01'),('BAVIA','phồng al','D08'),('BAVIA','phồng nhôm','D08'),
 ('BAVIA','lồi, lõm bề mặt','D10'),('BAVIA','lỗi, lõm','D10'),('BAVIA','khác','Z99'),
 ('GIA_CONG','ng kích thước','G01'),('GIA_CONG','kích thước gc','G01'),('GIA_CONG','rỗ khí (lộ sau gia công)','D01'),('GIA_CONG','rỗ khí','D01'),
 ('GIA_CONG','xước / va đập','T02'),('GIA_CONG','ba via / sót phoi','B01'),('GIA_CONG','thiếu / sai nguyên công','G05'),
 ('GIA_CONG','ren hỏng','G02'),('GIA_CONG','lệch gá / lệch tâm','G03'),('GIA_CONG','gá lệch','G03'),('GIA_CONG','độ nhám không đạt','G08'),
 ('GIA_CONG','biến dạng','D14'),('GIA_CONG','cắt vát','G04'),('GIA_CONG','chỉnh máy','Z02'),
 ('GIA_CONG','lỗi đúc phát hiện tại gia công','Z99'),('GIA_CONG','khác','Z99'),
 ('DUC_KEM','phồng kẽm','D08'),('DUC_KEM','nứt kẽm','D07'),('DUC_KEM','rỗ khí','D01'),('DUC_KEM','nhẹ cân','D17'),
 ('DUC_KEM','thiếu kẽm cửa liệu','D02'),('DUC_KEM','mốc-oxi hóa','T05'),('DUC_KEM','sứt vatc','B03'),('DUC_KEM','khác','Z99')
on conflict (nguon, ten_cu) do update set ma_loi = excluded.ma_loi;

-- 5. Đổi tên trong số liệu cũ (lưu giá trị cũ trước)
create temp table t265_ten on commit drop as
select a.nguon, a.ten_cu, c.label ten_moi
from public.loi_anh_xa a
join public.quality_defect_catalog c on c.ma_loi = a.ma_loi and c.processes <> '{}';

-- bavia_ng_qua_khu (Excel quá khứ Bavia; loai_ng_goc giữ tên gốc)
insert into public.t265_loi_sao_luu(bang, khoa, gia_tri_cu, gia_tri_moi)
select 'bavia_ng_qua_khu', q.id::text, to_jsonb(q.loai_ng), t.ten_moi
from public.bavia_ng_qua_khu q join t265_ten t on t.nguon = 'BAVIA' and t.ten_cu = lower(trim(q.loai_ng))
where q.loai_ng is distinct from t.ten_moi;
update public.bavia_ng_qua_khu q set loai_ng = t.ten_moi
from t265_ten t where t.nguon = 'BAVIA' and t.ten_cu = lower(trim(q.loai_ng)) and q.loai_ng is distinct from t.ten_moi;

-- cd_ng_khai_bao (Bavia, Gia công, Đánh bóng kẽm)
insert into public.t265_loi_sao_luu(bang, khoa, gia_tri_cu, gia_tri_moi)
select 'cd_ng_khai_bao', g.id::text, to_jsonb(g.loai_ng), t.ten_moi
from public.cd_ng_khai_bao g join t265_ten t
  on t.nguon = case when g.cong_doan = 'Bavia' then 'BAVIA' when g.cong_doan ilike '%kẽm%' then 'DUC_KEM' else 'GIA_CONG' end
 and t.ten_cu = lower(trim(g.loai_ng))
where g.loai_ng is distinct from t.ten_moi;
update public.cd_ng_khai_bao g set loai_ng = t.ten_moi
from t265_ten t
where t.nguon = case when g.cong_doan = 'Bavia' then 'BAVIA' when g.cong_doan ilike '%kẽm%' then 'DUC_KEM' else 'GIA_CONG' end
  and t.ten_cu = lower(trim(g.loai_ng)) and g.loai_ng is distinct from t.ten_moi;

-- duc_kanban_ng_log (Kanban Đúc kẽm)
insert into public.t265_loi_sao_luu(bang, khoa, gia_tri_cu, gia_tri_moi)
select 'duc_kanban_ng_log', k.id::text, to_jsonb(k.loai_ng), t.ten_moi
from public.duc_kanban_ng_log k join t265_ten t on t.nguon = 'DUC_KEM' and t.ten_cu = lower(trim(k.loai_ng))
where k.loai_ng is distinct from t.ten_moi;
update public.duc_kanban_ng_log k set loai_ng = t.ten_moi
from t265_ten t where t.nguon = 'DUC_KEM' and t.ten_cu = lower(trim(k.loai_ng)) and k.loai_ng is distinct from t.ten_moi;

-- 6. Hàm kiểm "Khác" nhận thêm "Z99 Khác" (sửa tại chỗ bản đang chạy, giữ nguyên phần còn lại)
do $$
declare r record; d text; d2 text;
begin
  for r in select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('bavia_ng', 'gc_ng_nhieu', 'bavia_ng_theo_tem') loop
    d := pg_get_functiondef(r.oid);
    d2 := replace(d, 'trim(p_loai) = ''Khác''', 'trim(p_loai) in (''Khác'', ''Z99 Khác'')');
    d2 := replace(d2, 'trim(r->>''loai'') = ''Khác''', 'trim(r->>''loai'') in (''Khác'', ''Z99 Khác'')');
    d2 := replace(d2, 'coalesce(nullif(trim(g.loai_ng), ''''), ''Khác'')', 'coalesce(nullif(trim(g.loai_ng), ''''), ''Z99 Khác'')');
    if d2 <> d then execute d2; raise notice 'T265: đã sửa %', r.proname;
    else raise notice 'T265: % không có chỗ cần sửa', r.proname; end if;
  end loop;
end$$;

commit;

-- Kiểm tra sau khi chạy:
-- select ma_loi, label, processes from quality_defect_catalog where processes <> '{}' order by sort_order;  -- 51 dòng
-- select bang, count(*) from t265_loi_sao_luu group by 1;
