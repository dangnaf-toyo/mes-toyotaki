-- ĐÃ ÁP DỤNG PROD 09/11/2026 (gộp theo mảng, bỏ phiên bản hàm trung gian; bản cuối các hàm đã sửa xem T230).
-- T213: IPQC Gia công, tái sử dụng tiêu chuẩn và duyệt T183/T185.
-- Đã áp dụng STAGING 04/11/2026.
begin;
alter table public.ipqc_btk add column if not exists ma_ban_ve text;
alter table public.ipqc_btk add column if not exists buoc_gia_cong text;
alter table public.ipqc_btk add column if not exists tai_lieu_goc jsonb;
alter table public.ipqc_btk drop constraint ipqc_btk_cd_ma_pb_key;
alter table public.ipqc_btk add constraint ipqc_btk_buoc_revision_key unique nulls not distinct(cong_doan,ma_sp,buoc_gia_cong,phien_ban);
drop index public.ipqc_btk_dang_dung_uq;
create unique index ipqc_btk_dang_dung_uq on public.ipqc_btk(cong_doan,ma_sp,coalesce(buoc_gia_cong,''))where dang_dung;
drop index public.ipqc_btk_nhap_uq;
create unique index ipqc_btk_nhap_uq on public.ipqc_btk(cong_doan,ma_sp,coalesce(buoc_gia_cong,''))where trang_thai<>'da_duyet';
alter table public.ipqc_btk_muc add column if not exists ma_dac_tinh text;
alter table public.ipqc_btk_muc add column if not exists don_vi text;
alter table public.ipqc_btk_muc add column if not exists phuong_phap text;
alter table public.ipqc_btk_muc add column if not exists lsl numeric;
alter table public.ipqc_btk_muc add column if not exists usl numeric;
alter table public.ipqc_btk_muc add column if not exists co_mau integer check(co_mau between 1 and 100);
alter table public.ipqc_btk_muc add column if not exists nguon_nhan_dien jsonb;
alter table public.ipqc_btk_muc add column if not exists xac_nhan_boi uuid;
alter table public.ipqc_btk_muc add column if not exists xac_nhan_luc timestamptz;
alter table public.ipqc_btk_muc drop constraint if exists ipqc_btk_muc_check;
alter table public.ipqc_btk_muc add constraint ipqc_btk_muc_check check(kieu='okng' or
 (danh_nghia is not null and(dung_sai_tren is not null or dung_sai_duoi is not null)) or lsl is not null or usl is not null);
alter table public.ipqc_btk_muc add constraint ipqc_btk_muc_gioi_han check(lsl is null or usl is null or lsl<=usl);
create table public.ipqc_gc_tieu_chuan_lich_su(
 id bigint generated always as identity primary key,id_btk bigint not null references public.ipqc_btk(id),
 nguoi_uid uuid,thoi_diem timestamptz not null default clock_timestamp(),du_lieu jsonb not null
);
create table public.ipqc_gc_lan(
 id uuid primary key default gen_random_uuid(),request_id uuid not null unique,payload_hash text not null,
 id_btk bigint not null references public.ipqc_btk(id),ma_sp text not null,revision text not null,
 buoc_gia_cong text not null,ma_may text not null,ca text not null,ma_lo text not null,
 thoi_diem timestamptz not null default clock_timestamp(),nguoi_kiem_uid uuid not null,nguoi_kiem text not null,
 so_mau integer not null,dat boolean not null,tieu_chuan jsonb not null
);
create table public.ipqc_gc_kq(
 id_lan uuid not null references public.ipqc_gc_lan(id),muc_no integer not null,mau integer not null,
 gia_tri numeric,dat boolean not null,primary key(id_lan,muc_no,mau)
);
do $$declare t text;begin
 foreach t in array array['ipqc_gc_tieu_chuan_lich_su','ipqc_gc_lan','ipqc_gc_kq']loop
  execute format('alter table public.%I enable row level security',t);
  execute format('create policy %I on public.%I for select to authenticated using(true)',t||'_doc',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('ipqc-gia-cong-ban-ve','ipqc-gia-cong-ban-ve',false,20971520,array['application/pdf','image/png','image/jpeg'])on conflict(id)do nothing;
create policy ipqc_gc_file_doc on storage.objects for select to authenticated using(bucket_id='ipqc-gia-cong-ban-ve');
create policy ipqc_gc_file_ghi on storage.objects for insert to authenticated with check(
 bucket_id='ipqc-gia-cong-ban-ve' and (storage.foldername(name))[1]=auth.uid()::text and public.has_role('admin','qc_manager','ipqc','nhan_vien_oqc'));

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
end $function$
;
revoke all on function public.ipqc_btk_luu(text,jsonb,text,text) from public,anon;
grant execute on function public.ipqc_btk_luu(text,jsonb,text,text) to authenticated;
CREATE OR REPLACE FUNCTION public.ipqc_tc_hieu_luc(p_ma_sp text, p_cong_doan text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b ipqc_btk%rowtype;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
 if p_cong_doan is null or p_cong_doan not in ('duc','gia_cong') then raise exception 'Chọn đúng công đoạn'; end if;
 select * into b from ipqc_btk where ma_sp=p_ma_sp and cong_doan=p_cong_doan and trang_thai='da_duyet'
 and coalesce(ngay_hieu_luc,'-infinity'::date)<=(now() at time zone 'Asia/Ho_Chi_Minh')::date
 order by ngay_hieu_luc desc nulls last, phe_duyet_luc desc nulls last, id desc limit 1;
 return jsonb_build_object('btk',case when b.id is not null then to_jsonb(b) end,
 'muc',(select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('min',coalesce(m.lsl,m.danh_nghia-m.dung_sai_duoi),'max',coalesce(m.usl,m.danh_nghia+m.dung_sai_tren)) order by m.muc_no),'[]') from ipqc_btk_muc m where m.id_btk=b.id),
 'checklist',(select to_jsonb(t) from duc_ipqc_tieuchuan t where t.ma_sp=p_ma_sp and t.cong_doan=p_cong_doan));
