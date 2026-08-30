-- ============================================================================
-- Phase T25 — Bavia luồng SỬA HÀNG (giai đoạn 3)
--
-- Tem "NG chờ sửa" (duc_tem.trang_thai = 'NG chờ sửa', do bavia_xu_ly_thung
-- tạo, GĐ1) → sửa lại: ra OK (tem TKB mới) và/hoặc NG phế. Phần chưa sửa xong
-- giữ nguyên trên tem.
--
-- Thêm:
--   - bavia_sua_log : audit mỗi lần sửa
--   - bavia_sua_hang() : nguồn = 1 tem NG chờ sửa → OK tem(s) + NG phế
--
-- Ghi nhận: bavia_sua_hang cộng THẲNG vào cd_bao_cao_ca (không đụng
-- cd_tram_hien_tai) cho (ngày, ca, Bavia, mã SP) hiện tại:
--   so_luong_ok      += p_ok
--   so_luong_ng      += p_ng_phe            (NG phế)
--   so_luong_ng_sua  -= (p_ok + p_ng_phe)   (giảm phần "chờ sửa" đã giải quyết)
--   so_luong_nhan_vao += 0                  (số này đã tính ở lần xử lý gốc)
-- → tổng gộp theo mã SP luôn cân: nhận vào giữ nguyên, ng_sua tiến về 0.
--
-- Chạy trong Supabase SQL Editor. Idempotent.
-- ============================================================================

create table if not exists bavia_sua_log (
  id           bigserial primary key,
  tag_ng       text not null references duc_tem(tag_no),
  ngay         date not null,
  ca           text not null,
  cong_doan    text not null,
  ma_sp        text not null,
  so_ok        numeric not null default 0,
  so_ng_phe    numeric not null default 0,
  ly_do        text,
  nguoi        text,
  thoi_diem    timestamptz not null default now()
);
create index if not exists idx_bavia_sua_log_tag on bavia_sua_log (tag_ng);

alter table bavia_sua_log enable row level security;
drop policy if exists "public read" on bavia_sua_log;
create policy "public read" on bavia_sua_log for select using (true);

