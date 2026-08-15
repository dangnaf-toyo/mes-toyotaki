-- ============================================================================
-- Giai đoạn 10 (bỏ Google) — Bắt buộc có kết quả IPQC OK trước khi kết thúc
-- sự cố (đổi khuôn hoặc sự cố thật) trên Dashboard Đúc, cho các loại sự cố:
-- A1, A2, A3, B1, B2, C3, E1, F1.
--
-- Bối cảnh: trưởng ca đôi khi bấm "✓ Xong" kết thúc sự cố/đổi khuôn trước khi
-- IPQC kịp kiểm tra, dẫn đến sản xuất hàng loạt sản phẩm NG mà không phát
-- hiện kịp.
--
-- TRIỂN KHAI 2 GIAI ĐOẠN (theo yêu cầu, xác nhận 2026-08-15):
--   Giai đoạn 1 (BẬT NGAY): mềm — vẫn cho kết thúc sự cố dù chưa có kết quả
--     IPQC OK, nhưng trả về cờ cảnh báo để trang web hiện thông báo nhắc nhở.
--   Giai đoạn 2 (BẬT SAU ~1 THÁNG, khi trưởng ca đã quen quy trình): cứng —
--     CHẶN HẲN việc kết thúc sự cố nếu chưa có kết quả IPQC OK.
--   Chuyển sang giai đoạn 2: đổi `v_hard_block_ipqc` bên dưới từ `false`
--   thành `true` rồi chạy lại migration này (1 dòng, không cần sửa gì khác).
--
-- Cách xác định "đã có kết quả IPQC OK cho sự cố này": có ít nhất 1 checkpoint
-- (duc_ipqc_checkpoint) cùng id_dong, loai_kiem IN ('doi_khuon','sau_su_co'),
-- đã kiểm xong (da_kiem) với kết quả OK, HOÀN THÀNH SAU thời điểm sự cố này
-- mở (thoi_diem_kiem_thuc_te >= open_gio_phat_sinh) — không so khớp cứng theo
-- han_kiem để vẫn đúng ngay cả khi giờ phát sinh bị sửa sau đó
-- (duc_edit_open_incident).
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create or replace function duc_resolve_incident(
  p_id_dong text, p_gio_tro_lai timestamptz, p_bonus_note text, p_truong_ca text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_cht record;
  v_noi_dung_combined text;
  v_seg record;
  v_stt int;
  v_id_ban_ghi text;
  v_created_ids text[] := array[]::text[];
  v_total_phut int := 0;
  v_seg_count int;
  v_idx int := 0;
  v_seg_noi_dung text;
  v_last_id text;
  v_loai_can_ipqc constant text[] := array['A1','A2','A3','B1','B2','C3','E1','F1'];
  v_hard_block_ipqc constant boolean := false;   -- Giai đoạn 2: đổi thành true khi sẵn sàng
  v_co_ipqc_ok boolean;
  v_canh_bao_ipqc boolean := false;
begin
  select ngay, ca, phuong_an_ca, ma_may, ma_sp, ten_sp, so_khuon, open_loai_su_co,
         open_gio_phat_sinh, open_noi_dung_xu_ly, open_van_de, open_dam_nhiem
  into v_cht from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng Ca_hien_tai: ' || p_id_dong);
  end if;
  if v_cht.open_gio_phat_sinh is null then
    return jsonb_build_object('ok', false, 'error', 'Dòng này không có sự cố đang mở');
  end if;
  if p_gio_tro_lai < v_cht.open_gio_phat_sinh then
    return jsonb_build_object('ok', false, 'error', 'Giờ trở lại phải sau giờ phát sinh');
  end if;
  if p_gio_tro_lai > now() + interval '1 minute' then
    return jsonb_build_object('ok', false, 'error', 'Giờ trở lại không được ở tương lai');
  end if;

  -- Bắt buộc/cảnh báo IPQC OK cho các loại sự cố liên quan chất lượng/khuôn.
  if left(coalesce(v_cht.open_loai_su_co, ''), 2) = any(v_loai_can_ipqc) then
    select exists(
      select 1 from duc_ipqc_checkpoint cp
      where cp.id_dong = p_id_dong
        and cp.loai_kiem in ('doi_khuon', 'sau_su_co')
        and cp.trang_thai = 'da_kiem'
        and cp.ket_qua = 'OK'
        and cp.thoi_diem_kiem_thuc_te >= v_cht.open_gio_phat_sinh
    ) into v_co_ipqc_ok;

    if not v_co_ipqc_ok then
      if v_hard_block_ipqc then
        return jsonb_build_object('ok', false, 'error',
          'Chưa có kết quả IPQC OK cho sự cố này — không thể kết thúc. Hãy nhắc nhân viên IPQC kiểm tra và hoàn thiện trên hệ thống trước.');
      end if;
      v_canh_bao_ipqc := true;
    end if;
  end if;

  v_noi_dung_combined := coalesce(v_cht.open_noi_dung_xu_ly, '');
  if p_bonus_note is not null and trim(p_bonus_note) <> '' then
    v_noi_dung_combined := case when v_noi_dung_combined <> '' then v_noi_dung_combined || E'\n[BS] ' || trim(p_bonus_note) else trim(p_bonus_note) end;
  end if;

  select count(*) into v_seg_count from duc_split_incident_by_shift(
    v_cht.open_gio_phat_sinh, p_gio_tro_lai, v_cht.phuong_an_ca, v_cht.ngay, v_cht.ca
  );

  for v_seg in select * from duc_split_incident_by_shift(
    v_cht.open_gio_phat_sinh, p_gio_tro_lai, v_cht.phuong_an_ca, v_cht.ngay, v_cht.ca
  ) loop
    v_idx := v_idx + 1;
    select count(*) + 1 into v_stt from duc_su_co_log
      where ngay = v_seg.ngay and ca = v_seg.ca and ma_may = v_cht.ma_may and ma_sp = v_cht.ma_sp;
    v_id_ban_ghi := duc_make_id_dong(v_seg.ngay, v_seg.ca, v_cht.ma_may, v_cht.ma_sp) || '_' || v_stt;

    v_seg_noi_dung := v_noi_dung_combined;
    if v_seg_count > 1 then
      v_seg_noi_dung := v_seg_noi_dung || E'\n[Phần ' || v_idx || '/' || v_seg_count || ' — ' || v_seg.ca || ' ' || to_char(v_seg.ngay, 'DD/MM/YYYY') ||
        (case when v_idx = v_seg_count then ', xử lý xong]' else ', chuyển tiếp ca sau]' end);
    end if;

    insert into duc_su_co_log (
      id_ban_ghi, ngay, ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, loai_su_co,
      gio_phat_sinh, gio_tro_lai, thoi_gian_dung_phut, van_de, noi_dung_xu_ly,
      dam_nhiem, ghi_chu, truong_ca, thoi_diem_luu, van_de_edited
    ) values (
      v_id_ban_ghi, v_seg.ngay, v_seg.ca, duc_iso_week(v_seg.ngay), v_cht.ma_may, v_cht.ma_sp, v_cht.ten_sp, v_cht.so_khuon,
      v_cht.open_loai_su_co, v_seg.seg_start, v_seg.seg_end, v_seg.phut,
      v_cht.open_van_de, v_seg_noi_dung, v_cht.open_dam_nhiem, '', coalesce(p_truong_ca, ''), now(), 'No'
    );

    v_created_ids := array_append(v_created_ids, v_id_ban_ghi);
    v_total_phut := v_total_phut + v_seg.phut;
    v_last_id := v_id_ban_ghi;
  end loop;

  perform duc_clear_incident_open(p_id_dong, coalesce(p_truong_ca, p_user, 'system'));

  return jsonb_build_object(
    'ok', true, 'id_ban_ghi', v_last_id, 'id_ban_ghi_list', to_jsonb(v_created_ids),
    'thoi_gian_dung_phut', v_total_phut, 'canh_bao_ipqc', v_canh_bao_ipqc
  );
end;
$$;
revoke execute on function duc_resolve_incident(text, timestamptz, text, text, text) from anon;
grant execute on function duc_resolve_incident(text, timestamptz, text, text, text) to authenticated;
