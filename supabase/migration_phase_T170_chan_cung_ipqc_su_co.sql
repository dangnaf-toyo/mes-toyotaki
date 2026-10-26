-- ============================================================================
-- Phase T170 — CHẶN CỨNG: sự cố loại A1/A2/A3/B1/B2/C3/E1/F1 chỉ kết thúc được
-- (máy chạy lại) khi kết quả IPQC MỚI NHẤT của lần kiểm sau sự cố / đổi khuôn là OK.
-- Trước đây (D13) chỉ cảnh báo sau khi đã đóng; bản mobile không cảnh báo gì.
--
-- 1) duc_ipqc_trang_thai_su_co(p_id_dong) — helper nội bộ: kết quả IPQC mới nhất của
--    sự cố đang mở. Khớp checkpoint 'sau_su_co'/'doi_khuon' đã kiểm theo:
--      - đúng mã sự cố (id_su_co_goc = open_id_su_co), HOẶC
--      - cùng máy và kiểm SAU giờ phát sinh sự cố.
--    Vế 2 cần vì duc_request_ipqc_check không tạo checkpoint mới khi dòng đã có 1
--    checkpoint cùng loại đang chờ (sự cố thứ 2 dùng chung checkpoint của sự cố 1),
--    và vì sự cố vắt ca có id_dong mới (25/102 sự cố 7 ngày tới 26/10 không có
--    checkpoint gắn đúng mã → nếu chỉ khớp mã thì sẽ kẹt vĩnh viễn).
-- 2) duc_resolve_incident — chưa OK thì trả lỗi, KHÔNG đóng; nếu dòng chưa có
--    checkpoint sau sự cố/đổi khuôn đang chờ thì tự tạo 1 cái để IPQC thấy trong
--    hàng đợi (không bao giờ kẹt vì "không có gì để kiểm").
-- 3) Bịt 2 đường lách — chỉ QC Manager / admin được làm khi IPQC chưa OK:
--      - duc_delete_incident mode 'open' (xoá sự cố đang mở — dùng khi nhập nhầm máy)
--      - duc_edit_open_incident đổi sang loại KHÔNG cần IPQC.
-- Đóng tự động F1 khi IPQC kiểm OK (duc_close_f1_incident_if_open) giữ nguyên.
--
-- Cập nhật hàm 2–3 bằng cách thay đúng đoạn trên định nghĩa ĐANG CHẠY (giữ các sửa
-- trước như D45 open_id_su_co). An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create or replace function public.duc_ipqc_trang_thai_su_co(p_id_dong text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v record; v_kq text;
begin
  select ma_may, open_loai_su_co, open_gio_phat_sinh, open_id_su_co into v
    from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found or v.open_gio_phat_sinh is null
     or not (left(coalesce(v.open_loai_su_co, ''), 2) = any(array['A1','A2','A3','B1','B2','C3','E1','F1'])) then
    return jsonb_build_object('can_ipqc', false, 'ok', true);
  end if;
  select cp.ket_qua into v_kq from duc_ipqc_checkpoint cp
   where cp.trang_thai = 'da_kiem' and cp.loai_kiem in ('sau_su_co', 'doi_khuon')
     and ((v.open_id_su_co is not null and cp.id_su_co_goc = v.open_id_su_co)
          or (cp.ma_may = v.ma_may and cp.thoi_diem_kiem_thuc_te >= v.open_gio_phat_sinh))
   order by cp.thoi_diem_kiem_thuc_te desc nulls last
   limit 1;
  return jsonb_build_object('can_ipqc', true, 'ok', coalesce(v_kq = 'OK', false), 'ket_qua', v_kq, 'id_su_co', v.open_id_su_co);
end $$;
revoke all on function public.duc_ipqc_trang_thai_su_co(text) from public, anon, authenticated;

do $mig$
declare d text; i int; j int;
begin
  -- 2) duc_resolve_incident
  d := replace(pg_get_functiondef('public.duc_resolve_incident(text,timestamptz,text,text,text)'::regprocedure), E'\r', '');
  if position('duc_ipqc_trang_thai_su_co' in d) = 0 then
    i := position('  -- Bắt buộc/cảnh báo IPQC OK' in d);
    j := position('  v_noi_dung_combined := coalesce(v_cht.open_noi_dung_xu_ly' in d);
    if i = 0 or j = 0 or j < i then raise exception 'T170: không tìm thấy đoạn kiểm IPQC trong duc_resolve_incident'; end if;
    d := left(d, i - 1) || $blk$  -- T170 CHẶN CỨNG: loại sự cố cần IPQC chỉ kết thúc khi kết quả IPQC mới nhất là OK
  -- (duc_ipqc_trang_thai_su_co). Chưa OK → không đóng; bảo đảm dòng có checkpoint chờ kiểm.
  v_ipqc := duc_ipqc_trang_thai_su_co(p_id_dong);
  if (v_ipqc->>'can_ipqc')::boolean and not (v_ipqc->>'ok')::boolean then
    if not exists (select 1 from duc_ipqc_checkpoint
                   where id_dong = p_id_dong and trang_thai = 'cho_kiem' and loai_kiem in ('sau_su_co', 'doi_khuon')) then
      begin
        perform duc_request_ipqc_check(p_id_dong, 'sau_su_co', v_cht.open_id_su_co, null);
      exception when unique_violation then null;  -- trùng mã checkpoint cùng giây: đã có yêu cầu
      end;
    end if;
    return jsonb_build_object('ok', false, 'chan_ipqc', true, 'ket_qua_ipqc', v_ipqc->>'ket_qua', 'error',
      case when v_ipqc->>'ket_qua' is null then
        '⛔ Chưa có kết quả IPQC cho sự cố ' || coalesce(v_cht.open_id_su_co, '') || ' — máy CHƯA được chạy lại. Đã gửi yêu cầu kiểm sang IPQC; khi IPQC kiểm OK thì bấm "Xử lý xong" lại.'
      else
        '⛔ IPQC kiểm sự cố ' || coalesce(v_cht.open_id_su_co, '') || ' KHÔNG ĐẠT (' || (v_ipqc->>'ket_qua') || ') — máy CHƯA được chạy lại. Xử lý tiếp rồi nhờ IPQC kiểm lại; chỉ khi lần kiểm mới nhất là OK mới kết thúc được sự cố.'
      end);
  end if;

