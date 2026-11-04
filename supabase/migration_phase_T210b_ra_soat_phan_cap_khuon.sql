-- T210b — Vá theo rà soát độc lập T210 (04/11/2026) + quyết định user: chỉ TỰ DUYỆT (người khai = người duyệt)
-- trong khung 22:00–08:00 (admin / GĐSX luôn được — không còn cấp trên).
--   1. Phiếu không hạ cấp được: cấp phiếu = max(cấp hạng mục, cấp cao nhất từng khai) (cap_max) — bị từ chối rồi khai
--      lại việc nhẹ hơn vẫn phải người duyệt cấp cũ.
--   2. "Không tác động vào khuôn": chỉ trưởng ca / QLBP Đúc / GĐSX / admin; cấm khi phiếu đã từng khai việc (cap_max ≥ 0 có
--      hạng mục) hoặc tổ khuôn đã ghi giờ bắt đầu.
--   3. F1 tự đóng khi IPQC OK (duc_close_f1_incident_if_open) cũng phải qua kiểm tra phân cấp.
--   4. Đóng sự cố A2/B1/F1 (trong phạm vi áp dụng) phải có phiếu; quyền vượt IPQC không vượt phân cấp.
--   5. Check sheet: mốc áp dụng theo giờ bắt đầu ĐÃ LƯU (không theo giờ người dùng nhập); chặn giờ bắt đầu tương lai /
--      sớm hơn ngày KH − 1 ngày.
--   7. Giờ bắt đầu so với lần duyệt ĐẦU TIÊN (duyet_luc_dau) — phát sinh việc mới giữa chừng không bắt sửa giờ.
--   8. Khai thêm việc mới (không nằm trong bộ đã duyệt) → cam kết an toàn phải tick lại.
--  11. Duyệt kèm cap_nhat_luc của bản đang xem — phiếu vừa bị sửa thì từ chối duyệt.
--  12–13. Danh sách chờ duyệt có loại sự cố đang mở; ap_dung check sheet khớp server.
--  Chuông: người khai không có người duyệt khác cùng cấp (vd tổ trưởng tự khai) → gửi thêm cấp trên.

alter table public.duc_khuon_can_thiep add column if not exists cap_max int not null default 0;
alter table public.duc_khuon_can_thiep add column if not exists duyet_luc_dau timestamptz;
update public.duc_khuon_can_thiep set cap_max = greatest(cap_max, coalesce(cap, 0)),
  duyet_luc_dau = coalesce(duyet_luc_dau, case when trang_thai = 'da_duyet' then duyet_luc end);

create or replace function public.duc_khuon_ct_tu_duyet_duoc() returns boolean
language sql stable security definer set search_path to 'public' as $$
  select extract(hour from (now() at time zone 'Asia/Ho_Chi_Minh')) >= 22
      or extract(hour from (now() at time zone 'Asia/Ho_Chi_Minh')) < 8
      or exists (select 1 from user_roles u where u.user_id = auth.uid() and u.role in ('admin', 'giam_doc_sx'));
$$;

-- Quyền duyệt 1 phiếu cụ thể (áp quy tắc tự duyệt).
create or replace function public.duc_khuon_ct_quyen_phieu(p_cap int, p_de_nghi_uid uuid) returns text
language sql stable security definer set search_path to 'public' as $$
  select case when p_de_nghi_uid = auth.uid() and not duc_khuon_ct_tu_duyet_duoc() then null
              else duc_khuon_ct_quyen_duyet(p_cap) end;
$$;

