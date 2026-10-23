-- ============================================================================
-- Phase T160 — Trang chủ "Toàn cảnh nhà máy hôm nay" + Wallboard Smart TV.
--
-- tong_quan_hom_nay(p_khoa) trả về MỘT gói jsonb số liệu thô của ngày sản xuất
-- hiện tại (trước 06:00 = ngày hôm trước, vì ca đêm thuộc ngày bắt đầu ca).
-- index.html và wallboard.html cùng gọi hàm này rồi tự tính ở trình duyệt
-- (shared/tong-quan.js).
--   - Người đã đăng nhập: gọi không cần khoá.
--   - Smart TV (không đăng nhập): wallboard.html?k=<khoá> — khoá nằm trong
--     bảng wallboard_khoa; xoá dòng = thu hồi link. Chỉ trả số liệu tổng hợp,
--     không có tên người, không ghi được gì.
-- An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create table if not exists public.wallboard_khoa (
  khoa text primary key default encode(extensions.gen_random_bytes(18), 'hex'),
  ten text not null,
  tao_luc timestamptz not null default now(),
  nguoi_tao text
);
alter table public.wallboard_khoa enable row level security;
revoke all on public.wallboard_khoa from anon, authenticated;
grant select, insert, delete on public.wallboard_khoa to authenticated;
drop policy if exists "wallboard khoa admin" on public.wallboard_khoa;
create policy "wallboard khoa admin" on public.wallboard_khoa for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

