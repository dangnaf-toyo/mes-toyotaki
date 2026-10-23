-- ============================================================================
-- T145 — Bảng điều khiển Bavia (đợt 1): gộp Tem xuất hàng Bavia + Bảng điều
-- khiển Bavia + Ghi nhận thùng Bavia thành 1 màn hình bavia-dashboard.html.
-- Thiết kế đã chốt qua bản mẫu https://claude.ai/artifact/TEmCDrLkhQ14jeLwHtAwFV
--
-- Mỗi Line Bavia (master_machines bo_phan 'Bavia') chạy 1 mã tại một thời điểm.
-- Line theo ca vẫn là 1 dòng cd_tram_hien_tai (cong_doan 'Bavia') để báo cáo ca
-- cũ dùng tiếp được; thêm cột nguoi_kiem_tra (trưởng ca khai báo theo Line, in
-- lên tem xuất hàng).
--
-- Dạng tự nhận theo lưu trình mã SP:
--   Dạng 1 — sau Bavia không còn công đoạn sản xuất (OQC / Nhập kho / Xuất hàng
--            / Tem xuất hàng): đủ thùng bấm "Đóng thùng · In tem" → tạo tem TP
--            và in tem xuất hàng theo mẫu khách. Sản lượng tính lúc in tem.
--   Dạng 2 — sau Bavia còn Gia Công / Sơn...: quét tem thùng TP QLSX in sẵn
--            (cd_tao_lo_tem_thanh_pham, trạng thái 'Chờ đóng gói TP').
-- Cả 2 dạng: quét tem Đúc khai báo nguồn đang dùng của Line (bảng
-- bavia_line_nguon, theo Line — KHÔNG dùng duc_tem.thoi_diem_bat_dau_dung của
-- Đánh bóng Kẽm để 2 công đoạn không trừ lẫn nguồn của nhau), thùng trừ nguồn
-- FIFO theo thứ tự khai báo, ghi cd_tem_nguon để truy xuất nguồn gốc.
-- Quét tem Đúc chưa chuyển công đoạn = tự ghi nhận Đúc → Bavia (user chốt
-- 23/10/2026); tem đang ở công đoạn khác thì chặn.
-- NG (24 lỗi A–X, Khác bắt buộc ghi nguyên nhân) và hàng test trừ thẳng vào tem
-- Đúc; kết thúc test trả lại thì cộng về tem Đúc, phần còn lại huỷ.
-- Thùng lẻ cuối ca để lẻ: số còn trên tem Đúc giữ khai báo, ca sau làm tiếp.
--
-- Chỉ trừ duc_tem.so_luong (số còn lại), KHÔNG đổi so_luong_tt của tem Đúc →
-- sản lượng Đúc (duc_tem_sync_actuals / sync_lich_su) không bị ảnh hưởng.
--
-- Trạng thái: Đã chạy STAGING 23/10/2026 (đợt 1; lịch sử migration staging ghi tên t144_*, t144b_*, t144c_* — trước khi đổi số sang T145). Đã chạy PROD 23/10/2026 (tên t145_bang_dieu_khien_bavia, bản cuối gồm mọi sửa đổi).
-- Đợt 2 (T146) bổ sung: bavia_line_luu / bavia_ng / bavia_test_lay chặn ca đã kết (bavia_ket_ca).
-- Mọi tài khoản đăng nhập thao tác được (công nhân Bavia dùng tài khoản chung) — cố ý không has_role.
-- Tên người thao tác / người kiểm tra / người test là dữ liệu trưởng ca chọn (không phải người đăng nhập);
-- người GHI luôn lấy từ user_roles theo auth.uid() (duc_su_co_nguoi_hien_tai).
-- ============================================================================

alter table public.cd_tram_hien_tai add column if not exists nguoi_kiem_tra text;
alter table public.cd_ng_khai_bao add column if not exists id_tram text;
alter table public.cd_ng_khai_bao add column if not exists ghi_chu text;

-- ── Tem Đúc đang dùng của từng Line ─────────────────────────────────────────
create table if not exists public.bavia_line_nguon (
  id          bigserial primary key,
  ten_line    text not null,
  tag_no      text not null,
  ma_sp       text not null,
  sl_khai_bao numeric not null,           -- số còn trên tem lúc khai báo
  thoi_diem   timestamptz not null default now(),
  nguoi       text,
  nguoi_uid   uuid,
  bo_luc      timestamptz,                -- bấm "Bỏ" (quét nhầm / chuyển Line khác)
  bo_boi      text
);
create unique index if not exists ux_bavia_line_nguon_dang_dung on public.bavia_line_nguon (tag_no) where bo_luc is null;
create index if not exists idx_bavia_line_nguon_line on public.bavia_line_nguon (ten_line) where bo_luc is null;

-- ── Thùng Bavia (cả 2 dạng) ─────────────────────────────────────────────────
create table if not exists public.bavia_thung (
  tag_tp      text primary key,
  ten_line    text not null,
  id_tram     text not null,
  ngay        date not null,
  ca          text not null,
  ma_sp       text not null,
  so_luong    numeric not null,
  dang        smallint not null check (dang in (1, 2)),
  nguoi_lam   text,
  nguoi_kiem  text,
  thoi_diem   timestamptz not null default now(),
  nguoi_ghi   text,
  nguoi_uid   uuid
);
create index if not exists idx_bavia_thung_tram on public.bavia_thung (id_tram);

