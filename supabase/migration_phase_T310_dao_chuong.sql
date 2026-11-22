-- T310 (22/11/2026): chuông cảnh báo tuổi thọ dao — Việc 3 trong SPEC_Quan_ly_thay_dao_MES.md.
--   * Dao đang lắp đạt 80% tuổi thọ → chuông "Dao sắp hết" 1 lần cho tổ trưởng Gia công.
--   * Đạt 100% → chuông "Dao hết tuổi thọ" cho tổ trưởng + QLBP Gia Công, nhắc lại mỗi 24 giờ tới khi thay.
--   * Thay / xoay cạnh / tháo → chuông của dao đó tự tắt (lần quét kế tiếp).
--   * Tổ trưởng Gia công = tài khoản trưởng ca có tick bộ phận "Gia Công" (Quản lý tài khoản).
--     Chưa ai được tick → chuông 80% gửi QLBP Gia Công.
--   * Cron gc_dao_nhac mỗi 10 phút (số chi tiết tính từ thùng Xong, không có sự kiện riêng).
--   khoa chuông: dao_cu:<id gc_dao_tren_may>:80 / :100
-- Trạng thái: Đã chạy STAGING + PROD 22/11/2026.
-- An toàn chạy lại.

alter table public.cv_thong_bao drop constraint if exists cv_thong_bao_nguon_check;
alter table public.cv_thong_bao add constraint cv_thong_bao_nguon_check
  check (nguon = any (array['cong_viec','khsx','bd_khuon','ipqc','ncp','tai_lieu','tieu_chuan','thay_doi','dao_cu']));

create or replace function public.gc_dao_nhac()
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare r record; v_n int := 0; v_ql uuid[]; v_tt uuid[]; v_khoa text; v_cu timestamptz; v_lk text; v_ten text;
begin
  v_ql := cv_pd_ds_role(array['quan_ly_bo_phan'], 'Gia Công');
  v_tt := cv_pd_ds_role(array['truong_ca'], 'Gia Công');
  if cardinality(v_tt) = 0 then v_tt := v_ql; end if;

  -- 1) dao đã tháo / đã xoay cạnh → tắt chuông
  update cv_thong_bao tb set da_xu_ly = true
  where tb.nguon = 'dao_cu' and tb.can_xu_ly and not tb.da_xu_ly and tb.khoa like 'dao_cu:%'
    and not exists (select 1 from gc_dao_tren_may t where t.thao_luc is null and t.id::text = split_part(tb.khoa, ':', 2));

  -- 2) dao đang lắp từ 80% tuổi thọ
  for r in
    select v.id, v.ma_may, v.vi_tri, v.ma_dao, v.ten_chuan, v.canh, v.so_canh, v.so_dung, v.tuoi_tho, v.tuoi_tho_theo,
      floor(v.so_dung * 100.0 / v.tuoi_tho)::int as pct
    from gc_dao_tren_may_v v
    where v.thao_luc is null and v.tuoi_tho > 0 and v.tuoi_tho_theo <> 'khong' and v.so_dung * 100 >= v.tuoi_tho * 80
  loop
    v_lk := 'gia-cong-dashboard.html?may=' || replace(r.ma_may, ' ', '%20');
    v_ten := r.ma_may || ' · ' || r.vi_tri || ' · ' || r.ma_dao
      || case when coalesce(r.so_canh, 1) > 1 then ' (cạnh ' || r.canh || '/' || r.so_canh || ')' else '' end
      || ' đã chạy ' || replace(to_char(round(r.so_dung), 'FM999,999,990'), ',', '.') || '/' || replace(to_char(r.tuoi_tho, 'FM999,999,990'), ',', '.')
      || case when r.tuoi_tho_theo = 'lo_ren' then ' lỗ' else '' end || ' (' || r.pct || '%)';
    if r.pct >= 100 then
      v_khoa := 'dao_cu:' || r.id || ':100';
      select max(created_at) into v_cu from cv_thong_bao where khoa = v_khoa;
      if v_cu is null or v_cu < now() - interval '24 hours' then
        perform cv_pd_xong(v_khoa);
        perform cv_pd_xong('dao_cu:' || r.id || ':80');
        v_n := v_n + cv_pd_gui(v_tt || v_ql, 'dao_cu', 'dao_het', v_khoa, v_lk,
          v_ten || ' — hết tuổi thọ, cần thay dao.', true);
      end if;
    else
      v_khoa := 'dao_cu:' || r.id || ':80';
      if not exists (select 1 from cv_thong_bao where khoa = v_khoa) then
        v_n := v_n + cv_pd_gui(v_tt, 'dao_cu', 'dao_sap_het', v_khoa, v_lk,
          v_ten || ' — sắp hết tuổi thọ, chuẩn bị dao thay.', true);
      end if;
    end if;
  end loop;
  return v_n;
end;
$function$;
revoke execute on function public.gc_dao_nhac() from public, anon, authenticated;

select cron.unschedule('gc_dao_nhac') where exists (select 1 from cron.job where jobname = 'gc_dao_nhac');
select cron.schedule('gc_dao_nhac', '*/10 * * * *', 'select public.gc_dao_nhac();');
