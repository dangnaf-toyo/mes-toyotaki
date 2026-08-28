-- ============================================================================
-- D45 — Sửa 2 nhánh ghi duc_su_co_log làm mất MÃ SỰ CỐ (id_su_co = null), rồi
-- backfill 13 dòng F1 đã bị mất mã.
--
-- Triệu chứng: màn hình "Tra cứu lịch sử" của QC Manager (badge phút dừng
-- cạnh mã sự cố cho lần kiểm NG) báo "chưa chốt giờ dừng" cho những sự cố
-- ĐÃ đóng và ĐÃ có thoi_gian_dung_phut. Nguyên nhân: badge dò theo mã sự cố
-- (duc_make_id_su_co = "SC-<máy>-<MMDD>-<HH24MI>"), mà 13/62 dòng loai_su_co
-- = 'F1' trong duc_su_co_log có id_su_co = null.
--
-- 2 nhánh code còn sinh dòng null (đều là bản mới nhất đang chạy):
--   1) duc_close_f1_incident_if_open (migration_phase4_step5) — đóng F1 tự
--      động khi IPQC kiểm lại OK: câu INSERT vào duc_su_co_log KHÔNG có cột
--      id_su_co.
--   2) duc_carry_over_shift (migration_phase4_step7) — chuyển sự cố mở sang
--      ca kế tiếp lúc kết ca: câu INSERT dòng duc_ca_hien_tai mới KHÔNG chép
--      open_id_su_co, nên khi trưởng ca đóng sự cố ở ca sau qua
--      duc_resolve_incident (D13, ghi v_cht.open_id_su_co) thì id_su_co ra
--      null. Bonus: nhánh "bắt buộc IPQC OK" trong D13 khớp
--      cp.id_su_co_goc = v_cht.open_id_su_co cũng hụt khi open_id_su_co null.
--
-- Sửa: bổ sung cột thiếu ở cả 2 hàm (không đổi hành vi khác), rồi UPDATE
-- backfill các dòng F1 null bằng duc_make_id_su_co(ma_may, gio_phat_sinh) —
-- đúng công thức badge dựng lại từ thời điểm kiểm NG (trùng phút vì sự cố F1
-- mở trong cùng giao dịch với lần kiểm). Đã đối chiếu: 13 mã tính ra không
-- trùng id_su_co nào đang có (không va chạm).
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ── 1) duc_close_f1_incident_if_open — thêm cột id_su_co vào INSERT ──────────
create or replace function duc_close_f1_incident_if_open(p_id_dong text, p_nguoi_kiem text)
returns boolean
language plpgsql
security definer
as $$
declare
  v_cht record;
  v_stt int;
  v_id_ban_ghi text;
begin
  select ngay, ca, ma_may, ma_sp, ten_sp, so_khuon, open_loai_su_co, open_gio_phat_sinh,
         open_van_de, open_dam_nhiem, open_id_su_co
  into v_cht from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found or v_cht.open_loai_su_co is null or left(v_cht.open_loai_su_co, 2) <> 'F1'
     or v_cht.open_gio_phat_sinh is null then
    return false;
  end if;

  select count(*) + 1 into v_stt from duc_su_co_log
    where ngay = v_cht.ngay and ca = v_cht.ca and ma_may = v_cht.ma_may and ma_sp = v_cht.ma_sp;
  v_id_ban_ghi := p_id_dong || '_' || v_stt;

  insert into duc_su_co_log (
    id_ban_ghi, ngay, ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon, loai_su_co,
    gio_phat_sinh, gio_tro_lai, thoi_gian_dung_phut, van_de, noi_dung_xu_ly,
    dam_nhiem, ghi_chu, truong_ca, thoi_diem_luu, van_de_edited, id_su_co
  ) values (
    v_id_ban_ghi, v_cht.ngay, v_cht.ca, duc_iso_week(v_cht.ngay), v_cht.ma_may, v_cht.ma_sp, v_cht.ten_sp, v_cht.so_khuon,
    v_cht.open_loai_su_co, v_cht.open_gio_phat_sinh, now(),
    round(extract(epoch from (now() - v_cht.open_gio_phat_sinh)) / 60),
    v_cht.open_van_de, 'IPQC kiểm tra lại: OK — cho phép sản xuất tiếp' || case when p_nguoi_kiem is not null then ' (' || p_nguoi_kiem || ')' else '' end,
    coalesce(p_nguoi_kiem, v_cht.open_dam_nhiem), '', '', now(), 'No',
    coalesce(v_cht.open_id_su_co, duc_make_id_su_co(v_cht.ma_may, v_cht.open_gio_phat_sinh))
  );

  perform duc_clear_incident_open(p_id_dong, coalesce(p_nguoi_kiem, 'system'));
  return true;
end;
$$;
revoke execute on function duc_close_f1_incident_if_open(text, text) from anon;
grant execute on function duc_close_f1_incident_if_open(text, text) to authenticated;

