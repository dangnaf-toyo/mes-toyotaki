-- ============================================================================
-- Phase T168 — Wallboard màn 5: Bảng công việc (module T161/T165).
-- wallboard_cong_viec(p_khoa): việc đang mở (mới / đang làm / chờ duyệt) CÔNG KHAI
-- — việc hien_thi = 'han_che' không bao giờ lên TV — kèm nhóm ưu tiên (Quan trọng ×
-- Gấp hiệu lực, giống view cv_cong_viec_v), tên người làm, tiến độ bước / việc con;
-- và số việc hoàn thành 7 ngày qua (đúng hạn bao nhiêu).
-- Cùng cơ chế khoá như tong_quan_hom_nay (T160): đã đăng nhập hoặc khoá hợp lệ.
-- An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create or replace function public.wallboard_cong_viec(p_khoa text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null and (p_khoa is null or not exists (select 1 from wallboard_khoa where khoa = p_khoa)) then
    return jsonb_build_object('ok', false, 'error', 'Link wallboard không hợp lệ hoặc đã bị thu hồi');
  end if;
  return jsonb_build_object(
    'ok', true,
    'now', now(),
    'viec', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 't', c.tieu_de, 'lam', cv_ten_nguoi(c.nguoi_lam), 'bp', c.bo_phan, 'tt', c.trang_thai,
        'nhom', case when c.quan_trong and g.gap then 1 when c.quan_trong then 2 when g.gap then 3 else 4 end,
        'han', c.han, 'qh', now() > c.han, 'cha', c.viec_cha_id is not null,
        'buoc', ck.n, 'buoc_xong', ck.x, 'con', vc.n, 'con_xong', vc.x) order by c.han)
      from cv_cong_viec c
      cross join lateral (select c.gap or c.han <= now() + interval '2 days' as gap) g
      cross join lateral (select count(*)::int n, (count(*) filter (where k.xong))::int x from cv_checklist k where k.cong_viec_id = c.id) ck
      cross join lateral (select count(*)::int n, (count(*) filter (where v.trang_thai = 'hoan_thanh'))::int x
        from cv_cong_viec v where v.viec_cha_id = c.id and v.trang_thai <> 'huy') vc
      where c.hien_thi = 'cong_khai' and c.trang_thai in ('moi', 'dang_lam', 'cho_duyet')), '[]'::jsonb),
    'xong7', (select jsonb_build_object('n', count(*), 'dung_han', count(*) filter (where dung_han)) from cv_cong_viec
      where hien_thi = 'cong_khai' and trang_thai = 'hoan_thanh' and hoan_thanh_luc >= now() - interval '7 days'));
end $$;
revoke all on function public.wallboard_cong_viec(text) from public;
grant execute on function public.wallboard_cong_viec(text) to anon, authenticated;
