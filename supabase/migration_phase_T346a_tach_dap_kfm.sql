-- T346a (25/11/2026): Tách sản lượng DẬP (máy "Dập …", vd Dập KFM) khỏi sản lượng ĐÚC.
-- Trước đây FCC-KFM-01 bị cộng 2 lần (DC 8 đúc + Dập KFM dập) vào tổng ca / báo cáo tuần / forecast.
-- Đúc xong phải chờ nguội mới dập → thêm số "Chờ dập" = tổng đúc OK − tổng đã dập (từ ngày có dập đầu tiên).

create or replace function public.duc_la_may_dap(p_ma_may text)
returns boolean language sql immutable set search_path to 'public'
as $$ select coalesce(trim(p_ma_may), '') ilike 'Dập %' $$;

alter table public.duc_bao_cao_ca
  add column if not exists tong_kh_dap numeric not null default 0,
  add column if not exists tong_tt_dap numeric not null default 0,
  add column if not exists tong_ng_dap numeric not null default 0;

-- Forecast "Thực tế": chỉ sản lượng ĐÚC
create or replace function public.forecast_thuc_te_duc(p_nam integer)
 returns table(ma_sp text, thang integer, so_luong numeric, so_ng numeric)
 language sql stable set search_path to 'public'
as $function$
  select trim(ma_sp), extract(month from ngay)::int, sum(coalesce(tt_ca, 0)), sum(coalesce(so_luong_ng, 0))
  from duc_lich_su_san_xuat
  where ngay >= make_date(p_nam, 1, 1) and ngay < make_date(p_nam + 1, 1, 1)
    and coalesce(trim(ma_sp), '') <> ''
    and not duc_la_may_dap(ma_may)
  group by 1, 2;
$function$;

-- Chờ dập theo mã: đúc OK − dập TT, tính từ ngày có dòng dập đầu tiên của mã (gồm cả ca đang chạy).
create or replace function public.duc_cho_dap()
 returns table(ma_sp text, tu_ngay date, duc_ok numeric, da_dap numeric, cho_dap numeric)
 language sql stable set search_path to 'public'
as $function$
  with tat_ca as (
    select ngay, ma_may, ma_sp, coalesce(tt_ca, 0) tt from duc_lich_su_san_xuat
    union all
    select c.ngay, c.ma_may, c.ma_sp, coalesce(c.tt_ca, 0) from duc_ca_hien_tai c
     where c.ma_sp is not null and c.ma_sp <> ''
       and not exists (select 1 from duc_lich_su_san_xuat l
                        where l.ngay = c.ngay and l.ca = c.ca and l.ma_may = c.ma_may and l.ma_sp = c.ma_sp)
  ),
  moc as (select ma_sp, min(ngay) tu from tat_ca where duc_la_may_dap(ma_may) group by ma_sp)
  select m.ma_sp, m.tu,
         sum(t.tt) filter (where not duc_la_may_dap(t.ma_may)),
         sum(t.tt) filter (where duc_la_may_dap(t.ma_may)),
         coalesce(sum(t.tt) filter (where not duc_la_may_dap(t.ma_may)), 0)
           - coalesce(sum(t.tt) filter (where duc_la_may_dap(t.ma_may)), 0)
  from moc m join tat_ca t on t.ma_sp = m.ma_sp and t.ngay >= m.tu
  group by m.ma_sp, m.tu
  order by m.ma_sp;
$function$;

revoke execute on function public.duc_cho_dap() from public, anon;
grant execute on function public.duc_cho_dap() to authenticated;
