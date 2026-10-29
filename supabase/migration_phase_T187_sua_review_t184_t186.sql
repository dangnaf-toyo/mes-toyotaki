-- ============================================================================
-- T187 (29/10/2026): sửa theo review trước khi đưa T184 / T185 / T186 (đồng đội) lên production.
--   1. T186: danh sách dụng cụ thêm 'Panme', 'JIG', 'Kiểm bằng mắt' (đang dùng trong bảng tuần kiểm prod).
--   2. T184: chỉ người mở phiếu (nguoi_mo_uid), Trưởng phòng QC, Admin được ĐỔI hạn trả lời đối sách
--      — người trả lời không tự lùi hạn; nhật ký ghi hạn cũ → hạn mới.
--   3. T184: chuông nhắc hạn chỉ gửi Giám đốc SX khi phiếu ĐÃ QUÁ HẠN (các mốc sắp hạn / hôm nay chỉ
--      gửi người mở phiếu, người trả lời đối sách, Trưởng phòng QC).
-- Chạy SAU T184, T185, T186. An toàn chạy lại nhiều lần.
-- ============================================================================

-- ── 1. Dụng cụ kiểm tra cho phép ─────────────────────────────────────────────
create or replace function public.ipqc_kiem_tra_dung_cu()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.dung_cu is not distinct from old.dung_cu then return new; end if;
  end if;
  new.dung_cu := nullif(trim(new.dung_cu), '');
  if new.dung_cu is not null and not (new.dung_cu = any(array[
    'Thước kẹp', 'CMM', 'OMM', 'Máy đo biên dạng', 'Máy đo độ nhám', 'Thước đo cao',
    'Thước lá', 'Máy phân tích nguyên vật liệu', 'Máy kiểm tra độ cứng',
    'Máy kiểm tra lực nén', 'Máy kiểm tra màu sắc', 'Máy đo độ dày sơn',
    'Panme', 'JIG', 'Kiểm bằng mắt'
  ])) then
    raise exception 'Chọn dụng cụ kiểm tra trong danh sách cho phép';
  end if;
  return new;
end $$;
revoke all on function public.ipqc_kiem_tra_dung_cu() from public, anon, authenticated;

-- ── 2. Đổi hạn trả lời đối sách: chỉ người mở phiếu / TP QC / Admin ──────────
create or replace function public.duc_ncp_update_root_cause(p_id_ncp text, p_nguoi_dam_nhiem_doi_sach text, p_nguyen_nhan_phat_sinh text,
  p_nguyen_nhan_luu_xuat text, p_hinh_anh_phat_sinh jsonb, p_hinh_anh_luu_xuat jsonb, p_doi_sach_ps_tam_thoi jsonb, p_doi_sach_ps_lau_dai jsonb,
  p_doi_sach_lx_tam_thoi jsonb, p_doi_sach_lx_lau_dai jsonb, p_user text, p_han_tra_loi_doi_sach date default null)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_trang_thai_duyet text;
  v_han_cu date;
  v_mo_uid uuid;
  v_doi_han boolean;
  v_now timestamptz := now();
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
  select coalesce(nullif(trim(username), ''), email) into p_user from user_roles where user_id = auth.uid();
  select coalesce(rc_trang_thai_duyet, 'nhap'), han_tra_loi_doi_sach, nguoi_mo_uid
    into v_trang_thai_duyet, v_han_cu, v_mo_uid from duc_ncp where id_ncp = p_id_ncp;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu: ' || p_id_ncp); end if;
  if v_trang_thai_duyet in ('cho_duyet', 'da_duyet') then
    return jsonb_build_object('ok', false, 'error', 'Phiếu đang ở trạng thái "' ||
      (case when v_trang_thai_duyet = 'cho_duyet' then 'Chờ duyệt' else 'Đã duyệt' end) ||
      '" — bấm "Mở lại để chỉnh sửa" trước khi sửa.');
  end if;
  v_doi_han := p_han_tra_loi_doi_sach is not null and p_han_tra_loi_doi_sach is distinct from v_han_cu;
  if v_doi_han and auth.uid() is distinct from v_mo_uid and not public.has_role('admin', 'qc_manager') then
    return jsonb_build_object('ok', false, 'error', 'Chỉ người mở phiếu, Trưởng phòng QC hoặc Admin được đổi hạn trả lời đối sách');
  end if;

  update duc_ncp set
    nguoi_dam_nhiem_doi_sach = trim(coalesce(p_nguoi_dam_nhiem_doi_sach, '')),
    nguyen_nhan_phat_sinh = trim(coalesce(p_nguyen_nhan_phat_sinh, '')),
    nguyen_nhan_luu_xuat = trim(coalesce(p_nguyen_nhan_luu_xuat, '')),
    hinh_anh_phat_sinh_json = coalesce(p_hinh_anh_phat_sinh, '[]'::jsonb),
    hinh_anh_luu_xuat_json = coalesce(p_hinh_anh_luu_xuat, '[]'::jsonb),
    doi_sach_ps_tam_thoi_json = coalesce(p_doi_sach_ps_tam_thoi, '[]'::jsonb),
    doi_sach_ps_lau_dai_json = coalesce(p_doi_sach_ps_lau_dai, '[]'::jsonb),
    doi_sach_lx_tam_thoi_json = coalesce(p_doi_sach_lx_tam_thoi, '[]'::jsonb),
    doi_sach_lx_lau_dai_json = coalesce(p_doi_sach_lx_lau_dai, '[]'::jsonb),
    han_tra_loi_doi_sach = coalesce(p_han_tra_loi_doi_sach, han_tra_loi_doi_sach),
    last_updated_at = v_now
  where id_ncp = p_id_ncp;
  perform duc_ncp_append_log(p_id_ncp, 'Cập nhật Nguyên nhân & Đối sách' ||
    case when v_doi_han then ', đổi hạn trả lời ' || coalesce(to_char(v_han_cu, 'DD/MM/YYYY'), '(chưa có)') || ' → ' || to_char(p_han_tra_loi_doi_sach, 'DD/MM/YYYY') else '' end ||
    ' — bởi ' || p_user);

  return jsonb_build_object('ok', true, 'id_ncp', p_id_ncp);
