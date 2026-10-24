-- ============================================================================
-- Phase T163 — Phê duyệt tiêu chuẩn theo mã SP (QC Manager › Quản lý tiêu chuẩn)
--
-- Áp dụng cho CẢ 2 phần của tab:
--   1) Bảng tuần kiểm kích thước (ipqc_btk + ipqc_btk_muc, T133)
--   2) Checklist kiểm tra + file PDF tiêu chuẩn gốc (duc_ipqc_tieuchuan)
--
-- Luồng (lập mới và sửa đổi đều như nhau):
--   Nhân viên QC soạn (ipqc / nhan_vien_oqc / qc_manager / admin) → 'cho_kiem_tra'
--   → Trưởng phòng QC kiểm tra (qc_manager)                        → 'cho_phe_duyet'
--   → Giám đốc sản xuất phê duyệt (giam_doc_sx)                    → 'da_duyet' = có hiệu lực
--   Kiểm tra / phê duyệt đều có thể "Trả lại" kèm lý do → 'tra_lai'; người soạn
--   sửa rồi gửi lại → về 'cho_kiem_tra'. Không có admin bypass (như T16 KHSX).
--
-- Trong lúc chờ duyệt, IPQC vẫn dùng bản ĐÃ DUYỆT cũ:
--   - ipqc_btk: bản nháp có dang_dung = false (mọi RPC đo/biểu đồ đọc dang_dung).
--   - checklist: bản nháp nằm ở bảng mới duc_ipqc_tieuchuan_de_xuat; chỉ khi
--     phê duyệt mới chép sang duc_ipqc_tieuchuan (bảng IPQC đọc).
-- Mỗi mã chỉ có tối đa 1 bản nháp đang mở / loại (unique partial index); gửi
-- lại khi đã có nháp = ghi đè nháp đó và quay về bước kiểm tra.
-- Dữ liệu cũ: mọi phiên bản / checklist hiện có coi như đã duyệt.
--
-- Thông báo chuông MES (cv_thong_bao, T162) nguon = 'tieu_chuan'.
-- An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. ipqc_btk: trạng thái duyệt
-- ---------------------------------------------------------------------------
alter table public.ipqc_btk add column if not exists trang_thai text not null default 'da_duyet';
alter table public.ipqc_btk add column if not exists gui_luc timestamptz;
alter table public.ipqc_btk add column if not exists nguoi_kiem_tra text;
alter table public.ipqc_btk add column if not exists nguoi_kiem_tra_uid uuid;
alter table public.ipqc_btk add column if not exists kiem_tra_luc timestamptz;
alter table public.ipqc_btk add column if not exists nguoi_phe_duyet text;
alter table public.ipqc_btk add column if not exists nguoi_phe_duyet_uid uuid;
alter table public.ipqc_btk add column if not exists phe_duyet_luc timestamptz;
alter table public.ipqc_btk add column if not exists ly_do_tra_lai text;
alter table public.ipqc_btk add column if not exists nguoi_tra_lai text;
alter table public.ipqc_btk add column if not exists tra_lai_luc timestamptz;

alter table public.ipqc_btk drop constraint if exists ipqc_btk_trang_thai_check;
alter table public.ipqc_btk add constraint ipqc_btk_trang_thai_check
  check (trang_thai in ('cho_kiem_tra', 'cho_phe_duyet', 'tra_lai', 'da_duyet'));
alter table public.ipqc_btk drop constraint if exists ipqc_btk_dang_dung_da_duyet_check;
alter table public.ipqc_btk add constraint ipqc_btk_dang_dung_da_duyet_check
  check (not dang_dung or trang_thai = 'da_duyet');
create unique index if not exists ipqc_btk_nhap_uq on public.ipqc_btk (ma_sp) where trang_thai <> 'da_duyet';

