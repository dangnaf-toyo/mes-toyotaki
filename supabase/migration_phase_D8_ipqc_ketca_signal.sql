-- ============================================================================
-- Giai đoạn 8 (bỏ Google) — Bỏ hẳn cách đoán "máy đã dừng" theo thời gian
-- (sp_end_time + khoảng đệm ở migration_phase_D6/D7) — dùng đúng tín hiệu
-- nghiệp vụ thật: máy chỉ dừng khi TRƯỞNG CA ĐÃ BẤM "KẾT CA" cho đúng ngày/ca
-- của dòng đó (và không tick "tiếp tục" cho máy này).
--
-- Bảng duc_bao_cao_ca đã ghi sẵn đúng tín hiệu này: có 1 dòng (ngay, ca) khi
-- và chỉ khi trưởng ca đã kết ca cho ngày/ca đó (duc_end_shift ghi
-- thoi_diem_ket_ca). Nếu dòng sản xuất mới nhất của 1 máy có (ngay, ca) CHƯA
-- có trong duc_bao_cao_ca → ca đó chưa kết thúc theo nghiệp vụ, máy vẫn được
-- coi là đang hoạt động BẤT KỂ đã chạy quá giờ dự kiến bao lâu.
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
begin
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

  -- Lọc lại: chỉ giữ id_dong mà CHÍNH dòng đó đang có sự cố mở, HOẶC ngày/ca
  -- của dòng CHƯA được kết ca (chưa có bản ghi duc_bao_cao_ca tương ứng).
  select array_agg(cht.id_dong) into v_active_id_dong
  from duc_ca_hien_tai cht
  where cht.id_dong = any(v_active_id_dong)
    and (cht.open_gio_phat_sinh is not null
      or not exists (
        select 1 from duc_bao_cao_ca bc where bc.ngay = cht.ngay and bc.ca = cht.ca
      ));

  return query
  select cht.id_dong, cht.ma_may, cht.ma_sp, cht.ngay, cht.ca,
    round(extract(epoch from (now() - coalesce(
      (select max(cp.thoi_diem_kiem_thuc_te) from duc_ipqc_checkpoint cp
        where cp.ma_may = cht.ma_may and cp.trang_thai = 'da_kiem'),
      cht.sp_start_time, cht.last_updated_at
    ))) / 60)::int as phut_da_troi
  from duc_ca_hien_tai cht
  where cht.id_dong = any(v_active_id_dong)
    and cht.ma_sp is not null and cht.ma_sp <> ''
    and not exists (
      select 1 from duc_ipqc_checkpoint cp2
      where cp2.id_dong = cht.id_dong and cp2.trang_thai = 'cho_kiem' and cp2.loai_kiem = 'dinh_ky'
    );
end;
$$;
