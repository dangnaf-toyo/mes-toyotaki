-- Đã chạy STAGING 29/10/2026; chưa chạy PRODUCTION.
-- T184 — STAGING: hạn trả lời, tiến độ và nhắc hạn NCP qua chuông chung.
-- Phiếu cũ giữ NULL (không tự gán hạn); không thay đổi nghiệp vụ duyệt đối sách.
begin;
alter table public.duc_ncp add column if not exists han_tra_loi_doi_sach date;
alter table public.duc_ncp add column if not exists nguoi_mo_uid uuid;
create index if not exists duc_ncp_han_doi_sach_idx on public.duc_ncp(han_tra_loi_doi_sach) where han_tra_loi_doi_sach is not null;

create table if not exists public.ncp_cau_hinh_nhac_han (
 id boolean primary key default true check(id),
 truoc_han_ngay integer not null default 3 check(truoc_han_ngay between 1 and 90),
 khan_truoc_ngay integer not null default 1 check(khan_truoc_ngay >= 1 and khan_truoc_ngay < truoc_han_ngay),
 bat_nhac boolean not null default true,
 cap_nhat_luc timestamptz not null default now()
);
insert into public.ncp_cau_hinh_nhac_han(id) values(true) on conflict do nothing;
alter table public.ncp_cau_hinh_nhac_han enable row level security;
create policy ncp_cau_hinh_doc on public.ncp_cau_hinh_nhac_han for select to authenticated using(true);
grant select on public.ncp_cau_hinh_nhac_han to authenticated;
revoke all on public.ncp_cau_hinh_nhac_han from anon;
revoke insert,update,delete on public.ncp_cau_hinh_nhac_han from authenticated;
create or replace function public.ncp_luu_cau_hinh(p_truoc integer,p_khan integer,p_bat boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not has_role('admin','qc_manager') then raise exception 'Chỉ Admin / Trưởng phòng QC được cấu hình nhắc hạn'; end if;
 update ncp_cau_hinh_nhac_han set truoc_han_ngay=p_truoc,khan_truoc_ngay=p_khan,bat_nhac=p_bat,cap_nhat_luc=now() where id;
end $$;
revoke all on function public.ncp_luu_cau_hinh(integer,integer,boolean) from public,anon;
grant execute on function public.ncp_luu_cau_hinh(integer,integer,boolean) to authenticated;

-- Gửi duyệt là mốc đã trả lời theo quy tắc hiện có (có ít nhất một đối sách).
-- Bị trả lại / mở lại cần trả lời tiếp, dù trước đó từng được duyệt.
create or replace function public.ncp_da_tra_loi(r public.duc_ncp)
returns boolean language sql immutable set search_path=public as $$
 select coalesce(r.rc_trang_thai_duyet in ('cho_duyet','da_duyet'),false) and exists(
 select 1 from jsonb_array_elements(coalesce(r.doi_sach_ps_tam_thoi_json,'[]')||coalesce(r.doi_sach_ps_lau_dai_json,'[]')||coalesce(r.doi_sach_lx_tam_thoi_json,'[]')||coalesce(r.doi_sach_lx_lau_dai_json,'[]')) e
 where nullif(trim(e->>'noi_dung'),'') is not null)
$$;
create or replace view public.duc_ncp_theo_doi with(security_invoker=true) as
select r.*,
 case when ncp_da_tra_loi(r) then 'da_tra_loi'
      when r.han_tra_loi_doi_sach < (now() at time zone 'Asia/Ho_Chi_Minh')::date then 'qua_han'
      when nullif(trim(r.nguyen_nhan_phat_sinh),'') is not null or nullif(trim(r.nguyen_nhan_luu_xuat),'') is not null
       or jsonb_array_length(coalesce(r.doi_sach_ps_tam_thoi_json,'[]')||coalesce(r.doi_sach_ps_lau_dai_json,'[]')||coalesce(r.doi_sach_lx_tam_thoi_json,'[]')||coalesce(r.doi_sach_lx_lau_dai_json,'[]'))>0 then 'dang_thuc_hien'
      else 'chua_tra_loi' end as tien_do_tra_loi,
 case when ncp_da_tra_loi(r) then 'hoan_thanh'
      when r.han_tra_loi_doi_sach is null then 'chua_co_han'
      when r.han_tra_loi_doi_sach < (now() at time zone 'Asia/Ho_Chi_Minh')::date then 'qua_han'
      when r.han_tra_loi_doi_sach = (now() at time zone 'Asia/Ho_Chi_Minh')::date then 'hom_nay'
      when r.han_tra_loi_doi_sach <= (now() at time zone 'Asia/Ho_Chi_Minh')::date+(select truoc_han_ngay from ncp_cau_hinh_nhac_han where id) then 'sap_den_han'
      else 'con_han' end as trang_thai_han
from public.duc_ncp r;
revoke all on function public.ncp_da_tra_loi(public.duc_ncp) from public,anon;
grant execute on function public.ncp_da_tra_loi(public.duc_ncp) to authenticated;
revoke all on public.duc_ncp_theo_doi from public,anon;
grant select on public.duc_ncp_theo_doi to authenticated;

-- Sổ sự kiện bền vững: khóa gồm phiếu + hạn + mốc. Lịch sử đọc nằm ở cv_thong_bao.
create table if not exists public.ncp_nhac_han_log (
 khoa text primary key,id_ncp text not null references public.duc_ncp(id_ncp),
 han date not null,moc text not null,nguoi_nhan uuid[] not null,
 so_thong_bao integer not null default 0,gui_luc timestamptz not null default now()
);
alter table public.ncp_nhac_han_log enable row level security;
create policy ncp_nhac_han_log_doc on public.ncp_nhac_han_log for select to authenticated
 using(auth.uid()=any(nguoi_nhan) or has_role('admin','qc_manager','giam_doc_sx'));
revoke all on public.ncp_nhac_han_log from anon,authenticated;
grant select on public.ncp_nhac_han_log to authenticated;

create or replace function public.ncp_quet_nhac_han()
returns integer language plpgsql security definer set search_path=public as $$
declare r duc_ncp%rowtype; cfg ncp_cau_hinh_nhac_han%rowtype;
 hom_nay date:=(now() at time zone 'Asia/Ho_Chi_Minh')::date;
 con_ngay integer; moc text; khoa_moc text; ds uuid[]; ds_moi uuid[]; so_gui integer; tong integer:=0;
begin
 -- Khóa toàn lượt quét để cron / lượt thử lại không gửi đồng thời.
 perform pg_advisory_xact_lock(hashtext('ncp_quet_nhac_han'));
 select * into cfg from ncp_cau_hinh_nhac_han where id;
 if not cfg.bat_nhac then return 0; end if;
 for r in select * from duc_ncp where han_tra_loi_doi_sach is not null loop
  if ncp_da_tra_loi(r) then
   perform cv_pd_xong('ncp-han:'||r.id_ncp||':',true); continue;
  end if;
  con_ngay:=r.han_tra_loi_doi_sach-hom_nay;
  moc:=case when con_ngay<0 then 'qua_han' when con_ngay=0 then 'hom_nay'
    when con_ngay<=cfg.khan_truoc_ngay then 'khan' when con_ngay<=cfg.truoc_han_ngay then 'sap_han' end;
  if moc is null then continue; end if;
  khoa_moc:='ncp-han:'||r.id_ncp||':'||r.han_tra_loi_doi_sach||':'||moc;
  select coalesce(array_agg(distinct x),'{}') into ds from unnest(
   array[r.nguoi_mo_uid]||cv_pd_ds_ten(r.nguoi_mo_case)||cv_pd_ds_ten(r.nguoi_dam_nhiem_doi_sach)||cv_pd_ds_role(array['giam_doc_sx','qc_manager'])
  ) x where x is not null;
  -- Cho phép người mới được phân công nhận sự kiện, không gửi lại người đã nhận.
  select coalesce(array_agg(u),'{}') into ds_moi from unnest(ds) u
   where not exists(select 1 from cv_thong_bao t where t.khoa=khoa_moc and t.nguoi_nhan=u);
  so_gui:=cv_pd_gui(ds_moi,'ncp','nhac_han',khoa_moc,'ncp-detail.html?id='||r.id_ncp,
   'NCP '||r.id_ncp||' — '||case moc when 'qua_han' then 'Quá hạn trả lời đối sách' when 'hom_nay' then 'Đến hạn trả lời hôm nay' when 'khan' then 'Khẩn: sắp hết hạn trả lời đối sách' else 'Sắp đến hạn trả lời đối sách' end
   ||' ('||to_char(r.han_tra_loi_doi_sach,'DD/MM/YYYY')||').',true);
  insert into ncp_nhac_han_log(khoa,id_ncp,han,moc,nguoi_nhan,so_thong_bao)
   values(khoa_moc,r.id_ncp,r.han_tra_loi_doi_sach,moc,ds,so_gui)
   on conflict(khoa) do update set nguoi_nhan=excluded.nguoi_nhan,so_thong_bao=ncp_nhac_han_log.so_thong_bao+excluded.so_thong_bao;
  tong:=tong+so_gui;
 end loop;
 return tong;
end $$;
revoke all on function public.ncp_quet_nhac_han() from public,anon,authenticated;
-- 07:00..22:00 GMT+7, mỗi giờ; bù mốc nếu server gián đoạn, không bắn các mốc đã qua.
select cron.schedule('ncp_nhac_han_doi_sach','0 0-15 * * *','select public.ncp_quet_nhac_han();');
drop function public.duc_ncp_open_case(text,text,text,text,text,text,numeric,numeric,text,text,text,text);
CREATE OR REPLACE FUNCTION public.duc_ncp_open_case(p_id_checkpoint_goc text, p_ma_may text, p_ma_sp text, p_ten_sp text, p_so_khuon text, p_mo_ta_loi text, p_so_luong_nghi_van numeric, p_so_luong_ng_du_kien numeric, p_vi_tri_cach_ly text, p_nguoi_dam_nhiem text, p_nguoi_dam_nhiem_doi_sach text, p_user text, p_han_tra_loi_doi_sach date default null)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public
AS $function$
declare
  v_id_ncp text;
  v_existing text;
  v_now timestamptz := now();
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
  select coalesce(nullif(trim(username),''),email) into p_user from user_roles where user_id=auth.uid();
  if p_han_tra_loi_doi_sach is null then raise exception 'Chọn hạn trả lời đối sách (tải lại trang nếu chưa thấy trường này)'; end if;
  if p_so_luong_nghi_van is null or p_so_luong_nghi_van <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Số lượng nghi vấn phải là số dương');
  end if;
  if p_so_luong_ng_du_kien is null or p_so_luong_ng_du_kien < 0 then
    return jsonb_build_object('ok', false, 'error', 'Số lượng NG dự kiến không được âm');
  end if;
  if p_so_luong_ng_du_kien > p_so_luong_nghi_van then
    return jsonb_build_object('ok', false, 'error', 'Số lượng NG dự kiến không được vượt quá số lượng nghi vấn');
  end if;

  if p_id_checkpoint_goc is not null and p_id_checkpoint_goc <> '' then
    select id_ncp_lien_quan into v_existing from duc_ipqc_checkpoint where id_checkpoint = p_id_checkpoint_goc;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'Không tìm thấy điểm kiểm gốc: ' || p_id_checkpoint_goc);
    end if;
    if v_existing is not null and v_existing <> '' then
      return jsonb_build_object('ok', false, 'error', 'Điểm kiểm này đã có phiếu xử lý (' || v_existing || ') — không mở trùng.');
    end if;
  end if;

  v_id_ncp := duc_ncp_so_quan_ly_moi();

  insert into duc_ncp (
    id_ncp, id_checkpoint_goc, ngay_tao, ma_may, ma_sp, ten_sp, so_khuon, mo_ta_loi,
    so_luong_nghi_van, so_luong_ng_du_kien, vi_tri_cach_ly, nguoi_mo_case,
    nguoi_dam_nhiem, nguoi_dam_nhiem_doi_sach, han_tra_loi_doi_sach, nguoi_mo_uid,
    so_luong_da_loc, so_luong_loc_ok, so_luong_loc_ng, so_luong_sua_ok, so_luong_sua_khong_duoc,
    so_luong_de_nghi_phe, so_luong_phe_da_duyet, trang_thai, rc_trang_thai_duyet, ghi_chu, last_updated_at
  ) values (
    v_id_ncp, nullif(p_id_checkpoint_goc, ''), v_now, p_ma_may, p_ma_sp, p_ten_sp, p_so_khuon, trim(p_mo_ta_loi),
    p_so_luong_nghi_van, p_so_luong_ng_du_kien, trim(p_vi_tri_cach_ly), p_user,
    trim(p_nguoi_dam_nhiem), trim(p_nguoi_dam_nhiem_doi_sach), p_han_tra_loi_doi_sach, auth.uid(),
    0, 0, 0, 0, 0, 0, 0, 'da_cach_ly', 'nhap',
    '[' || to_char(v_now at time zone 'Asia/Ho_Chi_Minh', 'DD/MM HH24:MI') || '] Mở phiếu, cách ly ' ||
      p_so_luong_nghi_van || ' SP tại "' || trim(p_vi_tri_cach_ly) || '" — bởi ' || p_user,
    v_now
  );

  if p_id_checkpoint_goc is not null and p_id_checkpoint_goc <> '' then
    update duc_ipqc_checkpoint set id_ncp_lien_quan = v_id_ncp where id_checkpoint = p_id_checkpoint_goc;
  end if;

  return jsonb_build_object('ok', true, 'id_ncp', v_id_ncp);
