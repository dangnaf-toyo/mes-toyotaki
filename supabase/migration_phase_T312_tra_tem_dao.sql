-- T312 (22/11/2026): tra thùng → dao (Việc 4 SPEC thay dao).
-- Với mỗi bước Gia công đã Xong của các tem, trả danh sách dao đang lắp trên máy
-- lúc thùng Xong: vị trí, mã dao, cạnh, % tuổi thọ tính tới thùng đó (gồm thùng đó).
-- Dùng ở truy-xuat-nguon-goc.html.

create or replace function public.gc_tem_dao(p_tags text[])
returns table (
  tag_no text, buoc integer, ma_may text, ma_sp text, xong_luc timestamptz, sl_ra numeric,
  vi_tri text, ma_dao text, ten_chuan text, canh integer, so_canh integer,
  so_dung numeric, tuoi_tho integer, pct numeric
)
language sql stable security definer set search_path = public as $$
  select b.tag_no, b.buoc, b.ma_may, b.ma_sp, b.xong_luc, b.sl_ra,
    t.vi_tri, t.ma_dao, d.ten_chuan, t.canh, d.so_canh,
    x.so_dung, x.tuoi_tho,
    case when coalesce(x.tuoi_tho, 0) > 0 then round(x.so_dung * 100 / x.tuoi_tho) end as pct
  from gc_tem_buoc b
  join gc_dao_tren_may t on t.ma_may = b.ma_may and t.lap_luc <= b.xong_luc
    and (t.thao_luc is null or t.thao_luc > b.xong_luc)
  join gc_dao_cu d on d.id = t.id_dao
  left join gc_bo_dao bo on bo.ma_sp = t.ma_sp and bo.buoc = t.buoc and bo.vi_tri = t.vi_tri and bo.id_dao = t.id_dao
  cross join lateral (
    select coalesce(bo.tuoi_tho_chuan, d.tuoi_tho_chuan) as tuoi_tho,
      t.so_ct_dau * coalesce(bo.so_lan_ct, 1)
        + gc_dao_so_dung(t.ma_may, t.vi_tri, t.id_dao, t.lap_luc, b.xong_luc + interval '1 microsecond', coalesce(bo.so_lan_ct, 1)) as so_dung
  ) x
  where b.tag_no = any(p_tags) and b.xong_luc is not null and b.bo_luc is null
  order by b.tag_no, b.xong_luc, t.vi_tri;
$$;
revoke execute on function public.gc_tem_dao(text[]) from public, anon;
grant execute on function public.gc_tem_dao(text[]) to authenticated;
