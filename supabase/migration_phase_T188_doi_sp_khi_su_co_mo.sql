-- =============================================================================
-- T188 (30/10/2026) — 2 sửa đổi cho Dashboard Đúc
--
-- (1) "Xong" sự cố: khi IPQC đã kiểm OK / Cảnh báo cho sự cố thì KHÔNG bắt buộc
--     bấm "📦 Hoàn thành mẫu & giao QC" (T180) nữa. Trước đây SC-DC5-1030-1553 đã
--     IPQC OK nhưng vẫn không đóng được vì chưa bấm giao QC. Câu báo lỗi sửa lại
--     cho rõ là thiếu bước giao QC (không phải thiếu kết quả IPQC).
--
-- (2) Đổi sản phẩm khi sự cố ĐANG MỞ (sự cố lớn chưa xử lý ngay được → đổi khuôn
--     khác để máy không dừng lâu):
--     - duc_change_product / _paired / _pair_out không còn chặn "đang có sự cố".
--     - Mọi sự cố đang mở của dòng cũ (cả sự cố phụ T178, cả dòng ghép cặp khuôn kép)
--       được kết thúc tại GIỜ BẮT ĐẦU ĐỔI KHUÔN → thời gian dừng ghi đến lúc đó, rồi
--       sự cố C3 Đổi khuôn của dòng mới nối tiếp. Không đòi IPQC / giao QC (SP đã
--       xuống). Nội dung xử lý ghi "[Chưa xử lý xong — ...]".
--     - Checkpoint IPQC sau sự cố còn chờ của dòng cũ → het_hieu_luc.
--     - Sự cố khuôn / chất lượng (A2, B1, C3, F1) → vấn đề khuôn (duc_van_de_khuon)
--       trạng thái Mở, cờ chan_len_khuon = true, chuông cho tổ khuôn (to_truong_khuon,
--       nhan_vien_bao_duong_khuon). Khuôn KHÔNG lên lại máy được (trigger) cho đến khi
--       tổ khuôn ghi nội dung xử lý ở trang Vấn đề khuôn (→ Chờ xác nhận); sau đó lên
--       khuôn vẫn qua bước "Đã nắm thông tin" (T127) + IPQC xác nhận tái phát như cũ.
--
-- Cách vá: các hàm cũ được sửa bằng replace() trên pg_get_functiondef (có kiểm tra
-- đoạn cần thay phải tồn tại) — chạy lại lần 2 sẽ bỏ qua hàm đã có dấu T188.
-- Trạng thái: đã chạy DB staging + prod 30/10/2026.
-- =============================================================================

alter table duc_van_de_khuon add column if not exists chan_len_khuon boolean not null default false;

create or replace function pg_temp.t188_thay(p_def text, p_cu text, p_moi text, p_ten text)
returns text language plpgsql as $f$
begin
  if position(p_cu in p_def) = 0 then
    raise exception 'T188: không thấy đoạn cần thay trong %: %', p_ten, left(p_cu, 100);
  end if;
  return replace(p_def, p_cu, p_moi);
end $f$;

