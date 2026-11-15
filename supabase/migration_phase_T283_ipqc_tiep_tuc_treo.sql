-- T283 (R25): Yêu cầu "tiếp tục SX" IPQC không còn treo vô hạn + dọn checkpoint mồ côi đủ trường hợp.
-- (1) Yêu cầu Chờ duyệt / Đang duyệt:
--     - quá 24 giờ không ai xử lý → nhắc lại người duyệt bước hiện tại, mỗi 24 giờ một lần;
--     - quá 72 giờ không ai xử lý → tự chuyển "Hết hiệu lực" (ghi audit TỰ HẾT HẠN DUYỆT),
--       chuông báo người tạo + QL Chất lượng. Muốn chạy tiếp thì tạo yêu cầu mới.
--     Mốc "xử lý gần nhất" = max(tạo yêu cầu, lần duyệt bước gần nhất).
-- (2) duc_ipqc_don_checkpoint_mo_coi:
--     - phiên kiểm mở quá 24 giờ (bỏ dở) không còn chặn việc dọn;
--     - checkpoint không gắn dòng ca (id_dong null, vd máy Kẽm) quá 24 giờ cũng được dọn;
--     - có phiếu bị dọn → 1 chuông báo QL Chất lượng (mỗi lần quét).
-- Chạy cùng cron duc_ipqc_nhac_cham (10 phút/lần).

create or replace function public.duc_ipqc_continue_quet_treo()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  q duc_ipqc_continue_request%rowtype;
  v_khoa text;
  v_n_nhac int := 0;
  v_n_het int := 0;
  v_ngay text := to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYYMMDD');
begin
  -- Tắt chuông nhắc của yêu cầu không còn chờ duyệt
  for r in
    select distinct x.id from duc_ipqc_continue_request x
    join cv_thong_bao t on t.khoa like 'ipqc-nhac:' || x.id || ':%' and t.can_xu_ly and not t.da_xu_ly
    where x.status not in ('Chờ duyệt', 'Đang duyệt')
  loop
    perform cv_pd_xong('ipqc-nhac:' || r.id || ':', true);
  end loop;

  for r in
    select x.id, greatest(x.created_at,
             coalesce((select max(a.decided_at) from duc_ipqc_continue_approval a where a.request_id = x.id), x.created_at)) moc
    from duc_ipqc_continue_request x
    where x.status in ('Chờ duyệt', 'Đang duyệt')
  loop
    select * into q from duc_ipqc_continue_request where id = r.id and status in ('Chờ duyệt', 'Đang duyệt') for update;
    if not found then continue; end if;
    if r.moc <= now() - interval '72 hours' then
      update duc_ipqc_continue_request set status = 'Hết hiệu lực', expired_at = now() where id = r.id;
      insert into duc_ipqc_continue_audit(request_id, action, actor_id, actor_name, detail)
      values (r.id, 'TỰ HẾT HẠN DUYỆT', null, 'Hệ thống',
        jsonb_build_object('step', q.current_step, 'cho_tu', r.moc, 'ly_do', 'Quá 72 giờ không ai duyệt'));
      perform cv_pd_xong('ipqc-nhac:' || r.id || ':', true);
      perform cv_pd_gui(
        (select coalesce(array_agg(distinct x), '{}') from unnest(array[q.requester_id] || cv_pd_ds_role(array['qc_manager'])) x where x is not null),
        'ipqc', 'het_han_duyet', 'ipqc-het:' || r.id, 'ipqc-approval.html?requestId=' || r.id,
        cv_pd_ipqc_mo_ta(q) || ' quá 72 giờ không ai duyệt (bước ' || q.current_step
          || ') → tự hết hiệu lực. Cần chạy tiếp thì tạo yêu cầu mới.', false);
      v_n_het := v_n_het + 1;
    elsif r.moc <= now() - interval '24 hours' then
      v_khoa := 'ipqc-nhac:' || r.id || ':' || q.current_step || ':' || v_ngay;
      if not exists (select 1 from cv_thong_bao t where t.khoa = v_khoa) then
        perform cv_pd_xong('ipqc-nhac:' || r.id || ':', true);
        perform cv_pd_gui(cv_pd_ds_role(duc_ipqc_step_roles(q.current_step)), 'ipqc', 'nhac_duyet', v_khoa,
          'ipqc-approval.html?requestId=' || r.id,
          cv_pd_ipqc_mo_ta(q) || ' chờ bạn duyệt đã '
            || floor(extract(epoch from now() - r.moc) / 3600)::int || ' giờ (bước ' || q.current_step
            || '). Quá 72 giờ sẽ tự hết hiệu lực.', true);
        v_n_nhac := v_n_nhac + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('nhac', v_n_nhac, 'het_hieu_luc', v_n_het);
end;
$$;

create or replace function public.duc_ipqc_don_checkpoint_mo_coi()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v_n int; v_ds text;
begin
  with don as (
    update duc_ipqc_checkpoint cp
       set trang_thai = 'het_hieu_luc',
           ghi_chu = concat_ws(E'\n', nullif(cp.ghi_chu, ''),
             case when cp.id_dong is null
               then '[T283: không gắn dòng ca, chờ kiểm quá 24 giờ — tự hết hiệu lực]'
               else '[T232: dòng ca ' || cp.id_dong || ' không còn (máy đổi SP / dừng) — tự hết hiệu lực]' end)
     where cp.trang_thai = 'cho_kiem'
       and cp.thoi_diem_tao < now() - interval '24 hours'
       and (cp.id_dong is null or not exists (select 1 from duc_ca_hien_tai c where c.id_dong = cp.id_dong))
       and not exists (select 1 from duc_ipqc_inspection_session ss
                       where ss.checkpoint_id = cp.id_checkpoint and ss.completed_at is null
                         and ss.started_at > now() - interval '24 hours')
       and (cp.id_su_co_goc is null
            or (not exists (select 1 from duc_ca_hien_tai c where c.open_id_su_co = cp.id_su_co_goc)
                and not exists (select 1 from duc_su_co_mo_them t where t.id_su_co = cp.id_su_co_goc)))
    returning cp.id_checkpoint, cp.ma_may
  )
  select count(*), string_agg(distinct ma_may, ', ') into v_n, v_ds from don;

  if v_n > 0 then
    begin
      perform cv_pd_gui(cv_pd_ds_role(array['qc_manager']), 'ipqc', 'mo_coi',
        'ipqc-mo-coi:' || to_char(now(), 'YYYYMMDDHH24MISS'), 'ipqc.html',
        v_n || ' phiếu IPQC chờ kiểm quá 24 giờ, máy đã đổi SP/dừng (' || v_ds || ') → tự hết hiệu lực.', false);
    exception when others then
      raise warning 'T283 chuông mồ côi lỗi (bỏ qua): %', sqlerrm;
    end;
  end if;
  return v_n;
end $$;

revoke execute on function public.duc_ipqc_continue_quet_treo() from public, anon, authenticated;
revoke execute on function public.duc_ipqc_don_checkpoint_mo_coi() from public, anon, authenticated;

select cron.alter_job(jobid, command := 'select public.duc_ipqc_nhac_cham(); select public.duc_ipqc_don_checkpoint_mo_coi(); select public.duc_ipqc_continue_quet_treo();')
from cron.job where jobname = 'duc_ipqc_nhac_cham';
