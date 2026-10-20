-- ============================================================================
-- T123 — Check sheet bảo dưỡng khuôn: bắt buộc xác nhận xử lý TOÀN BỘ vấn đề
-- khuôn chưa đóng (duc_van_de_khuon trạng thái Mở / Chờ xác nhận) trước khi
-- Hoàn thành.
--
--   - Cột duc_khuon_checksheet.van_de_xu_ly jsonb: [{id_van_de, mo_ta,
--     ngay_phat_hien, ma_may, trang_thai_truoc, noi_dung, xac_nhan}] — lưu cả khi
--     lưu nháp, để xem lại sau khi hoàn thành.
--   - duc_khuon_cs_luu (p_hoan_thanh): mọi vấn đề chưa đóng của khuôn phải có
--     mục xac_nhan = true + nội dung xử lý; thiếu → từ chối, báo số lượng + mô tả.
--   - Hoàn thành: vấn đề "Mở" → "Chờ xác nhận" (nội dung, người xử lý, ngày) —
--     chờ IPQC kiểm sản phẩm đầu xác nhận OK để đóng như luồng cũ; vấn đề đã
--     "Chờ xác nhận" thì nối thêm nội dung. Mọi vấn đề ghi chú "[thời điểm] Xử lý
--     trong check sheet bảo dưỡng #id"; sổ đời khuôn ghi số vấn đề đã xử lý.
--
-- Chỉ thay duc_khuon_cs_luu (giữ nguyên phần cũ). Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

alter table duc_khuon_checksheet add column if not exists van_de_xu_ly jsonb not null default '[]'::jsonb;

