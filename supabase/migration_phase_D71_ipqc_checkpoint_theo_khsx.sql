-- ============================================================================
-- D71 — IPQC: điểm kiểm định kỳ cho máy CÓ KHSX ngày hôm nay nhưng trưởng ca
-- CHƯA nhập dòng ca (duc_ca_hien_tai) — trước đây hàng đợi IPQC chỉ dựa trên
-- dòng ca nên trưởng ca nhập chậm = IPQC kiểm thiếu tần suất.
--
-- Ngày sản xuất D = ngày VN của (now - 6h) → cửa sổ 06:00 D → 06:00 D+1.
-- Máy M lọt danh sách khi:
--   * duc_khsx_tuan_plan có SL ngày D > 0 cho M (bất kể trạng thái duyệt KH tuần);
--   * dòng ca mới nhất của M KHÔNG còn sống (giống getActiveIdDongSet ở ipqc.html:
--     sống = đang có sự cố mở hoặc ngày/ca chưa kết ca);
--   * M chưa có dòng duc_ca_hien_tai / duc_lich_su_san_xuat nào ngày D
--     (trưởng ca đã nhập rồi kết ca = máy dừng thật, không nhắc nữa);
--   * IPQC không ở trạng thái "Kết thúc ngày làm việc".
-- Đồng hồ: từ max(06:00 D, lần kiểm xong gần nhất của M từ 06:00 D, mốc
-- "Bắt đầu ngày làm việc"), đến hạn sau 120 phút như định kỳ thường.
--
-- Checkpoint tạo ra: loai_kiem='dinh_ky', id_dong = NULL, ca = NULL.
-- Khi trưởng ca nhập dòng ca cho M ngày D (insert / đổi ma_sp, ngay), trigger
-- trg_duc_ipqc_gan_checkpoint_kh gắn các checkpoint KH cùng máy+ngày+mã SP vào
-- dòng đó (id_dong, ca, phuong_an_ca) → duc_get_ipqc_periodic_due đếm tiếp từ
-- lần kiểm này; checkpoint KH đang chờ của mã khác → het_hieu_luc.
-- Kết quả NG ở checkpoint KH (chưa có dòng ca) KHÔNG tự mở sự cố F1 — trưởng
-- ca xử lý (duc_submit_ipqc_check đã có nhánh "Dòng Ca_hien_tai gốc không còn").
-- An toàn chạy lại nhiều lần.
-- ============================================================================

create index if not exists idx_duc_ipqc_cp_kh
  on duc_ipqc_checkpoint (ma_may, ngay) where id_dong is null;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Danh sách máy cần kiểm theo KHSX (đọc — công khai như hàng đợi IPQC)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function duc_get_ipqc_kh_due()
returns table(ma_may text, ngay date, ds_ma_sp text[], so_khuon text,
              id_checkpoint text, ma_sp_dang_cho text, phut_da_troi integer)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_d date := ((now() at time zone 'Asia/Ho_Chi_Minh') - interval '6 hours')::date;
  v_start timestamptz;
  v_monday date;
  v_dow int;
  v_resume timestamptz;
begin
  if exists (select 1 from duc_ipqc_tam_dung where thoi_diem_bat_dau is null) then
    return;
  end if;
  select max(thoi_diem_bat_dau) into v_resume from duc_ipqc_tam_dung;

  v_start := (v_d::timestamp + time '06:00') at time zone 'Asia/Ho_Chi_Minh';
  v_dow := extract(isodow from v_d)::int;
  v_monday := v_d - (v_dow - 1);

  return query
  with kh as (
    select k.ma_may, k.ma_sp, nullif(trim(k.so_khuon), '') so_khuon
    from duc_khsx_tuan_plan k
    where k.tuan_bat_dau = v_monday and coalesce(k.ma_may, '') <> '' and coalesce(k.ma_sp, '') <> ''
      and coalesce(case v_dow when 1 then k.t2 when 2 then k.t3 when 3 then k.t4 when 4 then k.t5
                              when 5 then k.t6 when 6 then k.t7 else k.cn end, 0) > 0
  ),
  may as (
    select kh.ma_may, array_agg(distinct kh.ma_sp order by kh.ma_sp) ds_sp,
           string_agg(distinct kh.so_khuon, ', ') so_khuon
    from kh group by kh.ma_may
  ),
  latest as (
    select distinct on (c.ma_may) c.ma_may, c.ngay, c.ca, c.open_gio_phat_sinh
    from duc_ca_hien_tai c order by c.ma_may, c.row_seq desc
  ),
  chua as (
    select m.* from may m
    where not exists (
        select 1 from latest l where l.ma_may = m.ma_may
          and (l.open_gio_phat_sinh is not null
               or not exists (select 1 from duc_bao_cao_ca b where b.ngay = l.ngay and b.ca = l.ca)))
      and not exists (select 1 from duc_ca_hien_tai c where c.ma_may = m.ma_may and c.ngay = v_d)
      and not exists (select 1 from duc_lich_su_san_xuat l where l.ma_may = m.ma_may and l.ngay = v_d)
  )
  select ch.ma_may, v_d, ch.ds_sp, ch.so_khuon, p.id_checkpoint, p.ma_sp,
    round(extract(epoch from (now() - greatest(
      coalesce(p.han_kiem, (select max(cp.thoi_diem_kiem_thuc_te) from duc_ipqc_checkpoint cp
                            where cp.ma_may = ch.ma_may and cp.trang_thai = 'da_kiem'
                              and cp.thoi_diem_kiem_thuc_te >= v_start), v_start),
      v_start, coalesce(v_resume, '-infinity'::timestamptz)))) / 60)::int
  from chua ch
  left join lateral (
    select cp.id_checkpoint, cp.ma_sp, cp.han_kiem from duc_ipqc_checkpoint cp
    where cp.id_dong is null and cp.ma_may = ch.ma_may and cp.ngay = v_d and cp.trang_thai = 'cho_kiem'
    order by cp.thoi_diem_tao desc limit 1
  ) p on true;
