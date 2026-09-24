-- Đồng bộ cách ly NCP vào MES và khóa mọi đường đi của tem/LOT đang HOLD.
-- Mở rộng cấu trúc T35, không tạo một hệ trạng thái cách ly song song.

alter table public.duc_tem_cach_ly
  add column if not exists ma_doi_tuong text,
  add column if not exists loai_doi_tuong text,
  add column if not exists ma_sp text,
  add column if not exists ten_sp text,
  add column if not exists cong_doan_hien_tai text,
  add column if not exists ly_do_cach_ly text,
  add column if not exists ly_do_giai_toa text;

comment on column public.duc_tem_cach_ly.trang_thai is
  'dang_cach_ly = HOLD/QUARANTINE/BLOCKED; da_giai_toa = RELEASED';

create table if not exists public.duc_tem_cach_ly_audit (
  id bigserial primary key,
  id_cach_ly bigint not null references public.duc_tem_cach_ly(id),
  id_ncp text not null,
  tag_no text not null,
  ma_doi_tuong text,
  su_kien text not null check (su_kien in ('HOLD', 'RELEASE')),
  trang_thai_mes text not null check (trang_thai_mes in ('HOLD', 'RELEASED')),
  ma_sp text,
  ten_sp text,
  cong_doan_hien_tai text,
  ly_do text,
  nguoi_thao_tac text,
  thoi_diem timestamptz not null default now()
);

create index if not exists idx_tem_cach_ly_audit_tag
  on public.duc_tem_cach_ly_audit(tag_no, thoi_diem desc);
create index if not exists idx_tem_cach_ly_audit_ncp
  on public.duc_tem_cach_ly_audit(id_ncp, thoi_diem desc);

