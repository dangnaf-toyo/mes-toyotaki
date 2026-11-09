-- Run only on jcjbleugnclzsghfpmvk. Includes real current functions; all fixtures roll back.
begin;
do $$
declare u uuid;reader uuid:=gen_random_uuid();other uuid;account_name text;c text;before_case jsonb;
 path1 text;path2 text;path3 text;a uuid;request uuid:=gen_random_uuid();result jsonb;again jsonb;payload jsonb;
 n integer;failed boolean;product text;cp public.duc_ipqc_checkpoint%rowtype;other_role text;
begin
 select user_id,username into u,account_name from user_roles where role='admin' limit 1;
 select user_id into other from user_roles where user_id<>u limit 1;
 select id_ncp,to_jsonb(r) into c,before_case from duc_ncp r order by id_ncp limit 1;
 if u is null or c is null then raise exception 'Needs existing staging admin and case';end if;
 perform set_config('request.jwt.claim.sub',u::text,true);
 if not ncp_anh_duoc_sua(c) then raise exception 'Admin cannot edit';end if;
 path1:=u||'/'||request||'/'||gen_random_uuid()||'.jpg';
 path2:=u||'/'||request||'/'||gen_random_uuid()||'.jpg';
 path3:=u||'/'||request||'/'||gen_random_uuid()||'.jpg';
 -- Storage metadata fixture only: never uploads/deletes real files.
 insert into storage.objects(bucket_id,name,owner_id,metadata) values
 ('ncp-hinh-anh',path1,u::text,'{"mimetype":"image/jpeg","size":512}'),
 ('ncp-hinh-anh',path2,u::text,'{"mimetype":"image/jpeg","size":1024}'),
 ('ncp-hinh-anh',path3,u::text,'{"mimetype":"image/jpeg","size":1024}');
 perform ncp_anh_them(c,jsonb_build_array(jsonb_build_object('path',path1,'name','One.jpg')));
 select id into a from ncp_hinh_anh where storage_path=path1;
 perform ncp_anh_them(c,jsonb_build_array(jsonb_build_object('path',path1,'name','One.jpg')));
 if (select count(*) from ncp_hinh_anh_lich_su where id_anh=a)<>1 then raise exception 'Retry duplicated audit';end if;
 perform ncp_anh_them(c,jsonb_build_array(jsonb_build_object('path',path2,'name','Two.png')));
 if not exists(select 1 from ncp_hinh_anh where id_ncp=c and storage_path=path2 and xoa_luc is null) then raise exception 'Second image lost';end if;
 if (select to_jsonb(r) from duc_ncp r where id_ncp=c) is distinct from before_case then raise exception 'Adding images changed case business data';end if;
 perform set_config('request.jwt.claim.sub',reader::text,true);
 if ncp_anh_duoc_sua(c) or ncp_anh_duoc_sua() then raise exception 'Unregistered account has permission';end if;
 failed:=false;begin perform ncp_anh_xoa(a);exception when others then failed:=true;end;
 if not failed then raise exception 'Unauthorized delete allowed';end if;
 failed:=false;begin perform ncp_anh_them(c,'[]');exception when others then failed:=true;end;
 if not failed then raise exception 'Unauthorized add allowed';end if;
 -- Even an assigned/opening account becomes read-only when its role is chi_xem.
 select role into other_role from user_roles where user_id=other;
 update user_roles set role='chi_xem' where user_id=other;
 perform set_config('request.jwt.claim.sub',other::text,true);
 if ncp_anh_duoc_sua(c) or ncp_anh_duoc_sua() then raise exception 'Read-only account can edit';end if;
 update user_roles set role=other_role where user_id=other;
 perform set_config('request.jwt.claim.sub',u::text,true);
 perform ncp_anh_xoa(a);perform ncp_anh_xoa(a);
 if (select count(*) from ncp_hinh_anh_lich_su where id_anh=a and thao_tac='xoa' and nguoi_thuc_hien=u)<>1
 or not exists(select 1 from ncp_hinh_anh where id=a and xoa_luc is not null and nguoi_xoa=u)
 or not exists(select 1 from storage.objects where name=path1 and bucket_id='ncp-hinh-anh') then raise exception 'Delete audit/retention failed';end if;
 if (select to_jsonb(r) from duc_ncp r where id_ncp=c) is distinct from before_case then raise exception 'Deletion changed case';end if;
 for n in 1..4 loop
  update storage.objects set metadata=case n when 1 then '{"mimetype":"image/svg+xml","size":512}'::jsonb
    when 2 then '{"mimetype":"image/jpeg","size":5242881}'::jsonb
    when 3 then '{"mimetype":"image/jpeg","size":0}'::jsonb
    else '{"mimetype":"image/jpeg","size":512}'::jsonb end,
    owner_id=case when n=4 then other::text else u::text end where name=path3;
  failed:=false;begin perform ncp_anh_them(c,jsonb_build_array(jsonb_build_object('path',path3,'name','Invalid.jpg')));exception when others then failed:=true;end;
  if not failed then raise exception 'Bad MIME/size/owner accepted: %',n;end if;
 end loop;
 update storage.objects set metadata='{"mimetype":"image/jpeg","size":512}',owner_id=u::text where name=path3;
 failed:=false;begin perform ncp_anh_them(c,jsonb_build_array(jsonb_build_object('path',u||'/not-uploaded.jpg','name','Invalid.jpg')));exception when others then failed:=true;end;
 if not failed then raise exception 'Missing/invalid path accepted';end if;
 -- Atomic manual create + 1 photo, retry, zero photos, multiple photos, invalid-photo rollback.
 select ma_sp into product from master_products order by ma_sp limit 1;
 payload:=jsonb_build_object('source_type','department','department','Rollback QA','product_code',product,
 'description','NCP image rollback test','quantity',1,'ng_quantity',0,'location','Rollback fixture',
 'assignee',account_name,'response_owner',account_name,'response_due',current_date+1);
 result:=ncp_mo_phieu_co_anh(request,'source',payload,jsonb_build_array(jsonb_build_object('path',path3,'name','New.webp')));
 again:=ncp_mo_phieu_co_anh(request,'source',payload,jsonb_build_array(jsonb_build_object('path',path3,'name','New.webp')));
 if result->>'id_ncp' is distinct from again->>'id_ncp' then raise exception 'Create retry duplicated case';end if;
 if not exists(select 1 from ncp_hinh_anh where id_ncp=result->>'id_ncp' and storage_path=path3) then raise exception 'Create did not link image';end if;
 failed:=false;begin perform ncp_mo_phieu_co_anh(request,'source',payload||'{"description":"Changed"}', '[]');exception when others then failed:=true;end;
 if not failed then raise exception 'Changed retry silently accepted';end if;
 result:=ncp_mo_phieu_co_anh(gen_random_uuid(),'source',payload,'[]');
 if exists(select 1 from ncp_hinh_anh where id_ncp=result->>'id_ncp') then raise exception 'Empty create got photos';end if;
 select count(*) into n from duc_ncp;
 failed:=false;begin perform ncp_mo_phieu_co_anh(gen_random_uuid(),'source',payload,'[{"path":"missing","name":"Bad.jpg"}]');exception when others then failed:=true;end;
 if not failed or (select count(*) from duc_ncp)<>n then raise exception 'Failed photo left case behind';end if;
 -- Two attachments on a new NG-linked case use the unchanged existing opening routine.
 select * into cp from duc_ipqc_checkpoint where ket_qua='NG' limit 1;
 if not found then select * into cp from duc_ipqc_checkpoint limit 1;end if;
 if cp.id_checkpoint is null then raise exception 'Needs staging checkpoint fixture';end if;
 cp.id_checkpoint:='NCP-IMAGE-ROLLBACK-'||gen_random_uuid();cp.id_ncp_lien_quan:=null;
 insert into duc_ipqc_checkpoint select (cp).*;
 -- Reuse no path across cases: attachment paths are unique and immutable.
 path1:=u||'/'||gen_random_uuid()||'/'||gen_random_uuid()||'.jpg';
 path2:=u||'/'||gen_random_uuid()||'/'||gen_random_uuid()||'.jpg';
 insert into storage.objects(bucket_id,name,owner_id,metadata) values
 ('ncp-hinh-anh',path1,u::text,'{"mimetype":"image/jpeg","size":512}'),
 ('ncp-hinh-anh',path2,u::text,'{"mimetype":"image/jpeg","size":512}');
 payload:=jsonb_build_object('p_id_checkpoint_goc',cp.id_checkpoint,'p_ma_may',cp.ma_may,'p_ma_sp',cp.ma_sp,
 'p_ten_sp','Rollback fixture','p_so_khuon','Rollback fixture','p_mo_ta_loi','Rollback fixture','p_so_luong_nghi_van',10,
 'p_so_luong_ng_du_kien',1,'p_vi_tri_cach_ly','Rollback fixture','p_nguoi_dam_nhiem',account_name,'p_nguoi_dam_nhiem_doi_sach',account_name);
 result:=ncp_mo_phieu_co_anh(gen_random_uuid(),'ng',payload,jsonb_build_array(jsonb_build_object('path',path1,'name','A.jpg'),jsonb_build_object('path',path2,'name','B.png')));
 if (select count(*) from ncp_hinh_anh where id_ncp=result->>'id_ncp')<>2
 or (select id_ncp_lien_quan from duc_ipqc_checkpoint where id_checkpoint=cp.id_checkpoint) is distinct from result->>'id_ncp'
 then raise exception 'NG create lost photos or checkpoint link';end if;
 -- The old source_images array is copied without changing it, including late old-client writes.
 update duc_ncp set source_images='["https://example.invalid/legacy-photo.jpg"]' where id_ncp=result->>'id_ncp';
 if not exists(select 1 from ncp_hinh_anh where id_ncp=result->>'id_ncp' and legacy_url='https://example.invalid/legacy-photo.jpg') then raise exception 'Late legacy photo missing';end if;
 -- Fill the active-image limit and reject another attachment atomically.
 for n in 1..7 loop
  path3:=u||'/'||gen_random_uuid()||'/'||gen_random_uuid()||'.jpg';
  insert into storage.objects(bucket_id,name,owner_id,metadata) values('ncp-hinh-anh',path3,u::text,'{"mimetype":"image/jpeg","size":512}');
  perform ncp_anh_them(result->>'id_ncp',jsonb_build_array(jsonb_build_object('path',path3,'name','Limit.jpg')));
 end loop;
 failed:=false;begin perform ncp_anh_them(result->>'id_ncp',jsonb_build_array(jsonb_build_object('path',u||'/extra.jpg','name','Extra.jpg')));exception when others then failed:=true;end;
 if not failed or (select count(*) from ncp_hinh_anh where id_ncp=result->>'id_ncp' and xoa_luc is null)<>10 then raise exception 'Image limit not enforced';end if;
 if (select public from storage.buckets where id='ncp-hinh-anh')
 or (select file_size_limit from storage.buckets where id='ncp-hinh-anh')<>5242880 then raise exception 'Bucket guards missing';end if;
 if has_table_privilege('authenticated','ncp_hinh_anh','INSERT') or has_table_privilege('authenticated','ncp_hinh_anh','UPDATE')
 or has_table_privilege('authenticated','ncp_hinh_anh_lich_su','INSERT') or has_table_privilege('anon','ncp_hinh_anh','SELECT')
 or has_function_privilege('anon','ncp_anh_xoa(uuid)','EXECUTE') then raise exception 'Direct/anonymous bypass';end if;
 set constraints all immediate;
 perform set_config('ncp.test.uid',u::text,true);
 perform set_config('ncp.test.path',path2,true);
