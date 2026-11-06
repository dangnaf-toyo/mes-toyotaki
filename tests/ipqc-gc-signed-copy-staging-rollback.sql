-- STAGING only. Complete workflow fixtures are rolled back.
begin;
do $$
declare actor uuid;src text;dst text;machine text;token text:=gen_random_uuid()::text;
 p jsonb;items jsonb;r jsonb;source_id bigint;old_target bigint;copied bigint;legacy bigint;cast_id bigint;
 source_snapshot jsonb;source_features jsonb;target_snapshot jsonb;target_features jsonb;copy_features jsonb;
 failed boolean;measured uuid;values_json jsonb;item jsonb;marker integer;
begin
 select user_id into actor from user_roles where role='admin'order by user_id limit 1;
 select ma_sp into src from master_products order by ma_sp limit 1;
 select ma_sp into dst from master_products where ma_sp<>src order by ma_sp limit 1;
 select ma_may into machine from master_machines where bo_phan='Gia công - Sơn'limit 1;
 if actor is null or src is null or dst is null or machine is null then raise exception 'Need staging admin, two products and machining machine';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 select jsonb_agg(jsonb_build_object('muc_no',n,'ma_dac_tinh','D'||n,'hang_muc','Feature '||n,
  'kieu',case when n=50 then 'okng'else'so'end,'danh_nghia',case when n in(2,3)then 14.6 else 20 end,
  'dung_sai_tren',case n when 1 then 0.05 when 2 then 0.3 when 3 then -0.1 when 4 then 0 else 0.1 end,
  'dung_sai_duoi',case n when 1 then -0.05 when 2 then 0.1 when 3 then -0.3 when 4 then -0.1 else 0 end,
  'tieu_chuan',case when n=50 then 'Không ba via'else null end,'dung_cu','CMM','don_vi','mm','phuong_phap','CMM point',
  'tan_suat','2h/lần','co_mau',2,'nguon_nhan_dien',jsonb_build_object('ghi_chu','Keep config '||n),'da_xac_nhan',true)order by n)
 into items from generate_series(1,50)n;
 p:=jsonb_build_object('ma_sp',src,'ma_ban_ve','DRAWING-SOURCE','phien_ban','A','buoc_gia_cong','Signed copy '||token,
  'dung_sai_co_dau',true,'ngay_hieu_luc',(now()at time zone'Asia/Ho_Chi_Minh')::date,'so_mau',2,'noi_dung_sua_doi','Rollback signed source',
  'tai_lieu_goc',jsonb_build_object('path',actor::text||'/source.pdf','name','source.pdf'),'ban_ve_url','https://example.invalid/source.png',
  'ban_ve_vi_tri',jsonb_build_array(jsonb_build_object('no',1,'x',20,'y',30)),'muc',items);
 r:=ipqc_gc_luu_tieu_chuan(p);source_id:=(r->>'id')::bigint;
 if not(r->>'ok')::boolean then raise exception '%',r;end if;
 for item in select jsonb_build_object('no',n,'lsl',lo,'usl',hi)from(values
  (1,19.95::numeric,20.05::numeric),(2,14.7,14.9),(3,14.3,14.5),(4,19.9,20),(5,20,20.1))v(n,lo,hi)loop
  if not exists(select 1 from ipqc_btk_muc where id_btk=source_id and muc_no=(item->>'no')::int
   and lsl=(item->>'lsl')::numeric and usl=(item->>'usl')::numeric and dung_sai_co_dau)then raise exception 'Signed example failed: %',item;end if;
 end loop;
 if(select dung_sai_duoi from ipqc_btk_muc where id_btk=source_id and muc_no=2)<>0.1
  or(select dung_sai_tren from ipqc_btk_muc where id_btk=source_id and muc_no=3)<>-0.1 then raise exception 'Sign lost in storage';end if;
 failed:=false;begin
  perform ipqc_gc_luu_tieu_chuan(p||jsonb_build_object('phien_ban','BAD','buoc_gia_cong','Bad '||token,
   'muc',jsonb_build_array(jsonb_build_object('muc_no',1,'hang_muc','Bad bounds','kieu','so','danh_nghia',20,'dung_sai_tren',0.1,'dung_sai_duoi',0.2,'da_xac_nhan',true))));
 exception when others then failed:=true;end;if not failed then raise exception 'Inverted limits accepted';end if;
 -- Historical magnitude semantics remain available to old clients, and casting stays unchanged.
 r:=ipqc_btk_luu(src,jsonb_build_object('phien_ban','LEGACY-'||token,'buoc_gia_cong','Legacy '||token,'so_mau',1,
  'muc',jsonb_build_array(jsonb_build_object('muc_no',1,'hang_muc','Legacy','kieu','so','danh_nghia',20,'dung_sai_tren',0.05,'dung_sai_duoi',0.05))),'ignored','gia_cong');
 legacy:=(r->>'id')::bigint;
 if not(r->>'ok')::boolean then raise exception '%',r;end if;
 if(select dung_sai_co_dau from ipqc_btk_muc where id_btk=legacy)
  or(select dung_sai_duoi from ipqc_btk_muc where id_btk=legacy)<>0.05 then raise exception 'Legacy semantics changed';end if;
 r:=ipqc_gc_sao_chep_tieu_chuan(legacy,dst,null);marker:=(r->>'id')::int;
 if not exists(select 1 from ipqc_btk_muc where id_btk=marker and dung_sai_co_dau and dung_sai_duoi=-0.05 and lsl=19.95 and usl=20.05)
  then raise exception 'Copying legacy magnitudes changed effective limits';end if;
 r:=ipqc_btk_luu(dst,jsonb_build_object('phien_ban','CAST-'||token,'dung_sai_co_dau',true,'so_mau',1,
  'muc',jsonb_build_array(jsonb_build_object('muc_no',1,'hang_muc','Casting','kieu','so','danh_nghia',20,'dung_sai_tren',-0.1,'dung_sai_duoi',-0.2))),'ignored','duc');
 cast_id:=(r->>'id')::bigint;
 if not(r->>'ok')::boolean then raise exception '%',r;end if;
 if(select dung_sai_co_dau from ipqc_btk_muc where id_btk=cast_id)
  or(select dung_sai_tren from ipqc_btk_muc where id_btk=cast_id)<>0.1
  or(select dung_sai_duoi from ipqc_btk_muc where id_btk=cast_id)<>0.2 then raise exception 'Casting semantics changed';end if;
 r:=ipqc_tc_duyet('btk',source_id,'kiem_tra',null,'ignored');if not(r->>'ok')::boolean then raise exception '%',r;end if;
 r:=ipqc_tc_duyet('btk',source_id,'phe_duyet',null,'ignored');if not(r->>'ok')::boolean then raise exception '%',r;end if;
 r:=ipqc_gc_luu_tieu_chuan(p||jsonb_build_object('ma_sp',dst,'noi_dung_sua_doi','Existing target'));
 old_target:=(r->>'id')::bigint;
 r:=ipqc_tc_duyet('btk',old_target,'kiem_tra',null,'ignored');if not(r->>'ok')::boolean then raise exception '%',r;end if;
 r:=ipqc_tc_duyet('btk',old_target,'phe_duyet',null,'ignored');if not(r->>'ok')::boolean then raise exception '%',r;end if;
 select to_jsonb(b)into source_snapshot from ipqc_btk b where id=source_id;
 select jsonb_agg(to_jsonb(m)order by m.muc_no)into source_features from ipqc_btk_muc m where id_btk=source_id;
 select to_jsonb(b)into target_snapshot from ipqc_btk b where id=old_target;
 select jsonb_agg(to_jsonb(m)order by m.muc_no)into target_features from ipqc_btk_muc m where id_btk=old_target;
 failed:=false;begin perform ipqc_gc_sao_chep_tieu_chuan(source_id,dst,'A');exception when others then failed:=true;end;
 if not failed then raise exception 'Published destination revision overwritten';end if;
 failed:=false;begin perform ipqc_gc_sao_chep_tieu_chuan(cast_id,dst,'Z');exception when others then failed:=true;end;
 if not failed then raise exception 'Casting source accepted by machining copy';end if;
 r:=ipqc_gc_sao_chep_tieu_chuan(source_id,dst,null);copied:=(r->>'id')::bigint;
 if r->>'trang_thai'<>'ban_nhap'or r->>'phien_ban'<>'B' then raise exception 'Not a new independent draft: %',r;end if;
 if(select count(*)from ipqc_btk_muc where id_btk=copied)<>50 then raise exception 'Not all 50 features copied';end if;
 if exists(select 1 from ipqc_btk_muc where id_btk=copied and(xac_nhan_boi is not null or xac_nhan_luc is not null))then raise exception 'Feature confirmation copied';end if;
 if not exists(select 1 from ipqc_btk where id=copied and ma_sp=dst and not dang_dung and ma_ban_ve is null and tai_lieu_goc is null
  and ban_ve_url is null and ban_ve_vi_tri='[]'::jsonb and nguoi_kiem_tra_uid is null and nguoi_phe_duyet_uid is null
  and(nguon_sao_chep->>'id_nguon')::bigint=source_id and(nguon_sao_chep->>'nguoi_sao_chep_uid')::uuid=actor
  and nguon_sao_chep->>'model_nguon'=src and nguon_sao_chep->>'thoi_diem' is not null)then raise exception 'Source metadata/file/approval isolation failed';end if;
 r:=ipqc_tc_duyet('btk',copied,'kiem_tra',null,'ignored');if(r->>'ok')::boolean then raise exception 'Unsubmitted copy reviewed';end if;
 failed:=false;begin perform ipqc_gc_luu_do(jsonb_build_object('request_id',gen_random_uuid(),'id_btk',copied,'ma_sp',dst,'ma_may',machine,'ca','Ca ngày','ma_lo','Rollback','kq','[]'::jsonb));
 exception when others then failed:=true;end;if not failed then raise exception 'Unpublished copy used for measurement';end if;
 failed:=false;begin perform ipqc_gc_sao_chep_tieu_chuan(source_id,dst,'C');exception when others then failed:=true;end;
 if not failed then raise exception 'Existing target draft overwritten';end if;
 failed:=false;begin perform ipqc_gc_sao_chep_tieu_chuan(source_id,src,'Z');exception when others then failed:=true;end;
 if not failed then raise exception 'Source model overwritten';end if;
 select jsonb_agg(to_jsonb(m)-'id'-'id_btk'-'xac_nhan_boi'-'xac_nhan_luc'order by m.muc_no)into copy_features from ipqc_btk_muc m where id_btk=copied;
 if copy_features is distinct from(select jsonb_agg(to_jsonb(m)-'id'-'id_btk'-'xac_nhan_boi'-'xac_nhan_luc'order by m.muc_no)from ipqc_btk_muc m where id_btk=source_id)then raise exception 'Feature configuration lost';end if;
 select jsonb_agg((to_jsonb(m)||jsonb_build_object('hang_muc',case when muc_no<=3 then hang_muc||' revised'else hang_muc end,'da_xac_nhan',true))order by muc_no)
 into items from ipqc_btk_muc m where id_btk=copied;
 p:=p||jsonb_build_object('ma_sp',dst,'phien_ban','B','ma_ban_ve','TARGET-DRAWING','tai_lieu_goc',null,'muc',items);
 r:=ipqc_gc_luu_tieu_chuan(p);if(r->>'id')::bigint<>copied then raise exception 'Submitting draft changed ID';end if;
 if(select count(*)from ipqc_btk_muc where id_btk=copied and hang_muc like '% revised')<>3 then raise exception 'Expected three changed features';end if;
 if(select to_jsonb(b)from ipqc_btk b where id=source_id)is distinct from source_snapshot
  or(select jsonb_agg(to_jsonb(m)order by muc_no)from ipqc_btk_muc m where id_btk=source_id)is distinct from source_features
  or(select to_jsonb(b)from ipqc_btk b where id=old_target)is distinct from target_snapshot
  or(select jsonb_agg(to_jsonb(m)order by muc_no)from ipqc_btk_muc m where id_btk=old_target)is distinct from target_features
  then raise exception 'Source or existing target changed';end if;
 r:=ipqc_tc_duyet('btk',copied,'kiem_tra',null,'ignored');if not(r->>'ok')::boolean then raise exception '%',r;end if;
 r:=ipqc_tc_duyet('btk',copied,'phe_duyet',null,'ignored');if not(r->>'ok')::boolean then raise exception '%',r;end if;
 select jsonb_agg(jsonb_build_object('muc_no',m.muc_no,'mau',s,'gia_tri',case when m.muc_no=2 and s=1 then 14.69 else m.lsl end,'dat',true)order by m.muc_no,s)
 into values_json from ipqc_btk_muc m cross join generate_series(1,2)s where m.id_btk=copied;
 measured:=ipqc_gc_luu_do(jsonb_build_object('request_id',gen_random_uuid(),'id_btk',copied,'ma_sp',dst,'ma_may',machine,'ca','Ca ngày','ma_lo','Rollback','kq',values_json));
 if(select dat from ipqc_gc_lan where id=measured)then raise exception '14.69 must be NG for positive/positive 14.7–14.9';end if;
 if(select(tieu_chuan->'muc'->1->>'dung_sai_duoi')::numeric from ipqc_gc_lan where id=measured)<>0.1 then raise exception 'Snapshot lost signed deviation';end if;
 r:=ipqc_tc_huy('btk',copied);if(r->>'ok')::boolean then raise exception 'Released copy cancelled';end if;
 r:=ipqc_gc_sao_chep_tieu_chuan(source_id,dst,'C');marker:=(r->>'id')::int;
 r:=ipqc_tc_huy('btk',marker);if not(r->>'ok')::boolean then raise exception 'Cannot cancel independent draft';end if;
 if exists(select 1 from ipqc_gc_tieu_chuan_lich_su where id_btk=marker)then raise exception 'Cancelled draft left blocking history';end if;
 if has_function_privilege('authenticated','public.ipqc_gc_luu_do_t217(jsonb)','execute')then raise exception 'Internal writer exposed';end if;
 if has_function_privilege('anon','public.ipqc_gc_sao_chep_tieu_chuan(bigint,text,text)','execute')then raise exception 'Anonymous copy exposed';end if;
end $$;
select 'PASS five signed examples/save/reopen; legacy and casting compatibility; 50-feature independent draft; collision/source/file/approval isolation; edit three features; release and signed NG measurement' as result;
rollback;
