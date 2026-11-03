-- ============================================================================
-- T207 — Bảng điều khiển Gia công (gia-cong-dashboard.html), phương án B user
-- chốt 03/11/2026. Danh mục máy: T206 (master_machines bo_phan 'Gia công - Sơn',
-- loai_may / so_truc / ma_sp_dung).
--
-- Quyết định của user:
--   * Sản lượng = quét QR tem chuyển từ công đoạn trước, trừ NG và hàng test
--     (giống Bavia). Quét lúc BẮT ĐẦU làm thùng (thùng "đang làm" của máy), NG /
--     test khai trừ thẳng vào tem đó, làm xong bấm "Xong" → SL ra = số còn trên
--     tem. Thùng dở cuối ca: ca sau làm tiếp.
--   * Mã đi qua nhiều máy (vd phay → tiện → chuốt): quét ở MỖI máy, mỗi máy có
--     sản lượng máy riêng (gc_tem_buoc.sl_ra); sản lượng công đoạn Gia Công
--     (cd_tram_hien_tai.so_luong_ok → báo cáo ca) CHỈ cộng ở bước cuối. Thứ tự
--     bước lấy từ master_cnc_routing (trang Năng lực CNC); mã chưa khai = 1 bước.
--   * Không in tem mới: tem nhận vào đi tiếp với SL đã trừ NG/test.
--   * Dừng máy giống Đúc (bộ mã Đúc, A2/C3/E1 đổi nghĩa cho CNC): lý do, giờ
--     phát sinh / trở lại, số phút dừng, vấn đề, nội dung xử lý, ai xử lý.
--   * 1 nhân viên đứng được nhiều máy cùng lúc (không ràng buộc).
--
-- Tem nhận được khi đang ở 1 công đoạn ĐỨNG TRƯỚC Gia Công trong lưu trình mã
-- (hoặc đã ở Gia Công) → tự ghi chuyển công đoạn X → Gia Công (như Bavia tự
-- nhận Đúc → Bavia; không chờ xác nhận — T202). Lý do: 03/11 Bavia chưa ghi
-- nhận các mã gia công trên hệ thống nên tem tới Gia công phần lớn là tem Đúc.
--
-- Chỉ trừ duc_tem.so_luong (số còn lại), KHÔNG đổi so_luong_tt → sản lượng Đúc
-- không bị ảnh hưởng (giống Bavia T145).
-- Mọi tài khoản đăng nhập thao tác được (giống Bavia); mở lại ca chỉ admin.
-- An toàn chạy lại (idempotent).
-- Trạng thái: Đã chạy STAGING + PROD 03/11/2026 (4 phần t207a..t207d; gc_khung_ca chạy ở phần a).
-- ============================================================================

-- ── Quy trình CNC: thêm loại máy Chuốt ─────────────────────────────────────
alter table public.master_cnc_routing drop constraint if exists master_cnc_routing_loai_may_check;
alter table public.master_cnc_routing add constraint master_cnc_routing_loai_may_check
  check (loai_may in ('phay_3_truc', 'phay_4_truc', 'tien', 'chuot'));
alter table public.cnc_capacity_config add column if not exists so_may_chuot numeric not null default 1;

-- ── Thùng (tem) làm ở từng máy, từng bước ───────────────────────────────────
create table if not exists public.gc_tem_buoc (
  id           bigserial primary key,
  tag_no       text not null,
  ma_sp        text not null,
  ma_may       text not null,
  loai_may     text,                       -- phay_3_truc / phay_4_truc / tien / chuot
  buoc         int not null default 1,
  tong_buoc    int not null default 1,
  id_tram      text not null,              -- máy-ca lúc quét
  id_tram_xong text,                       -- máy-ca lúc bấm Xong (thùng dở qua ca)
  sl_vao       numeric not null,
  sl_ra        numeric,
  bat_dau      timestamptz not null default now(),
  xong_luc     timestamptz,
  nguoi_quet   text,
  nguoi_xong   text,
  nguoi_lam    text,                       -- người đứng máy lúc Xong
  bo_luc       timestamptz,                -- quét nhầm → Bỏ
  bo_boi       text
);
create unique index if not exists ux_gc_tem_buoc_dang_lam on public.gc_tem_buoc (tag_no) where xong_luc is null and bo_luc is null;
create index if not exists idx_gc_tem_buoc_may on public.gc_tem_buoc (ma_may) where xong_luc is null and bo_luc is null;
create index if not exists idx_gc_tem_buoc_tag on public.gc_tem_buoc (tag_no);
create index if not exists idx_gc_tem_buoc_tram on public.gc_tem_buoc (id_tram);
create index if not exists idx_gc_tem_buoc_tram_xong on public.gc_tem_buoc (id_tram_xong);

-- ── Hàng test ───────────────────────────────────────────────────────────────
create table if not exists public.gc_hang_test (
  id             bigserial primary key,
  id_buoc        bigint not null references public.gc_tem_buoc (id),
  id_tram        text not null,
  ma_may         text not null,
  ngay           date not null,
  ca             text not null,
  tag_no         text not null,
  ma_sp          text not null,
  so_luong       numeric not null check (so_luong > 0),
  muc_dich       text not null,
  noi_dung       text not null,
  nguoi_test     text not null,
  nguoi_ghi      text,
  thoi_diem      timestamptz not null default now(),
  ket_thuc_luc   timestamptz,
  sl_tra_lai     numeric,
  nguoi_ket_thuc text
);
create index if not exists idx_gc_hang_test_tram on public.gc_hang_test (id_tram);
create index if not exists idx_gc_hang_test_dang on public.gc_hang_test (ma_may) where ket_thuc_luc is null;

-- NG gia công ghi chung cd_ng_khai_bao (cong_doan 'Gia Công'); thêm id_buoc để biết NG ở bước/máy nào.
alter table public.cd_ng_khai_bao add column if not exists id_buoc bigint;

-- ── Dừng máy ────────────────────────────────────────────────────────────────
create table if not exists public.gc_su_co (
  id              bigserial primary key,
  ma_may          text not null,
  id_tram         text,
  ngay            date not null,
  ca              text not null,
  ma_sp           text,
  loai_su_co      text not null,           -- 'A1 — Sự cố máy CNC' ...
  bo_phan_xu_ly   text,
  gio_phat_sinh   timestamptz not null,
  gio_tro_lai     timestamptz,
  phut_dung       numeric,
  van_de          text not null,
  noi_dung_xu_ly  text,
  dam_nhiem       text,                    -- ai xử lý
  nguoi_bao       text,
  nguoi_dong      text,
  thoi_diem_luu   timestamptz not null default now(),
  huy_luc         timestamptz,
  huy_boi         text
);
create unique index if not exists ux_gc_su_co_mo on public.gc_su_co (ma_may) where gio_tro_lai is null and huy_luc is null;
create index if not exists idx_gc_su_co_ngay on public.gc_su_co (gio_phat_sinh);

