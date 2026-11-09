-- STAGING only, no persistent fixture standards, roles, history or measurements.
begin;
do $$
declare qc uuid;manager uuid;director uuid;product text;token text:=gen_random_uuid()::text;
 r jsonb;p jsonb;old_id bigint;draft_id bigint;old_json jsonb;old_features jsonb;history_count bigint;
begin
 select user_id into qc from user_roles where role in('ipqc','admin')limit 1;
 select user_id into manager from user_roles where role in('qc_manager','admin')and user_id<>qc limit 1;
 select user_id into director from user_roles where role in('giam_doc_sx','admin')and user_id not in(qc,manager)limit 1;
 if qc is null or manager is null or director is null then raise exception 'Need three staging accounts';end if;
 update user_roles set role='ipqc'where user_id=qc;
 update user_roles set role='qc_manager'where user_id=manager;
 update user_roles set role='giam_doc_sx'where user_id=director;
 select ma_sp into product from master_products p where not exists(
  select 1 from ipqc_btk b where b.ma_sp=p.ma_sp and b.cong_doan='gia_cong'and b.buoc_gia_cong is null)limit 1;
 if product is null then raise exception 'Need unused staging product for legacy fixture';end if;
 perform set_config('request.jwt.claim.sub',qc::text,true);
 p:=jsonb_build_object('phien_ban','LEGACY-'||token,'ngay_hieu_luc','2026-01-01','so_mau',2,
  'noi_dung_sua_doi','Legacy rollback fixture','ban_ve_vi_tri',jsonb_build_array(jsonb_build_object('no',1,'x',20,'y',30)),
  'muc',jsonb_build_array(jsonb_build_object('muc_no',1,'hang_muc','Legacy diameter','kieu','so','danh_nghia',20,
   'dung_sai_tren',0.05,'dung_sai_duoi',0.05,'lsl',19.95,'usl',20.05,'co_mau',2,'don_vi','mm','dung_cu','CMM')));
 r:=ipqc_btk_luu(product,p,'Ignored','gia_cong');old_id:=(r->>'id')::bigint;
 if not coalesce((r->>'ok')::boolean,false)then raise exception '%',r;end if;
 perform set_config('request.jwt.claim.sub',manager::text,true);
 r:=ipqc_tc_duyet('btk',old_id,'kiem_tra',null,'Ignored');if not(r->>'ok')::boolean then raise exception '%',r;end if;
 perform set_config('request.jwt.claim.sub',director::text,true);
 r:=ipqc_tc_duyet('btk',old_id,'phe_duyet',null,'Ignored');if not(r->>'ok')::boolean then raise exception '%',r;end if;
 select to_jsonb(b)into old_json from ipqc_btk b where id=old_id;
 select jsonb_agg(to_jsonb(m)order by m.muc_no)into old_features from ipqc_btk_muc m where id_btk=old_id;
 select count(*)into history_count from ipqc_gc_tieu_chuan_lich_su where id_btk=old_id;
 perform set_config('request.jwt.claim.sub',qc::text,true);
 p:=p||jsonb_build_object('ma_sp',product,'phien_ban','REVISION-'||token,'ma_ban_ve','',
   'buoc_gia_cong','','tai_lieu_goc',null,'noi_dung_sua_doi','Revise legacy in common standards manager',
   'muc',jsonb_build_array((p->'muc'->0)||jsonb_build_object('da_xac_nhan',true,'usl',20.04)));
 r:=ipqc_gc_luu_tieu_chuan(p);draft_id:=(r->>'id')::bigint;
 if draft_id=old_id then raise exception 'Approved legacy standard overwritten';end if;
 if (select to_jsonb(b)from ipqc_btk b where id=old_id)is distinct from old_json
  or(select jsonb_agg(to_jsonb(m)order by m.muc_no)from ipqc_btk_muc m where id_btk=old_id)is distinct from old_features
  then raise exception 'Legacy standard or feature data changed';end if;
 if(select count(*)from ipqc_gc_tieu_chuan_lich_su where id_btk=old_id)<>history_count then raise exception 'Legacy history changed';end if;
 if(select buoc_gia_cong from ipqc_btk where id=draft_id)is not null
   or(select ma_ban_ve from ipqc_btk where id=draft_id)is not null then raise exception 'Legacy metadata was invented';end if;
 if(select ma_dac_tinh from ipqc_btk_muc where id_btk=draft_id)is not null then raise exception 'Legacy feature code was invented';end if;
 if(select usl from ipqc_btk_muc where id_btk=draft_id)<>20.04 then raise exception 'Explicit bound lost';end if;
 if(select ban_ve_vi_tri from ipqc_btk where id=draft_id)is distinct from p->'ban_ve_vi_tri' then raise exception 'Drawing positions lost';end if;
 r:=ipqc_gc_luu_tieu_chuan(p||jsonb_build_object('noi_dung_sua_doi','Update same draft'));
 if(r->>'id')::bigint<>draft_id then raise exception 'Draft ID changed';end if;
 if(select count(*)from ipqc_gc_tieu_chuan_lich_su where id_btk=draft_id)<>2 then raise exception 'Save history not retained';end if;
 if(select xac_nhan_boi from ipqc_btk_muc where id_btk=draft_id)is distinct from qc then raise exception 'Confirmation identity lost';end if;
end $$;
select 'PASS shared registry legacy revision: same draft ID/history, original approved standard/features untouched, no invented step/code, bounds/positions/confirmation retained' as result;
rollback;
