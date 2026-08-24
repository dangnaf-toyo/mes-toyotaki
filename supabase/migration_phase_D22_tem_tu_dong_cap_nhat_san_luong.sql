-- ============================================================================
-- D22 — Tự động cập nhật "Sản lượng thực tế" (tt_ca) từ tem in ra, ngay trong
-- Postgres — KHÔNG còn phụ thuộc Apps Script (trigger_pollDiecast_).
--
-- Bối cảnh: trước đây, mỗi khi in tem (duc_ghi_tem ghi vào duc_tem), việc
-- cộng số lượng đó vào duc_ca_hien_tai.tt_ca do 1 trigger chạy mỗi phút bên
-- Apps Script project "Dashboard Đúc" (Diecast.js -> trigger_pollDiecast_ ->
-- RPC duc_bulk_update_actuals) đảm nhiệm. Trigger đó đã ngừng chạy từ
-- 2026-08-20 (kiểm tra last_updated_by='system@poll' trong duc_ca_hien_tai
-- không còn dòng nào mới hơn), khiến "Sản lượng thực tế" trên dashboard
-- không tự cập nhật nữa dù tem vẫn in bình thường — user yêu cầu làm lại cơ
-- chế này hoàn toàn trong Supabase, không phụ thuộc hệ thống ngoài nữa.
--
-- Cách hoạt động mới: trigger AFTER INSERT/UPDATE/DELETE trên duc_tem gọi
-- hàm tính lại tt_ca NGAY LẬP TỨC (đồng bộ, không cần đợi job nền) cho đúng
-- dòng sản xuất đang chạy (ma_may + ma_sp khớp, dòng row_seq lớn nhất) —
-- cộng dồn so_luong_tt của mọi tem thuộc đúng máy/mã SP đó, in ra trong
-- đúng khoảng thời gian dòng sản xuất này đang chạy (sp_start_time ->
-- sp_end_time, hoặc đến hiện tại nếu SP chưa kết thúc). Cách này tự nhiên
-- khớp với nguyên tắc "chốt theo kết ca, không cắt theo giờ đồng hồ" đã áp
-- dụng cho duc-dashboard.html — vì khớp theo (máy, mã SP) đang thực sự chạy,
-- không theo nhãn Ca 1/Ca 2 hay mốc giờ.
--
-- Phạm vi: chỉ tính lại tt_ca (số hiển thị "Sản lượng thực tế" trên
-- dashboard/báo cáo tuần). CHƯA đụng tới tt_tuan — cột đó cần công thức
-- riêng (cộng dồn theo tuần, có thể trải nhiều máy cho cùng 1 mã SP) chưa
-- được xác nhận rõ, để tránh suy diễn sai. Chạy an toàn nhiều lần (idempotent).
-- ============================================================================

-- ── Hàm lõi: tính lại tt_ca cho đúng 1 cặp (máy, mã SP) ────────────────────
create or replace function duc_recompute_tt_ca(p_ma_may text, p_ma_sp text)
returns void
language plpgsql
security definer
as $$
declare
  v_row duc_ca_hien_tai%rowtype;
  v_total numeric;
begin
  if p_ma_may is null or p_ma_sp is null then
    return;
  end if;

  -- Dòng sản xuất "đang chạy" cho đúng máy + mã SP này = dòng mới nhất
  -- (row_seq lớn nhất) khớp cả 2 điều kiện — không quan tâm nhãn ca/ngày,
  -- đúng nguyên tắc "kết ca quyết định, không phải đồng hồ".
  select * into v_row
  from duc_ca_hien_tai
  where ma_may = p_ma_may and ma_sp = p_ma_sp
  order by row_seq desc
  limit 1;

  if v_row.id_dong is null then
    return; -- không có dòng nào khớp (vd tem in cho máy/SP không có kế hoạch) — bỏ qua êm re
  end if;

  select coalesce(sum(so_luong_tt), 0) into v_total
  from duc_tem
  where may_tt = p_ma_may and ma_sp = p_ma_sp
    and ngay_gio_in >= coalesce(v_row.sp_start_time, '1970-01-01'::timestamptz)
    and (v_row.sp_end_time is null or ngay_gio_in <= v_row.sp_end_time);

  update duc_ca_hien_tai
  set tt_ca = v_total,
      version = coalesce(version, 0) + 1,
      last_updated_by = 'system@tem_trigger',
      last_updated_at = now()
  where id_dong = v_row.id_dong
    and coalesce(tt_ca, -1) is distinct from v_total; -- tránh ghi thừa khi không đổi gì
end;
$$;

-- ── Trigger function: gọi hàm trên cho cả tổ hợp (máy, mã SP) cũ và mới ────
-- (UPDATE có thể đổi may_tt/ma_sp; DELETE cần trừ lại đúng dòng cũ)
create or replace function duc_tem_sync_actuals_trigger()
returns trigger
language plpgsql
security definer
as $$
begin
  if TG_OP in ('INSERT', 'UPDATE') then
    perform duc_recompute_tt_ca(NEW.may_tt, NEW.ma_sp);
  end if;
  if TG_OP in ('UPDATE', 'DELETE') then
    if TG_OP = 'DELETE' or OLD.may_tt is distinct from NEW.may_tt or OLD.ma_sp is distinct from NEW.ma_sp then
      perform duc_recompute_tt_ca(OLD.may_tt, OLD.ma_sp);
    end if;
  end if;
  return coalesce(NEW, OLD);
end;
$$;

drop trigger if exists trg_duc_tem_sync_actuals on duc_tem;
create trigger trg_duc_tem_sync_actuals
  after insert or update or delete on duc_tem
  for each row execute function duc_tem_sync_actuals_trigger();

-- ── Backfill 1 lần: sửa ngay các dòng đang bị "đứng số" từ khi trigger cũ
--    (Apps Script) ngừng chạy — tính lại cho MỌI cặp (máy, mã SP) đang có
--    trong duc_ca_hien_tai, không chỉ tem mới sau này. ──────────────────────
do $$
declare
  r record;
begin
  for r in select distinct ma_may, ma_sp from duc_ca_hien_tai where ma_may is not null and ma_sp is not null
  loop
    perform duc_recompute_tt_ca(r.ma_may, r.ma_sp);
  end loop;
end $$;

-- Ghi chú vận hành: từ nay có thể tắt hẳn trigger `trigger_pollDiecast_` bên
-- Apps Script project "Dashboard Đúc" — không còn hàm nào trong repo Supabase
-- này gọi tới nó nữa, và duc_bulk_update_actuals() vẫn còn tồn tại (không xoá,
-- không hại gì nếu để đó) nhưng không còn là đường cập nhật chính.