-- ---------------------------------------------------------------------------
-- 2. Checklist + PDF: bảng đề xuất (nháp + lịch sử đã duyệt)
-- ---------------------------------------------------------------------------
create table if not exists public.duc_ipqc_tieuchuan_de_xuat (
  id                      bigserial primary key,
  ma_sp                   text not null,
  danh_sach_muc_kiem_json jsonb not null,
  file_pdf_url            text,
  noi_dung_sua_doi        text,
  trang_thai              text not null default 'cho_kiem_tra'
                          check (trang_thai in ('cho_kiem_tra', 'cho_phe_duyet', 'tra_lai', 'da_duyet')),
  nguoi_lap               text,
  nguoi_lap_uid           uuid,
  gui_luc                 timestamptz not null default now(),
  nguoi_kiem_tra          text,
  nguoi_kiem_tra_uid      uuid,
  kiem_tra_luc            timestamptz,
  nguoi_phe_duyet         text,
  nguoi_phe_duyet_uid     uuid,
  phe_duyet_luc           timestamptz,
  ly_do_tra_lai           text,
  nguoi_tra_lai           text,
  tra_lai_luc             timestamptz
);
create unique index if not exists duc_ipqc_tc_dx_nhap_uq on public.duc_ipqc_tieuchuan_de_xuat (ma_sp) where trang_thai <> 'da_duyet';
create index if not exists duc_ipqc_tc_dx_ma_idx on public.duc_ipqc_tieuchuan_de_xuat (ma_sp, gui_luc desc);