end $function$
;
revoke all on function public.ipqc_tc_hieu_luc(text,text) from public,anon;
grant execute on function public.ipqc_tc_hieu_luc(text,text) to authenticated;
create function public.ipqc_gc_luu_tieu_chuan(p_data jsonb)returns jsonb language plpgsql security definer set search_path=public as $$
declare actor text;r jsonb;m jsonb;v_id bigint;
begin
 if auth.uid() is null or not has_role('admin','qc_manager','ipqc','nhan_vien_oqc')then raise exception 'Không có quyền soạn tiêu chuẩn';end if;
 if nullif(trim(p_data->>'ma_ban_ve'),'') is null or nullif(trim(p_data->>'phien_ban'),'') is null or nullif(trim(p_data->>'buoc_gia_cong'),'')is null then raise exception 'Nhập mã bản vẽ, Revision và bước gia công';end if;
 for m in select * from jsonb_array_elements(coalesce(p_data->'muc','[]'))loop
  if coalesce((m->>'da_xac_nhan')::boolean,false)=false then raise exception 'Cần kiểm tra và xác nhận từng đặc tính trước khi gửi duyệt';end if;
  if nullif(trim(m->>'ma_dac_tinh'),'')is null then raise exception 'Nhập mã đặc tính';end if;
  if (nullif(m->>'lsl','')::numeric)::text in('NaN','Infinity','-Infinity')or(nullif(m->>'usl','')::numeric)::text in('NaN','Infinity','-Infinity')then raise exception 'Giới hạn kỹ thuật phải là số hữu hạn';end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_data->'muc')x group by lower(x->>'ma_dac_tinh')having count(*)>1)then raise exception 'Mã đặc tính không được trùng';end if;
 select coalesce(nullif(full_name,''),username)into actor from user_roles where user_id=auth.uid();
 r:=ipqc_btk_luu(p_data->>'ma_sp',p_data,actor,'gia_cong');
 if coalesce((r->>'ok')::boolean,false)=false then raise exception '%',r->>'error';end if;
 v_id:=(r->>'id')::bigint;
 update ipqc_btk set ma_ban_ve=trim(p_data->>'ma_ban_ve'),buoc_gia_cong=trim(p_data->>'buoc_gia_cong'),tai_lieu_goc=p_data->'tai_lieu_goc' where id=v_id;
 update ipqc_btk_muc set xac_nhan_boi=auth.uid(),xac_nhan_luc=clock_timestamp()where id_btk=v_id;
 insert into ipqc_gc_tieu_chuan_lich_su(id_btk,nguoi_uid,du_lieu)values(v_id,auth.uid(),jsonb_build_object(
 'tieu_chuan',(select to_jsonb(b)from ipqc_btk b where b.id=v_id),
 'muc',(select jsonb_agg(to_jsonb(history_item)order by history_item.muc_no)from ipqc_btk_muc history_item where history_item.id_btk=v_id)));
 return r;
end $$;
revoke all on function public.ipqc_gc_luu_tieu_chuan(jsonb) from public,anon;
grant execute on function public.ipqc_gc_luu_tieu_chuan(jsonb) to authenticated;

