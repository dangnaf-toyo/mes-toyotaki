-- ============================================================================
-- T88 — Lịch sử vấn đề của 1 khuôn để xem khi bảo dưỡng (check sheet bảo dưỡng
-- khuôn): sự cố (kèm ảnh hiện trạng / sau xử lý, T87) + kết quả IPQC NG / Cảnh
-- báo (kèm ảnh bằng chứng, hạng mục không đạt).
--
-- duc_ipqc_checkpoint không lưu số khuôn -> xác định khuôn của lần kiểm theo
-- (ngày, máy, mã SP) từ: tem đã in (duc_tem, theo ngày), sự cố (duc_su_co_log,
-- theo ngày + ca) và ca đang chạy (duc_ca_hien_tai). Nếu cùng ngày/máy/mã có
-- nhiều khuôn thì trả kèm khuon_khac để giao diện ghi chú "có thể là khuôn khác".
--
-- Hàm chạy theo quyền người gọi (các bảng nguồn đều public read).
-- Chạy trên CẢ 2 project (production + staging). Idempotent.
-- ============================================================================

create or replace function duc_khuon_van_de_lich_su(p_ma_khuon text, p_tu_ngay date)
returns jsonb
language sql
stable
set search_path = public
as $$
with mk as (select trim(coalesce(p_ma_khuon, '')) as k),
anh as (
  select id_su_co,
         coalesce(jsonb_agg(url order by id) filter (where loai = 'truoc'), '[]'::jsonb) as truoc,
         coalesce(jsonb_agg(url order by id) filter (where loai = 'sau'), '[]'::jsonb) as sau
  from duc_su_co_anh group by id_su_co
),
su_co as (
  select l.id_su_co, l.ngay, l.ca, l.ma_may, l.ma_sp, l.loai_su_co as loai, l.gio_phat_sinh, l.gio_tro_lai,
         l.thoi_gian_dung_phut as phut, l.van_de, l.noi_dung_xu_ly as xu_ly, false as dang_mo
  from duc_su_co_log l, mk
  where trim(coalesce(l.so_khuon, '')) = mk.k and l.ngay >= p_tu_ngay
  union all
  select c.open_id_su_co, c.ngay, c.ca, c.ma_may, c.ma_sp, c.open_loai_su_co, c.open_gio_phat_sinh, null,
         null, c.open_van_de, c.open_noi_dung_xu_ly, true
  from duc_ca_hien_tai c, mk
  where trim(coalesce(c.so_khuon, '')) = mk.k and c.open_gio_phat_sinh is not null
),
-- (ngày, ca|null, máy, mã SP) -> khuôn đã chạy
chay as (
  select t.ngay, null::text as ca, replace(t.may_duc_chi_thi, ' ', '') as may, t.ma_sp, trim(t.so_khuon) as khuon
  from duc_tem t where t.ngay >= p_tu_ngay and coalesce(trim(t.so_khuon), '') <> ''
  union
  select l.ngay, l.ca, replace(l.ma_may, ' ', ''), l.ma_sp, trim(l.so_khuon)
  from duc_su_co_log l where l.ngay >= p_tu_ngay and coalesce(trim(l.so_khuon), '') <> ''
  union
  select c.ngay, c.ca, replace(c.ma_may, ' ', ''), c.ma_sp, trim(c.so_khuon)
  from duc_ca_hien_tai c where coalesce(trim(c.so_khuon), '') <> ''
),
ipqc as (
  select p.*,
    (select array_agg(distinct ch.khuon) from chay ch
       where ch.ngay = p.ngay and ch.may = replace(p.ma_may, ' ', '') and ch.ma_sp = p.ma_sp
         and (ch.ca is null or ch.ca = p.ca)) as khuon_ds
  from duc_ipqc_checkpoint p
  where p.ket_qua in ('NG', 'CANH_BAO') and p.ngay >= p_tu_ngay
)
select jsonb_build_object(
  'su_co', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id_su_co', s.id_su_co, 'ngay', s.ngay, 'ca', s.ca, 'ma_may', s.ma_may, 'ma_sp', s.ma_sp, 'loai', s.loai,
      'gio_phat_sinh', s.gio_phat_sinh, 'gio_tro_lai', s.gio_tro_lai, 'phut', s.phut, 'van_de', s.van_de,
      'xu_ly', s.xu_ly, 'dang_mo', s.dang_mo,
      'anh_truoc', coalesce(a.truoc, '[]'::jsonb), 'anh_sau', coalesce(a.sau, '[]'::jsonb))
      order by s.gio_phat_sinh desc)
    from (select * from su_co order by gio_phat_sinh desc limit 300) s left join anh a on a.id_su_co = s.id_su_co), '[]'::jsonb),
  'ipqc', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id_checkpoint', i.id_checkpoint, 'ngay', i.ngay, 'ca', i.ca, 'ma_may', i.ma_may, 'ma_sp', i.ma_sp,
      'loai_kiem', i.loai_kiem, 'ket_qua', i.ket_qua, 'thoi_diem', i.thoi_diem_kiem_thuc_te, 'nguoi_kiem', i.nguoi_kiem,
      'hang_muc_ng', (select coalesce(jsonb_agg(x->>'muc'), '[]'::jsonb) from jsonb_array_elements(coalesce(i.checklist_json, '[]'::jsonb)) x
                      where jsonb_typeof(x) = 'object' and (x->>'dat') = 'false'),
      'ghi_chu', trim(regexp_replace(coalesce(i.ghi_chu, ''), '\[QC02_[A-Z_]+:[^\]]*\]', '', 'g')),
      'anh', coalesce(i.anh_bang_chung_url, '[]'::jsonb),
      'khuon_khac', to_jsonb(array(select k from unnest(i.khuon_ds) k where k <> (select k from mk))))
      order by i.thoi_diem_kiem_thuc_te desc nulls last)
    from (select * from ipqc where (select k from mk) = any(khuon_ds)
          order by thoi_diem_kiem_thuc_te desc nulls last limit 300) i), '[]'::jsonb)
);
$$;
grant execute on function duc_khuon_van_de_lich_su(text, date) to anon, authenticated;
