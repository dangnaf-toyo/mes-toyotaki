-- Kiểm thử STAGING trong transaction tự rollback, không lưu dữ liệu thử.
begin;
do $$
declare u uuid;caseid text;ds uuid;d ncp_doi_sach%rowtype;stamp timestamptz;created timestamptz;
begin
 select user_id into u from user_roles where role='admin' limit 1;
 if u is null then raise exception 'Staging test needs an admin account';end if;
 perform set_config('request.jwt.claim.sub',u::text,true);
 select id_ncp,ngay_tao into caseid,created from duc_ncp order by id_ncp limit 1;
 if caseid is null then raise exception 'Staging test needs a pre-existing NCP';end if;
 update duc_ncp set ngay_tao='1999-01-01',han_tra_loi_doi_sach=current_date+4 where id_ncp=caseid;
 if (select ngay_tao from duc_ncp where id_ncp=caseid)is distinct from created then raise exception 'Creation timestamp changed on edit';end if;
 ds:=ncp_luu_doi_sach(null,jsonb_build_object('id_ncp',caseid,'loai','noi_bo','van_de','Rollback verification'));
 if (select trang_thai from ncp_doi_sach_theo_doi where id=ds)<>'chua_tra_loi' then raise exception 'No deadline should be unanswered';end if;
 select * into d from ncp_doi_sach where id=ds;
 perform ncp_luu_doi_sach(ds,to_jsonb(d)||jsonb_build_object('han_tra_loi',clock_timestamp()-interval '1 hour'));
 if (select trang_thai from ncp_doi_sach_theo_doi where id=ds)<>'qua_han' then raise exception 'Past deadline should be overdue';end if;
 select * into d from ncp_doi_sach where id=ds;
 perform ncp_luu_doi_sach(ds,to_jsonb(d)||jsonb_build_object('loai','khach_hang','noi_dung_tra_loi','Actual rollback test response'));
 select tra_loi_luc into stamp from ncp_doi_sach where id=ds;
 if stamp is null or not (select tra_loi_muon from ncp_doi_sach_theo_doi where id=ds) then raise exception 'Missing actual late response timestamp';end if;
 if (select trang_thai from ncp_doi_sach_theo_doi where id=ds)<>'da_tra_loi' then raise exception 'Answered must override overdue';end if;
 if (select count(*) from ncp_doi_sach_lich_su where id_doi_sach=ds)<3 then raise exception 'Missing change history';end if;
 if not exists(select 1 from ncp_lich_su_han where id_ncp=caseid and nguoi_uid=u)then raise exception 'Missing deadline audit';end if;
end $$;
select 'PASS immutable creation, optional deadline, both types, yellow/red/green, server response time, late flag and audit history' as result;
rollback;
