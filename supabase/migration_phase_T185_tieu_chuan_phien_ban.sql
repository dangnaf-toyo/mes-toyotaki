-- Đã chạy STAGING 29/10/2026; chưa chạy PRODUCTION.
-- T185 — Tiêu chuẩn theo công đoạn, dùng chung T133/T163, giữ nguyên ID phiên bản cũ.
-- Nguồn cũ đã xác minh chỉ được ipqc.html (Đúc) đọc; không suy đoán từ mã sản phẩm.
begin;
alter table public.ipqc_do_lan add column if not exists cong_doan text not null default 'duc' check(cong_doan in ('duc','gia_cong'));
alter table public.ipqc_gioi_han add column if not exists cong_doan text not null default 'duc' check(cong_doan in ('duc','gia_cong'));
alter table public.ipqc_btk add column if not exists cong_doan text not null default 'duc' check(cong_doan in ('duc','gia_cong'));
alter table public.duc_ipqc_tieuchuan_de_xuat add column if not exists cong_doan text not null default 'duc' check(cong_doan in ('duc','gia_cong'));
alter table public.duc_ipqc_tieuchuan add column if not exists cong_doan text not null default 'duc' check(cong_doan in ('duc','gia_cong'));
alter table public.ipqc_btk drop constraint if exists ipqc_btk_ma_sp_phien_ban_key;
alter table public.ipqc_btk drop constraint if exists ipqc_btk_ma_sp_cd_phien_ban_key;
drop function if exists public.ipqc_btk_luu(text,jsonb,text);
alter table public.ipqc_btk add constraint ipqc_btk_cd_ma_pb_key unique(cong_doan,ma_sp,phien_ban);
drop index public.ipqc_btk_dang_dung_uq;
create unique index ipqc_btk_dang_dung_uq on public.ipqc_btk(cong_doan,ma_sp) where dang_dung;
drop index public.ipqc_btk_nhap_uq;
create unique index ipqc_btk_nhap_uq on public.ipqc_btk(cong_doan,ma_sp) where trang_thai<>'da_duyet';
drop index public.duc_ipqc_tc_dx_nhap_uq;
create unique index duc_ipqc_tc_dx_nhap_uq on public.duc_ipqc_tieuchuan_de_xuat(cong_doan,ma_sp) where trang_thai<>'da_duyet';
alter table public.duc_ipqc_tieuchuan drop constraint duc_ipqc_tieuchuan_pkey;
alter table public.duc_ipqc_tieuchuan add primary key(cong_doan,ma_sp);
CREATE OR REPLACE FUNCTION public.ipqc_btk_luu(p_ma_sp text, p_data jsonb, p_nguoi text, p_cong_doan text DEFAULT 'duc'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ma text := trim(coalesce(p_ma_sp, ''));
  v_cd text := coalesce(nullif(trim(p_cong_doan), ''), 'duc');
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
  if v_cd not in ('duc', 'gia_cong') then return jsonb_build_object('ok', false, 'error', 'Công đoạn không hợp lệ'); end if;
  if not exists (select 1 from master_products where ma_sp = v_ma) then
    return jsonb_build_object('ok', false, 'error', 'Mã SP không có trong danh mục: ' || v_ma);
  end if;
  if jsonb_array_length(coalesce(p_data -> 'muc', '[]'::jsonb)) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Cần ít nhất 1 hạng mục');
  end if;
  if coalesce((p_data ->> 'so_mau')::int, 1) not between 1 and 5 then
    return jsonb_build_object('ok', false, 'error', 'Số mẫu/lần phải từ 1 đến 5');
  end if;

  perform pg_advisory_xact_lock(hashtext('ipqc_btk:' || v_cd || ':' || v_ma));
  select * into v_cu from ipqc_btk where ma_sp = v_ma and cong_doan = v_cd and dang_dung;
  select * into v_nhap from ipqc_btk where ma_sp = v_ma and cong_doan = v_cd and trang_thai <> 'da_duyet' for update;
  if v_pb is null then
    v_pb := case when v_nhap.id is not null then v_nhap.phien_ban
                 when v_cu.id is null then 'A'
                 when v_cu.phien_ban ~ '^[A-Y]$' then chr(ascii(v_cu.phien_ban) + 1)
                 else v_cu.phien_ban || '.1' end;
  end if;
  if exists (select 1 from ipqc_btk where ma_sp = v_ma and cong_doan = v_cd and phien_ban = v_pb and id is distinct from v_nhap.id) then
    return jsonb_build_object('ok', false, 'error', 'Mã ' || v_ma || ' (' || ipqc_cd_ten(v_cd) || ') đã có phiên bản ' || v_pb);
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
    insert into ipqc_btk (ma_sp, cong_doan, phien_ban, ngay_hieu_luc, so_mau, tan_suat, ma_bieu, ban_ve_url, ban_ve_vi_tri,
      noi_dung_sua_doi, nguoi_lap, nguoi_lap_uid, dang_dung, trang_thai, gui_luc)
    values (v_ma, v_cd, v_pb, coalesce(nullif(p_data ->> 'ngay_hieu_luc', '')::date, (now() at time zone 'Asia/Ho_Chi_Minh')::date),
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
end $function$
;
revoke execute on function public.ipqc_btk_luu(p_ma_sp text, p_data jsonb, p_nguoi text, p_cong_doan text) from public,anon;
grant execute on function public.ipqc_btk_luu(p_ma_sp text, p_data jsonb, p_nguoi text, p_cong_doan text) to authenticated;

drop function if exists public.ipqc_tc_luu_checklist(text,jsonb,text,text,text);
CREATE OR REPLACE FUNCTION public.ipqc_tc_luu_checklist(p_ma_sp text, p_muc_kiem jsonb, p_pdf_url text, p_noi_dung text, p_nguoi text, p_cong_doan text DEFAULT 'duc'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ma text := trim(coalesce(p_ma_sp, ''));
  v_cd text := coalesce(nullif(trim(p_cong_doan), ''), 'duc');
  v_cu duc_ipqc_tieuchuan%rowtype;
  v_nhap duc_ipqc_tieuchuan_de_xuat%rowtype;
  v_pdf text := nullif(trim(coalesce(p_pdf_url, '')), '');
  v_id bigint;
begin
  if not public.has_role('ipqc', 'nhan_vien_oqc', 'qc_manager', 'admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ nhân viên QC / Trưởng phòng QC được soạn tiêu chuẩn');
  end if;
  if v_cd not in ('duc', 'gia_cong') then return jsonb_build_object('ok', false, 'error', 'Công đoạn không hợp lệ'); end if;
  if v_ma = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã SP'); end if;
  if not exists (select 1 from master_products where ma_sp = v_ma) then
    return jsonb_build_object('ok', false, 'error', 'Mã SP không có trong danh mục: ' || v_ma);
  end if;
  if jsonb_typeof(p_muc_kiem) is distinct from 'array' or jsonb_array_length(p_muc_kiem) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Checklist cần ít nhất 1 mục kiểm');
  end if;

  perform pg_advisory_xact_lock(hashtext('ipqc_tc:' || v_cd || ':' || v_ma));
  select * into v_cu from duc_ipqc_tieuchuan where ma_sp = v_ma and cong_doan = v_cd;
  select * into v_nhap from duc_ipqc_tieuchuan_de_xuat where ma_sp = v_ma and cong_doan = v_cd and trang_thai <> 'da_duyet' for update;

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
    insert into duc_ipqc_tieuchuan_de_xuat (ma_sp, cong_doan, danh_sach_muc_kiem_json, file_pdf_url, noi_dung_sua_doi,
      nguoi_lap, nguoi_lap_uid)
    values (v_ma, v_cd, p_muc_kiem, coalesce(v_pdf, v_cu.file_pdf_url),
      coalesce(nullif(trim(p_noi_dung), ''), case when v_cu.ma_sp is null then 'Lập mới' else 'Sửa đổi' end),
      p_nguoi, auth.uid())
    returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $function$
;
revoke execute on function public.ipqc_tc_luu_checklist(p_ma_sp text, p_muc_kiem jsonb, p_pdf_url text, p_noi_dung text, p_nguoi text, p_cong_doan text) from public,anon;
grant execute on function public.ipqc_tc_luu_checklist(p_ma_sp text, p_muc_kiem jsonb, p_pdf_url text, p_noi_dung text, p_nguoi text, p_cong_doan text) to authenticated;

CREATE OR REPLACE FUNCTION public.ipqc_tc_duyet(p_loai text, p_id bigint, p_hanh_dong text, p_ly_do text, p_nguoi text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tt text;
  v_ma text;
  v_cd text;
  v_moi text;
  v_ly_do text := nullif(trim(coalesce(p_ly_do, '')), '');
  v_hom_nay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  b ipqc_btk%rowtype;
  c duc_ipqc_tieuchuan_de_xuat%rowtype;
begin
  if p_loai = 'btk' then
    select * into b from ipqc_btk where id = p_id for update;
    v_tt := b.trang_thai; v_ma := b.ma_sp; v_cd := b.cong_doan;
  elsif p_loai = 'checklist' then
    select * into c from duc_ipqc_tieuchuan_de_xuat where id = p_id for update;
    v_tt := c.trang_thai; v_ma := c.ma_sp; v_cd := c.cong_doan;
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
      perform pg_advisory_xact_lock(hashtext('ipqc_btk:' || v_cd || ':' || v_ma));
      update ipqc_btk set dang_dung = false where ma_sp = v_ma and cong_doan = v_cd and dang_dung;
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
      insert into duc_ipqc_tieuchuan (ma_sp, cong_doan, danh_sach_muc_kiem_json, file_pdf_url, cap_nhat_lan_cuoi_boi, thoi_diem_cap_nhat)
      values (v_ma, v_cd, c.danh_sach_muc_kiem_json, c.file_pdf_url, c.nguoi_lap, now())
      on conflict (ma_sp, cong_doan) do update set
        danh_sach_muc_kiem_json = excluded.danh_sach_muc_kiem_json, file_pdf_url = excluded.file_pdf_url,
        cap_nhat_lan_cuoi_boi = excluded.cap_nhat_lan_cuoi_boi, thoi_diem_cap_nhat = excluded.thoi_diem_cap_nhat;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'trang_thai', v_moi);
end $function$
;
revoke execute on function public.ipqc_tc_duyet(p_loai text, p_id bigint, p_hanh_dong text, p_ly_do text, p_nguoi text) from public,anon;
grant execute on function public.ipqc_tc_duyet(p_loai text, p_id bigint, p_hanh_dong text, p_ly_do text, p_nguoi text) to authenticated;

CREATE OR REPLACE FUNCTION public.cv_pd_trg_tieu_chuan()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      v_ten := 'Bảng tuần kiểm ' || ipqc_cd_ten(new.cong_doan) || ' mã ' || new.ma_sp || ' (phiên bản ' || new.phien_ban || ')';
    else
      v_khoa := 'tc:cl:' || new.id;
      v_ten := 'Checklist / PDF tiêu chuẩn ' || ipqc_cd_ten(new.cong_doan) || ' mã ' || new.ma_sp;
    end if;
    v_lk := 'qc-manager.html?tab=tieuchuan&ma=' || new.ma_sp || '&cd=' || new.cong_doan;
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
$function$
;
revoke all on function public.cv_pd_trg_tieu_chuan() from public,anon,authenticated;
create or replace function public.ipqc_tc_hieu_luc(p_ma_sp text,p_cong_doan text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare b ipqc_btk%rowtype;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
 if p_cong_doan is null or p_cong_doan not in ('duc','gia_cong') then raise exception 'Chọn đúng công đoạn'; end if;
 select * into b from ipqc_btk where ma_sp=p_ma_sp and cong_doan=p_cong_doan and trang_thai='da_duyet'
 and coalesce(ngay_hieu_luc,'-infinity'::date)<=(now() at time zone 'Asia/Ho_Chi_Minh')::date
 order by ngay_hieu_luc desc nulls last, phe_duyet_luc desc nulls last, id desc limit 1;
 return jsonb_build_object('btk',case when b.id is not null then to_jsonb(b) end,
 'muc',(select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('min',m.danh_nghia-m.dung_sai_duoi,'max',m.danh_nghia+m.dung_sai_tren) order by m.muc_no),'[]') from ipqc_btk_muc m where m.id_btk=b.id),
 'checklist',(select to_jsonb(t) from duc_ipqc_tieuchuan t where t.ma_sp=p_ma_sp and t.cong_doan=p_cong_doan));
end $$;
revoke all on function public.ipqc_tc_hieu_luc(text,text) from public,anon;
grant execute on function public.ipqc_tc_hieu_luc(text,text) to authenticated;
CREATE OR REPLACE FUNCTION public.ipqc_do_du_lieu(p_ma_sp text, p_tu timestamp with time zone, p_den timestamp with time zone, p_so_lan integer, p_cong_doan text DEFAULT 'duc'::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with b as (select * from ipqc_btk where id=((ipqc_tc_hieu_luc(p_ma_sp,p_cong_doan)->'btk')->>'id')::bigint),
  lan as (
    select l.*, c.ket_qua from ipqc_do_lan l join duc_ipqc_checkpoint c on c.id_checkpoint = l.id_checkpoint and c.ket_qua is not null
    where l.ma_sp = p_ma_sp and l.cong_doan = p_cong_doan
      and (p_so_lan is not null or ((p_tu is null or l.thoi_diem >= p_tu) and (p_den is null or l.thoi_diem <= p_den)))
    order by l.thoi_diem desc limit coalesce(p_so_lan, 5000)
  )
  select jsonb_build_object(
    'btk', (select to_jsonb(b) from b),
    'muc', (select coalesce(jsonb_agg(to_jsonb(m) order by m.muc_no), '[]'::jsonb) from ipqc_btk_muc m where m.id_btk = (select id from b)),
    'gioi_han', (select coalesce(jsonb_agg(to_jsonb(h)), '[]'::jsonb) from ipqc_gioi_han h
                 where h.ma_sp = p_ma_sp and h.cong_doan = p_cong_doan and h.dang_dung),
    'lan', (select coalesce(jsonb_agg(jsonb_build_object('id_checkpoint', l.id_checkpoint, 'thoi_diem', l.thoi_diem, 'ma_may', l.ma_may,
              'id_btk',l.id_btk,'tieu_chuan',(select to_jsonb(v) from ipqc_btk v where v.id=l.id_btk),'muc_tieu_chuan',(select jsonb_agg(to_jsonb(m) order by m.muc_no) from ipqc_btk_muc m where m.id_btk=l.id_btk),'so_khuon', l.so_khuon, 'nguoi', l.nguoi, 'dat', l.dat, 'ket_qua', l.ket_qua,
              'kq', (select coalesce(jsonb_agg(jsonb_build_object('muc_no', k.muc_no, 'mau', k.mau, 'gia_tri', k.gia_tri, 'dat', k.dat)
                       order by k.muc_no, k.mau), '[]'::jsonb) from ipqc_do_kq k where k.id_checkpoint = l.id_checkpoint))
            order by l.thoi_diem), '[]'::jsonb) from lan l));
$function$
;
revoke execute on function public.ipqc_do_du_lieu(p_ma_sp text, p_tu timestamp with time zone, p_den timestamp with time zone, p_so_lan integer, p_cong_doan text) from public,anon;
grant execute on function public.ipqc_do_du_lieu(p_ma_sp text, p_tu timestamp with time zone, p_den timestamp with time zone, p_so_lan integer, p_cong_doan text) to authenticated;

drop function public.ipqc_do_luu(text,jsonb,text);
CREATE OR REPLACE FUNCTION public.ipqc_do_luu(p_id_checkpoint text, p_kq jsonb, p_nguoi text, p_id_btk bigint default null)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c duc_ipqc_checkpoint%rowtype;
  b ipqc_btk%rowtype;
  mu ipqc_btk_muc%rowtype;
  x jsonb;
  v_gt numeric; v_dat boolean; v_all boolean := true;
  v_thieu text[] := '{}';
  v_mau int;
  v_ng jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into c from duc_ipqc_checkpoint where id_checkpoint = p_id_checkpoint;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy điểm kiểm ' || coalesce(p_id_checkpoint, '')); end if;
  if c.ket_qua is not null then return jsonb_build_object('ok', false, 'error', 'Lần kiểm này đã nộp kết quả — không sửa được kết quả đo'); end if;
  select * into b from ipqc_btk where id=((ipqc_tc_hieu_luc(c.ma_sp,'duc')->'btk')->>'id')::bigint;
  if p_id_btk is not null and p_id_btk is distinct from b.id then raise exception 'Tiêu chuẩn vừa thay đổi. Mở lại phiếu để lấy phiên bản có hiệu lực mới nhất.'; end if;
  if not found then return jsonb_build_object('ok', false, 'error', 'Mã ' || c.ma_sp || ' chưa có bảng tuần kiểm'); end if;

  delete from ipqc_do_lan where id_checkpoint = c.id_checkpoint;
  insert into ipqc_do_lan (id_checkpoint, id_btk, ma_sp, ma_may, so_khuon, nguoi, nguoi_uid, dat)
  values (c.id_checkpoint, b.id, c.ma_sp, c.ma_may,
    (select so_khuon from duc_ca_hien_tai where id_dong = c.id_dong), p_nguoi, auth.uid(), true);

  for mu in select * from ipqc_btk_muc where id_btk = b.id order by muc_no loop
    for v_mau in 1 .. case when mu.kieu = 'so' then b.so_mau else 1 end loop
      x := null;
      select e.v into x from jsonb_array_elements(coalesce(p_kq, '[]'::jsonb)) as e(v)
      where (e.v ->> 'muc_no')::int = mu.muc_no and coalesce((e.v ->> 'mau')::int, 1) = v_mau limit 1;
      if mu.kieu = 'so' then
        v_gt := nullif(x ->> 'gia_tri', '')::numeric;
        if v_gt is null then v_thieu := v_thieu || (mu.muc_no || case when b.so_mau > 1 then '/' || v_mau else '' end); continue; end if;
        v_dat := (mu.dung_sai_tren is null or v_gt <= mu.danh_nghia + mu.dung_sai_tren)
             and (mu.dung_sai_duoi is null or v_gt >= mu.danh_nghia - mu.dung_sai_duoi);
      else
        v_gt := null;
        v_dat := (x ->> 'dat')::boolean;
        if v_dat is null then v_thieu := v_thieu || mu.muc_no::text; continue; end if;
      end if;
      insert into ipqc_do_kq (id_checkpoint, muc_no, mau, gia_tri, dat) values (c.id_checkpoint, mu.muc_no, v_mau, v_gt, v_dat);
      if not v_dat then
        v_all := false;
        v_ng := v_ng || jsonb_build_array(jsonb_build_object('muc_no', mu.muc_no, 'mau', v_mau, 'gia_tri', v_gt));
      end if;
    end loop;
  end loop;

  if array_length(v_thieu, 1) > 0 then
    raise exception 'Chưa nhập kết quả đo hạng mục: %', array_to_string(v_thieu, ', ');
  end if;
  update ipqc_do_lan set dat = v_all where id_checkpoint = c.id_checkpoint;
  return jsonb_build_object('ok', true, 'dat', v_all, 'ng', v_ng, 'phien_ban', b.phien_ban);
end $function$
;
revoke execute on function public.ipqc_do_luu(p_id_checkpoint text, p_kq jsonb, p_nguoi text, p_id_btk bigint) from public,anon;
grant execute on function public.ipqc_do_luu(p_id_checkpoint text, p_kq jsonb, p_nguoi text, p_id_btk bigint) to authenticated;

CREATE OR REPLACE FUNCTION public.ipqc_gioi_han_tu_khoa(p_ma_sp text, p_cong_doan text DEFAULT 'duc'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m record; g jsonb;
begin
  for m in select mu.muc_no from ipqc_btk b join ipqc_btk_muc mu on mu.id_btk = b.id
           where b.ma_sp = p_ma_sp and b.cong_doan = p_cong_doan and b.dang_dung and mu.kieu = 'so'
             and not exists (select 1 from ipqc_gioi_han h where h.ma_sp = p_ma_sp and h.cong_doan = p_cong_doan
                               and h.muc_no = mu.muc_no and h.dang_dung)
  loop
    g := ipqc_gioi_han_tinh(p_ma_sp, m.muc_no, null, null, 30, p_cong_doan);
    if g is not null and (g ->> 'n_lan')::int >= 30 then
      insert into ipqc_gioi_han (ma_sp, cong_doan, muc_no, so_mau, cl, ucl, lcl, cl_r, ucl_r, n_lan, cach, ghi_chu, nguoi)
      values (p_ma_sp, p_cong_doan, m.muc_no, (g ->> 'so_mau')::int, (g ->> 'cl')::numeric, (g ->> 'ucl')::numeric, (g ->> 'lcl')::numeric,
        (g ->> 'cl_r')::numeric, (g ->> 'ucl_r')::numeric, 30, 'tu_dong', 'Tự khoá sau 30 lần đo đầu', 'Hệ thống');
    end if;
  end loop;
end $function$
;
revoke execute on function public.ipqc_gioi_han_tu_khoa(p_ma_sp text, p_cong_doan text) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION public.ipqc_gioi_han_dat(p_ma_sp text, p_muc_no integer, p_cach text, p_tu timestamp with time zone, p_den timestamp with time zone, p_gt jsonb, p_ghi_chu text, p_nguoi text, p_cong_doan text DEFAULT 'duc'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g jsonb; v_so_mau int;
begin
  if not public.has_role('qc_manager', 'admin') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ QC Manager / admin được đặt giới hạn kiểm soát');
  end if;
  if p_cong_doan not in ('duc', 'gia_cong') then return jsonb_build_object('ok', false, 'error', 'Công đoạn không hợp lệ'); end if;
  if coalesce(trim(p_ghi_chu), '') = '' then return jsonb_build_object('ok', false, 'error', 'Nhập lý do (cải tiến / điều chỉnh gì)'); end if;
  if p_cach = 'tinh_lai' then
    g := ipqc_gioi_han_tinh(p_ma_sp, p_muc_no, p_tu, p_den, 30, p_cong_doan);
    if g is null or (g ->> 'n_lan')::int < 10 then
      return jsonb_build_object('ok', false, 'error', 'Khoảng đã chọn có ít hơn 10 lần đo — chưa đủ để tính giới hạn');
    end if;
  elsif p_cach = 'tay' then
    select so_mau into v_so_mau from ipqc_btk where ma_sp = p_ma_sp and cong_doan = p_cong_doan and dang_dung;
    g := p_gt || jsonb_build_object('so_mau', coalesce(v_so_mau, 1), 'n_lan', 0);
    if (g ->> 'ucl')::numeric is null or (g ->> 'lcl')::numeric is null or (g ->> 'cl')::numeric is null
       or (g ->> 'ucl')::numeric <= (g ->> 'lcl')::numeric then
      return jsonb_build_object('ok', false, 'error', 'Giới hạn nhập tay không hợp lệ (cần CL, UCL > LCL)');
    end if;
  else
    return jsonb_build_object('ok', false, 'error', 'Cách đặt không hợp lệ');
  end if;
  update ipqc_gioi_han set dang_dung = false where ma_sp = p_ma_sp and cong_doan = p_cong_doan and muc_no = p_muc_no and dang_dung;
  insert into ipqc_gioi_han (ma_sp, cong_doan, muc_no, so_mau, cl, ucl, lcl, cl_r, ucl_r, n_lan, cach, tu_luc, den_luc, ghi_chu, nguoi)
  values (p_ma_sp, p_cong_doan, p_muc_no, (g ->> 'so_mau')::int, (g ->> 'cl')::numeric, (g ->> 'ucl')::numeric, (g ->> 'lcl')::numeric,
    coalesce((g ->> 'cl_r')::numeric, 0), coalesce((g ->> 'ucl_r')::numeric, 0), (g ->> 'n_lan')::int, p_cach,
    p_tu, p_den, trim(p_ghi_chu), p_nguoi);
  return jsonb_build_object('ok', true, 'gioi_han', g);
end $function$
;
revoke execute on function public.ipqc_gioi_han_dat(p_ma_sp text, p_muc_no integer, p_cach text, p_tu timestamp with time zone, p_den timestamp with time zone, p_gt jsonb, p_ghi_chu text, p_nguoi text, p_cong_doan text) from public,anon;
commit;
