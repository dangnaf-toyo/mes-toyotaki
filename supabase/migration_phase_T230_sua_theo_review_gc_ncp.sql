-- T230: Sửa theo review trước prod phần IPQC Gia công / NCP của đồng đội (09/11/2026). Chạy sau T210–T219, T221–T223, T228.
-- 1) duc_ncp_open_case: thêm lại kiểm tra bắt buộc hạn trả lời đối sách (T212 làm mất).
-- 2) ipqc_gc_tieu_chuan_theo_ngay: thêm tham số bước. Một bước thì tự chọn; nhiều bước thì trả 'chon_buoc'; cùng bước lấy bản duyệt sau cùng
--    (T223 báo "chồng lấn" với mã nhiều bước hoặc 2 bản duyệt cùng ngày).
-- 3) ipqc_gc_luu_do_t217: kiểm đúng theo bước của tiêu chuẩn đang nhập.
-- 4) Bản vẽ và file kết quả đo: chỉ nhóm QC và quản lý được đọc.
begin;
CREATE OR REPLACE FUNCTION public.duc_ncp_open_case(p_id_checkpoint_goc text, p_ma_may text, p_ma_sp text, p_ten_sp text, p_so_khuon text, p_mo_ta_loi text, p_so_luong_nghi_van numeric, p_so_luong_ng_du_kien numeric, p_vi_tri_cach_ly text, p_nguoi_dam_nhiem text, p_nguoi_dam_nhiem_doi_sach text, p_user text, p_han_tra_loi_doi_sach date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id_ncp text;
  v_existing text;
  v_now timestamptz := now();
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
  select coalesce(nullif(trim(username),''),email) into p_user from user_roles where user_id=auth.uid();
  if p_han_tra_loi_doi_sach is null then raise exception 'Chọn hạn trả lời đối sách (tải lại trang nếu chưa thấy trường này)'; end if;
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
    nguoi_dam_nhiem, nguoi_dam_nhiem_doi_sach, han_tra_loi_doi_sach, nguoi_mo_uid,
    so_luong_da_loc, so_luong_loc_ok, so_luong_loc_ng, so_luong_sua_ok, so_luong_sua_khong_duoc,
    so_luong_de_nghi_phe, so_luong_phe_da_duyet, trang_thai, rc_trang_thai_duyet, ghi_chu, last_updated_at
  ) values (
    v_id_ncp, nullif(p_id_checkpoint_goc, ''), v_now, p_ma_may, p_ma_sp, p_ten_sp, p_so_khuon, trim(p_mo_ta_loi),
    p_so_luong_nghi_van, p_so_luong_ng_du_kien, trim(p_vi_tri_cach_ly), p_user,
    trim(p_nguoi_dam_nhiem), trim(p_nguoi_dam_nhiem_doi_sach), p_han_tra_loi_doi_sach, auth.uid(),
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
$function$
;
revoke all on function public.duc_ncp_open_case(text,text,text,text,text,text,numeric,numeric,text,text,text,text,date) from public,anon;
grant execute on function public.duc_ncp_open_case(text,text,text,text,text,text,numeric,numeric,text,text,text,text,date) to authenticated;
drop function if exists public.ipqc_gc_tieu_chuan_theo_ngay(text,date);
create function public.ipqc_gc_tieu_chuan_theo_ngay(p_ma_sp text,p_ngay_kiem date,p_buoc text default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare scopes text[];scope text;b ipqc_btk%rowtype;
begin
 if auth.uid()is null then raise exception 'Cần đăng nhập MES'using errcode='42501';end if;
 select array_agg(s.v order by s.v)into scopes from(select distinct coalesce(nullif(trim(x.buoc_gia_cong),''),'')as v
  from ipqc_btk x where x.ma_sp=p_ma_sp and x.cong_doan='gia_cong' and x.trang_thai='da_duyet' and x.ngay_hieu_luc<=p_ngay_kiem)s;
 if coalesce(cardinality(scopes),0)=0 then return jsonb_build_object('status','none','message','Chưa có tiêu chuẩn.','btk',null,'muc','[]'::jsonb,'buoc','[]'::jsonb);end if;
 scope:=case when cardinality(scopes)=1 then scopes[1] when trim(p_buoc)=any(scopes) then trim(p_buoc) end;
 if scope is null then return jsonb_build_object('status','chon_buoc','message','Chọn bước gia công.','btk',null,'muc','[]'::jsonb,'buoc',to_jsonb(scopes));end if;
 -- Cùng bước: bản có ngày hiệu lực mới nhất; cùng ngày thì bản được phê duyệt sau cùng.
 select * into b from ipqc_btk x where x.ma_sp=p_ma_sp and x.cong_doan='gia_cong' and x.trang_thai='da_duyet'
  and x.ngay_hieu_luc<=p_ngay_kiem and coalesce(nullif(trim(x.buoc_gia_cong),''),'')=scope
  order by x.ngay_hieu_luc desc,x.phe_duyet_luc desc nulls last,x.id desc limit 1;
 return jsonb_build_object('status','ok','btk',to_jsonb(b),'muc',coalesce((select jsonb_agg(to_jsonb(m)order by m.muc_no)from ipqc_btk_muc m where m.id_btk=b.id),'[]'::jsonb),'buoc',to_jsonb(scopes));
end $$;
revoke all on function public.ipqc_gc_tieu_chuan_theo_ngay(text,date,text)from public,anon;
grant execute on function public.ipqc_gc_tieu_chuan_theo_ngay(text,date,text)to authenticated;
CREATE OR REPLACE FUNCTION public.ipqc_gc_luu_do_t217(p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b ipqc_btk%rowtype;mu ipqc_btk_muc%rowtype;e jsonb;v numeric;ok boolean;all_ok boolean:=true;
 v_id uuid;prior ipqc_gc_lan%rowtype;req uuid:=(p_data->>'request_id')::uuid;actor text;
 n integer;minimum integer;s integer;max_samples integer:=1;lo numeric;hi numeric;expected integer:=0;
 inspection_day date:=coalesce(nullif(p_data->>'ngay_kiem','')::date,(clock_timestamp()at time zone'Asia/Ho_Chi_Minh')::date);resolution jsonb;step text;
 counts jsonb:='{}';overrides jsonb:=coalesce(p_data->'co_mau_thuc_te','{}');
begin
 if auth.uid()is null or not has_role('admin','qc_manager','ipqc')then raise exception 'Chỉ IPQC hoặc quản lý QC được ghi kết quả';end if;
 if req is null then raise exception 'Thiếu mã lần gửi';end if;
 perform pg_advisory_xact_lock(hashtextextended('ipqc-gc:'||req::text,0));
 select * into prior from ipqc_gc_lan where request_id=req;
 if found then
  if prior.nguoi_kiem_uid<>auth.uid()or prior.payload_hash<>md5(p_data::text)then raise exception 'Mã gửi đã dùng cho nội dung khác';end if;
  return prior.id;
 end if;
 -- Coordinate with the existing approval lock before locking a released standard row.
 perform pg_advisory_xact_lock_shared(hashtext('ipqc_btk:gia_cong:'||(p_data->>'ma_sp')));
 select coalesce(nullif(trim(x.buoc_gia_cong),''),'')into step from ipqc_btk x where x.id=(p_data->>'id_btk')::bigint;
 resolution:=ipqc_gc_tieu_chuan_theo_ngay(p_data->>'ma_sp',inspection_day,step);
 if resolution->>'status'<>'ok' then raise exception '%',resolution->>'message';end if;
 if (resolution->'btk'->>'id')::bigint is distinct from (p_data->>'id_btk')::bigint then
  raise exception 'Tiêu chuẩn đã thay đổi. Chọn lại Model và ngày kiểm.';end if;
 select * into b from ipqc_btk where id=(p_data->>'id_btk')::bigint for share;
 if b.id is null or b.cong_doan is distinct from 'gia_cong' or b.ma_sp is distinct from p_data->>'ma_sp'
  or b.trang_thai is distinct from 'da_duyet'
  or b.ngay_hieu_luc is null or b.ngay_hieu_luc>inspection_day then
  raise exception 'Chọn đúng tiêu chuẩn Gia công đã phát hành và đang có hiệu lực';end if;
 if not exists(select 1 from master_machines where ma_may=p_data->>'ma_may' and bo_phan='Gia công - Sơn')then raise exception 'Chọn máy Gia công trong danh mục';end if;
 if coalesce(p_data->>'ca','')not in('Ca ngày','Ca đêm','Ca 1','Ca 2')then raise exception 'Chọn ca.';end if;
 if jsonb_typeof(p_data->'kq')is distinct from'array'then raise exception 'Thiếu kết quả đo';end if;
 if jsonb_typeof(overrides)is distinct from'object' then raise exception 'Cỡ mẫu thực tế không hợp lệ';end if;
 if exists(select 1 from jsonb_each_text(overrides)x where x.value!~'^[1-9][0-9]*$'
  or not exists(select 1 from ipqc_btk_muc m where m.id_btk=b.id and m.muc_no::text=x.key))
  then raise exception 'Cỡ mẫu phải là số nguyên và thuộc đặc tính đang kiểm';end if;
 select coalesce(nullif(full_name,''),username)into actor from user_roles where user_id=auth.uid();
 for mu in select * from ipqc_btk_muc where id_btk=b.id order by muc_no loop
  minimum:=coalesce(mu.co_mau,case when mu.kieu='okng' then 1 else b.so_mau end,1);
  n:=coalesce((overrides->>mu.muc_no::text)::integer,minimum);
  if n<minimum or n>100 then raise exception 'No % cần ít nhất % mẫu, tối đa 100',mu.muc_no,minimum;end if;
  counts:=counts||jsonb_build_object(mu.muc_no::text,n);max_samples:=greatest(max_samples,n);
  lo:=coalesce(mu.lsl,mu.danh_nghia+case when mu.dung_sai_co_dau then mu.dung_sai_duoi else -abs(mu.dung_sai_duoi) end);hi:=coalesce(mu.usl,mu.danh_nghia+case when mu.dung_sai_co_dau then mu.dung_sai_tren else abs(mu.dung_sai_tren) end);
  if mu.kieu='so' and lo is null and hi is null then raise exception 'Đặc tính % chưa có giới hạn kiểm tra; liên hệ quản lý QC',mu.muc_no;end if;
  for s in 1..n loop
   expected:=expected+1;
   if(select count(*)from jsonb_array_elements(p_data->'kq')x where(x->>'muc_no')::integer=mu.muc_no and(x->>'mau')::integer=s)<>1
    then raise exception 'Thiếu hoặc trùng kết quả No %, mẫu %',mu.muc_no,s;end if;
   select x into e from jsonb_array_elements(p_data->'kq')x where(x->>'muc_no')::integer=mu.muc_no and(x->>'mau')::integer=s;
   if mu.kieu='so'then
    v:=nullif(e->>'gia_tri','')::numeric;
    if v is null or v::text in('NaN','Infinity','-Infinity')then raise exception 'Nhập giá trị đo hữu hạn No %, mẫu %',mu.muc_no,s;end if;
    ok:=(lo is null or v>=lo)and(hi is null or v<=hi);
   else ok:=(e->>'dat')::boolean;if ok is null then raise exception 'Chọn OK/NG No %, mẫu %',mu.muc_no,s;end if;
   end if;
   all_ok:=all_ok and ok;
  end loop;
 end loop;
 if expected=0 or expected<>jsonb_array_length(p_data->'kq')then raise exception 'Kết quả không khớp danh sách đặc tính';end if;
 insert into ipqc_gc_lan(request_id,payload_hash,id_btk,ma_sp,revision,buoc_gia_cong,ma_may,ca,ma_lo,nguoi_kiem_uid,nguoi_kiem,so_mau,dat,tieu_chuan,co_mau_thuc_te,ngay_kiem)
 values(req,md5(p_data::text),b.id,b.ma_sp,b.phien_ban,b.buoc_gia_cong,p_data->>'ma_may',p_data->>'ca',nullif(trim(p_data->>'ma_lo'),''),auth.uid(),actor,max_samples,all_ok,
 jsonb_build_object('btk',to_jsonb(b),'muc',(select jsonb_agg(to_jsonb(m)order by m.muc_no)from ipqc_btk_muc m where m.id_btk=b.id)),counts,inspection_day)returning id into v_id;
 for mu in select * from ipqc_btk_muc where id_btk=b.id loop
  lo:=coalesce(mu.lsl,mu.danh_nghia+case when mu.dung_sai_co_dau then mu.dung_sai_duoi else -abs(mu.dung_sai_duoi) end);hi:=coalesce(mu.usl,mu.danh_nghia+case when mu.dung_sai_co_dau then mu.dung_sai_tren else abs(mu.dung_sai_tren) end);
  for e in select x from jsonb_array_elements(p_data->'kq')x where(x->>'muc_no')::integer=mu.muc_no loop
   v:=case when mu.kieu='so'then(e->>'gia_tri')::numeric end;
   ok:=case when mu.kieu='so'then(lo is null or v>=lo)and(hi is null or v<=hi)else(e->>'dat')::boolean end;
   insert into ipqc_gc_kq(id_lan,muc_no,mau,gia_tri,dat)values(v_id,mu.muc_no,(e->>'mau')::integer,v,ok);
  end loop;
 end loop;
 return v_id;
end $function$;

revoke all on function public.ipqc_gc_luu_do_t217(jsonb)from public,anon,authenticated;
drop policy if exists ipqc_gc_file_doc on storage.objects;
create policy ipqc_gc_file_doc on storage.objects for select to authenticated using(bucket_id='ipqc-gia-cong-ban-ve' and public.has_role('admin','qc_manager','giam_doc_sx','ipqc','iqc','nhan_vien_oqc','iatf_admin'));
drop policy if exists ipqc_gc_ket_qua_doc on storage.objects;
create policy ipqc_gc_ket_qua_doc on storage.objects for select to authenticated using(bucket_id='ipqc-gia-cong-ket-qua' and public.has_role('admin','qc_manager','giam_doc_sx','ipqc','iqc','nhan_vien_oqc','iatf_admin'));
notify pgrst,'reload schema';
commit;
