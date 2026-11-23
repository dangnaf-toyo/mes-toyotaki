-- T324: Điều kiện đúc Bước 8 — xác nhận ĐK đúc khi lên khuôn / bắt đầu SX mã SP trên máy.
-- • Cặp (máy, mã SP) có phiếu Hiệu lực + SP không chạy tiếp trên máy đó (tem / sự cố / dòng khác trong 1 ngày)
--   → trưởng ca phải xác nhận: dụng cụ đúng mã phiếu, thông số ★ số trong ±ngưỡng (hoặc bằng giá trị
--   thay đổi đã duyệt / áp dụng khẩn sau ngày hiệu lực), thông số ★ chữ tick "Đúng". Hiệu lực 12 giờ.
-- • Trigger trên duc_ca_hien_tai chặn insert / đổi ma_sp, ma_may khi chưa xác nhận (sau trigger T127).
-- • Công tắc: duc_cau_hinh.chan_dk_duc_chua_xac_nhan = 'false' → bỏ chặn.
-- Chạy lại được.

insert into public.duc_cau_hinh (khoa, gia_tri, ghi_chu) values
  ('chan_dk_duc_chua_xac_nhan', 'true'::jsonb, 'T324: chặn lên khuôn khi trưởng ca chưa xác nhận điều kiện đúc (phiếu Hiệu lực)')
on conflict (khoa) do nothing;

create table if not exists public.duc_dk_xac_nhan (
  id bigserial primary key,
  ma_may text not null,
  ma_sp text not null,
  id_phieu bigint not null references public.duc_dk_phieu(id),
  id_dong text,
  gia_tri jsonb not null default '{}',      -- {ma_ts: số đang cài | 'dung'}
  dung_cu jsonb not null default '{}',      -- {loai: mã đang lắp}
  lech jsonb not null default '[]',         -- [{ma_ts, gia_tri, chuan, td}] dùng giá trị thay đổi đã duyệt
  nguoi uuid, nguoi_ten text,
  luc timestamptz not null default now(),
  het_han timestamptz not null default now() + interval '12 hours'
);
create index if not exists duc_dk_xac_nhan_may_sp on public.duc_dk_xac_nhan (ma_may, ma_sp, het_han desc);
create index if not exists duc_dk_xac_nhan_phieu on public.duc_dk_xac_nhan (id_phieu, luc desc);
alter table public.duc_dk_xac_nhan enable row level security;
drop policy if exists "dkxn doc" on public.duc_dk_xac_nhan;
create policy "dkxn doc" on public.duc_dk_xac_nhan for select to authenticated using (true);
revoke all on public.duc_dk_xac_nhan from anon;
revoke insert, update, delete on public.duc_dk_xac_nhan from authenticated;
grant select on public.duc_dk_xac_nhan to authenticated;

-- Mã SP đang chạy tiếp trên máy (giống duc_khuon_dang_tren_may của T100, so mã SP)
create or replace function public.duc_dk_sp_dang_tren_may(p_ma_sp text, p_ma_may text, p_ngay date, p_id_dong text default null)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from duc_ca_hien_tai c
                 where c.ma_may = p_ma_may and upper(trim(c.ma_sp)) = upper(trim(p_ma_sp))
                   and c.id_dong is distinct from p_id_dong)
      or exists (select 1 from duc_tem t
                 where upper(trim(t.ma_sp)) = upper(trim(p_ma_sp))
                   and replace(t.may_duc_chi_thi, ' ', '') = replace(p_ma_may, ' ', '')
                   and t.ngay between coalesce(p_ngay, current_date) - 1 and coalesce(p_ngay, current_date))
      or exists (select 1 from duc_su_co_log s
                 where upper(trim(s.ma_sp)) = upper(trim(p_ma_sp))
                   and replace(s.ma_may, ' ', '') = replace(p_ma_may, ' ', '')
                   and s.ngay between coalesce(p_ngay, current_date) - 1 and coalesce(p_ngay, current_date));
$$;

create or replace function public.duc_dk_bat_chan()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select gia_tri = 'true'::jsonb from duc_cau_hinh where khoa = 'chan_dk_duc_chua_xac_nhan'), false);
$$;

create or replace function public.duc_dk_da_xac_nhan(p_ma_may text, p_ma_sp text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from duc_dk_xac_nhan x
                  join duc_dk_phieu p on p.id = x.id_phieu and p.trang_thai = 'hieu_luc'
                 where x.ma_may = p_ma_may and x.ma_sp = upper(trim(p_ma_sp)) and x.het_han > now());
$$;

