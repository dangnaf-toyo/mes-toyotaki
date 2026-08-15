-- ============================================================================
-- Giai đoạn 6 (bỏ Google) — Sửa "active set" của IPQC: loại các dòng đã kết
-- thúc ca lâu rồi mà không có sự cố đang mở.
--
-- Phát hiện qua báo cáo thực tế (2026-08-15): nhiều máy hiện "Không có kế
-- hoạch" trên Dashboard Đúc (không có dòng nào cho ngày/ca hiện tại) nhưng
-- vẫn xuất hiện trong hàng chờ kiểm IPQC — vì _getActiveIdDongSet_/RPC
-- duc_get_ipqc_periodic_due() coi "active" = dòng row_seq lớn nhất của máy,
-- BẤT KỂ dòng đó đã kết thúc ca (sp_end_time đã qua) từ mấy ngày trước. Dòng
-- cũ vẫn còn trong bảng chỉ vì chưa có dòng mới ghi đè (máy thật ra đang
-- trống, không chạy) — không nên tính là active.
--
-- Sửa: 1 dòng chỉ được coi là active khi (a) sp_end_time chưa qua (ca chưa
-- kết thúc), HOẶC (b) đang có sự cố mở (open_gio_phat_sinh — kể cả trường
-- hợp mở sự cố trên 1 dòng đã quá giờ kết ca theo lịch, vẫn là tình huống
-- thật cần IPQC xử lý ngay). Áp dụng thêm cho ipqc.html/qc-manager.html
-- (getActiveIdDongSet, sửa trực tiếp trong 2 file đó, không qua SQL).
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

  -- Lọc lại: chỉ giữ id_dong mà CHÍNH dòng đó chưa kết thúc ca hoặc đang có
  -- sự cố mở — loại các dòng "sống dai" đã hết hiệu lực từ lâu.
  select array_agg(cht.id_dong) into v_active_id_dong
  from duc_ca_hien_tai cht
  where cht.id_dong = any(v_active_id_dong)
    and (cht.open_gio_phat_sinh is not null or cht.sp_end_time is null or cht.sp_end_time >= now());

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
