-- Read-only post-deployment assertions. Run with explicit STAGING project ref.
do $$
begin
 if not exists(select 1 from storage.buckets where id='ncp-hinh-anh' and not public
  and file_size_limit=5242880 and allowed_mime_types=array['image/jpeg']) then raise exception 'Private bucket configuration mismatch';end if;
 if exists(select 1 from duc_ncp c cross join lateral jsonb_array_elements_text(coalesce(c.source_images,'[]')) url
  where url is not null and url<>'' and not exists(select 1 from ncp_hinh_anh a where a.id_ncp=c.id_ncp and a.legacy_url=url)) then raise exception 'Legacy attachment missing';end if;
 if exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and cmd in('UPDATE','DELETE','ALL') and (coalesce(qual,'')||coalesce(with_check,'')) like '%ncp-hinh-anh%') then raise exception 'Attachment objects must be immutable';end if;
 if has_table_privilege('authenticated','ncp_hinh_anh','INSERT') or has_table_privilege('authenticated','ncp_hinh_anh','UPDATE')
 or has_table_privilege('authenticated','ncp_hinh_anh','DELETE') or has_table_privilege('anon','ncp_hinh_anh','SELECT')
 or has_function_privilege('anon','ncp_mo_phieu_co_anh(uuid,text,jsonb,jsonb)','EXECUTE') then raise exception 'Unexpected attachment grants';end if;
end $$;
select 'PASS private bucket, immutable objects, preserved legacy links and audited RPC-only writes' result,
 (select count(*) from duc_ncp) ncp_count,(select count(*) from ncp_hinh_anh) attachment_count,
 (select count(*) from ncp_hinh_anh_lich_su) audit_count;
