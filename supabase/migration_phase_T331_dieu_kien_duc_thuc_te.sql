-- T331: ĐK đúc — cột "Thực tế" = giá trị đang cài trên máy, theo (máy, mã SP, thông số).
-- • Trưởng ca xác nhận ĐK đúc khi lên khuôn (T324) → các số / chữ ★ vừa xác nhận thành Thực tế.
-- • Điểm thay đổi (T307): mục nối 1–1 với thông số (duc_dk_thong_so.ma_muc_td, cùng kiểu số/chữ):
--     – ô "Trước" PHẢI bằng Thực tế (nếu đã có) — chặn ở trigger BEFORE INSERT;
--     – khi thay đổi được áp dụng (thoi_diem_ap_dung có giá trị) → Thực tế = "Sau";
--     – áp dụng rồi mà bị Huỷ / Không duyệt bù (khẩn) → Thực tế trả về "Trước" (nếu chưa bị ghi đè).
-- • Kỹ thuật (hoặc admin) sửa tay được: duc_dk_thuc_te_sua.
-- Chỉ dùng trigger — không viết lại duc_td_ghi / duc_td_da_chinh / duc_dk_xac_nhan_luu. Chạy lại được.

create table if not exists public.duc_dk_thuc_te (
  ma_may      text not null,
  ma_sp       text not null,
  ma_ts       text not null references public.duc_dk_thong_so(ma_ts),
  gia_tri     numeric,           -- kiểu số
  gia_tri_chu text,              -- kiểu chữ; Có/Không = 'co' / 'khong'
  nguon       text not null check (nguon in ('xac_nhan', 'thay_doi', 'hoan', 'sua_tay')),
  id_nguon    bigint,            -- duc_dk_xac_nhan.id | duc_thay_doi.id
  luc         timestamptz not null default now(),
  nguoi       text,
  primary key (ma_may, ma_sp, ma_ts)
);
alter table public.duc_dk_thuc_te enable row level security;
drop policy if exists "dktt doc" on public.duc_dk_thuc_te;
create policy "dktt doc" on public.duc_dk_thuc_te for select to authenticated using (true);
revoke all on public.duc_dk_thuc_te from anon;
revoke insert, update, delete on public.duc_dk_thuc_te from authenticated;
grant select on public.duc_dk_thuc_te to authenticated;

-- Thông số nối 1–1 với mục thay đổi (cùng kiểu), không thì null
create or replace function public.duc_dk_ts_cua_muc(p_ma_muc text)
returns text language sql stable security definer set search_path = public as $$
  select min(t.ma_ts) from duc_dk_thong_so t join duc_thay_doi_mau m on m.ma = t.ma_muc_td
   where t.ma_muc_td = p_ma_muc
     and ((m.kieu_nhap = 'so' and t.kieu = 'so') or (m.kieu_nhap = 'chu' and t.kieu = 'chu'))
  having count(*) = 1
     and (select count(*) from duc_dk_thong_so x where x.ma_muc_td = p_ma_muc) = 1
$$;