create function public.ipqc_gc_luu_do(p_data jsonb)returns uuid language plpgsql security definer set search_path=public as $$
declare b ipqc_btk%rowtype;mu ipqc_btk_muc%rowtype;e jsonb;v numeric;ok boolean;all_ok boolean:=true;
 v_id uuid;prior ipqc_gc_lan%rowtype;req uuid:=(p_data->>'request_id')::uuid;actor text;
 n integer;s integer;max_samples integer:=1;lo numeric;hi numeric;expected integer:=0;
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
 if b.id is null or b.cong_doan is distinct from 'gia_cong' or b.ma_sp is distinct from p_data->>'ma_sp' or b.trang_thai is distinct from 'da_duyet'
 or b.ngay_hieu_luc>(now()at time zone'Asia/Ho_Chi_Minh')::date then raise exception 'Chọn đúng tiêu chuẩn Gia công đã duyệt và có hiệu lực';end if;
 if nullif(trim(b.buoc_gia_cong),'')is null then raise exception 'Tiêu chuẩn thiếu bước gia công; lập phiên bản đầy đủ trước khi đo';end if;
 if not exists(select 1 from master_machines where ma_may=p_data->>'ma_may' and bo_phan='Gia công - Sơn')then raise exception 'Chọn máy Gia công trong danh mục';end if;
 if coalesce(p_data->>'ca','')not in('Ca ngày','Ca đêm','Ca 1','Ca 2')or nullif(trim(p_data->>'ma_lo'),'')is null then raise exception 'Chọn ca và nhập mã lô';end if;
 if jsonb_typeof(p_data->'kq')is distinct from'array'then raise exception 'Thiếu kết quả đo';end if;
 select coalesce(nullif(full_name,''),username)into actor from user_roles where user_id=auth.uid();
 for mu in select * from ipqc_btk_muc where id_btk=b.id order by muc_no loop
  n:=case when mu.kieu='okng'then 1 else coalesce(mu.co_mau,b.so_mau,1)end;max_samples:=greatest(max_samples,n);
  lo:=coalesce(mu.lsl,mu.danh_nghia-mu.dung_sai_duoi);hi:=coalesce(mu.usl,mu.danh_nghia+mu.dung_sai_tren);
  for s in 1..n loop
   expected:=expected+1;
   if(select count(*)from jsonb_array_elements(p_data->'kq')x where(x->>'muc_no')::integer=mu.muc_no and(x->>'mau')::integer=s)<>1 then raise exception 'Thiếu hoặc trùng kết quả No %, mẫu %',mu.muc_no,s;end if;
   select x into e from jsonb_array_elements(p_data->'kq')x where(x->>'muc_no')::integer=mu.muc_no and(x->>'mau')::integer=s;
   if mu.kieu='so'then
    v:=nullif(e->>'gia_tri','')::numeric;
    if v is null or v::text in('NaN','Infinity','-Infinity')then raise exception 'Nhập giá trị đo hữu hạn No %, mẫu %',mu.muc_no,s;end if;
    ok:=(lo is null or v>=lo)and(hi is null or v<=hi);
   else ok:=(e->>'dat')::boolean;if ok is null then raise exception 'Chọn OK/NG No %',mu.muc_no;end if;
   end if;
   all_ok:=all_ok and ok;
  end loop;
 end loop;
 if expected=0 or expected<>jsonb_array_length(p_data->'kq')then raise exception 'Kết quả không khớp danh sách đặc tính';end if;
 insert into ipqc_gc_lan(request_id,payload_hash,id_btk,ma_sp,revision,buoc_gia_cong,ma_may,ca,ma_lo,nguoi_kiem_uid,nguoi_kiem,so_mau,dat,tieu_chuan)
 values(req,md5(p_data::text),b.id,b.ma_sp,b.phien_ban,b.buoc_gia_cong,p_data->>'ma_may',p_data->>'ca',trim(p_data->>'ma_lo'),auth.uid(),actor,max_samples,all_ok,
 jsonb_build_object('btk',to_jsonb(b),'muc',(select jsonb_agg(to_jsonb(m)order by m.muc_no)from ipqc_btk_muc m where m.id_btk=b.id)))returning id into v_id;
 for mu in select * from ipqc_btk_muc where id_btk=b.id loop
  lo:=coalesce(mu.lsl,mu.danh_nghia-mu.dung_sai_duoi);hi:=coalesce(mu.usl,mu.danh_nghia+mu.dung_sai_tren);
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