-- ── Ca đã kết ───────────────────────────────────────────────────────────────
create table if not exists public.gc_ket_ca (
  ngay      date not null,
  ca        text not null,
  ket_luc   timestamptz not null default now(),
  nguoi     text,
  nguoi_uid uuid,
  ly_do     jsonb not null default '{}'::jsonb,   -- {ma_may: lý do chưa đạt KH}
  primary key (ngay, ca)
);
create table if not exists public.gc_ket_ca_nhat_ky (
  id        bigserial primary key,
  ngay      date not null,
  ca        text not null,
  hanh_dong text not null,                        -- ket_ca / mo_lai
  ly_do     text,
  nguoi     text,
  luc       timestamptz not null default now()
);

do $$
declare t text;
begin
  foreach t in array array['gc_tem_buoc', 'gc_hang_test', 'gc_su_co', 'gc_ket_ca', 'gc_ket_ca_nhat_ky'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_doc', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_doc', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke insert, update, delete on public.%I from authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- ── Nội bộ: loại máy (khoá routing) của 1 máy ──────────────────────────────
create or replace function public.gc_loai_may(p_ma_may text)
returns text
language sql stable security definer set search_path = public
as $$
  select case
    when m.loai_may = 'Phay CNC' and coalesce(m.so_truc, 3) >= 4 then 'phay_4_truc'
    when m.loai_may = 'Phay CNC' then 'phay_3_truc'
    when m.loai_may = 'Tiện CNC' then 'tien'
    when m.loai_may = 'Chuốt' then 'chuot'
  end
  from master_machines m where m.ma_may = p_ma_may;
$$;
revoke execute on function public.gc_loai_may(text) from public, anon, authenticated;

create or replace function public.gc_ten_loai_may(p text)
returns text
language sql immutable set search_path = public
as $$
  select case p when 'phay_3_truc' then 'Phay 3 trục' when 'phay_4_truc' then 'Phay 4 trục'
                when 'tien' then 'Tiện' when 'chuot' then 'Chuốt' else coalesce(p, '?') end;
$$;
revoke execute on function public.gc_ten_loai_may(text) from public, anon, authenticated;

-- ── Nội bộ: chặn ghi vào ca đã kết ─────────────────────────────────────────
create or replace function public.gc_ca_da_ket(p_ngay date, p_ca text)
returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from gc_ket_ca where ngay = p_ngay and ca = p_ca); $$;
revoke execute on function public.gc_ca_da_ket(date, text) from public, anon, authenticated;

