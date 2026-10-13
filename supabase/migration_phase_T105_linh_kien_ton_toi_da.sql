-- ============================================================================
-- T105 — Linh kiện dự phòng khuôn: thêm "Tồn tối đa" (user 2026-10-13, khi
-- nhập danh sách linh kiện khuôn FCC). "Số lượng xin cấp" KHÔNG lưu (user bỏ).
--
--   - khuon_lk_danh_muc.ton_toi_da (null = chưa đặt), phải ≥ tồn tối thiểu.
--   - khuon_lk_luu: ghi ton_toi_da; key không có trong p_data (file Excel mẫu
--     cũ) thì giữ nguyên giá trị đang có khi cập nhật.
--   khuon_lk_nhap_excel truyền nguyên dòng vào khuon_lk_luu nên không cần sửa.
--
-- Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

alter table khuon_lk_danh_muc add column if not exists ton_toi_da numeric check (ton_toi_da is null or ton_toi_da >= 0);

create or replace function khuon_lk_luu(p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me record; v_id bigint := nullif(p_data->>'id', '')::bigint;
  v_ma text := trim(coalesce(p_data->>'ma_lk', ''));
  v_ten text := trim(coalesce(p_data->>'ten_lk', ''));
  v_co_max boolean := p_data ? 'ton_toi_da';
  v_max numeric := nullif(trim(coalesce(p_data->>'ton_toi_da', '')), '')::numeric;
  v_min numeric := coalesce(nullif(p_data->>'ton_toi_thieu', '')::numeric, 0);
begin
  select * into v_me from khuon_lk_nguoi('quan_ly');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if v_ma = '' or v_ten = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã / tên linh kiện'); end if;
  if exists (select 1 from khuon_lk_danh_muc where lower(ma_lk) = lower(v_ma) and id is distinct from v_id) then
    return jsonb_build_object('ok', false, 'error', 'Mã linh kiện đã tồn tại: ' || v_ma);
  end if;
  if v_max is not null and v_max < v_min then
    return jsonb_build_object('ok', false, 'error', 'Tồn tối đa (' || v_max || ') nhỏ hơn tồn tối thiểu (' || v_min || ')');
  end if;
  if v_id is null then
    insert into khuon_lk_danh_muc (ma_lk, ten_lk, loai, pham_vi, quy_cach, vat_lieu, ban_ve, nha_cung_cap,
      lead_time_ngay, tuoi_tho_shot, sua_duoc, don_vi, vi_tri_kho, ton_toi_thieu, ton_toi_da, ghi_chu, dang_dung, created_by, updated_by)
    values (v_ma, v_ten, coalesce(nullif(p_data->>'loai', ''), 'khac'), coalesce(nullif(p_data->>'pham_vi', ''), 'rieng'),
      trim(coalesce(p_data->>'quy_cach', '')), trim(coalesce(p_data->>'vat_lieu', '')), trim(coalesce(p_data->>'ban_ve', '')),
      trim(coalesce(p_data->>'nha_cung_cap', '')), nullif(p_data->>'lead_time_ngay', '')::int, nullif(p_data->>'tuoi_tho_shot', '')::int,
      coalesce((p_data->>'sua_duoc')::boolean, false), coalesce(nullif(trim(p_data->>'don_vi'), ''), 'cái'),
      trim(coalesce(p_data->>'vi_tri_kho', '')), v_min, v_max,
      trim(coalesce(p_data->>'ghi_chu', '')), coalesce((p_data->>'dang_dung')::boolean, true), v_me.o_ten, v_me.o_ten)
    returning id into v_id;
  else
    if not v_co_max then
      select ton_toi_da into v_max from khuon_lk_danh_muc where id = v_id;
      if v_max is not null and v_max < v_min then
        return jsonb_build_object('ok', false, 'error', 'Tồn tối thiểu (' || v_min || ') lớn hơn tồn tối đa đang có (' || v_max || ')');
      end if;
    end if;
    update khuon_lk_danh_muc set
      ma_lk = v_ma, ten_lk = v_ten, loai = coalesce(nullif(p_data->>'loai', ''), loai),
      pham_vi = coalesce(nullif(p_data->>'pham_vi', ''), pham_vi),
      quy_cach = trim(coalesce(p_data->>'quy_cach', '')), vat_lieu = trim(coalesce(p_data->>'vat_lieu', '')),
      ban_ve = trim(coalesce(p_data->>'ban_ve', '')), nha_cung_cap = trim(coalesce(p_data->>'nha_cung_cap', '')),
      lead_time_ngay = nullif(p_data->>'lead_time_ngay', '')::int, tuoi_tho_shot = nullif(p_data->>'tuoi_tho_shot', '')::int,
      sua_duoc = coalesce((p_data->>'sua_duoc')::boolean, sua_duoc), don_vi = coalesce(nullif(trim(p_data->>'don_vi'), ''), don_vi),
      vi_tri_kho = trim(coalesce(p_data->>'vi_tri_kho', '')), ton_toi_thieu = v_min, ton_toi_da = v_max,
      ghi_chu = trim(coalesce(p_data->>'ghi_chu', '')), dang_dung = coalesce((p_data->>'dang_dung')::boolean, dang_dung),
      updated_at = now(), updated_by = v_me.o_ten
    where id = v_id;
    if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy linh kiện'); end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
exception when check_violation or invalid_text_representation then
  return jsonb_build_object('ok', false, 'error', 'Dữ liệu không hợp lệ: ' || sqlerrm);
end $$;
revoke execute on function khuon_lk_luu(jsonb) from public, anon;
grant execute on function khuon_lk_luu(jsonb) to authenticated;
