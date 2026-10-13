-- ============================================================================
-- T103 — Dashboard tổ khuôn: công việc KHÔNG theo kế hoạch = xử lý bất thường
-- phát sinh trong sản xuất (sự cố A2 khuôn, B1 chất lượng SP, F1 IPQC NG).
--
-- Quyết định (user 2026-10-13):
--   - Chỉ sự cố phát sinh TỪ LÚC BẬT (duc_cau_hinh['xlbt_tu_thoi_diem'] = thời
--     điểm chạy migration này lần đầu). Vụ chưa hoàn thành luôn hiện; vụ đã
--     hoàn thành hiện thêm 7 ngày rồi chỉ còn ở Lịch sử.
--   - Phiếu xử lý TÁCH RIÊNG sự cố: hoàn thành ở tổ khuôn KHÔNG đóng sự cố /
--     không ghi giờ trở lại (trưởng ca vẫn đóng trên dashboard Đúc như cũ).
--     Không sửa RPC sự cố nào.
--   - Ảnh trước/sau dùng chung duc_su_co_anh (T87) theo id_su_co.
--   - Ghi: NV bảo dưỡng khuôn / QLBP Đúc / admin (duc_khuon_bd_la_nguoi_lap).
--
-- Một id_su_co có thể có nhiều dòng duc_su_co_log (sự cố vắt qua ca được đóng
-- lúc kết ca rồi mở lại ca sau cùng mã) → gộp theo id_su_co.
--
-- Chạy trên CẢ 2 project (production + staging). Idempotent.
-- ============================================================================

insert into duc_cau_hinh (khoa, gia_tri, ghi_chu)
values ('xlbt_tu_thoi_diem', to_jsonb(now()), 'T103: dashboard tổ khuôn chỉ lấy sự cố A2/B1/F1 phát sinh từ thời điểm này')
on conflict (khoa) do nothing;

create table if not exists duc_khuon_xu_ly_bat_thuong (
  id_su_co            text primary key,
  trang_thai          text not null default 'dang_xu_ly' check (trang_thai in ('dang_xu_ly', 'hoan_thanh')),
  nguoi_dam_nhiem     text not null default '',
  nguoi_dam_nhiem_phu text not null default '',
  bat_dau             timestamptz,
  ket_thuc            timestamptz,
  noi_dung_xu_ly      text not null default '',
  nguoi_cap_nhat      text not null default '',
  cap_nhat_luc        timestamptz not null default now(),
  nguoi_hoan_thanh    text not null default '',
  hoan_thanh_luc      timestamptz
);
alter table duc_khuon_xu_ly_bat_thuong enable row level security;
drop policy if exists "xlbt public read" on duc_khuon_xu_ly_bat_thuong;
create policy "xlbt public read" on duc_khuon_xu_ly_bat_thuong for select using (true);
revoke insert, update, delete on duc_khuon_xu_ly_bat_thuong from anon, authenticated;
grant select on duc_khuon_xu_ly_bat_thuong to anon, authenticated;

create index if not exists idx_duc_su_co_log_id_su_co on duc_su_co_log (id_su_co);

