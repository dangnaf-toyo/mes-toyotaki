-- ============================================================================
-- Phase T47 — Chặn khai báo tem THÀNH PHẨM (tiền tố Tag No "TP...") làm
-- "nguồn" ở màn ghi-nhan-tem-thanh-pham.html. Vị trí này chỉ nhận tem ĐÚC
-- (tiền tố "TKD...") — đọc nhầm tem thành phẩm vào ô này trước chỉ bị chặn
-- do sai công đoạn/đã dùng hết (thông báo khó hiểu), giờ báo rõ nguyên nhân.
-- Kiểm tra ở CLIENT (ghi-nhan-tem-thanh-pham.html) đã có — thêm ở đây để
-- chặn chắc chắn dù gọi thẳng RPC.
--
-- Không đổi tham số hàm (vẫn (text,text,text)) — chỉ CREATE OR REPLACE, an
-- toàn chạy lại nhiều lần.
-- ============================================================================

create or replace function cd_khai_bao_nguon_dang_dung(
  p_tag_no text,
  p_cong_doan text,
  p_nguoi text
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_tem duc_tem%rowtype;
  v_vi_tri text;
begin
  if p_tag_no is null or trim(p_tag_no) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu Tag No');
  end if;
  if p_cong_doan is null or trim(p_cong_doan) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu công đoạn');
  end if;

  if trim(p_tag_no) ilike 'TP%' then
    return jsonb_build_object('ok', false, 'error',
      'Tem thành phẩm không dùng làm nguồn được — hãy đọc đúng tem của công đoạn ĐÚC');
  end if;

  select * into v_tem from duc_tem where tag_no = trim(p_tag_no) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || p_tag_no);
  end if;

  if coalesce(v_tem.so_luong, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error',
      'Tem ' || p_tag_no || ' đã dùng hết — không thể khai báo lại', 'da_het', true);
  end if;

  select cong_doan_nhan into v_vi_tri
  from cd_chuyen_cong_doan_log
  where tag_no = v_tem.tag_no
  order by thoi_gian_chuyen desc limit 1;

  if v_vi_tri is distinct from p_cong_doan then
    return jsonb_build_object('ok', false, 'error',
      'Tem ' || p_tag_no || ' chưa được Chuyển công đoạn tới ' || p_cong_doan
      || coalesce(' — hiện đang ở ' || v_vi_tri, ' — chưa chuyển tới đâu'));
  end if;

  update duc_tem set thoi_diem_bat_dau_dung = coalesce(thoi_diem_bat_dau_dung, now())
  where tag_no = v_tem.tag_no
  returning * into v_tem;

  return jsonb_build_object(
    'ok', true, 'tag_no', v_tem.tag_no, 'ma_sp', v_tem.ma_sp, 'ten_sp', v_tem.ten_sp,
    'so_luong_con_lai', v_tem.so_luong,
    'da_khai_bao_truoc_do', v_tem.thoi_diem_bat_dau_dung is not null
  );
end;
$$;
