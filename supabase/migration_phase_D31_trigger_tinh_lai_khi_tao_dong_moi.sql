-- ============================================================================
-- D31 — Tự động tính lại tt_ca/tt_tuan ngay khi có DÒNG MỚI được tạo trong
-- duc_ca_hien_tai (kết ca carry-over, gán kế hoạch mới, đổi SP...), không
-- chỉ khi có tem in ra.
--
-- Phát hiện thực tế: sau khi Kết ca (tạo dòng carry-over cho Ca đêm), tt_tuan
-- của dòng mới về 0 dù tuần vẫn còn sản lượng từ Ca ngày trước đó — vì
-- trigger duc_tem_sync_actuals_trigger (D22-D28) CHỈ chạy khi duc_tem thay
-- đổi, không chạy khi chính duc_ca_hien_tai có dòng mới. Dòng mới đứng yên ở
-- tt_ca=0/tt_tuan=0 cho tới khi có tem tiếp theo mới kích hoạt tính lại.
--
-- Sửa: thêm trigger AFTER INSERT trên chính duc_ca_hien_tai, gọi lại
-- duc_recompute_tt_ca(ma_may, ma_sp) ngay khi dòng mới được tạo — tự khớp
-- đúng sản lượng/tuần hiện có mà không cần đợi tem tiếp theo.
-- An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create or replace function duc_cht_insert_recompute_trigger()
returns trigger
language plpgsql
security definer
as $$
begin
  -- Tránh đệ quy: duc_recompute_tt_ca có thể UPDATE chính dòng này, nhưng đó
  -- là UPDATE không phải INSERT nên không kích hoạt lại trigger này.
  perform duc_recompute_tt_ca(NEW.ma_may, NEW.ma_sp);
  return NEW;
end;
$$;

drop trigger if exists trg_duc_cht_insert_recompute on duc_ca_hien_tai;
create trigger trg_duc_cht_insert_recompute
  after insert on duc_ca_hien_tai
  for each row execute function duc_cht_insert_recompute_trigger();