create or replace function duc_khuon_cs_luu(p_id_ke_hoach bigint, p_data jsonb, p_hoan_thanh boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_me record; v_kh duc_khuon_bd_kh_tuan; v_cs duc_khuon_checksheet; v_mold duc_shot_khuon;
  v_items jsonb; v_ket_luan text; v_ngay date; v_bd timestamptz; v_kt timestamptz; v_dung numeric;
  v_id bigint; v_id_log text; v_now timestamptz := now(); v_mo_ta text; v_reset boolean;
  v_ng text; v_anh_truoc text[]; v_anh_sau text[];
  v_vd jsonb; v_thieu_n int; v_thieu text; v_nguoi_xl text; v_stamp text; v_n_vd int := 0; r record;
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  if not duc_khuon_bd_la_nguoi_lap(v_me.o_role, v_me.o_bo_phan) then  -- D68
    return jsonb_build_object('ok', false, 'error', 'Chỉ nhân viên bảo dưỡng khuôn / Quản lý bộ phận Đúc được ghi check sheet');
  end if;

  select * into v_kh from duc_khuon_bd_kh_tuan where id = p_id_ke_hoach;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy lịch bảo dưỡng'); end if;

  select * into v_cs from duc_khuon_checksheet where id_ke_hoach = p_id_ke_hoach for update;
  if found and v_cs.trang_thai = 'hoan_thanh' then
    return jsonb_build_object('ok', false, 'error', 'Check sheet đã hoàn thành — không sửa được nữa');
  end if;

  v_items := coalesce(p_data->'hang_muc', '[]'::jsonb);
  if jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Check sheet chưa có hạng mục nào');
  end if;
  -- T123: xác nhận xử lý vấn đề khuôn chưa đóng.
  v_vd := coalesce(p_data->'van_de_xu_ly', '[]'::jsonb);
  if jsonb_typeof(v_vd) <> 'array' then v_vd := '[]'::jsonb; end if;
  v_ket_luan := coalesce(p_data->>'ket_luan', '');
  select coalesce(array_agg(u), '{}') into v_anh_truoc from jsonb_array_elements_text(coalesce(p_data->'anh_truoc', '[]'::jsonb)) u;
  select coalesce(array_agg(u), '{}') into v_anh_sau from jsonb_array_elements_text(coalesce(p_data->'anh_sau', '[]'::jsonb)) u;
  if cardinality(v_anh_truoc) > 10 or cardinality(v_anh_sau) > 10 then
    return jsonb_build_object('ok', false, 'error', 'Tối đa 10 ảnh trước và 10 ảnh sau');
  end if;
  if exists (select 1 from unnest(v_anh_truoc || v_anh_sau) u where u not like '%/storage/v1/object/public/khuon-bao-duong/%') then
    return jsonb_build_object('ok', false, 'error', 'Link ảnh không hợp lệ');
  end if;
  v_ngay := coalesce(nullif(p_data->>'ngay_thuc_hien', '')::date, v_kh.ngay);
  v_bd := nullif(p_data->>'gio_bat_dau', '')::timestamptz;
  v_kt := nullif(p_data->>'gio_ket_thuc', '')::timestamptz;
  if v_bd is not null and v_kt is not null then
    if v_kt < v_bd then return jsonb_build_object('ok', false, 'error', 'Giờ kết thúc phải sau giờ bắt đầu'); end if;
    v_dung := round(extract(epoch from (v_kt - v_bd)) / 60);
  end if;

  if p_hoan_thanh then
    if exists (select 1 from jsonb_array_elements(v_items) x where coalesce(x->>'ket_qua', '') not in ('OK', 'NG', 'NA')) then
      return jsonb_build_object('ok', false, 'error', 'Còn hạng mục chưa đánh giá OK / NG / N/A');
    end if;
    if exists (select 1 from jsonb_array_elements(v_items) x where x->>'ket_qua' = 'NG' and coalesce(trim(x->>'ghi_chu'), '') = '') then
      return jsonb_build_object('ok', false, 'error', 'Hạng mục NG phải ghi chú tình trạng / cách xử lý');
    end if;
    if v_ket_luan not in ('dat', 'khong_dat') then
      return jsonb_build_object('ok', false, 'error', 'Chọn kết luận Đạt / Không đạt');
    end if;
    if cardinality(v_anh_truoc) = 0 or cardinality(v_anh_sau) = 0 then
      return jsonb_build_object('ok', false, 'error', 'Cần ít nhất 1 ảnh TRƯỚC và 1 ảnh SAU bảo dưỡng');
    end if;
    if coalesce(trim(p_data->>'nguoi_thuc_hien'), '') = '' then
      return jsonb_build_object('ok', false, 'error', 'Nhập người thực hiện');
    end if;
    -- T123: mọi vấn đề khuôn chưa đóng phải được xác nhận xử lý.
    select count(*), string_agg(to_char(v.ngay_phat_hien, 'DD/MM') || ' ' || left(coalesce(v.mo_ta, ''), 60), '; ' order by v.ngay_phat_hien)
    into v_thieu_n, v_thieu
    from duc_van_de_khuon v
    where v.ma_khuon = v_kh.ma_khuon and v.trang_thai <> 'Đã đóng'
      and not exists (select 1 from jsonb_array_elements(v_vd) x
                      where x->>'id_van_de' = v.id_van_de and coalesce((x->>'xac_nhan')::boolean, false)
                        and coalesce(trim(x->>'noi_dung'), '') <> '');
    if v_thieu_n > 0 then
      return jsonb_build_object('ok', false, 'error',
        'Còn ' || v_thieu_n || ' vấn đề khuôn chưa đóng chưa được xác nhận xử lý (' || left(v_thieu, 300) ||
        '). Xác nhận ở khung "Vấn đề khuôn chưa đóng" — nếu vừa phát sinh vấn đề mới, tải lại trang.',
        'thieu_van_de', v_thieu_n);
    end if;
  end if;

  if coalesce(trim(p_data->>'nguoi_thuc_hien_phu'), '') <> ''
     and trim(p_data->>'nguoi_thuc_hien_phu') = coalesce(trim(p_data->>'nguoi_thuc_hien'), '') then
    return jsonb_build_object('ok', false, 'error', 'Đảm nhiệm phụ phải khác đảm nhiệm chính');
  end if;

  if v_cs.id is null then
    insert into duc_khuon_checksheet (id_ke_hoach, ma_khuon, loai, ngay_ke_hoach, ngay_thuc_hien, nguoi_tao)
    values (v_kh.id, v_kh.ma_khuon, v_kh.loai, v_kh.ngay, v_ngay, v_me.o_ten)
    returning id into v_id;
  else
    v_id := v_cs.id;
  end if;

  update duc_khuon_checksheet set
    ngay_thuc_hien = v_ngay,
    loai = v_kh.loai,
    nguoi_thuc_hien = coalesce(trim(p_data->>'nguoi_thuc_hien'), ''),
    nguoi_thuc_hien_phu = coalesce(trim(p_data->>'nguoi_thuc_hien_phu'), ''),  -- T102
    gio_bat_dau = v_bd, gio_ket_thuc = v_kt, thoi_gian_dung_phut = v_dung,
    hang_muc = v_items,
    phu_tung_thay = coalesce(trim(p_data->>'phu_tung_thay'), ''),
    chi_phi = nullif(p_data->>'chi_phi', '')::numeric,
    ket_luan = v_ket_luan,
    ghi_chu = coalesce(trim(p_data->>'ghi_chu'), ''),
    anh_truoc = v_anh_truoc,
    anh_sau = v_anh_sau,
    van_de_xu_ly = v_vd,  -- T123
    updated_at = v_now
  where id = v_id;

  if not p_hoan_thanh then
    return jsonb_build_object('ok', true, 'id', v_id, 'trang_thai', 'dang_lam');
  end if;

  -- T123: ghi kết quả xử lý vào từng vấn đề khuôn chưa đóng.
  v_nguoi_xl := trim(p_data->>'nguoi_thuc_hien') || coalesce(' + ' || nullif(trim(p_data->>'nguoi_thuc_hien_phu'), ''), '');
  v_stamp := to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI');
  for r in
    select v.id_van_de, v.trang_thai, v.noi_dung_xu_ly, trim(j.x->>'noi_dung') nd
    from duc_van_de_khuon v
    join lateral (select e x from jsonb_array_elements(v_vd) e where e->>'id_van_de' = v.id_van_de limit 1) j on true
    where v.ma_khuon = v_kh.ma_khuon and v.trang_thai <> 'Đã đóng'
    for update of v
  loop
    v_n_vd := v_n_vd + 1;
    update duc_van_de_khuon set
      trang_thai = 'Chờ xác nhận',
      noi_dung_xu_ly = case when r.trang_thai = 'Mở' or coalesce(r.noi_dung_xu_ly, '') = '' then r.nd
                            when position(r.nd in r.noi_dung_xu_ly) > 0 then r.noi_dung_xu_ly
                            else r.noi_dung_xu_ly || E'\n' || r.nd end,
      nguoi_xu_ly = v_nguoi_xl,
      ngay_xu_ly = v_ngay,
      ghi_chu = coalesce(nullif(ghi_chu, '') || E'\n', '') || '[' || v_stamp || '] Xử lý trong check sheet bảo dưỡng #' || v_id
        || ' (' || v_nguoi_xl || '): ' || r.nd,
      last_updated_at = v_now
    where id_van_de = r.id_van_de;
  end loop;

  select * into v_mold from duc_shot_khuon where ma_khuon = v_kh.ma_khuon for update;
  if v_kh.loai in ('Bảo dưỡng định kỳ', 'Sửa chữa', 'Thay khuôn mới') then
    select string_agg(x->>'noi_dung' || ': ' || coalesce(x->>'ghi_chu', ''), '; ') into v_ng
    from jsonb_array_elements(v_items) x where x->>'ket_qua' = 'NG';
    v_mo_ta := 'Check sheet #' || v_id || ' — ' || case when v_ket_luan = 'dat' then 'ĐẠT' else 'KHÔNG ĐẠT' end
      || case when v_ng is not null then '. NG: ' || v_ng else '' end
      || case when coalesce(trim(p_data->>'phu_tung_thay'), '') <> '' then '. Phụ tùng thay: ' || trim(p_data->>'phu_tung_thay') else '' end
      || case when v_n_vd > 0 then '. Xử lý ' || v_n_vd || ' vấn đề khuôn chưa đóng' else '' end
      || case when coalesce(trim(p_data->>'ghi_chu'), '') <> '' then '. ' || trim(p_data->>'ghi_chu') else '' end;
    v_id_log := 'BD-' || duc_normalize_name(v_kh.ma_khuon) || '-' || to_char(v_now, 'YYYYMMDDHH24MISS');
    insert into duc_khuon_bao_duong_log (
      id_log, ma_khuon, loai, ngay, shot_tai_thoi_diem, nguoi_thuc_hien, mo_ta,
      chi_phi, thoi_gian_dung_phut, thoi_diem_ghi
    ) values (
      v_id_log, v_kh.ma_khuon, v_kh.loai, v_ngay, coalesce(v_mold.tong_shot_luy_ke, 0),
      trim(p_data->>'nguoi_thuc_hien') || coalesce(' + ' || nullif(trim(p_data->>'nguoi_thuc_hien_phu'), ''), ''), v_mo_ta, nullif(p_data->>'chi_phi', '')::numeric, v_dung, v_now
    );
    v_reset := v_ket_luan = 'dat' and v_kh.loai in ('Bảo dưỡng định kỳ', 'Thay khuôn mới') and v_mold.ma_khuon is not null;
    if v_reset then
      update duc_shot_khuon set
        lan_bao_duong_gan_nhat = v_ngay,
        shot_tai_lan_bao_duong_gan_nhat = coalesce(tong_shot_luy_ke, 0),
        trang_thai_khuon = duc_compute_mold_status(coalesce(tong_shot_luy_ke, 0), coalesce(tong_shot_luy_ke, 0),
          coalesce(nguong_bao_duong, 10000), coalesce(nguong_lam_moi, 100000)),
        last_updated_at = v_now
      where ma_khuon = v_kh.ma_khuon;
    end if;
  end if;

  update duc_khuon_checksheet set trang_thai = 'hoan_thanh', id_log = v_id_log,
    nguoi_hoan_thanh = v_me.o_ten, thoi_diem_hoan_thanh = v_now, updated_at = v_now
  where id = v_id;

  return jsonb_build_object('ok', true, 'id', v_id, 'trang_thai', 'hoan_thanh', 'id_log', v_id_log,
    'reset_dong_ho', coalesce(v_reset, false), 'so_van_de_xu_ly', v_n_vd);
end;
$$;
