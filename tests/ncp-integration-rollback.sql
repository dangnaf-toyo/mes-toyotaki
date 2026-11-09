-- STAGING: test dữ liệu thật trong transaction, luôn rollback toàn bộ.
begin;
do $$
declare u uuid;c text;a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();extra uuid;
 d ncp_doi_sach%rowtype;before_stamp timestamptz;failed boolean;
begin
 select user_id into u from user_roles where role='admin' limit 1;
 perform set_config('request.jwt.claim.sub',u::text,true);
 select id_ncp,ngay_tao into c,before_stamp from duc_ncp order by id_ncp limit 1;
 if u is null or c is null then raise exception 'Staging test needs existing admin and NCP';end if;
 update duc_ncp set doi_sach_ps_tam_thoi_json='[]',doi_sach_ps_lau_dai_json='[]',
  doi_sach_lx_tam_thoi_json='[]',doi_sach_lx_lau_dai_json='[]',rc_trang_thai_duyet='nhap' where id_ncp=c;
 update ncp_doi_sach set da_luu_tru=true,vi_tri_cu=null where id_ncp=c;
 update duc_ncp set doi_sach_ps_tam_thoi_json=jsonb_build_array(
  jsonb_build_object('id_doi_sach',a,'noi_dung','First response','danh_gia','Keep evaluation'),
  jsonb_build_object('id_doi_sach',b,'noi_dung','')) where id_ncp=c;
 if (select ncp_da_tra_loi(r) from duc_ncp r where id_ncp=c) then raise exception 'Unanswered second child ignored';end if;
 update duc_ncp set doi_sach_ps_tam_thoi_json=jsonb_build_array(
  jsonb_build_object('id_doi_sach',b,'noi_dung',''),
  jsonb_build_object('id_doi_sach',a,'noi_dung','First response','danh_gia','Keep evaluation')) where id_ncp=c;
 if (select vi_tri_cu from ncp_doi_sach where id=a)<>2 or
  (select vi_tri_cu from ncp_doi_sach where id=b)<>1 then raise exception 'Reorder lost stable identity';end if;
 select * into d from ncp_doi_sach where id=a;
 perform ncp_luu_doi_sach(a,to_jsonb(d)||jsonb_build_object('loai','noi_bo','noi_dung_tra_loi','Edited from board'));
 if (select doi_sach_ps_tam_thoi_json->1->>'noi_dung' from duc_ncp where id_ncp=c)<>'Edited from board'
  or (select doi_sach_ps_tam_thoi_json->1->>'danh_gia' from duc_ncp where id_ncp=c)<>'Keep evaluation'
  then raise exception 'Board edit did not preserve/synchronize legacy JSON';end if;
 update duc_ncp set rc_trang_thai_duyet='da_duyet' where id_ncp=c;
 select * into d from ncp_doi_sach where id=a;
 failed:=false;
 begin perform ncp_luu_doi_sach(a,to_jsonb(d)||jsonb_build_object('noi_dung_tra_loi','Forbidden edit'));
 exception when others then failed:=true;end;
 if not failed then raise exception 'Board bypassed legacy approval lock';end if;
 perform ncp_luu_doi_sach(a,to_jsonb(d)||jsonb_build_object('han_tra_loi',clock_timestamp()+interval '1 day'));
 update duc_ncp set rc_trang_thai_duyet='nhap' where id_ncp=c;
 update duc_ncp set doi_sach_ps_tam_thoi_json=doi_sach_ps_tam_thoi_json-0 where id_ncp=c;
 if not(select da_luu_tru from ncp_doi_sach where id=b) or
  exists(select 1 from ncp_doi_sach_theo_doi where id=b) then raise exception 'Removed source row remains active';end if;
 if not exists(select 1 from ncp_doi_sach_lich_su where id_doi_sach=b and du_lieu_moi->>'da_luu_tru'='true')
  then raise exception 'Archived source history missing';end if;
 if not(select ncp_da_tra_loi(r) from duc_ncp r where id_ncp=c) then raise exception 'Answered active children not reflected in case';end if;
 extra:=ncp_luu_doi_sach(null,jsonb_build_object('id_ncp',c,'loai','khach_hang','van_de','Rollback integration'));
 if (select ncp_da_tra_loi(r) from duc_ncp r where id_ncp=c) then raise exception 'New unanswered child not reflected';end if;
 select * into d from ncp_doi_sach where id=extra;
 perform ncp_luu_doi_sach(extra,to_jsonb(d)||jsonb_build_object('noi_dung_tra_loi','Answered'));
 if not(select ncp_da_tra_loi(r) from duc_ncp r where id_ncp=c) then raise exception 'All answered case not reflected';end if;
 if (select ngay_tao from duc_ncp where id_ncp=c)is distinct from before_stamp then raise exception 'Integration changed creation timestamp';end if;
 if has_function_privilege('anon','public.ncp_luu_doi_sach(uuid,jsonb)','EXECUTE') or
  has_function_privilege('authenticated','public.ncp_luu_doi_sach_t212(uuid,jsonb)','EXECUTE') then raise exception 'Writer bypass is exposed';end if;
 set constraints all immediate;
end $$;
select 'PASS stable row identity/reorder, archive with history, bidirectional legacy synchronization, aggregate status and writer grants' as result;
rollback;
