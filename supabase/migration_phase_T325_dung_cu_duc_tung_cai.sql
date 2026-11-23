-- T325: Điều kiện đúc Bước 9 — theo dõi TỪNG CÁI dụng cụ đúc (DT-060-01/03).
--  * duc_dung_cu_cai: từng cái (mã kiểu + "/STT"), shot đã dùng trước khi theo dõi, trạng thái kho / tren_may / hong.
--  * duc_dung_cu_lap: lịch sử lắp / tháo trên máy (1 cái đang lắp / máy / loại).
--  * Lần bắn đếm từ tem Đúc: so_luong_tt ÷ cavity của tem in trên máy trong [lắp, tháo).
--    (Khuôn nhóm nhiều mã SP / 1 lần bắn sẽ bị đếm dư — chấp nhận, ghi ⓘ ở giao diện.)
--  * Lắp: hộp xác nhận ĐK đúc lúc lên khuôn (chọn đúng cái) hoặc nút Thay ở dung-cu-duc.html.
--  * Chuông 80% (1 lần) / 100% (nhắc mỗi 24 giờ) → trưởng ca + QLBP Đúc; tháo ra thì tự tắt. Không chặn.
--  * Quyền: Kỹ thuật/admin thêm cái, sửa, báo hỏng; trưởng ca + Kỹ thuật lắp / tháo / thay.

-- ── Bảng ────────────────────────────────────────────────────────────────────
create table if not exists duc_dung_cu_cai (
  id bigserial primary key,
  ma_cai text not null unique,
  ma_dung_cu text not null references duc_dung_cu(ma) on update cascade,
  stt int not null,
  shot_ban_dau int not null default 0 check (shot_ban_dau >= 0),
  trang_thai text not null default 'kho' check (trang_thai in ('kho', 'tren_may', 'hong')),
  ghi_chu text,
  tao_luc timestamptz not null default now(),
  tao_boi uuid,
  hong_luc timestamptz, hong_boi uuid, hong_ten text, hong_ly_do text,
  unique (ma_dung_cu, stt)
);

create table if not exists duc_dung_cu_lap (
  id bigserial primary key,
  id_cai bigint not null references duc_dung_cu_cai(id) on delete cascade,
  ma_may text not null,
  loai text not null,
  lap_luc timestamptz not null default now(),
  lap_boi uuid, lap_ten text,
  nguon text not null default 'thay' check (nguon in ('thay', 'xac_nhan')),
  thao_luc timestamptz, thao_boi uuid, thao_ten text, ly_do_thao text,
  shot numeric             -- số lần bắn trong lần lắp này, chốt lúc tháo
);
create unique index if not exists duc_dung_cu_lap_may_loai_mo on duc_dung_cu_lap (ma_may, loai) where thao_luc is null;
create unique index if not exists duc_dung_cu_lap_cai_mo on duc_dung_cu_lap (id_cai) where thao_luc is null;
create index if not exists duc_dung_cu_lap_cai on duc_dung_cu_lap (id_cai);
create index if not exists idx_duc_tem_may_tt_ts on duc_tem (may_tt, (coalesce(ngay_gio_ghi_nhan, ngay_gio_in))) where may_tt is not null;

alter table duc_dung_cu_cai enable row level security;
alter table duc_dung_cu_lap enable row level security;
drop policy if exists duc_dung_cu_cai_doc on duc_dung_cu_cai;
create policy duc_dung_cu_cai_doc on duc_dung_cu_cai for select to authenticated using (true);
drop policy if exists duc_dung_cu_lap_doc on duc_dung_cu_lap;
create policy duc_dung_cu_lap_doc on duc_dung_cu_lap for select to authenticated using (true);
revoke all on duc_dung_cu_cai, duc_dung_cu_lap from anon;
grant select on duc_dung_cu_cai, duc_dung_cu_lap to authenticated;

