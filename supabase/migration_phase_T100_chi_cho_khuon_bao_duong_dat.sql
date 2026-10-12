-- ============================================================================
-- T100 — Chỉ khuôn đã bảo dưỡng ĐẠT mới được đưa lên máy sản xuất.
--
-- Quyết định (user 2026-10-12):
--   - CHẶN khi khuôn chưa có lần bảo dưỡng ĐẠT nào, hoặc lần bảo dưỡng gần
--     nhất KHÔNG ĐẠT.
--   - Ngoại lệ: Quản lý bộ phận Đúc / admin "Cho phép chạy tạm" (bắt buộc lý
--     do, dùng cho 1 lần lên khuôn, hết hạn sau 12 giờ), ghi lịch sử.
--   - Chỉ chặn LẦN LÊN KHUÔN MỚI: khuôn đang chạy không bị cắt ngang; chuyển ca
--     / nạp KH ca sau cho khuôn vẫn nằm trên cùng máy (có dòng ca khác, hoặc có
--     tem / sự cố cùng máy trong 1 ngày gần nhất) không bị chặn.
--
-- "Lần bảo dưỡng gần nhất" = mới nhất trong:
--   - check sheet bảo dưỡng đã HOÀN THÀNH (mọi loại) → kết luận đạt / không đạt;
--   - sổ đời khuôn ghi tay trước T81 (duc_khuon_bao_duong_log không gắn check
--     sheet) → coi là đạt.
--
-- Chặn ở trigger duc_ca_hien_tai (như T80) → mọi đường lên khuôn: đổi SP, gán
-- / nạp KH ca, khuôn kép, sửa khuôn trên dashboard / mobile.
-- Công tắc duc_cau_hinh['chan_khuon_chua_bd_dat'] (true/false) để tắt khẩn cấp.
--
-- Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

-- 1) Cấu hình chung + công tắc ---------------------------------------------------
create table if not exists duc_cau_hinh (
  khoa        text primary key,
  gia_tri     jsonb not null,
  ghi_chu     text not null default '',
  updated_at  timestamptz not null default now(),
  updated_by  text not null default ''
);
alter table duc_cau_hinh enable row level security;
drop policy if exists "public read" on duc_cau_hinh;
create policy "public read" on duc_cau_hinh for select using (true);
revoke all on duc_cau_hinh from anon, authenticated;
grant select on duc_cau_hinh to anon, authenticated;
insert into duc_cau_hinh (khoa, gia_tri, ghi_chu)
values ('chan_khuon_chua_bd_dat', 'true', 'T100: chỉ khuôn bảo dưỡng ĐẠT mới lên máy được (false = tắt chặn)')
on conflict (khoa) do nothing;

-- 2) Cho phép chạy tạm -------------------------------------------------------------
create table if not exists duc_khuon_cho_phep_tam (
  id            bigserial primary key,
  ma_khuon      text not null,
  ma_may        text,                       -- null = máy nào cũng được
  ly_do         text not null,
  nguoi         text not null,
  nguoi_uid     uuid,
  thoi_diem     timestamptz not null default now(),
  het_han       timestamptz not null,
  da_dung_luc   timestamptz,
  id_dong_dung  text,
  huy_luc       timestamptz,
  nguoi_huy     text not null default ''
);
create index if not exists duc_khuon_cpt_khuon_idx on duc_khuon_cho_phep_tam(ma_khuon, thoi_diem desc);
alter table duc_khuon_cho_phep_tam enable row level security;
drop policy if exists "public read" on duc_khuon_cho_phep_tam;
create policy "public read" on duc_khuon_cho_phep_tam for select using (true);
revoke all on duc_khuon_cho_phep_tam from anon, authenticated;
grant select on duc_khuon_cho_phep_tam to anon, authenticated;

-- 3) Lần bảo dưỡng gần nhất của 1 khuôn ------------------------------------------
create or replace function duc_khuon_bd_gan_nhat(p_ma_khuon text,
  out o_ket_luan text, out o_thoi_diem timestamptz, out o_ngay date, out o_loai text, out o_id_checksheet bigint)
