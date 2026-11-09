-- ĐÃ ÁP DỤNG PROD 09/11/2026 (gộp theo mảng, bỏ phiên bản hàm trung gian; bản cuối các hàm đã sửa xem T230).
-- T218: nguồn nhập và file kết quả đo private; đã áp dụng STAGING 05/11/2026.
-- Chỉ bổ sung dữ liệu kết quả; không sửa bảng/dữ liệu tiêu chuẩn, không đổi writer Đúc.
begin;
alter table public.ipqc_gc_lan add column nguon_nhap text check(nguon_nhap in('nhap_tay','tu_file'));
alter table public.ipqc_gc_lan add column tep_ket_qua jsonb;
alter table public.ipqc_gc_lan add column nhan_dien jsonb;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('ipqc-gia-cong-ket-qua','ipqc-gia-cong-ket-qua',false,20971520,array[
 'application/pdf','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
 'application/vnd.ms-excel','image/jpeg','image/png']);
create policy ipqc_gc_ket_qua_doc on storage.objects for select to authenticated
 using(bucket_id='ipqc-gia-cong-ket-qua');
create policy ipqc_gc_ket_qua_them on storage.objects for insert to authenticated with check(
 bucket_id='ipqc-gia-cong-ket-qua' and(storage.foldername(name))[1]=auth.uid()::text
 and public.has_role('admin','qc_manager','ipqc'));
alter function public.ipqc_gc_luu_do(jsonb) rename to ipqc_gc_luu_do_t217;
revoke all on function public.ipqc_gc_luu_do_t217(jsonb) from public,anon,authenticated;
create or replace function public.ipqc_gc_luu_do(p_data jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid;source text:=coalesce(p_data->>'nguon_nhap','nhap_tay');
 file_meta jsonb:=nullif(p_data->'tep_ket_qua','null'::jsonb);info jsonb:=nullif(p_data->'nhan_dien','null'::jsonb);
begin
 if auth.uid()is null or not has_role('admin','qc_manager','ipqc')then raise exception 'Chỉ IPQC hoặc quản lý QC được ghi kết quả';end if;
 if source not in('nhap_tay','tu_file')then raise exception 'Nguồn nhập kết quả không hợp lệ';end if;
 if source='tu_file' and (coalesce(p_data->>'xac_nhan_file','')<>'true' or jsonb_typeof(info)is distinct from'object')
  then raise exception 'Cần đối chiếu và xác nhận kết quả nhập từ file trước khi lưu';end if;
 if info is not null and octet_length(info::text)>1000000 then raise exception 'Thông tin nhận diện quá lớn; tách báo cáo đo cần nhập';end if;
 if file_meta is not null then
  if source<>'tu_file' or jsonb_typeof(file_meta)is distinct from'object'
   or file_meta->>'bucket' is distinct from'ipqc-gia-cong-ket-qua'
   or split_part(file_meta->>'path','/',1)is distinct from auth.uid()::text
   or not exists(select 1 from storage.objects where bucket_id='ipqc-gia-cong-ket-qua' and name=file_meta->>'path')
   then raise exception 'File kết quả phải được tải lên vùng lưu riêng của người đang nhập';end if;
 end if;
 v:=ipqc_gc_luu_do_t217(p_data);
 update ipqc_gc_lan set nguon_nhap=source,tep_ket_qua=file_meta,nhan_dien=info where id=v
  and(nguon_nhap is distinct from source or tep_ket_qua is distinct from file_meta or nhan_dien is distinct from info);
 return v;
end $$;
revoke all on function public.ipqc_gc_luu_do(jsonb) from public,anon;
grant execute on function public.ipqc_gc_luu_do(jsonb) to authenticated;
create or replace view public.ipqc_lan_tong_hop with(security_invoker=true)as
select g.id::text as id,'gia_cong'::text as cong_doan,g.ma_sp,g.revision,g.buoc_gia_cong,g.ma_may,g.ca,g.ma_lo,g.nguoi_kiem,
 g.thoi_diem,g.so_mau,g.dat,g.id_btk,g.tieu_chuan,
 (select coalesce(jsonb_agg(to_jsonb(k)order by k.muc_no,k.mau),'[]')from ipqc_gc_kq k where k.id_lan=g.id)as kq,
 g.nguon_nhap,g.tep_ket_qua,g.nhan_dien,g.co_mau_thuc_te
from ipqc_gc_lan g
union all
select l.id_checkpoint,'duc',l.ma_sp,b.phien_ban,null::text,l.ma_may,to_jsonb(c)->>'ca',null::text,l.nguoi,
 l.thoi_diem,b.so_mau,l.dat,l.id_btk,jsonb_build_object('btk',to_jsonb(b),'muc',
 (select jsonb_agg(to_jsonb(m)order by m.muc_no)from ipqc_btk_muc m where m.id_btk=b.id)),
 (select coalesce(jsonb_agg(to_jsonb(k)order by k.muc_no,k.mau),'[]')from ipqc_do_kq k where k.id_checkpoint=l.id_checkpoint),
 null::text,null::jsonb,null::jsonb,null::jsonb
from ipqc_do_lan l join ipqc_btk b on b.id=l.id_btk and b.cong_doan='duc'
join duc_ipqc_checkpoint c on c.id_checkpoint=l.id_checkpoint and c.ket_qua is not null;
revoke all on public.ipqc_lan_tong_hop from public,anon;
grant select on public.ipqc_lan_tong_hop to authenticated;
commit;
