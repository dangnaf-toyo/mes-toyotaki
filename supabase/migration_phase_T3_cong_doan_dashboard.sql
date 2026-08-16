-- ============================================================================
-- Phase T3 — Dashboard công đoạn dùng chung (Bavia/Gia công/Sơn/OQC): trạm/tổ
-- lao động thủ công, sản lượng OK/NG cộng dồn REAL-TIME xuyên ca, nhân sự.
-- Theo kế hoạch đã duyệt.
--
-- 2 lớp tách biệt, không trộn: lớp truy xuất theo tem (chuyencongdoan.html,
-- không đổi gì ở đây) và lớp tổ chức sản xuất/kế toán sản lượng (mới, ở đây)
-- — trạm KHÔNG link cứng theo tag_no, chỉ là bảng tính sổ trưởng ca tự đối
-- chiếu bằng mắt với hàng thực tế (card "Hàng đang chờ" trên dashboard đọc
-- cd_v_vi_tri_hien_tai chỉ để tham khảo).
--
-- cd_bao_cao_ca (đã có, migration_phase_T2) là điểm hội tụ: dashboard mới ghi
-- CỘNG DỒN vào đó (khác cd_luu_bao_cao_ca hiện có — ghi ĐÈ, dùng cho nhập tay
-- 1 lần dự phòng, giữ nguyên không đổi).
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create table if not exists cd_tram_hien_tai (
  id_tram         text primary key,   -- sinh xác định từ cong_doan+ngay+ca+ten_tram
  ngay            date not null,
  ca              text not null,
  cong_doan       text not null,
  ten_tram        text not null,
  ma_sp           text not null,
  ten_sp          text default '',
  nguoi_thao_tac  text default '',
  so_luong_ok     numeric not null default 0,
  so_luong_ng     numeric not null default 0,
  ghi_chu         text default '',
  version         bigint not null default 1,
  last_updated_by text,
  last_updated_at timestamptz not null default now()
);
create index if not exists idx_cd_tram_hien_tai_loc on cd_tram_hien_tai (cong_doan, ngay, ca);

-- ── Hàm nội bộ: gộp (CỘNG DỒN) tally vào cd_bao_cao_ca ──────────────────────
create or replace function cd_gop_tally_vao_bao_cao(
  p_ngay date, p_ca text, p_cong_doan text, p_ma_sp text, p_ten_sp text, p_to text,
  p_ok numeric, p_ng numeric, p_ghi_chu text
)
returns void
language plpgsql
security definer
as $$
declare
  v_id text;
  v_stamp text;
  v_note text;
begin
  v_id := to_char(p_ngay, 'DDMMYYYY') || '_' || duc_normalize_name(p_ca) || '_' || duc_normalize_name(p_cong_doan) || '_' || duc_normalize_name(p_ma_sp) ||
    case when coalesce(p_to, '') <> '' then '_' || duc_normalize_name(p_to) else '' end;
  v_stamp := to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DD/MM HH24:MI');
  v_note := case when coalesce(p_ghi_chu, '') <> '' then '[' || v_stamp || '] ' || trim(p_ghi_chu) else null end;

  insert into cd_bao_cao_ca (
    id_bao_cao, ngay, ca, cong_doan, ma_sp, ten_sp, to_san_xuat,
    so_luong_nhan_vao, so_luong_ok, so_luong_ng, ghi_chu, thoi_diem_luu
  ) values (
    v_id, p_ngay, p_ca, p_cong_doan, p_ma_sp, coalesce(p_ten_sp, ''), coalesce(p_to, ''),
    coalesce(p_ok, 0) + coalesce(p_ng, 0), coalesce(p_ok, 0), coalesce(p_ng, 0), v_note, now()
  )
  on conflict (id_bao_cao) do update set
    so_luong_nhan_vao = cd_bao_cao_ca.so_luong_nhan_vao + excluded.so_luong_nhan_vao,
    so_luong_ok = cd_bao_cao_ca.so_luong_ok + excluded.so_luong_ok,
    so_luong_ng = cd_bao_cao_ca.so_luong_ng + excluded.so_luong_ng,
    ten_sp = coalesce(nullif(excluded.ten_sp, ''), cd_bao_cao_ca.ten_sp),
    ghi_chu = case when v_note is null then cd_bao_cao_ca.ghi_chu
                   when coalesce(cd_bao_cao_ca.ghi_chu, '') = '' then v_note
                   else cd_bao_cao_ca.ghi_chu || E'\n' || v_note end,
    thoi_diem_luu = now();
end;
$$;

