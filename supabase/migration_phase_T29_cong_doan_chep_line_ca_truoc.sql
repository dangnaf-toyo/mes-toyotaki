-- ============================================================================
-- Phase T29 — Công đoạn (Bavia line mode): "Chép line từ ca trước sang"
--
-- Bối cảnh: cd_tram_hien_tai gắn cứng theo (ngày, ca) — id_tram sinh từ
-- công_đoạn + ngày + ca + tên_line. Không có cơ chế kế thừa ca như bên Đúc.
-- Sang ngày/ca mới, trưởng ca phải gán lại kế hoạch cho từng line dù mã SP
-- vẫn đang làm dở (hàng dở nằm ở tem nguồn duc_tem, không mất — nhưng dòng
-- line + KH ca + người thao tác thì phải nhập lại).
--
-- Hàm này chép nhanh: lấy nhóm (ngày, ca) của công đoạn còn line trong
-- cd_tram_hien_tai (KHÁC ca đích, trong vòng 7 ngày, được thao tác gần nhất),
-- tạo lại từng line ở (ngày, ca) đích với NGUYÊN mã SP / KH ca / KH tuần /
-- người thao tác, nhưng SẢN LƯỢNG OK/NG/NG-sửa = 0 (ca mới đếm lại từ đầu).
--
--   - KHÔNG đụng gì tới ca nguồn (line cũ vẫn còn — nếu ca nguồn chưa kết ca
--     thì vẫn phải kết ca bình thường cho đúng báo cáo).
--   - Line đã có sẵn ở ca đích → giữ nguyên, on conflict do nothing (không đè
--     sản lượng đang đếm).
--   - Nếu không có ca nào trước đó còn line → trả ok=false, reason='no_source'
--     (frontend gợi ý dùng "Nạp kế hoạch từ KHSX tuần").
--
-- Chạy trong Supabase SQL Editor. Idempotent.
-- ============================================================================

create or replace function cd_chep_line_tu_ca_truoc(
  p_ngay date, p_ca text, p_cong_doan text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_src_ngay  date;
  v_src_ca    text;
  v_copied    int := 0;
  v_skipped   int := 0;
  v_row       cd_tram_hien_tai%rowtype;
  v_id        text;
begin
  if p_cong_doan is null or trim(p_cong_doan) = '' then raise exception 'Thiếu công đoạn'; end if;

  -- Nguồn: nhóm (ngày, ca) của công đoạn này còn line trong cd_tram_hien_tai,
  -- khác (ngày, ca) đích, không quá 7 ngày trước, được cập nhật gần nhất.
  select ngay, ca into v_src_ngay, v_src_ca
  from cd_tram_hien_tai
  where cong_doan = p_cong_doan
    and not (ngay = p_ngay and ca = p_ca)
    and ngay >= p_ngay - 7
  order by last_updated_at desc
  limit 1;

  if v_src_ngay is null then
    return jsonb_build_object('ok', false, 'reason', 'no_source', 'copied', 0, 'skipped', 0);
  end if;

  for v_row in
    select * from cd_tram_hien_tai
    where cong_doan = p_cong_doan and ngay = v_src_ngay and ca = v_src_ca
    order by ten_tram
  loop
    v_id := duc_normalize_name(v_row.cong_doan) || '_' || to_char(p_ngay, 'DDMMYYYY') || '_' ||
            duc_normalize_name(p_ca) || '_' || duc_normalize_name(v_row.ten_tram);

    insert into cd_tram_hien_tai (
      id_tram, ngay, ca, cong_doan, ten_tram, ma_sp, ten_sp, kh_ca, kh_tuan,
      nguoi_thao_tac, so_luong_ok, so_luong_ng, so_luong_ng_sua,
      ghi_chu, version, last_updated_by, last_updated_at
    ) values (
      v_id, p_ngay, p_ca, v_row.cong_doan, v_row.ten_tram, v_row.ma_sp, coalesce(v_row.ten_sp, ''),
      v_row.kh_ca, v_row.kh_tuan, coalesce(v_row.nguoi_thao_tac, ''), 0, 0, 0,
      '', 1, p_user, now()
    )
    on conflict (id_tram) do nothing;

    if found then v_copied := v_copied + 1; else v_skipped := v_skipped + 1; end if;
  end loop;

  return jsonb_build_object(
    'ok', true, 'copied', v_copied, 'skipped', v_skipped,
    'src_ngay', v_src_ngay, 'src_ca', v_src_ca
  );
end;
$$;
revoke execute on function cd_chep_line_tu_ca_truoc(date, text, text, text) from anon;
grant  execute on function cd_chep_line_tu_ca_truoc(date, text, text, text) to authenticated;