-- 1) Xác nhận lên khuôn → Thực tế
create or replace function public.duc_dk_thuc_te_tu_xn()
returns trigger language plpgsql security definer set search_path = public as $$
declare k text; v jsonb; t record; g record;
begin
  for k, v in select * from jsonb_each(coalesce(new.gia_tri, '{}')) loop
    select * into t from duc_dk_thong_so where ma_ts = k;
    if not found then continue; end if;
    if t.kieu = 'so' and jsonb_typeof(v) = 'number' then
      insert into duc_dk_thuc_te (ma_may, ma_sp, ma_ts, gia_tri, gia_tri_chu, nguon, id_nguon, luc, nguoi)
      values (new.ma_may, new.ma_sp, k, (v #>> '{}')::numeric, null, 'xac_nhan', new.id, new.luc, new.nguoi_ten)
      on conflict (ma_may, ma_sp, ma_ts) do update set gia_tri = excluded.gia_tri, gia_tri_chu = null,
        nguon = 'xac_nhan', id_nguon = excluded.id_nguon, luc = excluded.luc, nguoi = excluded.nguoi;
    elsif t.kieu in ('chu', 'co_khong') and v #>> '{}' = 'dung' then
      select gia_tri_chu into g from duc_dk_gia_tri where id_phieu = new.id_phieu and ma_ts = k;
      if g.gia_tri_chu is null then continue; end if;
      insert into duc_dk_thuc_te (ma_may, ma_sp, ma_ts, gia_tri, gia_tri_chu, nguon, id_nguon, luc, nguoi)
      values (new.ma_may, new.ma_sp, k, null, g.gia_tri_chu, 'xac_nhan', new.id, new.luc, new.nguoi_ten)
      on conflict (ma_may, ma_sp, ma_ts) do update set gia_tri = null, gia_tri_chu = excluded.gia_tri_chu,
        nguon = 'xac_nhan', id_nguon = excluded.id_nguon, luc = excluded.luc, nguoi = excluded.nguoi;
    end if;
  end loop;
  return null;
end $$;
drop trigger if exists trg_duc_dk_thuc_te_xn on public.duc_dk_xac_nhan;
create trigger trg_duc_dk_thuc_te_xn after insert on public.duc_dk_xac_nhan
  for each row execute function public.duc_dk_thuc_te_tu_xn();

-- 2) Ghi thay đổi: "Trước" phải bằng Thực tế
create or replace function public.duc_dk_thuc_te_kiem_truoc()
returns trigger language plpgsql security definer set search_path = public as $$
declare e jsonb; k text; r record; v_truoc numeric;
begin
  if new.ma_sp is null then return new; end if;
  for e in select * from jsonb_array_elements(coalesce(new.chi_tiet, '[]')) loop
    k := duc_dk_ts_cua_muc(e->>'ma');
    if k is null then continue; end if;
    select * into r from duc_dk_thuc_te where ma_may = new.ma_may and ma_sp = new.ma_sp and ma_ts = k;
    if not found then continue; end if;
    if e->>'kieu' = 'so' and r.gia_tri is not null then
      v_truoc := nullif(e->>'truoc', '')::numeric;
      if v_truoc is distinct from r.gia_tri then
        raise exception '%: giá trị Trước phải là Thực tế đang cài (%).', e->>'ten', replace(trim_scale(r.gia_tri)::text, '.', ',');
      end if;
    elsif e->>'kieu' = 'chu' and r.gia_tri_chu is not null
          and lower(btrim(coalesce(e->>'truoc', ''))) is distinct from lower(btrim(r.gia_tri_chu)) then
      raise exception '%: giá trị Trước phải là Thực tế đang cài (%).', e->>'ten', r.gia_tri_chu;
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists trg_duc_dk_thuc_te_truoc on public.duc_thay_doi;
create trigger trg_duc_dk_thuc_te_truoc before insert on public.duc_thay_doi
  for each row execute function public.duc_dk_thuc_te_kiem_truoc();

-- 3) Áp dụng → Thực tế = Sau; Huỷ / Không duyệt bù sau khi đã áp dụng → trả về Trước
create or replace function public.duc_dk_thuc_te_tu_td()
returns trigger language plpgsql security definer set search_path = public as $$
declare e jsonb; k text; v_ap boolean; v_hoan boolean;
begin
  if new.ma_sp is null then return null; end if;
  v_ap := new.thoi_diem_ap_dung is not null and new.trang_thai not in ('huy', 'khong_duyet')
          and (tg_op = 'INSERT' or old.thoi_diem_ap_dung is null);
  v_hoan := tg_op = 'UPDATE' and old.thoi_diem_ap_dung is not null
          and ((new.trang_thai = 'huy' and old.trang_thai <> 'huy')
            or (new.ket_qua_duyet = 'khong_duyet' and old.ket_qua_duyet is distinct from 'khong_duyet'));
  if not (v_ap or v_hoan) then return null; end if;
  for e in select * from jsonb_array_elements(coalesce(new.chi_tiet, '[]')) loop
    k := duc_dk_ts_cua_muc(e->>'ma');
    if k is null then continue; end if;
    if v_ap then
      insert into duc_dk_thuc_te (ma_may, ma_sp, ma_ts, gia_tri, gia_tri_chu, nguon, id_nguon, luc, nguoi)
      values (new.ma_may, new.ma_sp, k,
              case when e->>'kieu' = 'so' then nullif(e->>'sau', '')::numeric end,
              case when e->>'kieu' = 'chu' then nullif(btrim(e->>'sau'), '') end,
              'thay_doi', new.id, now(), new.nguoi_ghi)
      on conflict (ma_may, ma_sp, ma_ts) do update set gia_tri = excluded.gia_tri, gia_tri_chu = excluded.gia_tri_chu,
        nguon = 'thay_doi', id_nguon = excluded.id_nguon, luc = now(), nguoi = excluded.nguoi;
    elsif nullif(btrim(coalesce(e->>'truoc', '')), '') is not null then
      update duc_dk_thuc_te
         set gia_tri = case when e->>'kieu' = 'so' then (e->>'truoc')::numeric end,
             gia_tri_chu = case when e->>'kieu' = 'chu' then btrim(e->>'truoc') end,
             nguon = 'hoan', luc = now()
       where ma_may = new.ma_may and ma_sp = new.ma_sp and ma_ts = k and nguon = 'thay_doi' and id_nguon = new.id;
    end if;
  end loop;
  return null;