-- Danh sách sự cố A2/B1/F1 kèm phiếu xử lý.
--   p_lich_su = false: chưa hoàn thành + hoàn thành trong 7 ngày.
--   p_lich_su = true : hoàn thành có ket_thuc trong [p_tu, p_den].
create or replace function duc_khuon_xlbt_danh_sach(p_lich_su boolean default false, p_tu date default null, p_den date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tu timestamptz;
  v_out jsonb;
begin
  select (gia_tri #>> '{}')::timestamptz into v_tu from duc_cau_hinh where khoa = 'xlbt_tu_thoi_diem';
  v_tu := coalesce(v_tu, now());

  with mo as (
    select distinct on (open_id_su_co) open_id_su_co as id_su_co, ma_may, ma_sp, ten_sp, so_khuon, open_loai_su_co as loai_su_co,
           open_gio_phat_sinh as gio_phat_sinh, open_van_de as van_de, open_noi_dung_xu_ly as noi_dung_sx,
           open_dam_nhiem as dam_nhiem_sx, ngay, ca
    from duc_ca_hien_tai
    where open_id_su_co is not null and left(coalesce(open_loai_su_co, ''), 2) in ('A2', 'B1', 'F1')
      and open_gio_phat_sinh >= v_tu
    order by open_id_su_co, open_gio_phat_sinh
  ),
  dong as (
    select id_su_co,
           (array_agg(ma_may order by gio_phat_sinh))[1] ma_may,
           (array_agg(ma_sp order by gio_phat_sinh))[1] ma_sp,
           (array_agg(ten_sp order by gio_phat_sinh))[1] ten_sp,
           (array_agg(so_khuon order by gio_phat_sinh))[1] so_khuon,
           (array_agg(loai_su_co order by gio_phat_sinh))[1] loai_su_co,
           min(gio_phat_sinh) gio_phat_sinh,
           max(gio_tro_lai) gio_tro_lai,
           sum(coalesce(thoi_gian_dung_phut, 0)) phut_dung,
           (array_agg(van_de order by gio_phat_sinh))[1] van_de,
           (array_agg(noi_dung_xu_ly order by gio_phat_sinh desc))[1] noi_dung_sx,
           (array_agg(dam_nhiem order by gio_phat_sinh desc))[1] dam_nhiem_sx,
           (array_agg(ngay order by gio_phat_sinh))[1] ngay,
           (array_agg(ca order by gio_phat_sinh))[1] ca
    from duc_su_co_log
    where id_su_co is not null and left(coalesce(loai_su_co, ''), 2) in ('A2', 'B1', 'F1')
      and gio_phat_sinh >= v_tu
    group by id_su_co
  ),
  tat_ca as (
    select coalesce(m.id_su_co, d.id_su_co) id_su_co,
           coalesce(d.ma_may, m.ma_may) ma_may, coalesce(d.ma_sp, m.ma_sp) ma_sp, coalesce(d.ten_sp, m.ten_sp) ten_sp,
           coalesce(m.so_khuon, d.so_khuon) so_khuon, coalesce(d.loai_su_co, m.loai_su_co) loai_su_co,
           least(d.gio_phat_sinh, m.gio_phat_sinh) gio_phat_sinh,
           case when m.id_su_co is null then d.gio_tro_lai end gio_tro_lai,
           (m.id_su_co is not null) dang_dung_may,
           coalesce(d.phut_dung, 0) + case when m.id_su_co is not null
             then round(extract(epoch from (now() - m.gio_phat_sinh)) / 60) else 0 end phut_dung,
           coalesce(d.van_de, m.van_de) van_de,
           coalesce(m.noi_dung_sx, d.noi_dung_sx) noi_dung_sx,
           coalesce(m.dam_nhiem_sx, d.dam_nhiem_sx) dam_nhiem_sx,
           coalesce(d.ngay, m.ngay) ngay, coalesce(d.ca, m.ca) ca
    from mo m full join dong d on d.id_su_co = m.id_su_co
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id_su_co', t.id_su_co, 'ma_may', t.ma_may, 'ma_sp', t.ma_sp, 'ten_sp', t.ten_sp,
           'so_khuon', t.so_khuon, 'loai_su_co', t.loai_su_co, 'gio_phat_sinh', t.gio_phat_sinh,
           'gio_tro_lai', t.gio_tro_lai, 'dang_dung_may', t.dang_dung_may, 'phut_dung', t.phut_dung,
           'van_de', t.van_de, 'noi_dung_sx', t.noi_dung_sx, 'dam_nhiem_sx', t.dam_nhiem_sx,
           'ngay', t.ngay, 'ca', t.ca,
           'xl', case when x.id_su_co is null then null else to_jsonb(x) end
         ) order by (x.trang_thai = 'hoan_thanh') nulls first, t.gio_phat_sinh desc), '[]'::jsonb)
    into v_out
  from tat_ca t
  left join duc_khuon_xu_ly_bat_thuong x on x.id_su_co = t.id_su_co
  where case when coalesce(p_lich_su, false)
          then x.trang_thai = 'hoan_thanh'
               and x.ket_thuc >= coalesce(p_tu, current_date - 6)::timestamp at time zone 'Asia/Ho_Chi_Minh'
               and x.ket_thuc < (coalesce(p_den, current_date) + 1)::timestamp at time zone 'Asia/Ho_Chi_Minh'
          else x.id_su_co is null or x.trang_thai <> 'hoan_thanh' or x.ket_thuc >= now() - interval '7 days'
        end;

  return jsonb_build_object('ok', true, 'tu_thoi_diem', v_tu, 'rows', v_out);
