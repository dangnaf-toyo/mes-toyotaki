-- T179 (28/10/2026): hoàn thiện T178 (tối đa 3 sự cố mở / máy).
--  A. Nhật ký sự cố: đổi chỗ chính ↔ phụ (duc_su_co_doi_cho / duc_su_co_phu_len_chinh) làm open_id_su_co của dòng đổi
--     → trigger duc_su_co_nk_ca_hien_tai ghi nhầm 'dong'/'mo'. Thêm cờ giao dịch duc.nk_bo_qua để bỏ qua; sự cố phụ
--     ghi 'mo' lúc tạo + 'chuyen_ca' khi sang ca qua trigger riêng trên duc_su_co_mo_them.
--  B. duc_su_co_lich_su: tìm được sự cố phụ đang mở (màn IPQC, Sự cố Đúc, tổ khuôn).
--  C. Tổ khuôn xử lý bất thường: danh sách + lưu phiếu nhận cả sự cố phụ A2/B1/F1.
--  D. IPQC kiểm ĐỊNH KỲ NG khi máy đang có sự cố khác → tự mở F1 thành sự cố phụ (trước: chỉ ghi chú cho trưởng ca).
--     Kiểm sau sự cố / đổi khuôn NG thì không mở thêm (sự cố đó đã bị chặn đóng tới khi IPQC OK — T170).
--  E. tong_quan_hom_nay: thêm 'phut_may' (phút dừng máy đã trừ chồng giờ) để cộng tổng.

-- ── A. Nhật ký ───────────────────────────────────────────────────────────────
create or replace function public.duc_su_co_nk_bo_qua()
returns boolean language sql stable as $$ select coalesce(current_setting('duc.nk_bo_qua', true), '') = '1' $$;

do $$
declare d text;
begin
  d := replace(pg_get_functiondef('public.duc_su_co_nk_ca_hien_tai'::regproc), E'\r\n', E'\n');
  if strpos(d, 'T179') = 0 then
    d := replace(d, E'begin\n  if new.open_id_su_co is not null then\n    v_dl',
      E'begin\n  if duc_su_co_nk_bo_qua() then return new; end if;   -- T179: đổi chỗ sự cố chính/phụ, không phải mở/đóng thật\n' ||
      E'  if new.open_id_su_co is not null then\n    v_dl');
    if strpos(d, 'T179') = 0 then raise exception 'T179: không vá được duc_su_co_nk_ca_hien_tai'; end if;
    execute d;
  end if;
end $$;

create or replace function public.duc_su_co_phu_len_chinh(p_id_dong text)
returns void language plpgsql security definer set search_path = public as $$
declare x record;
begin
  if exists (select 1 from duc_ca_hien_tai where id_dong = p_id_dong and open_gio_phat_sinh is not null) then return; end if;
  select * into x from duc_su_co_mo_them where id_dong = p_id_dong order by gio_phat_sinh, id limit 1;
  if not found then return; end if;
  perform set_config('duc.nk_bo_qua', '1', true);   -- T179: sự cố phụ đã ghi 'mo' lúc tạo
  update duc_ca_hien_tai set
    open_loai_su_co = x.loai_su_co, open_gio_phat_sinh = x.gio_phat_sinh, open_van_de = x.van_de,
    open_noi_dung_xu_ly = x.noi_dung_xu_ly, open_dam_nhiem = x.dam_nhiem, open_id_su_co = x.id_su_co,
    version = coalesce(version, 0) + 1, last_updated_at = now()
  where id_dong = p_id_dong;
  delete from duc_su_co_mo_them where id = x.id;
  perform set_config('duc.nk_bo_qua', '', true);
end $$;

create or replace function public.duc_su_co_doi_cho(p_id_dong text, p_id_su_co text)
returns text language plpgsql security definer set search_path = public as $$
declare c record; x record; v_id_chinh text;
begin
  select * into c from duc_ca_hien_tai where id_dong = p_id_dong for update;
  if not found or c.open_gio_phat_sinh is null then return null; end if;
  if c.open_id_su_co = p_id_su_co then return p_id_su_co; end if;
  select * into x from duc_su_co_mo_them where id_dong = p_id_dong and id_su_co = p_id_su_co for update;
  if not found then return null; end if;
  v_id_chinh := coalesce(c.open_id_su_co, duc_id_su_co_moi(c.ma_may, c.open_gio_phat_sinh));
  perform set_config('duc.nk_bo_qua', '1', true);   -- T179
  update duc_su_co_mo_them set
    loai_su_co = coalesce(nullif(c.open_loai_su_co, ''), '?'), gio_phat_sinh = c.open_gio_phat_sinh,
    van_de = coalesce(c.open_van_de, ''), noi_dung_xu_ly = coalesce(c.open_noi_dung_xu_ly, ''),
    dam_nhiem = coalesce(c.open_dam_nhiem, ''), id_su_co = v_id_chinh
  where id = x.id;
  update duc_ca_hien_tai set
    open_loai_su_co = x.loai_su_co, open_gio_phat_sinh = x.gio_phat_sinh, open_van_de = x.van_de,
    open_noi_dung_xu_ly = x.noi_dung_xu_ly, open_dam_nhiem = x.dam_nhiem, open_id_su_co = x.id_su_co
  where id_dong = p_id_dong;
  perform set_config('duc.nk_bo_qua', '', true);
  return v_id_chinh;
