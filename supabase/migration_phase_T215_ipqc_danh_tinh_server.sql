-- ĐÃ ÁP DỤNG PROD 09/11/2026 (gộp theo mảng, bỏ phiên bản hàm trung gian; bản cuối các hàm đã sửa xem T230).
-- T215: danh tính người soạn/duyệt lấy từ phiên server; đã áp dụng STAGING 04/11/2026.
begin;
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
  if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
  select coalesce(nullif(full_name,''),username) into p_nguoi from user_roles where user_id=auth.uid();
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
  select * into v_cu from ipqc_btk where ma_sp = v_ma and cong_doan = v_cd and(v_cd<>'gia_cong' or buoc_gia_cong is not distinct from nullif(trim(p_data->>'buoc_gia_cong'),'')) and dang_dung;
  select * into v_nhap from ipqc_btk where ma_sp = v_ma and cong_doan = v_cd and(v_cd<>'gia_cong' or buoc_gia_cong is not distinct from nullif(trim(p_data->>'buoc_gia_cong'),'')) and trang_thai <> 'da_duyet' for update;
  if v_cd='gia_cong'and(coalesce(v_nhap.buoc_gia_cong,v_cu.buoc_gia_cong)is not null)and not(p_data?'ma_ban_ve')then
      return jsonb_build_object('ok',false,'error','Mở màn Tiêu chuẩn IPQC Gia công để sửa đầy đủ đặc tính và bản vẽ');
  end if;
  if v_pb is null then
    v_pb := case when v_nhap.id is not null then v_nhap.phien_ban
                 when v_cu.id is null then 'A'
                 when v_cu.phien_ban ~ '^[A-Y]$' then chr(ascii(v_cu.phien_ban) + 1)
                 else v_cu.phien_ban || '.1' end;
  end if;
  if exists (select 1 from ipqc_btk where ma_sp = v_ma and cong_doan = v_cd and(v_cd<>'gia_cong' or buoc_gia_cong is not distinct from nullif(trim(p_data->>'buoc_gia_cong'),'')) and phien_ban = v_pb and id is distinct from v_nhap.id) then
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
    if v_kieu = 'so' and nullif(m->>'lsl','') is null and nullif(m->>'usl','') is null and (nullif(m ->> 'danh_nghia', '') is null or (nullif(m ->> 'dung_sai_tren', '') is null and nullif(m ->> 'dung_sai_duoi', '') is null)) then
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
    insert into ipqc_btk (ma_sp, cong_doan, buoc_gia_cong, phien_ban, ngay_hieu_luc, so_mau, tan_suat, ma_bieu, ban_ve_url, ban_ve_vi_tri,
      noi_dung_sua_doi, nguoi_lap, nguoi_lap_uid, dang_dung, trang_thai, gui_luc)
    values (v_ma, v_cd, nullif(trim(p_data->>'buoc_gia_cong'),''), v_pb, coalesce(nullif(p_data ->> 'ngay_hieu_luc', '')::date, (now() at time zone 'Asia/Ho_Chi_Minh')::date),
      coalesce((p_data ->> 'so_mau')::int, 1), coalesce(nullif(trim(p_data ->> 'tan_suat'), ''), '2h/lần'),
      coalesce(nullif(trim(p_data ->> 'ma_bieu'), ''), 'QP-82405-B'),
      coalesce(nullif(p_data ->> 'ban_ve_url', ''), v_cu.ban_ve_url),
      coalesce(p_data -> 'ban_ve_vi_tri', v_cu.ban_ve_vi_tri, '[]'::jsonb),
      coalesce(nullif(trim(p_data ->> 'noi_dung_sua_doi'), ''), case when v_cu.id is null then 'Lập mới' else 'Sửa đổi' end),
      p_nguoi, auth.uid(), false, 'cho_kiem_tra', now())
    returning id into v_id;
  end if;

  insert into ipqc_btk_muc (id_btk, muc_no, hang_muc, kieu, danh_nghia, dung_sai_tren, dung_sai_duoi, tieu_chuan, dung_cu, tan_suat, ma_dac_tinh, don_vi, phuong_phap, lsl, usl, co_mau, nguon_nhan_dien)
  select v_id, (j.v ->> 'muc_no')::int, trim(j.v ->> 'hang_muc'), j.v ->> 'kieu',
    case when j.v ->> 'kieu' = 'so' then nullif(j.v ->> 'danh_nghia', '')::numeric end,
    case when j.v ->> 'kieu' = 'so' then abs(nullif(j.v ->> 'dung_sai_tren', '')::numeric) end,
    case when j.v ->> 'kieu' = 'so' then abs(nullif(j.v ->> 'dung_sai_duoi', '')::numeric) end,
    nullif(trim(j.v ->> 'tieu_chuan'), ''), nullif(trim(j.v ->> 'dung_cu'), ''), nullif(trim(j.v ->> 'tan_suat'), ''),nullif(trim(j.v->>'ma_dac_tinh'),''),
    nullif(trim(j.v->>'don_vi'),''),nullif(trim(j.v->>'phuong_phap'),''),nullif(j.v->>'lsl','')::numeric,
    nullif(j.v->>'usl','')::numeric,nullif(j.v->>'co_mau','')::integer,j.v->'nguon_nhan_dien'
  from jsonb_array_elements(p_data -> 'muc') as j(v);

  return jsonb_build_object('ok', true, 'id', v_id, 'phien_ban', v_pb);
