-- ============================================================================
-- Phase 4, bước con 6 (cutover ghi) — Ncp.js (quản lý xử lý SP không phù hợp),
-- 11 hàm ghi + 1 hàm đọc tổng hợp, viết lại thành RPC Postgres.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
--
-- Ảnh (uploadNcpRootCauseImage_): KHÔNG cần RPC riêng — trình duyệt tự upload
-- thẳng lên Supabase Storage bucket "ipqc-evidence" (dùng chung, đã tạo ở D0),
-- lấy URL, rồi truyền vào duc_ncp_update_root_cause qua các mảng hinh_anh_*.
-- ============================================================================

-- ── Helper: tính trạng thái quy trình từ số liệu thô (_ncpTinhTrangThai_) ──
create or replace function duc_ncp_tinh_trang_thai(
  p_so_luong_da_loc numeric, p_so_luong_nghi_van numeric, p_so_luong_loc_ng numeric,
  p_so_luong_sua_ok numeric, p_so_luong_phe_da_duyet numeric
)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_da_loc_het boolean;
  v_pool_con_lai numeric;
begin
  v_da_loc_het := p_so_luong_da_loc >= p_so_luong_nghi_van;
  v_pool_con_lai := p_so_luong_loc_ng - p_so_luong_sua_ok - p_so_luong_phe_da_duyet;
  if not v_da_loc_het then
    return jsonb_build_object('pool_con_lai', v_pool_con_lai,
      'trang_thai', case when p_so_luong_da_loc > 0 then 'dang_loc' else 'da_cach_ly' end);
  end if;
  if v_pool_con_lai <= 0 then
    return jsonb_build_object('pool_con_lai', v_pool_con_lai, 'trang_thai', 'dong');
  end if;
  return jsonb_build_object('pool_con_lai', v_pool_con_lai, 'trang_thai', 'cho_quyet_dinh');
end;
$$;

-- ── Helper: sinh "số quản lý phiếu" ddMMyyyy-STT, STT riêng theo từng ngày ──
create table if not exists duc_ncp_id_counter (
  ngay date primary key,
  last_seq int not null default 0
);
create or replace function duc_ncp_so_quan_ly_moi()
returns text
language plpgsql
security definer
as $$
declare
  d date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  v_seq int;
begin
  insert into duc_ncp_id_counter (ngay, last_seq) values (d, 1)
  on conflict (ngay) do update set last_seq = duc_ncp_id_counter.last_seq + 1
  returning last_seq into v_seq;
  return to_char(d, 'DDMMYYYY') || '-' || lpad(v_seq::text, 2, '0');
end;
$$;

-- ── Helper: append log có timestamp vào ghi_chu (_ncpAppendLog_) ──────────
create or replace function duc_ncp_append_log(p_id_ncp text, p_text text)
returns void
language plpgsql
as $$
declare
  v_current text;
  v_stamp text := to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DD/MM HH24:MI');
begin
  select coalesce(ghi_chu, '') into v_current from duc_ncp where id_ncp = p_id_ncp;
  update duc_ncp set ghi_chu = v_current || (case when v_current <> '' then E'\n' else '' end) || '[' || v_stamp || '] ' || p_text
  where id_ncp = p_id_ncp;
end;
$$;