-- Kiểm tra chặn cứng (thay bản T210).
create or replace function public.duc_khuon_ct_kiem(p_nguon text, p_nguon_id text, p_muc text, p_bat_dau timestamptz default null)
returns text
language plpgsql stable security definer set search_path to 'public' as $$
declare n record; c duc_khuon_can_thiep; v_cap_txt text; v_bd_luu timestamptz;
begin
  select * into n from duc_khuon_ct_nguon(p_nguon, p_nguon_id);
  if not n.o_ok then return null; end if;
  if p_nguon = 'xlbt' and n.o_moc < duc_khuon_ct_moc() then return null; end if;
  if p_nguon = 'cs' then   -- T210b: theo giờ bắt đầu đã lưu, không theo giờ đang nhập
    select s.gio_bat_dau into v_bd_luu from duc_khuon_checksheet s where s.id_ke_hoach::text = p_nguon_id;
    if v_bd_luu is not null and v_bd_luu < duc_khuon_ct_moc() then return null; end if;
  end if;

  select * into c from duc_khuon_can_thiep where nguon = p_nguon and nguon_id = p_nguon_id;
  if c.id is null then
    if p_muc in ('giao_qc', 'dong') then
      return '⛔ Chưa khai can thiệp khuôn cho sự cố ' || p_nguon_id || ' — chưa được '
        || case p_muc when 'giao_qc' then 'giao QC' else 'đóng sự cố' end
        || '. Bấm "🔧 Can thiệp khuôn" để chọn việc đã / đang làm trên khuôn'
        || case when n.o_loai = 'A2' then '' else ' (hoặc trưởng ca chọn "Không tác động vào khuôn" nếu chỉ chỉnh thông số / máy)' end || '.';
    end if;
    return '⛔ Chưa chọn hạng mục công việc can thiệp khuôn — chọn việc sẽ làm ở khung "Cấp công việc & phê duyệt" trước khi bắt đầu.';
  end if;

  if c.trang_thai = 'khong_tac_dong' then
    if p_muc = 'bat_dau' then
      return '⛔ Sự cố này đang khai "Không tác động vào khuôn" — nếu tổ khuôn phải xử lý khuôn, chọn hạng mục công việc.';
    end if;
    return null;
  end if;
  v_cap_txt := 'cấp ' || c.cap || case c.cap when 1 then ' (Tổ trưởng khuôn duyệt)' when 2 then ' (QLBP Đúc duyệt)' when 3 then ' (Giám đốc SX duyệt)' else '' end;
  if c.trang_thai = 'cho_duyet' then
    return '⛔ Công việc can thiệp khuôn ' || v_cap_txt || ' đang CHỜ DUYỆT — chưa được '
      || case p_muc when 'bat_dau' then 'bắt đầu xử lý' when 'giao_qc' then 'giao QC' else 'đóng sự cố' end || '.';
  end if;
  if c.trang_thai = 'tu_choi' then
    return '⛔ Công việc can thiệp khuôn ' || v_cap_txt || ' đã bị TỪ CHỐI (' || coalesce(c.ly_do_tu_choi, '') || ') — khai lại hạng mục để gửi duyệt lại.';
  end if;
  if jsonb_array_length(c.an_toan) = 0 then
    return '⛔ Chưa tick cam kết an toàn trước khi can thiệp khuôn (ngắt nguồn, treo khoá, không dùng búa / máy mài trên bề mặt tạo hình…).';
  end if;
  if p_muc = 'bat_dau' and p_bat_dau is not null and c.cap >= 1 and coalesce(c.duyet_luc_dau, c.duyet_luc) is not null
     and p_bat_dau < coalesce(c.duyet_luc_dau, c.duyet_luc) - interval '5 minutes' then
    return '⛔ Giờ bắt đầu xử lý (' || to_char(p_bat_dau at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ') sớm hơn giờ được duyệt ('
      || to_char(coalesce(c.duyet_luc_dau, c.duyet_luc) at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ') — không được làm trước khi duyệt.';
  end if;
  return null;
end $$;

-- Khai hạng mục (thay bản T210): không hạ cấp, tự duyệt theo khung giờ, cam kết an toàn reset khi thêm việc mới.
create or replace function public.duc_khuon_ct_luu(p_nguon text, p_nguon_id text, p_hang_muc text[],
  p_khong_chac boolean default false, p_mo_ta text default '') returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare
  n record; c duc_khuon_can_thiep; v_items jsonb; v_n int; v_cap_hm int; v_cap int; v_tt text; v_quyen text;
  v_ten text := (select o_ten from duc_khuon_bd_nguoi_hien_tai());
  v_giu_duyet boolean := false; v_id bigint; v_dem boolean := false; v_nhan uuid[];
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if not duc_khuon_ct_duoc_khai(p_nguon) then
    return jsonb_build_object('ok', false, 'error', 'Tài khoản không được khai công việc can thiệp khuôn');
  end if;
  select * into n from duc_khuon_ct_nguon(p_nguon, p_nguon_id);
  if not n.o_ok then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố / lịch bảo dưỡng ' || coalesce(p_nguon_id, '')); end if;
  if n.o_xong then return jsonb_build_object('ok', false, 'error', 'Phiếu đã hoàn thành — không đổi hạng mục được nữa'); end if;
  if coalesce(cardinality(p_hang_muc), 0) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Chọn ít nhất 1 hạng mục công việc');
  end if;

  select jsonb_agg(jsonb_build_object('ma', d.ma, 'cap', d.cap, 'noi_dung', d.noi_dung) order by d.thu_tu), count(*), max(d.cap)
    into v_items, v_n, v_cap_hm
  from duc_khuon_ct_danh_muc d
  where d.loai = 'cong_viec' and d.hieu_luc and d.ma = any(p_hang_muc);
  if v_n <> (select count(distinct x) from unnest(p_hang_muc) x) then
    return jsonb_build_object('ok', false, 'error', 'Có hạng mục không hợp lệ — tải lại trang');
  end if;
  v_cap_hm := least(3, v_cap_hm + case when coalesce(p_khong_chac, false) then 1 else 0 end);

  select * into c from duc_khuon_can_thiep where nguon = p_nguon and nguon_id = p_nguon_id for update;
  -- Đã duyệt mà khai lại trong phạm vi đã duyệt (không thêm việc mới, không lên cấp) → giữ duyệt.
  v_giu_duyet := c.id is not null and c.trang_thai = 'da_duyet' and v_cap_hm <= coalesce(c.cap, 0)
    and not exists (select 1 from jsonb_array_elements(v_items) i
                    where not exists (select 1 from jsonb_array_elements(c.hang_muc_duyet) j where j->>'ma' = i->>'ma'));
  -- T210b: phiếu KHÔNG hạ cấp — giữ cấp cao nhất từng khai (bị từ chối rồi khai việc nhẹ hơn vẫn phải người duyệt cấp cũ).
  v_cap := case when v_giu_duyet then c.cap else greatest(v_cap_hm, coalesce(c.cap_max, 0)) end;
  v_quyen := duc_khuon_ct_quyen_duyet(v_cap);
  -- T210b: tự duyệt (người khai có thẩm quyền) chỉ trong 22:00–08:00, admin / GĐSX luôn được.
  if v_quyen is not null and not duc_khuon_ct_tu_duyet_duoc() then v_quyen := null; end if;
  v_tt := case when v_cap = 0 or v_giu_duyet or v_quyen is not null then 'da_duyet' else 'cho_duyet' end;
  v_dem := v_tt = 'da_duyet' and not v_giu_duyet and v_cap > 0 and v_quyen like 'Trưởng ca%';

  insert into duc_khuon_can_thiep as t (nguon, nguon_id, ma_khuon, ma_may, ma_sp, hang_muc, hang_muc_duyet, khong_chac, cap, cap_max, mo_ta,
      trang_thai, nguoi_de_nghi, de_nghi_uid, de_nghi_luc, nguoi_duyet, duyet_uid, duyet_luc, duyet_luc_dau, vai_tro_duyet, duyet_thay_ca_dem)
  values (p_nguon, p_nguon_id, n.o_ma_khuon, n.o_ma_may, n.o_ma_sp, v_items,
      case when v_tt = 'da_duyet' then v_items else '[]'::jsonb end, coalesce(p_khong_chac, false), v_cap, v_cap, coalesce(trim(p_mo_ta), ''),
      v_tt, v_ten, auth.uid(), now(),
      case when v_tt = 'da_duyet' then case when v_cap = 0 then '' else v_ten end end,
      case when v_tt = 'da_duyet' and v_cap > 0 then auth.uid() end,
      case when v_tt = 'da_duyet' then now() end,
      case when v_tt = 'da_duyet' then now() end,
      case when v_tt = 'da_duyet' then case when v_cap = 0 then 'Cấp 0 — không cần duyệt' else v_quyen || ' — tự duyệt khi khai' end end,
      v_dem)
  on conflict (nguon, nguon_id) do update set
    ma_khuon = excluded.ma_khuon, ma_may = coalesce(excluded.ma_may, t.ma_may), ma_sp = coalesce(excluded.ma_sp, t.ma_sp),
    hang_muc = excluded.hang_muc, khong_chac = excluded.khong_chac, cap = excluded.cap,
    cap_max = greatest(t.cap_max, excluded.cap), mo_ta = excluded.mo_ta,
    trang_thai = excluded.trang_thai,
    hang_muc_duyet = case when v_giu_duyet then t.hang_muc_duyet else excluded.hang_muc_duyet end,
    nguoi_de_nghi = case when v_giu_duyet then t.nguoi_de_nghi else excluded.nguoi_de_nghi end,
    de_nghi_uid = case when v_giu_duyet then t.de_nghi_uid else excluded.de_nghi_uid end,
    de_nghi_luc = case when v_giu_duyet then t.de_nghi_luc else excluded.de_nghi_luc end,
    nguoi_duyet = case when v_giu_duyet then t.nguoi_duyet else excluded.nguoi_duyet end,
    duyet_uid = case when v_giu_duyet then t.duyet_uid else excluded.duyet_uid end,
    duyet_luc = case when v_giu_duyet then t.duyet_luc else excluded.duyet_luc end,
    duyet_luc_dau = coalesce(t.duyet_luc_dau, excluded.duyet_luc_dau),
    vai_tro_duyet = case when v_giu_duyet then t.vai_tro_duyet else excluded.vai_tro_duyet end,
    duyet_thay_ca_dem = case when v_giu_duyet then t.duyet_thay_ca_dem else excluded.duyet_thay_ca_dem end,
    qlbp_xac_nhan = case when v_giu_duyet then t.qlbp_xac_nhan end,
    qlbp_xac_nhan_luc = case when v_giu_duyet then t.qlbp_xac_nhan_luc end,
    -- T210b: thêm việc mới → cam kết an toàn phải tick lại
    an_toan = case when v_giu_duyet then t.an_toan else '[]'::jsonb end,
    nguoi_an_toan = case when v_giu_duyet then t.nguoi_an_toan end,
    an_toan_luc = case when v_giu_duyet then t.an_toan_luc end,
    ly_do_tu_choi = null, cap_nhat_luc = now()
  returning id into v_id;

  perform duc_khuon_ct_ghi_nk(v_id, 'khai', jsonb_build_object('hang_muc', v_items, 'cap', v_cap, 'cap_hang_muc', v_cap_hm,
    'khong_chac', coalesce(p_khong_chac, false), 'trang_thai', v_tt,
    'vai_tro_duyet', case when v_tt = 'da_duyet' and not v_giu_duyet then coalesce(v_quyen, 'Cấp 0') end, 'mo_ta', p_mo_ta));

  begin
    perform cv_pd_xong('khuon_ct:' || v_id);
    if v_tt = 'cho_duyet' then
      v_nhan := array(select u from unnest(duc_khuon_ct_nguoi_duyet_ds(v_cap)) u where u is distinct from auth.uid());
      if cardinality(v_nhan) = 0 and v_cap < 3 then v_nhan := duc_khuon_ct_nguoi_duyet_ds(v_cap + 1); end if;   -- không còn ai cùng cấp → cấp trên
      perform cv_pd_gui(v_nhan, 'bd_khuon', 'duyet_can_thiep', 'khuon_ct:' || v_id,
        'bao-duong-khuon-tuan.html#cardCt',
        '🔧 Chờ duyệt cấp ' || v_cap || ': khuôn ' || coalesce(n.o_ma_khuon, '?') || coalesce(' (' || n.o_ma_may || ')', '') || ' — '
        || left((select string_agg(i->>'noi_dung', '; ') from jsonb_array_elements(v_items) i), 160) || ' · đề nghị: ' || coalesce(v_ten, ''), true);
    end if;
    if v_dem then
      perform cv_pd_gui(cv_pd_ds_role(array['quan_ly_bo_phan'], 'Đúc'), 'bd_khuon', 'bao_cao_duyet_dem', 'khuon_ct_bc:' || v_id,
        'bao-duong-khuon-tuan.html#cardCt',
        '🌙 Ca đêm trưởng ca ' || coalesce(v_ten, '') || ' đã duyệt cấp ' || v_cap || ' khuôn ' || coalesce(n.o_ma_khuon, '?') || ' — mời QLBP Đúc xác nhận.', true);
    end if;
  exception when others then raise warning 'duc_khuon_ct_luu thông báo: %', sqlerrm;
  end;

  return jsonb_build_object('ok', true, 'id', v_id, 'cap', v_cap, 'cap_hang_muc', v_cap_hm, 'trang_thai', v_tt, 'giu_duyet', v_giu_duyet);
end $$;

-- "Không tác động vào khuôn" (thay bản T210): chỉ trưởng ca / QLBP Đúc / GĐSX / admin; phiếu chưa từng khai việc,
-- tổ khuôn chưa bắt đầu.
create or replace function public.duc_khuon_ct_khong_tac_dong(p_id_su_co text, p_ghi_chu text default '') returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare n record; c duc_khuon_can_thiep; v_id bigint; v_ten text := (select o_ten from duc_khuon_bd_nguoi_hien_tai());
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if not exists (select 1 from user_roles u where u.user_id = auth.uid() and (u.role in ('truong_ca', 'admin', 'giam_doc_sx')
                 or (u.role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(u.bo_phan_phu_trach, '{}'))))) then
    return jsonb_build_object('ok', false, 'error', 'Chỉ trưởng ca / QLBP Đúc khai "Không tác động vào khuôn"');
  end if;
  if coalesce(trim(p_ghi_chu), '') = '' then return jsonb_build_object('ok', false, 'error', 'Ghi rõ đã xử lý gì (chỉnh thông số / máy)'); end if;
  select * into n from duc_khuon_ct_nguon('xlbt', p_id_su_co);
  if not n.o_ok then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố A2/B1/F1 ' || coalesce(p_id_su_co, '')); end if;
  if n.o_loai = 'A2' then
    return jsonb_build_object('ok', false, 'error', 'Sự cố A2 (khuôn) luôn có tác động vào khuôn — chọn hạng mục công việc.');
  end if;
  select * into c from duc_khuon_can_thiep where nguon = 'xlbt' and nguon_id = p_id_su_co for update;
  if c.id is not null and c.trang_thai <> 'khong_tac_dong' then
    return jsonb_build_object('ok', false, 'error', 'Sự cố đã khai công việc can thiệp khuôn cấp ' || c.cap || ' (' || coalesce(c.nguoi_de_nghi, '') ||
      case when c.trang_thai = 'tu_choi' then ', đã bị từ chối' else '' end || ') — không chuyển sang "Không tác động" được.');
  end if;
  if exists (select 1 from duc_khuon_xu_ly_bat_thuong x where x.id_su_co = p_id_su_co and x.bat_dau is not null) then
    return jsonb_build_object('ok', false, 'error', 'Tổ khuôn đã ghi bắt đầu xử lý sự cố này — không khai "Không tác động" được.');
  end if;
  insert into duc_khuon_can_thiep as t (nguon, nguon_id, ma_khuon, ma_may, ma_sp, trang_thai, mo_ta, nguoi_de_nghi, de_nghi_uid, de_nghi_luc)
  values ('xlbt', p_id_su_co, n.o_ma_khuon, n.o_ma_may, n.o_ma_sp, 'khong_tac_dong', trim(p_ghi_chu), v_ten, auth.uid(), now())
  on conflict (nguon, nguon_id) do update set mo_ta = excluded.mo_ta, nguoi_de_nghi = excluded.nguoi_de_nghi,
    de_nghi_uid = excluded.de_nghi_uid, de_nghi_luc = now(), cap_nhat_luc = now()
  returning id into v_id;
  perform duc_khuon_ct_ghi_nk(v_id, 'khong_tac_dong', jsonb_build_object('ghi_chu', p_ghi_chu));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- Duyệt / từ chối (thay bản T210): thêm p_cap_nhat_luc (bản đang xem), áp quy tắc tự duyệt.
drop function if exists public.duc_khuon_ct_duyet(bigint, boolean, text);
create or replace function public.duc_khuon_ct_duyet(p_id bigint, p_dong_y boolean, p_ly_do text default '', p_cap_nhat_luc timestamptz default null) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare c duc_khuon_can_thiep; v_quyen text; v_ten text := (select o_ten from duc_khuon_bd_nguoi_hien_tai()); v_dem boolean;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into c from duc_khuon_can_thiep where id = p_id for update;
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu'); end if;
  if c.trang_thai <> 'cho_duyet' then return jsonb_build_object('ok', false, 'error', 'Phiếu không ở trạng thái chờ duyệt (đã có người xử lý) — tải lại'); end if;
  if p_cap_nhat_luc is not null and abs(extract(epoch from (c.cap_nhat_luc - p_cap_nhat_luc))) > 0.5 then
    return jsonb_build_object('ok', false, 'error', 'Phiếu vừa được sửa hạng mục — tải lại để xem nội dung mới rồi duyệt.');
  end if;
  if c.de_nghi_uid = auth.uid() and not duc_khuon_ct_tu_duyet_duoc() then
    return jsonb_build_object('ok', false, 'error', 'Không tự duyệt việc do chính mình khai (chỉ được tự duyệt trong 22:00–08:00) — nhờ người duyệt khác.');
  end if;
  v_quyen := duc_khuon_ct_quyen_duyet(c.cap);
  if v_quyen is null then
    return jsonb_build_object('ok', false, 'error', 'Không có quyền duyệt cấp ' || c.cap || ' — cần ' ||
      case c.cap when 1 then 'Tổ trưởng khuôn' when 2 then 'Quản lý bộ phận Đúc' else 'Giám đốc sản xuất' end || ' trở lên'
      || case when c.cap <= 2 then ' (ca đêm 18:00–06:00: trưởng ca được duyệt thay)' else '' end || '.');
  end if;
  if not p_dong_y and coalesce(trim(p_ly_do), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'Nhập lý do từ chối');
  end if;
  v_dem := p_dong_y and v_quyen like 'Trưởng ca%';
  update duc_khuon_can_thiep set
    trang_thai = case when p_dong_y then 'da_duyet' else 'tu_choi' end,
    hang_muc_duyet = case when p_dong_y then hang_muc else '[]'::jsonb end,
    nguoi_duyet = v_ten, duyet_uid = auth.uid(), duyet_luc = now(),
    duyet_luc_dau = case when p_dong_y then coalesce(duyet_luc_dau, now()) else duyet_luc_dau end,
    vai_tro_duyet = v_quyen, duyet_thay_ca_dem = v_dem, qlbp_xac_nhan = null, qlbp_xac_nhan_luc = null,
    ly_do_tu_choi = case when p_dong_y then null else trim(p_ly_do) end, cap_nhat_luc = now()
  where id = p_id;
  perform duc_khuon_ct_ghi_nk(p_id, case when p_dong_y then 'duyet' else 'tu_choi' end,
    jsonb_build_object('vai_tro', v_quyen, 'ly_do', p_ly_do, 'cap', c.cap, 'tu_duyet', c.de_nghi_uid = auth.uid()));
  begin
    perform cv_pd_xong('khuon_ct:' || p_id);
    perform cv_pd_gui(array[c.de_nghi_uid], 'bd_khuon', case when p_dong_y then 'ct_da_duyet' else 'ct_tu_choi' end, 'khuon_ct_kq:' || p_id,
      'bao-duong-khuon-tuan.html#cardCt',
      case when p_dong_y then '✅ Đã duyệt cấp ' || c.cap || ' khuôn ' || coalesce(c.ma_khuon, '?') || ' (' || v_ten || ') — tick cam kết an toàn rồi bắt đầu.'
           else '❌ Từ chối cấp ' || c.cap || ' khuôn ' || coalesce(c.ma_khuon, '?') || ' (' || v_ten || '): ' || trim(p_ly_do) end, false);
    if v_dem then
      perform cv_pd_gui(cv_pd_ds_role(array['quan_ly_bo_phan'], 'Đúc'), 'bd_khuon', 'bao_cao_duyet_dem', 'khuon_ct_bc:' || p_id,
        'bao-duong-khuon-tuan.html#cardCt',
        '🌙 Ca đêm trưởng ca ' || coalesce(v_ten, '') || ' đã duyệt cấp ' || c.cap || ' khuôn ' || coalesce(c.ma_khuon, '?') || ' — mời QLBP Đúc xác nhận.', true);
    end if;
  exception when others then raise warning 'duc_khuon_ct_duyet thông báo: %', sqlerrm;
  end;
  return jsonb_build_object('ok', true, 'trang_thai', case when p_dong_y then 'da_duyet' else 'tu_choi' end, 'vai_tro', v_quyen);
end $$;

-- Lấy phiếu (thay bản T210): quyền duyệt theo quy tắc tự duyệt; ap_dung check sheet khớp server.
create or replace function public.duc_khuon_ct_lay(p_nguon text, p_nguon_id text) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
declare n record; c duc_khuon_can_thiep; v_nk jsonb; v_bd timestamptz;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into n from duc_khuon_ct_nguon(p_nguon, p_nguon_id);
  select * into c from duc_khuon_can_thiep where nguon = p_nguon and nguon_id = p_nguon_id;
  if p_nguon = 'cs' then select s.gio_bat_dau into v_bd from duc_khuon_checksheet s where s.id_ke_hoach::text = p_nguon_id; end if;
  select coalesce(jsonb_agg(jsonb_build_object('su_kien', k.su_kien, 'du_lieu', k.du_lieu, 'nguoi', k.nguoi, 'thoi_diem', k.thoi_diem)
           order by k.thoi_diem), '[]'::jsonb) into v_nk
    from duc_khuon_can_thiep_nhat_ky k where k.id_ct = c.id;
  return jsonb_build_object('ok', true,
    'ct', case when c.id is null then null else to_jsonb(c) end,
    'nhat_ky', v_nk,
    'nguon', jsonb_build_object('ok', n.o_ok, 'ma_khuon', n.o_ma_khuon, 'ma_may', n.o_ma_may, 'ma_sp', n.o_ma_sp,
                                'loai', n.o_loai, 'xong', n.o_xong),
    'ap_dung', n.o_ok and case when p_nguon = 'cs' then (v_bd is null or v_bd >= duc_khuon_ct_moc()) else n.o_moc >= duc_khuon_ct_moc() end,
    'duoc_khai', duc_khuon_ct_duoc_khai(p_nguon),
    'duoc_khong_tac_dong', exists (select 1 from user_roles u where u.user_id = auth.uid() and (u.role in ('truong_ca', 'admin', 'giam_doc_sx')
                 or (u.role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(u.bo_phan_phu_trach, '{}'))))),
    'quyen_duyet', case when c.id is null then null else duc_khuon_ct_quyen_phieu(c.cap, c.de_nghi_uid) end,
    'tu_duyet_duoc', duc_khuon_ct_tu_duyet_duoc(),
    'la_ca_dem', duc_khuon_ct_la_ca_dem());