-- ── Mở / sửa máy trong ca (mã SP, KH ca, người đứng máy) ───────────────────
create or replace function public.gc_may_luu(
  p_ngay date, p_ca text, p_ma_may text, p_ma_sp text, p_kh_ca numeric, p_nguoi text
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  m master_machines%rowtype;
  p master_products%rowtype;
  v_id text;
  v_do record;
  v_user text := duc_su_co_nguoi_hien_tai();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if p_ngay is null or coalesce(p_ca, '') not in ('Ca ngày', 'Ca đêm', 'Ca 1', 'Ca 2') then
    return jsonb_build_object('ok', false, 'error', 'Ngày / ca không hợp lệ');
  end if;
  if gc_ca_da_ket(p_ngay, p_ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không sửa máy được');
  end if;
  select * into m from master_machines where ma_may = p_ma_may and bo_phan = 'Gia công - Sơn';
  if not found then return jsonb_build_object('ok', false, 'error', coalesce(p_ma_may, '?') || ' không có trong danh mục máy Gia công'); end if;
  select * into p from master_products where ma_sp = trim(coalesce(p_ma_sp, ''));
  if not found then return jsonb_build_object('ok', false, 'error', 'Mã SP ' || coalesce(p_ma_sp, '') || ' không có trong Danh mục SP'); end if;
  if coalesce(p.quy_trinh_cong_doan, '') !~ 'Gia Công' then
    return jsonb_build_object('ok', false, 'error', 'Lưu trình mã ' || p.ma_sp || ' không có công đoạn Gia Công (Danh mục SP)');
  end if;
  if not (p.ma_sp = any(coalesce(m.ma_sp_dung, '{}'))) then
    return jsonb_build_object('ok', false, 'error', m.ma_may || ' chưa khai làm được mã ' || p.ma_sp
      || '. Admin bổ sung ở Quản lý danh mục → Máy-Line → cột "Dùng cho mã SP".');
  end if;
  if coalesce(p_kh_ca, 0) < 0 then return jsonb_build_object('ok', false, 'error', 'KH ca không hợp lệ'); end if;

  -- Máy còn thùng đang làm của mã khác thì không đổi mã
  select b.ma_sp, count(*) n into v_do from gc_tem_buoc b
  where b.ma_may = m.ma_may and b.xong_luc is null and b.bo_luc is null and b.ma_sp <> p.ma_sp
  group by b.ma_sp limit 1;
  if found then
    return jsonb_build_object('ok', false, 'error', m.ma_may || ' còn ' || v_do.n || ' thùng mã ' || v_do.ma_sp
      || ' đang làm. Bấm Xong hoặc Bỏ các thùng đó trước khi đổi mã.');
  end if;

  v_id := duc_normalize_name('Gia Công') || '_' || to_char(p_ngay, 'DDMMYYYY') || '_'
          || duc_normalize_name(p_ca) || '_' || duc_normalize_name(m.ma_may);
  insert into cd_tram_hien_tai (id_tram, ngay, ca, cong_doan, ten_tram, ma_sp, ten_sp, kh_ca, nguoi_thao_tac,
    so_luong_ok, so_luong_ng, version, last_updated_by, last_updated_at)
  values (v_id, p_ngay, p_ca, 'Gia Công', m.ma_may, p.ma_sp, coalesce(p.ten_sp, ''), nullif(p_kh_ca, 0),
    trim(coalesce(p_nguoi, '')), 0, 0, 1, v_user, now())
  on conflict (id_tram) do update set
    ma_sp = excluded.ma_sp, ten_sp = excluded.ten_sp, kh_ca = excluded.kh_ca, nguoi_thao_tac = excluded.nguoi_thao_tac,
    version = cd_tram_hien_tai.version + 1, last_updated_by = v_user, last_updated_at = now();
  return jsonb_build_object('ok', true, 'id_tram', v_id);
end $$;
revoke execute on function public.gc_may_luu(date, text, text, text, numeric, text) from public, anon;
grant execute on function public.gc_may_luu(date, text, text, text, numeric, text) to authenticated;

-- ── Quét tem ở máy: bắt đầu làm thùng ──────────────────────────────────────
create or replace function public.gc_quet(p_id_tram text, p_tag text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_tram cd_tram_hien_tai%rowtype;
  v_tem duc_tem%rowtype;
  v_tag text := upper(trim(coalesce(p_tag, '')));
  v_steps text[];
  v_i int;
  v_j int;
  v_loc text;
  v_loai text;
  v_route record;
  v_tong int;
  v_buoc int;
  v_khac record;
  v_xong record;
  v_line_bavia text;
  v_id bigint;
  v_user text := duc_su_co_nguoi_hien_tai();
  v_now timestamptz := now();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if v_tag = '' then return jsonb_build_object('ok', false, 'error', 'Chưa có mã quét'); end if;
  select * into v_tram from cd_tram_hien_tai where id_tram = p_id_tram and cong_doan = 'Gia Công';
  if not found then return jsonb_build_object('ok', false, 'error', 'Máy chưa được mở trong ca này'); end if;
  if gc_ca_da_ket(v_tram.ngay, v_tram.ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không ghi thêm được');
  end if;

  select * into v_tem from duc_tem where tag_no = v_tag for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || v_tag); end if;
  if v_tem.ma_sp is distinct from v_tram.ma_sp then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' là mã ' || coalesce(v_tem.ma_sp, '?')
      || ', ' || v_tram.ten_tram || ' đang chạy mã ' || v_tram.ma_sp);
  end if;
  if duc_tem_id_ncp_cach_ly(v_tem.tag_no) is not null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang bị cách ly theo phiếu NCP '
      || duc_tem_id_ncp_cach_ly(v_tem.tag_no) || '. Báo QC.');
  end if;
  if coalesce(v_tem.trang_thai, '') in ('Chờ sản xuất', 'NG chờ sửa', 'Chờ đóng gói TP') then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang ở trạng thái "' || v_tem.trang_thai
      || '", chưa dùng cho Gia công được');
  end if;
  if coalesce(v_tem.so_luong, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' không còn số lượng (đã dùng hết / NG hết)');
  end if;
  select ten_line into v_line_bavia from bavia_line_nguon where tag_no = v_tem.tag_no and bo_luc is null;
  if v_line_bavia is not null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang khai báo nguồn ở Bavia ' || v_line_bavia
      || '. Bavia bấm Bỏ trước.');
  end if;

  -- Đang làm ở máy khác / đã quét ở máy này
  select ma_may into v_khac from gc_tem_buoc where tag_no = v_tem.tag_no and xong_luc is null and bo_luc is null;
  if found then
    if v_khac.ma_may = v_tram.ten_tram then
      return jsonb_build_object('ok', false, 'trung', true, 'error', 'Tem ' || v_tem.tag_no || ' đã quét ở ' || v_khac.ma_may);
    end if;
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang làm ở ' || v_khac.ma_may
      || '. Bấm Xong hoặc Bỏ ở ' || v_khac.ma_may || ' trước.');
  end if;

  -- Bước tiếp theo theo quy trình CNC
  v_loai := gc_loai_may(v_tram.ten_tram);
  select count(*) into v_tong from master_cnc_routing where ma_sp = v_tram.ma_sp;
  v_tong := greatest(v_tong, 1);
  select max(buoc) mb, max(xong_luc) xl, (array_agg(ma_may order by xong_luc desc))[1] mm into v_xong
  from gc_tem_buoc where tag_no = v_tem.tag_no and bo_luc is null and xong_luc is not null;
  v_buoc := coalesce(v_xong.mb, 0) + 1;
  if v_buoc > v_tong then
    return jsonb_build_object('ok', false, 'error', 'Thùng ' || v_tem.tag_no || ' đã gia công xong (' || v_tong || '/' || v_tong
      || ' bước, lần cuối ở ' || coalesce(v_xong.mm, '?') || ' lúc '
      || coalesce(to_char(v_xong.xl at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'), '?') || ')');
  end if;
  select * into v_route from master_cnc_routing where ma_sp = v_tram.ma_sp order by buoc offset v_buoc - 1 limit 1;
  if found and not (v_route.loai_may = v_loai or (v_route.loai_may = 'phay_3_truc' and v_loai = 'phay_4_truc')) then
    return jsonb_build_object('ok', false, 'error', 'Thùng ' || v_tem.tag_no || ' đang chờ bước ' || v_buoc || '/' || v_tong
      || ': ' || gc_ten_loai_may(v_route.loai_may) || '. ' || v_tram.ten_tram || ' là máy ' || gc_ten_loai_may(v_loai) || '.');
  end if;

  -- Vị trí tem: phải ở công đoạn đứng trước Gia Công (tự nhận) hoặc đã ở Gia Công
  select array_agg(trim(s) order by ord) into v_steps
  from unnest(string_to_array(coalesce((select quy_trinh_cong_doan from master_products where ma_sp = v_tem.ma_sp), ''), ','))
       with ordinality as u(s, ord)
  where trim(s) <> '';
  v_i := array_position(v_steps, 'Gia Công');
  select cong_doan_nhan into v_loc from cd_chuyen_cong_doan_log
  where tag_no = v_tem.tag_no and coalesce(trang_thai_xac_nhan, '') <> 'Đã từ chối'
  order by thoi_gian_chuyen desc limit 1;
  v_loc := coalesce(v_loc, case when v_tem.tag_no like 'TP%' then coalesce(nullif(v_tem.tram_cong_doan, ''), 'Đúc') else 'Đúc' end);
  v_j := array_position(v_steps, v_loc);
  if v_loc <> 'Gia Công' then
    if v_i is null or v_j is null or v_j >= v_i then
      return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đang ở công đoạn ' || v_loc
        || ', không phải công đoạn trước Gia Công theo lưu trình (' || array_to_string(v_steps, ' → ') || ')');
    end if;
    insert into cd_chuyen_cong_doan_log (id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen,
      chenh_lech, lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan,
      nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan, ghi_chu)
    values (cd_next_transfer_id(), v_now, v_tem.tag_no, v_tem.ma_sp, v_tem.ten_sp, v_tem.so_luong, v_tem.so_luong, 0,
      coalesce(v_tem.lot, ''), coalesce(v_tem.so_khuon_tt, v_tem.so_khuon, ''), coalesce(v_tem.nguyen_lieu, ''),
      coalesce(v_tem.may_tt, v_tem.may_duc_chi_thi, ''), coalesce(v_tem.ngay::text, ''), v_loc, 'Gia Công',
      'Tự nhận tại ' || v_tram.ten_tram, v_user, 'Đã xác nhận chuyển công đoạn',
      to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI:SS DD/MM/YYYY'),
      'Quét tem ở Bảng điều khiển Gia công');
  end if;

  insert into gc_tem_buoc (tag_no, ma_sp, ma_may, loai_may, buoc, tong_buoc, id_tram, sl_vao, nguoi_quet)
  values (v_tem.tag_no, v_tem.ma_sp, v_tram.ten_tram, v_loai, v_buoc, v_tong, v_tram.id_tram, v_tem.so_luong, v_user)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'tag_no', v_tem.tag_no, 'so_luong', v_tem.so_luong,
    'buoc', v_buoc, 'tong_buoc', v_tong, 'tu_nhan', v_loc <> 'Gia Công', 'tu_cong_doan', v_loc);
