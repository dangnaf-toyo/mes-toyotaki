-- T342 (23/11/2026): tem thùng Gia Công KHÔNG đi khách hàng → không dùng tiền tố TP.
--   * Tem Gia Công in ở màn In tem (cd_tao_lo_tem_thanh_pham, công đoạn 'Gia Công')
--     sinh mã GC<YYYYMMDD>-<NNNN> (hàm mới cd_next_tag_no_gia_cong), lô GC…
--   * Mọi hàm đang nhận diện "tem thùng" bằng tag_no like 'TP%' → nhận cả GC
--     (regex ^(TP|GC)). Bavia / Đánh bóng Kẽm / OQC giữ TP như cũ.
--   * Huỷ (xoá) 10 tem Gia Công TP20261123-0001…0010 in 23/11 — chưa dùng (Chờ đóng gói TP,
--     không có nguồn/log). Chỉ xoá tem đúng trạng thái đó.

-- 1) Bộ đếm mã tem GC
create or replace function public.cd_next_tag_no_gia_cong()
returns text language plpgsql security definer set search_path = public as $$
declare
  d date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  key text := 'GC' || to_char(d, 'YYYYMMDD');
  next_seq int;
begin
  insert into duc_tag_no_counter (prefix_ngay, last_seq)
  values (key, 1)
  on conflict (prefix_ngay) do update set last_seq = duc_tag_no_counter.last_seq + 1
  returning last_seq into next_seq;
  return key || '-' || lpad(next_seq::text, 4, '0');
end;
$$;
revoke execute on function public.cd_next_tag_no_gia_cong() from public, anon, authenticated;

-- 2) Sửa hàng loạt hàm
do $$
declare
  v_fn text; v_old text; v_new text;
  v_list text[] := array[
    'bavia_du_lieu','bavia_ng_theo_tem','bavia_quet','bavia_xong_xe_huy',
    'cd_khai_bao_nguon_dang_dung','cd_kiem_xe_bavia','cd_ton_kho_theo_ma_sp',
    'cd_vi_tri_tem','duc_tem_mo_coi_ca','gc_chia_xe','gc_quet','gc_tem_cho'];
begin
  foreach v_fn in array v_list loop
    select pg_get_functiondef(('public.' || v_fn)::regproc) into v_old;
    v_new := v_old;
    -- dạng phủ định trước, rồi dạng khẳng định
    v_new := replace(v_new, E'not ilike ''TP%''', E'!~* ''^(TP|GC)''');
    v_new := replace(v_new, E'not like ''TP%''',  E'!~ ''^(TP|GC)''');
    v_new := replace(v_new, E'ilike ''TP%''',     E'~* ''^(TP|GC)''');
    v_new := replace(v_new, E'like ''TP%''',      E'~ ''^(TP|GC)''');
    if v_new = v_old then raise exception 'T342: không sửa được %', v_fn; end if;
    execute v_new;
  end loop;

  -- cd_tao_lo_tem_thanh_pham: Gia Công → mã GC
  select pg_get_functiondef('public.cd_tao_lo_tem_thanh_pham'::regproc) into v_old;
  v_new := replace(v_old,
    E'v_lo := ''TP'' || to_char(',
    E'v_lo := case when p_cong_doan = ''Gia Công'' then ''GC'' else ''TP'' end /* T342 */ || to_char(');
  v_new := replace(v_new,
    E'v_tag := cd_next_tag_no_thanh_pham();',
    E'v_tag := case when p_cong_doan = ''Gia Công'' then cd_next_tag_no_gia_cong() else cd_next_tag_no_thanh_pham() end; -- T342');
  if v_new = v_old or v_new !~ 'cd_next_tag_no_gia_cong' or v_new !~ 'then ''GC''' then
    raise exception 'T342: không sửa được cd_tao_lo_tem_thanh_pham';
  end if;
  execute v_new;

  -- kiểm: không còn hàm nào trong danh sách giữ like 'TP%'
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = any(v_list)
               and pg_get_functiondef(p.oid) ~* 'like ''TP%''') then
    raise exception 'T342: còn sót like TP%%';
  end if;
end $$;

-- 3) Huỷ 10 tem Gia Công mã TP in 23/11 (chưa dùng)
delete from duc_tem t
where t.tram_cong_doan = 'Gia Công' and t.tag_no like 'TP%'
  and t.trang_thai = 'Chờ đóng gói TP'
  and not exists (select 1 from cd_tem_nguon n where n.tag_no_moi = t.tag_no or n.tag_no_nguon = t.tag_no)
  and not exists (select 1 from cd_chuyen_cong_doan_log l where l.tag_no = t.tag_no);
