-- ĐÃ ÁP DỤNG PROD 09/11/2026 (gộp theo mảng, bỏ phiên bản hàm trung gian; bản cuối các hàm đã sửa xem T230).
-- T222: Copy standards into an independent, unconfirmed machining draft.
begin;
alter table public.ipqc_btk add column nguon_sao_chep jsonb;
alter table public.ipqc_btk drop constraint ipqc_btk_trang_thai_check;
alter table public.ipqc_btk add constraint ipqc_btk_trang_thai_check check(
 trang_thai in('cho_kiem_tra','cho_phe_duyet','tra_lai','da_duyet')or(cong_doan='gia_cong'and trang_thai='ban_nhap'));
-- Existing cancel-draft RPC forbids deleting released standards. Allow its draft cleanup to include history.
alter table public.ipqc_gc_tieu_chuan_lich_su drop constraint ipqc_gc_tieu_chuan_lich_su_id_btk_fkey;
alter table public.ipqc_gc_tieu_chuan_lich_su add constraint ipqc_gc_tieu_chuan_lich_su_id_btk_fkey
 foreign key(id_btk)references public.ipqc_btk(id)on delete cascade;
create or replace function public.ipqc_gc_sao_chep_tieu_chuan(p_nguon_id bigint,p_ma_dich text,p_phien_ban text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare source ipqc_btk%rowtype;target_model text:=nullif(trim(p_ma_dich),'');revision text:=nullif(trim(p_phien_ban),'');
 target_id bigint;actor text;origin jsonb;previous text;counter integer:=0;
begin
 if auth.uid()is null or not has_role('admin','qc_manager','ipqc','nhan_vien_oqc')then raise exception 'Không có quyền soạn tiêu chuẩn';end if;
 select * into source from ipqc_btk where id=p_nguon_id for share;
 if source.id is null or source.cong_doan<>'gia_cong' then raise exception 'Chọn phiên bản tiêu chuẩn Gia công nguồn';end if;
 if target_model is null or target_model=source.ma_sp then raise exception 'Chọn Model đích khác Model nguồn';end if;
 if not exists(select 1 from master_products where ma_sp=target_model)then raise exception 'Model đích không có trong danh mục';end if;
 if not exists(select 1 from ipqc_btk_muc where id_btk=source.id)then raise exception 'Tiêu chuẩn nguồn chưa có hạng mục';end if;
 perform pg_advisory_xact_lock(hashtext('ipqc_btk:gia_cong:'||target_model));
 if exists(select 1 from ipqc_btk where ma_sp=target_model and cong_doan='gia_cong'
  and buoc_gia_cong is not distinct from source.buoc_gia_cong and trang_thai<>'da_duyet')then
  raise exception 'Model đích đã có bản nháp cho bước này. Hoàn tất hoặc xử lý bản nháp hiện có trước khi sao chép; không ghi đè.';
 end if;
 if revision is null then
  select phien_ban into previous from ipqc_btk where ma_sp=target_model and cong_doan='gia_cong'
   and buoc_gia_cong is not distinct from source.buoc_gia_cong order by dang_dung desc,id desc limit 1;
  revision:=case when previous is null then 'A' when previous~'^[A-Y]$'then chr(ascii(previous)+1)else previous||'.1'end;
  while exists(select 1 from ipqc_btk where ma_sp=target_model and cong_doan='gia_cong'
   and buoc_gia_cong is not distinct from source.buoc_gia_cong and phien_ban=revision)loop
   counter:=counter+1;revision:=coalesce(previous,'A')||'.'||counter::text;
  end loop;
 elsif exists(select 1 from ipqc_btk where ma_sp=target_model and cong_doan='gia_cong'
  and buoc_gia_cong is not distinct from source.buoc_gia_cong and phien_ban=revision)then raise exception 'Revision đích đã tồn tại; chọn Revision mới';
 end if;
 select coalesce(nullif(full_name,''),username)into actor from user_roles where user_id=auth.uid();
 origin:=jsonb_build_object('id_nguon',source.id,'model_nguon',source.ma_sp,'phien_ban_nguon',source.phien_ban,
  'buoc_nguon',source.buoc_gia_cong,'nguoi_sao_chep_uid',auth.uid(),'nguoi_sao_chep',actor,'thoi_diem',clock_timestamp());
 insert into ipqc_btk(ma_sp,cong_doan,buoc_gia_cong,phien_ban,ngay_hieu_luc,so_mau,tan_suat,ma_bieu,
  ban_ve_url,ban_ve_vi_tri,ma_ban_ve,tai_lieu_goc,noi_dung_sua_doi,nguoi_lap,nguoi_lap_uid,dang_dung,trang_thai,nguon_sao_chep)
 values(target_model,'gia_cong',source.buoc_gia_cong,revision,(now()at time zone'Asia/Ho_Chi_Minh')::date,
  source.so_mau,source.tan_suat,source.ma_bieu,null,'[]'::jsonb,null,null,
  'Sao chép từ '||source.ma_sp||' / Revision '||source.phien_ban,actor,auth.uid(),false,'ban_nhap',origin)returning id into target_id;
 insert into ipqc_btk_muc(id_btk,muc_no,hang_muc,kieu,danh_nghia,dung_sai_tren,dung_sai_duoi,
  tieu_chuan,dung_cu,tan_suat,ma_dac_tinh,don_vi,phuong_phap,lsl,usl,co_mau,nguon_nhan_dien,dung_sai_co_dau)
 select target_id,m.muc_no,m.hang_muc,m.kieu,m.danh_nghia,
  case when m.dung_sai_co_dau then m.dung_sai_tren else abs(m.dung_sai_tren)end,
  case when m.dung_sai_co_dau then m.dung_sai_duoi else -abs(m.dung_sai_duoi)end,
  m.tieu_chuan,m.dung_cu,m.tan_suat,m.ma_dac_tinh,m.don_vi,m.phuong_phap,
  coalesce(m.lsl,m.danh_nghia+case when m.dung_sai_co_dau then m.dung_sai_duoi else -abs(m.dung_sai_duoi)end),
  coalesce(m.usl,m.danh_nghia+case when m.dung_sai_co_dau then m.dung_sai_tren else abs(m.dung_sai_tren)end),
  m.co_mau,m.nguon_nhan_dien,true from ipqc_btk_muc m where m.id_btk=source.id order by m.muc_no;
 insert into ipqc_gc_tieu_chuan_lich_su(id_btk,nguoi_uid,du_lieu)values(target_id,auth.uid(),jsonb_build_object(
  'tieu_chuan',(select to_jsonb(b)from ipqc_btk b where b.id=target_id),'nguon_sao_chep',origin,
  'muc',(select jsonb_agg(to_jsonb(m)order by m.muc_no)from ipqc_btk_muc m where m.id_btk=target_id)));
 return jsonb_build_object('ok',true,'id',target_id,'ma_sp',target_model,'phien_ban',revision,'trang_thai','ban_nhap');
end $$;
revoke all on function public.ipqc_gc_sao_chep_tieu_chuan(bigint,text,text)from public,anon;
grant execute on function public.ipqc_gc_sao_chep_tieu_chuan(bigint,text,text)to authenticated;
commit;
