-- ============================================================================
-- D70 — Mã SP chỉ thị sản xuất bằng Kanban: CHẶN in tem thủ công.
--
-- master_products.chi_thi_kanban = true → sản lượng mã này CHỈ ghi nhận bằng
-- quét QR tem chỉ thị Kanban (tạo lô ở intem.html tab "Chỉ thị SX", quét ở
-- ghi-nhan-tem-thanh-pham.html). duc_ghi_tem (tab "In Tem" thủ công) từ chối
-- mã này — chặn ở server, không chỉ ở giao diện.
--
-- Không ảnh hưởng: duc_tao_lo_kanban, duc_ghi_nhan_tem_kanban, tách tem,
-- tem thành phẩm các công đoạn sau.
-- Bật/tắt cờ ở Danh mục SP (quan-ly-danh-muc.html).
-- An toàn chạy lại nhiều lần.
-- ============================================================================

alter table master_products
  add column if not exists chi_thi_kanban boolean not null default false;

create or replace function public.duc_ghi_tem(p_loai_sp text, p_ten_sp text, p_ma_sp text, p_so_luong numeric, p_ngay date, p_lot text, p_so_khuon text, p_nguyen_lieu text, p_may_duc text, p_ghi_chu text, p_ngay_gio_in timestamp with time zone, p_nguoi_tt text)
returns text
language plpgsql
security definer
as $function$
declare
  v_tag_no text;
begin
  if exists (select 1 from master_products where ma_sp = p_ma_sp and chi_thi_kanban) then
    raise exception 'Mã % chỉ thị sản xuất bằng Kanban — không in tem thủ công. Quét QR tem chỉ thị Kanban để ghi nhận sản lượng.', p_ma_sp
      using errcode = 'P0001';
  end if;

  v_tag_no := duc_next_tag_no(p_loai_sp);
  insert into duc_tem (
    tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
    may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
    nguoi_tt, ngay_gio_xuat, nguoi_nhan, trang_thai, ghi_chu2, ng, ghi_chu_sl
  ) values (
    v_tag_no, p_ten_sp, p_ma_sp, p_so_luong, p_ngay, coalesce(p_lot, p_ngay::text), p_so_khuon, p_nguyen_lieu,
    p_may_duc, p_ghi_chu, p_ngay_gio_in, p_so_khuon, p_so_luong, p_may_duc,
    p_nguoi_tt, null, null, 'Đã đúc', null, null, 'Chờ chốt sản lượng'
  );
  return v_tag_no;
end;
$function$;

-- Giữ quyền như cũ (create or replace không đổi grant, ghi lại cho rõ).
revoke execute on function duc_ghi_tem(text, text, text, numeric, date, text, text, text, text, text, timestamptz, text) from public, anon;
grant execute on function duc_ghi_tem(text, text, text, numeric, date, text, text, text, text, text, timestamptz, text) to authenticated;

-- Bật cho các mã đang chạy Kanban (user chọn 2026-10-17).
update master_products set chi_thi_kanban = true
where ma_sp in ('EXE-SHO-01', 'BPH-SHO-01', 'BPH-SHO-02', 'BPH-SHO-03', 'YHS-HAN-01')
  and not chi_thi_kanban;