-- ── Đếm lần bắn từ tem ──────────────────────────────────────────────────────
create or replace function duc_dc_so_shot(p_may text, p_tu timestamptz, p_den timestamptz)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(round(sum(coalesce(t.so_luong_tt, t.so_luong, 0) / coalesce(nullif(mp.cavity, 0), 1))), 0)
  from duc_tem t left join master_products mp on mp.ma_sp = t.ma_sp
  where t.may_tt = p_may
    and coalesce(t.ngay_gio_ghi_nhan, t.ngay_gio_in) >= p_tu
    and coalesce(t.ngay_gio_ghi_nhan, t.ngay_gio_in) < coalesce(p_den, 'infinity'::timestamptz);
$$;

create or replace view duc_dung_cu_cai_v with (security_invoker = true) as
select c.id, c.ma_cai, c.ma_dung_cu, c.stt, c.shot_ban_dau, c.trang_thai, c.ghi_chu, c.tao_luc,
       c.hong_luc, c.hong_ten, c.hong_ly_do,
       d.loai, d.ten, d.duong_kinh, d.may_dung, d.tuoi_tho_du_kien,
       l.id as id_lap, l.ma_may, l.lap_luc, l.lap_ten,
       coalesce(h.shot_cu, 0) as shot_cu,
       case when l.id is null then 0 else duc_dc_so_shot(l.ma_may, l.lap_luc, null) end as shot_dang,
       c.shot_ban_dau + coalesce(h.shot_cu, 0)
         + case when l.id is null then 0 else duc_dc_so_shot(l.ma_may, l.lap_luc, null) end as shot_tong
from duc_dung_cu_cai c
join duc_dung_cu d on d.ma = c.ma_dung_cu
left join duc_dung_cu_lap l on l.id_cai = c.id and l.thao_luc is null
left join lateral (select sum(x.shot) as shot_cu from duc_dung_cu_lap x where x.id_cai = c.id and x.thao_luc is not null) h on true;
grant select on duc_dung_cu_cai_v to authenticated;
revoke all on duc_dung_cu_cai_v from anon;

-- ── Quyền ───────────────────────────────────────────────────────────────────
create or replace function duc_dc_quyen()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('ky_thuat', duc_dk_la_ky_thuat(),
                            'lap', duc_dk_la_ky_thuat() or has_role('truong_ca'));
$$;

-- ── Nội bộ: tháo 1 dòng lắp ─────────────────────────────────────────────────
create or replace function duc_dc_thao_noi(p_id_lap bigint, p_ly_do text, p_trang_thai text)
returns void language plpgsql security definer set search_path = public as $$
declare l record;
begin
  select * into l from duc_dung_cu_lap where id = p_id_lap and thao_luc is null for update;
  if not found then return; end if;
  update duc_dung_cu_lap set thao_luc = now(), thao_boi = auth.uid(), thao_ten = duc_dk_ten(auth.uid()),
         ly_do_thao = nullif(btrim(coalesce(p_ly_do, '')), ''),
         shot = duc_dc_so_shot(l.ma_may, l.lap_luc, now())
   where id = p_id_lap;
  update duc_dung_cu_cai set trang_thai = p_trang_thai where id = l.id_cai;
  perform cv_pd_xong('dcd:' || p_id_lap || ':', true);
end $$;

