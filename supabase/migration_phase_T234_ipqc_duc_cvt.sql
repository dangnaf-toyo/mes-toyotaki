-- Đã chạy STAGING jcjbleugnclzsghfpmvk 10/11 + PROD 10/11/2026 (sau review, nguyên trạng). Additive: no existing measurement or standard is rewritten.
begin;
alter table public.ipqc_do_kq add column if not exists ma_cvt text;
alter table public.ipqc_do_kq add constraint ipqc_do_kq_ma_cvt_check
 check(ma_cvt is null or (ma_cvt=btrim(ma_cvt) and char_length(ma_cvt) between 1 and 80));
create unique index ipqc_do_kq_cvt_uq on public.ipqc_do_kq(id_checkpoint,muc_no,lower(ma_cvt)) where ma_cvt is not null;
alter table public.ipqc_do_lan add column if not exists muc_da_chon jsonb;
alter table public.ipqc_do_lan add column if not exists so_muc_da_kiem integer;
alter table public.ipqc_do_lan add column if not exists so_muc_chua_kiem integer;
alter table public.ipqc_do_lan add column if not exists du_lieu_hash text;

-- One transaction saves measurements AND completes the existing server-timed session.
-- The legacy RPCs remain available for existing clients, unchanged.
create or replace function public.duc_submit_ipqc_cvt(
 p_id_checkpoint text,p_checklist jsonb,p_ket_qua text,p_anh_urls jsonb,p_ghi_chu text,
 p_thoi_gian_kiem_giay numeric,p_nguoi_kiem text,p_do jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c duc_ipqc_checkpoint%rowtype;s duc_ipqc_inspection_session%rowtype;b ipqc_btk%rowtype;
 mu ipqc_btk_muc%rowtype; e jsonb; value numeric; passed boolean; all_pass boolean:=true;
 lo numeric;hi numeric;selected integer[];n integer;actor text;stamp timestamptz;rows jsonb:='[]';result jsonb;
 fingerprint text:=md5(jsonb_build_object('do',p_do,'checklist',p_checklist,'result',p_ket_qua,'photos',p_anh_urls,'note',p_ghi_chu)::text);
begin
 if auth.uid()is null or not has_role('admin','qc_manager','ipqc')then raise exception 'Chỉ IPQC hoặc quản lý QC được ghi kết quả';end if;
 select * into c from duc_ipqc_checkpoint where id_checkpoint=p_id_checkpoint for update;
 if not found then raise exception 'Không tìm thấy phiên kiểm';end if;
 select * into s from duc_ipqc_inspection_session where checkpoint_id=c.id_checkpoint for update;
 if s.owner_id is distinct from auth.uid()then raise exception 'Hãy bắt đầu đúng phiên kiểm của tài khoản này';end if;
 if s.completed_at is not null then
  if c.ket_qua=p_ket_qua and exists(select 1 from ipqc_do_lan where id_checkpoint=c.id_checkpoint and du_lieu_hash=fingerprint)then
   return jsonb_build_object('ok',true,'existing',true);
  end if;
  raise exception 'Phiên kiểm đã hoàn tất — không sửa kết quả';
 end if;
 if c.trang_thai is distinct from 'cho_kiem' or c.ket_qua is not null then raise exception 'Phiên kiểm không còn chờ kiểm';end if;
 select * into b from ipqc_btk where id=((ipqc_tc_hieu_luc(c.ma_sp,'duc')->'btk')->>'id')::bigint for share;
 if b.id is null or b.id is distinct from (p_do->>'id_btk')::bigint then raise exception 'Tiêu chuẩn vừa thay đổi. Mở lại phiếu để lấy phiên bản có hiệu lực.';end if;
 if jsonb_typeof(p_do->'muc_da_chon')is distinct from'array' or jsonb_typeof(p_do->'kq')is distinct from'array'then raise exception 'Thiếu danh sách hạng mục và kết quả';end if;
 select array_agg(v::integer)into selected from jsonb_array_elements_text(p_do->'muc_da_chon')v;
 if coalesce(cardinality(selected),0)=0 or jsonb_array_length(p_do->'kq')=0 then raise exception 'Cần ít nhất một kết quả kiểm tra hợp lệ';end if;
 if (select count(distinct v)from unnest(selected)v)<>cardinality(selected)then raise exception 'Trùng hạng mục đã chọn';end if;
 if exists(select 1 from unnest(selected)v where not exists(select 1 from ipqc_btk_muc where id_btk=b.id and muc_no=v))then raise exception 'Hạng mục không thuộc tiêu chuẩn đã chọn';end if;
 for e in select * from jsonb_array_elements(p_do->'kq')loop
  n:=(e->>'muc_no')::integer;
  if n is null or not(n=any(selected))then raise exception 'Kết quả không thuộc hạng mục đã chọn';end if;
  select * into mu from ipqc_btk_muc where id_btk=b.id and muc_no=n;
  if coalesce(e->>'mau','')!~'^[1-9][0-9]*$'then raise exception 'Thứ tự dòng CVT không hợp lệ';end if;
  if exists(select 1 from jsonb_array_elements(rows)x where(x->>'muc_no')::integer=n and(x->>'mau')::integer=(e->>'mau')::integer)then raise exception 'Trùng dòng kết quả';end if;
  if mu.kieu='so'then
   if coalesce(btrim(e->>'ma_cvt'),'')='' or char_length(btrim(e->>'ma_cvt'))>80 then raise exception 'Nhập mã CVT cho hạng mục %',n;end if;
   if exists(select 1 from jsonb_array_elements(rows)x where(x->>'muc_no')::integer=n and lower(x->>'ma_cvt')=lower(btrim(e->>'ma_cvt')))then raise exception 'Trùng mã CVT % trong hạng mục %',e->>'ma_cvt',n;end if;
   if coalesce(e->>'gia_tri','')!~'^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)$'then raise exception 'Giá trị đo không đúng định dạng ở hạng mục %',n;end if;
   value:=(e->>'gia_tri')::numeric;
   lo:=coalesce(mu.lsl,mu.danh_nghia-mu.dung_sai_duoi);hi:=coalesce(mu.usl,mu.danh_nghia+mu.dung_sai_tren);
   if lo is null and hi is null then raise exception 'Hạng mục % chưa có giới hạn đánh giá',n;end if;
   passed:=(lo is null or value>=lo)and(hi is null or value<=hi);
  else
   if jsonb_typeof(e->'dat')is distinct from'boolean'then raise exception 'Chọn OK/NG ở hạng mục %',n;end if;
   if exists(select 1 from jsonb_array_elements(rows)x where(x->>'muc_no')::integer=n)then raise exception 'Trùng kết quả hạng mục %',n;end if;
   passed:=(e->>'dat')::boolean;value:=null;
  end if;
  rows:=rows||jsonb_build_array(jsonb_build_object('muc_no',n,'mau',(e->>'mau')::integer,
   'ma_cvt',case when mu.kieu='so'then btrim(e->>'ma_cvt')end,'gia_tri',value,'dat',passed));
  all_pass:=all_pass and passed;
 end loop;
 if exists(select 1 from unnest(selected)v where not exists(select 1 from jsonb_array_elements(rows)x where(x->>'muc_no')::integer=v))then raise exception 'Hạng mục đã chọn còn thiếu kết quả. Bỏ chọn hạng mục chưa thực hiện.';end if;
 if not all_pass and p_ket_qua='OK'then raise exception 'Có CVT NG — không thể kết thúc với kết quả OK';end if;
 -- Dimension checklist must describe measured values, never unchecked standard items.
 if not exists(select 1 from jsonb_array_elements(p_checklist)x where x->>'muc'='Kích thước (theo bảng tuần kiểm)' and(x->>'dat')::boolean=all_pass)then raise exception 'Kết quả kích thước không khớp dữ liệu đo';end if;
 select coalesce(nullif(full_name,''),username)into actor from user_roles where user_id=auth.uid();
 if coalesce(actor,'')=''then raise exception 'Chưa xác định được người kiểm';end if;
 stamp:=coalesce(s.submission_at,clock_timestamp());
 delete from ipqc_do_lan where id_checkpoint=c.id_checkpoint;
 insert into ipqc_do_lan(id_checkpoint,id_btk,ma_sp,ma_may,so_khuon,thoi_diem,nguoi,nguoi_uid,dat,cong_doan,muc_da_chon,so_muc_da_kiem,so_muc_chua_kiem,du_lieu_hash)
 values(c.id_checkpoint,b.id,c.ma_sp,c.ma_may,(select so_khuon from duc_ca_hien_tai where id_dong=c.id_dong),stamp,actor,auth.uid(),all_pass,'duc',to_jsonb(selected),cardinality(selected),
  (select count(*)from ipqc_btk_muc where id_btk=b.id)-cardinality(selected),fingerprint);
 insert into ipqc_do_kq(id_checkpoint,muc_no,mau,ma_cvt,gia_tri,dat)
 select c.id_checkpoint,(x->>'muc_no')::integer,(x->>'mau')::integer,x->>'ma_cvt',(x->>'gia_tri')::numeric,(x->>'dat')::boolean from jsonb_array_elements(rows)x;
 result:=duc_submit_ipqc_session(p_id_checkpoint,p_checklist,p_ket_qua,p_anh_urls,p_ghi_chu,p_thoi_gian_kiem_giay,actor);
 if coalesce((result->>'ok')::boolean,false)=false then raise exception '%',result->>'error';end if;
 return result||jsonb_build_object('so_muc_da_kiem',cardinality(selected),'so_muc_chua_kiem',(select so_muc_chua_kiem from ipqc_do_lan where id_checkpoint=c.id_checkpoint));
end $$;
revoke all on function public.duc_submit_ipqc_cvt(text,jsonb,text,jsonb,text,numeric,text,jsonb)from public,anon;
grant execute on function public.duc_submit_ipqc_cvt(text,jsonb,text,jsonb,text,numeric,text,jsonb)to authenticated;

-- Preserve the machining branch byte-for-byte; enrich only casting history.
alter function public.ipqc_do_du_lieu(text,timestamptz,timestamptz,integer,text)rename to ipqc_do_du_lieu_truoc_cvt;
revoke all on function public.ipqc_do_du_lieu_truoc_cvt(text,timestamptz,timestamptz,integer,text)from public,anon,authenticated;
create function public.ipqc_do_du_lieu(p_ma_sp text,p_tu timestamptz,p_den timestamptz,p_so_lan integer,p_cong_doan text default 'duc')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
 if auth.uid()is null then raise exception 'Cần đăng nhập';end if;
 result:=ipqc_do_du_lieu_truoc_cvt(p_ma_sp,p_tu,p_den,p_so_lan,p_cong_doan);
 if p_cong_doan='duc'then
  result:=jsonb_set(result,'{lan}',coalesce((select jsonb_agg(x||jsonb_build_object(
   'muc_da_chon',l.muc_da_chon,'so_muc_da_kiem',l.so_muc_da_kiem,'so_muc_chua_kiem',l.so_muc_chua_kiem,
   'kq',(select coalesce(jsonb_agg(to_jsonb(k)order by k.muc_no,k.mau),'[]')from ipqc_do_kq k where k.id_checkpoint=l.id_checkpoint))order by l.thoi_diem)
   from jsonb_array_elements(result->'lan')x join ipqc_do_lan l on l.id_checkpoint=x->>'id_checkpoint'),'[]'));
 end if;
 return result;
end $$;
revoke all on function public.ipqc_do_du_lieu(text,timestamptz,timestamptz,integer,text)from public,anon;
grant execute on function public.ipqc_do_du_lieu(text,timestamptz,timestamptz,integer,text)to authenticated;
-- CVT positions are not rational sample subgroups; preserve legacy control limits.
CREATE OR REPLACE FUNCTION public.ipqc_gioi_han_tinh(p_ma_sp text, p_muc_no integer, p_tu timestamp with time zone, p_den timestamp with time zone, p_toi_da integer, p_cong_doan text DEFAULT 'duc'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_n int; v_cl numeric; v_r numeric; v_so_mau int; a2 numeric; d4 numeric;
begin
  if auth.uid() is null then return null; end if;
  with lan as (
    select l.thoi_diem, avg(k.gia_tri) x, max(k.gia_tri) - min(k.gia_tri) r, count(k.gia_tri) n
    from ipqc_do_lan l join ipqc_do_kq k on k.id_checkpoint = l.id_checkpoint and k.muc_no = p_muc_no
    join duc_ipqc_checkpoint c on c.id_checkpoint = l.id_checkpoint and c.ket_qua is not null
    where l.ma_sp = p_ma_sp and l.cong_doan = p_cong_doan and k.gia_tri is not null and k.ma_cvt is null
      and (p_tu is null or l.thoi_diem >= p_tu) and (p_den is null or l.thoi_diem <= p_den)
    group by l.id_checkpoint, l.thoi_diem order by l.thoi_diem limit coalesce(p_toi_da, 100000)
  ), mr as (select x, r, n, abs(x - lag(x) over (order by thoi_diem)) mr from lan)
  select count(*), avg(x), round(avg(n))::int,
         case when round(avg(n)) <= 1 then avg(mr) else avg(r) end
    into v_n, v_cl, v_so_mau, v_r from mr;
  if coalesce(v_n, 0) < 2 or v_r is null then return null; end if;
  if v_so_mau <= 1 then
    return jsonb_build_object('so_mau', 1, 'cl', v_cl, 'ucl', v_cl + 2.66 * v_r, 'lcl', v_cl - 2.66 * v_r,
      'cl_r', v_r, 'ucl_r', 3.267 * v_r, 'n_lan', v_n);
  end if;
  a2 := (array[1.880, 1.023, 0.729, 0.577])[least(v_so_mau, 5) - 1];
  d4 := (array[3.267, 2.574, 2.282, 2.114])[least(v_so_mau, 5) - 1];
  return jsonb_build_object('so_mau', v_so_mau, 'cl', v_cl, 'ucl', v_cl + a2 * v_r, 'lcl', v_cl - a2 * v_r,
    'cl_r', v_r, 'ucl_r', d4 * v_r, 'n_lan', v_n);
end $function$
;
-- Internal calculation only, called by existing authorized control-limit RPCs/triggers.
revoke all on function public.ipqc_gioi_han_tinh(text,integer,timestamptz,timestamptz,integer,text) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
