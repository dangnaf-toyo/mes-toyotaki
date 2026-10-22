-- T140: Đóng cảnh báo IPQC cũ (tồn lâu, chưa có đề nghị tiếp tục SX) — hàng loạt, bắt buộc lý do.
-- Cảnh báo ở trang ipqc-approval.html = duc_ipqc_checkpoint (ket_qua='CANH_BAO', trang_thai='da_kiem')
-- chưa có dòng duc_ipqc_continue_request.checkpoint_id tương ứng (MesIpqcFlow.warnings()).
-- KHÔNG sửa/xoá duc_ipqc_checkpoint: chỉ ghi 1 dòng "đã đóng" vào bảng mới, trang lọc bỏ các id này.
-- Mở lại = xoá mềm (mo_lai_luc) qua RPC, lịch sử giữ nguyên ở duc_ipqc_canh_bao_dong_log.
-- CHƯA CHẠY — chạy lần lượt trên staging rồi prod.

create table if not exists public.duc_ipqc_canh_bao_dong (
  id_checkpoint text primary key references public.duc_ipqc_checkpoint(id_checkpoint) on delete cascade,
  ly_do         text not null check (char_length(trim(ly_do)) >= 3),
  nguoi_dong    text not null,
  nguoi_dong_id uuid,
  dong_luc      timestamptz not null default now()
);

create table if not exists public.duc_ipqc_canh_bao_dong_log (
  id            bigserial primary key,
  id_checkpoint text not null,
  hanh_dong     text not null check (hanh_dong in ('dong', 'mo_lai')),
  ly_do         text not null,
  nguoi         text not null,
  nguoi_id      uuid,
  luc           timestamptz not null default now(),
  du_lieu       jsonb   -- ảnh chụp checkpoint lúc đóng (ma_may, ma_sp, thoi_diem_kiem_thuc_te, ghi_chu)
);
create index if not exists duc_ipqc_canh_bao_dong_log_cp_idx on public.duc_ipqc_canh_bao_dong_log(id_checkpoint, luc desc);

alter table public.duc_ipqc_canh_bao_dong enable row level security;
alter table public.duc_ipqc_canh_bao_dong_log enable row level security;
drop policy if exists duc_ipqc_canh_bao_dong_select on public.duc_ipqc_canh_bao_dong;
create policy duc_ipqc_canh_bao_dong_select on public.duc_ipqc_canh_bao_dong for select to authenticated using (true);
drop policy if exists duc_ipqc_canh_bao_dong_log_select on public.duc_ipqc_canh_bao_dong_log;
create policy duc_ipqc_canh_bao_dong_log_select on public.duc_ipqc_canh_bao_dong_log for select to authenticated using (true);
-- Ghi chỉ qua RPC security definer.
revoke insert, update, delete on public.duc_ipqc_canh_bao_dong, public.duc_ipqc_canh_bao_dong_log from anon, authenticated;
grant select on public.duc_ipqc_canh_bao_dong, public.duc_ipqc_canh_bao_dong_log to authenticated;