end $$;

create or replace function public.duc_su_co_nk_mo_them()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_c record; v_dl jsonb;
begin
  if duc_su_co_nk_bo_qua() then return new; end if;
  if tg_op = 'UPDATE' and new.id_dong is not distinct from old.id_dong then return new; end if;
  select ngay, ca, ma_may, ma_sp, so_khuon into v_c from duc_ca_hien_tai where id_dong = new.id_dong;
  v_dl := jsonb_build_object('loai', new.loai_su_co, 'gio_phat_sinh', new.gio_phat_sinh, 'van_de', new.van_de,
    'noi_dung_xu_ly', new.noi_dung_xu_ly, 'dam_nhiem', new.dam_nhiem, 'ma_may', v_c.ma_may, 'ma_sp', v_c.ma_sp, 'so_khuon', v_c.so_khuon);
  insert into duc_su_co_nhat_ky (id_su_co, su_kien, id_dong, ngay, ca, du_lieu, nguoi, nguoi_uid, nguon)
  values (new.id_su_co, case when tg_op = 'INSERT' then 'mo' else 'chuyen_ca' end, new.id_dong, v_c.ngay, v_c.ca, v_dl,
          duc_su_co_nguoi_hien_tai(), auth.uid(), coalesce(nullif(current_setting('request.path', true), ''), 'sql'));
  return new;
exception when others then
  raise warning 'duc_su_co_nk_mo_them: %', sqlerrm;
  return new;
end $$;

drop trigger if exists trg_duc_su_co_nk_mo_them on public.duc_su_co_mo_them;
create trigger trg_duc_su_co_nk_mo_them after insert or update of id_dong on public.duc_su_co_mo_them
  for each row execute function public.duc_su_co_nk_mo_them();

-- ── B. Lịch sử 1 sự cố ──────────────────────────────────────────────────────
do $$
declare d text;
begin
  d := replace(pg_get_functiondef('public.duc_su_co_lich_su'::regproc), E'\r\n', E'\n');
  if strpos(d, 'T179') = 0 then
    d := replace(d, E'    from duc_ca_hien_tai where open_id_su_co = p_id_su_co order by row_seq desc nulls last limit 1) x;\n',
      E'    from duc_ca_hien_tai where open_id_su_co = p_id_su_co order by row_seq desc nulls last limit 1) x;\n' ||
      E'  if v_mo is null then   -- T179: sự cố phụ đang mở\n' ||
      E'    select to_jsonb(x) into v_mo from (\n' ||
      E'      select c.id_dong, c.ngay, c.ca, c.ma_may, c.ma_sp, c.ten_sp, c.so_khuon, t.loai_su_co loai, t.gio_phat_sinh,\n' ||
      E'             t.van_de, t.noi_dung_xu_ly, t.dam_nhiem\n' ||
      E'      from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong where t.id_su_co = p_id_su_co limit 1) x;\n' ||
      E'  end if;\n');
    if strpos(d, 'T179') = 0 then raise exception 'T179: không vá được duc_su_co_lich_su'; end if;
    execute d;
  end if;
end $$;

-- ── C. Tổ khuôn xử lý bất thường ────────────────────────────────────────────
do $$
declare d text;
begin
  d := replace(pg_get_functiondef('public.duc_khuon_xlbt_danh_sach'::regproc), E'\r\n', E'\n');
  if strpos(d, 'T179') = 0 then
    d := replace(d, E'    from duc_ca_hien_tai\n    where open_id_su_co is not null and left(coalesce(open_loai_su_co, \'\'), 2) in (\'A2\', \'B1\', \'F1\')',
      E'    from (select open_id_su_co, ma_may, ma_sp, ten_sp, so_khuon, open_loai_su_co, open_gio_phat_sinh, open_van_de,\n' ||
      E'                 open_noi_dung_xu_ly, open_dam_nhiem, ngay, ca from duc_ca_hien_tai\n' ||
      E'          union all   -- T179: sự cố phụ đang mở\n' ||
      E'          select t.id_su_co, c.ma_may, c.ma_sp, c.ten_sp, c.so_khuon, t.loai_su_co, t.gio_phat_sinh, t.van_de,\n' ||
      E'                 t.noi_dung_xu_ly, t.dam_nhiem, c.ngay, c.ca\n' ||
      E'            from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong) s\n' ||
      E'    where open_id_su_co is not null and left(coalesce(open_loai_su_co, \'\'), 2) in (\'A2\', \'B1\', \'F1\')');
    if strpos(d, 'T179') = 0 then raise exception 'T179: không vá được duc_khuon_xlbt_danh_sach'; end if;
    execute d;
  end if;

  d := replace(pg_get_functiondef('public.duc_khuon_xlbt_luu'::regproc), E'\r\n', E'\n');
  if strpos(d, 'T179') = 0 then
    d := replace(d, E'      (select min(open_gio_phat_sinh) from duc_ca_hien_tai where open_id_su_co = v_id and left(coalesce(open_loai_su_co, \'\'), 2) in (\'A2\', \'B1\', \'F1\')))',
      E'      (select min(open_gio_phat_sinh) from duc_ca_hien_tai where open_id_su_co = v_id and left(coalesce(open_loai_su_co, \'\'), 2) in (\'A2\', \'B1\', \'F1\')),\n' ||
      E'      (select min(gio_phat_sinh) from duc_su_co_mo_them where id_su_co = v_id and left(loai_su_co, 2) in (\'A2\', \'B1\', \'F1\')))   -- T179');
    if strpos(d, 'T179') = 0 then raise exception 'T179: không vá được duc_khuon_xlbt_luu'; end if;
    execute d;
  end if;