-- ── Tạo/gán trạm (giữ nguyên tally nếu trạm đã tồn tại) ─────────────────────
create or replace function cd_tram_tao(
  p_ngay date, p_ca text, p_cong_doan text, p_ten_tram text, p_ma_sp text, p_ten_sp text, p_nguoi text, p_user text
)
returns text
language plpgsql
security definer
as $$
declare
  v_id text;
begin
  if p_ten_tram is null or trim(p_ten_tram) = '' then raise exception 'Thiếu tên trạm'; end if;
  if p_ma_sp is null or trim(p_ma_sp) = '' then raise exception 'Thiếu mã SP'; end if;
  v_id := duc_normalize_name(p_cong_doan) || '_' || to_char(p_ngay, 'DDMMYYYY') || '_' || duc_normalize_name(p_ca) || '_' || duc_normalize_name(p_ten_tram);

  insert into cd_tram_hien_tai (id_tram, ngay, ca, cong_doan, ten_tram, ma_sp, ten_sp, nguoi_thao_tac, version, last_updated_by, last_updated_at)
  values (v_id, p_ngay, p_ca, p_cong_doan, trim(p_ten_tram), p_ma_sp, coalesce(p_ten_sp, ''), coalesce(p_nguoi, ''), 1, p_user, now())
  on conflict (id_tram) do update set
    ma_sp = excluded.ma_sp, ten_sp = excluded.ten_sp, nguoi_thao_tac = excluded.nguoi_thao_tac,
    version = cd_tram_hien_tai.version + 1, last_updated_by = excluded.last_updated_by, last_updated_at = now();

  return v_id;
end;
$$;

