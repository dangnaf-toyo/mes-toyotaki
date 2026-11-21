-- =============================================================================
-- T300 (21/11/2026) Lý lịch sự cố Đúc hiện đủ ảnh từ phát sinh đến khi đóng.
--   duc_su_co_lich_su trả thêm 'ipqc_khac': mọi phiếu IPQC đã kiểm trên CÙNG MÁY trong
--   khoảng [giờ phát sinh, giờ chạy lại] (đang mở → đến hiện tại) mà không gắn mã sự cố này
--   (kiểm định kỳ, đổi khuôn, phiếu của sự cố khác) — trước đây ảnh các phiếu này bị bỏ sót.
-- Chạy: prod (fgghikpzcxjqzahfiiil) + staging (jcjbleugnclzsghfpmvk).
-- =============================================================================
create or replace function public.duc_su_co_lich_su(p_id_su_co text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  v_mo jsonb; v_log jsonb; v_sc record; v_phat_hien jsonb; v_ipqc jsonb; v_cp_ids text[];
  v_den timestamptz; v_khac jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if coalesce(trim(p_id_su_co), '') = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã sự cố'); end if;

  select to_jsonb(x) into v_mo from (
    select id_dong, ngay, ca, ma_may, ma_sp, ten_sp, so_khuon, open_loai_su_co loai, open_gio_phat_sinh gio_phat_sinh,
           open_van_de van_de, open_noi_dung_xu_ly noi_dung_xu_ly, open_dam_nhiem dam_nhiem
    from duc_ca_hien_tai where open_id_su_co = p_id_su_co order by row_seq desc nulls last limit 1) x;
  if v_mo is null then   -- T179: sự cố phụ đang mở
    select to_jsonb(x) into v_mo from (
      select c.id_dong, c.ngay, c.ca, c.ma_may, c.ma_sp, c.ten_sp, c.so_khuon, t.loai_su_co loai, t.gio_phat_sinh,
             t.van_de, t.noi_dung_xu_ly, t.dam_nhiem
      from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong where t.id_su_co = p_id_su_co limit 1) x;
  end if;

  select coalesce(jsonb_agg(to_jsonb(l) order by l.gio_phat_sinh, l.thoi_diem_luu), '[]'::jsonb) into v_log
  from duc_su_co_log l where l.id_su_co = p_id_su_co;

  select coalesce(l.ma_may, v_mo->>'ma_may') ma_may, coalesce(l.loai_su_co, v_mo->>'loai') loai,
         least(l.gio_phat_sinh, (v_mo->>'gio_phat_sinh')::timestamptz) gio_phat_sinh
  into v_sc
  from (select 1) d left join lateral (select * from duc_su_co_log where id_su_co = p_id_su_co order by gio_phat_sinh limit 1) l on true;
  if v_sc.ma_may is null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố ' || p_id_su_co); end if;

  if left(coalesce(v_sc.loai, ''), 2) = 'F1' then
    select to_jsonb(c) into v_phat_hien from (
      select id_checkpoint, loai_kiem, nguoi_kiem, ket_qua, thoi_diem_kiem_thuc_te, checklist_json, anh_bang_chung_url, ghi_chu
      from duc_ipqc_checkpoint
      where ma_may = v_sc.ma_may and trang_thai = 'da_kiem' and ket_qua <> 'OK'
        and thoi_diem_kiem_thuc_te between v_sc.gio_phat_sinh - interval '3 minutes' and v_sc.gio_phat_sinh + interval '3 minutes'
      order by abs(extract(epoch from thoi_diem_kiem_thuc_te - v_sc.gio_phat_sinh)) limit 1) c;
  end if;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.thoi_diem_kiem_thuc_te nulls last, c.thoi_diem_tao), '[]'::jsonb),
         array_agg(c.id_checkpoint)
  into v_ipqc, v_cp_ids
  from (select id_checkpoint, loai_kiem, trang_thai, nguoi_kiem, ket_qua, thoi_diem_tao, thoi_diem_kiem_thuc_te,
               checklist_json, anh_bang_chung_url, ghi_chu
        from duc_ipqc_checkpoint where id_su_co_goc = p_id_su_co) c;

  -- T300: phiếu IPQC khác cùng máy trong lúc sự cố còn mở.
  v_den := case when v_mo is not null then now()
                else (select max(gio_tro_lai) from duc_su_co_log where id_su_co = p_id_su_co) end;
  select coalesce(jsonb_agg(to_jsonb(c) order by c.thoi_diem_kiem_thuc_te), '[]'::jsonb) into v_khac
  from (select id_checkpoint, loai_kiem, id_su_co_goc, nguoi_kiem, ket_qua, thoi_diem_kiem_thuc_te,
               checklist_json, anh_bang_chung_url, ghi_chu
        from duc_ipqc_checkpoint
        where ma_may = v_sc.ma_may and trang_thai = 'da_kiem'
          and id_su_co_goc is distinct from p_id_su_co
          and id_checkpoint is distinct from (v_phat_hien->>'id_checkpoint')
          and thoi_diem_kiem_thuc_te >= v_sc.gio_phat_sinh
          and thoi_diem_kiem_thuc_te <= coalesce(v_den, v_sc.gio_phat_sinh)
        limit 50) c;

  return jsonb_build_object('ok', true,
    'id_su_co', p_id_su_co,
    'dang_mo', v_mo,
    'log', v_log,
    'phat_hien_ipqc', v_phat_hien,
    'ipqc', v_ipqc,
    'ipqc_khac', v_khac,
    'nhat_ky', (select coalesce(jsonb_agg(to_jsonb(k) order by k.thoi_diem, k.id), '[]'::jsonb) from duc_su_co_nhat_ky k where k.id_su_co = p_id_su_co),
    'anh', (select coalesce(jsonb_agg(jsonb_build_object('loai', a.loai, 'url', a.url, 'nguoi', a.nguoi, 'thoi_diem', a.thoi_diem) order by a.thoi_diem, a.id), '[]'::jsonb)
            from duc_su_co_anh a where a.id_su_co = p_id_su_co),
    'to_khuon', (select to_jsonb(x) from duc_khuon_xu_ly_bat_thuong x where x.id_su_co = p_id_su_co),
    'linh_kien', (select coalesce(jsonb_agg(jsonb_build_object('thoi_diem', g.thoi_diem, 'loai', g.loai, 'ma_lk', g.ma_lk, 'ten_lk', g.ten_lk,
                    'so_luong', g.so_luong, 'ma_khuon', g.ma_khuon, 'vi_tri', g.vi_tri, 'muc_dich', g.muc_dich, 'ket_qua_thao', g.ket_qua_thao,
                    'nguoi', g.nguoi, 'ghi_chu', g.ghi_chu) order by g.thoi_diem, g.id), '[]'::jsonb)
                  from khuon_lk_giao_dich g where g.id_su_co = p_id_su_co),
    'tiep_tuc', (select coalesce(jsonb_agg(jsonb_build_object('request_code', r.request_code, 'checkpoint_id', r.checkpoint_id,
                    'requester_name', r.requester_name, 'reason_type', r.reason_type, 'reason_detail', r.reason_detail,
                    'treatment_content', r.treatment_content, 'status', r.status, 'created_at', r.created_at,
                    'allowed_until', r.allowed_until, 'allowed_qty', r.allowed_qty,
                    'audit', (select coalesce(jsonb_agg(jsonb_build_object('action', a.action, 'actor_name', a.actor_name, 'detail', a.detail,
                                'created_at', a.created_at) order by a.created_at), '[]'::jsonb)
                              from duc_ipqc_continue_audit a where a.request_id = r.id)) order by r.created_at), '[]'::jsonb)
                 from duc_ipqc_continue_request r
                 where r.checkpoint_id = any(coalesce(v_cp_ids, array[]::text[]) || coalesce(array[v_phat_hien->>'id_checkpoint'], array[]::text[])))
  );
end $function$;

revoke execute on function public.duc_su_co_lich_su(text) from public, anon;
grant execute on function public.duc_su_co_lich_su(text) to authenticated;
