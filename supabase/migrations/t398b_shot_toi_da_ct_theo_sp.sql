-- T398: cycle_time_s = giây/SẢN PHẨM → 1 shot = CT × cavity giây (tối thiểu 6s).
CREATE OR REPLACE FUNCTION public.duc_shot_toi_da_ca(p_id_dong text)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select ceil(
    coalesce(extract(epoch from ((w->>'end')::timestamptz - (w->>'start')::timestamptz)), 43200)
    / greatest(coalesce(nullif(mp.cycle_time_s, 0) * greatest(coalesce(mp.cavity, 1), 1), 6), 6) * 1.5)
  from duc_ca_hien_tai c
  left join master_products mp on mp.ma_sp = c.ma_sp
  cross join lateral (select duc_get_shift_window(c.ngay, c.phuong_an_ca, c.ca) w) x
  where c.id_dong = p_id_dong
$function$;