end $$;

-- ── D. IPQC định kỳ NG khi máy đang có sự cố khác → F1 thành sự cố phụ ─────────
do $$
declare d text; n int := 0;
begin
  d := replace(pg_get_functiondef('public.duc_submit_ipqc_check'::regproc), E'\r\n', E'\n');
  if strpos(d, 'T179') > 0 then return; end if;
  if strpos(d, '  select ngay, ca, so_khuon, open_gio_phat_sinh into v_cht from duc_ca_hien_tai where id_dong = v_cp.id_dong;') > 0 then n := n + 1; end if;
  d := replace(d, '  select ngay, ca, so_khuon, open_gio_phat_sinh into v_cht from duc_ca_hien_tai where id_dong = v_cp.id_dong;',
                  '  select ngay, ca, so_khuon, open_gio_phat_sinh, open_loai_su_co into v_cht from duc_ca_hien_tai where id_dong = v_cp.id_dong;');
  if strpos(d, E'    if v_cht.open_gio_phat_sinh is not null then\n      v_note := \'Không tự mở sự cố F1 được — dòng đang có sự cố khác mở. Cần trưởng ca xử lý thủ công.\';\n') > 0 then n := n + 1; end if;
  d := replace(d, E'    if v_cht.open_gio_phat_sinh is not null then\n      v_note := \'Không tự mở sự cố F1 được — dòng đang có sự cố khác mở. Cần trưởng ca xử lý thủ công.\';\n',
E'    -- T179: máy đang có sự cố khác mà lượt kiểm ĐỊNH KỲ ra NG → mở F1 thành sự cố phụ (tối đa 3 sự cố).
    -- Kiểm sau sự cố / đổi khuôn NG: sự cố đó đã bị chặn đóng tới khi IPQC OK (T170) → không mở thêm.
    if v_cht.open_gio_phat_sinh is not null and (
         v_cp.loai_kiem <> \'dinh_ky\'
         or left(coalesce(v_cht.open_loai_su_co, \'\'), 2) = \'F1\'
         or exists (select 1 from duc_su_co_mo_them where id_dong = v_cp.id_dong and left(loai_su_co, 2) = \'F1\')
         or (select count(*) from duc_su_co_mo_them where id_dong = v_cp.id_dong) >= 2) then
      v_note := case
        when v_cp.loai_kiem in (\'sau_su_co\', \'doi_khuon\') then \'Không mở thêm sự cố F1 — máy đang dừng vì sự cố chờ IPQC; sự cố đó chỉ kết thúc được khi IPQC kiểm lại OK / Cảnh báo.\'
        when v_cp.loai_kiem <> \'dinh_ky\' then \'Không tự mở sự cố F1 được — dòng đang có sự cố khác mở. Cần trưởng ca xử lý thủ công.\'
        when (select count(*) from duc_su_co_mo_them where id_dong = v_cp.id_dong) >= 2 then \'Không tự mở sự cố F1 được — máy đã có 3 sự cố đang mở. Cần trưởng ca xử lý thủ công.\'
        else \'Không mở thêm sự cố F1 — máy đã có sự cố F1 đang mở.\' end;
');
  if n < 2 or strpos(d, 'T179') = 0 then raise exception 'T179: không vá được duc_submit_ipqc_check (%/2)', n; end if;
  execute d;
end $$;

-- ── E. Tổng quan ─────────────────────────────────────────────────────────────
do $$
declare d text;
begin
  d := replace(pg_get_functiondef('public.tong_quan_hom_nay'::regproc), E'\r\n', E'\n');
  if strpos(d, 'phut_may') > 0 then return; end if;
  d := replace(d, '''phut'', thoi_gian_dung_phut,', '''phut'', thoi_gian_dung_phut, ''phut_may'', coalesce(phut_dung_may, thoi_gian_dung_phut),');
  if strpos(d, 'phut_may') = 0 then raise exception 'T179: không vá được tong_quan_hom_nay'; end if;
  execute d;
end $$;

-- ── Quyền ────────────────────────────────────────────────────────────────────
revoke execute on function public.duc_su_co_nk_mo_them() from public, anon, authenticated;
revoke execute on function public.duc_su_co_phu_len_chinh(text) from public, anon, authenticated;
revoke execute on function public.duc_su_co_doi_cho(text, text) from public, anon, authenticated;
