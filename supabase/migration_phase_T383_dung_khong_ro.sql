-- T383 (27/11/2026): Báo cáo kết ca — cột "Dừng không rõ" (phút) từng máy, để phát hiện trưởng ca
-- nhập thiếu sự cố / thiếu thời gian dừng.
--   Dừng không rõ = Thời gian ca chuẩn − Thời gian chạy theo CT − Phút sự cố đã nhập
--   Thời gian ca chuẩn (đã trừ nghỉ ăn ca, 5S): 2 ca 12h: Ca ngày 675', Ca đêm 660'; 2 ca 8h: Ca 1 = Ca 2 = 435'.
--     Kết ca sớm thì trừ phần ca chưa chạy tới (ngoài giờ nghỉ).
--   Thời gian chạy = [(OK + NG) / cavity + shot nóng khuôn] × CT / 60.
--     Khuôn nhiều mã (các mã cùng máy, cùng khung giờ) dùng chung shot → lấy số shot lớn nhất trong nhóm.
--   Phút sự cố = hợp khoảng dừng của máy (đã đóng + còn mở) trong ca, trừ phần trùng giờ nghỉ.
--   Không tính: máy Dập, máy ở ca không sản xuất; thiếu CT/cavity → null (hiện "—").
-- Lưu vào duc_bao_cao_ca.dung_khong_ro (jsonb) để trang tra cứu báo cáo cũ cũng hiện được.

alter table public.duc_bao_cao_ca add column if not exists dung_khong_ro jsonb;
comment on column public.duc_bao_cao_ca.dung_khong_ro is
  'T383: [{ma_may, phut_ca, phut_chay, phut_su_co, phut_khong_ro}] — phút dừng không rõ lý do từng máy lúc kết ca';

create or replace function public.duc_dung_khong_ro_ca(p_ngay date, p_ca text, p_phuong_an_ca text, p_now timestamptz default now())
returns jsonb
language plpgsql
stable
set search_path to 'public'
as $function$
declare
  v_sw jsonb; v_bw jsonb; v_ws timestamptz; v_end timestamptz; v_we timestamptz;
  v_chuan numeric; v_phut_ca numeric; v_br tstzmultirange := '{}'::tstzmultirange; v_kq jsonb;
