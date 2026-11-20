-- Append inside migration transaction; no fixture survives ROLLBACK.
do $$
declare n text; g text; j jsonb; u uuid; account text; al text; zn text; r jsonb; before_lot jsonb; legacy bigint;
begin
  select ma_nvl into n from nvl_materials where nhom_vat_tu <> 'kim_loai' limit 1;
  if n is null then raise exception 'Missing non-metal staging fixture'; end if;
  select nhom into g from iqc_phan_loai_tu_danh_muc(n);
  if g is distinct from 'khac' then raise exception 'Non-metal classification incorrect'; end if;
  select ma_nvl into n from nvl_materials where ma_mac in (select ma_mac from vat_lieu_mac where loai_kim_loai='nhom') limit 1;
  if n is null or (select nhom from iqc_phan_loai_tu_danh_muc(n)) is distinct from 'nhom' then raise exception 'Aluminium classification incorrect'; end if;
  select ma_nvl into n from nvl_materials where ma_mac in (select ma_mac from vat_lieu_mac where loai_kim_loai='kem') limit 1;
  if n is null or (select nhom from iqc_phan_loai_tu_danh_muc(n)) is distinct from 'kem' then raise exception 'Zinc classification incorrect'; end if;
  perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  j := iqc_nvl_danh_muc();
  if jsonb_array_length(j->'nvl') <> (select count(*) from nvl_materials) or
     jsonb_array_length(j->'san_pham') <> (select count(*) from master_products) then raise exception 'Catalog count mismatch'; end if;
  if not exists(select 1 from jsonb_array_elements(j->'nvl') x where x->>'code'=n and x ? 'supplierCode') then raise exception 'Supplier code missing'; end if;
  select user_id,username into u,account from user_roles where role='admin' limit 1;
  if u is null then raise exception 'Missing staging test account'; end if;
  perform set_config('request.jwt.claim.sub',u::text,true);
  select ma_mac into al from vat_lieu_mac where loai_kim_loai='nhom' limit 1;
  select ma_mac into zn from vat_lieu_mac where loai_kim_loai='kem' limit 1;
  select id,to_jsonb(l) into legacy,before_lot from iqc_lots l order by id limit 1;
  insert into nvl_materials(ma_nvl,ten_nvl,nhom_vat_tu,ma_mac,nha_cung_cap,ma_nvl_ncc)
    values ('IQC-CATALOG-ROLLBACK', 'NVL test', 'kim_loai', al, 'NCC test', 'SUPPLIER-TEST');
  insert into master_products(ma_sp,ten_sp) values ('IQC-CATALOG-PRODUCT-ROLLBACK','Sản phẩm test');
  j := iqc_nvl_danh_muc();
  if not exists(select 1 from jsonb_array_elements(j->'nvl') x where x->>'code'='IQC-CATALOG-ROLLBACK' and x->>'supplierCode'='SUPPLIER-TEST' and x->>'group'='nhom') or
     not exists(select 1 from jsonb_array_elements(j->'san_pham') x where x->>'code'='IQC-CATALOG-PRODUCT-ROLLBACK') then raise exception 'New codes missing'; end if;
  r:=iqc_luu_hoa_hoc(null,jsonb_build_object('request_id',gen_random_uuid(),'ma_nvl','IQC-CATALOG-ROLLBACK','ngay_kiem',current_date,'ca_kiem','Ca ngày','lot_no','TEST-ROLLBACK','inspector',account,'results','{}'::jsonb,'xac_nhan',true));
  if r->>'result' is distinct from '' or not exists(select 1 from iqc_lots where id=(r->>'id')::bigint and product_name='NVL test') then raise exception 'Chemical save/reopen or missing-standard outcome incorrect'; end if;
  update nvl_materials set ten_nvl='NVL mới',ma_mac=zn,nha_cung_cap='NCC mới' where ma_nvl='IQC-CATALOG-ROLLBACK';
  j:=iqc_nvl_danh_muc();
  if not exists(select 1 from jsonb_array_elements(j->'nvl') x where x->>'code'='IQC-CATALOG-ROLLBACK' and x->>'name'='NVL mới' and x->>'supplier'='NCC mới' and x->>'group'='kem') then raise exception 'Catalog update not visible'; end if;
  update nvl_materials set nhom_vat_tu='linh_kien',ma_mac=null where ma_nvl='IQC-CATALOG-ROLLBACK';
  insert into iqc_lots(doi_tuong,ma_nvl,product_code,supplier,pham_vi) values ('nvl','IQC-CATALOG-ROLLBACK','IQC-CATALOG-ROLLBACK','NCC mới','Linh kiện đầu vào');
  if not exists(select 1 from iqc_lots where ma_nvl='IQC-CATALOG-ROLLBACK' and phuong_thuc='ngoai_quan') then raise exception 'Visual material blocked'; end if;
  update nvl_materials set nhom_vat_tu='kim_loai',ma_mac=null where ma_nvl='IQC-CATALOG-ROLLBACK';
  if (select nhom from iqc_phan_loai_tu_danh_muc('IQC-CATALOG-ROLLBACK')) is distinct from 'khac' then raise exception 'Ungraded material blocked'; end if;
  if legacy is not null and (select to_jsonb(l) from iqc_lots l where id=legacy) is distinct from before_lot then raise exception 'Historical report changed'; end if;
end $$;