end;
$$;

revoke execute on function duc_get_ipqc_kh_due() from public;
grant execute on function duc_get_ipqc_kh_due() to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Tạo checkpoint thật khi IPQC bấm vào thẻ KHSX
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function duc_ipqc_tao_checkpoint_kh(p_ma_may text, p_ma_sp text, p_moc_cho timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_due record;
  v_last timestamptz;
  v_han timestamptz;
  v_id text;
begin
  select * into v_due from duc_get_ipqc_kh_due() d where d.ma_may = p_ma_may;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'Máy không còn trong danh sách kiểm theo KHSX (trưởng ca đã nhập KH ca hoặc hết KH hôm nay) — tải lại hàng đợi');
  end if;
  if not (p_ma_sp = any(v_due.ds_ma_sp)) then
    return jsonb_build_object('ok', false, 'reason', 'Mã ' || coalesce(p_ma_sp, '') || ' không có trong KHSX hôm nay của máy ' || p_ma_may);
  end if;

  if v_due.id_checkpoint is not null then
    if v_due.ma_sp_dang_cho = p_ma_sp then
      return jsonb_build_object('ok', true, 'id_checkpoint', v_due.id_checkpoint);
    end if;
    update duc_ipqc_checkpoint set trang_thai = 'het_hieu_luc'
    where id_dong is null and ma_may = p_ma_may and ngay = v_due.ngay and trang_thai = 'cho_kiem';
  end if;

  select max(thoi_diem_kiem_thuc_te) into v_last from duc_ipqc_checkpoint
  where ma_may = p_ma_may and trang_thai = 'da_kiem';
  v_han := coalesce(p_moc_cho, now());
  if v_last is not null and v_han < v_last then v_han := v_last; end if;
  if v_han > now() then v_han := now(); end if;

  v_id := 'IPQC_' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DDMMYYYY_HH24MISS')
    || '_' || duc_normalize_name(p_ma_may) || '_dinh_ky';

  insert into duc_ipqc_checkpoint (
    id_checkpoint, id_dong, ma_may, ma_sp, ngay, ca, phuong_an_ca, loai_kiem,
    id_su_co_goc, thoi_diem_tao, han_kiem, trang_thai
  ) values (
    v_id, null, p_ma_may, p_ma_sp, v_due.ngay, null, null, 'dinh_ky',
    null, now(), v_han, 'cho_kiem'
  );
  return jsonb_build_object('ok', true, 'id_checkpoint', v_id);
end;
$$;

revoke execute on function duc_ipqc_tao_checkpoint_kh(text, text, timestamptz) from public, anon;
grant execute on function duc_ipqc_tao_checkpoint_kh(text, text, timestamptz) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Trưởng ca nhập dòng ca → gắn checkpoint KH vào dòng đó
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function duc_ipqc_gan_checkpoint_kh()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.id_dong is null or new.ma_may is null or new.ngay is null or coalesce(new.ma_sp, '') = '' then
    return new;
  end if;

  update duc_ipqc_checkpoint
     set id_dong = new.id_dong, ca = new.ca, phuong_an_ca = new.phuong_an_ca
   where id_dong is null and ma_may = new.ma_may and ngay = new.ngay and ma_sp = new.ma_sp;

  update duc_ipqc_checkpoint set trang_thai = 'het_hieu_luc'
   where id_dong is null and ma_may = new.ma_may and ngay = new.ngay and trang_thai = 'cho_kiem';

  return new;
end;
$$;

revoke execute on function duc_ipqc_gan_checkpoint_kh() from public, anon, authenticated;

drop trigger if exists trg_duc_ipqc_gan_checkpoint_kh on duc_ca_hien_tai;
create trigger trg_duc_ipqc_gan_checkpoint_kh
  after insert or update of ma_sp, ngay, id_dong on duc_ca_hien_tai
  for each row execute function duc_ipqc_gan_checkpoint_kh();
