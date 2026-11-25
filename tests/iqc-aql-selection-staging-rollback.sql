-- Synthetic values exercise mechanics only; not a standard table. Always ROLLBACK.
do $$
declare u uuid; ordinary uuid; name text; product text; lot bigint; result jsonb; ts timestamptz; draft uuid; failed boolean;
begin
 select user_id,username into u,name from user_roles where role='admin' limit 1;
 select ma_sp into product from master_products order by ma_sp limit 1;
 if u is null or product is null then raise exception 'Missing test fixture'; end if;
 perform set_config('request.jwt.claim.sub',u::text,true);
 result:=iqc_luu_lan_kiem(null,jsonb_build_object('supplier','BRV','product_code',product,'product_name','fixture','lot_no','TEST-AQL-CHOICE','lot_qty',1000,'pham_vi','Đúc','inspection_type','Kiểm tra AQL'),null,gen_random_uuid());lot:=(result->>'lot_id')::bigint;
 select updated_at into ts from iqc_lots where id=lot;
 perform iqc_chon_aql(lot,'III','0.25','Normal',null,ts);
 if iqc_tra_ke_hoach_aql(lot) is not null then raise exception 'Missing table returned plan'; end if;
 perform iqc_luu_cau_hinh_aql('choice-fixture','v1','fixture only','II','1.0','Normal','{"lotRanges":[{"min":1,"max":null,"code":"A"}],"plans":{"A":{"sample":10,"ac":0,"re":1}}}'::jsonb,array[product],true);
 perform iqc_luu_cau_hinh_aql('choice-fixture','v1','fixture only','III','0.25','Normal','{"lotRanges":[{"min":1,"max":null,"code":"B"}],"plans":{"B":{"sample":20,"ac":1,"re":2}}}'::jsonb,array[product],true);
 if (select count(*) from iqc_aql_cau_hinh where nhom='choice-fixture' and da_duyet)<>2 or (iqc_tra_ke_hoach_aql(lot)->>'ma_chu')<>'B' then raise exception 'Multiple selectable plans failed'; end if;
 select updated_at into ts from iqc_lots where id=lot;
 perform iqc_duyet_ke_hoach_aql(lot,20,1,2,'fixture only',ts);
 draft:=gen_random_uuid();perform iqc_bat_dau_lan_kiem(draft,lot);
 perform iqc_luu_lan_kiem(lot,null,jsonb_build_object('bat_dau_id',draft,'nguoi_kiem',name,'so_kiem',10,'so_ok',9,'so_ng',1,'loi','[]'::jsonb),gen_random_uuid());
 select updated_at into ts from iqc_lots where id=lot;
 select user_id into ordinary from user_roles where role='nhan_vien_oqc' and user_id<>u limit 1;
 if ordinary is null then raise exception 'Missing test user for role check'; end if;
 update user_roles set role='iqc' where user_id=ordinary;
 if ordinary is not null then
  perform set_config('request.jwt.claim.sub',ordinary::text,true);
  failed:=false;begin perform iqc_chon_aql(lot,'II','1.0','Normal','reason',ts);exception when others then failed:=true;end;
  if not failed then raise exception 'Non-manager changed an inspected plan'; end if;
  perform set_config('request.jwt.claim.sub',u::text,true);
 end if;
 failed:=false;begin perform iqc_chon_aql(lot,'II','1.0','Normal',null,ts);exception when others then failed:=true;end;
 if not failed then raise exception 'Plan changed without reason'; end if;
 perform iqc_chon_aql(lot,'II','1.0','Normal','Kiểm thử thay đổi',ts);
 if exists(select 1 from iqc_aql_ke_hoach where lot_id=lot) or not exists(select 1 from iqc_lich_su where loai='chon_aql' and khoa=lot::text and du_lieu_moi->>'ly_do'='Kiểm thử thay đổi') or (iqc_tra_ke_hoach_aql(lot)->>'ma_chu')<>'A' then raise exception 'Selection change or audit failed'; end if;
end $$;
