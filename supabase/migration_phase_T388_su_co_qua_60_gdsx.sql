-- ============================================================================
-- Phase T388 — Sự cố dừng máy quá 60 phút → chuông cho Giám đốc SX
-- Cron 10 phút/lần quét:
--  (1) Sự cố ĐANG MỞ (duc_ca_hien_tai.open_*) đã dừng ≥ 60' (tính từ giờ phát sinh
--      đầu tiên, kể cả phần ca trước cùng id_su_co).
--  (2) Sự cố vừa ĐÓNG (duc_su_co_log lưu trong 20' gần nhất) tổng dừng > 60'
--      mà chưa báo (vd trưởng ca nhập lùi giờ rồi đóng luôn).
-- Mỗi sự cố báo 1 lần (khoá sc60:<id_su_co>), chuông chỉ để nắm tình hình (không cần xử lý).
-- Chạy lại an toàn.
-- ============================================================================

do $$ declare v text;
begin
  select pg_get_constraintdef(oid) into v from pg_constraint where conname = 'cv_thong_bao_nguon_check';
  if v is not null and v not like '%''su_co''%' then
    execute 'alter table public.cv_thong_bao drop constraint cv_thong_bao_nguon_check';
    execute 'alter table public.cv_thong_bao add constraint cv_thong_bao_nguon_check '
         || replace(v, '])))', ', ''su_co''::text])))');
  end if;
end $$;

create or replace function public.duc_su_co_nhac_gdsx()
returns integer language plpgsql security definer set search_path = public as $$
declare r record; v_n int := 0; v_gd uuid[]; v_khoa text;
begin
  v_gd := cv_pd_ds_role(array['giam_doc_sx']);
  if coalesce(array_length(v_gd, 1), 0) = 0 then return 0; end if;

  -- (1) Đang mở
  for r in
    select o.ma_may, o.id_su_co, o.loai, o.van_de,
           least(o.gps, coalesce((select min(l.gio_phat_sinh) from duc_su_co_log l where l.id_su_co = o.id_su_co), o.gps)) gps
    from (select c.ma_may, c.open_id_su_co id_su_co, max(c.open_loai_su_co) loai, max(c.open_van_de) van_de,
                 min(c.open_gio_phat_sinh) gps
          from duc_ca_hien_tai c
          where c.open_gio_phat_sinh is not null and nullif(c.open_id_su_co, '') is not null
          group by c.ma_may, c.open_id_su_co) o
  loop
    if r.gps > now() - interval '60 minutes' then continue; end if;
    v_khoa := 'sc60:' || r.id_su_co;
    if exists (select 1 from cv_thong_bao where khoa = v_khoa) then continue; end if;
    v_n := v_n + cv_pd_gui(v_gd, 'su_co', 'dung_qua_60', v_khoa, 'duc-dashboard.html',
      '⏱ ' || r.ma_may || ' đang dừng ' || floor(extract(epoch from now() - r.gps) / 60)::int || ' phút (từ '
      || to_char(r.gps at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ') — '
      || coalesce(split_part(r.loai, ' — ', 1), '') || ': ' || left(coalesce(r.van_de, ''), 150), false);
  end loop;

  -- (2) Vừa đóng, tổng dừng > 60'
  for r in
    select l.id_su_co, max(l.ma_may) ma_may, max(l.loai_su_co) loai, max(l.van_de) van_de,
           min(l.gio_phat_sinh) gps, max(l.gio_tro_lai) gtl, sum(coalesce(l.thoi_gian_dung_phut, 0)) phut
    from duc_su_co_log l
    where nullif(l.id_su_co, '') is not null
      and l.id_su_co in (select id_su_co from duc_su_co_log where thoi_diem_luu >= now() - interval '20 minutes')
    group by l.id_su_co
    having sum(coalesce(l.thoi_gian_dung_phut, 0)) > 60
  loop
    v_khoa := 'sc60:' || r.id_su_co;
    if exists (select 1 from cv_thong_bao where khoa = v_khoa) then continue; end if;
    if exists (select 1 from duc_ca_hien_tai where open_id_su_co = r.id_su_co) then continue; end if;
    v_n := v_n + cv_pd_gui(v_gd, 'su_co', 'dung_qua_60', v_khoa, 'duc-dashboard.html',
      '⏱ ' || r.ma_may || ' đã dừng ' || round(r.phut)::int || ' phút ('
      || to_char(r.gps at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI') || '–'
      || coalesce(to_char(r.gtl at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'), '?') || ') — '
      || coalesce(split_part(r.loai, ' — ', 1), '') || ': ' || left(coalesce(r.van_de, ''), 150), false);
  end loop;
  return v_n;
end $$;
revoke all on function public.duc_su_co_nhac_gdsx() from public, anon, authenticated;

select cron.unschedule('duc_su_co_nhac_gdsx') where exists (select 1 from cron.job where jobname = 'duc_su_co_nhac_gdsx');
select cron.schedule('duc_su_co_nhac_gdsx', '1-59/10 * * * *', 'select public.duc_su_co_nhac_gdsx();');
