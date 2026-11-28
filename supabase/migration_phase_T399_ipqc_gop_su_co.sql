-- T399: GỘP check point IPQC "sau sự cố" khi cùng máy + cùng mã (cùng id_dong) có thêm sự cố mới
-- trong lúc check point sự cố trước còn chờ kiểm.
--   * duc_ipqc_checkpoint.id_su_co_kem: các sự cố gộp thêm (ngoài id_su_co_goc).
--   * duc_request_ipqc_check: đã có check point sau_su_co/doi_khuon chờ kiểm trên dòng → gộp sự cố
--     mới vào (chỉ loại sự cố cần IPQC), kể cả khi sự cố trước đã bấm Xong mà mẫu chưa kiểm.
--     (1 máy chỉ mở 1 sự cố một lúc → trường hợp thực tế: A Xong nhưng check point A còn chờ, phát sinh B.)
--   * duc_giao_qc_x / duc_resolve_incident: luôn gọi duc_request_ipqc_check (bỏ chặn "đã có check point").
--   * duc_ipqc_kiem_cua_su_co: kết quả check point chung tính cho mọi sự cố trong đó
--     (sự cố gộp thêm phải giao QC TRƯỚC lúc kiểm) → OK đóng được cả 2.
--   * Xoá sự cố → gỡ khỏi check point đang chờ; hết sự cố thì check point sau_su_co hết hiệu lực.
--   * Lịch sử sự cố, ghi NG khi đang có sự cố, dọn check point mồ côi, ngữ cảnh lên khuôn: tính cả sự cố gộp.

alter table public.duc_ipqc_checkpoint add column if not exists id_su_co_kem text[] not null default '{}';

-- Sự cố còn đang mở không (sự cố chính của dòng hoặc sự cố mở thêm).
create or replace function public.duc_su_co_con_mo(p_id_su_co text)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select p_id_su_co is not null and (
    exists (select 1 from duc_ca_hien_tai c where c.open_id_su_co = p_id_su_co)
    or exists (select 1 from duc_su_co_mo_them t where t.id_su_co = p_id_su_co));
$$;
revoke execute on function public.duc_su_co_con_mo(text) from public, anon, authenticated;

-- Loại sự cố (đang mở) — để biết có cần IPQC không.
create or replace function public.duc_su_co_loai_dang_mo(p_id_su_co text)
returns text language sql stable security definer set search_path to 'public' as $$
  select coalesce(
    (select c.open_loai_su_co from duc_ca_hien_tai c where c.open_id_su_co = p_id_su_co limit 1),
    (select t.loai_su_co from duc_su_co_mo_them t where t.id_su_co = p_id_su_co limit 1));
$$;
revoke execute on function public.duc_su_co_loai_dang_mo(text) from public, anon, authenticated;

