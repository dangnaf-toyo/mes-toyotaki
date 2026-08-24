-- ============================================================================
-- D23 — Sửa lỗi migration D22: trigger tự cập nhật tt_ca từ tem vẫn bỏ sót
-- nhiều tem thật vì dùng sp_end_time làm cận trên quá cứng nhắc.
--
-- Phát hiện qua kiểm tra thực tế (2026-08-24): trong 9 tem in hôm nay, có
-- 4 tem (DC 8 x2, DC 11, Kẽm 190T) đúng máy + đúng mã SP đang chạy, nhưng
-- KHÔNG được cộng vào tt_ca vì dòng duc_ca_hien_tai tương ứng có sp_end_time
-- đã ở QUÁ KHỨ (từ 23/08) — dòng đó chưa được kết ca cho hôm nay (24/08) nên
-- vẫn là dòng "đang chạy" thật sự của máy, nhưng D22 lại coi sp_end_time là
-- mốc cứng nên loại tem in sau đó ra.
--
-- Nguyên tắc sửa: giống hệt logic loadLiveMachineStatus() ở duc-dashboard.html
-- — "dòng đang chạy" của 1 máy là dòng row_seq LỚN NHẤT của máy đó (không lọc
-- theo sp_end_time), KHÔNG dùng sp_end_time để đoán máy đã dừng. Chỉ kết ca
-- (tạo row_seq mới) mới thực sự "đóng" 1 dòng. sp_end_time chỉ là mốc DỰ KIẾN
-- kết thúc ca, không phải bằng chứng máy đã dừng sản xuất.
--
-- Vẫn giữ chặn overcounting: chỉ cộng tem có ngay_gio_in >= sp_start_time của
-- đúng dòng đang chạy — mỗi lần đổi SP/kết ca sẽ tạo row_seq mới với
-- sp_start_time mới, nên các đợt sản xuất CŨ của cùng máy/mã SP (VD DC 6 đã
-- chạy EXE-CEN-01 nhiều đợt tách biệt: 03/08, 10/08, 13/08, 24/08) không bị
-- gộp nhầm vào đợt hiện tại.
--
-- Thêm: nếu mã SP trên tem KHÔNG khớp mã SP dòng đang chạy của máy đó (VD tem
-- in cho SP cũ trong khi dashboard đã ghi nhận máy đổi sang SP khác) — không
-- cộng vào đâu cả (không đoán), để lộ rõ trong đối chiếu thủ công thay vì lặng
-- lẽ gán nhầm. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

drop function if exists duc_recompute_tt_ca(text, text);

create or replace function duc_recompute_tt_ca(p_ma_may text)
returns void
language plpgsql
security definer
as $$
declare
  v_row duc_ca_hien_tai%rowtype;
  v_total numeric;
begin
  if p_ma_may is null then
    return;
  end if;

  -- Dòng "đang chạy" thật sự của máy = row_seq lớn nhất, KHÔNG lọc sp_end_time
  select * into v_row
  from duc_ca_hien_tai
  where ma_may = p_ma_may
  order by row_seq desc
  limit 1;

  if v_row.id_dong is null or v_row.ma_sp is null then
    return;
  end if;

  select coalesce(sum(so_luong_tt), 0) into v_total
  from duc_tem
  where may_tt = p_ma_may and ma_sp = v_row.ma_sp
    and ngay_gio_in >= coalesce(v_row.sp_start_time, '1970-01-01'::timestamptz);

  update duc_ca_hien_tai
  set tt_ca = v_total,
      version = coalesce(version, 0) + 1,
      last_updated_by = 'system@tem_trigger',
      last_updated_at = now()
  where id_dong = v_row.id_dong
    and coalesce(tt_ca, -1) is distinct from v_total;
end;
$$;

create or replace function duc_tem_sync_actuals_trigger()
returns trigger
language plpgsql
security definer
as $$
begin
  if TG_OP in ('INSERT', 'UPDATE') then
    perform duc_recompute_tt_ca(NEW.may_tt);
  end if;
  if TG_OP in ('UPDATE', 'DELETE') then
    if TG_OP = 'DELETE' or OLD.may_tt is distinct from NEW.may_tt then
      perform duc_recompute_tt_ca(OLD.may_tt);
    end if;
  end if;
  return coalesce(NEW, OLD);
end;
$$;
-- (trigger trg_duc_tem_sync_actuals trên duc_tem đã tạo ở D22, không cần tạo lại)

-- ── Backfill lại theo logic mới cho MỌI máy đang có trong duc_ca_hien_tai ──
do $$
declare
  r record;
begin
  for r in select distinct ma_may from duc_ca_hien_tai where ma_may is not null
  loop
    perform duc_recompute_tt_ca(r.ma_may);
  end loop;
end $$;
