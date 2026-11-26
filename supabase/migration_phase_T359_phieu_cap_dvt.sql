-- T359: Phiếu đề nghị cấp NVL — thêm đơn vị tính từng dòng (kg / pcs), mặc định kg.
alter table public.nvl_phieu_cap_dong add column if not exists dvt text not null default 'kg';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'nvl_phieu_cap_dong_dvt_chk') then
    alter table public.nvl_phieu_cap_dong add constraint nvl_phieu_cap_dong_dvt_chk check (dvt in ('kg', 'pcs'));
  end if;
end $$;

create or replace function public.nvl_pdc_luu(p_id bigint, p_ngay date, p_bo_phan text, p_ghi_chu text, p_dong jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v public.nvl_phieu_cap; v_id bigint; v_so text; v_n int; d jsonb; i int := 0;
        v_ngay date := coalesce(p_ngay, (now() at time zone 'Asia/Ho_Chi_Minh')::date);
begin
  if not has_role('admin', 'nhan_vien_thong_ke') then
    raise exception '⛔ Chỉ Thống kê được lập phiếu đề nghị cấp NVL.' using errcode = '42501';
  end if;
  p_bo_phan := nullif(trim(coalesce(p_bo_phan, '')), '');
  if p_bo_phan is null or not (p_bo_phan = any(nvl_pdc_ds_bo_phan())) then raise exception 'Chọn bộ phận yêu cầu.'; end if;
  if p_dong is null or jsonb_typeof(p_dong) <> 'array' or jsonb_array_length(p_dong) = 0 then
    raise exception 'Phiếu chưa có dòng NVL nào.';
  end if;
  for d in select * from jsonb_array_elements(p_dong) loop
    if not exists (select 1 from nvl_materials where ma_nvl = d->>'ma_nvl') then
      raise exception 'Mã NVL không có trong danh mục: %', coalesce(d->>'ma_nvl', '(trống)');
    end if;
    if coalesce((d->>'sl_de_nghi')::numeric, 0) <= 0 then raise exception 'Số lượng đề nghị mã % phải > 0.', d->>'ma_nvl'; end if;
    if nullif(trim(coalesce(d->>'muc_dich', '')), '') is null then raise exception 'Nhập mục đích cấp cho mã %.', d->>'ma_nvl'; end if;
    if coalesce(d->>'dvt', 'kg') not in ('kg', 'pcs') then raise exception 'Đơn vị tính mã % chỉ được kg hoặc pcs.', d->>'ma_nvl'; end if;
  end loop;

  if p_id is null then
    perform pg_advisory_xact_lock(hashtext('nvl_pdc_so_phieu'));
    select count(*) + 1 into v_n from nvl_phieu_cap where so_phieu like 'DN' || to_char(v_ngay, 'YYMMDD') || '-%';
    v_so := 'DN' || to_char(v_ngay, 'YYMMDD') || '-' || lpad(v_n::text, 2, '0');
    while exists (select 1 from nvl_phieu_cap where so_phieu = v_so) loop
      v_n := v_n + 1; v_so := 'DN' || to_char(v_ngay, 'YYMMDD') || '-' || lpad(v_n::text, 2, '0');
    end loop;
    insert into nvl_phieu_cap (so_phieu, ngay, bo_phan, ghi_chu, nguoi_lap, ten_lap, lap_luc)
    values (v_so, v_ngay, p_bo_phan, nullif(trim(coalesce(p_ghi_chu, '')), ''), auth.uid(), nvl_pdc_ten(), now())
    returning id into v_id;
  else
    select * into v from nvl_phieu_cap where id = p_id for update;
    if not found then raise exception 'Không tìm thấy phiếu.'; end if;
    if v.trang_thai not in ('cho_qlbp', 'tra_lai') then raise exception '🔒 Phiếu đã xác nhận, không sửa được.'; end if;
    if v.nguoi_lap is distinct from auth.uid() and not has_role('admin') then
      raise exception '⛔ Chỉ người lập được sửa phiếu.' using errcode = '42501';
    end if;
    v_id := p_id; v_so := v.so_phieu;
    if v.bo_phan <> p_bo_phan then perform nvl_pdc_tb_xong('nvlcap:' || v_id || ':qlbp'); end if;
    update nvl_phieu_cap set ngay = v_ngay, bo_phan = p_bo_phan, ghi_chu = nullif(trim(coalesce(p_ghi_chu, '')), ''),
      trang_thai = 'cho_qlbp', ly_do_tra_lai = null, updated_at = now() where id = v_id;
    delete from nvl_phieu_cap_dong where phieu_id = v_id;
  end if;

  for d in select * from jsonb_array_elements(p_dong) loop
    i := i + 1;
    insert into nvl_phieu_cap_dong (phieu_id, stt, ma_nvl, sl_de_nghi, muc_dich, dvt)
    values (v_id, i, d->>'ma_nvl', (d->>'sl_de_nghi')::numeric, trim(d->>'muc_dich'), coalesce(d->>'dvt', 'kg'));
  end loop;

  perform nvl_pdc_tb(cv_pd_ds_role(array['quan_ly_bo_phan'], p_bo_phan), 'can_duyet', 'nvlcap:' || v_id || ':qlbp', v_id,
    'Xác nhận phiếu cấp NVL ' || v_so || ' (' || p_bo_phan || ')', true);
  return v_id;
end $$;

revoke execute on function public.nvl_pdc_luu(bigint, date, text, text, jsonb) from public, anon;
grant execute on function public.nvl_pdc_luu(bigint, date, text, text, jsonb) to authenticated;