-- ── Nội bộ: lắp 1 cái lên máy (tháo cái cũ cùng loại + tháo cái này khỏi máy khác) ──
create or replace function duc_dc_lap_noi(p_id_cai bigint, p_may text, p_nguon text, p_ly_do text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c record; v_cu record; v_id bigint;
begin
  select c0.*, d.loai, d.may_dung into c
    from duc_dung_cu_cai c0 join duc_dung_cu d on d.ma = c0.ma_dung_cu where c0.id = p_id_cai for update of c0;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không có cái dụng cụ này'); end if;
  if c.trang_thai = 'hong' then return jsonb_build_object('ok', false, 'error', c.ma_cai || ' đã báo hỏng'); end if;
  if not exists (select 1 from master_machines m where m.ma_may = p_may and m.loai_may in ('Đúc nhôm', 'Đúc kẽm')) then
    return jsonb_build_object('ok', false, 'error', 'Máy ' || coalesce(p_may, '') || ' không phải máy đúc');
  end if;
  if cardinality(coalesce(c.may_dung, '{}')) > 0 and not (p_may = any(c.may_dung)) then
    return jsonb_build_object('ok', false, 'error', c.ma_dung_cu || ' không dùng được cho ' || p_may);
  end if;
  -- đã lắp đúng máy này rồi
  if exists (select 1 from duc_dung_cu_lap where id_cai = c.id and thao_luc is null and ma_may = p_may) then
    return jsonb_build_object('ok', true, 'ma_cai', c.ma_cai, 'da_lap', true);
  end if;
  -- cái cũ cùng loại trên máy → về kho
  for v_cu in select id from duc_dung_cu_lap where ma_may = p_may and loai = c.loai and thao_luc is null loop
    perform duc_dc_thao_noi(v_cu.id, coalesce(nullif(btrim(coalesce(p_ly_do, '')), ''), 'Thay bằng ' || c.ma_cai), 'kho');
  end loop;
  -- cái này đang ở máy khác → chuyển
  for v_cu in select id, ma_may from duc_dung_cu_lap where id_cai = c.id and thao_luc is null loop
    perform duc_dc_thao_noi(v_cu.id, 'Chuyển sang ' || p_may, 'kho');
  end loop;
  insert into duc_dung_cu_lap (id_cai, ma_may, loai, lap_boi, lap_ten, nguon)
  values (c.id, p_may, c.loai, auth.uid(), duc_dk_ten(auth.uid()), p_nguon)
  returning id into v_id;
  update duc_dung_cu_cai set trang_thai = 'tren_may' where id = c.id;
  return jsonb_build_object('ok', true, 'ma_cai', c.ma_cai, 'id_lap', v_id);
end $$;

-- ── RPC giao diện ───────────────────────────────────────────────────────────
create or replace function duc_dc_cai_them(p_ma_dung_cu text, p_so int default 1, p_shot_ban_dau int default 0, p_ghi_chu text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_stt int; v_ma text; v_ds text[] := '{}'; i int;
begin
  if not duc_dk_la_ky_thuat() then return jsonb_build_object('ok', false, 'error', 'Chỉ Kỹ thuật / admin được thêm'); end if;
  if not exists (select 1 from duc_dung_cu where ma = p_ma_dung_cu) then
    return jsonb_build_object('ok', false, 'error', 'Không có mã dụng cụ ' || coalesce(p_ma_dung_cu, ''));
  end if;
  if coalesce(p_so, 0) < 1 or p_so > 20 then return jsonb_build_object('ok', false, 'error', 'Số lượng 1 – 20'); end if;
  if coalesce(p_shot_ban_dau, 0) < 0 then return jsonb_build_object('ok', false, 'error', 'Đã bắn phải ≥ 0'); end if;
  perform 1 from duc_dung_cu where ma = p_ma_dung_cu for update;
  select coalesce(max(stt), 0) into v_stt from duc_dung_cu_cai where ma_dung_cu = p_ma_dung_cu;
  for i in 1..p_so loop
    v_stt := v_stt + 1;
    v_ma := p_ma_dung_cu || '/' || lpad(v_stt::text, 2, '0');
    insert into duc_dung_cu_cai (ma_cai, ma_dung_cu, stt, shot_ban_dau, ghi_chu, tao_boi)
    values (v_ma, p_ma_dung_cu, v_stt, coalesce(p_shot_ban_dau, 0), nullif(btrim(coalesce(p_ghi_chu, '')), ''), auth.uid());
    v_ds := v_ds || v_ma;
  end loop;
  return jsonb_build_object('ok', true, 'ma', to_jsonb(v_ds));
end $$;

create or replace function duc_dc_cai_sua(p_ma_cai text, p_shot_ban_dau int, p_ghi_chu text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not duc_dk_la_ky_thuat() then return jsonb_build_object('ok', false, 'error', 'Chỉ Kỹ thuật / admin được sửa'); end if;
  if coalesce(p_shot_ban_dau, 0) < 0 then return jsonb_build_object('ok', false, 'error', 'Đã bắn phải ≥ 0'); end if;
  update duc_dung_cu_cai set shot_ban_dau = coalesce(p_shot_ban_dau, 0), ghi_chu = nullif(btrim(coalesce(p_ghi_chu, '')), '')
   where ma_cai = p_ma_cai;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không có ' || coalesce(p_ma_cai, '')); end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function duc_dc_lap(p_ma_cai text, p_ma_may text, p_ly_do text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if not (duc_dk_la_ky_thuat() or has_role('truong_ca')) then
    return jsonb_build_object('ok', false, 'error', 'Chỉ trưởng ca / Kỹ thuật được lắp');
  end if;
  select id into v_id from duc_dung_cu_cai where ma_cai = p_ma_cai;
  if v_id is null then return jsonb_build_object('ok', false, 'error', 'Không có ' || coalesce(p_ma_cai, '')); end if;
  return duc_dc_lap_noi(v_id, p_ma_may, 'thay', p_ly_do);
end $$;

create or replace function duc_dc_thao(p_ma_cai text, p_ly_do text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_lap bigint;
begin
  if not (duc_dk_la_ky_thuat() or has_role('truong_ca')) then
    return jsonb_build_object('ok', false, 'error', 'Chỉ trưởng ca / Kỹ thuật được tháo');
  end if;
  select l.id into v_lap from duc_dung_cu_lap l join duc_dung_cu_cai c on c.id = l.id_cai
   where c.ma_cai = p_ma_cai and l.thao_luc is null;
  if v_lap is null then return jsonb_build_object('ok', false, 'error', coalesce(p_ma_cai, '') || ' không đang lắp trên máy'); end if;
  perform duc_dc_thao_noi(v_lap, coalesce(nullif(btrim(coalesce(p_ly_do, '')), ''), 'Tháo'), 'kho');
  return jsonb_build_object('ok', true);
end $$;

create or replace function duc_dc_hong(p_ma_cai text, p_ly_do text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c record; v_lap bigint;
begin
  if not duc_dk_la_ky_thuat() then return jsonb_build_object('ok', false, 'error', 'Chỉ Kỹ thuật / admin được báo hỏng'); end if;
  if btrim(coalesce(p_ly_do, '')) = '' then return jsonb_build_object('ok', false, 'error', 'Cần ghi lý do hỏng'); end if;
  select * into c from duc_dung_cu_cai where ma_cai = p_ma_cai for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không có ' || coalesce(p_ma_cai, '')); end if;
  if c.trang_thai = 'hong' then return jsonb_build_object('ok', false, 'error', 'Đã báo hỏng rồi'); end if;
  select id into v_lap from duc_dung_cu_lap where id_cai = c.id and thao_luc is null;
  if v_lap is not null then perform duc_dc_thao_noi(v_lap, 'Hỏng: ' || btrim(p_ly_do), 'hong'); end if;
  update duc_dung_cu_cai set trang_thai = 'hong', hong_luc = now(), hong_boi = auth.uid(),
         hong_ten = duc_dk_ten(auth.uid()), hong_ly_do = btrim(p_ly_do)
   where id = c.id;
  return jsonb_build_object('ok', true);
end $$;

-- ── Chuông 80% / 100% (cron 10 phút) ────────────────────────────────────────
create or replace function duc_dc_nhac()
returns integer language plpgsql security definer set search_path = public as $$
declare r record; v_n int := 0; v_nguoi uuid[]; v_khoa text; v_cu timestamptz; v_lk text; v_ten text; v_pct int;
begin
  v_nguoi := cv_pd_ds_role(array['truong_ca']) || cv_pd_ds_role(array['quan_ly_bo_phan'], 'Đúc');
  -- đã tháo → tắt chuông
  update cv_thong_bao tb set da_xu_ly = true
   where tb.nguon = 'dieu_kien_duc' and tb.can_xu_ly and not tb.da_xu_ly and tb.khoa like 'dcd:%'
     and not exists (select 1 from duc_dung_cu_lap l where l.thao_luc is null and l.id::text = split_part(tb.khoa, ':', 2));
  for r in
    select v.* from duc_dung_cu_cai_v v
     where v.id_lap is not null and coalesce(v.tuoi_tho_du_kien, 0) > 0 and v.shot_tong * 100 >= v.tuoi_tho_du_kien * 80
  loop
    v_pct := floor(r.shot_tong * 100.0 / r.tuoi_tho_du_kien)::int;
    v_lk := 'dung-cu-duc.html?may=' || replace(r.ma_may, ' ', '%20');
    v_ten := r.ma_may || ' · ' || r.ma_cai || ' đã bắn '
      || replace(to_char(r.shot_tong, 'FM999,999,990'), ',', '.') || '/' || replace(to_char(r.tuoi_tho_du_kien, 'FM999,999,990'), ',', '.')
      || ' (' || v_pct || '%)';
    if v_pct >= 100 then
      v_khoa := 'dcd:' || r.id_lap || ':100';
      select max(created_at) into v_cu from cv_thong_bao where khoa = v_khoa;
      if v_cu is null or v_cu < now() - interval '23 hours 50 minutes' then
        perform cv_pd_xong(v_khoa);
        perform cv_pd_xong('dcd:' || r.id_lap || ':80');
        v_n := v_n + cv_pd_gui(v_nguoi, 'dieu_kien_duc', 'dung_cu_het', v_khoa, v_lk,
          v_ten || ' — hết tuổi thọ, cần thay.', true);
      end if;
    else
      v_khoa := 'dcd:' || r.id_lap || ':80';
      if not exists (select 1 from cv_thong_bao where khoa = v_khoa) then
        v_n := v_n + cv_pd_gui(v_nguoi, 'dieu_kien_duc', 'dung_cu_sap_het', v_khoa, v_lk,
          v_ten || ' — sắp hết tuổi thọ, chuẩn bị cái thay.', true);
      end if;
    end if;
  end loop;
  return v_n;
end $$;

-- ── Hộp xác nhận ĐK đúc: cho chọn từng cái ──────────────────────────────────
create or replace function public.duc_dk_len_khuon(p_ma_may text, p_ma_sp text)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
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
        'dang', (select v.ma_cai from duc_dung_cu_cai_v v where v.ma_may = p.ma_may and v.loai = d.loai and v.id_lap is not null limit 1),
        'chon', (select coalesce(jsonb_agg(o.j order by o.k), '[]'::jsonb) from (
                   -- mã kiểu chưa có cái nào theo dõi → chọn mã kiểu
                   select x.ma as k, jsonb_build_object('ma', x.ma, 'ten', x.ten) as j
                     from duc_dung_cu x
                    where x.loai = d.loai and (x.hien or x.ma = d.ma_dung_cu)
                      and (cardinality(x.may_dung) = 0 or p.ma_may = any(x.may_dung) or x.ma = d.ma_dung_cu)
                      and not exists (select 1 from duc_dung_cu_cai cc where cc.ma_dung_cu = x.ma and cc.trang_thai <> 'hong')
                   union all
                   -- mã kiểu đã có cái → chọn từng cái
                   select v.ma_cai, jsonb_build_object('ma', v.ma_cai, 'goc', v.ma_dung_cu, 'ten', v.ten, 'may', v.ma_may,
                            'pct', case when coalesce(v.tuoi_tho_du_kien, 0) > 0 then floor(v.shot_tong * 100.0 / v.tuoi_tho_du_kien)::int end)
                     from duc_dung_cu_cai_v v
                    where v.loai = d.loai and v.trang_thai <> 'hong'
                      and (cardinality(v.may_dung) = 0 or p.ma_may = any(v.may_dung) or v.ma_dung_cu = d.ma_dung_cu)
                 ) o))
        order by d.loai), '[]'::jsonb)
      from duc_dk_dung_cu d left join duc_dung_cu c on c.ma = d.ma_dung_cu where d.id_phieu = p.id));