end;
$$;
revoke execute on function duc_khuon_xlbt_danh_sach(boolean, date, date) from public, anon;
grant execute on function duc_khuon_xlbt_danh_sach(boolean, date, date) to authenticated;

-- Ghi phiếu xử lý. p_hanh_dong: 'luu' (đang xử lý) | 'hoan_thanh' | 'mo_lai'.
create or replace function duc_khuon_xlbt_luu(
  p_id_su_co text, p_hanh_dong text,
  p_nguoi_dam_nhiem text default '', p_nguoi_dam_nhiem_phu text default '',
  p_bat_dau timestamptz default null, p_ket_thuc timestamptz default null,
  p_noi_dung text default '')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me record;
  v_id text := trim(coalesce(p_id_su_co, ''));
  v_cu duc_khuon_xu_ly_bat_thuong;
  v_chinh text := trim(coalesce(p_nguoi_dam_nhiem, ''));
  v_phu text := trim(coalesce(p_nguoi_dam_nhiem_phu, ''));
  v_nd text := trim(coalesce(p_noi_dung, ''));
  v_ps timestamptz;
  v_anh_truoc int; v_anh_sau int;
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  if not duc_khuon_bd_la_nguoi_lap(v_me.o_role, v_me.o_bo_phan) then
    return jsonb_build_object('ok', false, 'error', 'Chỉ nhân viên bảo dưỡng khuôn / Quản lý bộ phận Đúc được ghi xử lý bất thường');
  end if;
  if p_hanh_dong not in ('luu', 'hoan_thanh', 'mo_lai') then
    return jsonb_build_object('ok', false, 'error', 'Thao tác không hợp lệ');
  end if;

  select least(
      (select min(gio_phat_sinh) from duc_su_co_log where id_su_co = v_id and left(coalesce(loai_su_co, ''), 2) in ('A2', 'B1', 'F1')),
      (select min(open_gio_phat_sinh) from duc_ca_hien_tai where open_id_su_co = v_id and left(coalesce(open_loai_su_co, ''), 2) in ('A2', 'B1', 'F1')))
    into v_ps;
  if v_ps is null then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố A2/B1/F1 mã ' || v_id);
  end if;

  select * into v_cu from duc_khuon_xu_ly_bat_thuong where id_su_co = v_id for update;

  if p_hanh_dong = 'mo_lai' then
    if v_cu.id_su_co is null or v_cu.trang_thai <> 'hoan_thanh' then
      return jsonb_build_object('ok', false, 'error', 'Phiếu chưa hoàn thành');
    end if;
    update duc_khuon_xu_ly_bat_thuong set trang_thai = 'dang_xu_ly', nguoi_hoan_thanh = '', hoan_thanh_luc = null,
      nguoi_cap_nhat = coalesce(v_me.o_ten, ''), cap_nhat_luc = now()
    where id_su_co = v_id;
    return jsonb_build_object('ok', true);
  end if;

  if v_cu.trang_thai = 'hoan_thanh' then
    return jsonb_build_object('ok', false, 'error', 'Phiếu đã hoàn thành — bấm Mở lại để sửa');
  end if;
  if v_phu <> '' and v_phu = v_chinh then
    return jsonb_build_object('ok', false, 'error', 'Đảm nhiệm phụ phải khác đảm nhiệm chính');
  end if;
  if p_bat_dau is not null and p_bat_dau < v_ps - interval '5 minutes' then
    return jsonb_build_object('ok', false, 'error', 'Thời gian bắt đầu trước giờ phát sinh sự cố');
  end if;
  if p_bat_dau is not null and p_bat_dau > now() + interval '5 minutes' then
    return jsonb_build_object('ok', false, 'error', 'Thời gian bắt đầu ở tương lai');
  end if;
  if p_ket_thuc is not null and p_ket_thuc > now() + interval '5 minutes' then
    return jsonb_build_object('ok', false, 'error', 'Thời gian kết thúc ở tương lai');
  end if;
  if p_ket_thuc is not null and (p_bat_dau is null or p_ket_thuc < p_bat_dau) then
    return jsonb_build_object('ok', false, 'error', 'Thời gian kết thúc phải sau thời gian bắt đầu');
  end if;

  if p_hanh_dong = 'hoan_thanh' then
    if v_chinh = '' then return jsonb_build_object('ok', false, 'error', 'Chọn người đảm nhiệm chính'); end if;
    if p_bat_dau is null or p_ket_thuc is null then
      return jsonb_build_object('ok', false, 'error', 'Nhập đủ thời gian bắt đầu và kết thúc xử lý');
    end if;
    if v_nd = '' then return jsonb_build_object('ok', false, 'error', 'Nhập nội dung xử lý'); end if;
    select count(*) filter (where loai = 'truoc'), count(*) filter (where loai = 'sau')
      into v_anh_truoc, v_anh_sau from duc_su_co_anh where id_su_co = v_id;
    if v_anh_truoc = 0 or v_anh_sau = 0 then
      return jsonb_build_object('ok', false, 'error', 'Cần ít nhất 1 ảnh trước và 1 ảnh sau xử lý');
    end if;
  end if;

  insert into duc_khuon_xu_ly_bat_thuong as x (id_su_co, trang_thai, nguoi_dam_nhiem, nguoi_dam_nhiem_phu, bat_dau, ket_thuc,
      noi_dung_xu_ly, nguoi_cap_nhat, cap_nhat_luc, nguoi_hoan_thanh, hoan_thanh_luc)
  values (v_id, case when p_hanh_dong = 'hoan_thanh' then 'hoan_thanh' else 'dang_xu_ly' end, v_chinh, v_phu, p_bat_dau, p_ket_thuc,
      v_nd, coalesce(v_me.o_ten, ''), now(),
      case when p_hanh_dong = 'hoan_thanh' then coalesce(v_me.o_ten, '') else '' end,
      case when p_hanh_dong = 'hoan_thanh' then now() end)
  on conflict (id_su_co) do update set
    trang_thai = excluded.trang_thai, nguoi_dam_nhiem = excluded.nguoi_dam_nhiem,
    nguoi_dam_nhiem_phu = excluded.nguoi_dam_nhiem_phu, bat_dau = excluded.bat_dau, ket_thuc = excluded.ket_thuc,
    noi_dung_xu_ly = excluded.noi_dung_xu_ly, nguoi_cap_nhat = excluded.nguoi_cap_nhat, cap_nhat_luc = now(),
    nguoi_hoan_thanh = excluded.nguoi_hoan_thanh, hoan_thanh_luc = excluded.hoan_thanh_luc;

  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function duc_khuon_xlbt_luu(text, text, text, text, timestamptz, timestamptz, text) from public, anon;
grant execute on function duc_khuon_xlbt_luu(text, text, text, text, timestamptz, timestamptz, text) to authenticated;