language sql
stable
set search_path = public
as $$
  select x.ket_luan, x.t, x.ngay, x.loai, x.id_cs from (
    select cs.ket_luan, cs.thoi_diem_hoan_thanh as t, cs.ngay_thuc_hien as ngay, cs.loai, cs.id as id_cs
    from duc_khuon_checksheet cs
    where trim(cs.ma_khuon) = trim(p_ma_khuon) and cs.trang_thai = 'hoan_thanh'
    union all
    select 'dat', l.thoi_diem_ghi, l.ngay, l.loai, null
    from duc_khuon_bao_duong_log l
    where trim(l.ma_khuon) = trim(p_ma_khuon)
      and not exists (select 1 from duc_khuon_checksheet c where c.id_log = l.id_log)
  ) x
  order by x.t desc nulls last, x.ngay desc nulls last
  limit 1;
$$;

-- Khuôn vẫn nằm trên máy này (chạy tiếp, không phải lên khuôn mới)?
create or replace function duc_khuon_dang_tren_may(p_ma_khuon text, p_ma_may text, p_ngay date, p_id_dong text default null)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (select 1 from duc_ca_hien_tai c
                 where c.ma_may = p_ma_may and trim(c.so_khuon) = trim(p_ma_khuon)
                   and c.id_dong is distinct from p_id_dong)
      or exists (select 1 from duc_tem t
                 where trim(t.so_khuon) = trim(p_ma_khuon)
                   and replace(t.may_duc_chi_thi, ' ', '') = replace(p_ma_may, ' ', '')
                   and t.ngay between coalesce(p_ngay, current_date) - 1 and coalesce(p_ngay, current_date))
      or exists (select 1 from duc_su_co_log s
                 where trim(s.so_khuon) = trim(p_ma_khuon)
                   and replace(s.ma_may, ' ', '') = replace(p_ma_may, ' ', '')
                   and s.ngay between coalesce(p_ngay, current_date) - 1 and coalesce(p_ngay, current_date));
$$;

-- Trạng thái bảo dưỡng mọi khuôn (cho dashboard / màn hình khuôn).
create or replace function duc_khuon_ds_trang_thai_bd()
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'bat', coalesce((select gia_tri = 'true'::jsonb from duc_cau_hinh where khoa = 'chan_khuon_chua_bd_dat'), false),
    'khuon', coalesce(jsonb_object_agg(k.ma_khuon, jsonb_build_object(
      'ket_luan', b.o_ket_luan, 'ngay', b.o_ngay, 'loai', b.o_loai, 'id_checksheet', b.o_id_checksheet,
      'cho_phep_tam', (select jsonb_build_object('id', p.id, 'ma_may', p.ma_may, 'ly_do', p.ly_do, 'nguoi', p.nguoi,
                                                 'thoi_diem', p.thoi_diem, 'het_han', p.het_han)
                       from duc_khuon_cho_phep_tam p
                       where p.ma_khuon = k.ma_khuon and p.huy_luc is null and p.da_dung_luc is null and p.het_han > now()
                       order by p.thoi_diem desc limit 1),
      'may_gan_day', (select coalesce(jsonb_agg(distinct m), '[]'::jsonb) from (
          select c.ma_may m from duc_ca_hien_tai c where trim(c.so_khuon) = k.ma_khuon
          union select t.may_duc_chi_thi from duc_tem t where trim(t.so_khuon) = k.ma_khuon and t.ngay >= current_date - 1
          union select s.ma_may from duc_su_co_log s where trim(s.so_khuon) = k.ma_khuon and s.ngay >= current_date - 1) mm
        where m is not null)
    )), '{}'::jsonb))
  from (select trim(ma_khuon) as ma_khuon from duc_shot_khuon where coalesce(trim(ma_khuon), '') <> '') k
  cross join lateral duc_khuon_bd_gan_nhat(k.ma_khuon) b;
$$;

-- 4) Trigger chặn ------------------------------------------------------------------
create or replace function duc_ca_hien_tai_chan_khuon_chua_bd()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mk text := trim(coalesce(new.so_khuon, ''));
  v_bd record; v_ex bigint;
