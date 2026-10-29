-- T180 (29/10/2026): nút "Hoàn thành mẫu & giao QC" cho sự cố cần IPQC (A1/A2/A3/B1/B2/C3/E1/F1).
--  Mục đích: tách thời gian dừng của sự cố thành
--    • phút XỬ LÝ sự cố        = phát sinh → lần giao QC cuối cùng
--    • phút XÁC NHẬN CHẤT LƯỢNG = lần giao QC cuối cùng → máy chạy lại (gồm chờ IPQC + kiểm + đóng)
--  1. Bảng duc_su_co_giao_qc (mỗi lần giao 1 dòng; IPQC NG → xử lý tiếp → giao lại).
--  2. RPC duc_giao_qc_x(id_dong, id_su_co, user): ghi lần giao + nhật ký 'giao_qc', bảo đảm có checkpoint chờ kiểm.
--  3. duc_resolve_incident: BẮT BUỘC đã giao QC mới đóng được (sự cố phát sinh từ mốc duc_moc_giao_qc();
--     admin / QC Manager / QLBP Thiết bị được vượt như T172-T173).
--  4. duc_su_co_log: cột gio_giao_qc, phut_xu_ly, phut_xac_nhan_cl — trigger tự tính cho từng phần (ca) của sự cố,
--     chia phút dừng của phần đó theo tỉ lệ thời gian trước / sau lần giao QC cuối.

-- ── 1. Bảng ──────────────────────────────────────────────────────────────────
create table if not exists public.duc_su_co_giao_qc (
  id bigserial primary key,
  id_su_co text not null,
  id_dong text,
  ma_may text,
  thoi_diem timestamptz not null default now(),
  nguoi text not null default '',
  nguoi_uid uuid
);
create index if not exists duc_su_co_giao_qc_id_su_co_idx on public.duc_su_co_giao_qc (id_su_co, thoi_diem);
alter table public.duc_su_co_giao_qc enable row level security;
drop policy if exists "public read" on public.duc_su_co_giao_qc;
create policy "public read" on public.duc_su_co_giao_qc for select using (true);
revoke insert, update, delete on public.duc_su_co_giao_qc from anon, authenticated;

alter table public.duc_su_co_nhat_ky drop constraint if exists duc_su_co_nhat_ky_su_kien_check;
alter table public.duc_su_co_nhat_ky add constraint duc_su_co_nhat_ky_su_kien_check
  check (su_kien = any (array['mo','cap_nhat','chuyen_ca','dong','sua_sau_dong','xoa','giao_qc']));

-- Mốc bắt buộc giao QC: sự cố phát sinh TRƯỚC mốc (đang mở lúc triển khai) không bị chặn.
do $$
begin
  if to_regprocedure('public.duc_moc_giao_qc()') is null then
    execute format('create function public.duc_moc_giao_qc() returns timestamptz language sql immutable as %L',
                   'select ' || quote_literal(now()::text) || '::timestamptz');
  end if;
end $$;
revoke execute on function public.duc_moc_giao_qc() from public, anon, authenticated;

