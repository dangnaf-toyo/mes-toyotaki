-- ============================================================================
-- Phase 4, bước con 3 (cutover ghi) — khối Ca_hien_tai (CaHienTai.js, Diecast.js,
-- IpqcCheckpoint.js, BanGhiSuCo.js, Ncp.js, BaoCao.js carry-over).
-- Bổ sung cho supabase/schema_duc.sql (đã chạy trước đó, có dữ liệu duc_ca_hien_tai).
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- Cột thứ tự chèn dòng — thay thế vai trò "row index" của Google Sheet mà
-- _getActiveIdDongSet_() (IpqcCheckpoint.js) dùng để xác định dòng SP nào đang
-- "active" trên 1 máy (dòng chèn SAU CÙNG = active; changeProduct_ giữ nguyên
-- dòng SP cũ, không xoá, nên cần phân biệt cũ/mới bằng thứ tự chèn — KHÔNG
-- dùng last_updated_at vì cột đó có thể bị trigger nền (poll Diecast) cập
-- nhật cả cho dòng cũ, làm sai thứ tự).
alter table duc_ca_hien_tai add column if not exists row_seq bigserial;
create index if not exists idx_duc_cht_row_seq on duc_ca_hien_tai (ma_may, row_seq desc);

-- Cập nhật hàng loạt tt_ca/tt_tuan từ trigger_pollDiecast_ (Diecast.js, chạy mỗi
-- phút) — gộp N lần PATCH riêng lẻ thành 1 lệnh gọi RPC. Giữ đúng ngữ nghĩa bản
-- gốc: chỉ các id_dong có trong danh sách mới bị đổi (đã lọc "có thay đổi" ở
-- phía Apps Script trước khi gọi); version tăng thêm 1; last_updated_by cố định
-- 'system@poll'. Bỏ qua êm re nếu id_dong không còn tồn tại (dòng đã bị xoá do
-- kết ca/đổi SP giữa lúc trigger đang chạy) — không được làm lỗi cả batch.
create or replace function duc_bulk_update_actuals(updates jsonb)
returns int
language plpgsql
security definer
as $$
declare
  v_now timestamptz := now();
  v_count int := 0;
  u jsonb;
begin
  for u in select * from jsonb_array_elements(updates)
  loop
    update duc_ca_hien_tai
    set tt_ca = (u->>'tt_ca')::numeric,
        tt_tuan = (u->>'tt_tuan')::numeric,
        version = coalesce(version, 0) + 1,
        last_updated_by = 'system@poll',
        last_updated_at = v_now
    where id_dong = (u->>'id_dong');
    if found then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;
