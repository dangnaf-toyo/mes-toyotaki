-- T271: Bảng điều khiển Gia công — cột phải "Tem chờ Gia công" (giống Bavia).
-- Tem chờ = tem còn SL, chưa lên máy CNC nào, chưa làm bước CNC nào, mã SP có KH Gia công tuần này
-- hoặc đang chạy trên máy trong ca; vị trí hiện tại là Gia Công, hoặc là công đoạn liền trước
-- Gia Công trong lưu trình và đã làm xong ở đó (Đúc: tem Đúc; công đoạn khác: trang_thai = tên công đoạn).
create or replace function public.gc_tem_cho(p_ngay date, p_ca text)
returns jsonb
language sql stable security definer
set search_path to 'public'
as $$
  with tuan as (select p_ngay - (extract(isodow from p_ngay)::int - 1) as t),
  ma as (
    select k.ma_sp from cd_khsx_tuan_plan k, tuan
     where k.cong_doan = 'Gia Công' and k.tuan_bat_dau = tuan.t and coalesce(k.kh_tuan, 0) > 0
    union
    select ma_sp from cd_tram_hien_tai where cong_doan = 'Gia Công' and ngay = p_ngay and ca = p_ca and ma_sp is not null
  ),
  sp as (
    select p.ma_sp, s.steps, array_position(s.steps, 'Gia Công') i
    from master_products p
    cross join lateral (select array_agg(trim(x) order by o) steps
      from unnest(string_to_array(coalesce(p.quy_trinh_cong_doan, ''), ',')) with ordinality u(x, o) where trim(x) <> '') s
    where p.ma_sp in (select ma_sp from ma)
  ),
  tem as (
    select t.tag_no, t.ma_sp, t.so_luong, t.ngay, coalesce(t.may_tt, t.may_duc_chi_thi) may,
      coalesce(v.vi_tri_hien_tai, 'Đúc') vt, coalesce(t.trang_thai, '') tt, sp.steps[sp.i - 1] truoc
    from duc_tem t
    join sp on sp.ma_sp = t.ma_sp and sp.i is not null
    left join cd_v_vi_tri_hien_tai v on v.tag_no = t.tag_no
    where coalesce(t.so_luong, 0) > 0
      and coalesce(t.trang_thai, '') not in ('Chờ sản xuất', 'NG chờ sửa', 'Chờ đóng gói TP', 'Đã đóng gói TP')
      and not exists (select 1 from gc_tem_buoc b where b.tag_no = t.tag_no and b.bo_luc is null)
      and not exists (select 1 from bavia_line_nguon n where n.tag_no = t.tag_no and n.bo_luc is null)
  )
  select coalesce(jsonb_agg(jsonb_build_object('ma_sp', x.ma_sp, 'so_tem', x.so_tem, 'pcs', x.pcs, 'tai_gc', x.tai_gc,
           'tu', x.tu, 'ngay_tu', x.ngay_tu, 'ngay_den', x.ngay_den) order by x.ma_sp), '[]'::jsonb)
  from (
    select ma_sp, count(*) so_tem, sum(so_luong) pcs, count(*) filter (where vt = 'Gia Công') tai_gc,
      string_agg(distinct vt, ', ') filter (where vt <> 'Gia Công') tu, min(ngay) ngay_tu, max(ngay) ngay_den
    from tem
    where vt = 'Gia Công'
       or (vt = truoc and (truoc = 'Đúc' and tag_no not like 'TP%' or tt = truoc))
    group by ma_sp
  ) x
  where auth.uid() is not null;
$$;

revoke all on function public.gc_tem_cho(date, text) from public, anon;
grant execute on function public.gc_tem_cho(date, text) to authenticated;
