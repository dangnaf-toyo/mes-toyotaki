-- ============================================================================
-- Phase T7 — Kho thành phẩm: thêm công đoạn "Nhập kho"/"Xuất hàng", tách rõ
-- "OQC đóng gói xong" khỏi "đã thực sự nhập kho" (2 vị trí/thời điểm khác
-- nhau trong thực tế), và phiếu xuất hàng (khách hàng/số đơn hàng).
--
-- 3 phần:
--   1) oqc_pallet: thêm trạng thái trung gian 'da_dong_goi' (đóng gói xong,
--      CHƯA nhập kho) — oqc_dong_pallet() đổi sang set trạng thái này thay
--      vì 'da_nhap_kho' như trước. RPC mới oqc_pallet_nhap_kho() mới thực sự
--      chuyển sang 'da_nhap_kho' (quét lại ở màn kho-thanh-pham.html). Thêm
--      trạng thái 'da_xuat' khi phiếu xuất hàng đóng.
--   2) kho_phieu_xuat + kho_phieu_xuat_item — phiếu xuất hàng, quét được cả
--      pallet (PLT...) lẫn tem lẻ (không qua pallet), lưu khách hàng/số đơn
--      hàng. Đóng phiếu → pallet chuyển 'da_xuat', tem lẻ ghi 1 dòng chuyển
--      công đoạn "Nhập kho" → "Xuất hàng" (tái dùng cd_chuyen_cong_doan_log
--      đã có, không cần bảng vị trí riêng).
--   3) Tem lẻ (không qua pallet) NHẬP KHO vẫn dùng thẳng RPC
--      cd_ghi_chuyen_cong_doan đã có (chuyển công đoạn nhận = "Nhập kho") —
--      không cần RPC mới, chỉ cần công đoạn "Nhập kho" xuất hiện trong danh
--      sách công đoạn hợp lệ ở giao diện (chuyencongdoan.html/
--      quan-ly-danh-muc.html/kho-thanh-pham.html).
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ── 1) oqc_pallet: tách "đóng gói xong" khỏi "đã nhập kho" ──────────────────
alter table oqc_pallet add column if not exists thoi_diem_dong_goi timestamptz;

alter table oqc_pallet drop constraint if exists oqc_pallet_trang_thai_check;
alter table oqc_pallet add constraint oqc_pallet_trang_thai_check
  check (trang_thai in ('dang_dong_goi', 'da_dong_goi', 'da_nhap_kho', 'da_xuat'));

create or replace function oqc_dong_pallet(p_id_pallet text)
returns void
language plpgsql
security definer
as $$
begin
  update oqc_pallet
  set trang_thai = 'da_dong_goi', thoi_diem_dong_goi = now()
  where id_pallet = p_id_pallet and trang_thai = 'dang_dong_goi';
  if not found then
    raise exception 'Không tìm thấy pallet đang đóng gói %', p_id_pallet;
  end if;
end;
$$;

