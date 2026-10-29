-- T186: giới hạn dụng cụ khi lưu hạng mục tiêu chuẩn; không cập nhật dữ liệu lịch sử.
-- Đã chạy STAGING 29/10/2026; chưa chạy PRODUCTION.
begin;
create or replace function public.ipqc_kiem_tra_dung_cu()
returns trigger language plpgsql set search_path=public as $$
begin
  if tg_op='UPDATE' then
    if new.dung_cu is not distinct from old.dung_cu then return new; end if;
  end if;
  new.dung_cu := nullif(trim(new.dung_cu),'');
  if new.dung_cu is not null and not (new.dung_cu=any(array[
    'Thước kẹp', 'CMM', 'OMM', 'Máy đo biên dạng', 'Máy đo độ nhám', 'Thước đo cao',
    'Thước lá', 'Máy phân tích nguyên vật liệu', 'Máy kiểm tra độ cứng',
    'Máy kiểm tra lực nén', 'Máy kiểm tra màu sắc', 'Máy đo độ dày sơn'
  ])) then
    raise exception 'Chọn dụng cụ kiểm tra trong danh sách cho phép';
  end if;
  return new;
end $$;
revoke all on function public.ipqc_kiem_tra_dung_cu() from public,anon,authenticated;
drop trigger if exists ipqc_kiem_tra_dung_cu on public.ipqc_btk_muc;
create trigger ipqc_kiem_tra_dung_cu before insert or update of dung_cu
on public.ipqc_btk_muc for each row execute function public.ipqc_kiem_tra_dung_cu();
commit;