end;
$function$
;
revoke execute on function public.duc_ncp_open_case(p_id_checkpoint_goc text, p_ma_may text, p_ma_sp text, p_ten_sp text, p_so_khuon text, p_mo_ta_loi text, p_so_luong_nghi_van numeric, p_so_luong_ng_du_kien numeric, p_vi_tri_cach_ly text, p_nguoi_dam_nhiem text, p_nguoi_dam_nhiem_doi_sach text, p_user text, p_han_tra_loi_doi_sach date) from public,anon;
grant execute on function public.duc_ncp_open_case(p_id_checkpoint_goc text, p_ma_may text, p_ma_sp text, p_ten_sp text, p_so_khuon text, p_mo_ta_loi text, p_so_luong_nghi_van numeric, p_so_luong_ng_du_kien numeric, p_vi_tri_cach_ly text, p_nguoi_dam_nhiem text, p_nguoi_dam_nhiem_doi_sach text, p_user text, p_han_tra_loi_doi_sach date) to authenticated;

CREATE OR REPLACE FUNCTION public.duc_ncp_open_source(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare product public.master_products%rowtype; result jsonb; existing text; actor text; assignee text; response_owner text; source text:=p_data->>'source_type'; customer_code text; customer_name text;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 if source is null or source not in ('machine','department','customer') then raise exception 'Chọn nguồn phát sinh';end if;
 if coalesce(p_data->>'quantity','') !~ '^[0-9]+([.][0-9]+)?$' or coalesce(p_data->>'ng_quantity','0') !~ '^[0-9]+([.][0-9]+)?$' then raise exception 'Số lượng phải là số hữu hạn không âm';end if;
 if nullif(p_data->>'request_id','') is null then raise exception 'Thiếu mã phiên tạo phiếu';end if;
 perform pg_advisory_xact_lock(hashtextextended('ncp-source:'||(p_data->>'request_id'),0));
 select id_ncp into existing from duc_ncp where source_request_id=(p_data->>'request_id')::uuid;
 if found then return jsonb_build_object('ok',true,'id_ncp',existing,'existing',true);end if;
 select * into product from master_products where ma_sp=p_data->>'product_code';if not found then raise exception 'Chọn sản phẩm từ danh mục';end if;
 if source='machine' and (nullif(trim(p_data->>'machine'),'') is null or nullif(trim(p_data->>'mold'),'') is null) then raise exception 'Nguồn máy đúc cần máy và số khuôn';end if;
 if source='machine' and not exists(select 1 from master_machines where ma_may=p_data->>'machine') then raise exception 'Máy không có trong danh mục';end if;
 if source='department' and nullif(trim(p_data->>'department'),'') is null then raise exception 'Chọn bộ phận/công đoạn';end if;
 if source='customer' then
   select ma_khach_hang,ten_khach_hang into customer_code,customer_name from master_products
   where coalesce(nullif(ma_khach_hang,''),ten_khach_hang)=p_data->>'customer' limit 1;
   if not found then raise exception 'Chọn khách hàng từ danh mục hiện có';end if;
 end if;
 select coalesce(full_name,username,email) into actor from user_roles where user_id=auth.uid();
 select coalesce(full_name,username) into assignee from user_roles where username=p_data->>'assignee';
 if not found then raise exception 'Chọn người đảm nhiệm từ tài khoản trung tâm';end if;
 select coalesce(full_name,username) into response_owner from user_roles where username=p_data->>'response_owner';
 if not found then raise exception 'Chọn người trả lời đối sách từ tài khoản trung tâm';end if;
 if nullif(trim(p_data->>'description'),'') is null or nullif(trim(p_data->>'location'),'') is null then raise exception 'Nhập mô tả và vị trí cách ly';end if;
 if p_data ? 'images' and jsonb_typeof(p_data->'images')<>'array' then raise exception 'Ảnh không hợp lệ';end if;
 if jsonb_array_length(coalesce(p_data->'images','[]'))>10 then raise exception 'Tối đa 10 ảnh';end if;
 if exists(select 1 from jsonb_array_elements_text(coalesce(p_data->'images','[]')) img where img is null or img !~ '^https://[^ ]+$') then raise exception 'Liên kết ảnh không hợp lệ';end if;
 result:=duc_ncp_open_case(null,case when source='machine' then p_data->>'machine' else '' end,product.ma_sp,product.ten_sp,case when source='machine' then p_data->>'mold' else '' end,p_data->>'description',(p_data->>'quantity')::numeric,coalesce((p_data->>'ng_quantity')::numeric,0),p_data->>'location',assignee,response_owner,coalesce(actor,'MES'),nullif(p_data->>'response_due','')::date);
 if coalesce((result->>'ok')::boolean,false)=false then raise exception '%',result->>'error';end if;
 update duc_ncp set source_type=source,source_department=nullif(trim(p_data->>'department'),''),source_customer_code=customer_code,source_customer_name=customer_name,source_images=coalesce(p_data->'images','[]'),source_request_id=(p_data->>'request_id')::uuid where id_ncp=result->>'id_ncp';
 return result;
end $function$
;
revoke execute on function public.duc_ncp_open_source(p_data jsonb) from public,anon;
grant execute on function public.duc_ncp_open_source(p_data jsonb) to authenticated;

drop function public.duc_ncp_update_root_cause(text,text,text,text,jsonb,jsonb,jsonb,jsonb,jsonb,jsonb,text);
CREATE OR REPLACE FUNCTION public.duc_ncp_update_root_cause(p_id_ncp text, p_nguoi_dam_nhiem_doi_sach text, p_nguyen_nhan_phat_sinh text, p_nguyen_nhan_luu_xuat text, p_hinh_anh_phat_sinh jsonb, p_hinh_anh_luu_xuat jsonb, p_doi_sach_ps_tam_thoi jsonb, p_doi_sach_ps_lau_dai jsonb, p_doi_sach_lx_tam_thoi jsonb, p_doi_sach_lx_lau_dai jsonb, p_user text, p_han_tra_loi_doi_sach date default null)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public
AS $function$
declare
  v_trang_thai_duyet text;
  v_now timestamptz := now();
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
  select coalesce(nullif(trim(username),''),email) into p_user from user_roles where user_id=auth.uid();
    select coalesce(rc_trang_thai_duyet, 'nhap') into v_trang_thai_duyet from duc_ncp where id_ncp = p_id_ncp;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu: ' || p_id_ncp); end if;
  if v_trang_thai_duyet in ('cho_duyet', 'da_duyet') then
    return jsonb_build_object('ok', false, 'error', 'Phiếu đang ở trạng thái "' ||
      (case when v_trang_thai_duyet = 'cho_duyet' then 'Chờ duyệt' else 'Đã duyệt' end) ||
      '" — bấm "Mở lại để chỉnh sửa" trước khi sửa.');
  end if;

  update duc_ncp set
    nguoi_dam_nhiem_doi_sach = trim(coalesce(p_nguoi_dam_nhiem_doi_sach, '')),
    nguyen_nhan_phat_sinh = trim(coalesce(p_nguyen_nhan_phat_sinh, '')),
    nguyen_nhan_luu_xuat = trim(coalesce(p_nguyen_nhan_luu_xuat, '')),
    hinh_anh_phat_sinh_json = coalesce(p_hinh_anh_phat_sinh, '[]'::jsonb),
    hinh_anh_luu_xuat_json = coalesce(p_hinh_anh_luu_xuat, '[]'::jsonb),
    doi_sach_ps_tam_thoi_json = coalesce(p_doi_sach_ps_tam_thoi, '[]'::jsonb),
    doi_sach_ps_lau_dai_json = coalesce(p_doi_sach_ps_lau_dai, '[]'::jsonb),
    doi_sach_lx_tam_thoi_json = coalesce(p_doi_sach_lx_tam_thoi, '[]'::jsonb),
    doi_sach_lx_lau_dai_json = coalesce(p_doi_sach_lx_lau_dai, '[]'::jsonb),
    han_tra_loi_doi_sach = coalesce(p_han_tra_loi_doi_sach, han_tra_loi_doi_sach),
    last_updated_at = v_now
  where id_ncp = p_id_ncp;
  perform duc_ncp_append_log(p_id_ncp, 'Cập nhật Nguyên nhân & Đối sách, hạn ' || coalesce(to_char(p_han_tra_loi_doi_sach,'DD/MM/YYYY'),'giữ nguyên') || ' — bởi ' || p_user);

  return jsonb_build_object('ok', true, 'id_ncp', p_id_ncp);
end;
$function$
;
revoke execute on function public.duc_ncp_update_root_cause(p_id_ncp text, p_nguoi_dam_nhiem_doi_sach text, p_nguyen_nhan_phat_sinh text, p_nguyen_nhan_luu_xuat text, p_hinh_anh_phat_sinh jsonb, p_hinh_anh_luu_xuat jsonb, p_doi_sach_ps_tam_thoi jsonb, p_doi_sach_ps_lau_dai jsonb, p_doi_sach_lx_tam_thoi jsonb, p_doi_sach_lx_lau_dai jsonb, p_user text, p_han_tra_loi_doi_sach date) from public,anon;
grant execute on function public.duc_ncp_update_root_cause(p_id_ncp text, p_nguoi_dam_nhiem_doi_sach text, p_nguyen_nhan_phat_sinh text, p_nguyen_nhan_luu_xuat text, p_hinh_anh_phat_sinh jsonb, p_hinh_anh_luu_xuat jsonb, p_doi_sach_ps_tam_thoi jsonb, p_doi_sach_ps_lau_dai jsonb, p_doi_sach_lx_tam_thoi jsonb, p_doi_sach_lx_lau_dai jsonb, p_user text, p_han_tra_loi_doi_sach date) to authenticated;

create or replace function public.ncp_dong_nhac_han() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if new.han_tra_loi_doi_sach is distinct from old.han_tra_loi_doi_sach or ncp_da_tra_loi(new) then
  perform cv_pd_xong('ncp-han:'||new.id_ncp||':',true);
 end if;
 return new;
end $$;
revoke all on function public.ncp_dong_nhac_han() from public,anon,authenticated;
create trigger ncp_dong_nhac_han after update on public.duc_ncp for each row execute function public.ncp_dong_nhac_han();
commit;