-- ── openNcpCase_ ─────────────────────────────────────────────────────────
create or replace function duc_ncp_open_case(
  p_id_checkpoint_goc text, p_ma_may text, p_ma_sp text, p_ten_sp text, p_so_khuon text,
  p_mo_ta_loi text, p_so_luong_nghi_van numeric, p_so_luong_ng_du_kien numeric,
  p_vi_tri_cach_ly text, p_nguoi_dam_nhiem text, p_nguoi_dam_nhiem_doi_sach text, p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_id_ncp text;
  v_existing text;
  v_now timestamptz := now();
begin
  if p_so_luong_nghi_van is null or p_so_luong_nghi_van <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Số lượng nghi vấn phải là số dương');
  end if;
  if p_so_luong_ng_du_kien is null or p_so_luong_ng_du_kien < 0 then
    return jsonb_build_object('ok', false, 'error', 'Số lượng NG dự kiến không được âm');
  end if;
  if p_so_luong_ng_du_kien > p_so_luong_nghi_van then
    return jsonb_build_object('ok', false, 'error', 'Số lượng NG dự kiến không được vượt quá số lượng nghi vấn');
  end if;

  if p_id_checkpoint_goc is not null and p_id_checkpoint_goc <> '' then
    select id_ncp_lien_quan into v_existing from duc_ipqc_checkpoint where id_checkpoint = p_id_checkpoint_goc;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'Không tìm thấy điểm kiểm gốc: ' || p_id_checkpoint_goc);
    end if;
    if v_existing is not null and v_existing <> '' then
      return jsonb_build_object('ok', false, 'error', 'Điểm kiểm này đã có phiếu xử lý (' || v_existing || ') — không mở trùng.');
    end if;
  end if;

  v_id_ncp := duc_ncp_so_quan_ly_moi();

  insert into duc_ncp (
    id_ncp, id_checkpoint_goc, ngay_tao, ma_may, ma_sp, ten_sp, so_khuon, mo_ta_loi,
    so_luong_nghi_van, so_luong_ng_du_kien, vi_tri_cach_ly, nguoi_mo_case,
    nguoi_dam_nhiem, nguoi_dam_nhiem_doi_sach,
    so_luong_da_loc, so_luong_loc_ok, so_luong_loc_ng, so_luong_sua_ok, so_luong_sua_khong_duoc,
    so_luong_de_nghi_phe, so_luong_phe_da_duyet, trang_thai, rc_trang_thai_duyet, ghi_chu, last_updated_at
  ) values (
    v_id_ncp, nullif(p_id_checkpoint_goc, ''), v_now, p_ma_may, p_ma_sp, p_ten_sp, p_so_khuon, trim(p_mo_ta_loi),
    p_so_luong_nghi_van, p_so_luong_ng_du_kien, trim(p_vi_tri_cach_ly), p_user,
    trim(p_nguoi_dam_nhiem), trim(p_nguoi_dam_nhiem_doi_sach),
    0, 0, 0, 0, 0, 0, 0, 'da_cach_ly', 'nhap',
    '[' || to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM HH24:MI') || '] Mở phiếu, cách ly ' ||
      p_so_luong_nghi_van || ' SP tại "' || trim(p_vi_tri_cach_ly) || '" — bởi ' || p_user,
    v_now
  );

  if p_id_checkpoint_goc is not null and p_id_checkpoint_goc <> '' then
    update duc_ipqc_checkpoint set id_ncp_lien_quan = v_id_ncp where id_checkpoint = p_id_checkpoint_goc;
  end if;

  return jsonb_build_object('ok', true, 'id_ncp', v_id_ncp);
end;
$$;
revoke execute on function duc_ncp_open_case(text, text, text, text, text, text, numeric, numeric, text, text, text, text) from anon;
grant execute on function duc_ncp_open_case(text, text, text, text, text, text, numeric, numeric, text, text, text, text) to authenticated;

