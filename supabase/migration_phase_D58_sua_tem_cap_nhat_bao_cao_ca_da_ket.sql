-- D58: Sửa/xoá tem thuộc ca ĐÃ KẾT CA → tự cập nhật lại báo cáo kết ca.
--
-- Trước đây trigger trg_duc_tem_sync_actuals (D22) chỉ tính lại tt_ca cho
-- dòng duc_ca_hien_tai ĐANG MỞ; sau khi kết ca dòng của ca cũ đã bị xoá, nên
-- sửa số lượng tem của ca cũ không làm đổi duc_lich_su_san_xuat lẫn
-- duc_bao_cao_ca (bao-cao-ca.html, báo cáo tuần vẫn hiện số cũ).
--
-- Cách làm: trigger mới AFTER UPDATE/DELETE trên duc_tem cộng/trừ CHÊNH LỆCH
-- so_luong_tt vào đúng dòng lịch sử (máy, mã SP, ca) chứa mốc thời gian của
-- tem (coalesce(ngay_gio_ghi_nhan, ngay_gio_in), giống duc_recompute_tt_ca),
-- rồi cập nhật báo cáo ca: tong_tt_ca, ty_le_hoan_thanh_ca, so_may_hoan_thanh_kh
-- (đếm theo máy, D57). Dùng chênh lệch chứ không tính lại từ đầu để không đè
-- mất các số trưởng ca đã sửa tay trước khi kết ca.
-- OEE/Availability/Performance/Quality giữ nguyên số chốt lúc kết ca.
--
-- Không xử lý INSERT: tem mới in/tách luôn có mốc = now() → thuộc ca đang mở,
-- đã do trigger D22 lo.
--
-- Chạy trên CẢ 2 project (production + staging).

create or replace function duc_ls_dieu_chinh_tem(
  p_ma_may text, p_ma_sp text, p_moc timestamptz, p_delta numeric
)
returns void
language plpgsql
security definer
as $$
declare
  v_ls record;
begin
  if p_ma_may is null or p_ma_sp is null or p_moc is null or coalesce(p_delta, 0) = 0 then
    return;
  end if;

  -- Ca đã kết chứa mốc tem: mốc nằm trong khung giờ ca, hoặc sau giờ kết thúc
  -- ca nhưng trước lúc bấm kết ca (tối đa 2 tiếng) — tem in trong khoảng này
  -- cũng đã được tính vào ca cũ lúc kết ca.
  select ls.ngay, ls.ca into v_ls
  from duc_lich_su_san_xuat ls
  cross join lateral (select duc_get_shift_window(ls.ngay, ls.phuong_an_ca, ls.ca) as w) sw
  where ls.ma_may = p_ma_may and ls.ma_sp = p_ma_sp
    and sw.w is not null
    and p_moc >= (sw.w->>'start')::timestamptz
    and p_moc < greatest((sw.w->>'end')::timestamptz,
                         least(ls.thoi_diem_ghi, (sw.w->>'end')::timestamptz + interval '2 hours'))
  order by (sw.w->>'start')::timestamptz desc
  limit 1;

  if v_ls.ngay is null then
    return;
  end if;

  update duc_lich_su_san_xuat
  set tt_ca = greatest(0, coalesce(tt_ca, 0) + p_delta)
  where ngay = v_ls.ngay and ca = v_ls.ca and ma_may = p_ma_may and ma_sp = p_ma_sp;

  update duc_bao_cao_ca b set
    tong_tt_ca = greatest(0, coalesce(b.tong_tt_ca, 0) + p_delta),
    ty_le_hoan_thanh_ca = case when coalesce(b.tong_kh_ca, 0) > 0
      then greatest(0, coalesce(b.tong_tt_ca, 0) + p_delta) / b.tong_kh_ca else 0 end,
    so_may_hoan_thanh_kh = (
      select count(*) filter (where dat) from (
        select bool_and(coalesce(tt_ca, 0) >= coalesce(kh_ca, 0)) as dat
        from duc_lich_su_san_xuat
        where ngay = v_ls.ngay and ca = v_ls.ca
        group by ma_may
      ) m
    )
  where b.ngay = v_ls.ngay and b.ca = v_ls.ca;
end;
$$;

create or replace function duc_tem_sync_lich_su_trigger()
returns trigger
language plpgsql
security definer
as $$
begin
  if TG_OP = 'DELETE' then
    perform duc_ls_dieu_chinh_tem(OLD.may_tt, OLD.ma_sp,
      coalesce(OLD.ngay_gio_ghi_nhan, OLD.ngay_gio_in), -coalesce(OLD.so_luong_tt, 0));
    return OLD;
  end if;

  if OLD.so_luong_tt is distinct from NEW.so_luong_tt
     or OLD.may_tt is distinct from NEW.may_tt
     or OLD.ma_sp is distinct from NEW.ma_sp
     or coalesce(OLD.ngay_gio_ghi_nhan, OLD.ngay_gio_in) is distinct from coalesce(NEW.ngay_gio_ghi_nhan, NEW.ngay_gio_in)
  then
    perform duc_ls_dieu_chinh_tem(OLD.may_tt, OLD.ma_sp,
      coalesce(OLD.ngay_gio_ghi_nhan, OLD.ngay_gio_in), -coalesce(OLD.so_luong_tt, 0));
    perform duc_ls_dieu_chinh_tem(NEW.may_tt, NEW.ma_sp,
      coalesce(NEW.ngay_gio_ghi_nhan, NEW.ngay_gio_in), coalesce(NEW.so_luong_tt, 0));
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_duc_tem_sync_lich_su on duc_tem;
create trigger trg_duc_tem_sync_lich_su
  after update or delete on duc_tem
  for each row execute function duc_tem_sync_lich_su_trigger();
