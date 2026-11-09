-- STAGING only. Optionally set test.ipqc.drawing_prefix to an uploaded fixture folder before this file.
-- Standards/history and fallback storage metadata fixtures always roll back.
begin;
do $$
declare actor uuid;product text;prefix text;token text:=gen_random_uuid()::text;
 p jsonb;r jsonb;first_id bigint;draft_id bigint;published jsonb;features jsonb;failed boolean;
begin
 select user_id into actor from user_roles where role='admin'order by user_id limit 1;
 if actor is null then raise exception 'Need staging admin';end if;
 prefix:=nullif(current_setting('test.ipqc.drawing_prefix',true),'');
 if prefix is null then
  prefix:=actor::text||'/rollback-drawing-'||token;
  insert into storage.objects(bucket_id,name)values
   ('ipqc-gia-cong-ban-ve',prefix||'/reference.pdf'),
   ('ipqc-gia-cong-ban-ve',prefix||'/reference.png'),
   ('ipqc-gia-cong-ban-ve',prefix||'/reference.jpg');
 end if;
 if(select count(*)from storage.objects where bucket_id='ipqc-gia-cong-ban-ve'
  and name in(prefix||'/reference.pdf',prefix||'/reference.png',prefix||'/reference.jpg'))<>3 then raise exception 'Missing uploaded fixtures';end if;
 if(select public from storage.buckets where id='ipqc-gia-cong-ban-ve')then raise exception 'Drawing bucket must remain private';end if;
 select ma_sp into product from master_products order by ma_sp limit 1;
 if product is null then raise exception 'Need staging product';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 p:=jsonb_build_object('ma_sp',product,'ma_ban_ve','REF-'||token,'buoc_gia_cong','Attachment rollback '||token,
  'phien_ban','A','ngay_hieu_luc',(now()at time zone'Asia/Ho_Chi_Minh')::date,'noi_dung_sua_doi','Reference file test','so_mau',1,
  'tai_lieu_goc',jsonb_build_object('path',prefix||'/reference.pdf','name','reference.pdf'),
  'ban_ve_vi_tri',jsonb_build_array(jsonb_build_object('no',1,'x',20,'y',30)),
  'muc',jsonb_build_array(jsonb_build_object('muc_no',1,'ma_dac_tinh','D01','hang_muc','Diameter','kieu','so','danh_nghia',20,
   'dung_sai_tren',0.05,'dung_sai_duoi',0.05,'lsl',19.95,'usl',20.05,'don_vi','mm','co_mau',2,'dung_cu','CMM','da_xac_nhan',true)));
 r:=ipqc_gc_luu_tieu_chuan(p);first_id:=(r->>'id')::bigint;
 if not(r->>'ok')::boolean then raise exception '%',r;end if;
 r:=ipqc_tc_duyet('btk',first_id,'kiem_tra',null,'Ignored');if not(r->>'ok')::boolean then raise exception '%',r;end if;
 r:=ipqc_tc_duyet('btk',first_id,'phe_duyet',null,'Ignored');if not(r->>'ok')::boolean then raise exception '%',r;end if;
 select to_jsonb(b)into published from ipqc_btk b where id=first_id;
 select jsonb_agg(to_jsonb(m)order by m.muc_no)into features from ipqc_btk_muc m where id_btk=first_id;
 if published->'tai_lieu_goc'->>'path'<>prefix||'/reference.pdf' or published->>'ma_sp'<>product
  or published->>'ma_ban_ve'<>'REF-'||token or published->>'phien_ban'<>'A' then raise exception 'Drawing link lost';end if;
 p:=p||jsonb_build_object('phien_ban','B','noi_dung_sua_doi','Replace reference file',
  'tai_lieu_goc',jsonb_build_object('path',prefix||'/reference.png','name','reference.png'));
 r:=ipqc_gc_luu_tieu_chuan(p);draft_id:=(r->>'id')::bigint;
 if not(r->>'ok')::boolean or draft_id=first_id then raise exception 'Published revision overwritten';end if;
 p:=p||jsonb_build_object('tai_lieu_goc',jsonb_build_object('path',prefix||'/reference.jpg','name','reference.jpg'));
 r:=ipqc_gc_luu_tieu_chuan(p);
 if not(r->>'ok')::boolean or(r->>'id')::bigint<>draft_id then raise exception 'Replacing file changed draft ID';end if;
 if(select tai_lieu_goc->>'path'from ipqc_btk where id=draft_id)<>prefix||'/reference.jpg' then raise exception 'Replacement not saved';end if;
 if(select count(*)from ipqc_btk_muc where id_btk=draft_id)<>1
  or(select lsl from ipqc_btk_muc where id_btk=draft_id)<>19.95
  or(select usl from ipqc_btk_muc where id_btk=draft_id)<>20.05
  or(select co_mau from ipqc_btk_muc where id_btk=draft_id)<>2 then raise exception 'Feature rows changed';end if;
 failed:=false;begin perform ipqc_gc_luu_tieu_chuan(p||jsonb_build_object('phien_ban','A'));
 exception when others then failed:=true;end;
 if not failed then raise exception 'Published revision accepted overwrite';end if;
 if(select to_jsonb(b)from ipqc_btk b where id=first_id)is distinct from published
  or(select jsonb_agg(to_jsonb(m)order by m.muc_no)from ipqc_btk_muc m where id_btk=first_id)is distinct from features
  then raise exception 'Published standard or dimensions changed';end if;
 if(select count(*)from ipqc_gc_tieu_chuan_lich_su where id_btk=draft_id)<>2 then raise exception 'File revision history lost';end if;
end $$;
select 'PASS private drawing metadata linked to Model/drawing/Revision; draft replacement retains dimensions/ID/history; published file/standard protected; existing admin review/release works' as result;
rollback;