-- Đóng nhiều cảnh báo. Chỉ đóng checkpoint CANH_BAO đã kiểm, chưa có đề nghị, chưa đóng.
-- Trả về {ok, so_dong, bo_qua:[{id_checkpoint, ly_do}]}.
create or replace function public.duc_ipqc_dong_canh_bao_cu(p_ids text[], p_ly_do text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nguoi text;
  v_ly    text := trim(coalesce(p_ly_do, ''));
  v_id    text;
  v_cp    record;
  v_dong  int := 0;
  v_bo    jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if not public.has_role('admin', 'qc_manager') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ QC Manager hoặc admin được đóng cảnh báo');
  end if;
  if char_length(v_ly) < 3 then
    return jsonb_build_object('ok', false, 'error', 'Lý do bắt buộc, tối thiểu 3 ký tự');
  end if;
  if p_ids is null or cardinality(p_ids) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Chưa chọn cảnh báo nào');
  end if;
  if cardinality(p_ids) > 500 then
    return jsonb_build_object('ok', false, 'error', 'Tối đa 500 cảnh báo mỗi lần');
  end if;

  select coalesce(nullif(trim(r.full_name), ''), r.email, r.username) into v_nguoi
  from user_roles r where r.user_id = auth.uid() limit 1;
  v_nguoi := coalesce(v_nguoi, nullif(auth.jwt()->>'email', ''), auth.uid()::text);

  foreach v_id in array (select array_agg(distinct x) from unnest(p_ids) x) loop
    select id_checkpoint, ket_qua, trang_thai, ma_may, ma_sp, thoi_diem_kiem_thuc_te, ghi_chu
      into v_cp from duc_ipqc_checkpoint where id_checkpoint = v_id;
    if not found then
      v_bo := v_bo || jsonb_build_object('id_checkpoint', v_id, 'ly_do', 'Không tồn tại');
    elsif v_cp.ket_qua is distinct from 'CANH_BAO' or v_cp.trang_thai is distinct from 'da_kiem' then
      v_bo := v_bo || jsonb_build_object('id_checkpoint', v_id, 'ly_do', 'Không phải cảnh báo đã kiểm');
    elsif exists (select 1 from duc_ipqc_continue_request r where r.checkpoint_id = v_id) then
      v_bo := v_bo || jsonb_build_object('id_checkpoint', v_id, 'ly_do', 'Đã có đề nghị tiếp tục SX');
    elsif exists (select 1 from duc_ipqc_canh_bao_dong d where d.id_checkpoint = v_id) then
      v_bo := v_bo || jsonb_build_object('id_checkpoint', v_id, 'ly_do', 'Đã đóng trước đó');
    else
      insert into duc_ipqc_canh_bao_dong(id_checkpoint, ly_do, nguoi_dong, nguoi_dong_id)
        values (v_id, v_ly, v_nguoi, auth.uid());
      insert into duc_ipqc_canh_bao_dong_log(id_checkpoint, hanh_dong, ly_do, nguoi, nguoi_id, du_lieu)
        values (v_id, 'dong', v_ly, v_nguoi, auth.uid(), jsonb_build_object(
          'ma_may', v_cp.ma_may, 'ma_sp', v_cp.ma_sp,
          'thoi_diem_kiem_thuc_te', v_cp.thoi_diem_kiem_thuc_te, 'ghi_chu', v_cp.ghi_chu));
      v_dong := v_dong + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'so_dong', v_dong, 'bo_qua', v_bo);
end;
$$;

-- Mở lại cảnh báo đã đóng nhầm (cùng quyền, cùng yêu cầu lý do). Lịch sử vẫn giữ trong _log.
create or replace function public.duc_ipqc_mo_lai_canh_bao(p_id text, p_ly_do text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nguoi text;
  v_ly    text := trim(coalesce(p_ly_do, ''));
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if not public.has_role('admin', 'qc_manager') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ QC Manager hoặc admin được mở lại cảnh báo');
  end if;
  if char_length(v_ly) < 3 then
    return jsonb_build_object('ok', false, 'error', 'Lý do bắt buộc, tối thiểu 3 ký tự');
  end if;
  select coalesce(nullif(trim(r.full_name), ''), r.email, r.username) into v_nguoi
  from user_roles r where r.user_id = auth.uid() limit 1;
  v_nguoi := coalesce(v_nguoi, nullif(auth.jwt()->>'email', ''), auth.uid()::text);
  delete from duc_ipqc_canh_bao_dong where id_checkpoint = p_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'Cảnh báo chưa bị đóng'); end if;
  insert into duc_ipqc_canh_bao_dong_log(id_checkpoint, hanh_dong, ly_do, nguoi, nguoi_id)
    values (p_id, 'mo_lai', v_ly, v_nguoi, auth.uid());
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.duc_ipqc_dong_canh_bao_cu(text[], text) from public, anon;
revoke all on function public.duc_ipqc_mo_lai_canh_bao(text, text) from public, anon;
grant execute on function public.duc_ipqc_dong_canh_bao_cu(text[], text) to authenticated;
grant execute on function public.duc_ipqc_mo_lai_canh_bao(text, text) to authenticated;

notify pgrst, 'reload schema';
