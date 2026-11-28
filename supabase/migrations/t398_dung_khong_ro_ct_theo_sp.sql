CREATE OR REPLACE FUNCTION public.duc_dung_khong_ro_ca(p_ngay date, p_ca text, p_phuong_an_ca text, p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
-- T398: cycle_time_s = giây/SẢN PHẨM (không phải giây/shot).
-- Phút chạy = [(OK+NG) + shot nóng × cavity] × CT / 60.
declare
  v_sw jsonb; v_bw jsonb; v_ws timestamptz; v_end timestamptz; v_we timestamptz;
  v_chuan numeric; v_phut_ca numeric; v_br tstzmultirange := '{}'::tstzmultirange; v_kq jsonb;
begin
  v_sw := duc_get_shift_window(p_ngay, p_phuong_an_ca, p_ca);
  if v_sw is null then return '[]'::jsonb; end if;
  v_chuan := case
    when p_phuong_an_ca = '2 ca 12h' and p_ca = 'Ca ngày' then 675
    when p_phuong_an_ca = '2 ca 12h' and p_ca = 'Ca đêm' then 660
    when p_phuong_an_ca = '2 ca 8h' and p_ca in ('Ca 1', 'Ca 2') then 435 end;
  if v_chuan is null then return '[]'::jsonb; end if;

  v_ws := (v_sw->>'start')::timestamptz;
  v_end := (v_sw->>'end')::timestamptz;
  v_we := least(p_now, v_end);
  if v_we <= v_ws then return '[]'::jsonb; end if;
  v_bw := duc_get_break_window(p_ngay, p_phuong_an_ca, p_ca);
  if v_bw is not null then
    v_br := tstzmultirange(tstzrange((v_bw->>'start')::timestamptz, (v_bw->>'end')::timestamptz));
  end if;
  v_phut_ca := v_chuan - greatest(0, extract(epoch from (v_end - v_we)) - duc_sum_break_overlap(v_we, v_end, v_bw)) / 60;

  with r as (
    select c.ma_may, c.sp_start_time, c.sp_end_time,
           coalesce(c.tt_ca, 0) tt, coalesce(c.so_luong_ng, 0) ng, coalesce(c.so_shot_nong_khuon, 0) sn,
           p.cavity cav, p.cycle_time_s ct
    from duc_ca_hien_tai c left join master_products p on p.ma_sp = c.ma_sp
    where c.ngay = p_ngay and c.ca = p_ca and c.ma_sp is not null and c.ma_sp <> '' and c.kh_ca is not null
      and not duc_la_may_dap(c.ma_may) and not duc_ca_khong_sx(p_ngay, c.ma_may)),
  nhom as (
    select ma_may,
           max(tt + ng) sp_sx, max(sn) sn, max(cav) cav, max(ct) ct,
           bool_and(coalesce(cav, 0) > 0 and coalesce(ct, 0) > 0) du
    from r group by ma_may, sp_start_time, sp_end_time),
  may as (
    select ma_may, sum((coalesce(sp_sx, 0) + sn * coalesce(cav, 0)) * coalesce(ct, 0)) / 60 phut_chay, bool_and(du) du
    from nhom group by ma_may),
  dung as (
    select m.ma_may,
      (select coalesce(sum(extract(epoch from upper(x) - lower(x))), 0) / 60
       from unnest(((
         select coalesce(range_agg(rg), '{}'::tstzmultirange) from (
           select tstzrange(l.gio_phat_sinh, l.gio_tro_lai) rg from duc_su_co_log l
            where l.ma_may = m.ma_may and l.ngay = p_ngay and l.ca = p_ca and l.gio_tro_lai > l.gio_phat_sinh
           union all
           select tstzrange(greatest(c.open_gio_phat_sinh, v_ws), v_we) from duc_ca_hien_tai c
            where c.ma_may = m.ma_may and c.ngay = p_ngay and c.ca = p_ca and c.open_gio_phat_sinh is not null
              and greatest(c.open_gio_phat_sinh, v_ws) < v_we
           union all
           select tstzrange(greatest(t.gio_phat_sinh, v_ws), v_we) from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong
            where c.ma_may = m.ma_may and c.ngay = p_ngay and c.ca = p_ca and greatest(t.gio_phat_sinh, v_ws) < v_we) q
       ) * tstzmultirange(tstzrange(v_ws, v_we))) - v_br) x) phut_sc
    from may m)
  select coalesce(jsonb_agg(jsonb_build_object(
           'ma_may', m.ma_may,
           'phut_ca', round(v_phut_ca),
           'phut_chay', case when m.du then round(m.phut_chay) end,
           'phut_su_co', round(d.phut_sc),
           'phut_khong_ro', case when m.du then greatest(0, round(v_phut_ca - m.phut_chay - d.phut_sc)) end)
         order by m.ma_may), '[]'::jsonb)
    into v_kq
  from may m join dung d on d.ma_may = m.ma_may;
  return v_kq;
end;
$function$;