$blk$ || substr(d, j);
    d := replace(d, '  v_canh_bao_ipqc_loai text;', E'  v_canh_bao_ipqc_loai text;\n  v_ipqc jsonb;');
    d := replace(d, 'v_hard_block_ipqc constant boolean := false;   -- Giai đoạn 2: đổi thành true khi sẵn sàng',
                    'v_hard_block_ipqc constant boolean := true;    -- T170: đã chặn cứng (xem khối duc_ipqc_trang_thai_su_co)');
    execute d;
  end if;

  -- 3a) duc_delete_incident — xoá sự cố đang mở
  d := replace(pg_get_functiondef('public.duc_delete_incident(text,text,text,text)'::regprocedure), E'\r', '');
  if position('duc_ipqc_trang_thai_su_co' in d) = 0 then
    i := position($s$    perform duc_clear_incident_open(p_id_dong, coalesce(p_user, 'system'));$s$ in d);
    if i = 0 then raise exception 'T170: không tìm thấy chỗ chèn trong duc_delete_incident'; end if;
    d := left(d, i - 1) || $blk$    -- T170: sự cố cần IPQC mà chưa OK → chỉ QC Manager / admin được xoá (tránh lách chặn cứng)
    if not (duc_ipqc_trang_thai_su_co(p_id_dong)->>'ok')::boolean and not public.has_role('admin', 'qc_manager') then
      return jsonb_build_object('ok', false, 'error',
        '⛔ Sự cố này bắt buộc IPQC OK mới được chạy lại — chỉ QC Manager / admin được xoá sự cố đang mở khi IPQC chưa OK (trường hợp nhập nhầm máy).');
    end if;
$blk$ || substr(d, i);
    execute d;
  end if;

  -- 3b) duc_edit_open_incident — đổi sang loại không cần IPQC
  d := replace(pg_get_functiondef('public.duc_edit_open_incident(text,text,timestamptz,text,text,text,text)'::regprocedure), E'\r', '');
  if position('duc_ipqc_trang_thai_su_co' in d) = 0 then
    i := position('  v_new_version := coalesce(v_row.version, 0) + 1;' in d);
    if i = 0 then raise exception 'T170: không tìm thấy chỗ chèn trong duc_edit_open_incident'; end if;
    d := left(d, i - 1) || $blk$  -- T170: không cho đổi sự cố cần IPQC (chưa OK) sang loại không cần IPQC, trừ QC Manager / admin
  if p_loai is not null and not (left(p_loai, 2) = any(array['A1','A2','A3','B1','B2','C3','E1','F1']))
     and not (duc_ipqc_trang_thai_su_co(p_id_dong)->>'ok')::boolean and not public.has_role('admin', 'qc_manager') then
    return jsonb_build_object('ok', false, 'error',
      '⛔ Sự cố đang mở bắt buộc IPQC OK — không đổi sang loại không cần IPQC khi chưa có kết quả OK. Nếu chọn nhầm loại, nhờ QC Manager / admin sửa.');
  end if;

$blk$ || substr(d, i);
    execute d;
  end if;
end $mig$;
