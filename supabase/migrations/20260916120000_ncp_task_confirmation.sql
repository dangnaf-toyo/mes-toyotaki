-- Xác nhận Task No. trước khi cách ly NCP.
-- Task No. của MES là duc_tem.tag_no; LOT được lưu riêng để truy vết.

alter table public.duc_tem_cach_ly
  add column if not exists lot_no text,
  add column if not exists so_luong_cach_ly numeric;

update public.duc_tem_cach_ly cl
set lot_no = coalesce(cl.lot_no, t.lot),
    so_luong_cach_ly = coalesce(cl.so_luong_cach_ly, t.so_luong)
from public.duc_tem t
where t.tag_no = cl.tag_no;

create or replace function public.duc_ncp_xac_nhan_task(p_task_no text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_task public.duc_tem%rowtype;
  v_vi_tri text;
  v_ncp_hold text;
begin
  if p_task_no is null or trim(p_task_no) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu Task No.');
  end if;

  select * into v_task
  from public.duc_tem
  where tag_no = trim(p_task_no);
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Task No. không tồn tại trong dữ liệu sản xuất/MES');
  end if;

  if v_task.trang_thai = 'Hủy' then
    return jsonb_build_object('ok', false, 'error', 'Task đã hủy, không thể cách ly');
  end if;
  if coalesce(v_task.so_luong, 0) <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Task No. không còn số lượng khả dụng');
  end if;

  select vi_tri_hien_tai into v_vi_tri
  from public.cd_v_vi_tri_hien_tai
  where tag_no = v_task.tag_no;
  v_ncp_hold := public.duc_tem_id_ncp_cach_ly(v_task.tag_no);

  return jsonb_build_object(
    'ok', true,
    'task_no', v_task.tag_no,
    'ma_sp', v_task.ma_sp,
    'ten_sp', v_task.ten_sp,
    'lot', v_task.lot,
    'may_cong_doan', coalesce(v_vi_tri, v_task.may_tt, v_task.may_duc_chi_thi, 'Đúc'),
    'so_luong', v_task.so_luong,
    'dang_hold', v_ncp_hold is not null,
    'id_ncp_hold', v_ncp_hold
  );
end;
$$;

revoke execute on function public.duc_ncp_xac_nhan_task(text) from public, anon;
grant execute on function public.duc_ncp_xac_nhan_task(text) to authenticated;

-- Ghi snapshot LOT và số lượng tại đúng thời điểm HOLD.
create or replace function public.duc_ncp_cach_ly_task(p_id_ncp text, p_tag_no text, p_user text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_code text := trim(p_tag_no);
  v_ncp public.duc_ncp%rowtype;
  v_task public.duc_tem%rowtype;
  v_position text;
  v_active_ncp text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  p_user := coalesce(nullif(auth.jwt()->>'email', ''), auth.uid()::text);
  if v_code is null or v_code = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu Task No.'); end if;
  select * into v_ncp from public.duc_ncp where id_ncp = p_id_ncp;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu: ' || p_id_ncp); end if;

  select * into v_task from public.duc_tem where tag_no = v_code for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Task No. không tồn tại trong dữ liệu sản xuất/MES'); end if;
  if v_task.trang_thai = 'Hủy' then return jsonb_build_object('ok', false, 'error', 'Task đã hủy, không thể cách ly'); end if;
  if coalesce(v_task.so_luong, 0) <= 0 then return jsonb_build_object('ok', false, 'error', 'Task No. không còn số lượng khả dụng'); end if;

  select id_ncp into v_active_ncp from public.duc_tem_cach_ly
  where tag_no = v_code and trang_thai = 'dang_cach_ly';
  if v_active_ncp is not null then
    return jsonb_build_object('ok', false, 'error', case when v_active_ncp = p_id_ncp
      then 'Task này đã được cách ly theo đúng phiếu NCP này'
      else 'Task đang bị cách ly theo phiếu NCP khác (' || v_active_ncp || ')' end);
  end if;

  select vi_tri_hien_tai into v_position from public.cd_v_vi_tri_hien_tai where tag_no = v_code;
  insert into public.duc_tem_cach_ly(
    tag_no, id_ncp, trang_thai, nguoi_cach_ly, thoi_diem_cach_ly,
    ma_doi_tuong, loai_doi_tuong, ma_sp, ten_sp, cong_doan_hien_tai,
    ly_do_cach_ly, lot_no, so_luong_cach_ly
  ) values (
    v_task.tag_no, p_id_ncp, 'dang_cach_ly', p_user, now(),
    v_task.tag_no, 'TASK', v_task.ma_sp, v_task.ten_sp,
    coalesce(v_position, v_task.may_tt, v_task.may_duc_chi_thi, 'Đúc'),
    coalesce(nullif(trim(v_ncp.mo_ta_loi), ''), 'Cách ly theo phiếu NCP ' || p_id_ncp),
    v_task.lot, v_task.so_luong
  );

  perform public.duc_ncp_append_log(p_id_ncp,
    'HOLD Task ' || v_task.tag_no || ' — LOT ' || coalesce(v_task.lot, '—') ||
    ' — SL ' || coalesce(v_task.so_luong, 0) || ' — bởi ' || p_user);
  return jsonb_build_object('ok', true, 'task_no', v_task.tag_no, 'lot', v_task.lot,
    'so_luong_cach_ly', v_task.so_luong, 'trang_thai', 'HOLD');
end;
$$;

revoke execute on function public.duc_ncp_cach_ly_task(text,text,text) from public, anon;
grant execute on function public.duc_ncp_cach_ly_task(text,text,text) to authenticated;

notify pgrst, 'reload schema';