-- Thông số ★ cần xác nhận của phiếu (kèm giá trị thay đổi đã duyệt / áp dụng khẩn sau ngày hiệu lực)
create or replace function public.duc_dk_xn_thong_so(p_id bigint)
returns jsonb language sql stable security definer set search_path = public as $$
  with p as (select *, duc_dk_loai_may(ma_may) loai from duc_dk_phieu where id = p_id)
  select coalesce(jsonb_agg(jsonb_build_object(
      'ma_ts', t.ma_ts, 'nhom', t.nhom, 'ten', t.ten, 'don_vi', t.don_vi, 'kieu', t.kieu,
      'chuan', g.chuan, 'chu', case when t.kieu = 'chon_nvl' then p.ma_nvl else g.gia_tri_chu end,
      'nguong', t.nguong_pct,
      'td', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'gia_tri', (e->>'sau')::numeric) order by d.id), '[]'::jsonb)
               from duc_thay_doi d, jsonb_array_elements(d.chi_tiet) e
              where t.kieu = 'so' and t.ma_muc_td is not null
                and d.ma_may = p.ma_may and upper(d.ma_sp) = p.ma_sp
                and d.thoi_diem_ghi >= coalesce(p.hieu_luc_tu, p.duyet_luc, p.lap_luc)
                and e->>'ma' = t.ma_muc_td and (e->>'sau') ~ '^-?[0-9]+(\.[0-9]+)?$'
                and (d.ket_qua_duyet = 'da_duyet'
                     or (d.khan and d.trang_thai <> 'huy' and d.ket_qua_duyet is distinct from 'khong_duyet')))
    ) order by t.nhom, t.thu_tu), '[]'::jsonb)
    from p
    join duc_dk_thong_so t on t.hien and t.ap_dung in (p.loai, 'ca_hai')
                          and case p.loai when 'kem' then t.bat_buoc_kem else t.bat_buoc_nhom end
    left join duc_dk_gia_tri g on g.id_phieu = p.id and g.ma_ts = t.ma_ts
   where (t.kieu = 'so' and g.chuan is not null)
      or (t.kieu in ('chu', 'co_khong') and nullif(btrim(g.gia_tri_chu), '') is not null)
      or (t.kieu = 'chon_nvl' and nullif(btrim(p.ma_nvl), '') is not null);
$$;