create or replace function public.duc_request_ipqc_check(p_id_dong text, p_loai_kiem text, p_id_su_co_goc text DEFAULT NULL::text, p_moc_cho_override timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_cht record;
  v_dup int;
  v_id text;
  v_goc text;
  v_n int := 1;
  v_han_kiem timestamptz;
  v_last_check timestamptz;
  v_cho record;
begin
  select ma_may, ma_sp, ngay, ca, phuong_an_ca into v_cht from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then return jsonb_build_object('ok', false, 'reason', 'khong_tim_thay_dong'); end if;
  if v_cht.ma_sp is null or v_cht.ma_sp = '' then return jsonb_build_object('ok', false, 'reason', 'dong_khong_co_sp'); end if;

  -- T399: dòng đã có check point sau sự cố / đổi khuôn đang chờ → gộp sự cố mới vào check point đó.
  if p_loai_kiem = 'sau_su_co' and p_id_su_co_goc is not null then
    select id_checkpoint, loai_kiem, id_su_co_goc, id_su_co_kem into v_cho
      from duc_ipqc_checkpoint
     where id_dong = p_id_dong and trang_thai = 'cho_kiem' and loai_kiem in ('sau_su_co', 'doi_khuon')
     order by thoi_diem_tao limit 1 for update;
    if found then
      if v_cho.id_su_co_goc = p_id_su_co_goc or p_id_su_co_goc = any(v_cho.id_su_co_kem) then
        return jsonb_build_object('ok', false, 'reason', 'da_co_checkpoint_cho_kiem', 'id_checkpoint', v_cho.id_checkpoint);
      end if;
      if left(coalesce(duc_su_co_loai_dang_mo(p_id_su_co_goc), ''), 2) = any(array['A1','A2','A3','B1','B2','C3','E1','F1']) then
        if v_cho.loai_kiem = 'sau_su_co' and v_cho.id_su_co_goc is null then
          update duc_ipqc_checkpoint set id_su_co_goc = p_id_su_co_goc where id_checkpoint = v_cho.id_checkpoint;
        else
          update duc_ipqc_checkpoint set id_su_co_kem = array_append(id_su_co_kem, p_id_su_co_goc) where id_checkpoint = v_cho.id_checkpoint;
        end if;
        return jsonb_build_object('ok', true, 'gop', true, 'id_checkpoint', v_cho.id_checkpoint);
      end if;
      return jsonb_build_object('ok', false, 'reason', 'da_co_checkpoint_cho_kiem', 'id_checkpoint', v_cho.id_checkpoint);
    end if;
  end if;

  select count(*) into v_dup from duc_ipqc_checkpoint
    where id_dong = p_id_dong and loai_kiem = p_loai_kiem and trang_thai = 'cho_kiem';
  if v_dup > 0 then return jsonb_build_object('ok', false, 'reason', 'da_co_checkpoint_cho_kiem'); end if;

  -- Sự cố / đổi khuôn / sau thay đổi (T307) ưu tiên hơn định kỳ: nuốt luôn checkpoint 'dinh_ky'
  -- đang chờ của cùng dòng (thường là dòng định kỳ IPQC bấm vào rồi bỏ dở).
  if p_loai_kiem in ('sau_su_co', 'doi_khuon', 'sau_thay_doi') then
    update duc_ipqc_checkpoint
      set trang_thai = 'het_hieu_luc'
      where id_dong = p_id_dong and loai_kiem = 'dinh_ky' and trang_thai = 'cho_kiem';
  end if;

  -- Mốc bắt đầu tính "trễ": không bao giờ lùi trước lần kiểm HOÀN THÀNH gần
  -- nhất của chính dòng này (kiểm sự cố / đổi khuôn cũng là kiểm định kỳ).
  select max(thoi_diem_kiem_thuc_te) into v_last_check
    from duc_ipqc_checkpoint
    where id_dong = p_id_dong and trang_thai = 'da_kiem';

  v_han_kiem := coalesce(p_moc_cho_override, now());
  if v_last_check is not null and v_han_kiem < v_last_check then
    v_han_kiem := v_last_check;
  end if;
  if v_han_kiem > now() then
    v_han_kiem := now();
  end if;

  v_goc := 'IPQC_' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DDMMYYYY_HH24MISS')
    || '_' || duc_normalize_name(v_cht.ma_may) || '_' || p_loai_kiem;
  v_id := v_goc;
  -- T328: nhiều dòng cùng máy trong cùng 1 giây (khuôn nhiều mã) → thêm đuôi _2, _3...
  while exists (select 1 from duc_ipqc_checkpoint where id_checkpoint = v_id) loop
    v_n := v_n + 1;
    v_id := v_goc || '_' || v_n;
  end loop;

  insert into duc_ipqc_checkpoint (
    id_checkpoint, id_dong, ma_may, ma_sp, ngay, ca, phuong_an_ca, loai_kiem,
    id_su_co_goc, thoi_diem_tao, han_kiem, trang_thai
  ) values (
    v_id, p_id_dong, v_cht.ma_may, v_cht.ma_sp, v_cht.ngay, v_cht.ca, v_cht.phuong_an_ca,
    p_loai_kiem, p_id_su_co_goc, now(), v_han_kiem, 'cho_kiem'
  );

  return jsonb_build_object('ok', true, 'id_checkpoint', v_id);
end;
$function$;

-- Kết quả IPQC của 1 sự cố: check point chung (gộp) tính cho sự cố gộp thêm khi sự cố đó đã giao QC trước lúc kiểm.
create or replace function public.duc_ipqc_kiem_cua_su_co(p_ma_may text, p_gio timestamp with time zone, p_id_su_co text, p_loai text DEFAULT NULL::text)
 RETURNS TABLE(id_checkpoint text, ket_qua text, luc timestamp with time zone, id_su_co_kiem text, nguoi_kiem text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with g as (select min(x.thoi_diem) dau from duc_su_co_giao_qc x where p_id_su_co is not null and x.id_su_co = p_id_su_co)
  select cp.id_checkpoint, cp.ket_qua, cp.thoi_diem_kiem_thuc_te,
         case when p_id_su_co is not null and p_id_su_co = any(cp.id_su_co_kem) then p_id_su_co else cp.id_su_co_goc end,
         cp.nguoi_kiem
    from duc_ipqc_checkpoint cp cross join g
   where p_gio is not null
     and cp.trang_thai = 'da_kiem' and cp.loai_kiem in ('sau_su_co', 'doi_khuon')
     and cp.thoi_diem_kiem_thuc_te is not null
     and (
       (p_id_su_co is not null and cp.id_su_co_goc = p_id_su_co
        and (p_gio < duc_moc_giao_qc()
             or (g.dau is not null and cp.thoi_diem_kiem_thuc_te > g.dau)
             or (g.dau is null and left(coalesce(p_loai, ''), 2) <> 'F1')))
       or
       (p_id_su_co is not null and p_id_su_co = any(cp.id_su_co_kem)
        and g.dau is not null and cp.thoi_diem_kiem_thuc_te > g.dau)
       or
       (cp.ma_may = p_ma_may and cp.id_su_co_goc is distinct from p_id_su_co
        and not (coalesce(p_id_su_co, '') = any(cp.id_su_co_kem))
        and cp.thoi_diem_kiem_thuc_te >= p_gio
        and (g.dau is null or cp.thoi_diem_kiem_thuc_te > g.dau)
        and coalesce((select max(g2.thoi_diem) from duc_su_co_giao_qc g2
                       where g2.id_su_co = cp.id_su_co_goc and g2.thoi_diem <= cp.thoi_diem_kiem_thuc_te),
                     case when cp.loai_kiem = 'doi_khuon' then cp.thoi_diem_kiem_thuc_te else cp.thoi_diem_tao end) >= p_gio)
     )
$function$;

create or replace function public.duc_ipqc_don_checkpoint_mo_coi()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
       and not exists (select 1 from unnest(array[cp.id_su_co_goc] || cp.id_su_co_kem) s(id)
                       where s.id is not null and duc_su_co_con_mo(s.id))
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
end $function$;

create or replace function public.duc_ipqc_vd_ngu_canh(p_id_checkpoint text, OUT o_ma_khuon text, OUT o_len_khuon boolean)
 RETURNS record
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_cp record;
begin
  select id_dong, loai_kiem, id_su_co_goc, id_su_co_kem into v_cp from duc_ipqc_checkpoint where id_checkpoint = p_id_checkpoint;
  if not found then return; end if;
  select nullif(trim(so_khuon), '') into o_ma_khuon from duc_ca_hien_tai where id_dong = v_cp.id_dong;
  o_len_khuon := v_cp.loai_kiem = 'doi_khuon'
    or (v_cp.loai_kiem = 'sau_su_co' and exists (
          select 1 from unnest(array[v_cp.id_su_co_goc] || v_cp.id_su_co_kem) s(id)
           where s.id is not null and (
                 exists (select 1 from duc_ca_hien_tai c where c.open_id_su_co = s.id and left(coalesce(c.open_loai_su_co, ''), 2) = 'C3')
              or exists (select 1 from duc_su_co_mo_them t where t.id_su_co = s.id and left(coalesce(t.loai_su_co, ''), 2) = 'C3')
              or exists (select 1 from duc_su_co_log l where l.id_su_co = s.id and left(coalesce(l.loai_su_co, ''), 2) = 'C3'))));
end $function$;

-- XOÁ sự cố → gỡ khỏi check point đang chờ (đóng sự cố thì giữ: check point vẫn hiện "sau sự cố A + B").
create or replace function public.duc_ipqc_go_su_co_dong()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if new.id_su_co is null or new.su_kien <> 'xoa' then return new; end if;
  update duc_ipqc_checkpoint set id_su_co_kem = array_remove(id_su_co_kem, new.id_su_co)
   where trang_thai = 'cho_kiem' and new.id_su_co = any(id_su_co_kem);
  update duc_ipqc_checkpoint set id_su_co_goc = id_su_co_kem[1], id_su_co_kem = id_su_co_kem[2:]
   where trang_thai = 'cho_kiem' and loai_kiem = 'sau_su_co' and id_su_co_goc = new.id_su_co
     and cardinality(id_su_co_kem) > 0;
  update duc_ipqc_checkpoint
     set trang_thai = 'het_hieu_luc',
         ghi_chu = concat_ws(E'\n', nullif(ghi_chu, ''), '[T399: sự cố ' || new.id_su_co || ' đã bị xoá — tự hết hiệu lực]')
   where trang_thai = 'cho_kiem' and loai_kiem = 'sau_su_co' and id_su_co_goc = new.id_su_co
     and cardinality(id_su_co_kem) = 0;
  return new;
exception when others then
  raise warning 'T399 gỡ sự cố khỏi check point lỗi (bỏ qua): %', sqlerrm;
  return new;
end $$;
revoke execute on function public.duc_ipqc_go_su_co_dong() from public, anon, authenticated;

drop trigger if exists trg_duc_ipqc_go_su_co_dong on public.duc_su_co_nhat_ky;
create trigger trg_duc_ipqc_go_su_co_dong after insert on public.duc_su_co_nhat_ky
  for each row when (new.su_kien = 'xoa') execute function public.duc_ipqc_go_su_co_dong();

-- Sửa tại chỗ các hàm dài (thay đúng đoạn, báo lỗi nếu không khớp).
do $do$
declare d text; d2 text;
begin
  -- giao QC: luôn gọi duc_request_ipqc_check (tự gộp).
  d := pg_get_functiondef('public.duc_giao_qc_x(text,text,text,text,text)'::regprocedure);
  d2 := replace(d,
$a$  if not exists (select 1 from duc_ipqc_checkpoint
                 where id_dong = p_id_dong and trang_thai = 'cho_kiem' and loai_kiem in ('sau_su_co', 'doi_khuon')) then
    begin
      perform duc_request_ipqc_check(p_id_dong, 'sau_su_co', v_id, null);
    exception when unique_violation then null;
    end;
  end if;$a$,
$a$  begin
    perform duc_request_ipqc_check(p_id_dong, 'sau_su_co', v_id, null);   -- T399: tự gộp nếu đã có check point chờ
  exception when unique_violation then null;
  end;$a$);
  if d2 = d then raise exception 'T399: không khớp đoạn duc_giao_qc_x'; end if;
  execute d2;

  -- Xử lý xong khi IPQC chưa OK: luôn gọi duc_request_ipqc_check.
  d := pg_get_functiondef('public.duc_resolve_incident(text,timestamptz,text,text,text)'::regprocedure);
  d2 := regexp_replace(d,
    'if\s+not\s+exists\s+\(select\s+1\s+from\s+duc_ipqc_checkpoint\s+where\s+id_dong\s+=\s+p_id_dong\s+and\s+trang_thai\s+=\s+''cho_kiem''\s+and\s+loai_kiem\s+in\s+\(''sau_su_co'',\s+''doi_khuon''\)\)\s+then\s+begin\s+perform\s+duc_request_ipqc_check\(p_id_dong,\s+''sau_su_co'',\s+v_cht\.open_id_su_co,\s+null\);\s+exception\s+when\s+unique_violation\s+then\s+null;\s+end;\s+end\s+if;',
    'begin perform duc_request_ipqc_check(p_id_dong, ''sau_su_co'', v_cht.open_id_su_co, null); exception when unique_violation then null; end;');
  if d2 = d then raise exception 'T399: không khớp đoạn duc_resolve_incident'; end if;
  execute d2;

  -- IPQC NG khi đang có sự cố: sự cố đang mở nằm trong check point gộp thì không ghi trùng.
  d := pg_get_functiondef('public.duc_submit_ipqc_check(text,jsonb,text,jsonb,text,numeric,text)'::regprocedure);
  d2 := replace(replace(d,
    'select id_dong, ma_may, ma_sp, loai_kiem, id_su_co_goc into v_cp from duc_ipqc_checkpoint',
    'select id_dong, ma_may, ma_sp, loai_kiem, id_su_co_goc, id_su_co_kem into v_cp from duc_ipqc_checkpoint'),
    'if v_cht.open_id_su_co is not null and v_cp.id_su_co_goc is distinct from v_cht.open_id_su_co then',
    'if v_cht.open_id_su_co is not null and v_cp.id_su_co_goc is distinct from v_cht.open_id_su_co and not (v_cht.open_id_su_co = any(v_cp.id_su_co_kem)) then');
  if d2 = d or strpos(d2, 'id_su_co_goc, id_su_co_kem into v_cp') = 0 or strpos(d2, 'any(v_cp.id_su_co_kem)') = 0 then
    raise exception 'T399: không khớp đoạn duc_submit_ipqc_check';
  end if;
  execute d2;

  -- Lịch sử sự cố: tính cả check point gộp.
  d := pg_get_functiondef('public.duc_su_co_lich_su(text)'::regprocedure);
  d2 := replace(replace(d,
    'from duc_ipqc_checkpoint where id_su_co_goc = p_id_su_co) c;',
    'from duc_ipqc_checkpoint where id_su_co_goc = p_id_su_co or p_id_su_co = any(id_su_co_kem)) c;'),
    'and id_su_co_goc is distinct from p_id_su_co',
    'and id_su_co_goc is distinct from p_id_su_co and not (p_id_su_co = any(id_su_co_kem))');
  if strpos(d2, 'p_id_su_co = any(id_su_co_kem)) c;') = 0 or strpos(d2, 'and not (p_id_su_co = any(id_su_co_kem))') = 0 then
    raise exception 'T399: không khớp đoạn duc_su_co_lich_su';
  end if;
  execute d2;
end $do$;