-- -----------------------------------------------------------------------------
-- duc_resolve_incident: (1) bỏ bắt buộc giao QC khi IPQC đã OK; (2) cờ duc.doi_sp_dong
-- -----------------------------------------------------------------------------
do $do$
declare d text := pg_get_functiondef('public.duc_resolve_incident'::regproc);
begin
  if position('T188' in d) > 0 then return; end if;
  d := pg_temp.t188_thay(d,
    $q$v_vuot_ipqc boolean := false;$q$,
    $q$v_vuot_ipqc boolean := false;
  v_doi_sp text := nullif(current_setting('duc.doi_sp_dong', true), '');   -- T188: đóng vì đổi SP (duc_doi_sp_dong_su_co)$q$,
    'duc_resolve_incident');
  d := pg_temp.t188_thay(d,
    $q$if (v_ipqc->>'can_ipqc')::boolean and not v_vuot_ipqc and v_cht.open_id_su_co is not null$q$,
    $q$if (v_ipqc->>'can_ipqc')::boolean and not (v_ipqc->>'ok')::boolean   -- T188: IPQC đã OK/Cảnh báo thì không cần giao QC
     and not v_vuot_ipqc and v_doi_sp is null and v_cht.open_id_su_co is not null$q$,
    'duc_resolve_incident');
  d := pg_temp.t188_thay(d,
    $q$chưa bấm "📦 Hoàn thành mẫu & giao QC". Xử lý xong và lấy mẫu thì bấm nút đó để IPQC kiểm; IPQC kiểm OK hoặc Cảnh báo rồi mới bấm "Xong".$q$,
    $q$chưa bấm "📦 Hoàn thành mẫu & giao QC" (IPQC cũng chưa kiểm OK). Xử lý xong, lấy mẫu thì bấm nút đó để IPQC kiểm; IPQC kiểm OK hoặc Cảnh báo rồi bấm "Xong".$q$,
    'duc_resolve_incident');
  d := pg_temp.t188_thay(d,
    $q$if (v_ipqc->>'can_ipqc')::boolean and not (v_ipqc->>'ok')::boolean and not v_vuot_ipqc then$q$,
    $q$if (v_ipqc->>'can_ipqc')::boolean and not (v_ipqc->>'ok')::boolean and not v_vuot_ipqc and v_doi_sp is null then$q$,
    'duc_resolve_incident');
  d := pg_temp.t188_thay(d,
    $q$  select count(*) into v_seg_count from duc_split_incident_by_shift($q$,
    $q$  if v_doi_sp is not null then   -- T188
    v_noi_dung_combined := case when v_noi_dung_combined <> '' then v_noi_dung_combined || E'\n' else '' end
      || '[Chưa xử lý xong — kết thúc sự cố lúc đổi sang SP ' || v_doi_sp || '. Khuôn '
      || coalesce(nullif(trim(v_cht.so_khuon), ''), '?') || ' xuống máy, tổ khuôn xử lý dứt điểm]';
  end if;

  select count(*) into v_seg_count from duc_split_incident_by_shift($q$,
    'duc_resolve_incident');
  execute d;
end $do$;

-- -----------------------------------------------------------------------------
-- Kết thúc mọi sự cố đang mở của 1 dòng tại giờ bắt đầu đổi khuôn (gọi từ các hàm đổi SP)
-- -----------------------------------------------------------------------------
create or replace function public.duc_doi_sp_dong_su_co(p_id_dong text, p_gio timestamptz, p_ma_sp_moi text, p_user text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  c record; r jsonb; v_ids text[] := '{}'; v_n int := 0; v_mk text; v_vd text; v_bao text;
begin
  loop
    select id_dong, ngay, ca, ma_may, ma_sp, so_khuon, open_gio_phat_sinh, open_id_su_co, open_loai_su_co, open_van_de
      into c from duc_ca_hien_tai where id_dong = p_id_dong for update;
    exit when not found or c.open_gio_phat_sinh is null;
    v_n := v_n + 1;
    if v_n > 10 then raise exception 'Không kết thúc được hết sự cố đang mở trên dòng %', p_id_dong; end if;
    if p_gio < c.open_gio_phat_sinh then
      raise exception 'Giờ bắt đầu đổi khuôn (%) phải sau giờ phát sinh sự cố % (%)',
        to_char(p_gio at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM'), coalesce(c.open_id_su_co, ''),
        to_char(c.open_gio_phat_sinh at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM');
    end if;

    perform set_config('duc.doi_sp_dong', coalesce(nullif(trim(p_ma_sp_moi), ''), '?'), true);
    r := duc_resolve_incident(p_id_dong, p_gio, null, p_user, p_user);
    perform set_config('duc.doi_sp_dong', '', true);
    if not coalesce((r->>'ok')::boolean, false) then
      raise exception 'Không kết thúc được sự cố %: %', coalesce(c.open_id_su_co, ''), r->>'error';
    end if;
    v_ids := v_ids || coalesce(c.open_id_su_co, '');

    -- Sự cố khuôn / chất lượng → vấn đề khuôn chặn lên lại khuôn tới khi tổ khuôn xử lý
    v_mk := trim(coalesce(c.so_khuon, ''));
    if c.open_id_su_co is not null and v_mk <> '' and left(coalesce(c.open_loai_su_co, ''), 2) in ('A2', 'B1', 'C3', 'F1') then
      v_vd := 'VDK_SC_' || c.open_id_su_co || '_' || duc_normalize_name(v_mk);
      if not exists (select 1 from duc_van_de_khuon where id_van_de = v_vd) then
        insert into duc_van_de_khuon (id_van_de, ma_khuon, ngay_phat_hien, ca_phat_hien, ma_may, ma_sp, mo_ta, nguoi_phat_hien,
                                      trang_thai, lan_tai_phat, ghi_chu, id_su_co, last_updated_at)
        values (v_vd, v_mk, c.ngay, c.ca, c.ma_may, c.ma_sp,
                c.open_loai_su_co || ': ' || coalesce(nullif(trim(c.open_van_de), ''), '(không mô tả)'),
                coalesce(p_user, ''), 'Mở', 0, 'Tự tạo từ sự cố ' || c.open_id_su_co, c.open_id_su_co, now());
      end if;
      update duc_van_de_khuon set chan_len_khuon = true, trang_thai = 'Mở', last_updated_at = now(),
        ghi_chu = coalesce(ghi_chu, '') || E'\n[' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
          || '] Xuống khuôn khi sự cố CHƯA xử lý xong (đổi sang SP ' || coalesce(p_ma_sp_moi, '?')
          || ') — tổ khuôn phải xử lý dứt điểm, ghi nội dung xử lý trước khi lên lại khuôn.'
      where id_van_de = v_vd;
      begin
        v_bao := '🔧 Khuôn ' || v_mk || ' (máy ' || c.ma_may || ', ' || c.ma_sp || ') xuống khi sự cố '
          || coalesce(c.open_loai_su_co, '') || ' chưa xử lý xong — tổ khuôn xử lý dứt điểm. Chưa ghi xử lý thì khuôn không lên lại máy được.';
        perform cv_pd_gui(cv_pd_ds_role(array['to_truong_khuon', 'nhan_vien_bao_duong_khuon']), 'bd_khuon', 'xu_ly_dut_diem',
          'vdk_dut_diem:' || v_vd,
          'van-de-khuon.html?khuon=' || replace(replace(v_mk, '#', '%23'), ' ', '%20') || '&tab=chua-dong&vd=' || replace(replace(v_vd, '#', '%23'), ' ', '%20'),
          v_bao, true);
      exception when others then raise warning 'duc_doi_sp_dong_su_co thông báo: %', sqlerrm;
      end;
    end if;
  end loop;

  if v_n > 0 then
    update duc_ipqc_checkpoint set trang_thai = 'het_hieu_luc',
      ghi_chu = concat_ws(E'\n', nullif(ghi_chu, ''), '[Hết hiệu lực: đổi sang SP ' || coalesce(p_ma_sp_moi, '?') || ' khi sự cố chưa xử lý xong]')
    where id_dong = p_id_dong and trang_thai = 'cho_kiem' and loai_kiem in ('sau_su_co', 'doi_khuon');
  end if;
  return jsonb_build_object('so_su_co', v_n, 'id_su_co', to_jsonb(v_ids));
end $function$;
revoke execute on function public.duc_doi_sp_dong_su_co(text, timestamptz, text, text) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3 hàm đổi SP: bỏ chặn "đang có sự cố", gọi duc_doi_sp_dong_su_co ngay trước khi tạo dòng mới
-- -----------------------------------------------------------------------------
do $do$
declare d text;
  v_chan constant text := $q$if v_old.open_gio_phat_sinh is not null then return jsonb_build_object('ok', false, 'error', 'Dòng SP cũ đang có sự cố khác. Vui lòng xử lý xong trước khi đổi SP.'); end if;$q$;
  v_bo constant text := '-- T188: đang có sự cố mở vẫn đổi SP được (duc_doi_sp_dong_su_co)';
begin
  d := pg_get_functiondef('public.duc_change_product'::regproc);
  if position('T188' in d) = 0 then
    d := pg_temp.t188_thay(d, v_chan, v_bo, 'duc_change_product');
    d := pg_temp.t188_thay(d,
      $q$v_id_su_co := duc_make_id_su_co(v_old.ma_may, p_gio_bat_dau_doi_khuon);$q$,
      $q$perform duc_doi_sp_dong_su_co(v_old.id_dong, p_gio_bat_dau_doi_khuon, trim(p_new_ma_sp), p_user);   -- T188
  v_id_su_co := duc_make_id_su_co(v_old.ma_may, p_gio_bat_dau_doi_khuon);$q$, 'duc_change_product');
    execute d;
  end if;

  d := pg_get_functiondef('public.duc_change_product_paired'::regproc);
  if position('T188' in d) = 0 then
    d := pg_temp.t188_thay(d, v_chan, v_bo, 'duc_change_product_paired');
    d := pg_temp.t188_thay(d,
      $q$  insert into duc_ca_hien_tai ($q$,
      $q$  perform duc_doi_sp_dong_su_co(v_old.id_dong, p_gio_bat_dau_doi_khuon, trim(p_sp_a_ma_sp) || ' + ' || trim(p_sp_b_ma_sp), p_user);   -- T188
  insert into duc_ca_hien_tai ($q$, 'duc_change_product_paired');
    execute d;
  end if;

  d := pg_get_functiondef('public.duc_change_product_pair_out'::regproc);
  if position('T188' in d) = 0 then
    d := pg_temp.t188_thay(d, v_chan, v_bo, 'duc_change_product_pair_out');
    d := pg_temp.t188_thay(d,
      $q$return jsonb_build_object('ok', false, 'error', 'Dòng SP ghép cặp (' || coalesce(v_partner.ma_sp,'') || ') đang có sự cố khác. Vui lòng xử lý xong trước khi đổi SP.');$q$,
      $q$null;   -- T188: sự cố dòng ghép cặp cũng được kết thúc khi đổi SP$q$, 'duc_change_product_pair_out');
    d := pg_temp.t188_thay(d,
      $q$v_id_su_co := duc_make_id_su_co(v_old.ma_may, p_gio_bat_dau_doi_khuon);$q$,
      $q$perform duc_doi_sp_dong_su_co(v_old.id_dong, p_gio_bat_dau_doi_khuon, trim(p_new_a_ma_sp) || coalesce(' + ' || nullif(trim(p_new_b_ma_sp), ''), ''), p_user);   -- T188
  perform duc_doi_sp_dong_su_co(v_partner.id_dong, p_gio_bat_dau_doi_khuon, trim(p_new_a_ma_sp) || coalesce(' + ' || nullif(trim(p_new_b_ma_sp), ''), ''), p_user);
  v_id_su_co := duc_make_id_su_co(v_old.ma_may, p_gio_bat_dau_doi_khuon);$q$, 'duc_change_product_pair_out');
    execute d;
  end if;
end $do$;

-- -----------------------------------------------------------------------------
-- Chặn lên lại khuôn còn vấn đề "xuống khi chưa xử lý xong" mà tổ khuôn chưa ghi xử lý
-- -----------------------------------------------------------------------------
create or replace function public.duc_ca_hien_tai_chan_khuon_chua_dut_diem()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare v_mk text := trim(coalesce(new.so_khuon, '')); v_ds text;
begin
  if v_mk = '' then return new; end if;
  if tg_op = 'UPDATE' and new.so_khuon is not distinct from old.so_khuon then return new; end if;
  if new.last_updated_by = 'system@carry-over' then return new; end if;   -- chuyển ca: khuôn đang chạy
  select string_agg(coalesce(id_su_co, id_van_de), ', ') into v_ds
    from duc_van_de_khuon where trim(ma_khuon) = v_mk and chan_len_khuon and trang_thai = 'Mở';
  if v_ds is null then return new; end if;
  raise exception 'Khuôn % đã xuống máy khi sự cố % chưa xử lý xong — tổ khuôn phải xử lý dứt điểm và ghi nội dung xử lý ở trang "Vấn đề khuôn" trước khi lên lại khuôn.',
    v_mk, v_ds;
end $function$;
revoke execute on function public.duc_ca_hien_tai_chan_khuon_chua_dut_diem() from public, anon, authenticated;

drop trigger if exists trg_duc_ca_hien_tai_chan_khuon_chua_dut_diem on duc_ca_hien_tai;
create trigger trg_duc_ca_hien_tai_chan_khuon_chua_dut_diem
  before insert or update of so_khuon on duc_ca_hien_tai
  for each row execute function duc_ca_hien_tai_chan_khuon_chua_dut_diem();

-- Tổ khuôn ghi xử lý (Mở → Chờ xác nhận / Đã đóng) → tắt chuông "xử lý dứt điểm"
create or replace function public.duc_van_de_khuon_dut_diem_xong_trg()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.chan_len_khuon and new.trang_thai is distinct from 'Mở' then
    perform cv_pd_xong('vdk_dut_diem:' || new.id_van_de);
  end if;
  return null;
exception when others then
  raise warning 'duc_van_de_khuon_dut_diem_xong_trg: %', sqlerrm;
  return null;
end $function$;
revoke execute on function public.duc_van_de_khuon_dut_diem_xong_trg() from public, anon, authenticated;

drop trigger if exists trg_duc_van_de_khuon_dut_diem_xong on duc_van_de_khuon;
create trigger trg_duc_van_de_khuon_dut_diem_xong
  after update of trang_thai on duc_van_de_khuon
  for each row execute function duc_van_de_khuon_dut_diem_xong_trg();
