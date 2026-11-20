-- T293: NO hiển thị cho IPQC Đúc. Đã chạy staging + prod 20/11/2026.
begin;

-- muc_no là mã nội bộ dùng trong kết quả đo và biểu đồ SPC từ trước.
-- NULL ở các phiên bản cũ hiển thị theo muc_no; không cập nhật dữ liệu lịch sử.
alter table public.ipqc_btk_muc
  add column no_hien_thi text check (no_hien_thi ~ '^[0-9]+(-[0-9]+)*$'),
  add column thu_tu_hien_thi integer check (thu_tu_hien_thi > 0);
create unique index ipqc_btk_muc_no_hien_thi_uq
  on public.ipqc_btk_muc (id_btk, no_hien_thi) where no_hien_thi is not null;

alter table public.ipqc_btk drop constraint ipqc_btk_trang_thai_check;
alter table public.ipqc_btk add constraint ipqc_btk_trang_thai_check check (
  trang_thai in ('cho_kiem_tra', 'cho_phe_duyet', 'tra_lai', 'da_duyet')
  or (cong_doan in ('duc', 'gia_cong', 'iqc_hoa_hoc') and trang_thai = 'ban_nhap')
);

create function public.ipqc_duc_luu_bang_tuan_kiem(p_ma_sp text, p_data jsonb, p_luu_nhap boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_ma text := btrim(coalesce(p_ma_sp, ''));
  v_nguon bigint := nullif(p_data->>'id_nguon', '')::bigint;
  v_nhap bigint;
  v_dang_dung bigint;
  v_ma_muc int;
  v_tiep int;
  v_no text;
  v_cac_no text[] := '{}';
  v_cac_ma int[] := '{}';
  v_muc jsonb := '[]';
  v_vi_tri jsonb;
  v_kq jsonb;
  v_loi text;
  v_id bigint;
  m jsonb;
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
  if not public.has_role('ipqc', 'nhan_vien_oqc', 'qc_manager', 'admin') then
    raise exception 'Chỉ nhân viên QC / Trưởng phòng QC được soạn bảng tuần kiểm';
  end if;
  perform pg_advisory_xact_lock(hashtext('ipqc_btk:duc:' || v_ma));
  select id into v_nhap from ipqc_btk
  where ma_sp = v_ma and cong_doan = 'duc' and trang_thai <> 'da_duyet'
  for update;
  select id into v_dang_dung from ipqc_btk
  where ma_sp = v_ma and cong_doan = 'duc' and dang_dung;

  if v_nguon is not null and not exists (
    select 1 from ipqc_btk where id = v_nguon and ma_sp = v_ma and cong_doan = 'duc'
  ) then
    raise exception 'Phiên bản nguồn không hợp lệ';
  end if;
  select coalesce(max(muc.muc_no), 0) into v_tiep
  from ipqc_btk_muc muc join ipqc_btk b on b.id = muc.id_btk
  where b.ma_sp = v_ma and b.cong_doan = 'duc';

  for m in select value from jsonb_array_elements(p_data->'muc') loop
    v_no := btrim(coalesce(m->>'no_hien_thi', m->>'muc_no', ''));
    if v_no !~ '^[0-9]+(-[0-9]+)*$' then
      raise exception 'NO phải có dạng 1 hoặc 1-1: %', v_no;
    end if;
    if v_no = any(v_cac_no) then raise exception 'Trùng NO % trong phiên bản', v_no; end if;
    v_cac_no := array_append(v_cac_no, v_no);

    v_ma_muc := null;
    if v_nguon is not null then
      select muc_no into v_ma_muc from ipqc_btk_muc
      where id_btk = v_nguon and muc_no = nullif(m->>'muc_no', '')::int;
    elsif not (m ? 'no_hien_thi') then
      -- Nhập Excel ghép mã với phiên bản nháp hoặc phiên bản đang dùng.
      select muc.muc_no into v_ma_muc
      from ipqc_btk_muc muc join ipqc_btk b on b.id = muc.id_btk
      where b.ma_sp = v_ma and b.cong_doan = 'duc'
        and b.id in (v_nhap, v_dang_dung)
        and coalesce(muc.no_hien_thi, muc.muc_no::text) = v_no
        and not (muc.muc_no = any(v_cac_ma))
      order by (b.id is not distinct from v_nhap) desc
      limit 1;
    end if;
    if v_ma_muc is null then
      v_tiep := v_tiep + 1;
      v_ma_muc := v_tiep;
    end if;
    if v_ma_muc = any(v_cac_ma) then raise exception 'Trùng hạng mục nội bộ cho NO %', v_no; end if;
    v_cac_ma := array_append(v_cac_ma, v_ma_muc);
    v_muc := v_muc || jsonb_build_array(m || jsonb_build_object('muc_no', v_ma_muc));
  end loop;

  if p_data ? 'ban_ve_vi_tri' then
    select coalesce(jsonb_agg(diem.value || jsonb_build_object('no', v_cac_ma[muc.vi_tri::int])
      order by diem.vi_tri), '[]'::jsonb) into v_vi_tri
    from jsonb_array_elements(p_data->'ban_ve_vi_tri') with ordinality as diem(value, vi_tri)
    join jsonb_array_elements(p_data->'muc') with ordinality as muc(value, vi_tri)
      on diem.value->>'no' = muc.value->>'muc_no';
    p_data := jsonb_set(p_data, '{ban_ve_vi_tri}', v_vi_tri);
  else
    -- Excel giữ vị trí trên bản vẽ của những hạng mục còn được sử dụng.
    select coalesce(jsonb_agg(diem.value order by diem.vi_tri), '[]'::jsonb) into v_vi_tri
    from ipqc_btk b
    cross join lateral jsonb_array_elements(b.ban_ve_vi_tri) with ordinality as diem(value, vi_tri)
    where b.id = coalesce(v_nhap, v_dang_dung)
      and diem.value->>'no' = any(v_cac_ma::text[]);
    p_data := jsonb_set(p_data, '{ban_ve_vi_tri}', v_vi_tri);
  end if;

  v_kq := public.ipqc_btk_luu(v_ma, jsonb_set(p_data - 'buoc_gia_cong', '{muc}', v_muc), null, 'duc');
  if not coalesce((v_kq->>'ok')::boolean, false) then
    v_loi := substring(v_kq->>'error' from '^No ([0-9]+):');
    if v_loi is not null then
      v_no := v_cac_no[array_position(v_cac_ma, v_loi::int)];
      if v_no is not null then
        v_kq := jsonb_set(v_kq, '{error}', to_jsonb(regexp_replace(v_kq->>'error', '^No [0-9]+:', 'NO ' || v_no || ':')));
      end if;
    end if;
    return v_kq;
  end if;
  v_id := (v_kq->>'id')::bigint;
  update ipqc_btk_muc muc
  set no_hien_thi = v_cac_no[ds.vi_tri::int], thu_tu_hien_thi = ds.vi_tri::int
  from unnest(v_cac_ma) with ordinality as ds(ma, vi_tri)
  where muc.id_btk = v_id and muc.muc_no = ds.ma;

  if p_luu_nhap then
    update ipqc_btk set trang_thai = 'ban_nhap', gui_luc = null where id = v_id;
  end if;
  return v_kq;
end;
$$;
revoke execute on function public.ipqc_duc_luu_bang_tuan_kiem(text, jsonb, boolean) from public, anon;
grant execute on function public.ipqc_duc_luu_bang_tuan_kiem(text, jsonb, boolean) to authenticated;

notify pgrst, 'reload schema';
commit;