begin
  v_sw := duc_get_shift_window(p_ngay, p_phuong_an_ca, p_ca);
  if v_sw is null then return '[]'::jsonb; end if;
  v_chuan := case
    when p_phuong_an_ca = '2 ca 12h' and p_ca = 'Ca ngày' then 675
    when p_phuong_an_ca = '2 ca 12h' and p_ca = 'Ca đêm' then 660
    when p_phuong_an_ca = '2 ca 8h' and p_ca in ('Ca 1', 'Ca 2') then 435 end;
  if v_chuan is null then return '[]'::jsonb; end if;

  v_ws := (v_sw->>'start')::timestamptz;
  v_end := (v_sw->>'end')::timestamptz;
  v_we := least(p_now, v_end);
  if v_we <= v_ws then return '[]'::jsonb; end if;
  v_bw := duc_get_break_window(p_ngay, p_phuong_an_ca, p_ca);
  if v_bw is not null then
    v_br := tstzmultirange(tstzrange((v_bw->>'start')::timestamptz, (v_bw->>'end')::timestamptz));
  end if;
  -- kết ca sớm: bỏ phần ca còn lại (không tính giờ nghỉ nằm trong phần đó)
  v_phut_ca := v_chuan - greatest(0, extract(epoch from (v_end - v_we)) - duc_sum_break_overlap(v_we, v_end, v_bw)) / 60;

  with r as (
    select c.ma_may, c.sp_start_time, c.sp_end_time,
           coalesce(c.tt_ca, 0) tt, coalesce(c.so_luong_ng, 0) ng, coalesce(c.so_shot_nong_khuon, 0) sn,
           p.cavity cav, p.cycle_time_s ct
    from duc_ca_hien_tai c left join master_products p on p.ma_sp = c.ma_sp
    where c.ngay = p_ngay and c.ca = p_ca and c.ma_sp is not null and c.ma_sp <> '' and c.kh_ca is not null
      and not duc_la_may_dap(c.ma_may) and not duc_ca_khong_sx(p_ngay, c.ma_may)),
  nhom as (   -- khuôn nhiều mã: cùng máy + cùng khung giờ = cùng shot
    select ma_may,
           max((tt + ng) / nullif(cav, 0)) shot_sx, max(sn) sn, max(ct) ct,
           bool_and(coalesce(cav, 0) > 0 and coalesce(ct, 0) > 0) du
    from r group by ma_may, sp_start_time, sp_end_time),
  may as (
    select ma_may, sum((coalesce(shot_sx, 0) + sn) * coalesce(ct, 0)) / 60 phut_chay, bool_and(du) du
    from nhom group by ma_may),
  dung as (
    select m.ma_may,
      (select coalesce(sum(extract(epoch from upper(x) - lower(x))), 0) / 60
       from unnest(((
         select coalesce(range_agg(rg), '{}'::tstzmultirange) from (
           select tstzrange(l.gio_phat_sinh, l.gio_tro_lai) rg from duc_su_co_log l
            where l.ma_may = m.ma_may and l.ngay = p_ngay and l.ca = p_ca and l.gio_tro_lai > l.gio_phat_sinh
           union all
           select tstzrange(greatest(c.open_gio_phat_sinh, v_ws), v_we) from duc_ca_hien_tai c
            where c.ma_may = m.ma_may and c.ngay = p_ngay and c.ca = p_ca and c.open_gio_phat_sinh is not null
              and greatest(c.open_gio_phat_sinh, v_ws) < v_we
           union all
           select tstzrange(greatest(t.gio_phat_sinh, v_ws), v_we) from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong
            where c.ma_may = m.ma_may and c.ngay = p_ngay and c.ca = p_ca and greatest(t.gio_phat_sinh, v_ws) < v_we) q
       ) * tstzmultirange(tstzrange(v_ws, v_we))) - v_br) x) phut_sc
    from may m)
  select coalesce(jsonb_agg(jsonb_build_object(
           'ma_may', m.ma_may,
           'phut_ca', round(v_phut_ca),
           'phut_chay', case when m.du then round(m.phut_chay) end,
           'phut_su_co', round(d.phut_sc),
           'phut_khong_ro', case when m.du then greatest(0, round(v_phut_ca - m.phut_chay - d.phut_sc)) end)
         order by m.ma_may), '[]'::jsonb)
    into v_kq
  from may m join dung d on d.ma_may = m.ma_may;
  return v_kq;
end;
$function$;

revoke execute on function public.duc_dung_khong_ro_ca(date, text, text, timestamptz) from public, anon;

-- Vá duc_end_shift: tính trước khi chuyển ca/xoá duc_ca_hien_tai, lưu vào báo cáo, trả về cho giao diện.
do $$
declare
  v_def text;
  v_moc1 text := 'v_tem_mo_coi jsonb;';
  v_moc2 text := 'v_carry_result := duc_carry_over_shift(';
  v_moc3 text := '''tem_mo_coi'', v_tem_mo_coi);';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'duc_end_shift';
  if v_def is null then raise exception 'Không thấy duc_end_shift'; end if;
  if position('T383' in v_def) > 0 then raise notice 'Đã vá T383 rồi'; return; end if;
  if position(v_moc1 in v_def) = 0 or position(v_moc2 in v_def) = 0 or position(v_moc3 in v_def) = 0 then
    raise exception 'Không tìm thấy dòng mốc trong duc_end_shift';
  end if;
  v_def := replace(v_def, v_moc1, 'v_tem_mo_coi jsonb; v_dkr jsonb;');
  v_def := replace(v_def, v_moc2,
    E'-- T383: phút dừng không rõ từng máy\n'
    || E'  v_dkr := duc_dung_khong_ro_ca(p_ngay, p_ca, p_phuong_an_ca, v_now);\n'
    || E'  update duc_bao_cao_ca set dung_khong_ro = v_dkr where id_bao_cao = v_id_bao_cao;\n'
    || E'  ' || v_moc2);
  v_def := replace(v_def, v_moc3, '''tem_mo_coi'', v_tem_mo_coi, ''dung_khong_ro'', v_dkr);');
  execute v_def;
end $$;