-- ── Hàng test ───────────────────────────────────────────────────────────────
create table if not exists public.bavia_hang_test (
  id             bigserial primary key,
  id_tram        text not null,
  ten_line       text not null,
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
create index if not exists idx_bavia_hang_test_tram on public.bavia_hang_test (id_tram);
create index if not exists idx_bavia_hang_test_dang on public.bavia_hang_test (ten_line) where ket_thuc_luc is null;

-- ── Ca đã kết (đợt 2 ghi; đợt 1 chỉ đọc để chặn ghi thêm vào ca đã kết) ─────
create table if not exists public.bavia_ket_ca (
  ngay      date not null,
  ca        text not null,
  ket_luc   timestamptz not null default now(),
  nguoi     text,
  nguoi_uid uuid,
  ly_do     jsonb not null default '{}'::jsonb,   -- {ten_line: lý do chưa đạt KH}
  primary key (ngay, ca)
);
alter table public.bavia_ket_ca enable row level security;
drop policy if exists bavia_ket_ca_doc on public.bavia_ket_ca;
create policy bavia_ket_ca_doc on public.bavia_ket_ca for select to authenticated using (true);
revoke insert, update, delete on public.bavia_ket_ca from anon, authenticated;
grant select on public.bavia_ket_ca to authenticated;

alter table public.bavia_line_nguon enable row level security;
alter table public.bavia_thung enable row level security;
alter table public.bavia_hang_test enable row level security;
drop policy if exists bavia_line_nguon_doc on public.bavia_line_nguon;
create policy bavia_line_nguon_doc on public.bavia_line_nguon for select to authenticated using (true);
drop policy if exists bavia_thung_doc on public.bavia_thung;
create policy bavia_thung_doc on public.bavia_thung for select to authenticated using (true);
drop policy if exists bavia_hang_test_doc on public.bavia_hang_test;
create policy bavia_hang_test_doc on public.bavia_hang_test for select to authenticated using (true);
revoke insert, update, delete on public.bavia_line_nguon, public.bavia_thung, public.bavia_hang_test from anon, authenticated;
grant select on public.bavia_line_nguon, public.bavia_thung, public.bavia_hang_test to authenticated;

-- ── Thông tin mã SP tại Bavia: dạng, SL/thùng, mẫu tem ─────────────────────
create or replace function public.bavia_thong_tin_ma(p_ma_sp text)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  p master_products%rowtype;
  v_steps text[];
  v_i int;
  v_sau text;
  v_sl numeric;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into p from master_products where ma_sp = trim(p_ma_sp);
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Mã SP ' || coalesce(p_ma_sp, '') || ' không có trong Danh mục SP');
  end if;

  select array_agg(trim(s) order by ord) into v_steps
  from unnest(string_to_array(coalesce(p.quy_trinh_cong_doan, ''), ',')) with ordinality as u(s, ord)
  where trim(s) <> '';
  v_i := array_position(v_steps, 'Bavia');
  if v_i is null then
    return jsonb_build_object('ok', false, 'ma_sp', p.ma_sp,
      'error', 'Lưu trình của mã ' || p.ma_sp || ' không có công đoạn Bavia (Danh mục SP)');
  end if;
  v_sau := v_steps[v_i + 1];

  v_sl := nullif(p.sl_thung_cong_doan ->> 'Bavia', '')::numeric;
  if coalesce(v_sl, 0) <= 0 then
    return jsonb_build_object('ok', false, 'ma_sp', p.ma_sp,
      'error', 'Mã ' || p.ma_sp || ' chưa khai báo SL/thùng công đoạn Bavia (Danh mục SP → SL/thùng theo công đoạn)');
  end if;

  return jsonb_build_object(
    'ok', true, 'ma_sp', p.ma_sp, 'ten_sp', p.ten_sp,
    'ten_khach_hang', p.ten_khach_hang, 'ma_sp_khach_hang', p.ma_sp_khach_hang, 'nguyen_lieu', p.nguyen_lieu,
    'sl_thung', v_sl, 'buoc_sau', v_sau, 'quy_trinh', to_jsonb(v_steps),
    'dang', case when v_sau is null or v_sau in ('OQC', 'Nhập kho', 'Xuất hàng', 'Xuất kho', 'Tem xuất hàng') then 1 else 2 end,
    'mau', case when p.ten_khach_hang ~* 'FCC' then 'fcc' when p.ten_khach_hang ~* 'ASTEMO' then 'astemo' else 'chung' end
  );
end $$;
revoke execute on function public.bavia_thong_tin_ma(text) from public, anon;
grant execute on function public.bavia_thong_tin_ma(text) to authenticated;

-- ── Mở / sửa Line trong ca (mã SP, KH ca, người thao tác, người kiểm tra) ────
create or replace function public.bavia_line_luu(
  p_ngay date, p_ca text, p_ten_line text, p_ma_sp text, p_kh_ca numeric,
  p_nguoi_thao_tac text, p_nguoi_kiem text
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_id text;
  v_info jsonb;
  v_dang_do record;
  v_user text := duc_su_co_nguoi_hien_tai();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if p_ngay is null or coalesce(p_ca, '') not in ('Ca ngày', 'Ca đêm', 'Ca 1', 'Ca 2') then
    return jsonb_build_object('ok', false, 'error', 'Ngày / ca không hợp lệ');
  end if;
  if exists (select 1 from bavia_ket_ca where ngay = p_ngay and ca = p_ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không sửa Line được');
  end if;
  if not exists (select 1 from master_machines where bo_phan = 'Bavia' and ma_may = p_ten_line) then
    return jsonb_build_object('ok', false, 'error', p_ten_line || ' không có trong danh mục Line Bavia');
  end if;
  v_info := bavia_thong_tin_ma(p_ma_sp);
  if not (v_info->>'ok')::boolean then return v_info; end if;

  -- Line còn hàng dở của mã khác thì không đổi mã (mỗi Line 1 mã tại một thời điểm)
  select n.ma_sp, sum(t.so_luong) sl into v_dang_do
  from bavia_line_nguon n join duc_tem t on t.tag_no = n.tag_no
  where n.ten_line = p_ten_line and n.bo_luc is null and t.so_luong > 0 and n.ma_sp <> trim(p_ma_sp)
  group by n.ma_sp limit 1;
  if found then
    return jsonb_build_object('ok', false, 'error',
      p_ten_line || ' còn dở ' || v_dang_do.sl || ' pcs mã ' || v_dang_do.ma_sp
      || ' trên tem Đúc đang dùng. Làm hết hoặc bấm Bỏ các tem đó trước khi đổi mã.');
  end if;

  v_id := duc_normalize_name('Bavia') || '_' || to_char(p_ngay, 'DDMMYYYY') || '_'
          || duc_normalize_name(p_ca) || '_' || duc_normalize_name(p_ten_line);
  insert into cd_tram_hien_tai (id_tram, ngay, ca, cong_doan, ten_tram, ma_sp, ten_sp, kh_ca,
    nguoi_thao_tac, nguoi_kiem_tra, so_luong_ok, so_luong_ng, version, last_updated_by, last_updated_at)
  values (v_id, p_ngay, p_ca, 'Bavia', p_ten_line, trim(p_ma_sp), coalesce(v_info->>'ten_sp', ''),
    nullif(p_kh_ca, 0), coalesce(p_nguoi_thao_tac, ''), nullif(trim(coalesce(p_nguoi_kiem, '')), ''),
    0, 0, 1, v_user, now())
  on conflict (id_tram) do update set
    ma_sp = excluded.ma_sp, ten_sp = excluded.ten_sp, kh_ca = excluded.kh_ca,
    nguoi_thao_tac = excluded.nguoi_thao_tac, nguoi_kiem_tra = excluded.nguoi_kiem_tra,
    version = cd_tram_hien_tai.version + 1, last_updated_by = v_user, last_updated_at = now();

  return jsonb_build_object('ok', true, 'id_tram', v_id);
end $$;
revoke execute on function public.bavia_line_luu(date, text, text, text, numeric, text, text) from public, anon;
grant execute on function public.bavia_line_luu(date, text, text, text, numeric, text, text) to authenticated;

-- ── Nội bộ: trừ nguồn FIFO của Line cho 1 thùng, ghi cd_tem_nguon ──────────
create or replace function public.bavia_tru_nguon(p_ten_line text, p_ma_sp text, p_sl numeric, p_tag_moi text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_need numeric := p_sl;
  v_take numeric;
  r record;
  v_used jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập'; end if;
  for r in
    select n.tag_no, t.so_luong
    from bavia_line_nguon n join duc_tem t on t.tag_no = n.tag_no
    where n.ten_line = p_ten_line and n.ma_sp = p_ma_sp and n.bo_luc is null and t.so_luong > 0
    order by n.thoi_diem, n.id
    for update of t
  loop
    exit when v_need <= 0;
    v_take := least(v_need, r.so_luong);
    update duc_tem set so_luong = so_luong - v_take where tag_no = r.tag_no;
    insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay) values (p_tag_moi, r.tag_no, v_take)
      on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
    v_used := v_used || jsonb_build_array(jsonb_build_object('tag_no', r.tag_no, 'so_luong_lay', v_take));
    v_need := v_need - v_take;
  end loop;
  if v_need > 0 then
    raise exception 'Tem Đúc đang dùng còn thiếu % pcs. Quét thêm tem Đúc rồi làm lại.', v_need
      using errcode = 'P0001';
  end if;
  return v_used;
end $$;
revoke execute on function public.bavia_tru_nguon(text, text, numeric, text) from public, anon, authenticated;

-- ── Tổng số còn trên tem Đúc đang dùng của Line (mã đang chạy) ─────────────
create or replace function public.bavia_con_nguon(p_ten_line text, p_ma_sp text)
returns numeric
language sql stable security definer set search_path = public
as $$
  select coalesce(sum(t.so_luong), 0)
  from bavia_line_nguon n join duc_tem t on t.tag_no = n.tag_no
  where n.ten_line = p_ten_line and n.ma_sp = p_ma_sp and n.bo_luc is null and t.so_luong > 0
    and auth.uid() is not null;
$$;
revoke execute on function public.bavia_con_nguon(text, text) from public, anon, authenticated;

-- ── Nội bộ: điền lô / khuôn / NVL / máy / ngày đúc của tem TP từ nguồn ──────
create or replace function public.bavia_dien_thong_tin_nguon(p_tag_tp text)
returns void
language sql security definer set search_path = public
as $$
  update duc_tem t set
    ngay = s.ngay, lot = s.lot, so_khuon = s.khuon, so_khuon_tt = s.khuon,
    nguyen_lieu = coalesce(nullif(s.nl, ''), t.nguyen_lieu), may_duc_chi_thi = s.may
  from (
    select min(d.ngay) ngay,
      string_agg(distinct nullif(d.lot, ''), ', ') lot,
      string_agg(distinct nullif(coalesce(d.so_khuon_tt, d.so_khuon), ''), ', ') khuon,
      string_agg(distinct nullif(d.nguyen_lieu, ''), ', ') nl,
      string_agg(distinct nullif(coalesce(d.may_tt, d.may_duc_chi_thi), ''), ', ') may
    from cd_tem_nguon n join duc_tem d on d.tag_no = n.tag_no_nguon
    where n.tag_no_moi = p_tag_tp
  ) s
  where t.tag_no = p_tag_tp and auth.uid() is not null;
$$;
revoke execute on function public.bavia_dien_thong_tin_nguon(text) from public, anon, authenticated;

-- ── Quét 1 mã ở Line: tem Đúc = khai báo nguồn; tem TP = ghi nhận thùng Dạng 2
create or replace function public.bavia_quet(p_id_tram text, p_tag text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_line cd_tram_hien_tai%rowtype;
  v_tem duc_tem%rowtype;
  v_tag text := upper(trim(coalesce(p_tag, '')));
  v_info jsonb;
  v_vi_tri text;
  v_line_khac text;
  v_used jsonb;
  v_user text := duc_su_co_nguoi_hien_tai();
  v_now timestamptz := now();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if v_tag = '' then return jsonb_build_object('ok', false, 'error', 'Chưa có mã quét'); end if;
  select * into v_line from cd_tram_hien_tai where id_tram = p_id_tram and cong_doan = 'Bavia';
  if not found then return jsonb_build_object('ok', false, 'error', 'Line chưa được mở trong ca này'); end if;
  if exists (select 1 from bavia_ket_ca where ngay = v_line.ngay and ca = v_line.ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không ghi thêm được');
  end if;

  select * into v_tem from duc_tem where tag_no = v_tag for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || v_tag);
  end if;
  if v_tem.ma_sp is distinct from v_line.ma_sp then
    return jsonb_build_object('ok', false, 'error',
      'Tem ' || v_tem.tag_no || ' là mã ' || coalesce(v_tem.ma_sp, '?') || ', ' || v_line.ten_tram || ' đang chạy mã ' || v_line.ma_sp);
  end if;
  if duc_tem_id_ncp_cach_ly(v_tem.tag_no) is not null then
    return jsonb_build_object('ok', false, 'error',
      'Tem ' || v_tem.tag_no || ' đang bị cách ly theo phiếu NCP ' || duc_tem_id_ncp_cach_ly(v_tem.tag_no) || '. Báo QC.');
  end if;

  -- ── Tem thùng TP in sẵn (Dạng 2) ──
  if v_tem.tag_no like 'TP%' then
    v_info := bavia_thong_tin_ma(v_line.ma_sp);
    if not (v_info->>'ok')::boolean then return v_info; end if;
    if (v_info->>'dang')::int = 1 then
      return jsonb_build_object('ok', false, 'error',
        v_line.ten_tram || ' in tem khi đóng thùng nên không quét tem in sẵn. Bấm "Đóng thùng · In tem".');
    end if;
    if v_tem.trang_thai = 'Đã đóng gói TP' then
      return jsonb_build_object('ok', false, 'da_ghi_nhan', true, 'error',
        'Tem thùng ' || v_tem.tag_no || ' đã ghi nhận lúc '
        || coalesce(to_char(v_tem.ngay_gio_ghi_nhan at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'), '?'));
    end if;
    if v_tem.trang_thai <> 'Chờ đóng gói TP' or coalesce(v_tem.tram_cong_doan, '') <> 'Bavia' then
      return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' không phải tem thùng Bavia in sẵn (hoặc đã huỷ)');
    end if;
    if coalesce(v_line.nguoi_thao_tac, '') = '' then
      return jsonb_build_object('ok', false, 'error', v_line.ten_tram || ' chưa gán người thao tác');
    end if;
    if coalesce(v_line.nguoi_kiem_tra, '') = '' then
      return jsonb_build_object('ok', false, 'error', v_line.ten_tram || ' chưa có người kiểm tra. Trưởng ca chọn ở Line.');
    end if;

    if bavia_con_nguon(v_line.ten_tram, v_line.ma_sp) < v_tem.so_luong then
      return jsonb_build_object('ok', false, 'thieu_nguon', true, 'error',
        'Tem Đúc đang dùng chỉ còn ' || bavia_con_nguon(v_line.ten_tram, v_line.ma_sp) || ' pcs, chưa đủ '
        || v_tem.so_luong || '. Quét thêm tem Đúc rồi quét lại tem thùng.');
    end if;
    v_used := bavia_tru_nguon(v_line.ten_tram, v_line.ma_sp, v_tem.so_luong, v_tem.tag_no);
    update duc_tem set so_luong_tt = so_luong, nguoi_tt = v_line.nguoi_kiem_tra, trang_thai = 'Đã đóng gói TP',
      ghi_chu_sl = 'Đã ghi nhận thành phẩm', ngay_gio_ghi_nhan = v_now, ngay_gio_xuat = v_now, thoi_diem_san_xuat = v_now
    where tag_no = v_tem.tag_no;
    perform bavia_dien_thong_tin_nguon(v_tem.tag_no);
    insert into bavia_thung (tag_tp, ten_line, id_tram, ngay, ca, ma_sp, so_luong, dang, nguoi_lam, nguoi_kiem, nguoi_ghi, nguoi_uid)
    values (v_tem.tag_no, v_line.ten_tram, v_line.id_tram, v_line.ngay, v_line.ca, v_line.ma_sp, v_tem.so_luong, 2,
      v_line.nguoi_thao_tac, v_line.nguoi_kiem_tra, v_user, auth.uid());
    perform cd_tram_nhap_sanluong(v_line.id_tram, v_tem.so_luong, 0, null, v_user);
    return jsonb_build_object('ok', true, 'loai', 'thung', 'tag_no', v_tem.tag_no, 'so_luong', v_tem.so_luong,
      'buoc_sau', v_info->>'buoc_sau', 'nguon', v_used);
  end if;

  -- ── Tem Đúc: khai báo nguồn đang dùng ──
  if coalesce(v_tem.trang_thai, '') in ('Chờ sản xuất', 'NG chờ sửa', 'Chờ đóng gói TP', 'Đã đóng gói TP') then
    return jsonb_build_object('ok', false, 'error',
      'Tem ' || v_tem.tag_no || ' đang ở trạng thái "' || v_tem.trang_thai || '", không dùng làm nguồn Bavia được');
  end if;
  if coalesce(v_tem.so_luong, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || v_tem.tag_no || ' đã dùng hết, không khai báo lại được');
  end if;
  select ten_line into v_line_khac from bavia_line_nguon where tag_no = v_tem.tag_no and bo_luc is null;
  if v_line_khac = v_line.ten_tram then
    return jsonb_build_object('ok', false, 'trung', true, 'error', 'Tem ' || v_tem.tag_no || ' đã khai báo ở ' || v_line_khac);
  elsif v_line_khac is not null then
    return jsonb_build_object('ok', false, 'error',
      'Tem ' || v_tem.tag_no || ' đang khai báo ở ' || v_line_khac || '. Bấm Bỏ ở ' || v_line_khac || ' trước.');
  end if;

  select cong_doan_nhan into v_vi_tri from cd_chuyen_cong_doan_log
  where tag_no = v_tem.tag_no order by thoi_gian_chuyen desc limit 1;
  if v_vi_tri is null or v_vi_tri = 'Đúc' then
    -- Tự nhận Đúc → Bavia khi quét ở Line
    insert into cd_chuyen_cong_doan_log (id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen,
      chenh_lech, lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan,
      nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan, ghi_chu)
    values (cd_next_transfer_id(), v_now, v_tem.tag_no, v_tem.ma_sp, v_tem.ten_sp, v_tem.so_luong, v_tem.so_luong, 0,
      coalesce(v_tem.lot, ''), coalesce(v_tem.so_khuon_tt, v_tem.so_khuon, ''), coalesce(v_tem.nguyen_lieu, ''),
      coalesce(v_tem.may_tt, v_tem.may_duc_chi_thi, ''), coalesce(v_tem.ngay::text, ''), 'Đúc', 'Bavia',
      'Tự nhận tại ' || v_line.ten_tram, v_user, 'Đã xác nhận chuyển công đoạn',
      to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI:SS DD/MM/YYYY'),
      'Quét tem Đúc ở Bảng điều khiển Bavia');
  elsif v_vi_tri <> 'Bavia' then
    return jsonb_build_object('ok', false, 'error',
      'Tem ' || v_tem.tag_no || ' đang ở công đoạn ' || v_vi_tri || ', không phải Bavia');
  end if;

  insert into bavia_line_nguon (ten_line, tag_no, ma_sp, sl_khai_bao, nguoi, nguoi_uid)
  values (v_line.ten_tram, v_tem.tag_no, v_tem.ma_sp, v_tem.so_luong, v_user, auth.uid());
  return jsonb_build_object('ok', true, 'loai', 'nguon', 'tag_no', v_tem.tag_no, 'so_luong', v_tem.so_luong,
    'tu_nhan', v_vi_tri is null or v_vi_tri = 'Đúc');
end $$;
revoke execute on function public.bavia_quet(text, text) from public, anon;
grant execute on function public.bavia_quet(text, text) to authenticated;

-- ── Bỏ khai báo 1 tem Đúc (quét nhầm / chuyển sang Line khác) ───────────────
create or replace function public.bavia_bo_nguon(p_id bigint)
returns jsonb
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  update bavia_line_nguon set bo_luc = now(), bo_boi = duc_su_co_nguoi_hien_tai()
  where id = p_id and bo_luc is null;
  if not found then return jsonb_build_object('ok', false, 'error', 'Tem này đã được bỏ trước đó'); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.bavia_bo_nguon(bigint) from public, anon;
grant execute on function public.bavia_bo_nguon(bigint) to authenticated;

-- ── Dạng 1: đóng thùng → tạo tem xuất hàng (TP) ─────────────────────────────
create or replace function public.bavia_dong_thung(p_id_tram text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_line cd_tram_hien_tai%rowtype;
  v_info jsonb;
  v_sl numeric;
  v_tag text;
  v_used jsonb;
  v_user text := duc_su_co_nguoi_hien_tai();
  v_now timestamptz := now();
  v_t duc_tem%rowtype;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into v_line from cd_tram_hien_tai where id_tram = p_id_tram and cong_doan = 'Bavia' for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Line chưa được mở trong ca này'); end if;
  if exists (select 1 from bavia_ket_ca where ngay = v_line.ngay and ca = v_line.ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không ghi thêm được');
  end if;
  v_info := bavia_thong_tin_ma(v_line.ma_sp);
  if not (v_info->>'ok')::boolean then return v_info; end if;
  if (v_info->>'dang')::int <> 1 then
    return jsonb_build_object('ok', false, 'error', 'Mã ' || v_line.ma_sp || ' còn công đoạn ' || (v_info->>'buoc_sau')
      || ' sau Bavia: quét tem thùng in sẵn thay vì đóng thùng in tem');
  end if;
  if coalesce(v_line.nguoi_thao_tac, '') = '' then
    return jsonb_build_object('ok', false, 'error', v_line.ten_tram || ' chưa gán người thao tác');
  end if;
  if coalesce(v_line.nguoi_kiem_tra, '') = '' then
    return jsonb_build_object('ok', false, 'error', v_line.ten_tram || ' chưa có người kiểm tra. Trưởng ca chọn ở Line.');
  end if;
  v_sl := (v_info->>'sl_thung')::numeric;
  if bavia_con_nguon(v_line.ten_tram, v_line.ma_sp) < v_sl then
    return jsonb_build_object('ok', false, 'thieu_nguon', true, 'error',
      'Tem Đúc đang dùng chỉ còn ' || bavia_con_nguon(v_line.ten_tram, v_line.ma_sp) || ' pcs, chưa đủ 1 thùng '
      || v_sl || ' pcs. Quét thêm tem Đúc trước khi đóng thùng.');
  end if;

  v_tag := cd_next_tag_no_thanh_pham();
  insert into duc_tem (tag_no, ten_sp, ma_sp, so_luong, so_luong_tt, ma_sp_khach_hang, ten_khach_hang, nguyen_lieu,
    ghi_chu, ngay_gio_in, ngay_gio_ghi_nhan, ngay_gio_xuat, nguoi_tt, trang_thai, ghi_chu_sl, tram_cong_doan, thoi_diem_san_xuat)
  values (v_tag, v_info->>'ten_sp', v_line.ma_sp, v_sl, v_sl, v_info->>'ma_sp_khach_hang', v_info->>'ten_khach_hang',
    v_info->>'nguyen_lieu', 'Tem xuất hàng Bavia — ' || v_line.ten_tram, v_now, v_now, v_now, v_line.nguoi_kiem_tra,
    'Đã đóng gói TP', 'Đã ghi nhận thành phẩm', 'Bavia', v_now);
  v_used := bavia_tru_nguon(v_line.ten_tram, v_line.ma_sp, v_sl, v_tag);
  perform bavia_dien_thong_tin_nguon(v_tag);
  select * into v_t from duc_tem where tag_no = v_tag;

  insert into cd_chuyen_cong_doan_log (id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen,
    chenh_lech, lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan,
    nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan, ghi_chu)
  values (cd_next_transfer_id(), v_now, v_tag, v_line.ma_sp, v_t.ten_sp, v_sl, v_sl, 0,
    coalesce(v_t.lot, ''), coalesce(v_t.so_khuon, ''), coalesce(v_t.nguyen_lieu, ''), coalesce(v_t.may_duc_chi_thi, ''),
    coalesce(v_t.ngay::text, ''), 'Bavia', 'Bavia', v_user, v_user, 'Đã xác nhận chuyển công đoạn',
    to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI:SS DD/MM/YYYY'),
    'Đóng thùng tem xuất hàng tại ' || v_line.ten_tram);

  insert into bavia_thung (tag_tp, ten_line, id_tram, ngay, ca, ma_sp, so_luong, dang, nguoi_lam, nguoi_kiem, nguoi_ghi, nguoi_uid)
  values (v_tag, v_line.ten_tram, v_line.id_tram, v_line.ngay, v_line.ca, v_line.ma_sp, v_sl, 1,
    v_line.nguoi_thao_tac, v_line.nguoi_kiem_tra, v_user, auth.uid());
  perform cd_tram_nhap_sanluong(v_line.id_tram, v_sl, 0, null, v_user);
  return jsonb_build_object('ok', true, 'tag_no', v_tag, 'so_luong', v_sl, 'mau', v_info->>'mau', 'nguon', v_used);
end $$;
revoke execute on function public.bavia_dong_thung(text) from public, anon;
grant execute on function public.bavia_dong_thung(text) to authenticated;

-- ── NG: trừ thẳng vào tem Đúc đang dùng của Line ────────────────────────────
create or replace function public.bavia_ng(p_id_tram text, p_tag_no text, p_loai text, p_ghi_chu text, p_sl numeric)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_line cd_tram_hien_tai%rowtype;
  v_tem duc_tem%rowtype;
  v_user text := duc_su_co_nguoi_hien_tai();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if coalesce(trim(p_loai), '') = '' then return jsonb_build_object('ok', false, 'error', 'Chọn tên lỗi NG'); end if;
  if trim(p_loai) = 'Khác' and length(trim(coalesce(p_ghi_chu, ''))) < 3 then
    return jsonb_build_object('ok', false, 'error', 'Lỗi "Khác" phải ghi rõ nguyên nhân');
  end if;
  if coalesce(p_sl, 0) <= 0 or p_sl <> trunc(p_sl) then
    return jsonb_build_object('ok', false, 'error', 'Số lượng NG phải là số nguyên lớn hơn 0');
  end if;
  select * into v_line from cd_tram_hien_tai where id_tram = p_id_tram and cong_doan = 'Bavia';
  if not found then return jsonb_build_object('ok', false, 'error', 'Line chưa được mở trong ca này'); end if;
  if exists (select 1 from bavia_ket_ca where ngay = v_line.ngay and ca = v_line.ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không ghi thêm được');
  end if;
  if not exists (select 1 from bavia_line_nguon where tag_no = p_tag_no and ten_line = v_line.ten_tram and bo_luc is null) then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || p_tag_no || ' không phải tem Đúc đang dùng của ' || v_line.ten_tram);
  end if;
  select * into v_tem from duc_tem where tag_no = p_tag_no for update;
  if p_sl > coalesce(v_tem.so_luong, 0) then
    return jsonb_build_object('ok', false, 'error', 'Số NG vượt số còn trên tem (' || coalesce(v_tem.so_luong, 0) || ' pcs)');
  end if;

  update duc_tem set so_luong = so_luong - p_sl where tag_no = p_tag_no;
  insert into cd_ng_khai_bao (tag_no, ma_sp, ten_sp, cong_doan, loai_ng, so_luong, nguoi, id_tram, ghi_chu)
  values (v_tem.tag_no, v_tem.ma_sp, v_tem.ten_sp, 'Bavia', trim(p_loai), p_sl, v_user, v_line.id_tram,
    nullif(trim(coalesce(p_ghi_chu, '')), ''));
  perform cd_tram_nhap_sanluong(v_line.id_tram, 0, p_sl, null, v_user);
  return jsonb_build_object('ok', true, 'so_luong_con_lai', v_tem.so_luong - p_sl);
end $$;
revoke execute on function public.bavia_ng(text, text, text, text, numeric) from public, anon;
grant execute on function public.bavia_ng(text, text, text, text, numeric) to authenticated;

-- ── Hàng test: lấy ra (trừ như NG) / kết thúc (trả lại cộng về tem Đúc) ─────
create or replace function public.bavia_test_lay(
  p_id_tram text, p_tag_no text, p_sl numeric, p_muc_dich text, p_noi_dung text, p_nguoi_test text
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_line cd_tram_hien_tai%rowtype;
  v_tem duc_tem%rowtype;
  v_id bigint;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if coalesce(trim(p_muc_dich), '') = '' then return jsonb_build_object('ok', false, 'error', 'Chọn mục đích test'); end if;
  if length(trim(coalesce(p_noi_dung, ''))) < 3 then
    return jsonb_build_object('ok', false, 'error', 'Ghi rõ nội dung test (ít nhất 3 ký tự)');
  end if;
  if coalesce(trim(p_nguoi_test), '') = '' then return jsonb_build_object('ok', false, 'error', 'Chọn người test'); end if;
  if coalesce(p_sl, 0) <= 0 or p_sl <> trunc(p_sl) then
    return jsonb_build_object('ok', false, 'error', 'Số lượng test phải là số nguyên lớn hơn 0');
  end if;
  select * into v_line from cd_tram_hien_tai where id_tram = p_id_tram and cong_doan = 'Bavia';
  if not found then return jsonb_build_object('ok', false, 'error', 'Line chưa được mở trong ca này'); end if;
  if exists (select 1 from bavia_ket_ca where ngay = v_line.ngay and ca = v_line.ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không ghi thêm được');
  end if;
  if not exists (select 1 from bavia_line_nguon where tag_no = p_tag_no and ten_line = v_line.ten_tram and bo_luc is null) then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || p_tag_no || ' không phải tem Đúc đang dùng của ' || v_line.ten_tram);
  end if;
  select * into v_tem from duc_tem where tag_no = p_tag_no for update;
  if p_sl > coalesce(v_tem.so_luong, 0) then
    return jsonb_build_object('ok', false, 'error', 'Số test vượt số còn trên tem (' || coalesce(v_tem.so_luong, 0) || ' pcs)');
  end if;

  update duc_tem set so_luong = so_luong - p_sl where tag_no = p_tag_no;
  insert into bavia_hang_test (id_tram, ten_line, ngay, ca, tag_no, ma_sp, so_luong, muc_dich, noi_dung, nguoi_test, nguoi_ghi)
  values (v_line.id_tram, v_line.ten_tram, v_line.ngay, v_line.ca, p_tag_no, v_tem.ma_sp, p_sl, trim(p_muc_dich),
    trim(p_noi_dung), trim(p_nguoi_test), duc_su_co_nguoi_hien_tai())
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke execute on function public.bavia_test_lay(text, text, numeric, text, text, text) from public, anon;
grant execute on function public.bavia_test_lay(text, text, numeric, text, text, text) to authenticated;

create or replace function public.bavia_test_ket_thuc(p_id bigint, p_sl_tra_lai numeric)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v bavia_hang_test%rowtype;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into v from bavia_hang_test where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy lần test'); end if;
  if v.ket_thuc_luc is not null then return jsonb_build_object('ok', false, 'error', 'Lần test này đã kết thúc'); end if;
  if p_sl_tra_lai is null or p_sl_tra_lai < 0 or p_sl_tra_lai > v.so_luong or p_sl_tra_lai <> trunc(p_sl_tra_lai) then
    return jsonb_build_object('ok', false, 'error', 'Số trả lại phải từ 0 đến ' || v.so_luong);
  end if;
  if p_sl_tra_lai > 0 then
    update duc_tem set so_luong = so_luong + p_sl_tra_lai where tag_no = v.tag_no;
  end if;
  update bavia_hang_test set ket_thuc_luc = now(), sl_tra_lai = p_sl_tra_lai, nguoi_ket_thuc = duc_su_co_nguoi_hien_tai()
  where id = p_id;
  return jsonb_build_object('ok', true, 'tra_lai', p_sl_tra_lai, 'huy', v.so_luong - p_sl_tra_lai,
    'nguon_con_khai_bao', exists (select 1 from bavia_line_nguon where tag_no = v.tag_no and bo_luc is null));
end $$;
revoke execute on function public.bavia_test_ket_thuc(bigint, numeric) from public, anon;
grant execute on function public.bavia_test_ket_thuc(bigint, numeric) to authenticated;

-- ── Dữ liệu 1 lần cho cả màn hình (ngày + ca) ───────────────────────────────
create or replace function public.bavia_du_lieu(p_ngay date, p_ca text)
returns jsonb
language sql stable security definer set search_path = public
as $$
  with lines as (
    select * from cd_tram_hien_tai where cong_doan = 'Bavia' and ngay = p_ngay and ca = p_ca
  )
  select jsonb_build_object(
    'danh_muc_line', (select coalesce(jsonb_agg(ma_may order by ma_may), '[]'::jsonb) from master_machines where bo_phan = 'Bavia'),
    'ket_ca', (select to_jsonb(k) from bavia_ket_ca k where k.ngay = p_ngay and k.ca = p_ca),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object(
        'id_tram', l.id_tram, 'ten_line', l.ten_tram, 'ma_sp', l.ma_sp, 'ten_sp', l.ten_sp, 'kh_ca', l.kh_ca,
        'nguoi_thao_tac', l.nguoi_thao_tac, 'nguoi_kiem_tra', l.nguoi_kiem_tra,
        'so_luong_ok', l.so_luong_ok, 'so_luong_ng', l.so_luong_ng,
        'info', bavia_thong_tin_ma(l.ma_sp),
        'nguon', (select coalesce(jsonb_agg(jsonb_build_object(
              'id', n.id, 'tag_no', n.tag_no, 'sl_khai_bao', n.sl_khai_bao, 'con', t.so_luong, 'thoi_diem', n.thoi_diem,
              'ngay_duc', t.ngay, 'may', coalesce(t.may_tt, t.may_duc_chi_thi), 'nguoi_duc', t.nguoi_tt,
              'so_khuon', coalesce(t.so_khuon_tt, t.so_khuon)) order by n.thoi_diem, n.id), '[]'::jsonb)
            from bavia_line_nguon n join duc_tem t on t.tag_no = n.tag_no
            where n.ten_line = l.ten_tram and n.bo_luc is null
              and (t.so_luong > 0 or n.thoi_diem > now() - interval '12 hours')),
        'thung', (select coalesce(jsonb_agg(jsonb_build_object(
              'tag_tp', b.tag_tp, 'so_luong', b.so_luong, 'dang', b.dang, 'nguoi_lam', b.nguoi_lam, 'nguoi_kiem', b.nguoi_kiem,
              'thoi_diem', b.thoi_diem,
              'nguon', (select coalesce(jsonb_agg(jsonb_build_object('tag_no', s.tag_no_nguon, 'so_luong_lay', s.so_luong_lay)), '[]'::jsonb)
                        from cd_tem_nguon s where s.tag_no_moi = b.tag_tp)) order by b.thoi_diem desc), '[]'::jsonb)
            from bavia_thung b where b.id_tram = l.id_tram),
        'ng', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'tag_no', g.tag_no, 'loai', g.loai_ng, 'ghi_chu', g.ghi_chu,
              'so_luong', g.so_luong, 'nguoi', g.nguoi, 'ngay_gio', g.ngay_gio) order by g.ngay_gio desc), '[]'::jsonb)
            from cd_ng_khai_bao g where g.id_tram = l.id_tram),
        'test', (select coalesce(jsonb_agg(to_jsonb(h) order by h.thoi_diem desc), '[]'::jsonb)
            from bavia_hang_test h where h.id_tram = l.id_tram or (h.ten_line = l.ten_tram and h.ket_thuc_luc is null))
      ) order by l.ten_tram), '[]'::jsonb) from lines l),
    -- Tem Đúc còn hàng của các mã Bavia, đang ở Bavia hoặc chưa chuyển khỏi Đúc, chưa khai báo ở Line nào
    'cho', (select coalesce(jsonb_agg(jsonb_build_object('ma_sp', x.ma_sp, 'so_tem', x.so_tem, 'pcs', x.pcs,
              'tai_bavia', x.tai_bavia, 'ngay_tu', x.ngay_tu, 'ngay_den', x.ngay_den, 'may', x.may) order by x.ma_sp), '[]'::jsonb)
      from (
        select t.ma_sp, count(*) so_tem, sum(t.so_luong) pcs, count(*) filter (where v.vi_tri_hien_tai = 'Bavia') tai_bavia,
          min(t.ngay) ngay_tu, max(t.ngay) ngay_den, string_agg(distinct coalesce(t.may_tt, t.may_duc_chi_thi), ', ') may
        from duc_tem t
        left join cd_v_vi_tri_hien_tai v on v.tag_no = t.tag_no
        where t.tag_no not like 'TP%' and t.so_luong > 0
          and coalesce(t.trang_thai, '') not in ('Chờ sản xuất', 'NG chờ sửa')
          and t.ma_sp in (select ma_sp from lines)
          and (v.vi_tri_hien_tai = 'Bavia'
               or (coalesce(v.vi_tri_hien_tai, 'Đúc') = 'Đúc' and t.ngay >= p_ngay - 14))
          and not exists (select 1 from bavia_line_nguon n where n.tag_no = t.tag_no and n.bo_luc is null)
        group by t.ma_sp
      ) x)
  )
  where auth.uid() is not null;
$$;
revoke execute on function public.bavia_du_lieu(date, text) from public, anon;
grant execute on function public.bavia_du_lieu(date, text) to authenticated;

-- ── Dữ liệu in tem xuất hàng / phiếu quản lý lô cho thùng Bavia ─────────────
create or replace function public.bavia_du_lieu_in(p_tags text[])
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'tag_no', t.tag_no, 'ma_sp', t.ma_sp, 'ten_sp', t.ten_sp, 'so_luong', t.so_luong_tt,
      'ma_sp_khach_hang', coalesce(t.ma_sp_khach_hang, p.ma_sp_khach_hang),
      'ten_khach_hang', coalesce(t.ten_khach_hang, p.ten_khach_hang),
      'nguyen_lieu', t.nguyen_lieu, 'lot', t.lot, 'ngay', t.ngay, 'so_khuon', t.so_khuon,
      'may', t.may_duc_chi_thi, 'luc', t.ngay_gio_ghi_nhan,
      'line', b.ten_line, 'ca_bavia', b.ca, 'ngay_bavia', b.ngay,
      'nguoi_bavia', b.nguoi_lam, 'nguoi_kiem', b.nguoi_kiem,
      'thung_le', t.so_luong_tt < coalesce(nullif(p.sl_thung_cong_doan ->> 'Bavia', '')::numeric, 0),
      'mau', case when coalesce(t.ten_khach_hang, p.ten_khach_hang) ~* 'FCC' then 'fcc'
                  when coalesce(t.ten_khach_hang, p.ten_khach_hang) ~* 'ASTEMO' then 'astemo' else 'chung' end,
      'nguon', (select coalesce(jsonb_agg(jsonb_build_object('tag_no', s.tag_no, 'so_luong_lay', n.so_luong_lay,
                  'ngay', s.ngay, 'may', coalesce(s.may_tt, s.may_duc_chi_thi), 'nguoi', s.nguoi_tt,
                  'so_khuon', s.so_khuon, 'ngay_gio_in', s.ngay_gio_in, 'ca', bavia_xh_ca_tem(s.tag_no))
                  order by s.ngay, s.tag_no), '[]'::jsonb)
                from cd_tem_nguon n join duc_tem s on s.tag_no = n.tag_no_nguon where n.tag_no_moi = t.tag_no)
    ) order by t.tag_no), '[]'::jsonb)
  from duc_tem t
  join bavia_thung b on b.tag_tp = t.tag_no
  left join master_products p on p.ma_sp = t.ma_sp
  where t.tag_no = any(p_tags) and auth.uid() is not null;
$$;
revoke execute on function public.bavia_du_lieu_in(text[]) from public, anon;
grant execute on function public.bavia_du_lieu_in(text[]) to authenticated;