end $$;
revoke execute on function public.duc_ncp_update_root_cause(text, text, text, text, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, text, date) from public, anon;
grant execute on function public.duc_ncp_update_root_cause(text, text, text, text, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, text, date) to authenticated;

-- ── 3. Chuông nhắc hạn: Giám đốc SX chỉ nhận khi quá hạn ─────────────────────
create or replace function public.ncp_quet_nhac_han()
returns integer language plpgsql security definer set search_path = public as $$
declare r duc_ncp%rowtype; cfg ncp_cau_hinh_nhac_han%rowtype;
  hom_nay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  con_ngay integer; moc text; khoa_moc text; ds uuid[]; ds_moi uuid[]; so_gui integer; tong integer := 0;
begin
  -- Khóa toàn lượt quét để cron / lượt thử lại không gửi đồng thời.
  perform pg_advisory_xact_lock(hashtext('ncp_quet_nhac_han'));
  select * into cfg from ncp_cau_hinh_nhac_han where id;
  if not cfg.bat_nhac then return 0; end if;
  for r in select * from duc_ncp where han_tra_loi_doi_sach is not null loop
    if ncp_da_tra_loi(r) then
      perform cv_pd_xong('ncp-han:' || r.id_ncp || ':', true); continue;
    end if;
    con_ngay := r.han_tra_loi_doi_sach - hom_nay;
    moc := case when con_ngay < 0 then 'qua_han' when con_ngay = 0 then 'hom_nay'
      when con_ngay <= cfg.khan_truoc_ngay then 'khan' when con_ngay <= cfg.truoc_han_ngay then 'sap_han' end;
    if moc is null then continue; end if;
    khoa_moc := 'ncp-han:' || r.id_ncp || ':' || r.han_tra_loi_doi_sach || ':' || moc;
    select coalesce(array_agg(distinct x), '{}') into ds from unnest(
      array[r.nguoi_mo_uid] || cv_pd_ds_ten(r.nguoi_mo_case) || cv_pd_ds_ten(r.nguoi_dam_nhiem_doi_sach)
      || cv_pd_ds_role(case when moc = 'qua_han' then array['giam_doc_sx', 'qc_manager'] else array['qc_manager'] end)
    ) x where x is not null;
    -- Cho phép người mới được phân công nhận sự kiện, không gửi lại người đã nhận.
    select coalesce(array_agg(u), '{}') into ds_moi from unnest(ds) u
      where not exists (select 1 from cv_thong_bao t where t.khoa = khoa_moc and t.nguoi_nhan = u);
    so_gui := cv_pd_gui(ds_moi, 'ncp', 'nhac_han', khoa_moc, 'ncp-detail.html?id=' || r.id_ncp,
      'NCP ' || r.id_ncp || ' — ' || case moc when 'qua_han' then 'Quá hạn trả lời đối sách' when 'hom_nay' then 'Đến hạn trả lời hôm nay'
        when 'khan' then 'Khẩn: sắp hết hạn trả lời đối sách' else 'Sắp đến hạn trả lời đối sách' end
      || ' (' || to_char(r.han_tra_loi_doi_sach, 'DD/MM/YYYY') || ').', true);
    insert into ncp_nhac_han_log (khoa, id_ncp, han, moc, nguoi_nhan, so_thong_bao)
      values (khoa_moc, r.id_ncp, r.han_tra_loi_doi_sach, moc, ds, so_gui)
      on conflict (khoa) do update set nguoi_nhan = excluded.nguoi_nhan, so_thong_bao = ncp_nhac_han_log.so_thong_bao + excluded.so_thong_bao;
    tong := tong + so_gui;
  end loop;
  return tong;
end $$;
revoke all on function public.ncp_quet_nhac_han() from public, anon, authenticated;