end $function$;
revoke all on function public.ipqc_btk_luu(text,jsonb,text,text) from public,anon;
grant execute on function public.ipqc_btk_luu(text,jsonb,text,text) to authenticated;
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
  if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
  select coalesce(nullif(full_name,''),username) into p_nguoi from user_roles where user_id=auth.uid();
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
      update ipqc_btk set dang_dung = false where ma_sp = v_ma and cong_doan = v_cd and dang_dung and(v_cd<>'gia_cong' or buoc_gia_cong is not distinct from b.buoc_gia_cong);
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
end $function$;
revoke all on function public.ipqc_tc_duyet(text,bigint,text,text,text) from public,anon;
grant execute on function public.ipqc_tc_duyet(text,bigint,text,text,text) to authenticated;

-- Giữ khóa nội dung đối sách cũ sau khi gửi duyệt; hạn/loại vẫn được cập nhật.
create or replace function public.ncp_luu_doi_sach(p_id uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare d ncp_doi_sach%rowtype;r duc_ncp%rowtype;v uuid;items jsonb;field text;caseid text;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 if p_id is null then caseid:=p_data->>'id_ncp';
 else select id_ncp into caseid from ncp_doi_sach where id=p_id;end if;
 -- Cùng thứ tự khóa với luồng lưu phiếu cũ, tránh khóa chéo phiếu/đối sách.
 select * into r from duc_ncp where id_ncp=caseid for update;
 if p_id is not null then
  select * into d from ncp_doi_sach where id=p_id for update;
  if d.da_luu_tru then raise exception 'Dòng này đã bỏ khỏi phiếu; hãy tải lại';end if;
  if d.nhom_cu is not null and r.rc_trang_thai_duyet in ('cho_duyet','da_duyet')
   and (nullif(p_data->>'noi_dung_tra_loi','') is distinct from nullif(d.noi_dung_tra_loi,'')
    or nullif(p_data->>'nguoi_phu_trach','') is distinct from nullif(d.nguoi_phu_trach,'')) then
   raise exception 'Mở lại đối sách đã gửi duyệt trước khi sửa nội dung hoặc người thực hiện';
  end if;
 end if;
 v:=ncp_luu_doi_sach_t212(p_id,p_data);
 if d.nhom_cu is not null then
  field:='doi_sach_'||d.nhom_cu||'_json';
  select jsonb_agg(case when ordinality=d.vi_tri_cu then value||jsonb_build_object(
   'id_doi_sach',v,'noi_dung',coalesce(p_data->>'noi_dung_tra_loi',''),
   'nguoi_thuc_hien',coalesce(p_data->>'nguoi_phu_trach','')) else value end order by ordinality)
   into items from jsonb_array_elements(to_jsonb(r)->field)with ordinality;
  execute format('update public.duc_ncp set %I=$1 where id_ncp=$2',field) using items,r.id_ncp;
 end if;
 return v;
end $$;
revoke all on function public.ncp_luu_doi_sach(uuid,jsonb) from public,anon;
grant execute on function public.ncp_luu_doi_sach(uuid,jsonb) to authenticated;

commit;
