-- ============================================================================
-- Phase T4 — Thêm KH ca (pcs) cho từng trạm/line/máy/bàn kiểm đang chạy 1 mã
-- SP. Tên gọi đơn vị (Line/Máy/Bàn kiểm) chỉ đổi ở giao diện
-- (cong-doan-dashboard.html), KHÔNG đổi tên cột/bảng — cd_tram_hien_tai vẫn
-- dùng chung 1 cấu trúc cho cả 4 công đoạn.
--
-- Phải DROP rồi tạo lại cd_tram_tao/cd_tram_doi_ma_sp vì CREATE OR REPLACE
-- không cho phép thêm tham số mới (đổi identity của hàm).
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

alter table cd_tram_hien_tai add column if not exists kh_ca numeric;

drop function if exists cd_tram_tao(date, text, text, text, text, text, text, text);
create or replace function cd_tram_tao(
  p_ngay date, p_ca text, p_cong_doan text, p_ten_tram text, p_ma_sp text, p_ten_sp text,
  p_kh_ca numeric, p_nguoi text, p_user text
)
returns text
language plpgsql
security definer
as $$
declare
  v_id text;
begin
  if p_ten_tram is null or trim(p_ten_tram) = '' then raise exception 'Thiếu tên'; end if;
  if p_ma_sp is null or trim(p_ma_sp) = '' then raise exception 'Thiếu mã SP'; end if;
  v_id := duc_normalize_name(p_cong_doan) || '_' || to_char(p_ngay, 'DDMMYYYY') || '_' || duc_normalize_name(p_ca) || '_' || duc_normalize_name(p_ten_tram);

  insert into cd_tram_hien_tai (id_tram, ngay, ca, cong_doan, ten_tram, ma_sp, ten_sp, kh_ca, nguoi_thao_tac, version, last_updated_by, last_updated_at)
  values (v_id, p_ngay, p_ca, p_cong_doan, trim(p_ten_tram), p_ma_sp, coalesce(p_ten_sp, ''), p_kh_ca, coalesce(p_nguoi, ''), 1, p_user, now())
  on conflict (id_tram) do update set
    ma_sp = excluded.ma_sp, ten_sp = excluded.ten_sp, kh_ca = excluded.kh_ca, nguoi_thao_tac = excluded.nguoi_thao_tac,
    version = cd_tram_hien_tai.version + 1, last_updated_by = excluded.last_updated_by, last_updated_at = now();

  return v_id;
end;
$$;
revoke execute on function cd_tram_tao(date, text, text, text, text, text, numeric, text, text) from anon;
grant execute on function cd_tram_tao(date, text, text, text, text, text, numeric, text, text) to authenticated;

drop function if exists cd_tram_doi_ma_sp(text, text, text, text, text);
create or replace function cd_tram_doi_ma_sp(
  p_id_tram text, p_ma_sp_moi text, p_ten_sp_moi text, p_kh_ca_moi numeric, p_nguoi_moi text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row cd_tram_hien_tai%rowtype;
begin
  if p_ma_sp_moi is null or trim(p_ma_sp_moi) = '' then raise exception 'Thiếu mã SP mới'; end if;

  select * into v_row from cd_tram_hien_tai where id_tram = p_id_tram for update;
  if not found then raise exception 'Không tìm thấy: %', p_id_tram; end if;

  if coalesce(v_row.so_luong_ok, 0) > 0 or coalesce(v_row.so_luong_ng, 0) > 0 then
    perform cd_gop_tally_vao_bao_cao(v_row.ngay, v_row.ca, v_row.cong_doan, v_row.ma_sp, v_row.ten_sp, v_row.ten_tram, v_row.so_luong_ok, v_row.so_luong_ng, v_row.ghi_chu);
  end if;

  update cd_tram_hien_tai set
    ma_sp = p_ma_sp_moi, ten_sp = coalesce(p_ten_sp_moi, ''), kh_ca = p_kh_ca_moi,
    nguoi_thao_tac = coalesce(nullif(p_nguoi_moi, ''), nguoi_thao_tac),
    so_luong_ok = 0, so_luong_ng = 0, ghi_chu = '',
    version = version + 1, last_updated_by = p_user, last_updated_at = now()
  where id_tram = p_id_tram;

  return jsonb_build_object('ok', true, 'id_tram', p_id_tram);
end;
$$;
revoke execute on function cd_tram_doi_ma_sp(text, text, text, numeric, text, text) from anon;
grant execute on function cd_tram_doi_ma_sp(text, text, text, numeric, text, text) to authenticated;