begin
  if v_mk = '' then return new; end if;
  if tg_op = 'UPDATE' and new.so_khuon is not distinct from old.so_khuon then return new; end if;
  if not coalesce((select gia_tri = 'true'::jsonb from duc_cau_hinh where khoa = 'chan_khuon_chua_bd_dat'), false) then
    return new;
  end if;
  -- Đổi tên khuôn (duc_rename_khuon): khuôn cũ đã không còn trong danh sách.
  if tg_op = 'UPDATE' and new.ma_may is not distinct from old.ma_may
     and not exists (select 1 from duc_shot_khuon where ma_khuon = trim(coalesce(old.so_khuon, ''))) then
    return new;
  end if;
  -- Khuôn chạy tiếp trên cùng máy (chuyển ca / nạp KH ca sau) → không phải lên khuôn mới.
  if duc_khuon_dang_tren_may(v_mk, new.ma_may, new.ngay, new.id_dong) then return new; end if;

  select * into v_bd from duc_khuon_bd_gan_nhat(v_mk);
  if v_bd.o_ket_luan = 'dat' then return new; end if;

  select id into v_ex from duc_khuon_cho_phep_tam
  where ma_khuon = v_mk and huy_luc is null and da_dung_luc is null and het_han > now()
    and (ma_may is null or replace(ma_may, ' ', '') = replace(new.ma_may, ' ', ''))
  order by thoi_diem desc limit 1
  for update;
  if v_ex is not null then
    update duc_khuon_cho_phep_tam set da_dung_luc = now(), id_dong_dung = new.id_dong where id = v_ex;
    return new;
  end if;

  raise exception 'Khuôn % %. Không được đưa vào sản xuất — bảo dưỡng ĐẠT (check sheet) trước, hoặc Quản lý bộ phận Đúc bấm "Cho phép chạy tạm".',
    v_mk,
    case when v_bd.o_ket_luan is null then 'chưa có lần bảo dưỡng ĐẠT nào'
         else 'có lần bảo dưỡng gần nhất (' || to_char(v_bd.o_ngay, 'DD/MM/YYYY') || ', ' || coalesce(v_bd.o_loai, '') || ') KHÔNG ĐẠT' end;
end $$;
revoke execute on function duc_ca_hien_tai_chan_khuon_chua_bd() from public, anon, authenticated;

drop trigger if exists trg_duc_ca_hien_tai_chan_khuon_chua_bd on duc_ca_hien_tai;
create trigger trg_duc_ca_hien_tai_chan_khuon_chua_bd
  before insert or update of so_khuon on duc_ca_hien_tai
  for each row execute function duc_ca_hien_tai_chan_khuon_chua_bd();

-- 5) RPC cho phép chạy tạm (QLBP Đúc / admin) ------------------------------------
create or replace function duc_khuon_cho_phep_chay_tam(p_ma_khuon text, p_ma_may text, p_ly_do text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me record; v_mk text := trim(coalesce(p_ma_khuon, '')); v_id bigint; v_het timestamptz := now() + interval '12 hours';
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  if not (coalesce(v_me.o_role, '') = 'admin'
          or (v_me.o_role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(v_me.o_bo_phan, '{}')))) then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Quản lý bộ phận Đúc / admin được cho phép chạy tạm');
  end if;
  if v_mk = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã khuôn'); end if;
  if coalesce(trim(p_ly_do), '') = '' then return jsonb_build_object('ok', false, 'error', 'Nhập lý do cho phép chạy tạm'); end if;
  insert into duc_khuon_cho_phep_tam (ma_khuon, ma_may, ly_do, nguoi, nguoi_uid, het_han)
  values (v_mk, nullif(trim(coalesce(p_ma_may, '')), ''), trim(p_ly_do), v_me.o_ten, auth.uid(), v_het)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'het_han', v_het);
end $$;
revoke execute on function duc_khuon_cho_phep_chay_tam(text, text, text) from public, anon;
grant execute on function duc_khuon_cho_phep_chay_tam(text, text, text) to authenticated;