create or replace function public.tong_quan_hom_nay(p_khoa text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_local timestamp := now() at time zone 'Asia/Ho_Chi_Minh';
  v_ngay date;
  v_tu date;
  v_tuan date;
  v_cot text;
  v_kh_ngay numeric;
begin
  if auth.uid() is null and (p_khoa is null or not exists (select 1 from wallboard_khoa where khoa = p_khoa)) then
    return jsonb_build_object('ok', false, 'error', 'Link wallboard không hợp lệ hoặc đã bị thu hồi');
  end if;
  v_ngay := case when v_local::time < time '06:00' then v_local::date - 1 else v_local::date end;
  v_tu := v_ngay - 13;
  v_tuan := v_ngay - (extract(isodow from v_ngay)::int - 1);
  v_cot := (array['t2','t3','t4','t5','t6','t7','cn'])[extract(isodow from v_ngay)::int];
  execute format('select coalesce(sum(%I), 0) from duc_khsx_tuan_plan where tuan_bat_dau = $1', v_cot) into v_kh_ngay using v_tuan;

  return (
  with bc as (select ngay, ca from duc_bao_cao_ca),
  latest as (
    select distinct on (c.ma_may) c.ma_may, c.ngay, c.ca, c.ma_sp, c.open_gio_phat_sinh
    from duc_ca_hien_tai c where c.ma_may is not null
    order by c.ma_may, c.row_seq desc
  ),
  active as (
    select l.* from latest l
    where l.ma_sp is not null
      and (l.open_gio_phat_sinh is not null or not exists (select 1 from bc where bc.ngay = l.ngay and bc.ca = l.ca))
  ),
  rows_active as (
    select c.ma_may, c.ma_sp, c.ngay, c.ca, c.phuong_an_ca, c.kh_ca, c.tt_ca, c.so_luong_ng,
           c.open_loai_su_co, c.open_gio_phat_sinh, c.open_van_de, c.row_seq
    from duc_ca_hien_tai c join active a on a.ma_may = c.ma_may and a.ngay = c.ngay and a.ca = c.ca
  )
  select jsonb_build_object(
    'ok', true,
    'now', v_now,
    'ngay', v_ngay,
    'kh_ngay', v_kh_ngay,
    'may', coalesce((select jsonb_agg(ma_may order by ma_may) from master_machines where bo_phan = 'Đúc' or bo_phan is null), '[]'::jsonb),
    'dong', coalesce((select jsonb_agg(to_jsonb(r) order by r.ma_may, r.row_seq) from rows_active r), '[]'::jsonb),
    'bao_cao', coalesce((select jsonb_agg(jsonb_build_object('ngay', ngay, 'ca', ca, 'kh', tong_kh_ca, 'tt', tong_tt_ca, 'ng', tong_ng_ca,
        'oee', oee_ca, 'phut_dung', tong_phut_dung_ca, 'su_co', so_su_co_ca, 'ket_luc', thoi_diem_ket_ca) order by ngay, thoi_diem_ket_ca)
      from duc_bao_cao_ca where ngay between v_tu and v_ngay), '[]'::jsonb),
    'su_co', coalesce((select jsonb_agg(jsonb_build_object('ngay', ngay, 'may', ma_may, 'loai', loai_su_co, 'phut', thoi_gian_dung_phut,
        'xong', gio_tro_lai is not null, 'van_de', left(van_de, 160)))
      from duc_su_co_log where ngay between v_tu and v_ngay), '[]'::jsonb),
    'oqc', coalesce((select jsonb_agg(jsonb_build_object('ngay', d, 'n', n, 'ng', ng) order by d) from (
        select inspection_date d, sum(total_qty) n, sum(ng_qty) ng from oqc_daily_inspection
        where inspection_date between v_tu and v_ngay group by 1) o), '[]'::jsonb),
    'oqc_ma', coalesce((select jsonb_agg(jsonb_build_object('ma', o.p, 'n', o.n, 'ng', o.ng, 'cl', h.cl)) from (
        select product_code p, sum(total_qty) n, sum(ng_qty) ng from oqc_daily_inspection
        where inspection_date = v_ngay and total_qty > 0 group by 1) o left join oqc_ng_cau_hinh h on h.ma_sp = o.p), '[]'::jsonb),
    'oqc_mt', (select muc_tieu from oqc_ng_cau_hinh where ma_sp = '*'),
    'ncp', coalesce((select jsonb_agg(jsonb_build_object('id', id_ncp, 'ma', ma_sp, 'may', ma_may, 'tt', trang_thai, 'ngay', ngay_tao) order by ngay_tao)
      from duc_ncp where coalesce(trang_thai, '') <> 'dong'), '[]'::jsonb),
    'ipqc', coalesce((select jsonb_agg(jsonb_build_object('may', k.ma_may, 'ma', k.ma_sp, 'kq', k.ket_qua, 'luc', k.thoi_diem_kiem_thuc_te) order by k.thoi_diem_kiem_thuc_te)
      from duc_ipqc_checkpoint k
      where k.trang_thai = 'da_kiem' and k.ket_qua in ('NG', 'CANH_BAO')
        and k.thoi_diem_kiem_thuc_te >= ((v_ngay + time '06:00') at time zone 'Asia/Ho_Chi_Minh')
        and not exists (select 1 from duc_ipqc_continue_request q where q.checkpoint_id = k.id_checkpoint)
        and not exists (select 1 from duc_ipqc_canh_bao_dong d where d.id_checkpoint = k.id_checkpoint)), '[]'::jsonb),
    'ipqc_tre', (select count(*) from duc_ipqc_checkpoint k join active a on a.ma_may = k.ma_may and a.ngay = k.ngay and a.ca = k.ca
      where k.trang_thai = 'cho_kiem' and k.han_kiem < v_now),
    'nhap_kho', (select coalesce(sum(tong_so_luong), 0) from oqc_pallet
      where thoi_diem_nhap_kho >= ((v_ngay + time '06:00') at time zone 'Asia/Ho_Chi_Minh'))
  ));
end $$;
revoke all on function public.tong_quan_hom_nay(text) from public;
grant execute on function public.tong_quan_hom_nay(text) to anon, authenticated;

-- Khoá đầu tiên cho TV văn phòng (đổi/thu hồi: xoá dòng, thêm dòng mới).
insert into public.wallboard_khoa (ten, nguoi_tao)
select 'TV nhà máy', 'T160' where not exists (select 1 from public.wallboard_khoa);
