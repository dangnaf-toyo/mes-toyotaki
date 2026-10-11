-- ============================================================================
-- T77 — Ảnh TRƯỚC / SAU bảo dưỡng trên check sheet (checksheet-bao-duong-khuon.html).
--
-- - Bucket mới "khuon-bao-duong" (public read, giống ipqc-evidence). Chỉ nhân
--   viên bảo dưỡng khuôn / admin được tải ảnh lên; không cho sửa/xoá file.
--   Giới hạn 5MB/ảnh, chỉ ảnh (trình duyệt đã nén JPEG ≤1280px trước khi tải).
-- - duc_khuon_checksheet thêm anh_truoc / anh_sau (text[] URL public).
-- - duc_khuon_cs_luu nhận p_data.anh_truoc / anh_sau (tối đa 10 mỗi loại, chỉ
--   URL của bucket này); Hoàn thành bắt buộc ≥1 ảnh trước và ≥1 ảnh sau.
--
-- Chạy trên CẢ 2 project (production + staging). Idempotent. Chạy sau T76.
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('khuon-bao-duong', 'khuon-bao-duong', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "public read khuon-bao-duong" on storage.objects;
create policy "public read khuon-bao-duong" on storage.objects
  for select using (bucket_id = 'khuon-bao-duong');

drop policy if exists "bd khuon upload khuon-bao-duong" on storage.objects;
create policy "bd khuon upload khuon-bao-duong" on storage.objects
  for insert with check (bucket_id = 'khuon-bao-duong' and public.has_role('nhan_vien_bao_duong_khuon', 'admin'));

alter table duc_khuon_checksheet add column if not exists anh_truoc text[] not null default '{}';
alter table duc_khuon_checksheet add column if not exists anh_sau  text[] not null default '{}';

create or replace function duc_khuon_cs_luu(p_id_ke_hoach bigint, p_data jsonb, p_hoan_thanh boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me record; v_kh duc_khuon_bd_kh_tuan; v_cs duc_khuon_checksheet; v_mold duc_shot_khuon;
  v_items jsonb; v_ket_luan text; v_ngay date; v_bd timestamptz; v_kt timestamptz; v_dung numeric;
  v_id bigint; v_id_log text; v_now timestamptz := now(); v_mo_ta text; v_reset boolean;
  v_ng text; v_anh_truoc text[]; v_anh_sau text[];
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  if coalesce(v_me.o_role, '') not in ('nhan_vien_bao_duong_khuon', 'admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ nhân viên bảo dưỡng khuôn được ghi check sheet');
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
  v_ket_luan := coalesce(p_data->>'ket_luan', '');
  -- Ảnh: chỉ nhận URL public của bucket khuon-bao-duong, tối đa 10 ảnh mỗi loại.
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
    gio_bat_dau = v_bd, gio_ket_thuc = v_kt, thoi_gian_dung_phut = v_dung,
    hang_muc = v_items,
    phu_tung_thay = coalesce(trim(p_data->>'phu_tung_thay'), ''),
    chi_phi = nullif(p_data->>'chi_phi', '')::numeric,
    ket_luan = v_ket_luan,
    ghi_chu = coalesce(trim(p_data->>'ghi_chu'), ''),
    anh_truoc = v_anh_truoc,
    anh_sau = v_anh_sau,
    updated_at = v_now
  where id = v_id;

  if not p_hoan_thanh then
    return jsonb_build_object('ok', true, 'id', v_id, 'trang_thai', 'dang_lam');
  end if;

  -- Hoàn thành: ghi sổ đời khuôn + reset đồng hồ shot nếu đạt.
  select * into v_mold from duc_shot_khuon where ma_khuon = v_kh.ma_khuon for update;
  if v_kh.loai in ('Bảo dưỡng định kỳ', 'Sửa chữa', 'Thay khuôn mới') then
    select string_agg(x->>'noi_dung' || ': ' || coalesce(x->>'ghi_chu', ''), '; ') into v_ng
    from jsonb_array_elements(v_items) x where x->>'ket_qua' = 'NG';
    v_mo_ta := 'Check sheet #' || v_id || ' — ' || case when v_ket_luan = 'dat' then 'ĐẠT' else 'KHÔNG ĐẠT' end
      || case when v_ng is not null then '. NG: ' || v_ng else '' end
      || case when coalesce(trim(p_data->>'phu_tung_thay'), '') <> '' then '. Phụ tùng thay: ' || trim(p_data->>'phu_tung_thay') else '' end
      || case when coalesce(trim(p_data->>'ghi_chu'), '') <> '' then '. ' || trim(p_data->>'ghi_chu') else '' end;
    v_id_log := 'BD-' || duc_normalize_name(v_kh.ma_khuon) || '-' || to_char(v_now, 'YYYYMMDDHH24MISS');
    insert into duc_khuon_bao_duong_log (
      id_log, ma_khuon, loai, ngay, shot_tai_thoi_diem, nguoi_thuc_hien, mo_ta,
      chi_phi, thoi_gian_dung_phut, thoi_diem_ghi
    ) values (
      v_id_log, v_kh.ma_khuon, v_kh.loai, v_ngay, coalesce(v_mold.tong_shot_luy_ke, 0),
      trim(p_data->>'nguoi_thuc_hien'), v_mo_ta, nullif(p_data->>'chi_phi', '')::numeric, v_dung, v_now
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

  return jsonb_build_object('ok', true, 'id', v_id, 'trang_thai', 'hoan_thanh', 'id_log', v_id_log, 'reset_dong_ho', coalesce(v_reset, false));
end;
$$;
revoke execute on function duc_khuon_cs_luu(bigint, jsonb, boolean) from public, anon;
grant execute on function duc_khuon_cs_luu(bigint, jsonb, boolean) to authenticated;
