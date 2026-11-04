-- Kiểm thử STAGING trong transaction tự rollback, không lưu dữ liệu thử.
begin;
do $$
declare qc uuid;manager uuid;director uuid;oqc uuid;product text;machine text;r jsonb;payload jsonb;id1 bigint;id2 bigint;
 req uuid:=gen_random_uuid();measurement uuid;saved ipqc_gc_lan%rowtype;before_cast bigint;cast_btk bigint;failed boolean;std_payload jsonb;
begin
 select user_id into qc from user_roles where role in('ipqc','admin')order by(role='ipqc')desc limit 1;
 select user_id into manager from user_roles where role in('qc_manager','admin')and user_id<>qc order by(role='qc_manager')desc limit 1;
 select user_id into director from user_roles where role in('giam_doc_sx','admin')and user_id not in(qc,manager)order by(role='giam_doc_sx')desc limit 1;
 if qc is null or manager is null or director is null then raise exception 'Need staging QC, manager and director accounts';end if;
 -- Role assignments exist only inside this rollback transaction. No account is changed persistently.
 update user_roles set role='ipqc'where user_id=qc;
 update user_roles set role='qc_manager'where user_id=manager;
 update user_roles set role='giam_doc_sx'where user_id=director;
 select ma_sp into product from master_products p where not exists(select 1 from ipqc_btk b where b.ma_sp=p.ma_sp and b.cong_doan='gia_cong'and b.trang_thai<>'da_duyet')order by ma_sp limit 1;
 select ma_may into machine from master_machines where bo_phan='Gia công - Sơn'order by ma_may limit 1;
 if product is null or machine is null then raise exception 'Need staging product and machining machine';end if;
 select count(*)into before_cast from ipqc_do_lan;
 perform set_config('request.jwt.claim.sub',qc::text,true);
 payload:=jsonb_build_object('ma_sp',product,'ma_ban_ve','ROLLBACK-DRAWING','phien_ban','TEST-'||req::text,'buoc_gia_cong','Rollback inspection',
 'ngay_hieu_luc',(now()at time zone'Asia/Ho_Chi_Minh')::date,'noi_dung_sua_doi','Rollback test','so_mau',1,
 'muc',jsonb_build_array(jsonb_build_object('muc_no',1,'ma_dac_tinh','D01','hang_muc','Diameter','kieu','so','danh_nghia',20,
 'dung_sai_tren',0.05,'dung_sai_duoi',-0.05,'lsl',19.95,'usl',20.05,'don_vi','mm','co_mau',2,'dung_cu','CMM','da_xac_nhan',true)));
 std_payload:=payload;
 r:=ipqc_gc_luu_tieu_chuan(payload);id1:=(r->>'id')::bigint;
 failed:=false;begin
  perform ipqc_gc_luu_do(jsonb_build_object('request_id',gen_random_uuid(),'id_btk',id1,'ma_sp',product,'ma_may',machine,'ca','Ca ngày','ma_lo','ROLLBACK','kq','[]'::jsonb));
 exception when others then failed:=true;end;
 if not failed then raise exception 'Unapproved standard was accepted';end if;
 perform set_config('request.jwt.claim.sub',manager::text,true);r:=ipqc_tc_duyet('btk',id1,'kiem_tra',null,'Rollback');if not(r->>'ok')::boolean then raise exception '%',r;end if;
 perform set_config('request.jwt.claim.sub',director::text,true);r:=ipqc_tc_duyet('btk',id1,'phe_duyet',null,'Rollback');if not(r->>'ok')::boolean then raise exception '%',r;end if;
 if (select nguoi_phe_duyet from ipqc_btk where id=id1)is distinct from
  (select coalesce(nullif(full_name,''),username) from user_roles where user_id=director)
  then raise exception 'Approval actor trusted client name';end if;
 perform set_config('request.jwt.claim.sub',qc::text,true);
 payload:=jsonb_build_object('request_id',req,'id_btk',id1,'ma_sp',product,'ma_may',machine,'ca','Ca ngày','ma_lo','ROLLBACK',
 'kq',jsonb_build_array(jsonb_build_object('muc_no',1,'mau',1,'gia_tri',19.95),jsonb_build_object('muc_no',1,'mau',2,'gia_tri',20.06)));
 measurement:=ipqc_gc_luu_do(payload);select * into saved from ipqc_gc_lan where id=measurement;
 if saved.dat or saved.so_mau<>2 then raise exception '20.06 must be NG for USL 20.05, with two samples';end if;
 if ipqc_gc_luu_do(payload)<>measurement then raise exception 'Retry duplicated measurement';end if;
 failed:=false;begin
  perform ipqc_gc_luu_do(payload||jsonb_build_object('request_id',gen_random_uuid(),'kq',jsonb_build_array(jsonb_build_object('muc_no',1,'mau',1,'gia_tri',20))));
 exception when others then failed:=true;end;if not failed then raise exception 'Incomplete samples accepted';end if;
 if (select count(*)from ipqc_gc_kq where id_lan=measurement)<>2 then raise exception 'Missing per-sample results';end if;
 if not exists(select 1 from ipqc_gc_kq where id_lan=measurement and mau=1 and dat)then raise exception 'LSL boundary should be OK';end if;
 if (select count(*)from ipqc_lan_tong_hop where id=measurement::text and cong_doan='gia_cong')<>1 then raise exception 'Unified dashboard missing machining measurement';end if;
 update ipqc_btk_muc set usl=21 where id_btk=id1;
 if (select(tieu_chuan->'muc'->0->>'usl')::numeric from ipqc_gc_lan where id=measurement)<>20.05 then raise exception 'History snapshot changed';end if;
 std_payload:=std_payload||jsonb_build_object('phien_ban','LIMITS-'||req::text,'muc',jsonb_build_array(jsonb_build_object(
 'muc_no',1,'ma_dac_tinh','LIMIT','hang_muc','Max-only dimension','kieu','so','danh_nghia',null,'usl',2,'co_mau',1,'da_xac_nhan',true)));
 r:=ipqc_gc_luu_tieu_chuan(std_payload);id2:=(r->>'id')::bigint;
 if (select danh_nghia from ipqc_btk_muc where id_btk=id2)is not null then raise exception 'Explicit Max must not invent nominal';end if;
 if (select usl from ipqc_btk_muc where id_btk=id2)<>2 then raise exception 'Max-only bound was lost';end if;
 -- Same drawing Revision may have independent standards for separate machining steps.
 std_payload:=std_payload||jsonb_build_object('phien_ban','TEST-'||req::text,'buoc_gia_cong','Second machining step');
 r:=ipqc_gc_luu_tieu_chuan(std_payload);
 if(r->>'id')::bigint=id1 or(r->>'id')::bigint=id2 then raise exception 'Different machining steps shared a standard row';end if;
 select id into cast_btk from ipqc_btk where cong_doan='duc'limit 1;
 if cast_btk is not null then failed:=false;begin
  perform ipqc_gc_luu_do(payload||jsonb_build_object('request_id',gen_random_uuid(),'id_btk',cast_btk));
 exception when others then failed:=true;end;if not failed then raise exception 'Casting standard crossed into machining';end if;end if;
 if(select count(*)from ipqc_do_lan)<>before_cast then raise exception 'Casting measurements changed';end if;
 select user_id into oqc from user_roles where role='nhan_vien_oqc' limit 1;
 if oqc is not null then
  perform set_config('request.jwt.claim.sub',oqc::text,true);failed:=false;
  begin perform ipqc_gc_luu_do(payload||jsonb_build_object('request_id',gen_random_uuid()));
  exception when others then failed:=true;end;
  if not failed then raise exception 'OQC role could save machining measurements';end if;
 end if;
end $$;
select 'PASS machining standard approval, multi-sample measurement, boundary OK/20.06 NG, retry dedup, immutable snapshots, combined dashboard and casting isolation' as result;
rollback;
