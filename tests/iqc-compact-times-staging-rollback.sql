-- Synthetic IQC times; transaction must be rolled back.
do $$
declare u uuid; username text; product text; lot bigint; rid bigint; token uuid; res jsonb; start_at timestamptz:=date_trunc('second',clock_timestamp()-interval '2 hours'); finish timestamptz:=date_trunc('second',clock_timestamp()-interval '1 hour'); stamp timestamptz; failed boolean; payload jsonb;
begin
 select user_id,user_roles.username into u,username from user_roles where role='admin' limit 1;select ma_sp into product from master_products order by ma_sp limit 1;
 if u is null or product is null then raise exception 'Missing fixture'; end if;perform set_config('request.jwt.claim.sub',u::text,true);
 res:=iqc_luu_lan_kiem(null,jsonb_build_object('supplier','BRV','product_code',product,'product_name','fixture','lot_no','IQC-COMPACT-TIME','lot_qty',100,'pham_vi','Đúc','inspection_type','Kiểm tra 100%'),null,gen_random_uuid());lot:=(res->>'lot_id')::bigint;
 token:=gen_random_uuid();perform iqc_bat_dau_lan_kiem(token,lot);
 payload:=jsonb_build_object('bat_dau_id',token,'bat_dau_luc',start_at,'nguoi_kiem',username,'so_kiem',40,'so_ok',39,'so_ng',1,'loi','[]'::jsonb);
 failed:=false;begin perform iqc_luu_lan_kiem(lot,null,payload||jsonb_build_object('ket_thuc_luc',finish),gen_random_uuid());exception when others then failed:=true;end;
 if not failed then raise exception 'Partial LOT accepted explicit completion'; end if;
 res:=iqc_luu_lan_kiem(lot,null,payload,gen_random_uuid());rid:=(res->>'lan_kiem_id')::bigint;
 if (select bat_dau_luc from iqc_lan_kiem where id=rid)<>start_at then raise exception 'Custom start not saved'; end if;
 token:=gen_random_uuid();perform iqc_bat_dau_lan_kiem(token,lot);
 payload:=jsonb_build_object('bat_dau_id',token,'bat_dau_luc',finish-interval '1 minute','ket_thuc_luc',finish,'nguoi_kiem',username,'so_kiem',60,'so_ok',60,'so_ng',0,'loi','[]'::jsonb);
 res:=iqc_luu_lan_kiem(lot,null,payload,gen_random_uuid());
 if (select ket_thuc_luc from iqc_lan_kiem where id=(res->>'lan_kiem_id')::bigint)<>finish then raise exception 'Completion not saved'; end if;
 if (select bat_dau_luc from iqc_lan_kiem where id=rid)<>start_at then raise exception 'Earlier start overwritten'; end if;
 select sua_luc into stamp from iqc_lan_kiem where id=rid;payload:=jsonb_build_object('bat_dau_luc',start_at-interval '1 minute','ly_do_thoi_gian','Đối chiếu thời gian','nguoi_kiem',username,'so_kiem',40,'so_ok',39,'so_ng',1,'loi','[]'::jsonb);
 perform iqc_sua_lan_kiem(rid,payload,stamp,gen_random_uuid());
 if not exists(select 1 from iqc_lich_su where loai='sua_lan_kiem' and khoa=rid::text and (du_lieu_cu->>'bat_dau_luc')::timestamptz=start_at) then raise exception 'Time edit audit missing'; end if;
 perform iqc_luu_cau_hinh_aql('compact-fixture','v1','TEST ONLY','II','1.0','Normal','{"lotRanges":[{"min":1,"max":null,"code":"A"}],"plans":{"A":{"sample":10,"ac":1,"re":2}}}'::jsonb,array[product],true);
 res:=iqc_luu_lan_kiem(null,jsonb_build_object('supplier','BRV','product_code',product,'product_name','fixture','lot_no','IQC-COMPACT-AQL','lot_qty',1000,'pham_vi','Đúc','inspection_type','Kiểm tra AQL'),null,gen_random_uuid());lot:=(res->>'lot_id')::bigint;
 select updated_at into stamp from iqc_lots where id=lot;perform iqc_chon_aql(lot,'II','1.0','Normal',null,stamp);
 select updated_at into stamp from iqc_lots where id=lot;perform iqc_duyet_ke_hoach_aql(lot,10,1,2,'TEST ONLY',stamp);
 token:=gen_random_uuid();perform iqc_bat_dau_lan_kiem(token,lot);
 payload:=jsonb_build_object('bat_dau_id',token,'bat_dau_luc',start_at,'ket_thuc_luc',finish,'nguoi_kiem',username,'so_kiem',10,'so_ok',9,'so_ng',1,'loi','[]'::jsonb);
 res:=iqc_luu_lan_kiem(lot,null,payload,gen_random_uuid());if (select ket_thuc_luc from iqc_lan_kiem where id=(res->>'lan_kiem_id')::bigint)<>finish then raise exception 'AQL completion timestamp failed'; end if;
 select updated_at into stamp from iqc_lots where id=lot;perform iqc_phan_quyet_lot(lot,'OK',stamp,'TEST ONLY');
 if (select iqc_ket_luan from iqc_lots where id=lot)<>'OK' then raise exception 'AQL disposition changed'; end if;
end $$;
