-- STAGING only: all fixture data and temporary role changes roll back.
begin;
do $$
declare adm uuid;qc uuid;manager uuid;director uuid;product text;kind text;cd text;
 token text:=gen_random_uuid()::text;r jsonb;p jsonb;id1 bigint;id2 bigint;snapshot jsonb;day date;
begin
 select user_id into adm from user_roles where role='admin'limit 1;
 select user_id into qc from user_roles where user_id<>adm and role in('admin','ipqc')limit 1;
 select user_id into manager from user_roles where user_id not in(adm,qc)and role in('admin','qc_manager')limit 1;
 select user_id into director from user_roles where user_id not in(adm,qc,manager)and role in('admin','giam_doc_sx')limit 1;
 if adm is null or qc is null or manager is null or director is null then raise exception 'Need four staging accounts';end if;
 update user_roles set role='admin',chuc_danh=null where user_id=adm;
 update user_roles set role='ipqc',chuc_danh=null where user_id=qc;
 update user_roles set role='qc_manager',chuc_danh=null where user_id=manager;
 update user_roles set role='giam_doc_sx',chuc_danh=null where user_id=director;
 select ma_sp into product from master_products p where not exists(
  select 1 from ipqc_btk b where b.ma_sp=p.ma_sp and b.trang_thai<>'da_duyet')and not exists(
  select 1 from duc_ipqc_tieuchuan_de_xuat c where c.ma_sp=p.ma_sp and c.trang_thai<>'da_duyet')limit 1;
 if product is null then raise exception 'Need staging product without pending standards';end if;
 foreach kind in array array['btk','checklist']loop
  foreach cd in array array['duc','gia_cong']loop
   perform set_config('request.jwt.claim.sub',adm::text,true);
   day:=(now()at time zone'Asia/Ho_Chi_Minh')::date+1;
   p:=jsonb_build_object('phien_ban','ADMIN-'||token,'ngay_hieu_luc',day,'so_mau',1,'noi_dung_sua_doi','Rollback admin approval',
    'muc',jsonb_build_array(jsonb_build_object('muc_no',1,'hang_muc','Test diameter','kieu','so','danh_nghia',20,'dung_sai_tren',0.05,'dung_sai_duoi',0.05)));
   if kind='btk' then r:=ipqc_btk_luu(product,p,'Spoofed name',cd);
   else r:=ipqc_tc_luu_checklist(product,'["Rollback item"]'::jsonb,null,'Rollback admin approval','Spoofed name',cd);end if;
   if not coalesce((r->>'ok')::boolean,false)then raise exception '%',r;end if;
   id1:=(r->>'id')::bigint;
   -- Other roles cannot bypass the review stage.
   perform set_config('request.jwt.claim.sub',qc::text,true);
   r:=ipqc_tc_duyet(kind,id1,'phe_duyet',null,'Spoofed name');if(r->>'ok')::boolean then raise exception 'QC bypassed review';end if;
   perform set_config('request.jwt.claim.sub',manager::text,true);
   r:=ipqc_tc_duyet(kind,id1,'phe_duyet',null,'Spoofed name');if(r->>'ok')::boolean then raise exception 'Manager bypassed approval';end if;
   perform set_config('request.jwt.claim.sub',director::text,true);
   r:=ipqc_tc_duyet(kind,id1,'phe_duyet',null,'Spoofed name');if(r->>'ok')::boolean then raise exception 'Director bypassed review';end if;
   perform set_config('request.jwt.claim.sub',adm::text,true);
   r:=ipqc_tc_duyet(kind,id1,'phe_duyet',null,'Spoofed name');
   if(r->>'ok')::boolean then raise exception 'Admin skipped the existing review step';end if;
   -- Same admin can return at either stage, review and approve with the existing actions.
   r:=ipqc_tc_duyet(kind,id1,'tra_lai','Rollback return at review','Spoofed name');
   if not(r->>'ok')::boolean then raise exception 'Admin cannot return at review: %',r;end if;
   if kind='btk' then r:=ipqc_btk_luu(product,p,'Spoofed name',cd);
   else r:=ipqc_tc_luu_checklist(product,'["Rollback item"]'::jsonb,null,'Rollback resubmit','Spoofed name',cd);end if;
   if not(r->>'ok')::boolean or(r->>'id')::bigint<>id1 then raise exception 'Resubmit changed draft ID';end if;
   r:=ipqc_tc_duyet(kind,id1,'kiem_tra',null,'Spoofed name');
   if not(r->>'ok')::boolean then raise exception 'Admin cannot review: %',r;end if;
   r:=ipqc_tc_duyet(kind,id1,'tra_lai','Rollback return at approval','Spoofed name');
   if not(r->>'ok')::boolean then raise exception 'Admin cannot return at approval: %',r;end if;
   if kind='btk' then r:=ipqc_btk_luu(product,p,'Spoofed name',cd);
   else r:=ipqc_tc_luu_checklist(product,'["Rollback item"]'::jsonb,null,'Rollback resubmit','Spoofed name',cd);end if;
   if not(r->>'ok')::boolean then raise exception 'Second resubmit failed';end if;
   r:=ipqc_tc_duyet(kind,id1,'kiem_tra',null,'Spoofed name');
   if not(r->>'ok')::boolean then raise exception 'Admin second review failed';end if;
   r:=ipqc_tc_duyet(kind,id1,'phe_duyet',null,'Spoofed name');
   if not coalesce((r->>'ok')::boolean,false)or r->>'trang_thai'<>'da_duyet' then raise exception 'Admin final approval failed: %',r;end if;
   if kind='btk' then select to_jsonb(b)into snapshot from ipqc_btk b where id=id1;
   else select to_jsonb(c)into snapshot from duc_ipqc_tieuchuan_de_xuat c where id=id1;
    if not exists(select 1 from duc_ipqc_tieuchuan where ma_sp=product and cong_doan=cd)then raise exception 'Checklist not published';end if;
   end if;
   if(snapshot->>'nguoi_phe_duyet_uid')::uuid is distinct from adm or snapshot->>'nguoi_phe_duyet'='Spoofed name'
    or snapshot->>'phe_duyet_luc' is null then raise exception 'Approval identity/time not recorded';end if;
   if(snapshot->>'nguoi_kiem_tra_uid')::uuid is distinct from adm or snapshot->>'kiem_tra_luc' is null then raise exception 'Actual admin reviewer missing';end if;
   if kind='btk'and(snapshot->>'ngay_hieu_luc')::date<>day then raise exception 'Future effective date changed';end if;
   r:=ipqc_tc_duyet(kind,id1,'phe_duyet',null,'Spoofed name');if(r->>'ok')::boolean then raise exception 'Published standard reapproved';end if;
   -- Admin can also approve after a real QC manager review, retaining the reviewer.
   if kind='btk' then r:=ipqc_btk_luu(product,p||jsonb_build_object('phien_ban','ADMIN2-'||token),'Spoofed name',cd);
   else r:=ipqc_tc_luu_checklist(product,'["Rollback revised item"]'::jsonb,null,'Rollback second approval','Spoofed name',cd);end if;
   if not coalesce((r->>'ok')::boolean,false)then raise exception '%',r;end if;
   id2:=(r->>'id')::bigint;
   perform set_config('request.jwt.claim.sub',manager::text,true);
   r:=ipqc_tc_duyet(kind,id2,'kiem_tra',null,'Spoofed name');if not(r->>'ok')::boolean then raise exception 'Normal manager review failed';end if;
   perform set_config('request.jwt.claim.sub',adm::text,true);
   r:=ipqc_tc_duyet(kind,id2,'phe_duyet',null,'Spoofed name');if not(r->>'ok')::boolean then raise exception 'Admin final approval failed';end if;
   if kind='btk' then select to_jsonb(b)into snapshot from ipqc_btk b where id=id2;
   else select to_jsonb(c)into snapshot from duc_ipqc_tieuchuan_de_xuat c where id=id2;end if;
   if(snapshot->>'nguoi_kiem_tra_uid')::uuid is distinct from manager then raise exception 'Real reviewer lost';end if;
  end loop;
 end loop;
 if has_function_privilege('anon','public.ipqc_tc_duyet(text,bigint,text,text,text)','execute')then raise exception 'Anonymous approval exposed';end if;
end $$;
select 'PASS admin review/approve/return at every existing stage for dimensional standards and checklists in casting/machining; state order and other roles preserved; actual actor/history/effective date retained' as result;
rollback;
