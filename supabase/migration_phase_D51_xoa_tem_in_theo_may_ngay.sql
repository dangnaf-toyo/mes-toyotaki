-- =============================================================================
-- D51 — Hàm xóa dữ liệu in tem theo (máy, ngày in)
--
-- Nhu cầu: xóa toàn bộ tem đã IN RA trong 1 ngày của 1 máy (mặc định Kẽm 190T).
-- "In ra" = có dòng trong duc_tem, mốc in = ngay_gio_in. Với tem Kanban của
-- Kẽm 190T/160T (D48) thì 1 "lô chỉ thị" chỉ là tập các dòng duc_tem cùng
-- id_lo_chi_thi — xóa hết các dòng đó là xóa luôn lô, không có bảng lô riêng
-- để dọn.
--
-- LƯU Ý TÁC ĐỘNG:
--   * Trigger trg_duc_tem_sync_actuals (D22/D26) chạy AFTER DELETE từng dòng,
--     gọi duc_recompute_tt_ca(OLD.may_tt, OLD.ma_sp). Tem chưa quét có
--     may_tt = NULL -> gần như no-op; tem đã quét (trang_thai 'Đã sản xuất')
--     sẽ được trừ đúng khỏi tt_ca / tt_tuan. Đây là hành vi mong muốn.
--   * Nếu tem đã bị tách pallet (duc_tem_tach.tag_no_cha) thì xóa tem cha sẽ
--     để lại lịch sử tách mồ côi — hàm sẽ RAISE cảnh báo (không chặn).
--   * Thao tác KHÔNG hoàn tác được. Mặc định p_dry_run = true (chỉ liệt kê).
--     Phải gọi lại với p_dry_run => false mới thực sự xóa.
-- =============================================================================

create or replace function duc_xoa_tem_in_theo_may_ngay(
  p_may                 text    default 'Kẽm 190T',
  p_ngay                date    default (now() at time zone 'Asia/Ho_Chi_Minh')::date,
  p_bo_qua_da_quet      boolean default false,   -- true: chỉ xóa tem CHƯA quét (ngay_gio_ghi_nhan IS NULL)
  p_dry_run             boolean default true     -- true: chỉ xem; false: xóa thật
)
returns table(
  tag_no            text,
  ma_sp             text,
  so_luong          numeric,
  so_luong_tt       numeric,
  may_duc_chi_thi   text,
  may_tt            text,
  id_lo_chi_thi     text,
  trang_thai        text,
  ngay_gio_in       timestamptz,
  ngay_gio_ghi_nhan timestamptz
)
language plpgsql
security definer
as $$
declare
  v_lower  timestamptz := (p_ngay::text            || ' 00:00:00+07')::timestamptz;
  v_upper  timestamptz := ((p_ngay + 1)::text      || ' 00:00:00+07')::timestamptz;
  v_tach   int;
  v_n      int;
begin
  if p_may is null or btrim(p_may) = '' then
    raise exception 'Phải truyền tên máy (p_may)';
  end if;

  -- Cảnh báo nếu có tem trong phạm vi xóa từng là tem cha của 1 lần tách pallet.
  select count(*) into v_tach
  from duc_tem_tach x
  join duc_tem t on t.tag_no = x.tag_no_cha
  where t.may_duc_chi_thi = p_may
    and t.ngay_gio_in >= v_lower and t.ngay_gio_in < v_upper
    and (not p_bo_qua_da_quet or t.ngay_gio_ghi_nhan is null);
  if v_tach > 0 then
    raise warning '% tem trong phạm vi đã từng tách pallet — lịch sử duc_tem_tach sẽ mồ côi', v_tach;
  end if;

  if p_dry_run then
    return query
      select t.tag_no, t.ma_sp, t.so_luong, t.so_luong_tt,
             t.may_duc_chi_thi, t.may_tt, t.id_lo_chi_thi,
             t.trang_thai, t.ngay_gio_in, t.ngay_gio_ghi_nhan
      from duc_tem t
      where t.may_duc_chi_thi = p_may
        and t.ngay_gio_in >= v_lower
        and t.ngay_gio_in <  v_upper
        and (not p_bo_qua_da_quet or t.ngay_gio_ghi_nhan is null)
      order by t.ngay_gio_in, t.tag_no;

    get diagnostics v_n = row_count;
    raise notice '[DRY RUN] Sẽ xóa % tem của máy "%" in ngày % (bỏ qua tem đã quét: %)',
      v_n, p_may, p_ngay, p_bo_qua_da_quet;
    return;
  end if;

  return query
    delete from duc_tem t
    where t.may_duc_chi_thi = p_may
      and t.ngay_gio_in >= v_lower
      and t.ngay_gio_in <  v_upper
      and (not p_bo_qua_da_quet or t.ngay_gio_ghi_nhan is null)
    returning t.tag_no, t.ma_sp, t.so_luong, t.so_luong_tt,
              t.may_duc_chi_thi, t.may_tt, t.id_lo_chi_thi,
              t.trang_thai, t.ngay_gio_in, t.ngay_gio_ghi_nhan;

  get diagnostics v_n = row_count;
  raise notice 'ĐÃ XÓA % tem của máy "%" in ngày %', v_n, p_may, p_ngay;
end;
$$;

-- Chỉ cho phép chạy từ vai trò quản trị (SQL editor / service_role), không mở
-- cho anon/authenticated như các RPC nghiệp vụ.
revoke all on function duc_xoa_tem_in_theo_may_ngay(text, date, boolean, boolean) from public;
revoke all on function duc_xoa_tem_in_theo_may_ngay(text, date, boolean, boolean) from anon;
revoke all on function duc_xoa_tem_in_theo_may_ngay(text, date, boolean, boolean) from authenticated;

-- =============================================================================
-- CÁCH DÙNG
--   -- 1) Xem trước (mặc định, không xóa gì) — Kẽm 190T, hôm nay:
--   select * from duc_xoa_tem_in_theo_may_ngay();
--
--   -- 2) Xem trước cho ngày / máy khác:
--   select * from duc_xoa_tem_in_theo_may_ngay('Kẽm 190T', date '2026-08-29');
--
--   -- 3) XÓA THẬT (Kẽm 190T, hôm nay, tất cả tem in trong ngày):
--   select * from duc_xoa_tem_in_theo_may_ngay('Kẽm 190T',
--            (now() at time zone 'Asia/Ho_Chi_Minh')::date, false, false);
--
--   -- 4) XÓA THẬT nhưng giữ lại tem đã quét ghi nhận:
--   select * from duc_xoa_tem_in_theo_may_ngay('Kẽm 190T',
--            (now() at time zone 'Asia/Ho_Chi_Minh')::date, true, false);
-- =============================================================================
