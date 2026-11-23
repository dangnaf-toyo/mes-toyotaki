-- ============================================================================
-- T328 — Nạp KH mã mới luôn tạo điểm kiểm IPQC "bắt đầu SX" (doi_khuon).
-- Lỗi: id_checkpoint = IPQC_<giây>_<máy>_<loại> → nạp 1 khuôn nhiều mã
-- (duc_assign_group_plan), cron hoãn ca mới (duc_ipqc_doi_khuon_ca_moi)...
-- tạo nhiều điểm kiểm cùng máy trong cùng 1 giây → trùng khoá chính, lỗi bị
-- nuốt (exception when others then null) → mã thứ 2 trở đi KHÔNG có điểm kiểm.
-- Sửa: trùng id thì thêm đuôi _2, _3... Phần còn lại giữ nguyên.
-- An toàn chạy lại nhiều lần.
-- ============================================================================

create or replace function public.duc_request_ipqc_check(p_id_dong text, p_loai_kiem text, p_id_su_co_goc text default null::text, p_moc_cho_override timestamp with time zone default null::timestamp with time zone)
 returns jsonb
 language plpgsql
 security definer
as $function$
declare
  v_cht record;
  v_dup int;
  v_id text;
  v_goc text;
  v_n int := 1;
  v_han_kiem timestamptz;
  v_last_check timestamptz;
begin
  select ma_may, ma_sp, ngay, ca, phuong_an_ca into v_cht from duc_ca_hien_tai where id_dong = p_id_dong;
  if not found then return jsonb_build_object('ok', false, 'reason', 'khong_tim_thay_dong'); end if;
  if v_cht.ma_sp is null or v_cht.ma_sp = '' then return jsonb_build_object('ok', false, 'reason', 'dong_khong_co_sp'); end if;

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