-- ── recordSortingResult_ ─────────────────────────────────────────────────
create or replace function duc_ncp_record_sorting(p_id_ncp text, p_so_luong_loc_ok numeric, p_so_luong_loc_ng numeric, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_d record;
  v_ok numeric := coalesce(p_so_luong_loc_ok, 0);
  v_ng numeric := coalesce(p_so_luong_loc_ng, 0);
  v_da_loc_moi numeric;
  v_tt jsonb;
  v_now timestamptz := now();
begin
  if v_ok < 0 or v_ng < 0 then return jsonb_build_object('ok', false, 'error', 'Số lượng không được âm'); end if;
  if v_ok + v_ng <= 0 then return jsonb_build_object('ok', false, 'error', 'Phải nhập số lượng OK hoặc NG của đợt lọc này'); end if;

  select * into v_d from duc_ncp where id_ncp = p_id_ncp;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu: ' || p_id_ncp); end if;
  if v_d.trang_thai = 'dong' then return jsonb_build_object('ok', false, 'error', 'Phiếu này đã đóng, không thể cập nhật thêm'); end if;

  v_da_loc_moi := v_d.so_luong_da_loc + v_ok + v_ng;
  if v_da_loc_moi > v_d.so_luong_nghi_van then
    return jsonb_build_object('ok', false, 'error', 'Tổng số đã lọc (' || v_da_loc_moi || ') vượt quá số lượng nghi vấn (' || v_d.so_luong_nghi_van || ')');
  end if;

  v_tt := duc_ncp_tinh_trang_thai(v_da_loc_moi, v_d.so_luong_nghi_van, v_d.so_luong_loc_ng + v_ng, v_d.so_luong_sua_ok, v_d.so_luong_phe_da_duyet);

  update duc_ncp set
    so_luong_da_loc = v_da_loc_moi, so_luong_loc_ok = so_luong_loc_ok + v_ok, so_luong_loc_ng = so_luong_loc_ng + v_ng,
    nguoi_loc = p_user, thoi_diem_loc = v_now, trang_thai = v_tt->>'trang_thai', last_updated_at = v_now
  where id_ncp = p_id_ncp;

  perform duc_ncp_append_log(p_id_ncp, 'Lọc: +' || v_ok || ' OK, +' || v_ng || ' NG (tổng đã lọc ' || v_da_loc_moi || '/' || v_d.so_luong_nghi_van || ') — bởi ' || p_user);

  return jsonb_build_object('ok', true, 'id_ncp', p_id_ncp, 'trang_thai', v_tt->>'trang_thai');
end;
$$;
revoke execute on function duc_ncp_record_sorting(text, numeric, numeric, text) from anon;
grant execute on function duc_ncp_record_sorting(text, numeric, numeric, text) to authenticated;

-- ── choosePhuongAnSua_ ───────────────────────────────────────────────────
create or replace function duc_ncp_choose_sua(p_id_ncp text, p_mo_ta_phuong_an_sua text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_trang_thai text;
  v_now timestamptz := now();
begin
  if p_mo_ta_phuong_an_sua is null or trim(p_mo_ta_phuong_an_sua) = '' then
    return jsonb_build_object('ok', false, 'error', 'Chưa nhập mô tả phương án sửa chữa');
  end if;
  select trang_thai into v_trang_thai from duc_ncp where id_ncp = p_id_ncp;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu: ' || p_id_ncp); end if;
  if v_trang_thai <> 'cho_quyet_dinh' then
    return jsonb_build_object('ok', false, 'error', 'Phiếu không ở trạng thái chờ quyết định phương án');
  end if;

  update duc_ncp set phuong_an_ng = 'sua', mo_ta_phuong_an_sua = trim(p_mo_ta_phuong_an_sua),
    trang_thai = 'dang_sua', last_updated_at = v_now
  where id_ncp = p_id_ncp;
  perform duc_ncp_append_log(p_id_ncp, 'Chọn phương án SỬA CHỮA: ' || p_mo_ta_phuong_an_sua || ' — bởi ' || p_user);

  return jsonb_build_object('ok', true, 'id_ncp', p_id_ncp, 'trang_thai', 'dang_sua');
end;
$$;
revoke execute on function duc_ncp_choose_sua(text, text, text) from anon;
grant execute on function duc_ncp_choose_sua(text, text, text) to authenticated;

-- ── recordRepairResult_ ──────────────────────────────────────────────────
create or replace function duc_ncp_record_repair(p_id_ncp text, p_so_luong_sua_ok numeric, p_so_luong_sua_khong_duoc numeric, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_d record;
  v_ok numeric := coalesce(p_so_luong_sua_ok, 0);
  v_khong_duoc numeric := coalesce(p_so_luong_sua_khong_duoc, 0);
  v_pool_truoc numeric;
  v_sua_ok_moi numeric;
  v_tt jsonb;
  v_now timestamptz := now();
begin
  if v_ok < 0 or v_khong_duoc < 0 then return jsonb_build_object('ok', false, 'error', 'Số lượng không được âm'); end if;
  if v_ok + v_khong_duoc <= 0 then return jsonb_build_object('ok', false, 'error', 'Phải nhập số lượng sửa OK hoặc không sửa được của đợt này'); end if;

  select * into v_d from duc_ncp where id_ncp = p_id_ncp;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu: ' || p_id_ncp); end if;
  if v_d.trang_thai <> 'dang_sua' then return jsonb_build_object('ok', false, 'error', 'Phiếu không ở trạng thái đang sửa chữa'); end if;

  v_pool_truoc := v_d.so_luong_loc_ng - v_d.so_luong_sua_ok - v_d.so_luong_phe_da_duyet;
  if v_ok + v_khong_duoc > v_pool_truoc then
    return jsonb_build_object('ok', false, 'error', 'Số lượng vừa nhập (' || (v_ok + v_khong_duoc) || ') vượt quá số NG còn tồn đọng (' || v_pool_truoc || ')');
  end if;

  v_sua_ok_moi := v_d.so_luong_sua_ok + v_ok;
  v_tt := duc_ncp_tinh_trang_thai(v_d.so_luong_da_loc, v_d.so_luong_nghi_van, v_d.so_luong_loc_ng, v_sua_ok_moi, v_d.so_luong_phe_da_duyet);

  update duc_ncp set
    so_luong_sua_ok = v_sua_ok_moi, so_luong_sua_khong_duoc = so_luong_sua_khong_duoc + v_khong_duoc,
    nguoi_sua = p_user, thoi_diem_sua = v_now, trang_thai = v_tt->>'trang_thai', last_updated_at = v_now
  where id_ncp = p_id_ncp;
  perform duc_ncp_append_log(p_id_ncp, 'Sửa chữa: +' || v_ok || ' OK, +' || v_khong_duoc || ' không sửa được — bởi ' || p_user);

  return jsonb_build_object('ok', true, 'id_ncp', p_id_ncp, 'trang_thai', v_tt->>'trang_thai');
end;
$$;
revoke execute on function duc_ncp_record_repair(text, numeric, numeric, text) from anon;
grant execute on function duc_ncp_record_repair(text, numeric, numeric, text) to authenticated;

-- ── requestScrap_ ────────────────────────────────────────────────────────
create or replace function duc_ncp_request_scrap(p_id_ncp text, p_so_luong_de_nghi_phe numeric, p_ly_do_phe text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_d record;
  v_pool_con_lai numeric;
  v_so_phieu text;
  v_now timestamptz := now();
begin
  if p_ly_do_phe is null or trim(p_ly_do_phe) = '' then return jsonb_build_object('ok', false, 'error', 'Chưa nhập lý do báo phế'); end if;
  if p_so_luong_de_nghi_phe is null or p_so_luong_de_nghi_phe <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Số lượng đề nghị phế phải là số dương');
  end if;

  select * into v_d from duc_ncp where id_ncp = p_id_ncp;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu: ' || p_id_ncp); end if;
  if v_d.trang_thai <> 'cho_quyet_dinh' then return jsonb_build_object('ok', false, 'error', 'Phiếu không ở trạng thái chờ quyết định phương án'); end if;

  v_pool_con_lai := v_d.so_luong_loc_ng - v_d.so_luong_sua_ok - v_d.so_luong_phe_da_duyet;
  if p_so_luong_de_nghi_phe > v_pool_con_lai then
    return jsonb_build_object('ok', false, 'error', 'Số lượng đề nghị phế (' || p_so_luong_de_nghi_phe || ') vượt quá số NG còn tồn đọng (' || v_pool_con_lai || ')');
  end if;

  v_so_phieu := 'PBP_' || to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DDMMYYYY_HH24MISS') || '_' || duc_normalize_name(v_d.ma_may);

  update duc_ncp set
    phuong_an_ng = 'bao_phe', so_phieu_phe = v_so_phieu, so_luong_de_nghi_phe = p_so_luong_de_nghi_phe,
    ly_do_phe = trim(p_ly_do_phe), nguoi_de_nghi_phe = p_user, thoi_diem_de_nghi_phe = v_now,
    ket_qua_duyet_phe = '', trang_thai = 'cho_duyet_phe', last_updated_at = v_now
  where id_ncp = p_id_ncp;
  perform duc_ncp_append_log(p_id_ncp, 'Đề nghị báo phế ' || p_so_luong_de_nghi_phe || ' SP (phiếu ' || v_so_phieu || ') — lý do: ' || p_ly_do_phe || ' — bởi ' || p_user);

  return jsonb_build_object('ok', true, 'id_ncp', p_id_ncp, 'so_phieu_phe', v_so_phieu, 'trang_thai', 'cho_duyet_phe');
end;
$$;
revoke execute on function duc_ncp_request_scrap(text, numeric, text, text) from anon;
grant execute on function duc_ncp_request_scrap(text, numeric, text, text) to authenticated;

-- ── approveScrap_ ────────────────────────────────────────────────────────
create or replace function duc_ncp_approve_scrap(p_id_ncp text, p_ket_qua text, p_ghi_chu text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_d record;
  v_tt jsonb;
  v_trang_thai_moi text;
  v_now timestamptz := now();
begin
  if p_ket_qua not in ('Duyet', 'Tu_choi') then return jsonb_build_object('ok', false, 'error', 'Kết quả duyệt không hợp lệ'); end if;
  select * into v_d from duc_ncp where id_ncp = p_id_ncp;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu: ' || p_id_ncp); end if;
  if v_d.trang_thai <> 'cho_duyet_phe' then return jsonb_build_object('ok', false, 'error', 'Phiếu không có đề nghị phế nào đang chờ duyệt'); end if;

  if p_ket_qua = 'Duyet' then
    v_tt := duc_ncp_tinh_trang_thai(v_d.so_luong_da_loc, v_d.so_luong_nghi_van, v_d.so_luong_loc_ng, v_d.so_luong_sua_ok, v_d.so_luong_phe_da_duyet + v_d.so_luong_de_nghi_phe);
    v_trang_thai_moi := v_tt->>'trang_thai';
    update duc_ncp set nguoi_duyet_phe = p_user, thoi_diem_duyet_phe = v_now, ket_qua_duyet_phe = p_ket_qua,
      so_luong_phe_da_duyet = so_luong_phe_da_duyet + v_d.so_luong_de_nghi_phe, trang_thai = v_trang_thai_moi, last_updated_at = v_now
    where id_ncp = p_id_ncp;
    perform duc_ncp_append_log(p_id_ncp, 'DUYỆT phế ' || v_d.so_luong_de_nghi_phe || ' SP (phiếu ' || v_d.so_phieu_phe || ') — bởi ' || p_user || (case when p_ghi_chu is not null and p_ghi_chu <> '' then ' — ' || p_ghi_chu else '' end));
  else
    v_trang_thai_moi := 'cho_quyet_dinh';
    update duc_ncp set nguoi_duyet_phe = p_user, thoi_diem_duyet_phe = v_now, ket_qua_duyet_phe = p_ket_qua,
      trang_thai = v_trang_thai_moi, last_updated_at = v_now
    where id_ncp = p_id_ncp;
    perform duc_ncp_append_log(p_id_ncp, 'TỪ CHỐI phế (phiếu ' || v_d.so_phieu_phe || ') — bởi ' || p_user || (case when p_ghi_chu is not null and p_ghi_chu <> '' then ' — ' || p_ghi_chu else '' end));
  end if;

  return jsonb_build_object('ok', true, 'id_ncp', p_id_ncp, 'trang_thai', v_trang_thai_moi);
end;
$$;
revoke execute on function duc_ncp_approve_scrap(text, text, text, text) from anon;
grant execute on function duc_ncp_approve_scrap(text, text, text, text) to authenticated;

-- ── updateNcpRootCause_ ──────────────────────────────────────────────────
create or replace function duc_ncp_update_root_cause(
  p_id_ncp text, p_nguoi_dam_nhiem_doi_sach text, p_nguyen_nhan_phat_sinh text, p_nguyen_nhan_luu_xuat text,
  p_hinh_anh_phat_sinh jsonb, p_hinh_anh_luu_xuat jsonb,
  p_doi_sach_ps_tam_thoi jsonb, p_doi_sach_ps_lau_dai jsonb, p_doi_sach_lx_tam_thoi jsonb, p_doi_sach_lx_lau_dai jsonb,
  p_user text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_trang_thai_duyet text;
  v_now timestamptz := now();
begin
  select coalesce(rc_trang_thai_duyet, 'nhap') into v_trang_thai_duyet from duc_ncp where id_ncp = p_id_ncp;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu: ' || p_id_ncp); end if;
  if v_trang_thai_duyet in ('cho_duyet', 'da_duyet') then
    return jsonb_build_object('ok', false, 'error', 'Phiếu đang ở trạng thái "' ||
      (case when v_trang_thai_duyet = 'cho_duyet' then 'Chờ duyệt' else 'Đã duyệt' end) ||
      '" — bấm "Mở lại để chỉnh sửa" trước khi sửa.');
  end if;

  update duc_ncp set
    nguoi_dam_nhiem_doi_sach = trim(coalesce(p_nguoi_dam_nhiem_doi_sach, '')),
    nguyen_nhan_phat_sinh = trim(coalesce(p_nguyen_nhan_phat_sinh, '')),
    nguyen_nhan_luu_xuat = trim(coalesce(p_nguyen_nhan_luu_xuat, '')),
    hinh_anh_phat_sinh_json = coalesce(p_hinh_anh_phat_sinh, '[]'::jsonb),
    hinh_anh_luu_xuat_json = coalesce(p_hinh_anh_luu_xuat, '[]'::jsonb),
    doi_sach_ps_tam_thoi_json = coalesce(p_doi_sach_ps_tam_thoi, '[]'::jsonb),
    doi_sach_ps_lau_dai_json = coalesce(p_doi_sach_ps_lau_dai, '[]'::jsonb),
    doi_sach_lx_tam_thoi_json = coalesce(p_doi_sach_lx_tam_thoi, '[]'::jsonb),
    doi_sach_lx_lau_dai_json = coalesce(p_doi_sach_lx_lau_dai, '[]'::jsonb),
    last_updated_at = v_now
  where id_ncp = p_id_ncp;
  perform duc_ncp_append_log(p_id_ncp, 'Cập nhật Nguyên nhân & Đối sách — bởi ' || p_user);

  return jsonb_build_object('ok', true, 'id_ncp', p_id_ncp);
end;
$$;
revoke execute on function duc_ncp_update_root_cause(text, text, text, text, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, text) from anon;
grant execute on function duc_ncp_update_root_cause(text, text, text, text, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, text) to authenticated;

-- ── submitNcpRootCauseForApproval_ ───────────────────────────────────────
create or replace function duc_ncp_submit_root_cause_for_approval(p_id_ncp text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_d record;
  v_co_doi_sach boolean;
  v_now timestamptz := now();
begin
  select * into v_d from duc_ncp where id_ncp = p_id_ncp;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu: ' || p_id_ncp); end if;
  if v_d.rc_trang_thai_duyet = 'cho_duyet' then return jsonb_build_object('ok', false, 'error', 'Phiếu đã đang chờ duyệt'); end if;
  if v_d.rc_trang_thai_duyet = 'da_duyet' then return jsonb_build_object('ok', false, 'error', 'Phiếu đã được duyệt'); end if;

  select exists(
    select 1 from jsonb_array_elements(coalesce(v_d.doi_sach_ps_tam_thoi_json, '[]'::jsonb)
      || coalesce(v_d.doi_sach_ps_lau_dai_json, '[]'::jsonb)
      || coalesce(v_d.doi_sach_lx_tam_thoi_json, '[]'::jsonb)
      || coalesce(v_d.doi_sach_lx_lau_dai_json, '[]'::jsonb)) elem
    where coalesce(elem->>'noi_dung', '') <> ''
  ) into v_co_doi_sach;
  if not v_co_doi_sach then
    return jsonb_build_object('ok', false, 'error', 'Cần ít nhất 1 đối sách có nội dung trước khi gửi phê duyệt');
  end if;

  update duc_ncp set rc_trang_thai_duyet = 'cho_duyet', rc_nguoi_gui_duyet = p_user, rc_thoi_diem_gui_duyet = v_now, last_updated_at = v_now
  where id_ncp = p_id_ncp;
  perform duc_ncp_append_log(p_id_ncp, 'Gửi phê duyệt Nguyên nhân & Đối sách — bởi ' || p_user);

  return jsonb_build_object('ok', true, 'id_ncp', p_id_ncp);
end;
$$;
revoke execute on function duc_ncp_submit_root_cause_for_approval(text, text) from anon;
grant execute on function duc_ncp_submit_root_cause_for_approval(text, text) to authenticated;

-- ── approveNcpRootCause_ ─────────────────────────────────────────────────
create or replace function duc_ncp_approve_root_cause(p_id_ncp text, p_ket_qua text, p_ghi_chu text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_trang_thai_duyet text;
  v_trang_thai_moi text;
  v_now timestamptz := now();
begin
  if p_ket_qua not in ('Duyet', 'Tu_choi') then return jsonb_build_object('ok', false, 'error', 'Kết quả duyệt không hợp lệ'); end if;
  select rc_trang_thai_duyet into v_trang_thai_duyet from duc_ncp where id_ncp = p_id_ncp;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu: ' || p_id_ncp); end if;
  if v_trang_thai_duyet <> 'cho_duyet' then return jsonb_build_object('ok', false, 'error', 'Phiếu không có yêu cầu nào đang chờ duyệt'); end if;

  v_trang_thai_moi := case when p_ket_qua = 'Duyet' then 'da_duyet' else 'tu_choi' end;
  update duc_ncp set rc_trang_thai_duyet = v_trang_thai_moi, rc_nguoi_duyet = p_user, rc_thoi_diem_duyet = v_now,
    rc_ghi_chu_duyet = trim(coalesce(p_ghi_chu, '')), last_updated_at = v_now
  where id_ncp = p_id_ncp;
  perform duc_ncp_append_log(p_id_ncp, (case when p_ket_qua = 'Duyet' then 'DUYỆT' else 'TỪ CHỐI' end) || ' Nguyên nhân & Đối sách — bởi ' || p_user ||
    (case when p_ghi_chu is not null and p_ghi_chu <> '' then ' — ' || p_ghi_chu else '' end));

  return jsonb_build_object('ok', true, 'id_ncp', p_id_ncp, 'trang_thai', v_trang_thai_moi);
end;
$$;
revoke execute on function duc_ncp_approve_root_cause(text, text, text, text) from anon;
grant execute on function duc_ncp_approve_root_cause(text, text, text, text) to authenticated;

-- ── reopenNcpRootCause_ ──────────────────────────────────────────────────
create or replace function duc_ncp_reopen_root_cause(p_id_ncp text, p_user text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_now timestamptz := now();
begin
  if not exists (select 1 from duc_ncp where id_ncp = p_id_ncp) then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu: ' || p_id_ncp);
  end if;
  update duc_ncp set rc_trang_thai_duyet = 'nhap', last_updated_at = v_now where id_ncp = p_id_ncp;
  perform duc_ncp_append_log(p_id_ncp, 'Mở lại để chỉnh sửa Nguyên nhân & Đối sách — bởi ' || p_user);
  return jsonb_build_object('ok', true, 'id_ncp', p_id_ncp);
end;
$$;
revoke execute on function duc_ncp_reopen_root_cause(text, text) from anon;
grant execute on function duc_ncp_reopen_root_cause(text, text) to authenticated;

-- ── getAvailableNgCheckpointsForNcp_ — đọc tổng hợp, public (chỉ đọc) ─────
create or replace function duc_get_available_ng_checkpoints_for_ncp()
returns table(
  id_checkpoint text, ma_may text, ma_sp text, so_khuon text,
  thoi_diem_kiem_thuc_te timestamptz, mo_ta_de_xuat text
)
language sql
stable
as $$
  select cp.id_checkpoint, cp.ma_may, cp.ma_sp,
    coalesce(cht.so_khuon, ''),
    cp.thoi_diem_kiem_thuc_te,
    duc_build_ipqc_issue_text('NG', cp.loai_kiem, cp.checklist_json, cp.ghi_chu)
  from duc_ipqc_checkpoint cp
  left join duc_ca_hien_tai cht on cht.id_dong = cp.id_dong
  where cp.ket_qua = 'NG'
    and (cp.id_ncp_lien_quan is null or cp.id_ncp_lien_quan = '')
    and cp.thoi_diem_kiem_thuc_te is not null
    and cp.thoi_diem_kiem_thuc_te >= now() - interval '7 days'
  order by cp.thoi_diem_kiem_thuc_te desc;
$$;
