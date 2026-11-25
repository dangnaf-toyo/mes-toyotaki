-- ============================================================================
-- Phase T347 — BOM gửi thông báo chuông (cv_thong_bao, nguon = 'bom')
-- Trước đây gửi duyệt / duyệt / trả lại BOM không ghi thông báo nào.
-- - Nháp → Chờ duyệt: báo "Cần duyệt BOM" cho Giám đốc SX + Tổng giám đốc (cần xử lý).
-- - Duyệt / Trả lại / Rút lại: đóng thông báo chờ duyệt; báo người lập kết quả.
-- Trigger bọc exception → lỗi thông báo không chặn thao tác BOM.
-- Bổ sung thông báo cho các BOM đang chờ duyệt. Chạy lại an toàn.
-- ============================================================================

do $$ declare v text;
begin
  select pg_get_constraintdef(oid) into v from pg_constraint where conname = 'cv_thong_bao_nguon_check';
  if v is not null and v not like '%''bom''%' then
    execute 'alter table public.cv_thong_bao drop constraint cv_thong_bao_nguon_check';
    execute 'alter table public.cv_thong_bao add constraint cv_thong_bao_nguon_check '
         || replace(v, '])))', ', ''bom''::text])))');
  end if;
end $$;

create or replace function public.bom_ds_duyet() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct user_id), '{}') from user_roles where chuc_danh in ('giam_doc_sx', 'tong_giam_doc');
$$;

create or replace function public.bom_tb_trig() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_khoa text := 'bom:' || new.id;
        v_lk text := 'bom.html?sp=' || new.ma_sp || '&v=' || new.id;
        v_nhan text := new.ma_sp || ' V' || new.version_no;
begin
  if new.trang_thai is not distinct from old.trang_thai then return new; end if;
  begin
    if new.trang_thai = 'cho_duyet' then
      perform cv_pd_gui(bom_ds_duyet(), 'bom', 'can_duyet', v_khoa, v_lk, 'Cần duyệt BOM ' || v_nhan, true);
    elsif old.trang_thai = 'cho_duyet' then
      perform cv_pd_xong(v_khoa, false);
      if new.trang_thai = 'da_duyet' then
        perform cv_pd_gui(array[new.nguoi_lap_uid], 'bom', 'da_duyet', v_khoa, v_lk, 'BOM ' || v_nhan || ' đã được duyệt', false);
      elsif new.trang_thai = 'nhap' and new.ly_do_tra_lai is not null then
        perform cv_pd_gui(array[new.nguoi_lap_uid], 'bom', 'tu_choi_duyet', v_khoa, v_lk,
          'BOM ' || v_nhan || ' bị trả lại: ' || new.ly_do_tra_lai, false);
      end if;
    end if;
  exception when others then
    raise warning 'bom_tb_trig: %', sqlerrm;
  end;
  return new;
end $$;

revoke all on function public.bom_ds_duyet(), public.bom_tb_trig() from public, anon, authenticated;

drop trigger if exists trg_bom_thong_bao on public.bom_versions;
create trigger trg_bom_thong_bao after update of trang_thai on public.bom_versions
  for each row execute function public.bom_tb_trig();

-- Bổ sung cho BOM đang chờ duyệt (chạy không có auth.uid → gửi đủ người duyệt).
select public.cv_pd_gui(public.bom_ds_duyet(), 'bom', 'can_duyet', 'bom:' || b.id,
         'bom.html?sp=' || b.ma_sp || '&v=' || b.id, 'Cần duyệt BOM ' || b.ma_sp || ' V' || b.version_no, true)
from public.bom_versions b where b.trang_thai = 'cho_duyet';
