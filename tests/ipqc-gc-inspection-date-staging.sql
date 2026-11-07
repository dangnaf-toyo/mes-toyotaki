-- STAGING only: all fixtures and measurements are rolled back.
begin;
do $$
declare actor uuid;product text;machine text;a bigint;b bigint;c bigint;other_step bigint;draft bigint;
 ref jsonb;payload jsonb;measurement uuid;legacy_client uuid;prior_updated timestamptz;prior_created timestamptz;failed boolean;
 before_cast text;before_values text;before_standards text;before_features text;req uuid:=gen_random_uuid();
begin
 select user_id into actor from user_roles where role='admin'order by user_id limit 1;
 select ma_sp into product from master_products p where not exists(select 1 from ipqc_btk b where b.ma_sp=p.ma_sp and b.cong_doan='gia_cong')order by ma_sp limit 1;
 select ma_may into machine from master_machines where bo_phan='Gia công - Sơn'order by ma_may limit 1;
 if actor is null or product is null or machine is null then raise exception 'Missing isolated staging prerequisites';end if;
 select md5(coalesce(jsonb_agg(to_jsonb(l)order by id_checkpoint)::text,''))into before_cast from ipqc_do_lan l;
 select md5(coalesce(jsonb_agg(to_jsonb(k)order by id_checkpoint,muc_no,mau)::text,''))into before_values from ipqc_do_kq k;
 select md5(coalesce(jsonb_agg(to_jsonb(x)order by id)::text,''))into before_standards from ipqc_btk x;
 select md5(coalesce(jsonb_agg(to_jsonb(x)order by id)::text,''))into before_features from ipqc_btk_muc x;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into ipqc_btk(ma_sp,cong_doan,phien_ban,ngay_hieu_luc,so_mau,dang_dung,trang_thai,buoc_gia_cong)
 values(product,'gia_cong','DATE-A-'||req,'2026-01-01',1,false,'da_duyet',null)returning id into a;
 insert into ipqc_btk(ma_sp,cong_doan,phien_ban,ngay_hieu_luc,so_mau,dang_dung,trang_thai,buoc_gia_cong)
 values(product,'gia_cong','DATE-B-'||req,'2026-02-01',1,true,'da_duyet',null)returning id into b;
 insert into ipqc_btk_muc(id_btk,muc_no,ma_dac_tinh,hang_muc,kieu,danh_nghia,dung_sai_tren,dung_sai_duoi,lsl,usl,don_vi,co_mau,dung_sai_co_dau)
 values(a,1,'D1','Diameter','so',20,0.05,-0.05,19.95,20.05,'mm',1,true),
       (b,1,'D1','Diameter','so',30,0.1,-0.1,29.9,30.1,'mm',1,true);
 ref:=ipqc_gc_tieu_chuan_theo_ngay(product,'2025-12-31');
 if ref->>'status'<>'none' then raise exception 'Selected a standard before it was effective';end if;
 ref:=ipqc_gc_tieu_chuan_theo_ngay(product,'2026-01-15');
 if (ref->'btk'->>'id')::bigint<>a then raise exception 'Historical inactive revision A not resolved';end if;
 ref:=ipqc_gc_tieu_chuan_theo_ngay(product,'2026-02-01');
 if (ref->'btk'->>'id')::bigint<>b then raise exception 'Effective-date boundary did not select B';end if;
 payload:=jsonb_build_object('request_id',req,'ma_sp',product,'id_btk',a,'ngay_kiem','2026-01-15','ma_may',machine,'ca','Ca ngày',
 'kq',jsonb_build_array(jsonb_build_object('muc_no',1,'mau',1,'gia_tri',20.01)));
 measurement:=ipqc_gc_luu_do(payload);
 if (select ngay_kiem from ipqc_gc_lan where id=measurement)<>'2026-01-15'::date
 or (select id_btk from ipqc_gc_lan where id=measurement)<>a
 or (select ma_lo is not null or buoc_gia_cong is not null from ipqc_gc_lan where id=measurement)
 then raise exception 'Inspection date, version or optional lot/step not stored correctly';end if;
 if not(select dat from ipqc_gc_lan where id=measurement)then raise exception 'Historical result used the new revision limits';end if;
 if (select(thoi_diem at time zone'Asia/Ho_Chi_Minh')::date from ipqc_gc_lan where id=measurement)='2026-01-15'::date
 then raise exception 'Creation time was overwritten by inspection date';end if;
 if not exists(select 1 from ipqc_lan_tong_hop where id=measurement::text and ngay_kiem between '2026-01-15'and'2026-01-15')
 then raise exception 'Dashboard does not filter by actual inspection date';end if;
 select thoi_diem,cap_nhat_luc into prior_created,prior_updated from ipqc_gc_lan where id=measurement;
 if ipqc_gc_luu_do(payload)<>measurement then raise exception 'Retry duplicated a measurement';end if;
 if (select cap_nhat_luc from ipqc_gc_lan where id=measurement)is distinct from prior_updated then raise exception 'Retry changed update timestamp';end if;
 update ipqc_gc_lan set ma_lo='AUDIT-ONLY'where id=measurement;
 if (select thoi_diem from ipqc_gc_lan where id=measurement)is distinct from prior_created
 or(select cap_nhat_luc from ipqc_gc_lan where id=measurement)<prior_updated then raise exception 'Creation/update audit not preserved';end if;
 failed:=false;begin perform ipqc_gc_luu_do(payload||jsonb_build_object('ngay_kiem','2026-01-16'));exception when others then failed:=true;end;
 if not failed then raise exception 'Changed inspection day reused the same request ID';end if;
 failed:=false;begin perform ipqc_gc_luu_do(payload||jsonb_build_object('request_id',gen_random_uuid(),'ngay_kiem','2026-02-15'));exception when others then failed:=true;end;
 if not failed then raise exception 'Client selected the obsolete revision for February';end if;
 -- Simulate a legacy row with no separate inspection date. VN midnight is preserved.
 update ipqc_gc_lan set ngay_kiem=null,thoi_diem='2025-12-31T18:00:00Z'where id=measurement;
 if (select ngay_kiem from ipqc_lan_tong_hop where id=measurement::text)<>'2026-01-01'::date then raise exception 'Legacy VN date fallback incorrect';end if;
 insert into ipqc_btk(ma_sp,cong_doan,phien_ban,ngay_hieu_luc,so_mau,dang_dung,trang_thai,buoc_gia_cong)
 values(product,'gia_cong','DATE-C-'||req,'2026-02-01',1,false,'da_duyet',null)returning id into c;
 if ipqc_gc_tieu_chuan_theo_ngay(product,'2026-02-15')->>'status'<>'ambiguous' then raise exception 'Same-day revisions were silently selected';end if;
 failed:=false;begin perform ipqc_gc_luu_do(payload||jsonb_build_object('request_id',gen_random_uuid(),'id_btk',b,'ngay_kiem','2026-02-15'));exception when others then failed:=true;end;
 if not failed then raise exception 'Ambiguous standards accepted by writer';end if;
 update ipqc_btk set ngay_hieu_luc='2099-01-01'where id=c;
 insert into ipqc_btk(ma_sp,cong_doan,phien_ban,ngay_hieu_luc,so_mau,dang_dung,trang_thai,buoc_gia_cong)
 values(product,'gia_cong','DATE-STEP-'||req,'2026-01-01',1,true,'da_duyet','Other step')returning id into other_step;
 if ipqc_gc_tieu_chuan_theo_ngay(product,'2026-01-15')->>'status'<>'ambiguous' then raise exception 'Overlapping steps selected arbitrarily';end if;
 update ipqc_btk set trang_thai='tra_lai',dang_dung=false where id=other_step;
 insert into ipqc_btk(ma_sp,cong_doan,phien_ban,ngay_hieu_luc,so_mau,dang_dung,trang_thai,buoc_gia_cong)
 values(product,'gia_cong','DATE-DRAFT-'||req,'2026-03-01',1,false,'cho_kiem_tra',null)returning id into draft;
 if (ipqc_gc_tieu_chuan_theo_ngay(product,'2026-03-15')->'btk'->>'id')::bigint<>b then raise exception 'Pending standard selected';end if;
 legacy_client:=ipqc_gc_luu_do((payload-'ngay_kiem')||jsonb_build_object('request_id',gen_random_uuid(),'id_btk',b,'ma_lo','LEGACY-CLIENT',
  'kq',jsonb_build_array(jsonb_build_object('muc_no',1,'mau',1,'gia_tri',30.01))));
 if (select ngay_kiem from ipqc_gc_lan where id=legacy_client)<>(clock_timestamp()at time zone'Asia/Ho_Chi_Minh')::date
 or(select ma_lo from ipqc_gc_lan where id=legacy_client)<>'LEGACY-CLIENT'then raise exception 'Legacy client compatibility failed';end if;
 if has_function_privilege('authenticated','public.ipqc_gc_luu_do_t217(jsonb)','EXECUTE')or has_function_privilege('anon','public.ipqc_gc_tieu_chuan_theo_ngay(text,date)','EXECUTE')then raise exception 'Function permissions widened';end if;
 perform set_config('request.jwt.claim.sub','',true);failed:=false;
 begin perform ipqc_gc_tieu_chuan_theo_ngay(product,'2026-01-15');exception when others then failed:=true;end;
 if not failed then raise exception 'Unauthenticated standard lookup accepted';end if;
 if (select md5(coalesce(jsonb_agg(to_jsonb(x)order by id)::text,''))from ipqc_btk x where id not in(a,b,c,other_step,draft))is distinct from before_standards
 or(select md5(coalesce(jsonb_agg(to_jsonb(x)order by id)::text,''))from ipqc_btk_muc x where id_btk not in(a,b))is distinct from before_features
 then raise exception 'Existing standards/features changed';end if;
 if(select md5(coalesce(jsonb_agg(to_jsonb(l)order by id_checkpoint)::text,''))from ipqc_do_lan l)is distinct from before_cast
 or(select md5(coalesce(jsonb_agg(to_jsonb(k)order by id_checkpoint,muc_no,mau)::text,''))from ipqc_do_kq k)is distinct from before_values
 then raise exception 'Casting data changed';end if;
end $$;
select 'PASS inspection-date persistence/filtering, historic revision bounds, boundaries/ambiguity, optional lot/step, audit/retry, legacy date, permissions and unchanged standards/casting' as result;
rollback;
