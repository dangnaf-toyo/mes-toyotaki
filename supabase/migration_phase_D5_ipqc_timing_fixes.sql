-- ============================================================================
-- Giai đoạn 5 (bỏ Google) — Sửa mốc thời gian/điểm kích hoạt cho 3 loại điểm
-- kiểm IPQC, theo yêu cầu nghiệp vụ xác nhận 2026-08-15:
--
-- 1) "Sau xử lý sự cố" (sau_su_co): trước đây tạo checkpoint LÚC ĐÓNG (xử lý
--    xong) sự cố. Nay tạo NGAY LÚC MỞ (báo) sự cố — bỏ hẳn việc tạo lúc đóng.
--    Mốc bắt đầu đếm giờ chờ (han_kiem) = giờ phát sinh sự cố thật (p_gio_phat_sinh),
--    không phải lúc trưởng ca bấm nút.
-- 2) "Lên khuôn/SP mới" (doi_khuon): giữ nguyên điểm kích hoạt, chỉ sửa mốc
--    đếm giờ cho trường hợp đổi SP giữa ca (duc_change_product) — dùng đúng
--    giờ bắt đầu đổi khuôn thật (p_gio_bat_dau_doi_khuon, đã có sẵn tham số
--    này nhưng trước đây KHÔNG được truyền vào checkpoint) thay vì giờ gọi RPC.
--    2 điểm tạo dòng mới (duc_upsert_plan/duc_assign_paired_plan) không có mốc
--    "bắt đầu sự kiện" tách rời — giữ nguyên now() (đúng = lúc dòng bắt đầu).
-- 3) "Định kỳ" (dinh_ky): bỏ hẳn việc lưu sẵn dòng checkpoint (trước đây do 1
--    trigger quét định kỳ bên Apps Script tạo) — nay TÍNH TRỰC TIẾP lúc tải
--    màn hình IPQC: mọi máy đang chạy đều coi là có 1 điểm định kỳ, đếm giờ từ
--    LẦN KIỂM HOÀN THÀNH GẦN NHẤT của máy đó (bất kỳ loại kiểm nào — đã kiểm
--    là tính như đã "chạm" vào máy, reset đồng hồ định kỳ). Dòng checkpoint
--    thật trong bảng chỉ được tạo (materialize) khi IPQC thật sự bấm vào kiểm
--    (xem ipqc.html — gọi duc_request_ipqc_check ngay trước khi mở form kiểm).
--
--    ⚠️ Cần tắt thủ công trigger thời gian `trigger_ipqcScanDinhKy_` trong
--    Apps Script project "Dashboard Đúc" (Triggers → xoá trigger này) — nếu
--    không, nó vẫn chèn thêm dòng 'dinh_ky' cũ song song, gây trùng lặp.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ── 1) duc_open_incident — tạo checkpoint sau_su_co ngay lúc mở sự cố ───────
create or replace function duc_open_incident(p_id_dong text, p_loai text, p_gio_phat_sinh timestamptz, p_van_de text, p_noi_dung_xu_ly text, p_dam_nhiem text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_result jsonb;
begin
  if p_loai is null or trim(p_loai) = '' then return jsonb_build_object('ok', false, 'error', 'Invalid incident type'); end if;
  if p_gio_phat_sinh is null then return jsonb_build_object('ok', false, 'error', 'Chưa nhập giờ phát sinh'); end if;
  if p_gio_phat_sinh > now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Giờ phát sinh không được ở tương lai'); end if;

  v_result := duc_set_incident_open(p_id_dong, p_loai, p_gio_phat_sinh, p_van_de, p_noi_dung_xu_ly, p_dam_nhiem);

  if (v_result->>'ok')::boolean then
    -- Vừa báo sự cố → bắt buộc IPQC đến kiểm tra ngay, đếm giờ chờ từ lúc sự
    -- cố thật sự phát sinh. Lỗi ở đây không được làm hỏng luồng mở sự cố chính.
    begin
      perform duc_request_ipqc_check(p_id_dong, 'sau_su_co', null, p_gio_phat_sinh);
    exception when others then
      null;
    end;
  end if;

  return v_result;
end;
$$;
revoke execute on function duc_open_incident(text, text, timestamptz, text, text, text, text) from anon;
grant execute on function duc_open_incident(text, text, timestamptz, text, text, text, text) to authenticated;

-- ── 2) duc_resolve_incident — bỏ việc tạo checkpoint sau_su_co lúc đóng ─────
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

  -- (Đã bỏ việc tạo checkpoint IPQC 'sau_su_co' ở đây — nay tạo ngay lúc MỞ
  -- sự cố, xem duc_open_incident.)

  return jsonb_build_object(
    'ok', true, 'id_ban_ghi', v_last_id, 'id_ban_ghi_list', to_jsonb(v_created_ids),
    'thoi_gian_dung_phut', v_total_phut
  );
