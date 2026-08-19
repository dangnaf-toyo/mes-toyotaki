-- ============================================================================
-- Phase T15 — Nút "Sửa" cho trạm/line/máy/bàn kiểm đang chạy ở
-- cong-doan-dashboard.html: chỉ sửa "Người thao tác" và "KH ca", KHÔNG đụng
-- tới mã SP/sản lượng OK-NG đang cộng dồn.
--
-- Trước đây muốn thêm/sửa người thao tác sau khi đã tạo trạm chỉ có cách
-- dùng "Đổi mã SP" (cd_tram_doi_ma_sp) — nhưng hàm đó BẮT BUỘC nhập mã SP
-- mới và LUÔN gộp sản lượng vào báo cáo rồi reset OK/NG về 0 (đúng ý nghĩa
-- "đổi sang SP khác"), dùng sai mục đích nếu chỉ muốn gõ thêm tên người
-- đứng máy — sẽ làm mất sản lượng đang đếm dở của ca. Cần 1 đường update
-- nhẹ, không có tác dụng phụ.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create or replace function cd_tram_sua(
  p_id_tram text, p_nguoi_moi text, p_kh_ca_moi numeric, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
begin
  if not exists (select 1 from cd_tram_hien_tai where id_tram = p_id_tram) then
    raise exception 'Không tìm thấy: %', p_id_tram;
  end if;

  update cd_tram_hien_tai set
    nguoi_thao_tac = coalesce(p_nguoi_moi, ''), kh_ca = p_kh_ca_moi,
    version = version + 1, last_updated_by = p_user, last_updated_at = now()
  where id_tram = p_id_tram;

  return jsonb_build_object('ok', true, 'id_tram', p_id_tram);
end;
$$;
revoke execute on function cd_tram_sua(text, text, numeric, text) from anon;
grant execute on function cd_tram_sua(text, text, numeric, text) to authenticated;
