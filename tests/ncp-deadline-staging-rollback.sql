-- STAGING only. All test changes and generated notifications are rolled back.
begin;
do $$
declare
 r duc_ncp%rowtype; u uuid; ten text; n integer; sent integer;
 today date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
 select * into r from duc_ncp order by id_ncp limit 1;
 if r.id_ncp is null then raise exception 'Need an existing staging NCP for rollback test'; end if;
 select user_id,coalesce(username,email) into u,ten from user_roles order by user_id limit 1;
 if u is null then raise exception 'Need a staging user for notification test'; end if;
 update duc_ncp set nguoi_mo_uid=u,nguoi_mo_case=ten,nguoi_dam_nhiem_doi_sach=ten,
  han_tra_loi_doi_sach=today+3,rc_trang_thai_duyet='nhap',
  doi_sach_ps_tam_thoi_json='[]',doi_sach_ps_lau_dai_json='[]',doi_sach_lx_tam_thoi_json='[]',doi_sach_lx_lau_dai_json='[]'
 where id_ncp=r.id_ncp;
 perform ncp_quet_nhac_han();
 select count(*) into n from cv_thong_bao where khoa='ncp-han:'||r.id_ncp||':'||(today+3)||':sap_han' and nguoi_nhan=u;
 if n<>1 then raise exception 'Opener/assignee must receive one shared notification, got %',n; end if;
 select count(*) into sent from cv_thong_bao where khoa like 'ncp-han:'||r.id_ncp||':%';
 perform ncp_quet_nhac_han();
 select count(*) into n from cv_thong_bao where khoa like 'ncp-han:'||r.id_ncp||':%';
 if n<>sent then raise exception 'Repeat scan generated duplicate notifications'; end if;
 update duc_ncp set han_tra_loi_doi_sach=today+1 where id_ncp=r.id_ncp;
 perform ncp_quet_nhac_han();
 if not exists(select 1 from ncp_nhac_han_log where id_ncp=r.id_ncp and moc='khan') then raise exception 'Missing urgent milestone'; end if;
 update duc_ncp set han_tra_loi_doi_sach=today where id_ncp=r.id_ncp;
 perform ncp_quet_nhac_han();
 if not exists(select 1 from ncp_nhac_han_log where id_ncp=r.id_ncp and moc='hom_nay') then raise exception 'Missing today milestone'; end if;
 update duc_ncp set han_tra_loi_doi_sach=today-1 where id_ncp=r.id_ncp;
 perform ncp_quet_nhac_han();
 if not exists(select 1 from ncp_nhac_han_log where id_ncp=r.id_ncp and moc='qua_han') then raise exception 'Missing overdue milestone'; end if;
 update duc_ncp set rc_trang_thai_duyet='cho_duyet',doi_sach_ps_tam_thoi_json='[{"noi_dung":"Rollback-only test"}]' where id_ncp=r.id_ncp;
 if exists(select 1 from cv_thong_bao where khoa like 'ncp-han:'||r.id_ncp||':%' and can_xu_ly and not da_xu_ly) then raise exception 'Completed response left pending reminders'; end if;
 if (select tien_do_tra_loi from duc_ncp_theo_doi where id_ncp=r.id_ncp)<>'da_tra_loi' then raise exception 'Completed response misclassified'; end if;
 select count(*) into sent from cv_thong_bao where khoa like 'ncp-han:'||r.id_ncp||':%';
 perform ncp_quet_nhac_han();
 if (select count(*) from cv_thong_bao where khoa like 'ncp-han:'||r.id_ncp||':%')<>sent then raise exception 'Completed response received another reminder'; end if;
end $$;
select 'PASS: 3/1/0/overdue milestones, opener-assignee deduplication, repeat scan, immediate completion and stop reminders' as result;
rollback;
