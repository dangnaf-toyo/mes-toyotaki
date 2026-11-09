-- ĐÃ ÁP DỤNG PROD 09/11/2026 (gộp theo mảng, bỏ phiên bản hàm trung gian; bản cuối các hàm đã sửa xem T230).
-- T223: inspection date, automatic effective standards and optional report lot/step.
-- Existing measurements/standards stay unchanged.
-- Applied to staging 2026-11-07.
begin;
alter table public.ipqc_gc_lan add column ngay_kiem date;
alter table public.ipqc_gc_lan add column cap_nhat_luc timestamptz;
-- Set the default separately: legacy audit timestamps remain unknown, not migration time.
alter table public.ipqc_gc_lan alter column cap_nhat_luc set default clock_timestamp();
alter table public.ipqc_gc_lan alter column ma_lo drop not null;
alter table public.ipqc_gc_lan alter column buoc_gia_cong drop not null;
create or replace function public.ipqc_gc_dau_cap_nhat()
returns trigger language plpgsql set search_path=public as $$
begin new.cap_nhat_luc:=clock_timestamp();return new;end $$;
revoke all on function public.ipqc_gc_dau_cap_nhat()from public,anon,authenticated;
create trigger ipqc_gc_lan_cap_nhat before update on public.ipqc_gc_lan
for each row when(old.* is distinct from new.*)execute function public.ipqc_gc_dau_cap_nhat();

create or replace function public.ipqc_gc_tieu_chuan_theo_ngay(p_ma_sp text,p_ngay_kiem date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare ids bigint[];b ipqc_btk%rowtype;
begin
 if auth.uid()is null then raise exception 'Cần đăng nhập MES'using errcode='42501';end if;
 -- A successor closes the previous version's interval for the same step. Active flags
 -- describe today, so historical selection uses approved effective dates instead.
 with eligible as(select x.*,coalesce(nullif(trim(x.buoc_gia_cong),''),'')as scope
  from ipqc_btk x where x.ma_sp=p_ma_sp and x.cong_doan='gia_cong'
  and x.trang_thai='da_duyet'and x.ngay_hieu_luc<=p_ngay_kiem),
 latest as(select scope,max(ngay_hieu_luc)as start_day from eligible group by scope)
 select array_agg(e.id order by e.id)into ids from eligible e join latest l on l.scope=e.scope and l.start_day=e.ngay_hieu_luc;
 if coalesce(cardinality(ids),0)=0 then return jsonb_build_object('status','none','message','Chưa có tiêu chuẩn.','btk',null,'muc','[]'::jsonb);end if;
 if cardinality(ids)<>1 then return jsonb_build_object('status','ambiguous','message','Tiêu chuẩn chồng lấn. Liên hệ quản lý QC.','btk',null,'muc','[]'::jsonb);end if;
 select * into b from ipqc_btk where id=ids[1];
 return jsonb_build_object('status','ok','btk',to_jsonb(b),'muc',coalesce((select jsonb_agg(to_jsonb(m)order by m.muc_no)from ipqc_btk_muc m where m.id_btk=b.id),'[]'::jsonb));
end $$;
revoke all on function public.ipqc_gc_tieu_chuan_theo_ngay(text,date)from public,anon;
grant execute on function public.ipqc_gc_tieu_chuan_theo_ngay(text,date)to authenticated;

CREATE OR REPLACE FUNCTION public.ipqc_gc_luu_do_t217(p_data jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b ipqc_btk%rowtype;mu ipqc_btk_muc%rowtype;e jsonb;v numeric;ok boolean;all_ok boolean:=true;
 v_id uuid;prior ipqc_gc_lan%rowtype;req uuid:=(p_data->>'request_id')::uuid;actor text;
 n integer;minimum integer;s integer;max_samples integer:=1;lo numeric;hi numeric;expected integer:=0;
 inspection_day date:=coalesce(nullif(p_data->>'ngay_kiem','')::date,(clock_timestamp()at time zone'Asia/Ho_Chi_Minh')::date);resolution jsonb;
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
 resolution:=ipqc_gc_tieu_chuan_theo_ngay(p_data->>'ma_sp',inspection_day);
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

-- Internal only: authenticated clients must use the source/confirmation wrapper.
revoke all on function public.ipqc_gc_luu_do_t217(jsonb)from public,anon,authenticated;
create or replace view public.ipqc_lan_tong_hop with(security_invoker=true)as
select g.id::text as id,'gia_cong'::text as cong_doan,g.ma_sp,g.revision,g.buoc_gia_cong,g.ma_may,g.ca,g.ma_lo,g.nguoi_kiem,
 g.thoi_diem,g.so_mau,g.dat,g.id_btk,g.tieu_chuan,
 (select coalesce(jsonb_agg(to_jsonb(k)order by k.muc_no,k.mau),'[]')from ipqc_gc_kq k where k.id_lan=g.id)as kq,
 g.nguon_nhap,g.tep_ket_qua,g.nhan_dien,g.co_mau_thuc_te,
 coalesce(g.ngay_kiem,(g.thoi_diem at time zone'Asia/Ho_Chi_Minh')::date)as ngay_kiem,g.cap_nhat_luc
from ipqc_gc_lan g
union all
select l.id_checkpoint,'duc',l.ma_sp,b.phien_ban,null::text,l.ma_may,to_jsonb(c)->>'ca',null::text,l.nguoi,
 l.thoi_diem,b.so_mau,l.dat,l.id_btk,jsonb_build_object('btk',to_jsonb(b),'muc',
 (select jsonb_agg(to_jsonb(m)order by m.muc_no)from ipqc_btk_muc m where m.id_btk=b.id)),
 (select coalesce(jsonb_agg(to_jsonb(k)order by k.muc_no,k.mau),'[]')from ipqc_do_kq k where k.id_checkpoint=l.id_checkpoint),
 null::text,null::jsonb,null::jsonb,null::jsonb,(l.thoi_diem at time zone'Asia/Ho_Chi_Minh')::date,null::timestamptz
from ipqc_do_lan l join ipqc_btk b on b.id=l.id_btk and b.cong_doan='duc'
join duc_ipqc_checkpoint c on c.id_checkpoint=l.id_checkpoint and c.ket_qua is not null;
revoke all on public.ipqc_lan_tong_hop from public,anon;
grant select on public.ipqc_lan_tong_hop to authenticated;
create index ipqc_gc_lan_ngay_kiem_idx on public.ipqc_gc_lan
 ((coalesce(ngay_kiem,(thoi_diem at time zone'Asia/Ho_Chi_Minh')::date)));
notify pgrst,'reload schema';
commit;