end $$;
revoke execute on function public.gc_quet(text, text) from public, anon;
grant execute on function public.gc_quet(text, text) to authenticated;

-- ── Nội bộ: lấy thùng đang làm + máy-ca đang chọn, kiểm tra hợp lệ ─────────
create or replace function public.gc_kiem_buoc(p_id_tram text, p_id_buoc bigint)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_tram cd_tram_hien_tai%rowtype;
  b gc_tem_buoc%rowtype;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into v_tram from cd_tram_hien_tai where id_tram = p_id_tram and cong_doan = 'Gia Công';
  if not found then return jsonb_build_object('ok', false, 'error', 'Máy chưa được mở trong ca này'); end if;
  if gc_ca_da_ket(v_tram.ngay, v_tram.ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không ghi thêm được');
  end if;
  select * into b from gc_tem_buoc where id = p_id_buoc;
  if not found or b.bo_luc is not null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy thùng đang làm'); end if;
  if b.xong_luc is not null then return jsonb_build_object('ok', false, 'error', 'Thùng ' || b.tag_no || ' đã bấm Xong'); end if;
  if b.ma_may <> v_tram.ten_tram then
    return jsonb_build_object('ok', false, 'error', 'Thùng ' || b.tag_no || ' đang làm ở ' || b.ma_may || ', không phải ' || v_tram.ten_tram);
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.gc_kiem_buoc(text, bigint) from public, anon, authenticated;

-- ── NG (nhiều dòng 1 lần) ───────────────────────────────────────────────────
create or replace function public.gc_ng_nhieu(p_id_tram text, p_id_buoc bigint, p_ds jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_chk jsonb;
  b gc_tem_buoc%rowtype;
  v_tem duc_tem%rowtype;
  r jsonb;
  n int := 0;
  v_sl numeric;
  v_tong numeric := 0;
  v_user text := duc_su_co_nguoi_hien_tai();
begin
  v_chk := gc_kiem_buoc(p_id_tram, p_id_buoc);
  if not (v_chk->>'ok')::boolean then return v_chk; end if;
  if jsonb_typeof(p_ds) <> 'array' or jsonb_array_length(p_ds) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Nhập ít nhất 1 dòng NG');
  end if;
  select * into b from gc_tem_buoc where id = p_id_buoc;
  select * into v_tem from duc_tem where tag_no = b.tag_no for update;
  for r in select * from jsonb_array_elements(p_ds) loop
    n := n + 1;
    if coalesce(trim(r->>'loai'), '') = '' then
      return jsonb_build_object('ok', false, 'error', 'Dòng ' || n || ': chọn tên lỗi NG');
    end if;
    if trim(r->>'loai') = 'Khác' and length(trim(coalesce(r->>'ghi_chu', ''))) < 3 then
      return jsonb_build_object('ok', false, 'error', 'Dòng ' || n || ': lỗi "Khác" phải ghi rõ nguyên nhân');
    end if;
    if coalesce(r->>'so_luong', '') !~ '^\d+$' or (r->>'so_luong')::numeric <= 0 then
      return jsonb_build_object('ok', false, 'error', 'Dòng ' || n || ': số lượng NG phải là số nguyên lớn hơn 0');
    end if;
    v_tong := v_tong + (r->>'so_luong')::numeric;
  end loop;
  if v_tong > coalesce(v_tem.so_luong, 0) then
    return jsonb_build_object('ok', false, 'error', 'Tổng NG ' || v_tong || ' vượt số còn trên tem (' || coalesce(v_tem.so_luong, 0) || ' pcs)');
  end if;

  for r in select * from jsonb_array_elements(p_ds) loop
    v_sl := (r->>'so_luong')::numeric;
    insert into cd_ng_khai_bao (tag_no, ma_sp, ten_sp, cong_doan, loai_ng, so_luong, nguoi, id_tram, ghi_chu, id_buoc)
    values (v_tem.tag_no, v_tem.ma_sp, v_tem.ten_sp, 'Gia Công', trim(r->>'loai'), v_sl, v_user, p_id_tram,
      nullif(trim(coalesce(r->>'ghi_chu', '')), ''), p_id_buoc);
  end loop;
  update duc_tem set so_luong = so_luong - v_tong where tag_no = v_tem.tag_no;
  perform cd_tram_nhap_sanluong(p_id_tram, 0, v_tong, null, v_user);
  return jsonb_build_object('ok', true, 'so_dong', n, 'tong', v_tong, 'so_luong_con_lai', v_tem.so_luong - v_tong);
end $$;
revoke execute on function public.gc_ng_nhieu(text, bigint, jsonb) from public, anon;
grant execute on function public.gc_ng_nhieu(text, bigint, jsonb) to authenticated;

-- ── Hàng test: lấy ra / kết thúc (trả lại cộng về tem) ──────────────────────
create or replace function public.gc_test_lay(
  p_id_tram text, p_id_buoc bigint, p_sl numeric, p_muc_dich text, p_noi_dung text, p_nguoi_test text
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_chk jsonb;
  v_tram cd_tram_hien_tai%rowtype;
  b gc_tem_buoc%rowtype;
  v_tem duc_tem%rowtype;
  v_id bigint;
begin
  v_chk := gc_kiem_buoc(p_id_tram, p_id_buoc);
  if not (v_chk->>'ok')::boolean then return v_chk; end if;
  if coalesce(trim(p_muc_dich), '') = '' then return jsonb_build_object('ok', false, 'error', 'Chọn mục đích test'); end if;
  if length(trim(coalesce(p_noi_dung, ''))) < 3 then
    return jsonb_build_object('ok', false, 'error', 'Ghi rõ nội dung test (ít nhất 3 ký tự)');
  end if;
  if coalesce(trim(p_nguoi_test), '') = '' then return jsonb_build_object('ok', false, 'error', 'Chọn người test'); end if;
  if coalesce(p_sl, 0) <= 0 or p_sl <> trunc(p_sl) then
    return jsonb_build_object('ok', false, 'error', 'Số lượng test phải là số nguyên lớn hơn 0');
  end if;
  select * into v_tram from cd_tram_hien_tai where id_tram = p_id_tram;
  select * into b from gc_tem_buoc where id = p_id_buoc;
  select * into v_tem from duc_tem where tag_no = b.tag_no for update;
  if p_sl > coalesce(v_tem.so_luong, 0) then
    return jsonb_build_object('ok', false, 'error', 'Số test vượt số còn trên tem (' || coalesce(v_tem.so_luong, 0) || ' pcs)');
  end if;
  update duc_tem set so_luong = so_luong - p_sl where tag_no = b.tag_no;
  insert into gc_hang_test (id_buoc, id_tram, ma_may, ngay, ca, tag_no, ma_sp, so_luong, muc_dich, noi_dung, nguoi_test, nguoi_ghi)
  values (p_id_buoc, p_id_tram, v_tram.ten_tram, v_tram.ngay, v_tram.ca, b.tag_no, b.ma_sp, p_sl, trim(p_muc_dich),
    trim(p_noi_dung), trim(p_nguoi_test), duc_su_co_nguoi_hien_tai())
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'so_luong_con_lai', v_tem.so_luong - p_sl);
end $$;
revoke execute on function public.gc_test_lay(text, bigint, numeric, text, text, text) from public, anon;
grant execute on function public.gc_test_lay(text, bigint, numeric, text, text, text) to authenticated;

create or replace function public.gc_test_ket_thuc(p_id bigint, p_sl_tra_lai numeric)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v gc_hang_test%rowtype;
  v_dang_lam boolean;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into v from gc_hang_test where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy lần test'); end if;
  if v.ket_thuc_luc is not null then return jsonb_build_object('ok', false, 'error', 'Lần test này đã kết thúc'); end if;
  if p_sl_tra_lai is null or p_sl_tra_lai < 0 or p_sl_tra_lai > v.so_luong or p_sl_tra_lai <> trunc(p_sl_tra_lai) then
    return jsonb_build_object('ok', false, 'error', 'Số trả lại phải từ 0 đến ' || v.so_luong);
  end if;
  -- Trả lại chỉ khi thùng còn đang làm (chưa bấm Xong) — đã Xong thì phần trả lại không vào SL ra được
  select exists (select 1 from gc_tem_buoc where id = v.id_buoc and xong_luc is null and bo_luc is null) into v_dang_lam;
  if p_sl_tra_lai > 0 and not v_dang_lam then
    return jsonb_build_object('ok', false, 'error', 'Thùng ' || v.tag_no || ' đã bấm Xong. Chỉ kết thúc với số trả lại = 0 (hàng test huỷ).');
  end if;
  if p_sl_tra_lai > 0 then
    update duc_tem set so_luong = so_luong + p_sl_tra_lai where tag_no = v.tag_no;
  end if;
  update gc_hang_test set ket_thuc_luc = now(), sl_tra_lai = p_sl_tra_lai, nguoi_ket_thuc = duc_su_co_nguoi_hien_tai()
  where id = p_id;
  return jsonb_build_object('ok', true, 'tra_lai', p_sl_tra_lai, 'huy', v.so_luong - p_sl_tra_lai);
end $$;
revoke execute on function public.gc_test_ket_thuc(bigint, numeric) from public, anon;
grant execute on function public.gc_test_ket_thuc(bigint, numeric) to authenticated;

-- ── Xong thùng ──────────────────────────────────────────────────────────────
create or replace function public.gc_xong(p_id_tram text, p_id_buoc bigint)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_chk jsonb;
  v_tram cd_tram_hien_tai%rowtype;
  b gc_tem_buoc%rowtype;
  v_sl numeric;
  v_user text := duc_su_co_nguoi_hien_tai();
begin
  v_chk := gc_kiem_buoc(p_id_tram, p_id_buoc);
  if not (v_chk->>'ok')::boolean then return v_chk; end if;
  select * into v_tram from cd_tram_hien_tai where id_tram = p_id_tram for update;
  if coalesce(v_tram.nguoi_thao_tac, '') = '' then
    return jsonb_build_object('ok', false, 'error', v_tram.ten_tram || ' chưa gán người đứng máy. Bấm "Sửa máy" để chọn.');
  end if;
  if exists (select 1 from gc_hang_test where id_buoc = p_id_buoc and ket_thuc_luc is null) then
    return jsonb_build_object('ok', false, 'error', 'Thùng còn hàng test chưa kết thúc. Kết thúc test (nhập số trả lại) trước khi bấm Xong.');
  end if;
  select * into b from gc_tem_buoc where id = p_id_buoc for update;
  select coalesce(so_luong, 0) into v_sl from duc_tem where tag_no = b.tag_no for update;
  update gc_tem_buoc set xong_luc = now(), sl_ra = v_sl, id_tram_xong = p_id_tram, nguoi_xong = v_user,
    nguoi_lam = v_tram.nguoi_thao_tac
  where id = p_id_buoc;
  -- Sản lượng công đoạn chỉ cộng ở bước cuối
  if b.buoc >= b.tong_buoc and v_sl > 0 then
    perform cd_tram_nhap_sanluong(p_id_tram, v_sl, 0, null, v_user);
  end if;
  return jsonb_build_object('ok', true, 'tag_no', b.tag_no, 'sl_ra', v_sl, 'buoc', b.buoc, 'tong_buoc', b.tong_buoc,
    'buoc_cuoi', b.buoc >= b.tong_buoc);
end $$;
revoke execute on function public.gc_xong(text, bigint) from public, anon;
grant execute on function public.gc_xong(text, bigint) to authenticated;

-- ── Huỷ "Xong" (bấm nhầm) — chỉ bước mới nhất của thùng, ca chưa kết ──────
create or replace function public.gc_xong_huy(p_id_buoc bigint)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  b gc_tem_buoc%rowtype;
  v_tram cd_tram_hien_tai%rowtype;
  v_user text := duc_su_co_nguoi_hien_tai();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into b from gc_tem_buoc where id = p_id_buoc for update;
  if not found or b.bo_luc is not null or b.xong_luc is null then
    return jsonb_build_object('ok', false, 'error', 'Thùng này chưa bấm Xong');
  end if;
  if exists (select 1 from gc_tem_buoc where tag_no = b.tag_no and bo_luc is null and id <> b.id and bat_dau > b.bat_dau) then
    return jsonb_build_object('ok', false, 'error', 'Thùng ' || b.tag_no || ' đã sang bước sau, không huỷ Xong được');
  end if;
  if exists (select 1 from gc_tem_buoc where tag_no = b.tag_no and xong_luc is null and bo_luc is null) then
    return jsonb_build_object('ok', false, 'error', 'Thùng ' || b.tag_no || ' đang làm ở máy khác');
  end if;
  select * into v_tram from cd_tram_hien_tai where id_tram = b.id_tram_xong for update;
  if found and gc_ca_da_ket(v_tram.ngay, v_tram.ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca bấm Xong đã kết ca, không huỷ được');
  end if;
  if b.buoc >= b.tong_buoc and coalesce(b.sl_ra, 0) > 0 and v_tram.id_tram is not null then
    update cd_tram_hien_tai set so_luong_ok = greatest(0, so_luong_ok - b.sl_ra), version = version + 1,
      last_updated_by = v_user, last_updated_at = now()
    where id_tram = v_tram.id_tram;
  end if;
  update gc_tem_buoc set xong_luc = null, sl_ra = null, id_tram_xong = null, nguoi_xong = null, nguoi_lam = null
  where id = b.id;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.gc_xong_huy(bigint) from public, anon;
grant execute on function public.gc_xong_huy(bigint) to authenticated;

-- ── Bỏ thùng (quét nhầm) — NG/test đã ghi vẫn giữ trên tem ─────────────────
create or replace function public.gc_bo_tem(p_id_buoc bigint)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  b gc_tem_buoc%rowtype;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into b from gc_tem_buoc where id = p_id_buoc for update;
  if not found or b.bo_luc is not null then return jsonb_build_object('ok', false, 'error', 'Thùng này đã được bỏ trước đó'); end if;
  if b.xong_luc is not null then return jsonb_build_object('ok', false, 'error', 'Thùng đã bấm Xong. Dùng "Huỷ Xong" trước.'); end if;
  if exists (select 1 from gc_hang_test where id_buoc = p_id_buoc and ket_thuc_luc is null) then
    return jsonb_build_object('ok', false, 'error', 'Thùng còn hàng test chưa kết thúc');
  end if;
  update gc_tem_buoc set bo_luc = now(), bo_boi = duc_su_co_nguoi_hien_tai() where id = p_id_buoc;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.gc_bo_tem(bigint) from public, anon;
grant execute on function public.gc_bo_tem(bigint) to authenticated;

-- ── Dừng máy: mở / đóng / huỷ ──────────────────────────────────────────────
create or replace function public.gc_su_co_mo(p_id_tram text, p_loai text, p_bo_phan text, p_van_de text, p_gio_phat_sinh timestamptz)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_tram cd_tram_hien_tai%rowtype;
  v_gio timestamptz := coalesce(p_gio_phat_sinh, now());
  v_id bigint;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into v_tram from cd_tram_hien_tai where id_tram = p_id_tram and cong_doan = 'Gia Công';
  if not found then return jsonb_build_object('ok', false, 'error', 'Máy chưa được mở trong ca này'); end if;
  if gc_ca_da_ket(v_tram.ngay, v_tram.ca) then return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca'); end if;
  if coalesce(trim(p_loai), '') = '' then return jsonb_build_object('ok', false, 'error', 'Chọn lý do dừng'); end if;
  if length(trim(coalesce(p_van_de, ''))) < 3 then return jsonb_build_object('ok', false, 'error', 'Ghi rõ vấn đề (ít nhất 3 ký tự)'); end if;
  if v_gio > now() + interval '5 minutes' then return jsonb_build_object('ok', false, 'error', 'Giờ phát sinh không được ở tương lai'); end if;
  if v_gio < now() - interval '24 hours' then return jsonb_build_object('ok', false, 'error', 'Giờ phát sinh quá 24 giờ trước'); end if;
  if exists (select 1 from gc_su_co where ma_may = v_tram.ten_tram and gio_tro_lai is null and huy_luc is null) then
    return jsonb_build_object('ok', false, 'error', v_tram.ten_tram || ' đang có 1 lần dừng chưa đóng');
  end if;
  insert into gc_su_co (ma_may, id_tram, ngay, ca, ma_sp, loai_su_co, bo_phan_xu_ly, gio_phat_sinh, van_de, nguoi_bao)
  values (v_tram.ten_tram, v_tram.id_tram, v_tram.ngay, v_tram.ca, v_tram.ma_sp, trim(p_loai),
    nullif(trim(coalesce(p_bo_phan, '')), ''), v_gio, trim(p_van_de), duc_su_co_nguoi_hien_tai())
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke execute on function public.gc_su_co_mo(text, text, text, text, timestamptz) from public, anon;
grant execute on function public.gc_su_co_mo(text, text, text, text, timestamptz) to authenticated;

create or replace function public.gc_su_co_dong(p_id bigint, p_gio_tro_lai timestamptz, p_noi_dung text, p_dam_nhiem text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v gc_su_co%rowtype;
  v_gio timestamptz := coalesce(p_gio_tro_lai, now());
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into v from gc_su_co where id = p_id for update;
  if not found or v.huy_luc is not null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy lần dừng'); end if;
  if v.gio_tro_lai is not null then return jsonb_build_object('ok', false, 'error', 'Lần dừng này đã đóng'); end if;
  if length(trim(coalesce(p_noi_dung, ''))) < 3 then return jsonb_build_object('ok', false, 'error', 'Ghi nội dung xử lý (ít nhất 3 ký tự)'); end if;
  if coalesce(trim(p_dam_nhiem), '') = '' then return jsonb_build_object('ok', false, 'error', 'Chọn / ghi người xử lý'); end if;
  if v_gio < v.gio_phat_sinh then return jsonb_build_object('ok', false, 'error', 'Giờ chạy lại phải sau giờ dừng'); end if;
  if v_gio > now() + interval '5 minutes' then return jsonb_build_object('ok', false, 'error', 'Giờ chạy lại không được ở tương lai'); end if;
  update gc_su_co set gio_tro_lai = v_gio, phut_dung = round(extract(epoch from (v_gio - v.gio_phat_sinh)) / 60),
    noi_dung_xu_ly = trim(p_noi_dung), dam_nhiem = trim(p_dam_nhiem), nguoi_dong = duc_su_co_nguoi_hien_tai()
  where id = p_id;
  return jsonb_build_object('ok', true, 'phut_dung', round(extract(epoch from (v_gio - v.gio_phat_sinh)) / 60));
end $$;
revoke execute on function public.gc_su_co_dong(bigint, timestamptz, text, text) from public, anon;
grant execute on function public.gc_su_co_dong(bigint, timestamptz, text, text) to authenticated;

create or replace function public.gc_su_co_huy(p_id bigint)
returns jsonb
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  update gc_su_co set huy_luc = now(), huy_boi = duc_su_co_nguoi_hien_tai()
  where id = p_id and huy_luc is null and gio_tro_lai is null;
  if not found then return jsonb_build_object('ok', false, 'error', 'Chỉ huỷ được lần dừng đang mở (báo nhầm)'); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.gc_su_co_huy(bigint) from public, anon;
grant execute on function public.gc_su_co_huy(bigint) to authenticated;

-- ── Khung giờ ca (khớp dashboard Đúc) ──────────────────────────────────────
create or replace function public.gc_khung_ca(p_ngay date, p_ca text, out tu timestamptz, out den timestamptz)
language sql immutable set search_path = public
as $$
  select ((p_ngay + case p_ca when 'Ca đêm' then time '18:00' when 'Ca 2' then time '14:00' else time '06:00' end)::timestamp
           at time zone 'Asia/Ho_Chi_Minh'),
         ((p_ngay + case p_ca when 'Ca ngày' then time '18:00' when 'Ca 1' then time '14:00' when 'Ca 2' then time '22:00' else time '06:00' end
           + case when p_ca = 'Ca đêm' then interval '1 day' else interval '0' end)::timestamp at time zone 'Asia/Ho_Chi_Minh');
$$;
revoke execute on function public.gc_khung_ca(date, text) from public, anon;
grant execute on function public.gc_khung_ca(date, text) to authenticated;

-- ── Dữ liệu 1 lần cho cả màn hình ──────────────────────────────────────────
create or replace function public.gc_du_lieu(p_ngay date, p_ca text)
returns jsonb
language sql stable security definer set search_path = public
as $$
  with kc as (select * from gc_khung_ca(p_ngay, p_ca)),
  trams as (select * from cd_tram_hien_tai where cong_doan = 'Gia Công' and ngay = p_ngay and ca = p_ca),
  tuan as (select p_ngay - (extract(isodow from p_ngay)::int - 1) as t),
  kh as (
    select k.ma_sp, max(k.ten_sp) ten_sp, sum(k.kh_tuan) kh_tuan,
      sum(case extract(isodow from p_ngay)::int
            when 1 then k.t2 when 2 then k.t3 when 3 then k.t4 when 4 then k.t5 when 5 then k.t6 when 6 then k.t7 else k.cn end) kh_ngay
    from cd_khsx_tuan_plan k, tuan
    where k.cong_doan = 'Gia Công' and k.tuan_bat_dau = tuan.t
    group by k.ma_sp
  )
  select jsonb_build_object(
    'khung_ca', (select jsonb_build_object('tu', tu, 'den', den) from kc),
    'ket_ca', (select to_jsonb(k) from gc_ket_ca k where k.ngay = p_ngay and k.ca = p_ca),
    'may', (select coalesce(jsonb_agg(jsonb_build_object(
        'ma_may', m.ma_may, 'loai_may', m.loai_may, 'so_truc', m.so_truc, 'ma_sp_dung', coalesce(m.ma_sp_dung, '{}'),
        'tram', (select to_jsonb(t) from trams t where t.ten_tram = m.ma_may),
        'dang_lam', (select coalesce(jsonb_agg(jsonb_build_object(
              'id', b.id, 'tag_no', b.tag_no, 'ma_sp', b.ma_sp, 'buoc', b.buoc, 'tong_buoc', b.tong_buoc,
              'sl_vao', b.sl_vao, 'con', d.so_luong, 'bat_dau', b.bat_dau, 'id_tram', b.id_tram,
              'lot', d.lot, 'ngay_duc', d.ngay, 'may_duc', coalesce(d.may_tt, d.may_duc_chi_thi),
              'so_khuon', coalesce(d.so_khuon_tt, d.so_khuon),
              'ng', (select coalesce(sum(g.so_luong), 0) from cd_ng_khai_bao g where g.id_buoc = b.id),
              'test', (select coalesce(jsonb_agg(to_jsonb(h) order by h.thoi_diem), '[]'::jsonb) from gc_hang_test h where h.id_buoc = b.id)
            ) order by b.bat_dau, b.id), '[]'::jsonb)
            from gc_tem_buoc b join duc_tem d on d.tag_no = b.tag_no
            where b.ma_may = m.ma_may and b.xong_luc is null and b.bo_luc is null),
        'xong', (select coalesce(jsonb_agg(jsonb_build_object(
              'id', b.id, 'tag_no', b.tag_no, 'ma_sp', b.ma_sp, 'buoc', b.buoc, 'tong_buoc', b.tong_buoc,
              'sl_vao', b.sl_vao, 'sl_ra', b.sl_ra, 'bat_dau', b.bat_dau, 'xong_luc', b.xong_luc, 'nguoi_lam', b.nguoi_lam,
              'ng', (select coalesce(sum(g.so_luong), 0) from cd_ng_khai_bao g where g.id_buoc = b.id),
              'test', (select coalesce(sum(h.so_luong - coalesce(h.sl_tra_lai, 0)), 0) from gc_hang_test h where h.id_buoc = b.id)
            ) order by b.xong_luc desc), '[]'::jsonb)
            from gc_tem_buoc b join trams t on t.id_tram = b.id_tram_xong
            where t.ten_tram = m.ma_may and b.bo_luc is null and b.xong_luc is not null),
        'ng', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'tag_no', g.tag_no, 'loai', g.loai_ng, 'ghi_chu', g.ghi_chu,
              'so_luong', g.so_luong, 'nguoi', g.nguoi, 'ngay_gio', g.ngay_gio) order by g.ngay_gio desc), '[]'::jsonb)
            from cd_ng_khai_bao g join trams t on t.id_tram = g.id_tram where t.ten_tram = m.ma_may and g.cong_doan = 'Gia Công'),
        'test_ca', (select coalesce(sum(h.so_luong - coalesce(h.sl_tra_lai, 0)), 0)
            from gc_hang_test h join trams t on t.id_tram = h.id_tram where t.ten_tram = m.ma_may),
        'su_co', (select coalesce(jsonb_agg(to_jsonb(s) order by s.gio_phat_sinh desc), '[]'::jsonb)
            from gc_su_co s, kc
            where s.ma_may = m.ma_may and s.huy_luc is null
              and s.gio_phat_sinh < kc.den and coalesce(s.gio_tro_lai, 'infinity'::timestamptz) > kc.tu)
      ) order by m.loai_may, m.so_truc desc nulls last, m.ma_may), '[]'::jsonb)
      from master_machines m where m.bo_phan = 'Gia công - Sơn'),
    'tram_ngoai_danh_muc', (select coalesce(jsonb_agg(t.ten_tram), '[]'::jsonb) from trams t
      where not exists (select 1 from master_machines m where m.ma_may = t.ten_tram and m.bo_phan = 'Gia công - Sơn')),
    'kh', (select coalesce(jsonb_agg(jsonb_build_object(
        'ma_sp', kh.ma_sp, 'ten_sp', kh.ten_sp, 'kh_ngay', kh.kh_ngay, 'kh_tuan', kh.kh_tuan,
        'so_may_lam_duoc', (select count(*) from master_machines m where m.bo_phan = 'Gia công - Sơn' and kh.ma_sp = any(coalesce(m.ma_sp_dung, '{}'))),
        'quy_trinh', (select coalesce(jsonb_agg(jsonb_build_object('buoc', r.buoc, 'loai_may', r.loai_may) order by r.buoc), '[]'::jsonb)
                      from master_cnc_routing r where r.ma_sp = kh.ma_sp)
      ) order by kh.ma_sp), '[]'::jsonb) from kh where coalesce(kh.kh_ngay, 0) > 0 or coalesce(kh.kh_tuan, 0) > 0),
    -- Thùng đã làm xong 1 phần quy trình, đang chờ bước sau (không có máy nào đang làm)
    'cho_buoc_sau', (select coalesce(jsonb_agg(jsonb_build_object('tag_no', x.tag_no, 'ma_sp', x.ma_sp, 'buoc_xong', x.buoc,
          'tong_buoc', x.tong_buoc, 'con', x.con, 'may_truoc', x.ma_may, 'xong_luc', x.xong_luc,
          'loai_may_tiep', (select r.loai_may from master_cnc_routing r where r.ma_sp = x.ma_sp order by r.buoc offset x.buoc limit 1))
        order by x.xong_luc), '[]'::jsonb)
      from (
        select distinct on (b.tag_no) b.tag_no, b.ma_sp, b.buoc, b.tong_buoc, b.ma_may, b.xong_luc, d.so_luong con
        from gc_tem_buoc b join duc_tem d on d.tag_no = b.tag_no
        where b.bo_luc is null and b.xong_luc is not null and b.xong_luc > now() - interval '30 days'
        order by b.tag_no, b.xong_luc desc
      ) x
      where x.buoc < x.tong_buoc and coalesce(x.con, 0) > 0
        and not exists (select 1 from gc_tem_buoc o where o.tag_no = x.tag_no and o.xong_luc is null and o.bo_luc is null))
  )
  where auth.uid() is not null;