create or replace function oqc_pallet_nhap_kho(p_id_pallet text, p_nguoi text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row oqc_pallet%rowtype;
begin
  select * into v_row from oqc_pallet where id_pallet = p_id_pallet for update;
  if not found then raise exception 'Không tìm thấy pallet %', p_id_pallet; end if;
  if v_row.trang_thai = 'dang_dong_goi' then raise exception 'Pallet % chưa đóng gói xong, không nhập kho được', p_id_pallet; end if;
  if v_row.trang_thai = 'da_nhap_kho' then raise exception 'Pallet % đã nhập kho trước đó rồi', p_id_pallet; end if;
  if v_row.trang_thai = 'da_xuat' then raise exception 'Pallet % đã xuất kho rồi', p_id_pallet; end if;

  update oqc_pallet set trang_thai = 'da_nhap_kho', thoi_diem_nhap_kho = now() where id_pallet = p_id_pallet;
  return jsonb_build_object('ok', true, 'tong_so_luong', v_row.tong_so_luong);
end;
$$;

-- Nhập kho 1 tem lẻ (không qua pallet OQC) — tự xác nhận luôn (người quét
-- chính là người đang đứng ở kho, không cần bên khác xác nhận lại như luồng
-- chuyển công đoạn thường), đối xứng với oqc_pallet_nhap_kho() ở trên.
create or replace function kho_nhap_kho_tem(p_tag_no text, p_nguoi text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_tem duc_tem%rowtype;
  v_vitri text;
  v_now timestamptz := now();
begin
  select * into v_tem from duc_tem where tag_no = p_tag_no;
  if not found then raise exception 'Không tìm thấy tem %', p_tag_no; end if;
  if coalesce(v_tem.so_luong, 0) <= 0 then raise exception 'Tem % đã hết số lượng', p_tag_no; end if;

  select vi_tri_hien_tai into v_vitri from cd_v_vi_tri_hien_tai where tag_no = p_tag_no;
  if v_vitri = 'Nhập kho' then raise exception 'Tem % đã nhập kho rồi', p_tag_no; end if;

  insert into cd_chuyen_cong_doan_log (
    id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
    cong_doan_giao, cong_doan_nhan, nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan
  ) values (
    cd_next_transfer_id(), v_now, p_tag_no, v_tem.ma_sp, v_tem.ten_sp, v_tem.so_luong, v_tem.so_luong, 0,
    coalesce(v_vitri, 'OQC'), 'Nhập kho', p_nguoi, p_nguoi, 'Đã xác nhận chuyển công đoạn',
    to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
  );

  return jsonb_build_object('ok', true, 'ma_sp', v_tem.ma_sp, 'ten_sp', v_tem.ten_sp, 'so_luong', v_tem.so_luong);
end;
$$;

-- ── 2) Phiếu xuất hàng ───────────────────────────────────────────────────────
create table if not exists kho_phieu_xuat_counter (
  prefix_ngay text primary key,
  last_seq    int not null default 0
);

create table if not exists kho_phieu_xuat (
  id_phieu      text primary key,   -- "XH{yyyyMMdd}-{seq 3 chữ số}"
  ngay          date not null,
  khach_hang    text,
  so_don_hang   text,
  trang_thai    text not null default 'mo' check (trang_thai in ('mo', 'da_xuat')),
  nguoi_xuat    text,
  ghi_chu       text,
  thoi_diem_tao timestamptz not null default now(),
  thoi_diem_dong timestamptz
);

create table if not exists kho_phieu_xuat_item (
  id_phieu    text not null references kho_phieu_xuat (id_phieu) on delete cascade,
  loai        text not null check (loai in ('pallet', 'tem')),
  ma          text not null,   -- id_pallet hoặc tag_no
  ma_sp       text,
  ten_sp      text,
  so_luong    numeric,
  thoi_diem_quet timestamptz not null default now(),
  primary key (id_phieu, ma)
);

create or replace function kho_next_phieu_xuat_id()
returns text
language plpgsql
security definer
as $$
declare
  d date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  key text := 'XH' || to_char(d, 'YYYYMMDD');
  next_seq int;
begin
  insert into kho_phieu_xuat_counter (prefix_ngay, last_seq)
  values (key, 1)
  on conflict (prefix_ngay) do update set last_seq = kho_phieu_xuat_counter.last_seq + 1
  returning last_seq into next_seq;
  return key || '-' || lpad(next_seq::text, 3, '0');
end;
$$;

create or replace function kho_tao_phieu_xuat(p_khach_hang text, p_so_don_hang text, p_nguoi text)
returns text
language plpgsql
security definer
as $$
declare
  v_id text := kho_next_phieu_xuat_id();
begin
  insert into kho_phieu_xuat (id_phieu, ngay, khach_hang, so_don_hang, nguoi_xuat, trang_thai, thoi_diem_tao)
  values (v_id, (now() at time zone 'Asia/Ho_Chi_Minh')::date, nullif(trim(coalesce(p_khach_hang, '')), ''), nullif(trim(coalesce(p_so_don_hang, '')), ''), p_nguoi, 'mo', now());
  return v_id;
end;
$$;

-- Quét 1 mã (pallet PLT... hoặc tag_no tem lẻ) thêm vào phiếu xuất — tự nhận
-- diện loại theo tiền tố, kiểm tra đang thực sự "trong kho" trước khi cho
-- thêm (pallet: trang_thai='da_nhap_kho'; tem lẻ: vị trí hiện tại='Nhập kho').
create or replace function kho_them_vao_phieu_xuat(p_id_phieu text, p_ma text, p_nguoi text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_loai text;
  v_sl numeric;
  v_ma_sp text;
  v_ten_sp text;
  v_trang_thai_phieu text;
  v_vi_tri text;
begin
  if p_ma is null or trim(p_ma) = '' then raise exception 'Thiếu mã quét'; end if;
  select trang_thai into v_trang_thai_phieu from kho_phieu_xuat where id_phieu = p_id_phieu;
  if not found then raise exception 'Không tìm thấy phiếu xuất %', p_id_phieu; end if;
  if v_trang_thai_phieu <> 'mo' then raise exception 'Phiếu % đã đóng, không thêm được nữa', p_id_phieu; end if;
  if exists (select 1 from kho_phieu_xuat_item where id_phieu = p_id_phieu and ma = p_ma) then
    raise exception 'Mã % đã có trong phiếu này rồi', p_ma;
  end if;

  if p_ma like 'PLT%' then
    select tong_so_luong into v_sl from oqc_pallet where id_pallet = p_ma and trang_thai = 'da_nhap_kho';
    if not found then raise exception 'Không tìm thấy pallet % đang trong kho (chưa nhập kho, hoặc đã xuất, hoặc đang ở phiếu xuất khác)', p_ma; end if;
    v_loai := 'pallet';
    select string_agg(distinct t.ma_sp, ', ') into v_ma_sp
    from duc_tem t where t.tag_no in (select tag_no from oqc_pallet_item where id_pallet = p_ma);
  else
    select ma_sp, ten_sp, so_luong into v_ma_sp, v_ten_sp, v_sl from duc_tem where tag_no = p_ma;
    if not found then raise exception 'Không tìm thấy tem %', p_ma; end if;
    select vi_tri_hien_tai into v_vi_tri from cd_v_vi_tri_hien_tai where tag_no = p_ma;
    if v_vi_tri is distinct from 'Nhập kho' then
      raise exception 'Tem % chưa ở trạng thái trong kho (vị trí hiện tại: %)', p_ma, coalesce(v_vi_tri, '(chưa xác định)');
    end if;
    v_loai := 'tem';
  end if;

  insert into kho_phieu_xuat_item (id_phieu, loai, ma, ma_sp, ten_sp, so_luong)
  values (p_id_phieu, v_loai, p_ma, v_ma_sp, v_ten_sp, coalesce(v_sl, 0));

  return jsonb_build_object('ok', true, 'loai', v_loai, 'ma_sp', v_ma_sp, 'so_luong', v_sl);
end;
$$;

create or replace function kho_xoa_khoi_phieu_xuat(p_id_phieu text, p_ma text)
returns void
language sql
security definer
as $$
  delete from kho_phieu_xuat_item where id_phieu = p_id_phieu and ma = p_ma;
$$;

-- Đóng phiếu — pallet chuyển 'da_xuat', tem lẻ ghi 1 dòng chuyển công đoạn
-- "Nhập kho" → "Xuất hàng" (đã xác nhận luôn, không cần bên nhận xác nhận
-- lại vì hàng đã thực sự rời khỏi nhà máy).
create or replace function kho_dong_phieu_xuat(p_id_phieu text, p_nguoi text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_item record;
  v_now timestamptz := now();
  v_count int := 0;
begin
  if not exists (select 1 from kho_phieu_xuat where id_phieu = p_id_phieu and trang_thai = 'mo') then
    raise exception 'Không tìm thấy phiếu đang mở %', p_id_phieu;
  end if;
  if not exists (select 1 from kho_phieu_xuat_item where id_phieu = p_id_phieu) then
    raise exception 'Phiếu chưa có mã nào — quét ít nhất 1 pallet/tem trước khi đóng phiếu';
  end if;

  for v_item in select * from kho_phieu_xuat_item where id_phieu = p_id_phieu loop
    if v_item.loai = 'pallet' then
      update oqc_pallet set trang_thai = 'da_xuat' where id_pallet = v_item.ma and trang_thai = 'da_nhap_kho';
      if not found then raise exception 'Pallet % không còn ở trạng thái trong kho — có thể đã xuất ở phiếu khác', v_item.ma; end if;
    else
      insert into cd_chuyen_cong_doan_log (
        id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
        cong_doan_giao, cong_doan_nhan, nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan
      ) values (
        cd_next_transfer_id(), v_now, v_item.ma, v_item.ma_sp, v_item.ten_sp, v_item.so_luong, v_item.so_luong, 0,
        'Nhập kho', 'Xuất hàng', p_nguoi, p_nguoi, 'Đã xác nhận chuyển công đoạn',
        to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
      );
    end if;
    v_count := v_count + 1;
  end loop;

  update kho_phieu_xuat set trang_thai = 'da_xuat', thoi_diem_dong = v_now, nguoi_xuat = coalesce(nguoi_xuat, p_nguoi)
  where id_phieu = p_id_phieu;

  return jsonb_build_object('ok', true, 'so_muc', v_count);
end;
$$;

-- ----------------------------------------------------------------------------
-- Row Level Security + quyền thực thi RPC.
-- ----------------------------------------------------------------------------
do $$
declare t text;
begin
  for t in select unnest(array['kho_phieu_xuat_counter', 'kho_phieu_xuat', 'kho_phieu_xuat_item'])
  loop
    execute format('alter table %I enable row level security;', t);
    execute format('drop policy if exists "public read" on %I;', t);
    execute format('create policy "public read" on %I for select using (true);', t);
  end loop;
end $$;

revoke execute on function oqc_pallet_nhap_kho(text, text) from anon;
grant execute on function oqc_pallet_nhap_kho(text, text) to authenticated;

revoke execute on function kho_nhap_kho_tem(text, text) from anon;
grant execute on function kho_nhap_kho_tem(text, text) to authenticated;

revoke execute on function kho_next_phieu_xuat_id() from anon;
grant execute on function kho_next_phieu_xuat_id() to authenticated;

revoke execute on function kho_tao_phieu_xuat(text, text, text) from anon;
grant execute on function kho_tao_phieu_xuat(text, text, text) to authenticated;

revoke execute on function kho_them_vao_phieu_xuat(text, text, text) from anon;
grant execute on function kho_them_vao_phieu_xuat(text, text, text) to authenticated;

revoke execute on function kho_xoa_khoi_phieu_xuat(text, text) from anon;
grant execute on function kho_xoa_khoi_phieu_xuat(text, text) to authenticated;

revoke execute on function kho_dong_phieu_xuat(text, text) from anon;
grant execute on function kho_dong_phieu_xuat(text, text) to authenticated;