end $function$;

create or replace function public.duc_dk_xac_nhan_luu(p_ma_may text, p_ma_sp text, p_gia_tri jsonb, p_dung_cu jsonb, p_id_dong text default null::text)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_sp text := upper(trim(coalesce(p_ma_sp, ''))); p record; t jsonb; d record;
        v_loi text[] := '{}'; v_lech jsonb := '[]'; v_so numeric; v_chuan numeric; v_bien numeric; v_td jsonb;
        v_gt jsonb := '{}'; v_id bigint; v_raw text; v_chon text; v_cai record; v_r jsonb; v_lap bigint[] := '{}';
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into p from duc_dk_phieu where ma_may = p_ma_may and ma_sp = v_sp and trang_thai = 'hieu_luc';
  if not found then return jsonb_build_object('ok', false, 'error', 'Máy này chưa có phiếu ĐK đúc hiệu lực cho mã SP này'); end if;

  for d in select dc.loai, dc.ma_dung_cu from duc_dk_dung_cu dc where dc.id_phieu = p.id loop
    v_chon := btrim(coalesce(p_dung_cu->>d.loai, ''));
    if split_part(v_chon, '/', 1) <> d.ma_dung_cu then
      v_loi := v_loi || ('Dụng cụ ' || d.loai || ': phải là ' || d.ma_dung_cu);
      continue;
    end if;
    if position('/' in v_chon) > 0 then
      select * into v_cai from duc_dung_cu_cai where ma_cai = v_chon;
      if not found then v_loi := v_loi || ('Không có ' || v_chon); continue; end if;
      if v_cai.trang_thai = 'hong' then v_loi := v_loi || (v_chon || ' đã báo hỏng'); continue; end if;
      v_lap := v_lap || v_cai.id;
    elsif exists (select 1 from duc_dung_cu_cai where ma_dung_cu = d.ma_dung_cu and trang_thai <> 'hong') then
      v_loi := v_loi || ('Dụng cụ ' || d.loai || ': chọn đúng cái đang lắp (' || d.ma_dung_cu || '/..)');
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
  -- T325: lắp từng cái đã chọn lên máy (cái cũ cùng loại tự về kho)
  for i in 1..coalesce(cardinality(v_lap), 0) loop
    v_r := duc_dc_lap_noi(v_lap[i], p_ma_may, 'xac_nhan', null);
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '%', v_r->>'error';
    end if;
  end loop;
  insert into duc_dk_xac_nhan (ma_may, ma_sp, id_phieu, id_dong, gia_tri, dung_cu, lech, nguoi, nguoi_ten)
  values (p_ma_may, v_sp, p.id, nullif(btrim(coalesce(p_id_dong, '')), ''), v_gt, coalesce(p_dung_cu, '{}'), v_lech,
          auth.uid(), duc_dk_ten(auth.uid()))
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'lech', v_lech);
end $function$;

