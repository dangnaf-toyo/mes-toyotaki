-- Run after T234, inside a transaction. Fixtures and their workflow effects always roll back.
begin;
do $$
declare u uuid;other_uid uuid;model text;machine text;b bigint;cp text;doc jsonb;checks jsonb;result jsonb;failed boolean;before_gc jsonb;
begin
 select user_id into u from user_roles where role='admin'limit 1;
 perform set_config('request.jwt.claim.sub',u::text,true);
 select ma_sp into model from master_products order by ma_sp limit 1;
 select ma_may into machine from master_machines order by ma_may limit 1;
 select jsonb_agg(to_jsonb(x)order by id)into before_gc from ipqc_gc_lan x;
 insert into ipqc_btk(ma_sp,cong_doan,phien_ban,ngay_hieu_luc,trang_thai,dang_dung,so_mau,nguoi_lap_uid)
 values(model,'duc','QA-CVT-'||gen_random_uuid(),current_date,'da_duyet',false,3,u)returning id into b;
 insert into ipqc_btk_muc(id_btk,muc_no,hang_muc,kieu,danh_nghia,dung_sai_tren,dung_sai_duoi)
 select b,n,'CVT QA '||n,'so',115.7,.4,.4 from generate_series(1,30)n;
 for test in 1..10 loop
  cp:='QA-CVT-'||gen_random_uuid();
  insert into duc_ipqc_checkpoint(id_checkpoint,id_dong,ma_may,ma_sp,loai_kiem,trang_thai)
  values(cp,null,machine,model,'dinh_ky','cho_kiem');
  perform duc_ipqc_session(cp,true);perform duc_ipqc_session_submit_time(cp,false);
  checks:='[{"muc":"Kích thước (theo bảng tuần kiểm)","dat":true},{"code":"machine_condition","muc":"Điều kiện máy","dat":true}]';
  doc:=jsonb_build_object('id_btk',b,'muc_da_chon','[2,5,12,20]'::jsonb,'kq','[{"muc_no":2,"mau":1,"ma_cvt":"2-1","gia_tri":115.85},{"muc_no":2,"mau":2,"ma_cvt":"2-2","gia_tri":115.91},{"muc_no":2,"mau":3,"ma_cvt":"69","gia_tri":115.76},{"muc_no":2,"mau":4,"ma_cvt":"70","gia_tri":115.76},{"muc_no":5,"mau":1,"ma_cvt":"70","gia_tri":115.7},{"muc_no":12,"mau":1,"ma_cvt":"A","gia_tri":115.7},{"muc_no":20,"mau":1,"ma_cvt":"B","gia_tri":115.7}]'::jsonb);
  if test=1 then
   result:=duc_submit_ipqc_cvt(cp,checks,'OK','["https://example.invalid/qa.jpg"]','',null,'spoofed',doc);
   if not(result->>'ok')::boolean then raise exception 'Save failed';end if;
   if(select count(*)from ipqc_do_kq where id_checkpoint=cp)<>7 then raise exception 'CVT rows overwritten';end if;
   if not exists(select 1 from ipqc_do_lan where id_checkpoint=cp and so_muc_da_kiem=4 and so_muc_chua_kiem=26 and nguoi_uid=u and nguoi<>'spoofed')then raise exception 'Partial counts/author incorrect';end if;
   result:=duc_submit_ipqc_cvt(cp,checks,'OK','["https://example.invalid/qa.jpg"]','',null,'spoofed',doc);
   if result->>'existing'<>'true'then raise exception 'Retry not idempotent';end if;
   result:=ipqc_do_du_lieu(model,null,null,100,'duc');
   if not exists(select 1 from jsonb_array_elements(result->'lan')x where x->>'id_checkpoint'=cp and jsonb_array_length(x->'kq')=7 and x->'kq'->0->>'ma_cvt'='2-1')then raise exception 'CVT lost in history';end if;
  elsif test=2 then
   doc:=jsonb_set(doc,'{kq,2,gia_tri}','116.15');checks:=jsonb_set(checks,'{0,dat}','false');
   perform duc_submit_ipqc_cvt(cp,checks,'NG','["https://example.invalid/qa.jpg"]','CVT 69 NG',null,'QA',doc);
   if(select count(*)from ipqc_do_kq where id_checkpoint=cp and not dat)<>1 or(select ket_qua from duc_ipqc_checkpoint where id_checkpoint=cp)<>'NG'then raise exception 'NG altered';end if;
  else
   if test=3 then doc:=jsonb_set(doc,'{kq,3,ma_cvt}','"69"');
   elsif test=4 then doc:=jsonb_set(doc,'{kq,1,gia_tri}','"NaN"');
   elsif test=5 then doc:=jsonb_set(doc,'{muc_da_chon}','[2,5,12,20,30]');
   elsif test=6 then doc:=jsonb_set(doc,'{kq,0,ma_cvt}','""');
   elsif test=7 then doc:=jsonb_set(doc,'{kq,0,gia_tri}','116.15');
   elsif test=8 then doc:=jsonb_set(doc,'{id_btk}','-1');
   elsif test=9 then doc:=jsonb_set(doc,'{kq}','[]');
   elsif test=10 then checks:=jsonb_set(checks,'{1,dat}','null');end if;
   failed:=false;
   begin perform duc_submit_ipqc_cvt(cp,checks,'OK','["https://example.invalid/qa.jpg"]','',null,'QA',doc);exception when others then failed:=true;end;
   if not failed then raise exception 'Invalid case % accepted',test;end if;
   if exists(select 1 from ipqc_do_lan where id_checkpoint=cp)or(select completed_at from duc_ipqc_inspection_session where checkpoint_id=cp)is not null then raise exception 'Partial write escaped failed transaction';end if;
  end if;
 end loop;
 -- A single CVT, independent of the standard's configured three samples.
 cp:='QA-CVT-'||gen_random_uuid();
 insert into duc_ipqc_checkpoint(id_checkpoint,ma_may,ma_sp,loai_kiem,trang_thai)values(cp,machine,model,'dinh_ky','cho_kiem');
 perform duc_ipqc_session(cp,true);perform duc_ipqc_session_submit_time(cp,false);
 doc:=jsonb_build_object('id_btk',b,'muc_da_chon','[2]'::jsonb,'kq','[{"muc_no":2,"mau":1,"ma_cvt":"70","gia_tri":115.7}]'::jsonb);
 checks:='[{"muc":"Kích thước (theo bảng tuần kiểm)","dat":true}]';
 perform duc_submit_ipqc_cvt(cp,checks,'OK','["https://example.invalid/qa.jpg"]','',null,'QA',doc);
 if not exists(select 1 from ipqc_do_lan where id_checkpoint=cp and so_muc_da_kiem=1 and so_muc_chua_kiem=29)then raise exception 'Single CVT blocked';end if;
 -- Legacy results keep null code and the original number/value, without backfill.
 update ipqc_do_kq set ma_cvt=null where id_checkpoint=cp;
 result:=ipqc_do_du_lieu(model,null,null,100,'duc');
 if not exists(select 1 from jsonb_array_elements(result->'lan')x,jsonb_array_elements(x->'kq')k where x->>'id_checkpoint'=cp and k->>'ma_cvt'is null and(k->>'gia_tri')::numeric=115.7)then raise exception 'Legacy uncoded value not readable';end if;
 select user_id into other_uid from user_roles where user_id<>u limit 1;
 perform set_config('request.jwt.claim.sub',other_uid::text,true);
 failed:=false;begin perform duc_submit_ipqc_cvt(cp,checks,'OK','["https://example.invalid/qa.jpg"]','',null,'QA',doc);exception when others then failed:=true;end;
 if not failed then raise exception 'Wrong owner accepted';end if;
 perform set_config('request.jwt.claim.sub',u::text,true);
 if(select jsonb_agg(to_jsonb(x)order by id)from ipqc_gc_lan x)is distinct from before_gc then raise exception 'Machining data changed';end if;
 if ipqc_do_du_lieu(model,null,null,100,'gia_cong')is distinct from ipqc_do_du_lieu_truoc_cvt(model,null,null,100,'gia_cong')then raise exception 'Machining reader behavior changed';end if;
 -- Browser history reads use actual authenticated-role RLS, including old revisions.
 update user_roles set role='ipqc',chuc_danh=null where user_id=other_uid;
 perform set_config('request.jwt.claim.sub',other_uid::text,true);
 execute 'set local role authenticated';
 if not exists(select 1 from ipqc_do_lan where id_checkpoint=cp)or not exists(select 1 from ipqc_do_kq where id_checkpoint=cp)
 or not exists(select 1 from ipqc_btk where id=b)or(select count(*)from ipqc_btk_muc where id_btk=b)<>30 then raise exception 'IPQC history read denied by RLS';end if;
 execute 'reset role';
 raise notice 'PASS: CVT1/many, 4/30 and 1/30, free codes, duplicates, invalid/missing, revision, NG, atomic rollback, retry, legacy history, owner and machining preservation';
end $$;
select 'PASS T234 casting CVT and partial inspections; all fixtures rolled back' as result;
rollback;
