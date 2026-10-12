-- ============================================================================
-- T96 — Kết quả sau bảo dưỡng khuôn = IPQC kiểm sản phẩm đầu khi lên khuôn.
--
-- User 2026-10-12: bỏ hạng mục "7. Sau bảo dưỡng — lắp khuôn, đúc thử, kiểm
-- tra sản phẩm đầu" khỏi mẫu check sheet (NV bảo dưỡng không phải chờ đúc
-- thử mới hoàn thành, bộ đếm shot reset ngay); lấy kết quả IPQC kiểm sản phẩm
-- đầu khi khuôn lên máy (điểm kiểm 'doi_khuon', hoặc 'sau_su_co' của sự cố
-- C3 - Đổi khuôn) làm kết quả sau bảo dưỡng, hiển thị trên check sheet.
--
-- duc_ipqc_checkpoint không lưu số khuôn → khớp khuôn theo thứ tự tin cậy:
--   1. su_co : sự cố gốc (id_su_co_goc → duc_su_co_log.so_khuon)
--   2. dong  : dòng đang chạy (id_dong → duc_ca_hien_tai.so_khuon)
--   3. tem   : cùng ngày + máy + mã SP với tem / sự cố có số khuôn (như T88);
--              trả kèm khuon_khac nếu cùng ngày/máy/mã còn khuôn khác.
-- Mốc tìm = giờ kết thúc bảo dưỡng trên check sheet (không có thì đầu ngày
-- thực hiện), trong 45 ngày; bỏ điểm kiểm het_hieu_luc. Lấy lần lên khuôn
-- ĐẦU TIÊN sau mốc.
--
-- Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

-- 1) Tắt hạng mục 7 trong mẫu (giữ lại dòng, chỉ bỏ "Dùng") ---------------------
update duc_khuon_cs_mau set dang_dung = false, updated_at = now()
where ma_khuon is null and nhom like '7. Sau bảo dưỡng%' and dang_dung;

-- 2) Kết quả IPQC sau bảo dưỡng của 1 check sheet -----------------------------
create or replace function duc_khuon_cs_ipqc_sau_bd(p_id_checksheet bigint)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_cs duc_khuon_checksheet%rowtype; v_k text; v_moc timestamptz; r record;
begin
  select * into v_cs from duc_khuon_checksheet where id = p_id_checksheet;
  if not found then return null; end if;
  v_k := trim(v_cs.ma_khuon);
  v_moc := coalesce(v_cs.gio_ket_thuc, (v_cs.ngay_thuc_hien::timestamp at time zone 'Asia/Ho_Chi_Minh'));

  select p.*, k.cach, k.khuon_khac into r
  from duc_ipqc_checkpoint p
  left join duc_su_co_log l on l.id_su_co = p.id_su_co_goc and p.id_su_co_goc is not null
  cross join lateral (
    select case
      when trim(coalesce(l.so_khuon, '')) = v_k then 'su_co'
      when exists (select 1 from duc_ca_hien_tai c where c.id_dong = p.id_dong and trim(coalesce(c.so_khuon, '')) = v_k) then 'dong'
      when v_k in (select trim(t.so_khuon) from duc_tem t
                   where t.ngay = p.ngay and replace(t.may_duc_chi_thi, ' ', '') = replace(p.ma_may, ' ', '') and t.ma_sp = p.ma_sp
                   union
                   select trim(s.so_khuon) from duc_su_co_log s
                   where s.ngay = p.ngay and s.ca = p.ca and replace(s.ma_may, ' ', '') = replace(p.ma_may, ' ', '') and s.ma_sp = p.ma_sp)
        then 'tem'
    end as cach,
    (select coalesce(jsonb_agg(distinct x.k), '[]'::jsonb) from (
       select trim(t.so_khuon) k from duc_tem t
       where t.ngay = p.ngay and replace(t.may_duc_chi_thi, ' ', '') = replace(p.ma_may, ' ', '') and t.ma_sp = p.ma_sp
       union
       select trim(s.so_khuon) from duc_su_co_log s
       where s.ngay = p.ngay and s.ca = p.ca and replace(s.ma_may, ' ', '') = replace(p.ma_may, ' ', '') and s.ma_sp = p.ma_sp) x
     where coalesce(x.k, '') not in ('', v_k)) as khuon_khac
  ) k
  where p.thoi_diem_tao >= v_moc and p.thoi_diem_tao < v_moc + interval '45 days'
    and p.trang_thai <> 'het_hieu_luc'
    and (p.loai_kiem = 'doi_khuon' or (p.loai_kiem = 'sau_su_co' and l.loai_su_co ilike 'C3%'))
    and k.cach is not null
  order by p.thoi_diem_tao
  limit 1;

  if r.id_checkpoint is null then
    return jsonb_build_object('moc', v_moc, 'ipqc', null);
  end if;
  return jsonb_build_object('moc', v_moc, 'ipqc', jsonb_build_object(
    'id_checkpoint', r.id_checkpoint, 'loai_kiem', r.loai_kiem, 'ngay', r.ngay, 'ca', r.ca,
    'ma_may', r.ma_may, 'ma_sp', r.ma_sp, 'thoi_diem_tao', r.thoi_diem_tao, 'han_kiem', r.han_kiem,
    'trang_thai', r.trang_thai, 'ket_qua', r.ket_qua, 'thoi_diem_kiem', r.thoi_diem_kiem_thuc_te,
    'nguoi_kiem', r.nguoi_kiem,
    'hang_muc_ng', (select coalesce(jsonb_agg(x->>'muc'), '[]'::jsonb) from jsonb_array_elements(coalesce(r.checklist_json, '[]'::jsonb)) x
                    where jsonb_typeof(x) = 'object' and (x->>'dat') = 'false'),
    'ghi_chu', trim(regexp_replace(coalesce(r.ghi_chu, ''), '\[QC02_[A-Z_]+:[^\]]*\]', '', 'g')),
    'anh', coalesce(r.anh_bang_chung_url, '[]'::jsonb),
    'cach_khop', r.cach, 'khuon_khac', case when r.cach = 'tem' then r.khuon_khac else '[]'::jsonb end));
end $$;