alter table public.duc_ipqc_tieuchuan_de_xuat enable row level security;
drop policy if exists duc_ipqc_tc_dx_doc on public.duc_ipqc_tieuchuan_de_xuat;
create policy duc_ipqc_tc_dx_doc on public.duc_ipqc_tieuchuan_de_xuat for select to authenticated using (true);
revoke insert, update, delete on public.duc_ipqc_tieuchuan_de_xuat from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Bảng tuần kiểm: lưu = gửi duyệt (tạo / ghi đè bản nháp, không đổi bản đang dùng)
-- ---------------------------------------------------------------------------
create or replace function public.ipqc_btk_luu(p_ma_sp text, p_data jsonb, p_nguoi text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_ma text := trim(coalesce(p_ma_sp, ''));
  v_cu ipqc_btk%rowtype;
  v_nhap ipqc_btk%rowtype;
  v_pb text := nullif(trim(coalesce(p_data ->> 'phien_ban', '')), '');
  v_id bigint;
  m jsonb;
  v_nos int[] := '{}';
  v_no int;
  v_kieu text;
begin
  if not public.has_role('ipqc', 'nhan_vien_oqc', 'qc_manager', 'admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ nhân viên QC / Trưởng phòng QC được soạn bảng tuần kiểm');
  end if;
  if not exists (select 1 from master_products where ma_sp = v_ma) then
    return jsonb_build_object('ok', false, 'error', 'Mã SP không có trong danh mục: ' || v_ma);
  end if;
  if jsonb_array_length(coalesce(p_data -> 'muc', '[]'::jsonb)) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Cần ít nhất 1 hạng mục');
  end if;
  if coalesce((p_data ->> 'so_mau')::int, 1) not between 1 and 5 then
    return jsonb_build_object('ok', false, 'error', 'Số mẫu/lần phải từ 1 đến 5');
  end if;

  perform pg_advisory_xact_lock(hashtext('ipqc_btk:' || v_ma));
  select * into v_cu from ipqc_btk where ma_sp = v_ma and dang_dung;
  select * into v_nhap from ipqc_btk where ma_sp = v_ma and trang_thai <> 'da_duyet' for update;
  if v_pb is null then
    v_pb := case when v_nhap.id is not null then v_nhap.phien_ban
                 when v_cu.id is null then 'A'
                 when v_cu.phien_ban ~ '^[A-Y]$' then chr(ascii(v_cu.phien_ban) + 1)
                 else v_cu.phien_ban || '.1' end;
  end if;
  if exists (select 1 from ipqc_btk where ma_sp = v_ma and phien_ban = v_pb and id is distinct from v_nhap.id) then
    return jsonb_build_object('ok', false, 'error', 'Mã ' || v_ma || ' đã có phiên bản ' || v_pb);
  end if;

  for m in select * from jsonb_array_elements(p_data -> 'muc') loop
    v_no := nullif(m ->> 'muc_no', '')::int;
    v_kieu := m ->> 'kieu';
    if v_no is null or v_no < 1 then return jsonb_build_object('ok', false, 'error', 'Thiếu số thứ tự (No) hạng mục'); end if;
    if v_no = any(v_nos) then return jsonb_build_object('ok', false, 'error', 'Trùng No ' || v_no); end if;
    v_nos := v_nos || v_no;
    if coalesce(trim(m ->> 'hang_muc'), '') = '' then return jsonb_build_object('ok', false, 'error', 'No ' || v_no || ': thiếu tên hạng mục'); end if;
    if v_kieu not in ('so', 'okng') then return jsonb_build_object('ok', false, 'error', 'No ' || v_no || ': kiểu phải là Đo số hoặc OK/NG'); end if;
    if v_kieu = 'so' and (nullif(m ->> 'danh_nghia', '') is null or (nullif(m ->> 'dung_sai_tren', '') is null and nullif(m ->> 'dung_sai_duoi', '') is null)) then
      return jsonb_build_object('ok', false, 'error', 'No ' || v_no || ': hạng mục đo số cần giá trị danh nghĩa + dung sai');
    end if;
    if v_kieu = 'okng' and coalesce(trim(m ->> 'tieu_chuan'), '') = '' then
      return jsonb_build_object('ok', false, 'error', 'No ' || v_no || ': hạng mục OK/NG cần ghi tiêu chuẩn');
    end if;
  end loop;

  if v_nhap.id is not null then
    update ipqc_btk set
      phien_ban = v_pb,
      ngay_hieu_luc = coalesce(nullif(p_data ->> 'ngay_hieu_luc', '')::date, (now() at time zone 'Asia/Ho_Chi_Minh')::date),
      so_mau = coalesce((p_data ->> 'so_mau')::int, 1),
      tan_suat = coalesce(nullif(trim(p_data ->> 'tan_suat'), ''), '2h/lần'),
      ma_bieu = coalesce(nullif(trim(p_data ->> 'ma_bieu'), ''), 'QP-82405-B'),
      ban_ve_url = coalesce(nullif(p_data ->> 'ban_ve_url', ''), v_nhap.ban_ve_url),
      ban_ve_vi_tri = coalesce(p_data -> 'ban_ve_vi_tri', v_nhap.ban_ve_vi_tri, '[]'::jsonb),
      noi_dung_sua_doi = coalesce(nullif(trim(p_data ->> 'noi_dung_sua_doi'), ''), v_nhap.noi_dung_sua_doi),
      nguoi_lap = p_nguoi, nguoi_lap_uid = auth.uid(), tao_luc = now(), gui_luc = now(),
      trang_thai = 'cho_kiem_tra',
      nguoi_kiem_tra = null, nguoi_kiem_tra_uid = null, kiem_tra_luc = null,
      nguoi_phe_duyet = null, nguoi_phe_duyet_uid = null, phe_duyet_luc = null
    where id = v_nhap.id;
    v_id := v_nhap.id;
    delete from ipqc_btk_muc where id_btk = v_id;
  else
    insert into ipqc_btk (ma_sp, phien_ban, ngay_hieu_luc, so_mau, tan_suat, ma_bieu, ban_ve_url, ban_ve_vi_tri,
      noi_dung_sua_doi, nguoi_lap, nguoi_lap_uid, dang_dung, trang_thai, gui_luc)
    values (v_ma, v_pb, coalesce(nullif(p_data ->> 'ngay_hieu_luc', '')::date, (now() at time zone 'Asia/Ho_Chi_Minh')::date),
      coalesce((p_data ->> 'so_mau')::int, 1), coalesce(nullif(trim(p_data ->> 'tan_suat'), ''), '2h/lần'),
      coalesce(nullif(trim(p_data ->> 'ma_bieu'), ''), 'QP-82405-B'),
      coalesce(nullif(p_data ->> 'ban_ve_url', ''), v_cu.ban_ve_url),
      coalesce(p_data -> 'ban_ve_vi_tri', v_cu.ban_ve_vi_tri, '[]'::jsonb),
      coalesce(nullif(trim(p_data ->> 'noi_dung_sua_doi'), ''), case when v_cu.id is null then 'Lập mới' else 'Sửa đổi' end),
      p_nguoi, auth.uid(), false, 'cho_kiem_tra', now())
    returning id into v_id;
  end if;

  insert into ipqc_btk_muc (id_btk, muc_no, hang_muc, kieu, danh_nghia, dung_sai_tren, dung_sai_duoi, tieu_chuan, dung_cu, tan_suat)
  select v_id, (j.v ->> 'muc_no')::int, trim(j.v ->> 'hang_muc'), j.v ->> 'kieu',
    case when j.v ->> 'kieu' = 'so' then nullif(j.v ->> 'danh_nghia', '')::numeric end,
    case when j.v ->> 'kieu' = 'so' then abs(nullif(j.v ->> 'dung_sai_tren', '')::numeric) end,
    case when j.v ->> 'kieu' = 'so' then abs(nullif(j.v ->> 'dung_sai_duoi', '')::numeric) end,
    nullif(trim(j.v ->> 'tieu_chuan'), ''), nullif(trim(j.v ->> 'dung_cu'), ''), nullif(trim(j.v ->> 'tan_suat'), '')
  from jsonb_array_elements(p_data -> 'muc') as j(v);

  return jsonb_build_object('ok', true, 'id', v_id, 'phien_ban', v_pb);
end $$;
revoke execute on function public.ipqc_btk_luu(text, jsonb, text) from public, anon;
grant execute on function public.ipqc_btk_luu(text, jsonb, text) to authenticated;

-- Bản vẽ + vị trí đo giờ đi cùng payload ipqc_btk_luu (phải duyệt như nội dung khác).
drop function if exists public.ipqc_btk_ban_ve(bigint, text, jsonb);

-- Nhân viên QC cũng tải được ảnh bản vẽ.
drop policy if exists "qc upload ipqc-ban-ve" on storage.objects;
create policy "qc upload ipqc-ban-ve" on storage.objects
  for insert with check (bucket_id = 'ipqc-ban-ve' and public.has_role('ipqc', 'nhan_vien_oqc', 'qc_manager', 'admin'));

-- ---------------------------------------------------------------------------
-- 4. Checklist + PDF: lưu = gửi duyệt
-- p_pdf_url null/'' = giữ PDF của nháp / bản đang dùng.
-- ---------------------------------------------------------------------------
drop function if exists public.duc_ipqc_save_tieu_chuan(text, jsonb, text);
drop function if exists public.duc_ipqc_set_tieu_chuan_pdf(text, text, text);

create or replace function public.ipqc_tc_luu_checklist(p_ma_sp text, p_muc_kiem jsonb, p_pdf_url text,
                                                       p_noi_dung text, p_nguoi text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_ma text := trim(coalesce(p_ma_sp, ''));
  v_cu duc_ipqc_tieuchuan%rowtype;
  v_nhap duc_ipqc_tieuchuan_de_xuat%rowtype;
  v_pdf text := nullif(trim(coalesce(p_pdf_url, '')), '');
  v_id bigint;
begin
  if not public.has_role('ipqc', 'nhan_vien_oqc', 'qc_manager', 'admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ nhân viên QC / Trưởng phòng QC được soạn tiêu chuẩn');
  end if;
  if v_ma = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã SP'); end if;
  if not exists (select 1 from master_products where ma_sp = v_ma) then
    return jsonb_build_object('ok', false, 'error', 'Mã SP không có trong danh mục: ' || v_ma);
  end if;
  if jsonb_typeof(p_muc_kiem) is distinct from 'array' or jsonb_array_length(p_muc_kiem) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Checklist cần ít nhất 1 mục kiểm');
  end if;

  perform pg_advisory_xact_lock(hashtext('ipqc_tc:' || v_ma));
  select * into v_cu from duc_ipqc_tieuchuan where ma_sp = v_ma;
  select * into v_nhap from duc_ipqc_tieuchuan_de_xuat where ma_sp = v_ma and trang_thai <> 'da_duyet' for update;

  if v_nhap.id is null and v_cu.ma_sp is not null
     and v_cu.danh_sach_muc_kiem_json = p_muc_kiem
     and coalesce(v_pdf, v_cu.file_pdf_url, '') = coalesce(v_cu.file_pdf_url, '') then
    return jsonb_build_object('ok', false, 'error', 'Không có thay đổi so với bản đang dùng');
  end if;

  if v_nhap.id is not null then
    update duc_ipqc_tieuchuan_de_xuat set
      danh_sach_muc_kiem_json = p_muc_kiem,
      file_pdf_url = coalesce(v_pdf, v_nhap.file_pdf_url),
      noi_dung_sua_doi = coalesce(nullif(trim(p_noi_dung), ''), v_nhap.noi_dung_sua_doi),
      nguoi_lap = p_nguoi, nguoi_lap_uid = auth.uid(), gui_luc = now(),
      trang_thai = 'cho_kiem_tra',
      nguoi_kiem_tra = null, nguoi_kiem_tra_uid = null, kiem_tra_luc = null,
      nguoi_phe_duyet = null, nguoi_phe_duyet_uid = null, phe_duyet_luc = null
    where id = v_nhap.id;
    v_id := v_nhap.id;
  else
    insert into duc_ipqc_tieuchuan_de_xuat (ma_sp, danh_sach_muc_kiem_json, file_pdf_url, noi_dung_sua_doi,
      nguoi_lap, nguoi_lap_uid)
    values (v_ma, p_muc_kiem, coalesce(v_pdf, v_cu.file_pdf_url),
      coalesce(nullif(trim(p_noi_dung), ''), case when v_cu.ma_sp is null then 'Lập mới' else 'Sửa đổi' end),
      p_nguoi, auth.uid())
    returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke execute on function public.ipqc_tc_luu_checklist(text, jsonb, text, text, text) from public, anon;
grant execute on function public.ipqc_tc_luu_checklist(text, jsonb, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Kiểm tra / phê duyệt / trả lại — dùng chung 2 loại
-- p_loai: 'btk' | 'checklist'; p_hanh_dong: 'kiem_tra' | 'phe_duyet' | 'tra_lai'
-- ---------------------------------------------------------------------------
create or replace function public.ipqc_tc_duyet(p_loai text, p_id bigint, p_hanh_dong text, p_ly_do text, p_nguoi text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_tt text;
  v_ma text;
  v_moi text;
  v_ly_do text := nullif(trim(coalesce(p_ly_do, '')), '');
  v_hom_nay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  b ipqc_btk%rowtype;
  c duc_ipqc_tieuchuan_de_xuat%rowtype;
begin
  if p_loai = 'btk' then
    select * into b from ipqc_btk where id = p_id for update;
    v_tt := b.trang_thai; v_ma := b.ma_sp;
  elsif p_loai = 'checklist' then
    select * into c from duc_ipqc_tieuchuan_de_xuat where id = p_id for update;
    v_tt := c.trang_thai; v_ma := c.ma_sp;
  else
    return jsonb_build_object('ok', false, 'error', 'Loại tiêu chuẩn không hợp lệ');
  end if;
  if v_ma is null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy bản tiêu chuẩn #' || p_id); end if;

  if p_hanh_dong = 'kiem_tra' then
    if v_tt <> 'cho_kiem_tra' then return jsonb_build_object('ok', false, 'error', 'Bản này không ở bước chờ kiểm tra'); end if;
    if not public.has_role('qc_manager') then return jsonb_build_object('ok', false, 'error', 'Chỉ Trưởng phòng QC được kiểm tra'); end if;
    v_moi := 'cho_phe_duyet';
  elsif p_hanh_dong = 'phe_duyet' then
    if v_tt <> 'cho_phe_duyet' then return jsonb_build_object('ok', false, 'error', 'Bản này chưa được Trưởng phòng QC kiểm tra'); end if;
    if not public.has_role('giam_doc_sx') then return jsonb_build_object('ok', false, 'error', 'Chỉ Giám đốc sản xuất được phê duyệt'); end if;
    v_moi := 'da_duyet';
  elsif p_hanh_dong = 'tra_lai' then
    if v_tt = 'cho_kiem_tra' and not public.has_role('qc_manager') then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Trưởng phòng QC được trả lại ở bước kiểm tra');
    elsif v_tt = 'cho_phe_duyet' and not public.has_role('giam_doc_sx') then
      return jsonb_build_object('ok', false, 'error', 'Chỉ Giám đốc sản xuất được trả lại ở bước phê duyệt');
    elsif v_tt not in ('cho_kiem_tra', 'cho_phe_duyet') then
      return jsonb_build_object('ok', false, 'error', 'Bản này không ở bước chờ duyệt');
    end if;
    if v_ly_do is null then return jsonb_build_object('ok', false, 'error', 'Nhập lý do trả lại'); end if;
    v_moi := 'tra_lai';
  else
    return jsonb_build_object('ok', false, 'error', 'Thao tác không hợp lệ');
  end if;

  if p_loai = 'btk' then
    if v_moi = 'da_duyet' then
      perform pg_advisory_xact_lock(hashtext('ipqc_btk:' || v_ma));
      update ipqc_btk set dang_dung = false where ma_sp = v_ma and dang_dung;
    end if;
    update ipqc_btk set
      trang_thai = v_moi,
      dang_dung = (v_moi = 'da_duyet'),
      ngay_hieu_luc = case when v_moi = 'da_duyet' then greatest(coalesce(ngay_hieu_luc, v_hom_nay), v_hom_nay) else ngay_hieu_luc end,
      nguoi_kiem_tra = case when p_hanh_dong = 'kiem_tra' then p_nguoi else nguoi_kiem_tra end,
      nguoi_kiem_tra_uid = case when p_hanh_dong = 'kiem_tra' then auth.uid() else nguoi_kiem_tra_uid end,
      kiem_tra_luc = case when p_hanh_dong = 'kiem_tra' then now() else kiem_tra_luc end,
      nguoi_phe_duyet = case when p_hanh_dong = 'phe_duyet' then p_nguoi else nguoi_phe_duyet end,
      nguoi_phe_duyet_uid = case when p_hanh_dong = 'phe_duyet' then auth.uid() else nguoi_phe_duyet_uid end,
      phe_duyet_luc = case when p_hanh_dong = 'phe_duyet' then now() else phe_duyet_luc end,
      ly_do_tra_lai = case when p_hanh_dong = 'tra_lai' then v_ly_do else ly_do_tra_lai end,
      nguoi_tra_lai = case when p_hanh_dong = 'tra_lai' then p_nguoi else nguoi_tra_lai end,
      tra_lai_luc = case when p_hanh_dong = 'tra_lai' then now() else tra_lai_luc end
    where id = p_id;
  else
    update duc_ipqc_tieuchuan_de_xuat set
      trang_thai = v_moi,
      nguoi_kiem_tra = case when p_hanh_dong = 'kiem_tra' then p_nguoi else nguoi_kiem_tra end,
      nguoi_kiem_tra_uid = case when p_hanh_dong = 'kiem_tra' then auth.uid() else nguoi_kiem_tra_uid end,
      kiem_tra_luc = case when p_hanh_dong = 'kiem_tra' then now() else kiem_tra_luc end,
      nguoi_phe_duyet = case when p_hanh_dong = 'phe_duyet' then p_nguoi else nguoi_phe_duyet end,
      nguoi_phe_duyet_uid = case when p_hanh_dong = 'phe_duyet' then auth.uid() else nguoi_phe_duyet_uid end,
      phe_duyet_luc = case when p_hanh_dong = 'phe_duyet' then now() else phe_duyet_luc end,
      ly_do_tra_lai = case when p_hanh_dong = 'tra_lai' then v_ly_do else ly_do_tra_lai end,
      nguoi_tra_lai = case when p_hanh_dong = 'tra_lai' then p_nguoi else nguoi_tra_lai end,
      tra_lai_luc = case when p_hanh_dong = 'tra_lai' then now() else tra_lai_luc end
    where id = p_id;
    if v_moi = 'da_duyet' then
      insert into duc_ipqc_tieuchuan (ma_sp, danh_sach_muc_kiem_json, file_pdf_url, cap_nhat_lan_cuoi_boi, thoi_diem_cap_nhat)
      values (v_ma, c.danh_sach_muc_kiem_json, c.file_pdf_url, c.nguoi_lap, now())
      on conflict (ma_sp) do update set
        danh_sach_muc_kiem_json = excluded.danh_sach_muc_kiem_json, file_pdf_url = excluded.file_pdf_url,
        cap_nhat_lan_cuoi_boi = excluded.cap_nhat_lan_cuoi_boi, thoi_diem_cap_nhat = excluded.thoi_diem_cap_nhat;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'trang_thai', v_moi);
end $$;
revoke execute on function public.ipqc_tc_duyet(text, bigint, text, text, text) from public, anon;
grant execute on function public.ipqc_tc_duyet(text, bigint, text, text, text) to authenticated;

-- Huỷ bản nháp (người lập hoặc Trưởng phòng QC / admin).
create or replace function public.ipqc_tc_huy(p_loai text, p_id bigint)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_uid uuid; v_tt text;
begin
  if p_loai = 'btk' then
    select nguoi_lap_uid, trang_thai into v_uid, v_tt from ipqc_btk where id = p_id for update;
  elsif p_loai = 'checklist' then
    select nguoi_lap_uid, trang_thai into v_uid, v_tt from duc_ipqc_tieuchuan_de_xuat where id = p_id for update;
  else
    return jsonb_build_object('ok', false, 'error', 'Loại tiêu chuẩn không hợp lệ');
  end if;
  if v_tt is null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy bản nháp #' || p_id); end if;
  if v_tt = 'da_duyet' then return jsonb_build_object('ok', false, 'error', 'Bản đã duyệt không huỷ được'); end if;
  if v_uid is distinct from auth.uid() and not public.has_role('qc_manager', 'admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ người soạn hoặc Trưởng phòng QC được huỷ bản nháp');
  end if;
  if p_loai = 'btk' then delete from ipqc_btk where id = p_id;
  else delete from duc_ipqc_tieuchuan_de_xuat where id = p_id; end if;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.ipqc_tc_huy(text, bigint) from public, anon;
grant execute on function public.ipqc_tc_huy(text, bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Thông báo chuông MES (nguon 'tieu_chuan')
-- ---------------------------------------------------------------------------
alter table public.cv_thong_bao drop constraint if exists cv_thong_bao_nguon_check;
alter table public.cv_thong_bao add constraint cv_thong_bao_nguon_check
  check (nguon in ('cong_viec', 'khsx', 'bd_khuon', 'ipqc', 'ncp', 'tai_lieu', 'tieu_chuan'));

create or replace function public.cv_pd_trg_tieu_chuan()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_khoa text; v_lk text; v_ten text; v_cu text;
begin
  begin
    if tg_op = 'DELETE' then
      perform cv_pd_xong(case when tg_table_name = 'ipqc_btk' then 'tc:btk:' else 'tc:cl:' end || old.id);
      return old;
    end if;
    v_cu := case when tg_op = 'UPDATE' then old.trang_thai end;
    if v_cu is not distinct from new.trang_thai then return new; end if;
    if tg_op = 'INSERT' and new.trang_thai = 'da_duyet' then return new; end if;
    if tg_table_name = 'ipqc_btk' then
      v_khoa := 'tc:btk:' || new.id;
      v_ten := 'Bảng tuần kiểm mã ' || new.ma_sp || ' (phiên bản ' || new.phien_ban || ')';
    else
      v_khoa := 'tc:cl:' || new.id;
      v_ten := 'Checklist / PDF tiêu chuẩn mã ' || new.ma_sp;
    end if;
    v_lk := 'qc-manager.html?tab=tieuchuan&ma=' || new.ma_sp;
    perform cv_pd_xong(v_khoa);
    if new.trang_thai = 'cho_kiem_tra' then
      perform cv_pd_gui(cv_pd_ds_role(array['qc_manager']), 'tieu_chuan', 'can_duyet', v_khoa, v_lk,
        v_ten || ' đang chờ bạn kiểm tra (Trưởng phòng QC).', true);
    elsif new.trang_thai = 'cho_phe_duyet' then
      perform cv_pd_gui(cv_pd_ds_role(array['giam_doc_sx']), 'tieu_chuan', 'can_duyet', v_khoa, v_lk,
        v_ten || ' đã được Trưởng phòng QC kiểm tra, đang chờ bạn phê duyệt.', true);
    elsif new.trang_thai = 'tra_lai' then
      perform cv_pd_gui(array[new.nguoi_lap_uid], 'tieu_chuan', 'tu_choi_duyet', v_khoa, v_lk,
        v_ten || ' bị trả lại' || coalesce(': ' || new.ly_do_tra_lai, '') || '.', false);
    elsif new.trang_thai = 'da_duyet' then
      perform cv_pd_gui(array[new.nguoi_lap_uid], 'tieu_chuan', 'da_duyet', v_khoa, v_lk,
        v_ten || ' đã được Giám đốc sản xuất phê duyệt — có hiệu lực cho IPQC.', false);
    end if;
  exception when others then
    raise warning 'T163 thông báo tiêu chuẩn lỗi (bỏ qua, không chặn thao tác): %', sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists trg_cv_pd_tc_btk on public.ipqc_btk;
create trigger trg_cv_pd_tc_btk after insert or update of trang_thai or delete on public.ipqc_btk
  for each row execute function public.cv_pd_trg_tieu_chuan();
drop trigger if exists trg_cv_pd_tc_cl on public.duc_ipqc_tieuchuan_de_xuat;
create trigger trg_cv_pd_tc_cl after insert or update of trang_thai or delete on public.duc_ipqc_tieuchuan_de_xuat
  for each row execute function public.cv_pd_trg_tieu_chuan();

revoke execute on function public.cv_pd_trg_tieu_chuan() from public, anon, authenticated;
