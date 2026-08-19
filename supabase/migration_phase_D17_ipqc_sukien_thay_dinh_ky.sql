-- ============================================================================
-- Giai đoạn 17 — Kiểm sau sự cố / đổi khuôn-SP mới có thể THAY THẾ 1 lần
-- kiểm định kỳ (cùng là kiểm chất lượng ngay tại thời điểm đó, không cần
-- kiểm định kỳ thêm nữa nếu đã có 1 trong 2 loại trên đang chờ/vừa xong).
--
-- Trước đây (migration_phase_D16) chỉ ẩn bớt ở client (ipqc.html) khi có ≥2
-- loại kiểm cùng đến hạn cho 1 máy — dữ liệu "định kỳ đến hạn" vẫn được RPC
-- trả về, dòng cong_doan-dashboard/qc-manager vẫn có thể thấy trùng. Sửa
-- thẳng ở RPC: không tính "định kỳ đến hạn" cho 1 id_dong nếu id_dong đó
-- đang có BẤT KỲ checkpoint nào khác (sau_su_co/doi_khuon) ở trạng thái
-- "cho_kiem" — không chỉ riêng loai_kiem='dinh_ky' như bản cũ.
--
-- Lưu ý: khi checkpoint sau_su_co/doi_khuon đó ĐƯỢC KIỂM XONG (trang_thai
-- chuyển 'da_kiem'), mốc "lần kiểm gần nhất" dùng để tính phut_da_troi
-- (coalesce max(thoi_diem_kiem_thuc_te) theo id_dong, KHÔNG lọc loai_kiem)
-- đã tự động tính luôn lần kiểm đó — đồng hồ định kỳ tự "reset" từ đó, đúng
-- ý "kiểm sau sự cố thay được 1 lần định kỳ", không cần sửa gì thêm.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create or replace function duc_get_ipqc_periodic_due()
returns table(id_dong text, ma_may text, ma_sp text, ngay date, ca text, phut_da_troi int)
language plpgsql
stable
as $$
declare
  v_active_id_dong text[];
  v_dang_tam_dung boolean;
  v_moc_bat_dau_lai timestamptz;
begin
  select exists(select 1 from duc_ipqc_tam_dung where thoi_diem_bat_dau is null) into v_dang_tam_dung;
  if v_dang_tam_dung then
    return;
  end if;

  select max(thoi_diem_bat_dau) into v_moc_bat_dau_lai from duc_ipqc_tam_dung;

  select array_agg(t.id_dong) into v_active_id_dong from (
    select cht.id_dong, cht.ma_may, cht.khuon_kep_voi,
      row_number() over (partition by cht.ma_may order by cht.row_seq desc) as rn
    from duc_ca_hien_tai cht
  ) t
  where t.rn = 1 or exists (
    select 1 from duc_ca_hien_tai c2
    where c2.id_dong = t.khuon_kep_voi
      and (select rn2.rn from (
             select cht2.id_dong, row_number() over (partition by cht2.ma_may order by cht2.row_seq desc) as rn
             from duc_ca_hien_tai cht2
           ) rn2 where rn2.id_dong = t.khuon_kep_voi) = 1
  );

  select array_agg(cht.id_dong) into v_active_id_dong
  from duc_ca_hien_tai cht
  where cht.id_dong = any(v_active_id_dong)
    and (cht.open_gio_phat_sinh is not null
      or not exists (
        select 1 from duc_bao_cao_ca bc where bc.ngay = cht.ngay and bc.ca = cht.ca
      ));

  return query
  select cht.id_dong, cht.ma_may, cht.ma_sp, cht.ngay, cht.ca,
    round(extract(epoch from (now() - greatest(
      coalesce(
        (select max(cp.thoi_diem_kiem_thuc_te) from duc_ipqc_checkpoint cp
          where cp.id_dong = cht.id_dong and cp.trang_thai = 'da_kiem'),
        cht.sp_start_time, cht.last_updated_at
      ),
      coalesce(v_moc_bat_dau_lai, '-infinity'::timestamptz)
    ))) / 60)::int as phut_da_troi
  from duc_ca_hien_tai cht
  where cht.id_dong = any(v_active_id_dong)
    and cht.ma_sp is not null and cht.ma_sp <> ''
    -- Không tính "định kỳ đến hạn" nếu dòng này đang có BẤT KỲ checkpoint
    -- nào khác chờ kiểm (sau_su_co/doi_khuon/dinh_ky) — checkpoint đó đủ
    -- thay thế, tránh sinh thêm 1 mục định kỳ trùng.
    and not exists (
      select 1 from duc_ipqc_checkpoint cp2
      where cp2.id_dong = cht.id_dong and cp2.trang_thai = 'cho_kiem'
    );
end;
$$;
