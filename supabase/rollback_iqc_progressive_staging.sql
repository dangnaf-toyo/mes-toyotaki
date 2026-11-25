-- STAGING ONLY: pause IQC writes and return application to commit 5726041 first.
-- This restores previous function bodies but retains all new data and columns.
begin;
create or replace function public.iqc_luu_lan_kiem(p_lot_id bigint,p_lot jsonb,p_lan jsonb,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l iqc_lots%rowtype; x jsonb; r iqc_lan_kiem%rowtype; old_request iqc_lan_kiem_yeu_cau%rowtype;
 body jsonb:=jsonb_build_object('lot_id',p_lot_id,'lot',p_lot,'lan',p_lan);
 checked bigint; ok bigint; ng bigint; already bigint; answer jsonb; v_lot_id bigint;
begin
 if auth.uid() is null or not has_role('admin','qc_manager','iqc') then raise exception 'Chỉ IQC hoặc quản lý QC được lưu lần kiểm'; end if;
 if p_request_id is null then raise exception 'Thiếu mã yêu cầu lưu'; end if;
 perform pg_advisory_xact_lock(hashtextextended('iqc-inspection-request:'||p_request_id,0));
 select * into old_request from iqc_lan_kiem_yeu_cau where request_id=p_request_id;
 if found then
  if old_request.nguoi_uid<>auth.uid() or old_request.noi_dung<>body then raise exception 'Mã yêu cầu đã được dùng cho dữ liệu khác'; end if;
  return old_request.ket_qua;
 end if;
 if p_lan is null and p_lot_id is not null then raise exception 'Chưa nhập lần kiểm'; end if;
 if p_lan is not null then
  if jsonb_typeof(p_lan->'loi') is distinct from 'array' then raise exception 'Dữ liệu lần kiểm không hợp lệ'; end if;
  checked:=(p_lan->>'so_kiem')::bigint; ok:=(p_lan->>'so_ok')::bigint; ng:=(p_lan->>'so_ng')::bigint;
  if checked is null or checked<=0 or ok is null or ok<0 or ng is null or ng<0 or ok+ng<>checked or nullif(trim(p_lan->>'nguoi_kiem'),'') is null or nullif(p_lan->>'ngay_kiem','') is null then
   raise exception 'Ngày, người kiểm và số lượng OK + NG bằng số kiểm là bắt buộc'; end if;
 end if;
 if p_lot_id is null then
  if nullif(trim(p_lot->>'lot_no'),'') is null or nullif(trim(p_lot->>'product_code'),'') is null or nullif(trim(p_lot->>'supplier'),'') is null or nullif(p_lot->>'received_at','') is null or nullif(p_lot->>'lot_qty','') is null or (p_lot->>'lot_qty')::bigint<=0 then raise exception 'Thiếu thông tin LOT'; end if;
  if coalesce(p_lot->>'doi_tuong','san_pham') not in ('san_pham','nvl') then raise exception 'Loại mã không hợp lệ'; end if;
  if coalesce(p_lot->>'doi_tuong','san_pham')='san_pham' and not exists(select 1 from master_products where ma_sp=trim(p_lot->>'product_code')) then raise exception 'Mã sản phẩm không có trong danh mục'; end if;
  perform pg_advisory_xact_lock(hashtextextended('iqc-lot:'||lower(trim(p_lot->>'supplier'))||':'||lower(trim(p_lot->>'product_code'))||':'||lower(trim(p_lot->>'lot_no')),0));
  if exists(select 1 from iqc_lots where lower(trim(supplier))=lower(trim(p_lot->>'supplier')) and lower(trim(product_code))=lower(trim(p_lot->>'product_code')) and lower(trim(lot_no))=lower(trim(p_lot->>'lot_no')) and phuong_thuc='ngoai_quan' and not da_luu_tru) then raise exception 'LOT đã tồn tại; chọn LOT cũ để kiểm tiếp'; end if;
  insert into iqc_lots(received_at,supplier,product_code,product_name,lot_no,lot_qty,pham_vi,doi_tuong,ma_nvl,phuong_thuc,inspection_type,inspector,nguoi_kiem_id,nguoi_kiem_ten,nguoi_tao_uid,iqc_quan_ly_nhieu_lan)
  values ((p_lot->>'received_at')::timestamptz,trim(p_lot->>'supplier'),trim(p_lot->>'product_code'),trim(p_lot->>'product_name'),trim(p_lot->>'lot_no'),(p_lot->>'lot_qty')::bigint,
   p_lot->>'pham_vi',coalesce(p_lot->>'doi_tuong','san_pham'),nullif(p_lot->>'ma_nvl',''),'ngoai_quan',coalesce(nullif(p_lot->>'inspection_type',''),'Kiểm tra 100%'),trim(coalesce(p_lan->>'nguoi_kiem',p_lot->>'inspector','')),p_lot->>'nguoi_kiem_id',p_lot->>'nguoi_kiem_ten',auth.uid(),true) returning * into l;
 else
  select * into l from iqc_lots where id=p_lot_id for update;
  if not found or l.da_luu_tru or l.phuong_thuc<>'ngoai_quan' then raise exception 'Không tìm thấy LOT ngoại quan đang dùng'; end if;
  if l.iqc_tam_dung then raise exception 'LOT đang tạm dừng; xử lý trước khi kiểm tiếp'; end if;
  if l.doi_tuong='nvl' and exists(select 1 from iqc_phan_loai_tu_danh_muc(l.ma_nvl) c where c.nhom in ('nhom','kem')) then raise exception 'Danh mục hiện phân loại NVL này là Nhôm/Kẽm; kiểm hóa học trước khi tiếp tục'; end if;
  if not exists(select 1 from iqc_lan_kiem where lot_id=l.id) and (coalesce(l.ok_qty,0)<>0 or coalesce(l.ng_qty,0)<>0 or l.status='Đã kiểm tra' or (l.inspection_type='Kiểm tra AQL' and l.status not in ('Chưa lấy hàng','Đang chờ kiểm')) or exists(select 1 from iqc_defects where lot_id=l.id)) then
   if l.inspection_type='Kiểm tra 100%' and coalesce(l.ok_qty,0)>=0 and coalesce(l.ng_qty,0)>=0 and l.ok_qty=trunc(l.ok_qty) and l.ng_qty=trunc(l.ng_qty) and l.ok_qty+l.ng_qty>0 and l.ok_qty+l.ng_qty<=l.lot_qty then
    insert into iqc_lan_kiem(lot_id,loai,ngay_kiem,nguoi_kiem,so_kiem,so_ok,so_ng,nguoi_tao,ket_luan_cu)
     values(l.id,'so_du_cu',null,coalesce(nullif(l.inspector,''),'Không xác định'),(l.ok_qty+l.ng_qty)::bigint,l.ok_qty::bigint,l.ng_qty::bigint,auth.uid(),l.result);
    insert into iqc_lich_su(loai,khoa,du_lieu_cu,du_lieu_moi,nguoi_uid,nguoi) values('so_du_lich_su',l.id::text,to_jsonb(l),jsonb_build_object('so_kiem',l.ok_qty+l.ng_qty,'so_ok',l.ok_qty,'so_ng',l.ng_qty),auth.uid(),duc_ten_nguoi_hien_tai());
   else raise exception 'LOT lịch sử chưa có số đã kiểm xác định; cần xử lý dữ liệu cũ trước khi kiểm tiếp'; end if;
  end if;
 end if;
 if p_lan is null then
  answer:=jsonb_build_object('lot_id',l.id,'lan_kiem_id',null);
  insert into iqc_lan_kiem_yeu_cau values(p_request_id,auth.uid(),body,answer);
  insert into iqc_lich_su(loai,khoa,du_lieu_moi,nguoi_uid,nguoi) values('tao_lot',l.id::text,to_jsonb(l),auth.uid(),duc_ten_nguoi_hien_tai());
  return answer;
 end if;
 select coalesce(sum(so_kiem),0) into already from iqc_lan_kiem where lot_id=l.id;
 if already+checked>l.lot_qty then raise exception 'Số lượng kiểm vượt số còn lại'; end if;
 insert into iqc_lan_kiem(lot_id,ngay_kiem,nguoi_kiem,so_kiem,so_ok,so_ng,nguoi_tao)
 values(l.id,(p_lan->>'ngay_kiem')::date,trim(p_lan->>'nguoi_kiem'),checked,ok,ng,auth.uid()) returning * into r;
 if l.iqc_ket_luan is not null then
  perform set_config('iqc.quality_lot',l.id::text,true);
  update iqc_lots set iqc_ket_luan=null where id=l.id;
  perform set_config('iqc.quality_lot','',true);
 end if;
 for x in select value from jsonb_array_elements(p_lan->'loi') loop
  insert into iqc_lan_kiem_loi(lan_kiem_id,ten_loi,nhom_loi,chi_tiet,so_luong)
  values(r.id,trim(x->>'ten_loi'),nullif(trim(x->>'nhom_loi'),''),nullif(trim(x->>'chi_tiet'),''),(x->>'so_luong')::bigint);
 end loop;
 perform iqc_tinh_tong_lot(l.id);
 answer:=jsonb_build_object('lot_id',l.id,'lan_kiem_id',r.id);
 insert into iqc_lan_kiem_yeu_cau values(p_request_id,auth.uid(),body,answer);
 insert into iqc_lich_su(loai,khoa,du_lieu_moi,nguoi_uid,nguoi) values('lan_kiem',r.id::text,to_jsonb(r)||jsonb_build_object('loi',p_lan->'loi'),auth.uid(),duc_ten_nguoi_hien_tai());
 return answer;
end $$;

create or replace function public.iqc_sua_lan_kiem(p_id bigint,p_lan jsonb,p_sua_luc timestamptz,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare oldrow iqc_lan_kiem%rowtype; newrow iqc_lan_kiem%rowtype; l iqc_lots%rowtype;
 old_request iqc_lan_kiem_yeu_cau%rowtype; old_defects jsonb; x jsonb; checked bigint; ok bigint; ng bigint; other_checked bigint;
 body jsonb:=jsonb_build_object('id',p_id,'lan',p_lan,'sua_luc',p_sua_luc); answer jsonb;
begin
 if auth.uid() is null or not has_role('admin','qc_manager','iqc') then raise exception 'Không có quyền sửa lần kiểm'; end if;
 if p_request_id is null then raise exception 'Thiếu mã yêu cầu'; end if;
 perform pg_advisory_xact_lock(hashtextextended('iqc-inspection-request:'||p_request_id,0));
 select * into old_request from iqc_lan_kiem_yeu_cau where request_id=p_request_id;
 if found then
  if old_request.nguoi_uid<>auth.uid() or old_request.noi_dung<>body then raise exception 'Mã yêu cầu đã dùng cho dữ liệu khác'; end if;
  return old_request.ket_qua;
 end if;
 select * into oldrow from iqc_lan_kiem where id=p_id;
 if not found then raise exception 'Không tìm thấy lần kiểm'; end if;
 select * into l from iqc_lots where id=oldrow.lot_id for update;
 select * into oldrow from iqc_lan_kiem where id=p_id for update;
 if l.da_luu_tru or l.phuong_thuc<>'ngoai_quan' then raise exception 'LOT không thể sửa'; end if;
 if oldrow.loai='so_du_cu' then raise exception 'Số dư lịch sử chỉ đọc; dữ liệu LOT gốc được giữ nguyên'; end if;
 if oldrow.nguoi_tao<>auth.uid() and not has_role('admin','qc_manager') then raise exception 'Chỉ người tạo hoặc quản lý QC được sửa'; end if;
 if p_sua_luc is distinct from oldrow.sua_luc then raise exception 'Lần kiểm đã thay đổi; mở lại trước khi sửa'; end if;
 if p_lan is null or jsonb_typeof(p_lan->'loi') is distinct from 'array' then raise exception 'Dữ liệu lỗi không hợp lệ'; end if;
 checked:=(p_lan->>'so_kiem')::bigint; ok:=(p_lan->>'so_ok')::bigint; ng:=(p_lan->>'so_ng')::bigint;
 if checked is null or checked<=0 or ok is null or ok<0 or ng is null or ng<0 or ok+ng<>checked or nullif(trim(p_lan->>'nguoi_kiem'),'') is null or nullif(p_lan->>'ngay_kiem','') is null then raise exception 'Ngày, người kiểm và số lượng OK + NG bằng số kiểm là bắt buộc'; end if;
 select coalesce(sum(so_kiem),0) into other_checked from iqc_lan_kiem where lot_id=l.id and id<>p_id;
 if other_checked+checked>l.lot_qty then raise exception 'Số lượng kiểm vượt số lượng LOT'; end if;
 select coalesce(jsonb_agg(to_jsonb(d) order by d.id),'[]') into old_defects from iqc_lan_kiem_loi d where lan_kiem_id=p_id;
 update iqc_lan_kiem set ngay_kiem=(p_lan->>'ngay_kiem')::date,nguoi_kiem=trim(p_lan->>'nguoi_kiem'),so_kiem=checked,so_ok=ok,so_ng=ng,sua_luc=clock_timestamp() where id=p_id returning * into newrow;
 if l.iqc_ket_luan is not null then
  perform set_config('iqc.quality_lot',l.id::text,true);
  update iqc_lots set iqc_ket_luan=null where id=l.id;
  perform set_config('iqc.quality_lot','',true);
 end if;
 delete from iqc_lan_kiem_loi where lan_kiem_id=p_id;
 for x in select value from jsonb_array_elements(p_lan->'loi') loop
  insert into iqc_lan_kiem_loi(lan_kiem_id,ten_loi,nhom_loi,chi_tiet,so_luong)
  values(p_id,trim(x->>'ten_loi'),nullif(trim(x->>'nhom_loi'),''),nullif(trim(x->>'chi_tiet'),''),(x->>'so_luong')::bigint);
 end loop;
 perform iqc_tinh_tong_lot(l.id);
 answer:=jsonb_build_object('lot_id',l.id,'lan_kiem_id',p_id,'sua_luc',newrow.sua_luc);
 insert into iqc_lan_kiem_yeu_cau values(p_request_id,auth.uid(),body,answer);
 insert into iqc_lich_su(loai,khoa,du_lieu_cu,du_lieu_moi,nguoi_uid,nguoi) values('sua_lan_kiem',p_id::text,to_jsonb(oldrow)||jsonb_build_object('loi',old_defects),to_jsonb(newrow)||jsonb_build_object('loi',p_lan->'loi'),auth.uid(),duc_ten_nguoi_hien_tai());
 return answer;
end $$;

create or replace function public.iqc_sua_thong_tin_lot(p_id bigint,p_lot jsonb,p_updated_at timestamptz)
returns jsonb language plpgsql security definer set search_path=public as $$
declare before_row iqc_lots%rowtype; after_row iqc_lots%rowtype; v_qty bigint; v_total bigint;
begin
 if auth.uid() is null or not has_role('admin','qc_manager') then raise exception 'Chỉ quản lý QC được sửa thông tin LOT'; end if;
 select * into before_row from iqc_lots where id=p_id for update;
 if not found or before_row.da_luu_tru or before_row.phuong_thuc<>'ngoai_quan' then raise exception 'Không tìm thấy LOT'; end if;
 if before_row.updated_at is distinct from p_updated_at then raise exception 'LOT đã thay đổi; tải lại trước khi sửa'; end if;
 v_qty:=(p_lot->>'lot_qty')::bigint;
 select coalesce(sum(so_kiem),0) into v_total from iqc_lan_kiem where lot_id=p_id;
 if v_qty is null or v_qty<=0 or v_qty<v_total or nullif(p_lot->>'received_at','') is null then raise exception 'Ngày nhận và số LOT phải hợp lệ, không nhỏ hơn số đã kiểm'; end if;
 if nullif(trim(p_lot->>'supplier'),'') is null then raise exception 'Nhà cung cấp là bắt buộc'; end if;
 perform pg_advisory_xact_lock(hashtextextended('iqc-lot:'||lower(trim(p_lot->>'supplier'))||':'||lower(trim(before_row.product_code))||':'||lower(trim(before_row.lot_no)),0));
 if exists(select 1 from iqc_lots where id<>p_id and lower(trim(supplier))=lower(trim(p_lot->>'supplier')) and lower(trim(product_code))=lower(trim(before_row.product_code)) and lower(trim(lot_no))=lower(trim(before_row.lot_no)) and phuong_thuc='ngoai_quan' and not da_luu_tru) then raise exception 'LOT đã tồn tại với nhà cung cấp này'; end if;
 perform set_config('iqc.edit_lot',p_id::text,true);
 update iqc_lots set received_at=(p_lot->>'received_at')::timestamptz,lot_qty=v_qty,supplier=trim(p_lot->>'supplier'),note=p_lot->>'note', location=p_lot->>'location' where id=p_id returning * into after_row;
 perform set_config('iqc.edit_lot','',true);
 perform iqc_tinh_tong_lot(p_id);
 select * into after_row from iqc_lots where id=p_id;
 insert into iqc_lich_su(loai,khoa,du_lieu_cu,du_lieu_moi,nguoi_uid,nguoi) values('sua_thong_tin_lot',p_id::text,to_jsonb(before_row),to_jsonb(after_row),auth.uid(),duc_ten_nguoi_hien_tai());
 return to_jsonb(after_row);
end $$;

create or replace function public.iqc_bao_ve_tong_lan_kiem() returns trigger language plpgsql set search_path=public as $$
begin
 if (old.iqc_quan_ly_nhieu_lan or exists(select 1 from iqc_lan_kiem where lot_id=old.id)) and
  (((new.lot_qty is distinct from old.lot_qty or new.received_at is distinct from old.received_at or new.supplier is distinct from old.supplier or new.note is distinct from old.note or new.location is distinct from old.location) and (current_setting('iqc.edit_lot',true) is distinct from old.id::text or current_user <> pg_get_userbyid((select proowner from pg_proc where oid='public.iqc_sua_thong_tin_lot(bigint,jsonb,timestamptz)'::regprocedure)))) or
   (new.iqc_tam_dung is distinct from old.iqc_tam_dung and (current_setting('iqc.pause_lot',true) is distinct from old.id::text or current_user <> pg_get_userbyid((select proowner from pg_proc where oid='public.iqc_tam_dung_lot(bigint,boolean,text)'::regprocedure)))) or new.product_code is distinct from old.product_code or new.lot_no is distinct from old.lot_no or
   (new.iqc_ket_luan is distinct from old.iqc_ket_luan and (current_setting('iqc.quality_lot',true) is distinct from old.id::text or current_user <> pg_get_userbyid((select proowner from pg_proc where oid='public.iqc_danh_gia_lot(bigint,text,timestamptz)'::regprocedure)))) or
   new.doi_tuong is distinct from old.doi_tuong or new.ma_nvl is distinct from old.ma_nvl or new.phuong_thuc is distinct from old.phuong_thuc or new.iqc_quan_ly_nhieu_lan is distinct from old.iqc_quan_ly_nhieu_lan or
   new.pham_vi is distinct from old.pham_vi or new.inspection_type is distinct from old.inspection_type or new.aql is distinct from old.aql or new.sample_qty is distinct from old.sample_qty or new.inspector is distinct from old.inspector or
   ((new.ok_qty is distinct from old.ok_qty or new.ng_qty is distinct from old.ng_qty or new.ok_pct is distinct from old.ok_pct or new.ng_pct is distinct from old.ng_pct or new.result is distinct from old.result or new.status is distinct from old.status) and
    (current_setting('iqc.aggregate_lot',true) is distinct from old.id::text or current_user <> pg_get_userbyid((select proowner from pg_proc where oid='public.iqc_tinh_tong_lot(bigint)'::regprocedure))))) then
  raise exception 'LOT có lịch sử lần kiểm: thay đổi qua chức năng IQC nhiều lần kiểm';
 end if;
 return new;
end $$;

create or replace function public.iqc_tinh_tong_lot(p_id bigint) returns void language plpgsql security definer set search_path=public as $$
declare l iqc_lots%rowtype; checked bigint; oks bigint; ngs bigint; legacy_ng boolean; q_result text; q_status text;
begin
 select * into l from iqc_lots where id=p_id for update;
 select coalesce(sum(so_kiem),0),coalesce(sum(so_ok),0),coalesce(sum(so_ng),0),coalesce(bool_or(loai='so_du_cu' and ket_luan_cu='NG'),false)
  into checked,oks,ngs,legacy_ng from iqc_lan_kiem where lot_id=p_id;
 if checked>l.lot_qty then raise exception 'Tổng đã kiểm vượt số lượng LOT'; end if;
 q_status:=case when checked=0 then 'Chưa lấy hàng' when checked=l.lot_qty then 'Đã kiểm tra' else 'Đang kiểm tra' end;
 q_result:=case when ngs>0 or legacy_ng then 'NG' else coalesce(l.iqc_ket_luan,'') end;
 perform set_config('iqc.aggregate_lot',p_id::text,true);
 update iqc_lots set ok_qty=oks,ng_qty=ngs,ok_pct=case when checked>0 then 100.0*oks/checked else 0 end,
  ng_pct=case when checked>0 then 100.0*ngs/checked else 0 end,status=q_status,result=q_result where id=p_id;
 perform set_config('iqc.aggregate_lot','',true);
end $$;
drop trigger if exists iqc_tranh_trung_lot_hoa_hoc on public.iqc_lots;
grant execute on function public.iqc_danh_gia_lot(bigint,text,timestamptz) to authenticated;
revoke execute on function public.iqc_bat_dau_lan_kiem(uuid,bigint), public.iqc_dang_ky_lot_hoa_hoc(uuid,text,text,text,numeric,text), public.iqc_sua_thoi_gian_lan_kiem(bigint,timestamptz,timestamptz,timestamptz,text), public.iqc_phan_quyet_lot(bigint,text,timestamptz,text), public.iqc_duyet_ke_hoach_aql(bigint,bigint,bigint,bigint,text,timestamptz), public.iqc_luu_cau_hinh_aql(text,text,text,text,text,text,jsonb,text[],boolean), public.iqc_tra_ke_hoach_aql(bigint) from authenticated;
notify pgrst,'reload schema';
commit;
