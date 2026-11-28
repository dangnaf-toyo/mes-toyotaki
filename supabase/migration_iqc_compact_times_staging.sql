-- IQC release step 4. Supports explicit round times and completion validation. Production execution pending.
begin;
create or replace function public.iqc_luu_lan_kiem(p_lot_id bigint,p_lot jsonb,p_lan jsonb,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare l iqc_lots%rowtype; x jsonb; r iqc_lan_kiem%rowtype; old_request iqc_lan_kiem_yeu_cau%rowtype;
 body jsonb:=jsonb_build_object('lot_id',p_lot_id,'lot',p_lot,'lan',p_lan);
 checked bigint; ok bigint; ng bigint; already bigint; answer jsonb; v_lot_id bigint; draft iqc_lan_kiem_nhap%rowtype; start_at timestamptz; end_at timestamptz; target bigint;
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
  if checked is null or checked<=0 or ok is null or ok<0 or ng is null or ng<0 or ok+ng<>checked or nullif(trim(p_lan->>'nguoi_kiem'),'') is null then
   raise exception 'Ngày, người kiểm và số lượng OK + NG bằng số kiểm là bắt buộc'; end if;
 end if;
 if p_lot_id is null then
  if nullif(trim(p_lot->>'lot_no'),'') is null or nullif(trim(p_lot->>'product_code'),'') is null or nullif(trim(p_lot->>'supplier'),'') is null or nullif(p_lot->>'lot_qty','') is null or (p_lot->>'lot_qty')::bigint<=0 then raise exception 'Thiếu thông tin LOT'; end if;
  if coalesce(p_lot->>'doi_tuong','san_pham') not in ('san_pham','nvl') then raise exception 'Loại mã không hợp lệ'; end if;
  if coalesce(p_lot->>'doi_tuong','san_pham')='san_pham' and not exists(select 1 from master_products where ma_sp=trim(p_lot->>'product_code')) then raise exception 'Mã sản phẩm không có trong danh mục'; end if;
  perform pg_advisory_xact_lock(hashtextextended('iqc-lot:'||lower(trim(p_lot->>'supplier'))||':'||lower(trim(p_lot->>'product_code'))||':'||lower(trim(p_lot->>'lot_no')),0));
  if exists(select 1 from iqc_lots where lower(trim(supplier))=lower(trim(p_lot->>'supplier')) and lower(trim(product_code))=lower(trim(p_lot->>'product_code')) and lower(trim(lot_no))=lower(trim(p_lot->>'lot_no')) and phuong_thuc='ngoai_quan' and not da_luu_tru) then raise exception 'LOT đã tồn tại; chọn LOT cũ để kiểm tiếp'; end if;
  insert into iqc_lots(received_at,supplier,product_code,product_name,lot_no,lot_qty,pham_vi,doi_tuong,ma_nvl,phuong_thuc,inspection_type,aql,inspector,nguoi_kiem_id,nguoi_kiem_ten,nguoi_tao_uid,iqc_quan_ly_nhieu_lan)
  values (clock_timestamp(),trim(p_lot->>'supplier'),trim(p_lot->>'product_code'),trim(p_lot->>'product_name'),trim(p_lot->>'lot_no'),(p_lot->>'lot_qty')::bigint,
   p_lot->>'pham_vi',coalesce(p_lot->>'doi_tuong','san_pham'),nullif(p_lot->>'ma_nvl',''),'ngoai_quan',coalesce(nullif(p_lot->>'inspection_type',''),'Kiểm tra 100%'),case when p_lot->>'inspection_type'='Kiểm tra AQL' then nullif(trim(p_lot->>'aql'),'') else null end,trim(coalesce(p_lan->>'nguoi_kiem',p_lot->>'inspector','')),p_lot->>'nguoi_kiem_id',p_lot->>'nguoi_kiem_ten',auth.uid(),true) returning * into l;
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
 select * into draft from iqc_lan_kiem_nhap where id=(p_lan->>'bat_dau_id')::uuid for update;
 if draft.id is null or draft.nguoi_uid<>auth.uid() or draft.lot_id is distinct from p_lot_id or draft.lan_kiem_id is not null then raise exception 'Lần kiểm chưa được bắt đầu hoặc đã hoàn thành'; end if;
 start_at:=coalesce(nullif(p_lan->>'bat_dau_luc','')::timestamptz,draft.bat_dau_luc);
 end_at:=coalesce(nullif(p_lan->>'ket_thuc_luc','')::timestamptz,clock_timestamp());
 if start_at>end_at or end_at>clock_timestamp() then raise exception 'Thời gian không hợp lệ'; end if;
 if nullif(p_lan->>'ket_thuc_luc','') is not null then
  if l.inspection_type='Kiểm tra AQL' then select mau_yeu_cau into target from iqc_aql_ke_hoach where lot_id=l.id; else target:=l.lot_qty; end if;
  if target is null or already+checked<target then raise exception 'LOT chưa đủ số lượng để ghi giờ hoàn thành'; end if;
  if exists(select 1 from iqc_lan_kiem where lot_id=l.id and bat_dau_luc>end_at) then raise exception 'Giờ hoàn thành trước lần kiểm trước đó'; end if;
 end if;
 insert into iqc_lan_kiem(lot_id,ngay_kiem,nguoi_kiem,so_kiem,so_ok,so_ng,nguoi_tao,bat_dau_luc,ket_thuc_luc)
 values(l.id,(start_at at time zone 'Asia/Ho_Chi_Minh')::date,trim(p_lan->>'nguoi_kiem'),checked,ok,ng,auth.uid(),start_at,end_at) returning * into r;
 update iqc_lan_kiem_nhap set lan_kiem_id=r.id where id=draft.id;
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
 old_request iqc_lan_kiem_yeu_cau%rowtype; old_defects jsonb; x jsonb; checked bigint; ok bigint; ng bigint; other_checked bigint; start_at timestamptz; end_at timestamptz; target bigint;
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
 if checked is null or checked<=0 or ok is null or ok<0 or ng is null or ng<0 or ok+ng<>checked or nullif(trim(p_lan->>'nguoi_kiem'),'') is null then raise exception 'Ngày, người kiểm và số lượng OK + NG bằng số kiểm là bắt buộc'; end if;
 select coalesce(sum(so_kiem),0) into other_checked from iqc_lan_kiem where lot_id=l.id and id<>p_id;
 if other_checked+checked>l.lot_qty then raise exception 'Số lượng kiểm vượt số lượng LOT'; end if;
 select coalesce(jsonb_agg(to_jsonb(d) order by d.id),'[]') into old_defects from iqc_lan_kiem_loi d where lan_kiem_id=p_id;
 start_at:=coalesce(nullif(p_lan->>'bat_dau_luc','')::timestamptz,oldrow.bat_dau_luc);end_at:=coalesce(nullif(p_lan->>'ket_thuc_luc','')::timestamptz,oldrow.ket_thuc_luc);
 if (start_at is distinct from oldrow.bat_dau_luc or end_at is distinct from oldrow.ket_thuc_luc) and (not has_role('admin','qc_manager') or nullif(trim(p_lan->>'ly_do_thoi_gian'),'') is null) then raise exception 'Quản lý QC cần ghi lý do sửa thời gian'; end if;
 if nullif(p_lan->>'ket_thuc_luc','') is not null then
  if l.inspection_type='Kiểm tra AQL' then select mau_yeu_cau into target from iqc_aql_ke_hoach where lot_id=l.id; else target:=l.lot_qty; end if;
  if target is null or other_checked+checked<target then raise exception 'LOT chưa đủ số lượng để ghi giờ hoàn thành'; end if;
  if exists(select 1 from iqc_lan_kiem where lot_id=l.id and id<>p_id and bat_dau_luc>end_at) then raise exception 'Giờ hoàn thành trước lần kiểm trước đó'; end if;
 end if;
 if start_at is not null and end_at is not null and (start_at>end_at or end_at>clock_timestamp()) then raise exception 'Thời gian không hợp lệ'; end if;
 update iqc_lan_kiem set ngay_kiem=case when start_at is distinct from oldrow.bat_dau_luc then (start_at at time zone 'Asia/Ho_Chi_Minh')::date else oldrow.ngay_kiem end,bat_dau_luc=start_at,ket_thuc_luc=end_at,nguoi_kiem=trim(p_lan->>'nguoi_kiem'),so_kiem=checked,so_ok=ok,so_ng=ng,sua_luc=clock_timestamp() where id=p_id returning * into newrow;
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
 insert into iqc_lich_su(loai,khoa,du_lieu_cu,du_lieu_moi,nguoi_uid,nguoi) values('sua_lan_kiem',p_id::text,to_jsonb(oldrow)||jsonb_build_object('loi',old_defects),to_jsonb(newrow)||jsonb_build_object('loi',p_lan->'loi','ly_do_thoi_gian',p_lan->>'ly_do_thoi_gian'),auth.uid(),duc_ten_nguoi_hien_tai());
 return answer;
end $$;
notify pgrst,'reload schema';
commit;