create view public.ipqc_lan_tong_hop with(security_invoker=true)as
select g.id::text as id,'gia_cong'::text as cong_doan,g.ma_sp,g.revision,g.buoc_gia_cong,g.ma_may,g.ca,g.ma_lo,g.nguoi_kiem,
 g.thoi_diem,g.so_mau,g.dat,g.id_btk,g.tieu_chuan,
 (select coalesce(jsonb_agg(to_jsonb(k)order by k.muc_no,k.mau),'[]')from ipqc_gc_kq k where k.id_lan=g.id)as kq
from ipqc_gc_lan g
union all
select l.id_checkpoint,'duc',l.ma_sp,b.phien_ban,null::text,l.ma_may,to_jsonb(c)->>'ca',null::text,l.nguoi,
 l.thoi_diem,b.so_mau,l.dat,l.id_btk,jsonb_build_object('btk',to_jsonb(b),'muc',
 (select jsonb_agg(to_jsonb(m)order by m.muc_no)from ipqc_btk_muc m where m.id_btk=b.id)),
 (select coalesce(jsonb_agg(to_jsonb(k)order by k.muc_no,k.mau),'[]')from ipqc_do_kq k where k.id_checkpoint=l.id_checkpoint)
from ipqc_do_lan l join ipqc_btk b on b.id=l.id_btk and b.cong_doan='duc'
join duc_ipqc_checkpoint c on c.id_checkpoint=l.id_checkpoint and c.ket_qua is not null;
revoke all on public.ipqc_lan_tong_hop from public,anon;
grant select on public.ipqc_lan_tong_hop to authenticated;
create or replace function public.ipqc_do_du_lieu(p_ma_sp text,p_tu timestamptz,p_den timestamptz,p_so_lan integer,p_cong_doan text default 'duc')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare ref jsonb;result jsonb;
begin
 if auth.uid()is null then raise exception 'Cần đăng nhập';end if;
 if p_cong_doan='gia_cong'then
  ref:=ipqc_tc_hieu_luc(p_ma_sp,'gia_cong');
  select jsonb_build_object('btk',ref->'btk','muc',ref->'muc','gioi_han','[]'::jsonb,'lan',coalesce(jsonb_agg(x.v order by x.thoi_diem),'[]'))into result
  from(select g.thoi_diem,jsonb_build_object('id_checkpoint',g.id,'thoi_diem',g.thoi_diem,'ma_may',g.ma_may,'nguoi',g.nguoi_kiem,
   'id_btk',g.id_btk,'dat',g.dat,'ket_qua',case when g.dat then 'OK'else'NG'end,
   'tieu_chuan',g.tieu_chuan->'btk','muc_tieu_chuan',g.tieu_chuan->'muc',
   'kq',(select jsonb_agg(to_jsonb(k)order by k.muc_no,k.mau)from ipqc_gc_kq k where k.id_lan=g.id))v
   from ipqc_gc_lan g where g.ma_sp=p_ma_sp and(p_tu is null or g.thoi_diem>=p_tu)and(p_den is null or g.thoi_diem<=p_den)
   order by g.thoi_diem desc limit coalesce(p_so_lan,5000))x;
  return result;
 elsif p_cong_doan is distinct from 'duc'then raise exception 'Công đoạn không hợp lệ';end if;
 return (with b as (select * from ipqc_btk where id=((ipqc_tc_hieu_luc(p_ma_sp,p_cong_doan)->'btk')->>'id')::bigint),
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
            order by l.thoi_diem), '[]'::jsonb) from lan l)));
end $$;
revoke all on function public.ipqc_do_du_lieu(text,timestamptz,timestamptz,integer,text) from public,anon;
grant execute on function public.ipqc_do_du_lieu(text,timestamptz,timestamptz,integer,text) to authenticated;
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
      v_ten := 'Bảng tuần kiểm ' || ipqc_cd_ten(new.cong_doan) || ' mã ' || new.ma_sp || ' (phiên bản ' || new.phien_ban || ')';
    else
      v_khoa := 'tc:cl:' || new.id;
      v_ten := 'Checklist / PDF tiêu chuẩn ' || ipqc_cd_ten(new.cong_doan) || ' mã ' || new.ma_sp;
    end if;
    v_lk := 'qc-manager.html?tab=tieuchuan&ma=' || new.ma_sp || '&cd=' || new.cong_doan;
    if tg_table_name='ipqc_btk' and new.cong_doan='gia_cong'then
      v_lk:='ipqc-gia-cong.html?standard='||new.ma_sp||'&version='||new.id;
    end if;
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
;
revoke all on function public.cv_pd_trg_tieu_chuan()from public,anon,authenticated;
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
end $function$
;
revoke all on function public.ipqc_tc_duyet(text,bigint,text,text,text)from public,anon;
grant execute on function public.ipqc_tc_duyet(text,bigint,text,text,text)to authenticated;
commit;
