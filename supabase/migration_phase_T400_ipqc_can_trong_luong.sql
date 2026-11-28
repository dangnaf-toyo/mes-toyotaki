-- T400: dụng cụ Cân trọng lượng cho bảng tuần kiểm Đúc và Gia công.
-- Chạy sau T186, T187 và T232. Đã chạy STAGING + PRODUCTION 28/11/2026.
begin;

create or replace function public.ipqc_kiem_tra_dung_cu()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.dung_cu is not distinct from old.dung_cu then
    return new;
  end if;

  new.dung_cu := nullif(trim(new.dung_cu), '');
  if new.dung_cu = 'Cân trọng lượng' then
    if not exists (
      select 1 from public.ipqc_btk
      where id = new.id_btk and cong_doan in ('duc', 'gia_cong')
    ) then
      raise exception 'Cân trọng lượng chỉ dùng cho tiêu chuẩn Đúc và Gia công';
    end if;
    return new;
  end if;

  if new.dung_cu is not null and not (new.dung_cu = any(array[
    'Thước kẹp', 'CMM', 'OMM', 'Máy đo biên dạng', 'Máy đo độ nhám', 'Thước đo cao',
    'Thước lá', 'Máy phân tích nguyên vật liệu', 'Máy kiểm tra độ cứng',
    'Máy kiểm tra lực nén', 'Máy kiểm tra màu sắc', 'Máy đo độ dày sơn',
    'Panme', 'JIG', 'Kiểm bằng mắt'
  ])) then
    raise exception 'Chọn dụng cụ kiểm tra trong danh sách cho phép';
  end if;
  return new;
end $$;

revoke all on function public.ipqc_kiem_tra_dung_cu() from public, anon, authenticated;
commit;
