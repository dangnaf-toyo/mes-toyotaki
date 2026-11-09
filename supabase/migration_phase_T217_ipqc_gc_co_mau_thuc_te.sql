-- ĐÃ ÁP DỤNG PROD 09/11/2026 (gộp theo mảng, bỏ phiên bản hàm trung gian; bản cuối các hàm đã sửa xem T230).
-- T217: cỡ mẫu thực tế; đã áp dụng STAGING 05/11/2026. Không sửa dữ liệu tiêu chuẩn.
begin;
alter table public.ipqc_gc_lan add column co_mau_thuc_te jsonb;
create or replace function public.ipqc_gc_luu_do(p_data jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
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
  lo:=coalesce(mu.lsl,mu.danh_nghia-abs(mu.dung_sai_duoi));hi:=coalesce(mu.usl,mu.danh_nghia+abs(mu.dung_sai_tren));
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
  lo:=coalesce(mu.lsl,mu.danh_nghia-abs(mu.dung_sai_duoi));hi:=coalesce(mu.usl,mu.danh_nghia+abs(mu.dung_sai_tren));
  for e in select x from jsonb_array_elements(p_data->'kq')x where(x->>'muc_no')::integer=mu.muc_no loop
   v:=case when mu.kieu='so'then(e->>'gia_tri')::numeric end;
   ok:=case when mu.kieu='so'then(lo is null or v>=lo)and(hi is null or v<=hi)else(e->>'dat')::boolean end;
   insert into ipqc_gc_kq(id_lan,muc_no,mau,gia_tri,dat)values(v_id,mu.muc_no,(e->>'mau')::integer,v,ok);
  end loop;
 end loop;
 return v_id;
end $$;
revoke all on function public.ipqc_gc_luu_do(jsonb) from public,anon;
grant execute on function public.ipqc_gc_luu_do(jsonb) to authenticated;
commit;