-- Dữ liệu hộp xác nhận
create or replace function public.duc_dk_len_khuon(p_ma_may text, p_ma_sp text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_sp text := upper(trim(coalesce(p_ma_sp, ''))); p record;
        v_ngay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into p from duc_dk_phieu where ma_may = p_ma_may and ma_sp = v_sp and trang_thai = 'hieu_luc';
  if not found then return jsonb_build_object('ok', true, 'co_phieu', false, 'bat', duc_dk_bat_chan()); end if;
  return jsonb_build_object('ok', true, 'co_phieu', true, 'bat', duc_dk_bat_chan(),
    'chay_tiep', duc_dk_sp_dang_tren_may(v_sp, p_ma_may, v_ngay, null),
    'da_xac_nhan', duc_dk_da_xac_nhan(p_ma_may, v_sp),
    'phieu', jsonb_build_object('id', p.id, 'lan', p.lan, 'ma_may', p.ma_may, 'ma_sp', p.ma_sp),
    'thong_so', duc_dk_xn_thong_so(p.id),
    'dung_cu', (select coalesce(jsonb_agg(jsonb_build_object('loai', d.loai, 'ma', d.ma_dung_cu, 'ten', c.ten,
        'chon', (select coalesce(jsonb_agg(jsonb_build_object('ma', x.ma, 'ten', x.ten) order by x.ma), '[]'::jsonb)
                   from duc_dung_cu x
                  where x.loai = d.loai and (x.hien or x.ma = d.ma_dung_cu)
                    and (cardinality(x.may_dung) = 0 or p.ma_may = any(x.may_dung) or x.ma = d.ma_dung_cu)))
        order by d.loai), '[]'::jsonb)
      from duc_dk_dung_cu d left join duc_dung_cu c on c.ma = d.ma_dung_cu where d.id_phieu = p.id));
end $$;

-- Lưu xác nhận (kiểm lại toàn bộ trong DB)
create or replace function public.duc_dk_xac_nhan_luu(p_ma_may text, p_ma_sp text, p_gia_tri jsonb, p_dung_cu jsonb,
                                                       p_id_dong text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_sp text := upper(trim(coalesce(p_ma_sp, ''))); p record; t jsonb; d record;
        v_loi text[] := '{}'; v_lech jsonb := '[]'; v_so numeric; v_chuan numeric; v_bien numeric; v_td jsonb;
        v_gt jsonb := '{}'; v_id bigint; v_raw text;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into p from duc_dk_phieu where ma_may = p_ma_may and ma_sp = v_sp and trang_thai = 'hieu_luc';
  if not found then return jsonb_build_object('ok', false, 'error', 'Máy này chưa có phiếu ĐK đúc hiệu lực cho mã SP này'); end if;

  for d in select dc.loai, dc.ma_dung_cu from duc_dk_dung_cu dc where dc.id_phieu = p.id loop
    if coalesce(p_dung_cu->>d.loai, '') <> d.ma_dung_cu then
      v_loi := v_loi || ('Dụng cụ ' || d.loai || ': phải là ' || d.ma_dung_cu);
    end if;
  end loop;

  for t in select * from jsonb_array_elements(duc_dk_xn_thong_so(p.id)) loop
    v_raw := btrim(coalesce(p_gia_tri->>(t->>'ma_ts'), ''));
    if t->>'kieu' = 'so' then
      if v_raw !~ '^-?[0-9]+([.,][0-9]+)?$' then
        v_loi := v_loi || ((t->>'ten') || ': chưa nhập số'); continue;
      end if;
      v_so := replace(v_raw, ',', '.')::numeric;
      v_chuan := (t->>'chuan')::numeric;
      v_bien := abs(v_chuan) * coalesce((t->>'nguong')::numeric, 5) / 100;
      v_gt := v_gt || jsonb_build_object(t->>'ma_ts', v_so);
      if abs(v_so - v_chuan) <= v_bien + 1e-9 then continue; end if;
      v_td := null;
      select e into v_td from jsonb_array_elements(t->'td') e
       where abs(v_so - (e->>'gia_tri')::numeric) <= abs((e->>'gia_tri')::numeric) * coalesce((t->>'nguong')::numeric, 5) / 100 + 1e-9
       order by (e->>'id')::bigint desc limit 1;
      if v_td is not null then
        v_lech := v_lech || jsonb_build_array(jsonb_build_object('ma_ts', t->>'ma_ts', 'gia_tri', v_so, 'chuan', v_chuan, 'td', v_td->'id'));
      else
        v_loi := v_loi || ((t->>'ten') || ' ' || trim_scale(v_so) || ' ngoài ' || trim_scale(round(v_chuan - v_bien, 3)) || ' – ' || trim_scale(round(v_chuan + v_bien, 3)));
      end if;
    else
      if v_raw <> 'dung' then v_loi := v_loi || ((t->>'ten') || ': chưa tick Đúng'); continue; end if;
      v_gt := v_gt || jsonb_build_object(t->>'ma_ts', 'dung');
    end if;
  end loop;

  if cardinality(v_loi) > 0 then
    return jsonb_build_object('ok', false, 'error', array_to_string(v_loi, '; '), 'loi', to_jsonb(v_loi));
  end if;
  insert into duc_dk_xac_nhan (ma_may, ma_sp, id_phieu, id_dong, gia_tri, dung_cu, lech, nguoi, nguoi_ten)
  values (p_ma_may, v_sp, p.id, nullif(btrim(coalesce(p_id_dong, '')), ''), v_gt, coalesce(p_dung_cu, '{}'), v_lech,
          auth.uid(), duc_dk_ten(auth.uid()))
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'lech', v_lech);
end $$;

-- Trigger chặn lên khuôn / đổi SP khi chưa xác nhận
create or replace function public.duc_ca_hien_tai_chan_dk_duc()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_sp text := upper(trim(coalesce(new.ma_sp, ''))); v_lan int;
begin
  if v_sp = '' or coalesce(new.ma_may, '') = '' then return new; end if;
  if tg_op = 'UPDATE' and upper(trim(coalesce(old.ma_sp, ''))) = v_sp and new.ma_may is not distinct from old.ma_may then
    return new;
  end if;
  if not duc_dk_bat_chan() then return new; end if;
  select lan into v_lan from duc_dk_phieu where ma_may = new.ma_may and ma_sp = v_sp and trang_thai = 'hieu_luc';
  if not found then return new; end if;
  if duc_dk_sp_dang_tren_may(v_sp, new.ma_may, new.ngay, new.id_dong) then return new; end if;
  if duc_dk_da_xac_nhan(new.ma_may, v_sp) then return new; end if;
  raise exception 'Chưa xác nhận điều kiện đúc % · % (phiếu lần %). Gán lại trên Bảng điều khiển Đúc / ĐT để mở hộp xác nhận.',
    new.ma_may, v_sp, v_lan;
end $$;

drop trigger if exists trg_duc_ca_hien_tai_dk_xac_nhan on public.duc_ca_hien_tai;
create trigger trg_duc_ca_hien_tai_dk_xac_nhan
  before insert or update of ma_sp, ma_may on public.duc_ca_hien_tai
  for each row execute function public.duc_ca_hien_tai_chan_dk_duc();

-- Quyền
revoke execute on function public.duc_dk_sp_dang_tren_may(text, text, date, text), public.duc_dk_bat_chan(),
  public.duc_dk_da_xac_nhan(text, text), public.duc_dk_xn_thong_so(bigint), public.duc_ca_hien_tai_chan_dk_duc()
  from public, anon, authenticated;
revoke execute on function public.duc_dk_len_khuon(text, text),
  public.duc_dk_xac_nhan_luu(text, text, jsonb, jsonb, text) from public, anon;
grant execute on function public.duc_dk_len_khuon(text, text),
  public.duc_dk_xac_nhan_luu(text, text, jsonb, jsonb, text) to authenticated;
