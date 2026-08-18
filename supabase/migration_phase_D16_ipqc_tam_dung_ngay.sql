-- ============================================================================
-- Giai đoạn 16 — Sửa lỗi thời gian "chờ kiểm" IPQC cộng dồn qua khoảng nghỉ
-- (qua đêm giữa 2 ca 8 tiếng, cuối tuần, nghỉ lễ), theo hướng KẾT HỢP:
--
-- 1) TỰ ĐỘNG: mốc "lần kiểm gần nhất" để tính phút đã trôi trước đây tra
--    theo CẢ MÁY (ma_may) — nếu ca cuối ngày trước có kiểm lúc 14h, rồi máy
--    nghỉ qua đêm/cuối tuần, ca đầu ngày sau vừa mở đã tính "chờ" tính từ
--    14h hôm trước, sai hoàn toàn. Sửa: tra theo ĐÚNG DÒNG hiện tại
--    (id_dong) — dòng mới (ca mới) luôn chưa có lần kiểm nào nên rơi về
--    sp_start_time của chính dòng đó, tự động "reset" đồng hồ mỗi khi có
--    dòng sản xuất mới, không cần thao tác gì thêm — miễn trưởng ca đã bấm
--    "Kết ca" đúng lúc (xem migration_phase_D8).
--
-- 2) THỦ CÔNG (lưới an toàn): trường hợp không có "Kết ca" nào đánh dấu rõ
--    khoảng nghỉ (VD ngày làm việc cuối trước kỳ nghỉ lễ dài, không phải chỉ
--    1 ca mà nhiều ca/nhiều ngày không sản xuất) — thêm nút "Kết thúc ngày
--    làm việc" / "Bắt đầu ngày làm việc" ở ipqc.html. Khi tạm dừng: hàng đợi
--    định kỳ trống hẳn (không tính, không hiện). Khi bắt đầu lại: mốc tính
--    giờ của MỌI dòng được đẩy về đúng thời điểm bấm "Bắt đầu ngày làm việc"
--    (nếu mốc tự động vẫn cũ hơn) — coi như vừa kiểm xong tại đó.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ── Bảng ghi lại các phiên tạm dừng ─────────────────────────────────────────
create table if not exists public.duc_ipqc_tam_dung (
  id                  bigint generated always as identity primary key,
  thoi_diem_ket_thuc  timestamptz not null default now(),
  nguoi_ket_thuc      text,
  thoi_diem_bat_dau   timestamptz,
  nguoi_bat_dau       text
);

alter table public.duc_ipqc_tam_dung enable row level security;

drop policy if exists "public read duc_ipqc_tam_dung" on public.duc_ipqc_tam_dung;
create policy "public read duc_ipqc_tam_dung" on public.duc_ipqc_tam_dung for select using (true);

-- ── RPC: bấm "Kết thúc ngày làm việc" ───────────────────────────────────────
create or replace function duc_ipqc_ket_thuc_ngay(p_nguoi text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_dang_mo int;
begin
  select count(*) into v_dang_mo from duc_ipqc_tam_dung where thoi_diem_bat_dau is null;
  if v_dang_mo > 0 then
    return jsonb_build_object('ok', false, 'reason', 'da_tam_dung_roi');
  end if;

  insert into duc_ipqc_tam_dung (thoi_diem_ket_thuc, nguoi_ket_thuc)
  values (now(), p_nguoi);

  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function duc_ipqc_ket_thuc_ngay(text) from anon;
grant execute on function duc_ipqc_ket_thuc_ngay(text) to authenticated;

-- ── RPC: bấm "Bắt đầu ngày làm việc" ────────────────────────────────────────
create or replace function duc_ipqc_bat_dau_ngay(p_nguoi text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_id bigint;
begin
  select id into v_id from duc_ipqc_tam_dung where thoi_diem_bat_dau is null
    order by thoi_diem_ket_thuc desc limit 1;
  if v_id is null then
    return jsonb_build_object('ok', false, 'reason', 'chua_tam_dung');
  end if;

  update duc_ipqc_tam_dung set thoi_diem_bat_dau = now(), nguoi_bat_dau = p_nguoi where id = v_id;

  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function duc_ipqc_bat_dau_ngay(text) from anon;
grant execute on function duc_ipqc_bat_dau_ngay(text) to authenticated;

-- ── duc_get_ipqc_periodic_due(): áp cả 2 bản sửa ───────────────────────────
create or replace function duc_get_ipqc_periodic_due()
returns table(id_dong text, ma_may text, ma_sp text, ngay date, ca text, phut_da_troi int)
language plpgsql
stable
as $$
declare
  v_active_id_dong text[];
  v_dang_tam_dung boolean;
  v_moc_bat_dau_lai timestamptz;
begin
  -- Đang tạm dừng (đã bấm "Kết thúc ngày làm việc", chưa bấm "Bắt đầu ngày
  -- làm việc") → không tính điểm định kỳ nào cả, hàng đợi trống hẳn.
  select exists(select 1 from duc_ipqc_tam_dung where thoi_diem_bat_dau is null) into v_dang_tam_dung;
  if v_dang_tam_dung then
    return;
  end if;

  -- Mốc "Bắt đầu ngày làm việc" gần nhất (nếu có) — dùng làm sàn tối thiểu
  -- cho mốc bắt đầu tính giờ chờ của MỌI dòng, để không bị cộng dồn khoảng
  -- tạm dừng vào thời gian chờ.
  select max(thoi_diem_bat_dau) into v_moc_bat_dau_lai from duc_ipqc_tam_dung;

  select array_agg(t.id_dong) into v_active_id_dong from (
    select cht.id_dong, cht.ma_may, cht.khuon_kep_voi,
      row_number() over (partition by cht.ma_may order by cht.row_seq desc) as rn
    from duc_ca_hien_tai cht
  ) t
  where t.rn = 1 or exists (
    select 1 from duc_ca_hien_tai c2
    where c2.id_dong = t.khuon_kep_voi
      and (select rn2.rn from (
             select cht2.id_dong, row_number() over (partition by cht2.ma_may order by cht2.row_seq desc) as rn
             from duc_ca_hien_tai cht2
           ) rn2 where rn2.id_dong = t.khuon_kep_voi) = 1
  );

  select array_agg(cht.id_dong) into v_active_id_dong
  from duc_ca_hien_tai cht
  where cht.id_dong = any(v_active_id_dong)
    and (cht.open_gio_phat_sinh is not null
      or not exists (
        select 1 from duc_bao_cao_ca bc where bc.ngay = cht.ngay and bc.ca = cht.ca
      ));

  return query
  select cht.id_dong, cht.ma_may, cht.ma_sp, cht.ngay, cht.ca,
    round(extract(epoch from (now() - greatest(
      coalesce(
        (select max(cp.thoi_diem_kiem_thuc_te) from duc_ipqc_checkpoint cp
          where cp.id_dong = cht.id_dong and cp.trang_thai = 'da_kiem'),
        cht.sp_start_time, cht.last_updated_at
      ),
      coalesce(v_moc_bat_dau_lai, '-infinity'::timestamptz)
    ))) / 60)::int as phut_da_troi
  from duc_ca_hien_tai cht
  where cht.id_dong = any(v_active_id_dong)
    and cht.ma_sp is not null and cht.ma_sp <> ''
    and not exists (
      select 1 from duc_ipqc_checkpoint cp2
      where cp2.id_dong = cht.id_dong and cp2.trang_thai = 'cho_kiem' and cp2.loai_kiem = 'dinh_ky'
    );
end;
$$;