$$;
revoke execute on function public.gc_du_lieu(date, text) from public, anon;
grant execute on function public.gc_du_lieu(date, text) to authenticated;

-- ── Kết ca: kiểm tra + ghi báo cáo ca (cd_bao_cao_ca) + khoá ───────────────
create or replace function public.gc_ket_ca_luu(p_ngay date, p_ca text, p_ly_do jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  l record;
  v_may numeric;
  v_ok numeric;
  v_test numeric;
  v_thieu text[] := '{}';
  v_user text := duc_su_co_nguoi_hien_tai();
  v_ly text;
  v_note text;
  v_ket_lai boolean;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if gc_ca_da_ket(p_ngay, p_ca) then return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca rồi'); end if;
  if not exists (select 1 from cd_tram_hien_tai where cong_doan = 'Gia Công' and ngay = p_ngay and ca = p_ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này chưa mở máy nào');
  end if;
  if exists (select 1 from gc_hang_test h join cd_tram_hien_tai t on t.id_tram = h.id_tram
             where t.ngay = p_ngay and t.ca = p_ca and t.cong_doan = 'Gia Công' and h.ket_thuc_luc is null) then
    v_thieu := v_thieu || 'Còn hàng test chưa kết thúc'::text;
  end if;
  for l in select * from cd_tram_hien_tai where cong_doan = 'Gia Công' and ngay = p_ngay and ca = p_ca order by ten_tram loop
    if coalesce(l.nguoi_thao_tac, '') = '' then v_thieu := v_thieu || (l.ten_tram || ' chưa gán người đứng máy'); end if;
    select coalesce(sum(sl_ra), 0) into v_may from gc_tem_buoc where id_tram_xong = l.id_tram and bo_luc is null;
    if coalesce(l.kh_ca, 0) > 0 and v_may < 0.9 * l.kh_ca
       and length(trim(coalesce(p_ly_do ->> l.ten_tram, ''))) < 3 then
      v_thieu := v_thieu || (l.ten_tram || ' đạt ' || round(v_may / l.kh_ca * 100) || '% KH, chưa ghi lý do');
    end if;
  end loop;
  if array_length(v_thieu, 1) > 0 then
    return jsonb_build_object('ok', false, 'thieu', to_jsonb(v_thieu), 'error', array_to_string(v_thieu, '; '));
  end if;

  v_ket_lai := exists (select 1 from gc_ket_ca_nhat_ky where ngay = p_ngay and ca = p_ca and hanh_dong = 'ket_ca');
  insert into gc_ket_ca (ngay, ca, nguoi, nguoi_uid, ly_do) values (p_ngay, p_ca, v_user, auth.uid(), coalesce(p_ly_do, '{}'::jsonb));
  insert into gc_ket_ca_nhat_ky (ngay, ca, hanh_dong, nguoi) values (p_ngay, p_ca, 'ket_ca', v_user);
  if v_ket_lai then
    delete from cd_bao_cao_ca b where b.ngay = p_ngay and b.ca = p_ca and b.cong_doan = 'Gia Công'
      and b.to_san_xuat in (select ten_tram from cd_tram_hien_tai where cong_doan = 'Gia Công' and ngay = p_ngay and ca = p_ca);
  end if;
  for l in select * from cd_tram_hien_tai where cong_doan = 'Gia Công' and ngay = p_ngay and ca = p_ca loop
    select coalesce(sum(sl_ra), 0), coalesce(sum(sl_ra) filter (where buoc >= tong_buoc), 0) into v_may, v_ok
    from gc_tem_buoc where id_tram_xong = l.id_tram and bo_luc is null;
    select coalesce(sum(so_luong - coalesce(sl_tra_lai, 0)), 0) into v_test from gc_hang_test where id_tram = l.id_tram;
    v_ly := nullif(trim(coalesce(p_ly_do ->> l.ten_tram, '')), '');
    v_note := concat_ws(' · ', 'KH ' || coalesce(l.kh_ca, 0),
      case when v_may <> v_ok then 'SL máy ' || v_may || ' (gồm bước trung gian)' end,
      case when v_test > 0 then 'Test ' || v_test end,
      case when v_ly is not null then 'Lý do chưa đạt KH: ' || v_ly end);
    if v_may > 0 or coalesce(l.so_luong_ng, 0) > 0 or v_test > 0 or coalesce(l.kh_ca, 0) > 0 then
      perform cd_gop_tally_vao_bao_cao(p_ngay, p_ca, 'Gia Công', l.ma_sp, l.ten_sp, l.ten_tram, v_ok, coalesce(l.so_luong_ng, 0), v_note, 0);
    end if;
  end loop;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.gc_ket_ca_luu(date, text, jsonb) from public, anon;
grant execute on function public.gc_ket_ca_luu(date, text, jsonb) to authenticated;

create or replace function public.gc_mo_lai_ca(p_ngay date, p_ca text, p_ly_do text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if not has_role('admin') then return jsonb_build_object('ok', false, 'error', 'Chỉ admin mở lại ca được'); end if;
  if length(trim(coalesce(p_ly_do, ''))) < 3 then return jsonb_build_object('ok', false, 'error', 'Ghi lý do mở lại'); end if;
  delete from gc_ket_ca where ngay = p_ngay and ca = p_ca;
  if not found then return jsonb_build_object('ok', false, 'error', 'Ca này chưa kết'); end if;
  insert into gc_ket_ca_nhat_ky (ngay, ca, hanh_dong, ly_do, nguoi) values (p_ngay, p_ca, 'mo_lai', trim(p_ly_do), duc_su_co_nguoi_hien_tai());
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.gc_mo_lai_ca(date, text, text) from public, anon;
grant execute on function public.gc_mo_lai_ca(date, text, text) to authenticated;
