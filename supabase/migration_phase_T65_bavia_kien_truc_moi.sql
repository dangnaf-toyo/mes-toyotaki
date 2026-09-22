-- ============================================================================
-- Phase T65 — Bavia: chuyển sang kiến trúc "in tem trước + quét ghi nhận"
-- (giống Đánh bóng Kẽm, xem KE_HOACH_TINH_NANG_MOI.md).
--
-- Luồng OK giờ dùng lại nguyên xi cd_khai_bao_nguon_dang_dung /
-- cd_ton_kho_theo_ma_sp / cd_tao_lo_tem_thanh_pham / cd_ghi_nhan_tem_thanh_pham
-- (đã tổng quát theo p_cong_doan, KHÔNG cần sửa SQL). bavia_xu_ly_thung được
-- coi là DEPRECATED từ T65 (không xoá — dữ liệu lịch sử bavia_xu_ly/
-- bavia_xu_ly_nguon/bavia_xu_ly_ra vẫn cần cho Đối soát tra tem cũ).
--
-- Việc duy nhất còn thiếu: luồng "Báo NG cần sửa" trước đây nằm chung trong
-- bavia_xu_ly_thung (nhập số NG sửa cùng lúc với OK) — nay tách thành thao
-- tác độc lập ngay trên tem nguồn đang dùng (giống nút "⚠ Báo NG" của Đánh
-- bóng Kẽm, nhưng tạo tem "NG chờ sửa" thay vì trừ thẳng). RPC mới dưới đây
-- copy đúng logic tạo tem NG chờ sửa trong bavia_xu_ly_thung (T27, đoạn
-- "if v_sua > 0 then ..."), rút gọn cho 1 tem nguồn duy nhất.
--
-- bavia_sua_hang / bavia_gom_ng_cho_sua / bavia_undo_* / Đối soát: KHÔNG đổi
-- gì — chúng chỉ cần tem có trang_thai='NG chờ sửa', không quan tâm tem đó
-- sinh ra từ bavia_xu_ly_thung (dữ liệu cũ) hay bavia_bao_ng_cho_sua (mới).
--
-- Chạy trong Supabase SQL Editor. Idempotent.
-- ============================================================================

create table if not exists bavia_bao_ng_log (
  id           bigint generated always as identity primary key,
  tag_nguon    text not null,
  tag_ra       text not null,
  so_luong     numeric not null check (so_luong > 0),
  ly_do        text not null,
  nguoi        text,
  created_at   timestamptz not null default now(),
  client_key   text
);
alter table bavia_bao_ng_log enable row level security;
drop policy if exists "public read" on bavia_bao_ng_log;
create policy "public read" on bavia_bao_ng_log for select using (true);
create unique index if not exists ux_bavia_bao_ng_log_ckey on bavia_bao_ng_log(client_key) where client_key is not null;

drop function if exists bavia_bao_ng_cho_sua(text, numeric, text, text, text, text);
create or replace function bavia_bao_ng_cho_sua(
  p_tag_nguon  text,
  p_so_luong   numeric,
  p_ly_do      text,
  p_nguoi      text,
  p_user       text,
  p_client_key text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_src duc_tem%rowtype;
  v_tag text;
  v_now timestamptz := now();
  v_key text := nullif(trim(p_client_key), '');
begin
  if coalesce(p_so_luong, 0) <= 0 then raise exception 'Số lượng phải lớn hơn 0'; end if;
  if coalesce(trim(p_ly_do), '') = '' then raise exception 'Phải nhập lý do NG'; end if;

  -- dedup: gọi lại cùng key → trả kết quả cũ, không tạo tem lần 2
  if v_key is not null and exists(select 1 from bavia_bao_ng_log where client_key = v_key) then
    select tag_ra, so_luong into v_tag, p_so_luong from bavia_bao_ng_log where client_key = v_key;
    return jsonb_build_object('ok', true, 'tag_ra', v_tag, 'so_luong', p_so_luong, 'duplicate', true);
  end if;

  select * into v_src from duc_tem where tag_no = p_tag_nguon for update;
  if not found then raise exception 'Không tìm thấy tem %', p_tag_nguon; end if;
  if coalesce(v_src.so_luong, 0) <= 0 then raise exception 'Tem % đã hết số lượng', p_tag_nguon; end if;
  if p_so_luong > v_src.so_luong then
    raise exception 'Số lượng NG (%) vượt SL còn lại của tem (%)', p_so_luong, v_src.so_luong;
  end if;

  v_tag := bavia_next_tag_no();
  insert into duc_tem (
    tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
    may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
    nguoi_tt, trang_thai, ghi_chu_sl, tram_cong_doan, thoi_diem_san_xuat
  ) values (
    v_tag, v_src.ten_sp, v_src.ma_sp, p_so_luong, v_src.ngay,
    v_src.lot, v_src.so_khuon, v_src.nguyen_lieu, v_src.may_duc_chi_thi,
    'NG chờ sửa (Bavia) — ' || trim(p_ly_do), v_now, v_src.so_khuon, p_so_luong, v_src.may_duc_chi_thi,
    coalesce(nullif(trim(p_nguoi), ''), p_user), 'NG chờ sửa', 'Bavia báo NG từ ' || p_tag_nguon,
    v_src.tram_cong_doan, v_now
  );

  insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay)
  values (v_tag, p_tag_nguon, p_so_luong)
  on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;

  update duc_tem set so_luong = coalesce(so_luong, 0) - p_so_luong where tag_no = p_tag_nguon;

  insert into cd_chuyen_cong_doan_log (
    id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
    lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan,
    nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan
  ) values (
    cd_next_transfer_id(), v_now, v_tag, v_src.ma_sp, v_src.ten_sp, p_so_luong, p_so_luong, 0,
    v_src.lot, v_src.so_khuon, v_src.nguyen_lieu, v_src.may_duc_chi_thi, coalesce(v_src.ngay::text, ''),
    'Bavia', 'Bavia',
    coalesce(nullif(trim(p_nguoi), ''), p_user), coalesce(nullif(trim(p_nguoi), ''), p_user),
    'Đã xác nhận chuyển công đoạn', to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
  );

  insert into bavia_bao_ng_log (tag_nguon, tag_ra, so_luong, ly_do, nguoi, client_key)
  values (p_tag_nguon, v_tag, p_so_luong, trim(p_ly_do), coalesce(nullif(trim(p_nguoi), ''), p_user), v_key);

  return jsonb_build_object('ok', true, 'tag_ra', v_tag, 'so_luong', p_so_luong,
    'so_luong_con_lai', coalesce(v_src.so_luong, 0) - p_so_luong);
end;
$$;
revoke execute on function bavia_bao_ng_cho_sua(text, numeric, text, text, text, text) from anon;
grant  execute on function bavia_bao_ng_cho_sua(text, numeric, text, text, text, text) to authenticated;
