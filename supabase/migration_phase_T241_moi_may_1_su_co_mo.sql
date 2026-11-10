-- T241 (10/11/2026): quay lại MỖI MÁY CHỈ 1 SỰ CỐ MỞ — đóng sự cố đang mở rồi mới mở được sự cố mới.
-- ĐÃ CHẠY: DB staging + DB prod 10/11/2026.
-- Bỏ quy tắc "tối đa 3 sự cố mở / máy" của T178/T179 (trưởng ca phản ánh: sự cố khuôn cũ chưa xong,
-- máy đã đổi sang khuôn mới → sự cố treo, không đóng được).
--
-- Chỉ CHẶN MỞ THÊM. Giữ nguyên bảng duc_su_co_mo_them và các hàm *_x / đổi chỗ / đưa sự cố phụ lên
-- chỗ chính, để sự cố phụ còn sót (nếu có) vẫn sửa / đóng được bình thường.
--   A. duc_set_incident_open: máy đang có sự cố mở → từ chối.
--   B. duc_submit_ipqc_check: IPQC định kỳ NG khi máy đang có sự cố khác → KHÔNG tự mở F1 phụ nữa
--      (như trước T179: ghi chú "cần trưởng ca xử lý thủ công").
-- Chạy lại nhiều lần được.

-- ── A. Mở sự cố ──────────────────────────────────────────────────────────────
create or replace function public.duc_set_incident_open(p_id_dong text, p_loai text, p_gio_phat_sinh timestamptz, p_van_de text, p_noi_dung_xu_ly text, p_dam_nhiem text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_current record;
  v_new_version bigint;
  v_id_su_co text;
begin
  select ma_may, open_gio_phat_sinh, open_id_su_co, open_loai_su_co, version into v_current from duc_ca_hien_tai where id_dong = p_id_dong for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng: ' || p_id_dong);
  end if;

  -- T241: mỗi máy chỉ 1 sự cố mở
  if v_current.open_gio_phat_sinh is not null then
    return jsonb_build_object('ok', false, 'error',
      'Máy ' || coalesce(v_current.ma_may, '') || ' đang có sự cố mở'
      || coalesce(' (' || nullif(v_current.open_id_su_co, '') || coalesce(' · ' || nullif(split_part(v_current.open_loai_su_co, ' ', 1), ''), '') || ')', '')
      || '. Đóng sự cố đó rồi mới mở được sự cố mới.');
  end if;

  v_id_su_co := duc_id_su_co_moi(v_current.ma_may, p_gio_phat_sinh);
  v_new_version := coalesce(v_current.version, 0) + 1;

  update duc_ca_hien_tai set
    open_loai_su_co = p_loai, open_gio_phat_sinh = p_gio_phat_sinh,
    open_van_de = coalesce(p_van_de, ''), open_noi_dung_xu_ly = coalesce(p_noi_dung_xu_ly, ''),
    open_dam_nhiem = coalesce(p_dam_nhiem, ''), open_id_su_co = v_id_su_co,
    version = v_new_version, last_updated_by = coalesce(p_dam_nhiem, 'system'), last_updated_at = now()
  where id_dong = p_id_dong;

  return jsonb_build_object('ok', true, 'id_dong', p_id_dong, 'version', v_new_version, 'id_su_co', v_id_su_co);
end $$;

-- ── B. IPQC NG khi máy đang có sự cố → không tự mở F1 ─────────────────────────
do $$
declare
  d text; a int; b int;
  m_dau text := '    -- T179: máy đang có sự cố khác';
  m_cuoi text := 'else ''Không mở thêm sự cố F1 — máy đã có sự cố F1 đang mở.'' end;';
  moi text := $moi$    -- T241: mỗi máy chỉ 1 sự cố mở — máy đang có sự cố thì không tự mở thêm F1.
    if v_cht.open_gio_phat_sinh is not null then
      v_note := case
        when v_cp.loai_kiem in ('sau_su_co', 'doi_khuon') then 'Không mở thêm sự cố F1 — máy đang dừng vì sự cố chờ IPQC; sự cố đó chỉ kết thúc được khi IPQC kiểm lại OK / Cảnh báo.'
        when left(coalesce(v_cht.open_loai_su_co, ''), 2) = 'F1' then 'Không mở thêm sự cố F1 — máy đã có sự cố F1 đang mở.'
        else 'Không tự mở sự cố F1 được — máy đang có sự cố khác mở (mỗi máy chỉ 1 sự cố mở). Cần trưởng ca xử lý thủ công.' end;$moi$;
begin
  d := replace(pg_get_functiondef('public.duc_submit_ipqc_check'::regproc), E'\r\n', E'\n');
  if strpos(d, 'T241') > 0 then return; end if;
  a := strpos(d, m_dau);
  b := strpos(d, m_cuoi);
  if a = 0 or b = 0 or b < a then raise exception 'T241: không vá được duc_submit_ipqc_check (a=%, b=%)', a, b; end if;
  d := substr(d, 1, a - 1) || replace(moi, E'\r\n', E'\n') || substr(d, b + length(m_cuoi));
  execute d;
end $$;