end;
$$;
revoke execute on function duc_resolve_incident(text, timestamptz, text, text, text) from anon;
grant execute on function duc_resolve_incident(text, timestamptz, text, text, text) to authenticated;

-- ── 3) duc_change_product — đếm giờ doi_khuon từ giờ bắt đầu đổi khuôn thật ─
create or replace function duc_change_product(
  p_old_id_dong text, p_new_ma_sp text, p_new_ten_sp text, p_new_so_khuon text,
  p_new_kh_ca numeric, p_new_kh_tuan numeric, p_gio_bat_dau_doi_khuon timestamptz, p_dam_nhiem text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_old record; v_new_id_dong text; v_win jsonb; v_carry_shot numeric; v_now timestamptz := now();
begin
  if p_new_ma_sp is null or trim(p_new_ma_sp) = '' then return jsonb_build_object('ok', false, 'error', 'Chưa nhập mã SP mới'); end if;
  if p_new_kh_ca is null or p_new_kh_ca <= 0 then return jsonb_build_object('ok', false, 'error', 'Chưa nhập KH ca cho SP mới'); end if;
  if p_gio_bat_dau_doi_khuon is null then return jsonb_build_object('ok', false, 'error', 'Chưa nhập giờ bắt đầu đổi khuôn'); end if;
  if p_new_so_khuon is null or trim(p_new_so_khuon) = '' then return jsonb_build_object('ok', false, 'error', 'Bắt buộc nhập số khuôn'); end if;
  if p_gio_bat_dau_doi_khuon > now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Giờ bắt đầu đổi khuôn không được ở tương lai'); end if;

  select * into v_old from duc_ca_hien_tai where id_dong = p_old_id_dong;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy dòng SP cũ: ' || p_old_id_dong); end if;
  if v_old.open_gio_phat_sinh is not null then return jsonb_build_object('ok', false, 'error', 'Dòng SP cũ đang có sự cố khác. Vui lòng xử lý xong trước khi đổi SP.'); end if;
  if trim(p_new_ma_sp) = trim(coalesce(v_old.ma_sp, '')) then return jsonb_build_object('ok', false, 'error', 'SP mới trùng với SP hiện tại'); end if;

  v_new_id_dong := duc_make_id_dong(v_old.ngay, v_old.ca, v_old.ma_may, p_new_ma_sp);
  if exists (select 1 from duc_ca_hien_tai where id_dong = v_new_id_dong) then
    return jsonb_build_object('ok', false, 'error', 'Máy ' || v_old.ma_may || ' đã có dòng với SP ' || p_new_ma_sp || ' trong ca này');
  end if;

  v_win := duc_get_shift_window(v_old.ngay, v_old.phuong_an_ca, v_old.ca);
  v_carry_shot := v_old.so_shot_cuoi_ca;
  if v_carry_shot is null then select so_shot_cuoi_ca_gan_nhat into v_carry_shot from duc_shot_may where ma_may = v_old.ma_may; end if;

  insert into duc_ca_hien_tai (
    id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, kh_ca, kh_tuan, tt_ca, tt_tuan,
    nv_ca_ngay, nv_ca_dem, open_loai_su_co, open_gio_phat_sinh, open_van_de, open_noi_dung_xu_ly, open_dam_nhiem,
    version, last_updated_by, last_updated_at, so_shot_nong_khuon, so_luong_ng, phan_loai_ng,
    sp_start_time, sp_end_time, so_shot_khuon_snapshot, so_shot_dau_ca, so_shot_cuoi_ca
  ) values (
    v_new_id_dong, v_old.ngay, v_old.ca, v_old.phuong_an_ca, duc_iso_week(v_old.ngay), v_old.ma_may, p_new_ma_sp, coalesce(p_new_ten_sp,''), coalesce(p_new_so_khuon,''),
    p_new_kh_ca, coalesce(p_new_kh_tuan,0), 0, 0, coalesce(v_old.nv_ca_ngay,''), coalesce(v_old.nv_ca_dem,''),
    'C3 - Đổi khuôn', p_gio_bat_dau_doi_khuon, 'Đổi khuôn từ ' || coalesce(v_old.ma_sp,''), 'Đang thực hiện đổi khuôn', coalesce(p_dam_nhiem,''),
    1, p_user, v_now, 0, 0, '', p_gio_bat_dau_doi_khuon, (v_win->>'end')::timestamptz, 0, v_carry_shot, null
  );

  if p_new_so_khuon is not null and p_new_ma_sp is not null then perform duc_ensure_mold_product_mapping(p_new_so_khuon, p_new_ma_sp); end if;
  -- Đếm giờ chờ IPQC từ giờ bắt đầu đổi khuôn thật (p_gio_bat_dau_doi_khuon),
  -- không phải lúc trưởng ca bấm lưu form (có thể muộn hơn nhiều).
  begin perform duc_request_ipqc_check(v_new_id_dong, 'doi_khuon', null, p_gio_bat_dau_doi_khuon); exception when others then null; end;

  return jsonb_build_object('ok', true, 'new_id_dong', v_new_id_dong, 'old_id_dong', p_old_id_dong, 'old_ma_sp', v_old.ma_sp, 'new_ma_sp', p_new_ma_sp, 'ma_may', v_old.ma_may);
end;
$$;
revoke execute on function duc_change_product(text, text, text, text, numeric, numeric, timestamptz, text, text) from anon;
grant execute on function duc_change_product(text, text, text, text, numeric, numeric, timestamptz, text, text) to authenticated;

-- ── 4) duc_get_ipqc_periodic_due — tính điểm "định kỳ" trực tiếp, không lưu
--    sẵn dòng nào. Trả về 1 dòng cho MỖI dòng sản xuất đang active (giống
--    _getActiveIdDongSet_ ở ipqc.html), số phút đã trôi kể từ lần kiểm HOÀN
--    THÀNH gần nhất của MÁY đó (bất kỳ loại kiểm nào); nếu máy chưa từng được
--    kiểm, tính từ lúc dòng hiện tại bắt đầu chạy (sp_start_time). Loại trừ
--    những dòng đang có sẵn 1 checkpoint 'dinh_ky' chưa kiểm (đã được
--    materialize khi IPQC bấm vào kiểm trước đó, tránh hiện trùng). ────────
create or replace function duc_get_ipqc_periodic_due()
returns table(id_dong text, ma_may text, ma_sp text, ngay date, ca text, phut_da_troi int)
language plpgsql
stable
as $$
declare
  v_active_id_dong text[];