-- ── Quyền thực thi ──────────────────────────────────────────────────────────
revoke execute on function duc_dc_so_shot(text, timestamptz, timestamptz) from public, anon;
revoke execute on function duc_dc_thao_noi(bigint, text, text) from public, anon, authenticated;
revoke execute on function duc_dc_lap_noi(bigint, text, text, text) from public, anon, authenticated;
revoke execute on function duc_dc_nhac() from public, anon, authenticated;
revoke execute on function duc_dc_quyen() from public, anon;
revoke execute on function duc_dc_cai_them(text, int, int, text) from public, anon;
revoke execute on function duc_dc_cai_sua(text, int, text) from public, anon;
revoke execute on function duc_dc_lap(text, text, text) from public, anon;
revoke execute on function duc_dc_thao(text, text) from public, anon;
revoke execute on function duc_dc_hong(text, text) from public, anon;
grant execute on function duc_dc_so_shot(text, timestamptz, timestamptz) to authenticated;
grant execute on function duc_dc_quyen() to authenticated;
grant execute on function duc_dc_cai_them(text, int, int, text) to authenticated;
grant execute on function duc_dc_cai_sua(text, int, text) to authenticated;
grant execute on function duc_dc_lap(text, text, text) to authenticated;
grant execute on function duc_dc_thao(text, text) to authenticated;
grant execute on function duc_dc_hong(text, text) to authenticated;
revoke execute on function duc_dk_len_khuon(text, text) from public, anon;
revoke execute on function duc_dk_xac_nhan_luu(text, text, jsonb, jsonb, text) from public, anon;
grant execute on function duc_dk_len_khuon(text, text) to authenticated;
grant execute on function duc_dk_xac_nhan_luu(text, text, jsonb, jsonb, text) to authenticated;

-- ── Cron ────────────────────────────────────────────────────────────────────
select cron.unschedule('duc_dc_nhac') where exists (select 1 from cron.job where jobname = 'duc_dc_nhac');
select cron.schedule('duc_dc_nhac', '3-59/10 * * * *', 'select public.duc_dc_nhac()');
