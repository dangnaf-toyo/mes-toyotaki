-- T210c — User 04/11/2026: gộp 1 khung đêm 22:00–08:00 cho cả "trưởng ca duyệt thay" (trước là 18:00–06:00)
-- và "tự duyệt" (người khai = người duyệt). 08:00–22:00 không ai tự duyệt, trưởng ca không duyệt thay.
create or replace function public.duc_khuon_ct_la_ca_dem() returns boolean
language sql stable as $$
  -- T210c: khung đêm duy nhất 22:00–08:00 (trưởng ca duyệt thay + tự duyệt)
  select extract(hour from (now() at time zone 'Asia/Ho_Chi_Minh')) >= 22
      or extract(hour from (now() at time zone 'Asia/Ho_Chi_Minh')) < 8;
$$;
create or replace function public.duc_khuon_ct_tu_duyet_duoc() returns boolean
language sql stable security definer set search_path to 'public' as $$
  select duc_khuon_ct_la_ca_dem();
$$;
revoke execute on function public.duc_khuon_ct_la_ca_dem(), public.duc_khuon_ct_tu_duyet_duoc() from public, anon, authenticated;
do $p$
declare d text; n text;
begin
  d := pg_get_functiondef('public.duc_khuon_ct_duyet(bigint,boolean,text,timestamptz)'::regprocedure);
  n := replace(d, '(ca đêm 18:00–06:00: trưởng ca được duyệt thay)', '(22:00–08:00: trưởng ca được duyệt thay)');
  if n <> d then execute n; end if;
end $p$;