end $$;

-- Danh sách chờ duyệt (thay bản T210): quyền theo quy tắc tự duyệt, loại sự cố cả khi đang mở.
create or replace function public.duc_khuon_ct_cho_duyet() returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
declare v_out jsonb; v_la_qlbp boolean;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  v_la_qlbp := exists (select 1 from user_roles u where u.user_id = auth.uid() and (u.role in ('admin', 'giam_doc_sx')
                 or (u.role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(u.bo_phan_phu_trach, '{}')))));
  select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object(
           'quyen_duyet', duc_khuon_ct_quyen_phieu(c.cap, c.de_nghi_uid),
           'quyen_xac_nhan', v_la_qlbp and c.duyet_thay_ca_dem and c.qlbp_xac_nhan is null,
           'loai_nguon', case when c.nguon = 'xlbt'
               then (select o_loai from duc_khuon_ct_nguon(c.nguon, c.nguon_id))
               else (select k.loai from duc_khuon_bd_kh_tuan k where k.id::text = c.nguon_id) end)
         order by (c.trang_thai = 'cho_duyet') desc, c.de_nghi_luc), '[]'::jsonb)
    into v_out
  from duc_khuon_can_thiep c
  where c.trang_thai = 'cho_duyet'
     or (c.duyet_thay_ca_dem and c.qlbp_xac_nhan is null and c.trang_thai in ('da_duyet') and c.duyet_luc > now() - interval '30 days');
  return jsonb_build_object('ok', true, 'rows', v_out, 'la_ca_dem', duc_khuon_ct_la_ca_dem());