create or replace function public.duc_tem_cach_ly_audit_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.duc_tem_cach_ly_audit(
      id_cach_ly, id_ncp, tag_no, ma_doi_tuong, su_kien, trang_thai_mes,
      ma_sp, ten_sp, cong_doan_hien_tai, ly_do, nguoi_thao_tac, thoi_diem
    ) values (
      new.id, new.id_ncp, new.tag_no, new.ma_doi_tuong, 'HOLD', 'HOLD',
      new.ma_sp, new.ten_sp, new.cong_doan_hien_tai, new.ly_do_cach_ly,
      new.nguoi_cach_ly, new.thoi_diem_cach_ly
    );
  elsif old.trang_thai = 'dang_cach_ly' and new.trang_thai = 'da_giai_toa' then
    insert into public.duc_tem_cach_ly_audit(
      id_cach_ly, id_ncp, tag_no, ma_doi_tuong, su_kien, trang_thai_mes,
      ma_sp, ten_sp, cong_doan_hien_tai, ly_do, nguoi_thao_tac, thoi_diem
    ) values (
      new.id, new.id_ncp, new.tag_no, new.ma_doi_tuong, 'RELEASE', 'RELEASED',
      new.ma_sp, new.ten_sp, new.cong_doan_hien_tai, new.ly_do_giai_toa,
      new.nguoi_giai_toa, new.thoi_diem_giai_toa
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_duc_tem_cach_ly_audit on public.duc_tem_cach_ly;
create trigger trg_duc_tem_cach_ly_audit
after insert or update of trang_thai on public.duc_tem_cach_ly
for each row execute function public.duc_tem_cach_ly_audit_trigger();

-- Bổ sung snapshot cho các dòng T35 đã tồn tại, không thay đổi trạng thái của chúng.
update public.duc_tem_cach_ly cl
set ma_doi_tuong = coalesce(cl.ma_doi_tuong, cl.tag_no),
    loai_doi_tuong = coalesce(cl.loai_doi_tuong, 'TEM'),
    ma_sp = coalesce(cl.ma_sp, t.ma_sp),
    ten_sp = coalesce(cl.ten_sp, t.ten_sp),
    cong_doan_hien_tai = coalesce(cl.cong_doan_hien_tai, pos.vi_tri_hien_tai),
    ly_do_cach_ly = coalesce(cl.ly_do_cach_ly, nullif(trim(n.mo_ta_loi), ''), 'Cách ly theo phiếu NCP ' || cl.id_ncp),
    ly_do_giai_toa = case
      when cl.trang_thai = 'da_giai_toa' then coalesce(cl.ly_do_giai_toa, 'Đã giải toả trước khi bổ sung nhật ký MES')
      else cl.ly_do_giai_toa
    end
from public.duc_tem t
left join public.cd_v_vi_tri_hien_tai pos on pos.tag_no = t.tag_no,
public.duc_ncp n
where t.tag_no = cl.tag_no and n.id_ncp = cl.id_ncp;

-- Giữ được lịch sử cách ly cũ khi nâng cấp, đồng thời chạy lại migration không nhân đôi.
insert into public.duc_tem_cach_ly_audit(
  id_cach_ly, id_ncp, tag_no, ma_doi_tuong, su_kien, trang_thai_mes,
  ma_sp, ten_sp, cong_doan_hien_tai, ly_do, nguoi_thao_tac, thoi_diem
)
select cl.id, cl.id_ncp, cl.tag_no, cl.ma_doi_tuong, 'HOLD', 'HOLD',
  cl.ma_sp, cl.ten_sp, cl.cong_doan_hien_tai, cl.ly_do_cach_ly,
  cl.nguoi_cach_ly, cl.thoi_diem_cach_ly
from public.duc_tem_cach_ly cl
where not exists (
  select 1 from public.duc_tem_cach_ly_audit a
  where a.id_cach_ly = cl.id and a.su_kien = 'HOLD'
);

insert into public.duc_tem_cach_ly_audit(
  id_cach_ly, id_ncp, tag_no, ma_doi_tuong, su_kien, trang_thai_mes,
  ma_sp, ten_sp, cong_doan_hien_tai, ly_do, nguoi_thao_tac, thoi_diem
)
select cl.id, cl.id_ncp, cl.tag_no, cl.ma_doi_tuong, 'RELEASE', 'RELEASED',
  cl.ma_sp, cl.ten_sp, cl.cong_doan_hien_tai, cl.ly_do_giai_toa,
  cl.nguoi_giai_toa, cl.thoi_diem_giai_toa
from public.duc_tem_cach_ly cl
where cl.trang_thai = 'da_giai_toa'
  and not exists (
    select 1 from public.duc_tem_cach_ly_audit a
    where a.id_cach_ly = cl.id and a.su_kien = 'RELEASE'
  );

-- Nhận cả Tag No và LOT. Với LOT, toàn bộ tem thuộc LOT được HOLD trong một giao dịch.
create or replace function public.duc_ncp_cach_ly_tem(p_id_ncp text, p_tag_no text, p_user text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_code text := trim(p_tag_no);
  v_ncp public.duc_ncp%rowtype;
  v_conflict text;
  v_count integer;
begin
  if v_code is null or v_code = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu mã tem/LOT');
  end if;
  select * into v_ncp from public.duc_ncp where id_ncp = p_id_ncp;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu: ' || p_id_ncp); end if;
  if not exists (select 1 from public.duc_tem where tag_no = v_code or lot = v_code) then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem/LOT: ' || v_code);
  end if;

  select cl.id_ncp into v_conflict
  from public.duc_tem t join public.duc_tem_cach_ly cl on cl.tag_no = t.tag_no and cl.trang_thai = 'dang_cach_ly'
  where (t.tag_no = v_code or t.lot = v_code) and cl.id_ncp <> p_id_ncp limit 1;
  if v_conflict is not null then
    return jsonb_build_object('ok', false, 'error', 'Tem/LOT đang bị cách ly theo phiếu khác (' || v_conflict || ')');
  end if;

  insert into public.duc_tem_cach_ly(
    tag_no, id_ncp, trang_thai, nguoi_cach_ly, thoi_diem_cach_ly,
    ma_doi_tuong, loai_doi_tuong, ma_sp, ten_sp, cong_doan_hien_tai, ly_do_cach_ly
  )
  select t.tag_no, p_id_ncp, 'dang_cach_ly', p_user, now(), v_code,
    case when t.tag_no = v_code then 'TEM' else 'LOT' end,
    t.ma_sp, t.ten_sp, pos.vi_tri_hien_tai,
    coalesce(nullif(trim(v_ncp.mo_ta_loi), ''), 'Cách ly theo phiếu NCP ' || p_id_ncp)
  from public.duc_tem t
  left join public.cd_v_vi_tri_hien_tai pos on pos.tag_no = t.tag_no
  where (t.tag_no = v_code or t.lot = v_code)
    and not exists (
      select 1 from public.duc_tem_cach_ly cl
      where cl.tag_no = t.tag_no and cl.trang_thai = 'dang_cach_ly'
    );
  get diagnostics v_count = row_count;
  if v_count = 0 then
    return jsonb_build_object('ok', false, 'error', 'Tem/LOT này đã HOLD theo đúng phiếu NCP này');
  end if;

  perform public.duc_ncp_append_log(p_id_ncp, 'HOLD ' || v_code || ' (' || v_count || ' tem) — bởi ' || p_user);
  return jsonb_build_object('ok', true, 'ma_doi_tuong', v_code, 'so_tem_hold', v_count, 'trang_thai', 'HOLD');
end;
$$;

-- Release có lý do và chỉ hợp lệ sau khi đối sách đã được duyệt.
create or replace function public.duc_ncp_giai_toa_tem_v2(
  p_id_ncp text, p_tag_no text, p_user text, p_ly_do text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_approval text;
  v_updated integer;
  v_reason text := nullif(trim(p_ly_do), '');
begin
  select rc_trang_thai_duyet into v_approval from public.duc_ncp where id_ncp = p_id_ncp for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu ' || p_id_ncp); end if;
  if v_approval is distinct from 'da_duyet' then
    return jsonb_build_object('ok', false, 'error', 'Chỉ được Release sau khi đối sách NCP đã được phê duyệt');
  end if;
  if v_reason is null then
    return jsonb_build_object('ok', false, 'error', 'Bắt buộc nhập lý do Release');
  end if;

  update public.duc_tem_cach_ly
  set trang_thai = 'da_giai_toa', nguoi_giai_toa = p_user,
      thoi_diem_giai_toa = now(), ly_do_giai_toa = v_reason
  where tag_no = p_tag_no and id_ncp = p_id_ncp and trang_thai = 'dang_cach_ly';
  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy cách ly đang mở cho tem ' || p_tag_no || ' theo phiếu này');
  end if;
  perform public.duc_ncp_append_log(p_id_ncp, 'RELEASE tem ' || p_tag_no || ': ' || v_reason || ' — bởi ' || p_user);
  return jsonb_build_object('ok', true, 'tag_no', p_tag_no, 'trang_thai', 'RELEASED');
end;
$$;

-- Giữ RPC cũ tương thích, nhưng vẫn áp dụng điều kiện duyệt và ghi lý do chuẩn.
create or replace function public.duc_ncp_giai_toa_tem(p_id_ncp text, p_tag_no text, p_user text)
returns jsonb language sql security definer set search_path = public as $$
  select public.duc_ncp_giai_toa_tem_v2(p_id_ncp, p_tag_no, p_user, 'Release sau khi đối sách NCP được duyệt');
$$;

create or replace function public.oqc_them_tem_vao_pallet(
  p_id_pallet text, p_tag_no text, p_so_luong numeric, p_nguoi text
) returns void language plpgsql security definer set search_path = public as $$
declare v_trang_thai text; v_ncp text;
begin
  v_ncp := public.duc_tem_id_ncp_cach_ly(p_tag_no);
  if v_ncp is not null then
    raise exception 'Tem/LOT đang bị cách ly theo NCP %, không được đóng pallet', v_ncp;
  end if;
  select trang_thai into v_trang_thai from public.oqc_pallet where id_pallet = p_id_pallet for update;
  if not found then raise exception 'Không tìm thấy pallet %', p_id_pallet; end if;
  if v_trang_thai <> 'dang_dong_goi' then raise exception 'Pallet % đã đóng, không thêm được nữa', p_id_pallet; end if;
  insert into public.oqc_pallet_item(id_pallet, tag_no, so_luong, nguoi_quet)
  values (p_id_pallet, p_tag_no, p_so_luong, p_nguoi)
  on conflict (id_pallet, tag_no) do update
    set so_luong = excluded.so_luong, nguoi_quet = excluded.nguoi_quet, thoi_diem_quet = now();
  update public.oqc_pallet set tong_so_luong = (
    select coalesce(sum(so_luong), 0) from public.oqc_pallet_item where id_pallet = p_id_pallet
  ) where id_pallet = p_id_pallet;
end;
$$;

-- Chặn cả phiếu chuyển đã được tạo trước thời điểm tem bị HOLD.
create or replace function public.cd_xac_nhan_chuyen(
  p_id_phieu text, p_nguoi_giao text, p_ngay_gio_xac_nhan text
) returns void language plpgsql security definer set search_path = public as $$
declare v_tag text; v_ncp text;
begin
  select tag_no into v_tag from public.cd_chuyen_cong_doan_log where id_phieu = p_id_phieu for update;
  if not found then raise exception 'Không tìm thấy phiếu chuyển %', p_id_phieu; end if;
  v_ncp := public.duc_tem_id_ncp_cach_ly(v_tag);
  if v_ncp is not null then
    raise exception 'Tem/LOT đang bị cách ly theo NCP %, không được nhận hoặc xác nhận chuyển công đoạn', v_ncp;
  end if;
  update public.cd_chuyen_cong_doan_log
  set nguoi_giao = p_nguoi_giao,
      trang_thai_xac_nhan = 'Đã xác nhận chuyển công đoạn',
      ngay_gio_xac_nhan = p_ngay_gio_xac_nhan
  where id_phieu = p_id_phieu;
end;
$$;

create or replace function public.oqc_dong_pallet(p_id_pallet text)
returns void language plpgsql security definer set search_path = public as $$
declare v_tag text; v_ncp text;
begin
  select pi.tag_no, public.duc_tem_id_ncp_cach_ly(pi.tag_no) into v_tag, v_ncp
  from public.oqc_pallet_item pi
  where pi.id_pallet = p_id_pallet and public.duc_tem_id_ncp_cach_ly(pi.tag_no) is not null limit 1;
  if v_ncp is not null then
    raise exception 'Tem/LOT % đang bị cách ly theo NCP %, không được đóng pallet', v_tag, v_ncp;
  end if;
  update public.oqc_pallet set trang_thai = 'da_dong_goi', thoi_diem_dong_goi = now()
  where id_pallet = p_id_pallet and trang_thai = 'dang_dong_goi';
  if not found then raise exception 'Không tìm thấy pallet đang đóng gói %', p_id_pallet; end if;
end;
$$;

create or replace function public.oqc_pallet_nhap_kho(p_id_pallet text, p_nguoi text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_row public.oqc_pallet%rowtype; v_tag text; v_ncp text;
begin
  select * into v_row from public.oqc_pallet where id_pallet = p_id_pallet for update;
  if not found then raise exception 'Không tìm thấy pallet %', p_id_pallet; end if;
  select pi.tag_no, public.duc_tem_id_ncp_cach_ly(pi.tag_no) into v_tag, v_ncp
  from public.oqc_pallet_item pi
  where pi.id_pallet = p_id_pallet and public.duc_tem_id_ncp_cach_ly(pi.tag_no) is not null limit 1;
  if v_ncp is not null then
    raise exception 'Tem/LOT % trong pallet đang bị cách ly theo NCP %, không được nhập kho', v_tag, v_ncp;
  end if;
  if v_row.trang_thai = 'dang_dong_goi' then raise exception 'Pallet % chưa đóng gói xong, không nhập kho được', p_id_pallet; end if;
  if v_row.trang_thai = 'da_nhap_kho' then raise exception 'Pallet % đã nhập kho trước đó rồi', p_id_pallet; end if;
  if v_row.trang_thai = 'da_xuat' then raise exception 'Pallet % đã xuất kho rồi', p_id_pallet; end if;
  update public.oqc_pallet set trang_thai = 'da_nhap_kho', thoi_diem_nhap_kho = now() where id_pallet = p_id_pallet;
  return jsonb_build_object('ok', true, 'tong_so_luong', v_row.tong_so_luong);
end;
$$;

-- Bổ sung chốt cho luồng ghi nhận thùng Kanban.
create or replace function public.duc_ghi_nhan_tem_kanban(p_tag_no text, p_may_tt text, p_nguoi_tt text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_tem public.duc_tem%rowtype; v_may text; v_ncp text;
begin
  if p_tag_no is null or trim(p_tag_no) = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu Tag No'); end if;
  select * into v_tem from public.duc_tem where tag_no = trim(p_tag_no) for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || p_tag_no); end if;
  v_ncp := public.duc_tem_id_ncp_cach_ly(v_tem.tag_no);
  if v_ncp is not null then
    return jsonb_build_object('ok', false, 'error', 'Tem/LOT đang bị cách ly theo NCP ' || v_ncp || ', không được ghi nhận sản xuất', 'id_ncp', v_ncp, 'hold', true);
  end if;
  if v_tem.id_lo_chi_thi is null then return jsonb_build_object('ok', false, 'error', 'Tem ' || p_tag_no || ' không phải tem chỉ thị Kanban'); end if;
  if v_tem.trang_thai = 'Hủy' then return jsonb_build_object('ok', false, 'error', 'Tem ' || p_tag_no || ' đã bị hủy'); end if;
  if v_tem.trang_thai <> 'Chờ sản xuất' or v_tem.ngay_gio_ghi_nhan is not null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || p_tag_no || ' đã được ghi nhận lúc ' ||
      to_char(v_tem.ngay_gio_ghi_nhan at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ' bởi ' || coalesce(v_tem.nguoi_tt, '(không rõ)'), 'da_ghi_nhan', true);
  end if;
  v_may := coalesce(nullif(trim(p_may_tt), ''), v_tem.may_duc_chi_thi);
  update public.duc_tem set so_luong_tt = so_luong, so_khuon_tt = coalesce(so_khuon_tt, so_khuon),
    may_tt = v_may, nguoi_tt = p_nguoi_tt, ngay_gio_ghi_nhan = now(), ngay_gio_xuat = now(),
    trang_thai = 'Đã sản xuất', ghi_chu_sl = 'Đã ghi nhận Kanban' where tag_no = v_tem.tag_no;
  return jsonb_build_object('ok', true, 'tag_no', v_tem.tag_no, 'ma_sp', v_tem.ma_sp,
    'ten_sp', v_tem.ten_sp, 'so_luong', v_tem.so_luong, 'so_thung_stt', v_tem.so_thung_stt,
    'may_tt', v_may, 'doi_may', v_may is distinct from v_tem.may_duc_chi_thi, 'ngay_gio_ghi_nhan', now());
end;
$$;

alter table public.duc_tem_cach_ly enable row level security;
alter table public.duc_tem_cach_ly_audit enable row level security;
drop policy if exists "public read" on public.duc_tem_cach_ly_audit;
create policy "public read" on public.duc_tem_cach_ly_audit for select using (true);

revoke insert, update, delete on public.duc_tem_cach_ly_audit from anon, authenticated;
revoke execute on function public.duc_ncp_giai_toa_tem_v2(text,text,text,text) from anon;
grant execute on function public.duc_ncp_giai_toa_tem_v2(text,text,text,text) to authenticated;
grant execute on function public.duc_ncp_cach_ly_tem(text,text,text) to authenticated;
grant execute on function public.cd_xac_nhan_chuyen(text,text,text) to authenticated;
grant execute on function public.oqc_them_tem_vao_pallet(text,text,numeric,text) to authenticated;
grant execute on function public.oqc_dong_pallet(text) to authenticated;
grant execute on function public.oqc_pallet_nhap_kho(text,text) to authenticated;
grant execute on function public.duc_ghi_nhan_tem_kanban(text,text,text) to authenticated;

notify pgrst, 'reload schema';