-- ── Nhập sản lượng — CỘNG THÊM vào trạm, lặp lại nhiều lần trong ca ─────────
create or replace function cd_tram_nhap_sanluong(
  p_id_tram text, p_them_ok numeric, p_them_ng numeric, p_ghi_chu text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_ok numeric := coalesce(p_them_ok, 0);
  v_ng numeric := coalesce(p_them_ng, 0);
  v_stamp text;
  v_note text;
  v_row cd_tram_hien_tai%rowtype;
begin
  if v_ok <= 0 and v_ng <= 0 then raise exception 'Phải nhập số OK hoặc NG lớn hơn 0'; end if;

  select * into v_row from cd_tram_hien_tai where id_tram = p_id_tram for update;
  if not found then raise exception 'Không tìm thấy trạm %', p_id_tram; end if;

  v_note := v_row.ghi_chu;
  if coalesce(p_ghi_chu, '') <> '' then
    v_stamp := to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DD/MM HH24:MI');
    v_note := coalesce(v_note, '') || (case when coalesce(v_note, '') <> '' then E'\n' else '' end) || '[' || v_stamp || '] ' || trim(p_ghi_chu);
  end if;

  update cd_tram_hien_tai set
    so_luong_ok = so_luong_ok + v_ok, so_luong_ng = so_luong_ng + v_ng, ghi_chu = v_note,
    version = version + 1, last_updated_by = p_user, last_updated_at = now()
  where id_tram = p_id_tram
  returning * into v_row;

  return jsonb_build_object('ok', true, 'id_tram', p_id_tram, 'so_luong_ok', v_row.so_luong_ok, 'so_luong_ng', v_row.so_luong_ng);
end;
$$;

-- ── Đổi mã SP trên 1 trạm — gộp tally cũ vào báo cáo trước khi reset ────────
create or replace function cd_tram_doi_ma_sp(
  p_id_tram text, p_ma_sp_moi text, p_ten_sp_moi text, p_nguoi_moi text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row cd_tram_hien_tai%rowtype;
begin
  if p_ma_sp_moi is null or trim(p_ma_sp_moi) = '' then raise exception 'Thiếu mã SP mới'; end if;

  select * into v_row from cd_tram_hien_tai where id_tram = p_id_tram for update;
  if not found then raise exception 'Không tìm thấy trạm %', p_id_tram; end if;

  if coalesce(v_row.so_luong_ok, 0) > 0 or coalesce(v_row.so_luong_ng, 0) > 0 then
    perform cd_gop_tally_vao_bao_cao(v_row.ngay, v_row.ca, v_row.cong_doan, v_row.ma_sp, v_row.ten_sp, v_row.ten_tram, v_row.so_luong_ok, v_row.so_luong_ng, v_row.ghi_chu);
  end if;

  update cd_tram_hien_tai set
    ma_sp = p_ma_sp_moi, ten_sp = coalesce(p_ten_sp_moi, ''),
    nguoi_thao_tac = coalesce(nullif(p_nguoi_moi, ''), nguoi_thao_tac),
    so_luong_ok = 0, so_luong_ng = 0, ghi_chu = '',
    version = version + 1, last_updated_by = p_user, last_updated_at = now()
  where id_tram = p_id_tram;

  return jsonb_build_object('ok', true, 'id_tram', p_id_tram);
end;
$$;

-- ── Kết thúc 1 trạm (không dùng nữa hôm nay) — gộp tally rồi xoá ────────────
create or replace function cd_tram_ket_thuc(p_id_tram text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row cd_tram_hien_tai%rowtype;
begin
  select * into v_row from cd_tram_hien_tai where id_tram = p_id_tram for update;
  if not found then raise exception 'Không tìm thấy trạm %', p_id_tram; end if;

  if coalesce(v_row.so_luong_ok, 0) > 0 or coalesce(v_row.so_luong_ng, 0) > 0 then
    perform cd_gop_tally_vao_bao_cao(v_row.ngay, v_row.ca, v_row.cong_doan, v_row.ma_sp, v_row.ten_sp, v_row.ten_tram, v_row.so_luong_ok, v_row.so_luong_ng, v_row.ghi_chu);
  end if;

  delete from cd_tram_hien_tai where id_tram = p_id_tram;
  return jsonb_build_object('ok', true);
end;
$$;

-- ── Kết ca — gộp tally toàn bộ trạm của đúng (ngày,ca,công đoạn), xoá hết,
-- trả về bảng tổng hợp theo mã SP để hiện báo cáo ngay ───────────────────────
create or replace function cd_ket_ca_cong_doan(p_ngay date, p_ca text, p_cong_doan text, p_user text)
returns table(ma_sp text, ten_sp text, so_luong_nhan_vao numeric, so_luong_ok numeric, so_luong_ng numeric)
language plpgsql
security definer
as $$
declare
  v_tram cd_tram_hien_tai%rowtype;
begin
  for v_tram in select * from cd_tram_hien_tai where ngay = p_ngay and ca = p_ca and cong_doan = p_cong_doan loop
    if coalesce(v_tram.so_luong_ok, 0) > 0 or coalesce(v_tram.so_luong_ng, 0) > 0 then
      perform cd_gop_tally_vao_bao_cao(v_tram.ngay, v_tram.ca, v_tram.cong_doan, v_tram.ma_sp, v_tram.ten_sp, v_tram.ten_tram, v_tram.so_luong_ok, v_tram.so_luong_ng, v_tram.ghi_chu);
    end if;
  end loop;

  delete from cd_tram_hien_tai where ngay = p_ngay and ca = p_ca and cong_doan = p_cong_doan;

  return query
    select b.ma_sp, max(b.ten_sp), sum(b.so_luong_nhan_vao), sum(b.so_luong_ok), sum(b.so_luong_ng)
    from cd_bao_cao_ca b
    where b.ngay = p_ngay and b.ca = p_ca and b.cong_doan = p_cong_doan
    group by b.ma_sp
    order by b.ma_sp;
end;
$$;

-- ----------------------------------------------------------------------------
-- Row Level Security + quyền thực thi RPC — theo đúng pattern các module khác.
-- ----------------------------------------------------------------------------
alter table cd_tram_hien_tai enable row level security;
drop policy if exists "public read" on cd_tram_hien_tai;
create policy "public read" on cd_tram_hien_tai for select using (true);

revoke execute on function cd_gop_tally_vao_bao_cao(date, text, text, text, text, text, numeric, numeric, text) from anon;
grant execute on function cd_gop_tally_vao_bao_cao(date, text, text, text, text, text, numeric, numeric, text) to authenticated;

revoke execute on function cd_tram_tao(date, text, text, text, text, text, text, text) from anon;
grant execute on function cd_tram_tao(date, text, text, text, text, text, text, text) to authenticated;

revoke execute on function cd_tram_nhap_sanluong(text, numeric, numeric, text, text) from anon;
grant execute on function cd_tram_nhap_sanluong(text, numeric, numeric, text, text) to authenticated;

revoke execute on function cd_tram_doi_ma_sp(text, text, text, text, text) from anon;
grant execute on function cd_tram_doi_ma_sp(text, text, text, text, text) to authenticated;

revoke execute on function cd_tram_ket_thuc(text, text) from anon;
grant execute on function cd_tram_ket_thuc(text, text) to authenticated;

revoke execute on function cd_ket_ca_cong_doan(date, text, text, text) from anon;
grant execute on function cd_ket_ca_cong_doan(date, text, text, text) to authenticated;
