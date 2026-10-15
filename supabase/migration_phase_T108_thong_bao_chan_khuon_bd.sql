-- ============================================================================
-- T108 — Thông báo chặn khuôn chưa bảo dưỡng ĐẠT (T100) nói rõ lý do + link mở
-- KH bảo dưỡng tuần của khuôn (user 2026-10-15: khuôn 9002 #2, K09 #45-46 tổ
-- khuôn nói đã bảo dưỡng nhưng không có check sheet → dashboard vẫn chặn).
--
--   duc_khuon_ds_trang_thai_bd() thêm cho mỗi khuôn:
--     - cs_dang_lam: check sheet gần nhất CHƯA hoàn thành {id, id_kh, ngay, tuan}
--     - kh_chua_cs : lịch bảo dưỡng chưa có check sheet hoàn thành, gần hôm nay
--                    nhất (ưu tiên lịch đã tới hạn) {id, ngay, tuan, loai, nguoi}
--   Logic chặn (trigger) KHÔNG đổi.
--
-- Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

create or replace function duc_khuon_ds_trang_thai_bd()
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'bat', coalesce((select gia_tri = 'true'::jsonb from duc_cau_hinh where khoa = 'chan_khuon_chua_bd_dat'), false),
    'khuon', coalesce(jsonb_object_agg(k.ma_khuon, jsonb_build_object(
      'ket_luan', b.o_ket_luan, 'ngay', b.o_ngay, 'loai', b.o_loai, 'id_checksheet', b.o_id_checksheet,
      'cho_phep_tam', (select jsonb_build_object('id', p.id, 'ma_may', p.ma_may, 'ly_do', p.ly_do, 'nguoi', p.nguoi,
                                                 'thoi_diem', p.thoi_diem, 'het_han', p.het_han)
                       from duc_khuon_cho_phep_tam p
                       where p.ma_khuon = k.ma_khuon and p.huy_luc is null and p.da_dung_luc is null and p.het_han > now()
                       order by p.thoi_diem desc limit 1),
      'may_gan_day', (select coalesce(jsonb_agg(distinct m), '[]'::jsonb) from (
          select c.ma_may m from duc_ca_hien_tai c where trim(c.so_khuon) = k.ma_khuon
          union select t.may_duc_chi_thi from duc_tem t where trim(t.so_khuon) = k.ma_khuon and t.ngay >= current_date - 1
          union select s.ma_may from duc_su_co_log s where trim(s.so_khuon) = k.ma_khuon and s.ngay >= current_date - 1) mm
        where m is not null),
      'cs_dang_lam', (select jsonb_build_object('id', cs.id, 'id_kh', cs.id_ke_hoach, 'ngay', cs.ngay_thuc_hien, 'tuan', kh.tuan_bat_dau)
                      from duc_khuon_checksheet cs
                      left join duc_khuon_bd_kh_tuan kh on kh.id = cs.id_ke_hoach
                      where trim(cs.ma_khuon) = k.ma_khuon and cs.trang_thai <> 'hoan_thanh'
                      order by cs.id desc limit 1),
      'kh_chua_cs', (select jsonb_build_object('id', kh.id, 'ngay', kh.ngay, 'tuan', kh.tuan_bat_dau,
                                               'loai', kh.loai, 'nguoi', kh.nguoi_phu_trach)
                     from duc_khuon_bd_kh_tuan kh
                     where trim(kh.ma_khuon) = k.ma_khuon
                       and not exists (select 1 from duc_khuon_checksheet cs
                                       where cs.id_ke_hoach = kh.id and cs.trang_thai = 'hoan_thanh')
                     order by (kh.ngay > current_date), abs(kh.ngay - current_date) limit 1)
    )), '{}'::jsonb))
  from (select trim(ma_khuon) as ma_khuon from duc_shot_khuon where coalesce(trim(ma_khuon), '') <> '') k
  cross join lateral duc_khuon_bd_gan_nhat(k.ma_khuon) b;
$$;