end $$;

-- ── Vá thêm hàm có sẵn ──────────────────────────────────────────────────────
do $patch$
declare d text; n text;
begin
  -- 3. F1 tự đóng khi IPQC OK: phiếu can thiệp chưa đạt → không tự đóng (trưởng ca đóng sau khi đủ điều kiện).
  d := pg_get_functiondef('public.duc_close_f1_incident_if_open(text,text)'::regprocedure);
  if position('duc_khuon_ct_kiem' in d) = 0 then
    n := replace(d, E'  select count(*) + 1 into v_stt from duc_su_co_log',
      E'  -- T210b: công việc can thiệp khuôn chưa duyệt / chưa cam kết an toàn / chưa khai → KHÔNG tự đóng F1.\n'
      || E'  if v_cht.open_id_su_co is not null and duc_khuon_ct_kiem(''xlbt'', v_cht.open_id_su_co, ''dong'') is not null then\n'
      || E'    return false;\n'
      || E'  end if;\n\n'
      || E'  select count(*) + 1 into v_stt from duc_su_co_log');
    if n = d or (length(n) - length(replace(n, 'duc_khuon_ct_kiem', ''))) <> length('duc_khuon_ct_kiem') then
      raise exception 'T210b: không vá được duc_close_f1_incident_if_open';
    end if;
    execute n;
  end if;

  -- 5. Check sheet: chặn giờ bắt đầu ở tương lai / sớm hơn ngày KH − 1 ngày.
  d := pg_get_functiondef('public.duc_khuon_cs_luu(bigint,jsonb,boolean)'::regprocedure);
  if position('T210b' in d) = 0 then
    n := replace(d, E'  -- T210: phân cấp phê duyệt can thiệp khuôn.\n',
      E'  -- T210b: giờ bắt đầu hợp lệ (không lùi để né mốc áp dụng phân cấp).\n'
      || E'  if v_bd is not null and v_bd > now() + interval ''5 minutes'' then\n'
      || E'    return jsonb_build_object(''ok'', false, ''error'', ''Giờ bắt đầu ở tương lai'');\n'
      || E'  end if;\n'
      || E'  if v_bd is not null and v_bd < (v_kh.ngay - 1)::timestamp at time zone ''Asia/Ho_Chi_Minh''\n'
      || E'     and v_bd is distinct from v_cs.gio_bat_dau then\n'
      || E'    return jsonb_build_object(''ok'', false, ''error'', ''Giờ bắt đầu sớm hơn ngày kế hoạch quá 1 ngày'');\n'
      || E'  end if;\n'
      || E'  -- T210: phân cấp phê duyệt can thiệp khuôn.\n');
    if n = d then raise exception 'T210b: không vá được duc_khuon_cs_luu'; end if;
    execute n;
  end if;
end $patch$;

-- ── Quyền ───────────────────────────────────────────────────────────────────
revoke execute on function public.duc_khuon_ct_tu_duyet_duoc(), public.duc_khuon_ct_quyen_phieu(int, uuid)
  from public, anon, authenticated;
revoke execute on function public.duc_khuon_ct_duyet(bigint, boolean, text, timestamptz) from public, anon;
grant execute on function public.duc_khuon_ct_duyet(bigint, boolean, text, timestamptz) to authenticated;
