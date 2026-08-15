-- ============================================================================
-- Giai đoạn 15 — Sổ đời khuôn mở rộng (Nhóm 5 KE_HOACH_TINH_NANG_MOI.md).
--
-- Trước đây `duc_record_mold_maintenance` chỉ ghi ĐÈ lên 1 dòng tóm tắt của
-- duc_shot_khuon (lan_bao_duong_gan_nhat/shot_tai_lan_bao_duong_gan_nhat) và
-- gộp mọi ghi chú vào 1 cột text ngày càng dài — không tra được lịch sử từng
-- lần bảo dưỡng/sửa chữa, không có chi phí, không phân biệt "bảo dưỡng định
-- kỳ" (reset đồng hồ đếm shot) với "sửa chữa nhỏ" (chỉ ghi log, không reset).
--
-- Nay: bảng `duc_khuon_bao_duong_log` lưu TỪNG lần bảo dưỡng/sửa chữa/thay
-- mới (loại, ngày, shot tại thời điểm, người thực hiện, mô tả, chi phí, thời
-- gian dừng máy, liên kết vấn đề khuôn gốc nếu có). Thêm cột
-- `chu_ky_bao_duong_ngay` cho lịch bảo dưỡng THEO THỜI GIAN (bổ sung cho
-- ngưỡng theo số shot đã có) — hạn bảo dưỡng tiếp theo = lan_bao_duong_gan_nhat
-- + chu_ky_bao_duong_ngay, tính lúc hiển thị, không lưu cột riêng để tránh
-- lệch dữ liệu.
--
-- Chỉ "Bảo dưỡng định kỳ" và "Thay khuôn mới" mới reset đồng hồ đếm shot kể
-- từ lần bảo dưỡng gần nhất — "Sửa chữa" chỉ ghi lại lịch sử, không reset (vì
-- không phải bảo dưỡng theo lịch, khuôn vẫn cần bảo dưỡng đúng hạn cũ).
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

alter table duc_shot_khuon add column if not exists chu_ky_bao_duong_ngay numeric;

create table if not exists duc_khuon_bao_duong_log (
  id_log               text primary key,
  ma_khuon             text not null,
  loai                 text not null,   -- 'Bảo dưỡng định kỳ' | 'Sửa chữa' | 'Thay khuôn mới'
  ngay                 date not null,
  shot_tai_thoi_diem   numeric,
  nguoi_thuc_hien      text,
  mo_ta                text,
  chi_phi              numeric,
  thoi_gian_dung_phut  numeric,
  id_van_de_lien_quan  text,
  thoi_diem_ghi        timestamptz default now()
);
create index if not exists idx_khuon_bd_log_ma_khuon on duc_khuon_bao_duong_log (ma_khuon, ngay desc);

alter table duc_khuon_bao_duong_log enable row level security;
drop policy if exists "public read" on duc_khuon_bao_duong_log;
create policy "public read" on duc_khuon_bao_duong_log for select using (true);

-- ── duc_ghi_lich_su_bao_duong — ghi 1 lần bảo dưỡng/sửa chữa/thay mới ───────
create or replace function duc_ghi_lich_su_bao_duong(
  p_ma_khuon text, p_loai text, p_ngay date, p_mo_ta text, p_chi_phi numeric,
  p_thoi_gian_dung_phut numeric, p_id_van_de_lien_quan text,
  p_nguong_bao_duong_moi numeric, p_nguong_lam_moi_moi numeric, p_chu_ky_ngay_moi numeric,
  p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row record;
  v_now timestamptz := now();
  v_id text;
  v_ngay date;
  v_nguong_bd numeric;
  v_nguong_lm numeric;
  v_chu_ky numeric;
  v_reset_clock boolean;
  v_shot_bdgn numeric;
begin
  if p_ma_khuon is null or trim(p_ma_khuon) = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã khuôn'); end if;
  if p_loai not in ('Bảo dưỡng định kỳ', 'Sửa chữa', 'Thay khuôn mới') then
    return jsonb_build_object('ok', false, 'error', 'Loại phải là Bảo dưỡng định kỳ / Sửa chữa / Thay khuôn mới');
  end if;

  select * into v_row from duc_shot_khuon where ma_khuon = trim(p_ma_khuon);
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy khuôn: ' || p_ma_khuon); end if;

  v_ngay := coalesce(p_ngay, v_now::date);
  v_id := 'BD-' || duc_normalize_name(p_ma_khuon) || '-' || to_char(v_now, 'YYYYMMDDHH24MISS');

  insert into duc_khuon_bao_duong_log (
    id_log, ma_khuon, loai, ngay, shot_tai_thoi_diem, nguoi_thuc_hien, mo_ta,
    chi_phi, thoi_gian_dung_phut, id_van_de_lien_quan, thoi_diem_ghi
  ) values (
    v_id, trim(p_ma_khuon), p_loai, v_ngay, coalesce(v_row.tong_shot_luy_ke, 0), p_user, p_mo_ta,
    p_chi_phi, p_thoi_gian_dung_phut, nullif(trim(coalesce(p_id_van_de_lien_quan, '')), ''), v_now
  );

  v_nguong_bd := coalesce(p_nguong_bao_duong_moi, v_row.nguong_bao_duong, 10000);
  v_nguong_lm := coalesce(p_nguong_lam_moi_moi, v_row.nguong_lam_moi, 100000);
  v_chu_ky := coalesce(p_chu_ky_ngay_moi, v_row.chu_ky_bao_duong_ngay);
  v_reset_clock := p_loai in ('Bảo dưỡng định kỳ', 'Thay khuôn mới');
  v_shot_bdgn := case when v_reset_clock then coalesce(v_row.tong_shot_luy_ke, 0) else coalesce(v_row.shot_tai_lan_bao_duong_gan_nhat, 0) end;

  update duc_shot_khuon set
    lan_bao_duong_gan_nhat = case when v_reset_clock then v_ngay else lan_bao_duong_gan_nhat end,
    shot_tai_lan_bao_duong_gan_nhat = case when v_reset_clock then coalesce(v_row.tong_shot_luy_ke, 0) else shot_tai_lan_bao_duong_gan_nhat end,
    nguong_bao_duong = v_nguong_bd, nguong_lam_moi = v_nguong_lm, chu_ky_bao_duong_ngay = v_chu_ky,
    trang_thai_khuon = duc_compute_mold_status(coalesce(v_row.tong_shot_luy_ke, 0), v_shot_bdgn, v_nguong_bd, v_nguong_lm),
    last_updated_at = v_now
  where ma_khuon = trim(p_ma_khuon);

  return jsonb_build_object('ok', true, 'id_log', v_id, 'ma_khuon', trim(p_ma_khuon), 'shot_tai_thoi_diem', coalesce(v_row.tong_shot_luy_ke, 0), 'reset_dong_ho', v_reset_clock);
end;
$$;
revoke execute on function duc_ghi_lich_su_bao_duong(text, text, date, text, numeric, numeric, text, numeric, numeric, numeric, text) from anon;
grant execute on function duc_ghi_lich_su_bao_duong(text, text, date, text, numeric, numeric, text, numeric, numeric, numeric, text) to authenticated;
