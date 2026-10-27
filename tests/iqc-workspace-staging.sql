begin;
create temp table iqc_before_test as select count(*) n, md5(coalesce(string_agg(md5(to_jsonb(l)::text),'' order by id),'')) checksum from public.iqc_lots l;
select set_config('request.jwt.claim.sub',(select user_id::text from public.user_roles where role='admin' limit 1),true);
set local role authenticated;
do $$
declare v_id bigint := -927102701; v_pham_vi text; v_ncc text; v_row public.iqc_lots; v_count integer;
begin
  if auth.uid() is null then raise exception 'Missing test auth context'; end if;
  if exists(select 1 from public.iqc_lots where id=v_id) then raise exception 'Test id already exists'; end if;
  foreach v_pham_vi in array array['Bán thành phẩm','Linh kiện đầu vào','Mạ','In','Anode','Đúc','Thành phẩm'] loop
    insert into public.iqc_lots(id,supplier,pham_vi,lot_no,lot_qty,nguoi_kiem_id,nguoi_kiem_ten,inspector,received_at,status)
    values(v_id,'BRV',v_pham_vi,'IQC-ROLLBACK-TEST',50,'TEST-SX','Người kiểm SX thử','TEST-SX_Người kiểm SX thử','2026-10-27T02:00:00Z','Đang chờ kiểm');
    select * into v_row from public.iqc_lots where id=v_id;
    if v_row.pham_vi<>v_pham_vi or v_row.nguoi_kiem_id<>'TEST-SX' or v_row.nguoi_kiem_ten<>'Người kiểm SX thử' then raise exception 'Persistence mismatch'; end if;
    v_id:=v_id-1;
  end loop;
  foreach v_ncc in array array['BRV','HANIN','VIỆT PHÁP','ASAHI','MINGANN'] loop
    update public.iqc_lots set supplier=v_ncc,pham_vi='In' where id=-927102701;
    select * into v_row from public.iqc_lots where id=-927102701;
    if v_row.supplier<>v_ncc then raise exception 'Supplier mismatch'; end if;
  end loop;
  begin
    update public.iqc_lots set pham_vi='INVALID' where id=-927102701;
    raise exception using errcode='ZX001',message='Invalid scope accepted';
  exception when sqlstate 'P0001' then null; end;
  begin
    update public.iqc_lots set supplier='INVALID' where id=-927102701;
    raise exception using errcode='ZX001',message='Invalid supplier accepted';
  exception when sqlstate 'P0001' then null; end;
  update public.iqc_lots set status='Đã kiểm tra',result='NG',completed_at='2026-10-27T03:00:00Z' where id=-927102701;
  select count(*) into v_count from public.iqc_lots where id between -927102707 and -927102701 and pham_vi is not null;
  if v_count<>7 then raise exception 'Dashboard source count mismatch'; end if;
end $$;
reset role;
select 'PASS staging authenticated insert/read/update, 7 scopes, 5 suppliers, identity, invalid-value rejection, completion and dashboard source; transaction rolled back' as result;
rollback;
