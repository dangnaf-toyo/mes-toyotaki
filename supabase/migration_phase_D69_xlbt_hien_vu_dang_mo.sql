-- ============================================================================
-- D69 — Dashboard tổ khuôn (T103): luôn hiện sự cố A2/B1/F1 ĐANG MỞ bất kể mốc
-- xlbt_tu_thoi_diem (user 2026-10-13: SC-DC8-1013-0712 phát sinh 07:12, trước
-- mốc bật 10:18, máy vẫn dừng nhưng không hiện).
--
--   - mo: bỏ điều kiện open_gio_phat_sinh >= mốc.
--   - dong: ngoài sự cố từ mốc, lấy thêm các dòng log của sự cố đang mở (phần
--     đã đóng lúc kết ca của sự cố vắt ca) và sự cố ĐÃ CÓ phiếu tổ khuôn — để
--     vụ cũ đang được tổ khuôn xử lý không biến mất khi trưởng ca đóng sự cố.
--   - Vụ cũ đã đóng mà tổ khuôn chưa nhận thì vẫn không hiện (như T103).
--
-- Chỉ thay hàm duc_khuon_xlbt_danh_sach. Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

create or replace function duc_khuon_xlbt_danh_sach(p_lich_su boolean default false, p_tu date default null, p_den date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tu timestamptz;
  v_out jsonb;
begin
  select (gia_tri #>> '{}')::timestamptz into v_tu from duc_cau_hinh where khoa = 'xlbt_tu_thoi_diem';
  v_tu := coalesce(v_tu, now());

  with mo as (
    select distinct on (open_id_su_co) open_id_su_co as id_su_co, ma_may, ma_sp, ten_sp, so_khuon, open_loai_su_co as loai_su_co,
           open_gio_phat_sinh as gio_phat_sinh, open_van_de as van_de, open_noi_dung_xu_ly as noi_dung_sx,
           open_dam_nhiem as dam_nhiem_sx, ngay, ca
    from duc_ca_hien_tai
    where open_id_su_co is not null and left(coalesce(open_loai_su_co, ''), 2) in ('A2', 'B1', 'F1')
    order by open_id_su_co, open_gio_phat_sinh
  ),
  dong as (
    select id_su_co,
           (array_agg(ma_may order by gio_phat_sinh))[1] ma_may,
           (array_agg(ma_sp order by gio_phat_sinh))[1] ma_sp,
           (array_agg(ten_sp order by gio_phat_sinh))[1] ten_sp,
           (array_agg(so_khuon order by gio_phat_sinh))[1] so_khuon,
           (array_agg(loai_su_co order by gio_phat_sinh))[1] loai_su_co,
           min(gio_phat_sinh) gio_phat_sinh,
           max(gio_tro_lai) gio_tro_lai,
           sum(coalesce(thoi_gian_dung_phut, 0)) phut_dung,
           (array_agg(van_de order by gio_phat_sinh))[1] van_de,
           (array_agg(noi_dung_xu_ly order by gio_phat_sinh desc))[1] noi_dung_sx,
           (array_agg(dam_nhiem order by gio_phat_sinh desc))[1] dam_nhiem_sx,
           (array_agg(ngay order by gio_phat_sinh))[1] ngay,
           (array_agg(ca order by gio_phat_sinh))[1] ca
    from duc_su_co_log
    where id_su_co is not null and left(coalesce(loai_su_co, ''), 2) in ('A2', 'B1', 'F1')
      and (gio_phat_sinh >= v_tu
           or id_su_co in (select id_su_co from mo)
           or id_su_co in (select id_su_co from duc_khuon_xu_ly_bat_thuong))
    group by id_su_co
  ),
  tat_ca as (
    select coalesce(m.id_su_co, d.id_su_co) id_su_co,
           coalesce(d.ma_may, m.ma_may) ma_may, coalesce(d.ma_sp, m.ma_sp) ma_sp, coalesce(d.ten_sp, m.ten_sp) ten_sp,
           coalesce(m.so_khuon, d.so_khuon) so_khuon, coalesce(d.loai_su_co, m.loai_su_co) loai_su_co,
           least(d.gio_phat_sinh, m.gio_phat_sinh) gio_phat_sinh,
           case when m.id_su_co is null then d.gio_tro_lai end gio_tro_lai,
           (m.id_su_co is not null) dang_dung_may,
           coalesce(d.phut_dung, 0) + case when m.id_su_co is not null
             then round(extract(epoch from (now() - m.gio_phat_sinh)) / 60) else 0 end phut_dung,
           coalesce(d.van_de, m.van_de) van_de,
           coalesce(m.noi_dung_sx, d.noi_dung_sx) noi_dung_sx,
           coalesce(m.dam_nhiem_sx, d.dam_nhiem_sx) dam_nhiem_sx,
           coalesce(d.ngay, m.ngay) ngay, coalesce(d.ca, m.ca) ca
    from mo m full join dong d on d.id_su_co = m.id_su_co
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id_su_co', t.id_su_co, 'ma_may', t.ma_may, 'ma_sp', t.ma_sp, 'ten_sp', t.ten_sp,
           'so_khuon', t.so_khuon, 'loai_su_co', t.loai_su_co, 'gio_phat_sinh', t.gio_phat_sinh,
           'gio_tro_lai', t.gio_tro_lai, 'dang_dung_may', t.dang_dung_may, 'phut_dung', t.phut_dung,
           'van_de', t.van_de, 'noi_dung_sx', t.noi_dung_sx, 'dam_nhiem_sx', t.dam_nhiem_sx,
           'ngay', t.ngay, 'ca', t.ca,
           'xl', case when x.id_su_co is null then null else to_jsonb(x) end
         ) order by (x.trang_thai = 'hoan_thanh') nulls first, t.gio_phat_sinh desc), '[]'::jsonb)
    into v_out
  from tat_ca t
  left join duc_khuon_xu_ly_bat_thuong x on x.id_su_co = t.id_su_co
  where case when coalesce(p_lich_su, false)
          then x.trang_thai = 'hoan_thanh'
               and x.ket_thuc >= coalesce(p_tu, current_date - 6)::timestamp at time zone 'Asia/Ho_Chi_Minh'
               and x.ket_thuc < (coalesce(p_den, current_date) + 1)::timestamp at time zone 'Asia/Ho_Chi_Minh'
          else x.id_su_co is null or x.trang_thai <> 'hoan_thanh' or x.ket_thuc >= now() - interval '7 days'
        end;

  return jsonb_build_object('ok', true, 'tu_thoi_diem', v_tu, 'rows', v_out);
end;
$$;
revoke execute on function duc_khuon_xlbt_danh_sach(boolean, date, date) from public, anon;
grant execute on function duc_khuon_xlbt_danh_sach(boolean, date, date) to authenticated;
