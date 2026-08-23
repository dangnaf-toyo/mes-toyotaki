-- ============================================================================
-- Phase T22 — Chuyển công đoạn: "Người giao" chọn trong danh sách tài khoản hệ
-- thống (không phải danh mục nhân viên tự do), "Người nhận" cố định = tài
-- khoản đang đăng nhập (đã tự chọn sẵn từ trước ở frontend), và thêm cột
-- "Ghi chú" lưu vào database.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
--
-- Vì sao cần 1 hàm riêng thay vì SELECT thẳng bảng user_roles: RLS của
-- user_roles (migration S1) chỉ cho phép user đọc ĐÚNG dòng của chính mình
-- (hoặc admin đọc hết) — 1 công nhân bình thường KHÔNG tự query được toàn bộ
-- danh sách tài khoản để làm dropdown "Người giao". Hàm SECURITY DEFINER dưới
-- đây chỉ trả về đúng 1 cột "identity" (định dạng MãNV_TênNV, giống hệt
-- MesAuth.getCurrentUserIdentity() đang dùng khắp nơi) — không lộ email/vai
-- trò/user_id của người khác.
-- ============================================================================

create or replace function public.danh_sach_nguoi_dung_he_thong()
returns table(identity text)
language sql
security definer
stable
set search_path = public
as $$
  select
    case
      when nullif(trim(username), '') is not null and nullif(trim(full_name), '') is not null
        then trim(username) || '_' || trim(full_name)
      else coalesce(nullif(trim(username), ''), nullif(trim(full_name), ''))
    end as identity
  from public.user_roles
  where coalesce(nullif(trim(username), ''), nullif(trim(full_name), '')) is not null
  order by coalesce(nullif(trim(full_name), ''), nullif(trim(username), ''));
$$;

grant execute on function public.danh_sach_nguoi_dung_he_thong() to authenticated;

-- ── Ghi chú (mới) ────────────────────────────────────────────────────────
alter table public.cd_chuyen_cong_doan_log add column if not exists ghi_chu text;

-- cd_ghi_chuyen_cong_doan thêm tham số p_ghi_chu (mặc định null, không phá
-- lời gọi cũ nếu còn nơi nào chưa cập nhật) — drop chữ ký cũ trước để không
-- tồn tại song song 2 bản overload.
drop function if exists cd_ghi_chuyen_cong_doan(
  text, text, text, numeric, numeric, text, text, text, text, text, text, text, text, text
);

create or replace function cd_ghi_chuyen_cong_doan(
  p_tag_no text, p_ma_sp text, p_ten_sp text,
  p_sl_tren_tem numeric, p_sl_thuc_chuyen numeric,
  p_lot_no text, p_so_khuon text, p_nguyen_lieu text, p_may_duc text, p_ngay_duc text,
  p_cong_doan_giao text, p_cong_doan_nhan text,
  p_nguoi_giao text, p_nguoi_nhan text,
  p_ghi_chu text default null
)
returns table(id_phieu text, thoi_gian_chuyen timestamptz, chenh_lech numeric)
language plpgsql
security definer
as $$
declare
  v_id text := cd_next_transfer_id();
  v_now timestamptz := now();
  v_chenh_lech numeric := p_sl_tren_tem - p_sl_thuc_chuyen;
begin
  insert into cd_chuyen_cong_doan_log (
    id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp,
    sl_tren_tem, sl_thuc_chuyen, chenh_lech,
    lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc,
    cong_doan_giao, cong_doan_nhan, nguoi_giao, nguoi_nhan,
    ghi_chu, trang_thai_xac_nhan
  ) values (
    v_id, v_now, p_tag_no, p_ma_sp, p_ten_sp,
    p_sl_tren_tem, p_sl_thuc_chuyen, v_chenh_lech,
    p_lot_no, p_so_khuon, p_nguyen_lieu, p_may_duc, p_ngay_duc,
    p_cong_doan_giao, p_cong_doan_nhan, p_nguoi_giao, p_nguoi_nhan,
    nullif(trim(p_ghi_chu), ''), 'Chờ công đoạn trước xác nhận'
  );
  return query select v_id, v_now, v_chenh_lech;
end;
$$;

revoke execute on function cd_ghi_chuyen_cong_doan(
  text, text, text, numeric, numeric, text, text, text, text, text, text, text, text, text, text
) from anon;
grant execute on function cd_ghi_chuyen_cong_doan(
  text, text, text, numeric, numeric, text, text, text, text, text, text, text, text, text, text
) to authenticated;