end $$;
drop trigger if exists trg_duc_dk_thuc_te_td on public.duc_thay_doi;
create trigger trg_duc_dk_thuc_te_td after insert or update of thoi_diem_ap_dung, trang_thai, ket_qua_duyet on public.duc_thay_doi
  for each row execute function public.duc_dk_thuc_te_tu_td();

-- 4) Kỹ thuật sửa tay (p_gia_tri rỗng = xoá)
create or replace function public.duc_dk_thuc_te_sua(p_ma_may text, p_ma_sp text, p_ma_ts text, p_gia_tri text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t record; v_raw text := btrim(coalesce(p_gia_tri, '')); v_so numeric; v_chu text; v_sp text := upper(btrim(coalesce(p_ma_sp, '')));
begin
  if not duc_dk_la_ky_thuat() then
    raise exception '⛔ Chỉ bộ phận Kỹ thuật (hoặc admin) sửa Thực tế.' using errcode = '42501';
  end if;
  select * into t from duc_dk_thong_so where ma_ts = p_ma_ts;
  if not found then raise exception 'Thông số % không có trong danh mục.', p_ma_ts; end if;
  if v_raw = '' then
    delete from duc_dk_thuc_te where ma_may = p_ma_may and ma_sp = v_sp and ma_ts = p_ma_ts;
    return jsonb_build_object('ok', true, 'xoa', true);
  end if;
  if t.kieu = 'so' then
    if v_raw !~ '^-?[0-9]+([.,][0-9]+)?$' then raise exception '%: "%" không phải số.', t.ten, v_raw; end if;
    v_so := replace(v_raw, ',', '.')::numeric;
  elsif t.kieu = 'co_khong' then
    v_chu := case lower(v_raw) when 'co' then 'co' when 'có' then 'co' when 'khong' then 'khong' when 'không' then 'khong' end;
    if v_chu is null then raise exception '%: nhập Có hoặc Không.', t.ten; end if;
  else
    v_chu := v_raw;
  end if;
  insert into duc_dk_thuc_te (ma_may, ma_sp, ma_ts, gia_tri, gia_tri_chu, nguon, id_nguon, luc, nguoi)
  values (p_ma_may, v_sp, p_ma_ts, v_so, v_chu, 'sua_tay', null, now(), duc_dk_ten(auth.uid()))
  on conflict (ma_may, ma_sp, ma_ts) do update set gia_tri = excluded.gia_tri, gia_tri_chu = excluded.gia_tri_chu,
    nguon = 'sua_tay', id_nguon = null, luc = now(), nguoi = excluded.nguoi;
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.duc_dk_ts_cua_muc(text) from public, anon;
grant execute on function public.duc_dk_ts_cua_muc(text) to authenticated;
revoke execute on function public.duc_dk_thuc_te_tu_xn() from public, anon, authenticated;
revoke execute on function public.duc_dk_thuc_te_kiem_truoc() from public, anon, authenticated;
revoke execute on function public.duc_dk_thuc_te_tu_td() from public, anon, authenticated;
revoke execute on function public.duc_dk_thuc_te_sua(text, text, text, text) from public, anon;
grant execute on function public.duc_dk_thuc_te_sua(text, text, text, text) to authenticated;
