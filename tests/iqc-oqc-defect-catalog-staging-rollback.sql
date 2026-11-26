-- STAGING only. Creates a synthetic LOT in this transaction and rolls it back.
begin;
do $$
declare u uuid; inspector_name text; product text; lot_id bigint; round_id bigint; request_id uuid; response jsonb; stamp timestamptz;
begin
 select user_id,username into u,inspector_name from public.user_roles where role='admin' limit 1;
 select ma_sp into product from public.master_products order by ma_sp limit 1;
 if u is null or product is null then raise exception 'Missing staging test fixture'; end if;
 perform set_config('request.jwt.claim.sub',u::text,true);
 response:=public.iqc_luu_lan_kiem(null,jsonb_build_object('supplier','BRV','product_code',product,'product_name','Fixture','lot_no','IQC-OQC-CATALOG-ROLLBACK','lot_qty',10,'pham_vi','Đúc','inspection_type','Kiểm tra 100%'),null,gen_random_uuid());
 lot_id:=(response->>'lot_id')::bigint;request_id:=gen_random_uuid();perform public.iqc_bat_dau_lan_kiem(request_id,lot_id);
 response:=public.iqc_luu_lan_kiem(lot_id,null,jsonb_build_object('bat_dau_id',request_id,'nguoi_kiem',inspector_name,'so_kiem',10,'so_ok',9,'so_ng',1,'loi',jsonb_build_array(jsonb_build_object('ma_loi','D01','ten_loi','Tên snapshot','nhom_loi','NG ngoại quan','chi_tiet','Mặt A','so_luong',1))),gen_random_uuid());
 round_id:=(response->>'lan_kiem_id')::bigint;
 if not exists(select 1 from public.iqc_lan_kiem_loi where lan_kiem_id=round_id and ma_loi='D01' and ten_loi='Tên snapshot' and chi_tiet='Mặt A' and so_luong=1) then raise exception 'Catalog code snapshot was not saved'; end if;
 select sua_luc into stamp from public.iqc_lan_kiem where id=round_id;
 perform public.iqc_sua_lan_kiem(round_id,jsonb_build_object('nguoi_kiem',inspector_name,'so_kiem',10,'so_ok',9,'so_ng',1,'loi',jsonb_build_array(jsonb_build_object('ma_loi','D02','ten_loi','Tên mới','nhom_loi','NG khác','chi_tiet','Mặt B','so_luong',1))),stamp,gen_random_uuid());
 if exists(select 1 from public.iqc_lan_kiem_loi where lan_kiem_id=round_id and ma_loi='D01') or not exists(select 1 from public.iqc_lan_kiem_loi where lan_kiem_id=round_id and ma_loi='D02' and ten_loi='Tên mới') then raise exception 'Edit did not replace only this round defects'; end if;
end $$;
rollback;
