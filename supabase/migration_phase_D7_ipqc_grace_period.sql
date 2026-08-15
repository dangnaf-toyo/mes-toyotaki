-- ============================================================================
-- Giai đoạn 7 (bỏ Google) — Thêm khoảng đệm (grace period) sau giờ kết ca dự
-- kiến trước khi coi 1 dòng sản xuất là "đã dừng hẳn" (loại khỏi active set).
--
-- Phát hiện qua báo cáo thực tế (2026-08-15): DC6 đang sản xuất thật (hiển
-- thị đúng trên Dashboard Đúc), có 1 checkpoint 'doi_khuon' đang chờ kiểm
-- thật (33 phút) — nhưng biến mất khỏi ipqc.html/qc-manager.html ngay khi
-- giờ kết ca dự kiến (sp_end_time) vừa trôi qua VÀI PHÚT. Bản vá trước
-- (migration_phase_D6) cắt "active" đúng lúc sp_end_time qua — quá cứng nhắc:
-- ca chạy trễ vài giờ so với dự kiến (tăng ca thực tế nhưng chưa kịp ghi
-- nhận trên hệ thống) là chuyện bình thường trong sản xuất thật.
--
-- Sửa: chỉ coi 1 dòng là "đã dừng hẳn" khi sp_end_time đã qua HƠN 240 PHÚT
-- (4 giờ) — đủ để loại các dòng "sống dai" nhiều ngày (như DC4 hôm trước),
-- nhưng không cắt nhầm ca đang chạy trễ vài chục phút/vài giờ như DC6. Đã
-- sửa đồng bộ ipqc.html/qc-manager.html/duc-dashboard.html (JS, không qua
-- SQL) — hàm dưới đây là bản sửa cho RPC dùng ở cả 2 trang IPQC.
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
  v_stale_grace_min constant int := 240;
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

  -- Lọc lại: chỉ giữ id_dong mà CHÍNH dòng đó chưa kết thúc ca QUÁ LÂU (trong
  -- khoảng đệm v_stale_grace_min phút) hoặc đang có sự cố mở.
  select array_agg(cht.id_dong) into v_active_id_dong
  from duc_ca_hien_tai cht
  where cht.id_dong = any(v_active_id_dong)
    and (cht.open_gio_phat_sinh is not null
      or cht.sp_end_time is null
      or extract(epoch from (now() - cht.sp_end_time)) / 60 <= v_stale_grace_min);

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