end $$;
set local role authenticated;
do $$
declare failed boolean;u uuid:=current_setting('ncp.test.uid')::uuid;p text;
begin
 perform set_config('request.jwt.claim.sub',u::text,true);
 if not exists(select 1 from ncp_hinh_anh) then raise exception 'Authenticated read blocked';end if;
 failed:=false;begin update ncp_hinh_anh set xoa_luc=now();exception when insufficient_privilege then failed:=true;end;
 if not failed then raise exception 'Client bypassed audited delete';end if;
 failed:=false;begin insert into ncp_hinh_anh_lich_su(id_anh,id_ncp,thao_tac,nguoi_thuc_hien,ten_file) values(gen_random_uuid(),'fake','them',u,'forged');exception when insufficient_privilege then failed:=true;end;
 if not failed then raise exception 'Client forged audit';end if;
 p:=u||'/'||gen_random_uuid()||'/'||gen_random_uuid()||'.jpg';
 insert into storage.objects(bucket_id,name,owner_id,metadata) values('ncp-hinh-anh',p,u::text,'{"mimetype":"image/jpeg","size":512}');
 failed:=false;begin insert into storage.objects(bucket_id,name) values('ncp-hinh-anh','other-user/not-allowed.jpg');exception when insufficient_privilege then failed:=true;end;
 if not failed then raise exception 'Storage RLS path bypass';end if;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 failed:=false;begin insert into storage.objects(bucket_id,name) values('ncp-hinh-anh',gen_random_uuid()||'/'||gen_random_uuid()||'/'||gen_random_uuid()||'.jpg');exception when insufficient_privilege then failed:=true;end;
 if not failed then raise exception 'Storage RLS allowed unauthorized upload';end if;
end $$;
reset role;
select 'PASS real staging RPC/RLS: manual and NG creation (0/1/many photos), atomic rollback, retry, append/delete with audit, legacy compatibility, 10-photo limit, unchanged case, read-only/unauthorized users, MIME/size/path/owner guards and private storage (ROLLBACK)' result;
rollback;