-- ── 2) duc_carry_over_shift — chép open_id_su_co sang dòng ca kế tiếp ────────
create or replace function duc_carry_over_shift(p_ngay date, p_ca text, p_phuong_an_ca text, p_carry_over_list jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_next jsonb;
  v_item jsonb;
  v_old record;
  v_new_id_dong text;
  v_win jsonb;
  v_kh_ca_moi numeric;
  v_carry_shot numeric;
  v_old_to_new jsonb := '{}'::jsonb;
  v_now timestamptz := now();
  v_carried jsonb := '[]'::jsonb;
begin
  if p_carry_over_list is null or jsonb_array_length(p_carry_over_list) = 0 then
    return jsonb_build_object('carried', '[]'::jsonb, 'next_ngay', null, 'next_ca', null);
  end if;

  v_next := duc_get_next_shift(p_ngay, p_ca, p_phuong_an_ca);
  if v_next is null then
    raise exception 'Không xác định được ca kế tiếp cho % / %', p_phuong_an_ca, p_ca;
  end if;

  for v_item in select * from jsonb_array_elements(p_carry_over_list) loop
    select * into v_old from duc_ca_hien_tai
      where ngay = p_ngay and ca = p_ca and ma_may = (v_item->>'ma_may') and ma_sp = (v_item->>'ma_sp');
    if not found then continue; end if;

    v_new_id_dong := duc_make_id_dong((v_next->>'ngay')::date, v_next->>'ca', v_old.ma_may, v_old.ma_sp);
    if exists (select 1 from duc_ca_hien_tai where id_dong = v_new_id_dong) then continue; end if;

    v_win := duc_get_shift_window((v_next->>'ngay')::date, p_phuong_an_ca, v_next->>'ca');
    v_kh_ca_moi := coalesce((v_item->>'kh_ca_moi')::numeric, v_old.kh_ca, 0);

    v_carry_shot := v_old.so_shot_cuoi_ca;
    if v_carry_shot is null then
      select so_shot_cuoi_ca_gan_nhat into v_carry_shot from duc_shot_may where ma_may = v_old.ma_may;
    end if;

    insert into duc_ca_hien_tai (
      id_dong, ngay, ca, phuong_an_ca, tuan_sx, ma_may, ma_sp, ten_sp, so_khuon,
      kh_ca, kh_tuan, tt_ca, tt_tuan, nv_ca_ngay, nv_ca_dem,
      open_loai_su_co, open_gio_phat_sinh, open_van_de, open_noi_dung_xu_ly, open_dam_nhiem, open_id_su_co,
      version, last_updated_by, last_updated_at,
      so_shot_nong_khuon, so_luong_ng, phan_loai_ng, sp_start_time, sp_end_time, so_shot_khuon_snapshot,
      so_shot_dau_ca, so_shot_cuoi_ca
    ) values (
      v_new_id_dong, (v_next->>'ngay')::date, v_next->>'ca', p_phuong_an_ca, duc_iso_week((v_next->>'ngay')::date),
      v_old.ma_may, v_old.ma_sp, v_old.ten_sp, v_old.so_khuon,
      v_kh_ca_moi, coalesce((v_item->>'kh_tuan_moi')::numeric, v_old.kh_tuan, 0), 0, 0,
      v_old.nv_ca_ngay, v_old.nv_ca_dem,
      case when v_old.open_gio_phat_sinh is not null then v_old.open_loai_su_co else null end,
      v_old.open_gio_phat_sinh,
      v_old.open_van_de,
      case when v_old.open_gio_phat_sinh is not null
        then coalesce(v_old.open_noi_dung_xu_ly, '') || (case when coalesce(v_old.open_noi_dung_xu_ly, '') <> '' then E'\n' else '' end) ||
             '[Chuyển tiếp từ ' || p_ca || ' ' || to_char(p_ngay, 'DD/MM/YYYY') || ']'
        else null end,
      v_old.open_dam_nhiem,
      case when v_old.open_gio_phat_sinh is not null then v_old.open_id_su_co else null end,
      1, 'system@carry-over', v_now,
      0, 0, '', coalesce((v_win->>'start')::timestamptz, v_now), (v_win->>'end')::timestamptz, 0,
      v_carry_shot, null
    );

    v_old_to_new := jsonb_set(v_old_to_new, array[v_old.id_dong], to_jsonb(v_new_id_dong));
    v_carried := v_carried || jsonb_build_array(jsonb_build_object(
      'ma_may', v_old.ma_may, 'ma_sp', v_old.ma_sp, 'kh_ca', v_kh_ca_moi,
      'has_open_incident', v_old.open_gio_phat_sinh is not null
    ));
  end loop;

  for v_old in select id_dong, khuon_kep_voi from duc_ca_hien_tai
    where ngay = p_ngay and ca = p_ca and khuon_kep_voi is not null and khuon_kep_voi <> ''
  loop
    if v_old_to_new ? v_old.id_dong and v_old_to_new ? v_old.khuon_kep_voi then
      update duc_ca_hien_tai set khuon_kep_voi = v_old_to_new->>v_old.khuon_kep_voi
      where id_dong = v_old_to_new->>v_old.id_dong;
    end if;
  end loop;

  return jsonb_build_object('carried', v_carried, 'next_ngay', v_next->>'ngay', 'next_ca', v_next->>'ca');
end;
$$;
revoke execute on function duc_carry_over_shift(date, text, text, jsonb) from anon;
grant execute on function duc_carry_over_shift(date, text, text, jsonb) to authenticated;

-- ── 3) Backfill 13 dòng F1 đã mất mã ───────────────────────────────────────
-- Chỉ đụng dòng loai_su_co = 'F1' và id_su_co IS NULL. Mã dựng lại theo
-- (ma_may, gio_phat_sinh) — cùng công thức duc_make_id_su_co mà badge dùng.
do $$
declare
  v_truoc int;
  v_sau int;
begin
  select count(*) into v_truoc from duc_su_co_log where loai_su_co = 'F1' and id_su_co is null;

  update duc_su_co_log
  set id_su_co = duc_make_id_su_co(ma_may, gio_phat_sinh)
  where loai_su_co = 'F1'
    and id_su_co is null
    and ma_may is not null
    and gio_phat_sinh is not null;

  select count(*) into v_sau from duc_su_co_log where loai_su_co = 'F1' and id_su_co is null;
  raise notice 'Backfill F1 id_su_co: % dòng null trước → % dòng null còn lại (đã gán % dòng).',
    v_truoc, v_sau, v_truoc - v_sau;
end $$;