-- ── bavia_sua_hang ────────────────────────────────────────────────────────
create or replace function bavia_sua_hang(
  p_tag_ng     text,
  p_ngay       date,
  p_ca         text,
  p_cong_doan  text,
  p_ok         numeric,
  p_ng_phe     numeric,
  p_ng_ly_do   text,
  p_cach_dong  text,       -- 'nguyen' | 'quy_cach' | 'gop'
  p_quy_cach   numeric,
  p_tag_gop    text,
  p_nguoi      text,
  p_user       text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_t     duc_tem%rowtype;   -- tem "NG chờ sửa"
  v_gop   duc_tem%rowtype;   -- thùng đích khi gộp
  v_ok    numeric := coalesce(p_ok, 0);
  v_phe   numeric := coalesce(p_ng_phe, 0);
  v_can   numeric;
  v_out_tag text[] := '{}';
  v_out_qty numeric[] := '{}';
  v_tag text; v_need numeric; v_q numeric;
  j int;
  v_tems jsonb := '[]'::jsonb;
  v_lot text; v_khu text; v_nl text; v_may text; v_ngay date; v_ten_sp text; v_ma_sp text;
  v_now timestamptz := now();
begin
  if v_ok < 0 or v_phe < 0 then raise exception 'Số lượng không được âm'; end if;
  v_can := v_ok + v_phe;
  if v_can <= 0 then raise exception 'Chưa nhập OK / NG phế'; end if;
  if p_ngay is null or coalesce(trim(p_ca), '') = '' or coalesce(trim(p_cong_doan), '') = '' then
    raise exception 'Thiếu ngày / ca / công đoạn';
  end if;

  select * into v_t from duc_tem where tag_no = p_tag_ng for update;
  if not found then raise exception 'Không tìm thấy tem %', p_tag_ng; end if;
  if v_t.trang_thai is distinct from 'NG chờ sửa' then
    raise exception 'Tem % không phải "NG chờ sửa" (đang: %)', p_tag_ng, coalesce(v_t.trang_thai, '—');
  end if;
  if coalesce(v_t.so_luong, 0) <= 0 then raise exception 'Tem % đã hết số lượng', p_tag_ng; end if;
  if v_can > v_t.so_luong then
    raise exception 'OK + NG phế (%) vượt SL còn lại của tem (%)', v_can, v_t.so_luong;
  end if;

  v_lot := v_t.lot; v_khu := v_t.so_khuon; v_nl := v_t.nguyen_lieu; v_may := v_t.may_duc_chi_thi;
  v_ngay := v_t.ngay; v_ten_sp := v_t.ten_sp; v_ma_sp := v_t.ma_sp;

  -- ── Thùng OK ra ────────────────────────────────────────────────────────
  if v_ok > 0 then
    if p_cach_dong = 'gop' then
      if coalesce(trim(p_tag_gop), '') = '' then raise exception 'Chọn "gộp" thì phải chọn thùng đích'; end if;
      select * into v_gop from duc_tem where tag_no = p_tag_gop for update;
      if not found then raise exception 'Không tìm thấy thùng gộp %', p_tag_gop; end if;
      if v_gop.ma_sp is distinct from v_ma_sp then raise exception 'Thùng gộp % khác mã SP', p_tag_gop; end if;
      update duc_tem set so_luong = coalesce(so_luong, 0) + v_ok where tag_no = p_tag_gop;
      insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay)
      values (p_tag_gop, p_tag_ng, v_ok)
      on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;
      v_tems := v_tems || jsonb_build_object('tag', p_tag_gop, 'so_luong', v_ok, 'loai', 'ok_gop');
    else
      if p_cach_dong = 'quy_cach' then
        if coalesce(p_quy_cach, 0) <= 0 then raise exception 'Quy cách không hợp lệ'; end if;
        v_need := v_ok;
        while v_need > 0 loop
          v_q := least(v_need, p_quy_cach);
          v_out_tag := array_append(v_out_tag, bavia_next_tag_no());
          v_out_qty := array_append(v_out_qty, v_q);
          v_need := v_need - v_q;
        end loop;
      else
        v_out_tag := array[bavia_next_tag_no()];
        v_out_qty := array[v_ok];
      end if;

      for j in 1 .. array_length(v_out_tag, 1) loop
        insert into duc_tem (
          tag_no, ten_sp, ma_sp, so_luong, ngay, lot, so_khuon, nguyen_lieu,
          may_duc_chi_thi, ghi_chu, ngay_gio_in, so_khuon_tt, so_luong_tt, may_tt,
          nguoi_tt, trang_thai, ghi_chu_sl, tram_cong_doan, thoi_diem_san_xuat
        ) values (
          v_out_tag[j], v_ten_sp, v_ma_sp, v_out_qty[j], v_ngay,
          v_lot, v_khu, v_nl, v_may, 'Sửa hàng từ ' || p_tag_ng, v_now, v_khu, v_out_qty[j], v_may,
          coalesce(nullif(trim(p_nguoi), ''), p_user), 'Bavia', 'Sửa từ ' || p_tag_ng,
          coalesce(v_t.tram_cong_doan, p_cong_doan), v_now
        );
        insert into cd_tem_nguon (tag_no_moi, tag_no_nguon, so_luong_lay)
        values (v_out_tag[j], p_tag_ng, v_out_qty[j])
        on conflict (tag_no_moi, tag_no_nguon) do update set so_luong_lay = cd_tem_nguon.so_luong_lay + excluded.so_luong_lay;

        insert into cd_chuyen_cong_doan_log (
          id_phieu, thoi_gian_chuyen, tag_no, ma_sp, ten_sp, sl_tren_tem, sl_thuc_chuyen, chenh_lech,
          lot_no, so_khuon, nguyen_lieu, may_duc, ngay_duc, cong_doan_giao, cong_doan_nhan,
          nguoi_giao, nguoi_nhan, trang_thai_xac_nhan, ngay_gio_xac_nhan
        ) values (
          cd_next_transfer_id(), v_now, v_out_tag[j], v_ma_sp, v_ten_sp, v_out_qty[j], v_out_qty[j], 0,
          v_lot, v_khu, v_nl, v_may, coalesce(v_ngay::text, ''), p_cong_doan, p_cong_doan,
          coalesce(nullif(trim(p_nguoi), ''), p_user), coalesce(nullif(trim(p_nguoi), ''), p_user),
          'Đã xác nhận chuyển công đoạn', to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
        );
        v_tems := v_tems || jsonb_build_object('tag', v_out_tag[j], 'so_luong', v_out_qty[j], 'loai', 'ok');
      end loop;
    end if;
  end if;

  -- ── Trừ SL tem NG chờ sửa + đổi trạng thái nếu hết ────────────────────
  update duc_tem set
    so_luong = coalesce(so_luong, 0) - v_can,
    trang_thai = case when coalesce(so_luong, 0) - v_can <= 0 then 'Đã sửa xong' else 'NG chờ sửa' end
  where tag_no = p_tag_ng;

  -- ── Ghi nhận vào cd_bao_cao_ca (ngày/ca hiện tại) ─────────────────────
  perform cd_gop_tally_vao_bao_cao(
    p_ngay, p_ca, p_cong_doan, v_ma_sp, v_ten_sp, coalesce(v_t.tram_cong_doan, ''),
    v_ok, v_phe, 'Sửa hàng từ ' || p_tag_ng || case when coalesce(trim(p_ng_ly_do),'') <> '' then ' — ' || trim(p_ng_ly_do) else '' end,
    -(v_ok + v_phe)
  );

  insert into bavia_sua_log (tag_ng, ngay, ca, cong_doan, ma_sp, so_ok, so_ng_phe, ly_do, nguoi)
  values (p_tag_ng, p_ngay, p_ca, p_cong_doan, v_ma_sp, v_ok, v_phe, nullif(trim(p_ng_ly_do), ''),
          coalesce(nullif(trim(p_nguoi), ''), p_user));

  return jsonb_build_object('ok', true, 'tems', v_tems, 'con_lai_tem_ng', greatest(0, coalesce(v_t.so_luong, 0) - v_can));
end;
$$;
revoke execute on function bavia_sua_hang(text, date, text, text, numeric, numeric, text, text, numeric, text, text, text) from anon;
grant  execute on function bavia_sua_hang(text, date, text, text, numeric, numeric, text, text, numeric, text, text, text) to authenticated;

-- Kiểm tra nhanh
-- select tag_no, so_luong, trang_thai from duc_tem where trang_thai in ('NG chờ sửa','Đã sửa xong');
-- select * from bavia_sua_log order by id desc limit 5;
