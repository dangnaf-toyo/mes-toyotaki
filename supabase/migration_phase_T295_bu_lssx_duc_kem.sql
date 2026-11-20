-- T295 (20/11/2026) — CHỈ DỮ LIỆU PROD.
-- Bù dòng duc_lich_su_san_xuat cho máy Đúc Kẽm (may_tt 'Kẽm%') những ca ĐÃ KẾT
-- mà trưởng ca không nạp máy Kẽm vào ca → tem Kanban đã quét không được chốt,
-- báo cáo tuần/ca thiếu sản lượng. Lấy số đúng từ duc_tem (ngay_gio_ghi_nhan),
-- KH ca lấy từ KHSX tuần đã duyệt; cộng thêm vào duc_bao_cao_ca tương ứng.
-- Phạm vi: 09/11 – 19/11/2026, chỉ phương án "2 ca 12h". Chạy lại không nhân đôi
-- (chỉ chèn khi chưa có dòng cùng ngày/ca/máy/mã SP).
begin;

create temp table t295_bu on commit drop as
with tem as (
  select t.may_tt, t.ma_sp, max(t.ten_sp) ten_sp,
         ((t.ngay_gio_ghi_nhan at time zone 'Asia/Ho_Chi_Minh') - interval '6 hours')::date ngay,
         case when extract(hour from t.ngay_gio_ghi_nhan at time zone 'Asia/Ho_Chi_Minh') between 6 and 17
              then 'Ca ngày' else 'Ca đêm' end ca,
         sum(t.so_luong_tt) tt
  from public.duc_tem t
  where t.may_tt ilike 'kẽm%' and t.ngay_gio_ghi_nhan is not null
    and t.ngay_gio_ghi_nhan >= timestamptz '2026-11-09 06:00+07'
    and t.ngay_gio_ghi_nhan <  timestamptz '2026-11-20 06:00+07'
  group by 1, 2, 4, 5
)
select tem.*, b.phuong_an_ca,
       coalesce((select (array[p.t2,p.t3,p.t4,p.t5,p.t6,p.t7])[extract(isodow from tem.ngay)::int]
                 from public.duc_khsx_tuan_plan p
                 where p.ma_may = tem.may_tt and p.ma_sp = tem.ma_sp
                   and p.tuan_bat_dau = tem.ngay - (extract(isodow from tem.ngay)::int - 1)
                 limit 1), 0) kh
from tem
join public.duc_bao_cao_ca b on b.ngay = tem.ngay and b.ca = tem.ca and b.phuong_an_ca = '2 ca 12h'
where not exists (select 1 from public.duc_lich_su_san_xuat l
                  where l.ngay = tem.ngay and l.ca = tem.ca and l.ma_may = tem.may_tt and l.ma_sp = tem.ma_sp);

insert into public.duc_lich_su_san_xuat (ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, kh_ca, tt_ca, so_luong_ng, thoi_diem_ghi)
select ngay, ca, phuong_an_ca,
       'W' || to_char(ngay, 'IW') || '_' || to_char(ngay, 'IYYY'),
       may_tt, ma_sp, ten_sp, kh, tt, 0, now()
from t295_bu;

update public.duc_bao_cao_ca b
set tong_kh_ca = b.tong_kh_ca + x.kh,
    tong_tt_ca = b.tong_tt_ca + x.tt,
    so_may_co_kh = b.so_may_co_kh + x.n_kh,
    so_may_hoan_thanh_kh = b.so_may_hoan_thanh_kh + x.n_ht,
    ty_le_hoan_thanh_ca = case when b.tong_kh_ca + x.kh > 0
                               then (b.tong_tt_ca + x.tt)::numeric / (b.tong_kh_ca + x.kh) else 0 end,
    ghi_chu = concat_ws(' | ', nullif(b.ghi_chu, ''), 'T295 bù Đúc Kẽm +' || x.tt)
from (select ngay, ca, sum(kh) kh, sum(tt) tt,
             count(*) filter (where kh > 0) n_kh,
             count(*) filter (where kh > 0 and tt >= kh) n_ht
      from t295_bu group by 1, 2) x
where b.ngay = x.ngay and b.ca = x.ca;

select ngay, ca, may_tt, ma_sp, kh, tt from t295_bu order by ngay, ca;
commit;