-- ── 2. RPC giao QC ──────────────────────────────────────────────────────────
create or replace function public.duc_giao_qc_x(p_id_dong text, p_id_su_co text, p_user text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  c record; v_id text; v_loai text; v_gio timestamptz;
  v_lan_cuoi timestamptz; v_kq_sau text; v_lan int; v_now timestamptz := now();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into c from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found or c.open_gio_phat_sinh is null then
    return jsonb_build_object('ok', false, 'error', 'Dòng này không có sự cố đang mở — tải lại trang.');
  end if;
  if p_id_su_co is null or p_id_su_co = coalesce(c.open_id_su_co, '') then
    v_id := c.open_id_su_co; v_loai := c.open_loai_su_co; v_gio := c.open_gio_phat_sinh;
  else
    select id_su_co, loai_su_co, gio_phat_sinh into v_id, v_loai, v_gio
      from duc_su_co_mo_them where id_dong = p_id_dong and id_su_co = p_id_su_co;
    if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố ' || p_id_su_co || ' đang mở — tải lại trang.'); end if;
  end if;
  if v_id is null then return jsonb_build_object('ok', false, 'error', 'Sự cố chưa có mã nên chưa giao QC được.'); end if;
  if not (left(coalesce(v_loai, ''), 2) = any(array['A1','A2','A3','B1','B2','C3','E1','F1'])) then
    return jsonb_build_object('ok', false, 'error', 'Loại sự cố này không cần IPQC xác nhận — bấm "Xong" để đóng.');
  end if;

  -- Đã giao mà IPQC chưa có kết quả mới → không giao trùng; kết quả mới là OK/Cảnh báo → đóng luôn.
  select max(thoi_diem) into v_lan_cuoi from duc_su_co_giao_qc where id_su_co = v_id;
  if v_lan_cuoi is not null then
    select cp.ket_qua into v_kq_sau from duc_ipqc_checkpoint cp
     where cp.trang_thai = 'da_kiem' and cp.loai_kiem in ('sau_su_co', 'doi_khuon')
       and (cp.id_su_co_goc = v_id or (cp.ma_may = c.ma_may and cp.thoi_diem_kiem_thuc_te >= v_gio))
       and cp.thoi_diem_kiem_thuc_te > v_lan_cuoi
     order by cp.thoi_diem_kiem_thuc_te desc limit 1;
    if v_kq_sau is null then
      return jsonb_build_object('ok', false, 'error', 'Đã giao QC lúc '
        || to_char(v_lan_cuoi at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI') || ' — đang chờ IPQC kiểm.');
    end if;
    if v_kq_sau in ('OK', 'CANH_BAO') then
      return jsonb_build_object('ok', false, 'error', 'IPQC đã kiểm đạt (' || v_kq_sau || ') — bấm "Xong" để kết thúc sự cố.');
    end if;
  end if;

  insert into duc_su_co_giao_qc (id_su_co, id_dong, ma_may, thoi_diem, nguoi, nguoi_uid)
  values (v_id, p_id_dong, c.ma_may, v_now, coalesce(nullif(duc_su_co_nguoi_hien_tai(), ''), p_user, ''), auth.uid());
  select count(*) into v_lan from duc_su_co_giao_qc where id_su_co = v_id;

  insert into duc_su_co_nhat_ky (id_su_co, su_kien, id_dong, ngay, ca, du_lieu, nguoi, nguoi_uid, nguon)
  values (v_id, 'giao_qc', p_id_dong, c.ngay, c.ca, jsonb_build_object('lan', v_lan, 'loai', v_loai),
          coalesce(nullif(duc_su_co_nguoi_hien_tai(), ''), p_user, ''), auth.uid(), '/rpc/duc_giao_qc_x');

  -- Dòng phải có checkpoint chờ kiểm để IPQC thấy trong hàng đợi.
  if not exists (select 1 from duc_ipqc_checkpoint
                 where id_dong = p_id_dong and trang_thai = 'cho_kiem' and loai_kiem in ('sau_su_co', 'doi_khuon')) then
    begin
      perform duc_request_ipqc_check(p_id_dong, 'sau_su_co', v_id, null);
    exception when unique_violation then null;
    end;
  end if;

  return jsonb_build_object('ok', true, 'id_su_co', v_id, 'thoi_diem', v_now, 'lan', v_lan);
end $$;
revoke execute on function public.duc_giao_qc_x(text, text, text) from public, anon;
grant execute on function public.duc_giao_qc_x(text, text, text) to authenticated;

-- ── 3. Chặn đóng khi chưa giao QC ────────────────────────────────────────────
do $$
declare d text;
begin
  d := replace(pg_get_functiondef('public.duc_resolve_incident(text,timestamptz,text,text,text)'::regprocedure), E'\r\n', E'\n');
  if strpos(d, 'T180') = 0 then
    d := replace(d,
      E'  if (v_ipqc->>''can_ipqc'')::boolean and not (v_ipqc->>''ok'')::boolean and not v_vuot_ipqc then\n',
      E'  -- T180: BẮT BUỘC đã bấm "Hoàn thành mẫu & giao QC" (duc_giao_qc_x) — để tách phút xử lý / xác nhận chất lượng.\n' ||
      E'  if (v_ipqc->>''can_ipqc'')::boolean and not v_vuot_ipqc and v_cht.open_id_su_co is not null\n' ||
      E'     and v_cht.open_gio_phat_sinh >= duc_moc_giao_qc()\n' ||
      E'     and not exists (select 1 from duc_su_co_giao_qc g where g.id_su_co = v_cht.open_id_su_co)\n' ||
      E'     and not (public.has_role(''admin'', ''qc_manager'')\n' ||
      E'              or exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role = ''quan_ly_bo_phan''\n' ||
      E'                         and ''Thiết bị'' = any(coalesce(ur.bo_phan_phu_trach, ''{}'')))) then\n' ||
      E'    return jsonb_build_object(''ok'', false, ''chan_giao_qc'', true, ''error'',\n' ||
      E'      ''⛔ Sự cố '' || v_cht.open_id_su_co || '' chưa bấm "📦 Hoàn thành mẫu & giao QC". Xử lý xong và lấy mẫu thì bấm nút đó để IPQC kiểm; IPQC kiểm OK hoặc Cảnh báo rồi mới bấm "Xong".'');\n' ||
      E'  end if;\n\n' ||
      E'  if (v_ipqc->>''can_ipqc'')::boolean and not (v_ipqc->>''ok'')::boolean and not v_vuot_ipqc then\n');
    if strpos(d, 'T180') = 0 then raise exception 'T180: không vá được duc_resolve_incident'; end if;
    execute d;
  end if;
end $$;

-- ── 4. Tách phút trên duc_su_co_log ──────────────────────────────────────────
alter table public.duc_su_co_log add column if not exists gio_giao_qc timestamptz;
alter table public.duc_su_co_log add column if not exists phut_xu_ly numeric;
alter table public.duc_su_co_log add column if not exists phut_xac_nhan_cl numeric;

create or replace function public.duc_su_co_log_giao_qc_trg()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_g timestamptz; v_span numeric; v_tl numeric;
begin
  if new.id_su_co is not null then
    select max(thoi_diem) into v_g from duc_su_co_giao_qc where id_su_co = new.id_su_co;
  end if;
  new.gio_giao_qc := v_g;
  if v_g is null or new.gio_phat_sinh is null or new.gio_tro_lai is null then
    new.phut_xu_ly := null; new.phut_xac_nhan_cl := null;
    return new;
  end if;
  v_span := extract(epoch from (new.gio_tro_lai - new.gio_phat_sinh));
  v_tl := case when v_span <= 0 then 0
               else greatest(0, least(1, extract(epoch from (v_g - new.gio_phat_sinh)) / v_span)) end;
  new.phut_xu_ly := round(coalesce(new.thoi_gian_dung_phut, 0) * v_tl);
  new.phut_xac_nhan_cl := coalesce(new.thoi_gian_dung_phut, 0) - new.phut_xu_ly;
  return new;
end $$;
revoke execute on function public.duc_su_co_log_giao_qc_trg() from public, anon, authenticated;

drop trigger if exists trg_duc_su_co_log_giao_qc on public.duc_su_co_log;
create trigger trg_duc_su_co_log_giao_qc
  before insert or update of gio_phat_sinh, gio_tro_lai, thoi_gian_dung_phut, id_su_co on public.duc_su_co_log
  for each row execute function public.duc_su_co_log_giao_qc_trg();

-- ── 5. Tổng quan hôm nay: thêm phút xử lý / xác nhận CL cho từng dòng sự cố ──
do $$
declare d text;
begin
  d := replace(pg_get_functiondef('public.tong_quan_hom_nay'::regproc), E'\r\n', E'\n');
  if strpos(d, '''phut_xl''') = 0 then
    d := replace(d, $r$'xong', gio_tro_lai is not null,$r$,
                    $r$'phut_xl', phut_xu_ly, 'phut_cl', phut_xac_nhan_cl, 'xong', gio_tro_lai is not null,$r$);
    if strpos(d, '''phut_xl''') = 0 then raise exception 'T180: không vá được tong_quan_hom_nay'; end if;
    execute d;
  end if;
end $$;
