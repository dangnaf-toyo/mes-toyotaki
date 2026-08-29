-- ============================================================================
-- D50 — Chỉ thị Kanban KHÔNG cần ca làm việc (chỉ thị cho cả ngày). Bỏ p_ca
-- khỏi phần ghi_chu của tem (frontend giờ truyền p_ca = null). Giữ p_ca trong
-- chữ ký hàm để không phải cấp lại quyền / đổi lời gọi — chỉ đơn giản là bỏ
-- dùng.
-- An toàn chạy lại nhiều lần.
-- ============================================================================

create or replace function duc_tao_lo_kanban(
  p_ma_may text,
  p_ma_sp text,
  p_ngay date,
  p_ca text,          -- không còn dùng (chỉ thị theo NGÀY, không theo ca)
  p_so_thung int,
  p_sl_thung numeric,
  p_sl_thung_cuoi numeric,
  p_so_khuon text,
  p_nguyen_lieu text,
  p_nguoi text
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_ten_sp text;
  v_so_khuon text;
  v_nguyen_lieu text;
  v_sl_chuan numeric;
  v_sl_thung numeric;
  v_lo text;
  v_tag text;
  v_sl numeric;
  v_tems jsonb := '[]'::jsonb;
  i int;
  v_loai_sp text;
begin
  if p_ma_may is null or trim(p_ma_may) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu mã máy');
  end if;
  if p_ma_sp is null or trim(p_ma_sp) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu mã SP');
  end if;
  if p_ngay is null then
    return jsonb_build_object('ok', false, 'error', 'Thiếu ngày chỉ thị');
  end if;
  if coalesce(p_so_thung, 0) < 1 then
    return jsonb_build_object('ok', false, 'error', 'Số thùng phải >= 1');
  end if;
  if p_so_thung > 500 then
    return jsonb_build_object('ok', false, 'error', 'Tối đa 500 tem/lô');
  end if;

  select ten_sp, so_khuon, nguyen_lieu, sl_dong_goi_chuan
    into v_ten_sp, v_so_khuon, v_nguyen_lieu, v_sl_chuan
  from master_products where ma_sp = p_ma_sp;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Mã SP không có trong danh mục: ' || p_ma_sp);
  end if;

  v_sl_thung := coalesce(nullif(v_sl_chuan, 0), nullif(p_sl_thung, 0));
  if v_sl_thung is null or v_sl_thung <= 0 then
    return jsonb_build_object('ok', false, 'error',
      'Mã SP ' || p_ma_sp || ' chưa có "SL đóng gói chuẩn" trong Quản lý danh mục — cập nhật trước khi tạo lô Kanban');
  end if;

  v_so_khuon := coalesce(nullif(trim(p_so_khuon), ''), v_so_khuon, '');
  v_nguyen_lieu := coalesce(nullif(trim(p_nguyen_lieu), ''), v_nguyen_lieu, '');
  v_loai_sp := case when p_ma_sp ilike 'D-%' or v_ten_sp ilike '%phát triển%' then 'phattrien' else 'hangloat' end;

  v_lo := 'LK' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYYMMDDHH24MISS')
          || '_' || regexp_replace(p_ma_may, '\s+', '', 'g');

  for i in 1..p_so_thung loop
    v_tag := duc_next_tag_no(v_loai_sp);
    if i = p_so_thung and coalesce(p_sl_thung_cuoi, 0) > 0 then
      v_sl := p_sl_thung_cuoi;
    else
      v_sl := v_sl_thung;
    end if;

    insert into duc_tem (
      tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
      may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
      nguoi_tt, ngay_gio_xuat, nguoi_nhan, trang_thai, ghi_chu2, ng, ghi_chu_sl,
      id_lo_chi_thi, so_thung_stt, ngay_gio_ghi_nhan
    ) values (
      v_tag, v_ten_sp, p_ma_sp, v_sl, p_ngay, p_ngay::text, v_so_khuon, v_nguyen_lieu,
      p_ma_may, 'Kanban chỉ thị ngày ' || to_char(p_ngay, 'DD/MM/YYYY') || ' — thùng ' || i || '/' || p_so_thung,
      now(), v_so_khuon, null, null,
      null, null, null, 'Chờ sản xuất', null, null, 'Chờ ghi nhận Kanban',
      v_lo, i, null
    );

    v_tems := v_tems || jsonb_build_array(jsonb_build_object(
      'tag_no', v_tag, 'ma_sp', p_ma_sp, 'ten_sp', v_ten_sp, 'so_luong', v_sl,
      'so_khuon', v_so_khuon, 'nguyen_lieu', v_nguyen_lieu, 'may_duc_chi_thi', p_ma_may,
      'ngay', p_ngay, 'so_thung_stt', i, 'tong_so_thung', p_so_thung
    ));
  end loop;

  return jsonb_build_object('ok', true, 'id_lo_chi_thi', v_lo, 'so_tem', p_so_thung, 'tems', v_tems);
end;
$$;
