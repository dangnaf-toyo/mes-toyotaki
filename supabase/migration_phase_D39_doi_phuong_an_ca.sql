-- ============================================================================
-- D39 — Đổi phương án ca của 1 máy đang chạy (vd DC 6/DC 11 đang kẹt "2 ca 8h"
-- trong khi cả nhà máy đã đổi "2 ca 12h" từ D30 — xem banner cảnh báo
-- renderOpsWarnings() ở duc-dashboard.html).
--
-- Bình thường "Phương án" chỉ đổi được qua dropdown ở header duc-dashboard.html
-- (lưu localStorage riêng từng trình duyệt) và chỉ áp dụng cho CA MỚI tạo sau
-- đó — không có cách nào tự đổi dòng đang chạy dở qua giao diện. Hàm này đổi
-- thẳng dòng đang hoạt động của 1 máy sang phương án mới, tính lại đúng ca/
-- khung giờ theo giờ hiện tại (Asia/Ho_Chi_Minh).
--
-- CẢNH BÁO: theo migration D32, tt_ca được tính lại từ KHUNG GIỜ CHUẨN của
-- ca (ngay+ca+phuong_an_ca), không phải sp_start_time — nên đổi khung giờ
-- giữa chừng CÓ THỂ làm tt_ca nhảy số (khung giờ mới gộp thêm hoặc bớt tem đã
-- in so với khung giờ cũ). Hàm này CHỦ ĐỘNG gọi lại duc_recompute_tt_ca ngay
-- sau khi đổi và trả về tt_ca CŨ/MỚI để thấy ngay, không đợi tem tiếp theo
-- mới lộ ra thay đổi.
--
-- Chỉ đổi dòng đang hoạt động (row_seq lớn nhất của máy) — không đụng lịch sử.
-- ============================================================================

create or replace function duc_doi_phuong_an_ca(p_ma_may text, p_phuong_an_ca_moi text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row duc_ca_hien_tai%rowtype;
  v_now_vn timestamp;
  v_today_vn date;
  v_t_phut int;
  v_ca_moi text;
  v_ngay_moi date;
  v_start_vn timestamp;
  v_end_vn timestamp;
  v_tt_ca_cu numeric;
  v_tt_ca_moi numeric;
begin
  if p_phuong_an_ca_moi not in ('2 ca 8h', '2 ca 12h') then
    return jsonb_build_object('ok', false, 'error', 'Phương án không hợp lệ — chỉ nhận "2 ca 8h" hoặc "2 ca 12h"');
  end if;

  select * into v_row from duc_ca_hien_tai where ma_may = trim(coalesce(p_ma_may, '')) order by row_seq desc limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng đang hoạt động của máy: ' || p_ma_may);
  end if;
  if v_row.ma_sp is null then
    return jsonb_build_object('ok', false, 'error', 'Máy chưa có mã SP đang chạy, không xác định được để tính lại tt_ca');
  end if;
  if v_row.phuong_an_ca = p_phuong_an_ca_moi then
    return jsonb_build_object('ok', false, 'error', 'Máy đã đang dùng đúng phương án này rồi');
  end if;

  v_tt_ca_cu := v_row.tt_ca;
  v_now_vn := now() at time zone 'Asia/Ho_Chi_Minh';
  v_today_vn := v_now_vn::date;
  v_t_phut := extract(hour from v_now_vn)::int * 60 + extract(minute from v_now_vn)::int;

  if p_phuong_an_ca_moi = '2 ca 12h' then
    if v_t_phut >= 6*60 and v_t_phut < 18*60 then
      v_ca_moi := 'Ca ngày'; v_ngay_moi := v_today_vn;
      v_start_vn := v_today_vn + time '06:00'; v_end_vn := v_today_vn + time '18:00';
    elsif v_t_phut >= 18*60 then
      v_ca_moi := 'Ca đêm'; v_ngay_moi := v_today_vn;
      v_start_vn := v_today_vn + time '18:00'; v_end_vn := (v_today_vn + 1) + time '06:00';
    else
      v_ca_moi := 'Ca đêm'; v_ngay_moi := v_today_vn - 1;
      v_start_vn := (v_today_vn - 1) + time '18:00'; v_end_vn := v_today_vn + time '06:00';
    end if;
  else -- '2 ca 8h'
    if v_t_phut >= 6*60 and v_t_phut < 14*60 then
      v_ca_moi := 'Ca 1'; v_ngay_moi := v_today_vn;
      v_start_vn := v_today_vn + time '06:00'; v_end_vn := v_today_vn + time '14:00';
    elsif v_t_phut >= 14*60 and v_t_phut < 22*60 then
      v_ca_moi := 'Ca 2'; v_ngay_moi := v_today_vn;
      v_start_vn := v_today_vn + time '14:00'; v_end_vn := v_today_vn + time '22:00';
    else
      return jsonb_build_object('ok', false, 'error',
        'Giờ hiện tại (22h-6h) không thuộc ca nào của phương án "2 ca 8h" — máy nên chờ tới 6h sáng, hoặc dùng "2 ca 12h" (có Ca đêm 18h-6h)');
    end if;
  end if;

  update duc_ca_hien_tai set
    phuong_an_ca = p_phuong_an_ca_moi,
    ca = v_ca_moi,
    ngay = v_ngay_moi,
    sp_start_time = v_start_vn at time zone 'Asia/Ho_Chi_Minh',
    sp_end_time = v_end_vn at time zone 'Asia/Ho_Chi_Minh',
    version = coalesce(version, 0) + 1,
    last_updated_by = coalesce(nullif(trim(p_user), ''), 'system'),
    last_updated_at = now()
  where id_dong = v_row.id_dong;

  perform duc_recompute_tt_ca(v_row.ma_may, v_row.ma_sp);
  select tt_ca into v_tt_ca_moi from duc_ca_hien_tai where id_dong = v_row.id_dong;

  return jsonb_build_object(
    'ok', true, 'ma_may', v_row.ma_may,
    'phuong_an_ca_cu', v_row.phuong_an_ca, 'ca_cu', v_row.ca, 'ngay_cu', v_row.ngay,
    'phuong_an_ca_moi', p_phuong_an_ca_moi, 'ca_moi', v_ca_moi, 'ngay_moi', v_ngay_moi,
    'tt_ca_cu', v_tt_ca_cu, 'tt_ca_moi', v_tt_ca_moi
  );
end;
$$;

revoke execute on function duc_doi_phuong_an_ca(text, text, text) from public;
revoke execute on function duc_doi_phuong_an_ca(text, text, text) from anon;
grant execute on function duc_doi_phuong_an_ca(text, text, text) to authenticated;