begin
  select array_agg(t.id_dong) into v_active_id_dong from (
    select cht.id_dong, cht.ma_may, cht.khuon_kep_voi,
      row_number() over (partition by cht.ma_may order by cht.row_seq desc) as rn
    from duc_ca_hien_tai cht
  ) t
  where t.rn = 1 or exists (
    select 1 from duc_ca_hien_tai c2
    where c2.id_dong = t.khuon_kep_voi
      and (select rn2.rn from (
             select cht2.id_dong, row_number() over (partition by cht2.ma_may order by cht2.row_seq desc) as rn
             from duc_ca_hien_tai cht2
           ) rn2 where rn2.id_dong = t.khuon_kep_voi) = 1
  );

  return query
  select cht.id_dong, cht.ma_may, cht.ma_sp, cht.ngay, cht.ca,
    round(extract(epoch from (now() - coalesce(
      (select max(cp.thoi_diem_kiem_thuc_te) from duc_ipqc_checkpoint cp
        where cp.ma_may = cht.ma_may and cp.trang_thai = 'da_kiem'),
      cht.sp_start_time, cht.last_updated_at
    ))) / 60)::int as phut_da_troi
  from duc_ca_hien_tai cht
  where cht.id_dong = any(v_active_id_dong)
    and cht.ma_sp is not null and cht.ma_sp <> ''
    and not exists (
      select 1 from duc_ipqc_checkpoint cp2
      where cp2.id_dong = cht.id_dong and cp2.trang_thai = 'cho_kiem' and cp2.loai_kiem = 'dinh_ky'
    );
end;
$$;
