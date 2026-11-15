-- T274: Kho dao cụ Gia công — Đợt 3: báo cáo (chi phí dao / chi tiết, tuổi thọ thực tế so chuẩn).
-- Báo cáo tính ở trình duyệt từ gc_dao_tren_may_v, gc_dao_cu_giao_dich, gc_tem_buoc (không thêm bảng).
-- DB chỉ thêm 1 RPC: áp dụng tuổi thọ chuẩn gợi ý (quản lý).
--   * Có dòng bộ dao chuẩn đúng (mã SP, bước, vị trí, mã dao) → sửa tuổi thọ ở bộ dao.
--   * Không có → sửa tuổi thọ chuẩn mặc định ở danh mục dao.
-- An toàn chạy lại.
-- Trạng thái: Đã chạy STAGING + PROD 15/11/2026.

create or replace function public.gc_dao_dat_tuoi_tho(p_ma_sp text, p_buoc integer, p_vi_tri text, p_id_dao bigint, p_tuoi_tho integer)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_me record; v_n int := 0;
begin
  select * into v_me from gc_dao_cu_nguoi('quan_ly');
  if v_me.o_loi is not null then return jsonb_build_object('ok', false, 'error', v_me.o_loi); end if;
  if coalesce(p_tuoi_tho, 0) <= 0 then return jsonb_build_object('ok', false, 'error', 'Tuổi thọ phải > 0'); end if;
  if not exists (select 1 from gc_dao_cu where id = p_id_dao) then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy mã dao');
  end if;
  update gc_bo_dao set tuoi_tho_chuan = p_tuoi_tho, updated_at = now(), updated_by = v_me.o_ten
  where ma_sp = trim(coalesce(p_ma_sp, '')) and buoc = coalesce(p_buoc, 1)
    and vi_tri = upper(trim(coalesce(p_vi_tri, ''))) and id_dao = p_id_dao;
  get diagnostics v_n = row_count;
  if v_n > 0 then return jsonb_build_object('ok', true, 'noi', 'bo'); end if;
  update gc_dao_cu set tuoi_tho_chuan = p_tuoi_tho, updated_at = now() where id = p_id_dao;
  return jsonb_build_object('ok', true, 'noi', 'danh_muc');
end $$;
revoke execute on function public.gc_dao_dat_tuoi_tho(text, integer, text, bigint, integer) from public, anon;
grant execute on function public.gc_dao_dat_tuoi_tho(text, integer, text, bigint, integer) to authenticated;
