-- T221: STAGING only. Versioned signed deviations; historical values/bounds remain untouched.
begin;
alter table public.ipqc_btk_muc add column dung_sai_co_dau boolean not null default false;
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
  v_signed boolean := coalesce(p_cong_doan,'duc')='gia_cong' and coalesce((p_data->>'dung_sai_co_dau')::boolean,false);
  lo numeric;hi numeric;
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
    if v_signed and v_kieu='so' then
      if exists(select 1 from jsonb_each_text(m)x where x.key in('danh_nghia','dung_sai_tren','dung_sai_duoi','lsl','usl')
        and nullif(x.value,'')::numeric::text in('NaN','Infinity','-Infinity'))then
        return jsonb_build_object('ok',false,'error','Giá trị và sai lệch phải là số hữu hạn');
      end if;
      lo:=coalesce(nullif(m->>'lsl','')::numeric,nullif(m->>'danh_nghia','')::numeric+nullif(m->>'dung_sai_duoi','')::numeric);
      hi:=coalesce(nullif(m->>'usl','')::numeric,nullif(m->>'danh_nghia','')::numeric+nullif(m->>'dung_sai_tren','')::numeric);
      if lo>hi then return jsonb_build_object('ok',false,'error','LSL không được lớn hơn USL');end if;
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

  insert into ipqc_btk_muc (id_btk, muc_no, hang_muc, kieu, danh_nghia, dung_sai_tren, dung_sai_duoi, tieu_chuan, dung_cu, tan_suat, ma_dac_tinh, don_vi, phuong_phap, lsl, usl, co_mau, nguon_nhan_dien, dung_sai_co_dau)
  select v_id, (j.v ->> 'muc_no')::int, trim(j.v ->> 'hang_muc'), j.v ->> 'kieu',
    case when j.v ->> 'kieu' = 'so' then nullif(j.v ->> 'danh_nghia', '')::numeric end,
    case when j.v ->> 'kieu' = 'so' then case when v_signed then nullif(j.v ->> 'dung_sai_tren', '')::numeric else abs(nullif(j.v ->> 'dung_sai_tren', '')::numeric) end end,
    case when j.v ->> 'kieu' = 'so' then case when v_signed then nullif(j.v ->> 'dung_sai_duoi', '')::numeric else abs(nullif(j.v ->> 'dung_sai_duoi', '')::numeric) end end,
    nullif(trim(j.v ->> 'tieu_chuan'), ''), nullif(trim(j.v ->> 'dung_cu'), ''), nullif(trim(j.v ->> 'tan_suat'), ''),nullif(trim(j.v->>'ma_dac_tinh'),''),
    nullif(trim(j.v->>'don_vi'),''),nullif(trim(j.v->>'phuong_phap'),''),coalesce(nullif(j.v->>'lsl','')::numeric,case when v_signed and (j.v->>'kieu')='so' then nullif(j.v->>'danh_nghia','')::numeric+nullif(j.v->>'dung_sai_duoi','')::numeric end),
    coalesce(nullif(j.v->>'usl','')::numeric,case when v_signed and (j.v->>'kieu')='so' then nullif(j.v->>'danh_nghia','')::numeric+nullif(j.v->>'dung_sai_tren','')::numeric end),nullif(j.v->>'co_mau','')::integer,j.v->'nguon_nhan_dien',v_signed
  from jsonb_array_elements(p_data -> 'muc') as j(v);

  return jsonb_build_object('ok', true, 'id', v_id, 'phien_ban', v_pb);
end $function$;
revoke all on function public.ipqc_btk_luu(text,jsonb,text,text) from public,anon;
grant execute on function public.ipqc_btk_luu(text,jsonb,text,text) to authenticated;
CREATE OR REPLACE FUNCTION public.ipqc_gc_luu_do_t217(p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b ipqc_btk%rowtype;mu ipqc_btk_muc%rowtype;e jsonb;v numeric;ok boolean;all_ok boolean:=true;
 v_id uuid;prior ipqc_gc_lan%rowtype;req uuid:=(p_data->>'request_id')::uuid;actor text;
 n integer;minimum integer;s integer;max_samples integer:=1;lo numeric;hi numeric;expected integer:=0;
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
 select * into b from ipqc_btk where id=(p_data->>'id_btk')::bigint for share;
 if b.id is null or b.cong_doan is distinct from 'gia_cong' or b.ma_sp is distinct from p_data->>'ma_sp'
  or b.trang_thai is distinct from 'da_duyet' or not b.dang_dung
  or b.ngay_hieu_luc>(now()at time zone'Asia/Ho_Chi_Minh')::date then
  raise exception 'Chọn đúng tiêu chuẩn Gia công đã phát hành và đang có hiệu lực';end if;
 if not exists(select 1 from master_machines where ma_may=p_data->>'ma_may' and bo_phan='Gia công - Sơn')then raise exception 'Chọn máy Gia công trong danh mục';end if;
 if coalesce(p_data->>'ca','')not in('Ca ngày','Ca đêm','Ca 1','Ca 2')or nullif(trim(p_data->>'ma_lo'),'')is null then raise exception 'Chọn ca và nhập mã lô';end if;
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
 insert into ipqc_gc_lan(request_id,payload_hash,id_btk,ma_sp,revision,buoc_gia_cong,ma_may,ca,ma_lo,nguoi_kiem_uid,nguoi_kiem,so_mau,dat,tieu_chuan,co_mau_thuc_te)
 values(req,md5(p_data::text),b.id,b.ma_sp,b.phien_ban,b.buoc_gia_cong,p_data->>'ma_may',p_data->>'ca',trim(p_data->>'ma_lo'),auth.uid(),actor,max_samples,all_ok,
 jsonb_build_object('btk',to_jsonb(b),'muc',(select jsonb_agg(to_jsonb(m)order by m.muc_no)from ipqc_btk_muc m where m.id_btk=b.id)),counts)returning id into v_id;
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
revoke all on function public.ipqc_gc_luu_do_t217(jsonb) from public,anon,authenticated;
commit;
