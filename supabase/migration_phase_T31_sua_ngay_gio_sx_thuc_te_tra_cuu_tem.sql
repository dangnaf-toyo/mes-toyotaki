-- ============================================================================
-- Phase T31 — Cho phép sửa "Ngày giờ SX thực tế" (duc_tem.ngay_gio_ghi_nhan)
-- ngay trên màn hình tra-cuu-tem.html.
--
-- duc_tem chỉ có RLS đọc công khai, KHÔNG mở ghi trực tiếp (schema_duc.sql) —
-- mọi thao tác ghi đi qua RPC security definer / Apps Script. Thêm 1 RPC nhỏ
-- để trang tra cứu cập nhật đúng 1 cột thời điểm ghi nhận SX thực tế. Bất kỳ
-- tài khoản đăng nhập nào cũng gọi được (đồng nhất với các thao tác nhập liệu
-- khác hiện thời).
--
-- LƯU Ý side-effect: trigger trg_duc_tem_sync_actuals (D22) chạy AFTER UPDATE
-- trên duc_tem → gọi lại duc_recompute_tt_ca(may_tt, ma_sp). Nếu cặp (máy, mã
-- SP) của tem đang có DÒNG SẢN XUẤT CHẠY, tt_ca của ca đó được tính lại theo
-- mốc mới (D48: cửa sổ ca dùng coalesce(ngay_gio_ghi_nhan, ngay_gio_in)).
-- KHÔNG hồi tố báo cáo ca đã "Kết ca" — chỉ ảnh hưởng số liệu ca đang mở.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create or replace function duc_tem_sua_ngay_gio_ghi_nhan(
  p_tag_no text, p_ngay_gio timestamptz
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_old timestamptz;
begin
  if p_tag_no is null or trim(p_tag_no) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu Tag No');
  end if;
  if p_ngay_gio is null then
    return jsonb_build_object('ok', false, 'error', 'Thiếu ngày giờ');
  end if;
  if p_ngay_gio > now() + interval '1 minute' then
    return jsonb_build_object('ok', false, 'error', 'Ngày giờ SX thực tế không được ở tương lai');
  end if;

  select ngay_gio_ghi_nhan into v_old from duc_tem where tag_no = p_tag_no;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem: ' || p_tag_no);
  end if;

  update duc_tem set ngay_gio_ghi_nhan = p_ngay_gio where tag_no = p_tag_no;

  return jsonb_build_object('ok', true, 'tag_no', p_tag_no, 'cu', v_old, 'moi', p_ngay_gio);
end;
$$;
revoke execute on function duc_tem_sua_ngay_gio_ghi_nhan(text, timestamptz) from anon;
grant execute on function duc_tem_sua_ngay_gio_ghi_nhan(text, timestamptz) to authenticated;
