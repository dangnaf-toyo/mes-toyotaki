-- T279 (R20): Chuông nhắc việc gọn + đúng.
-- 1) Chuông "cần xử lý" đã xử lý xong → tự coi là đã đọc (số trên chuông chỉ đếm việc thật).
-- 2) Việc đổi trạng thái: báo xong (chờ duyệt) → tắt chuông Quá hạn/Giao việc của việc đó;
--    hoàn thành / huỷ → tắt mọi chuông cần xử lý của việc đó.
-- 3) cv_quet_qua_han (cron mỗi giờ :05):
--    - Không báo Quá hạn cho việc đang Chờ duyệt (người làm đã báo xong).
--    - Quá hạn: nhắc lại mỗi 24 giờ (chuông cũ tự xong).
--    - Chờ duyệt quá 24 giờ: nhắc người giao mỗi 24 giờ.
--    - KHSX tuần: tuần đã hết mà còn chờ duyệt → Lưu trữ (luu_tru), tắt chuông;
--      tuần chưa hết, chờ duyệt quá 24 giờ → nhắc lại người duyệt bước đó.
-- 4) khsx_ghi_log_sua: sửa dòng của tuần đã Lưu trữ không đưa về chờ duyệt.

-- 1) Chuông xử lý xong = đã đọc
create or replace function public.cv_tb_xu_ly_la_doc()
returns trigger language plpgsql set search_path to 'public' as $$
begin
  if new.da_xu_ly and not coalesce(old.da_xu_ly, false) and not new.da_doc then
    new.da_doc := true;
    new.da_doc_luc := coalesce(new.da_doc_luc, now());
  end if;
  return new;
end;
$$;
drop trigger if exists trg_cv_tb_xu_ly_la_doc on public.cv_thong_bao;
create trigger trg_cv_tb_xu_ly_la_doc before update of da_xu_ly on public.cv_thong_bao
  for each row execute function public.cv_tb_xu_ly_la_doc();

update cv_thong_bao set da_doc = true, da_doc_luc = coalesce(da_doc_luc, now())
where can_xu_ly and da_xu_ly and not da_doc;

-- 2) Việc đổi trạng thái → tắt chuông cũ
create or replace function public.cv_trg_viec_tat_chuong()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  begin
    if new.trang_thai is not distinct from old.trang_thai then return new; end if;
    if new.trang_thai in ('hoan_thanh', 'huy') then
      perform cv_xong_tb(new.id, null, null);
    elsif new.trang_thai = 'cho_duyet' then
      perform cv_xong_tb(new.id, array['qua_han', 'giao_viec', 'nhac_viec', 'tra_lai'], null);
    end if;
  exception when others then
    raise warning 'T279 tắt chuông việc lỗi (bỏ qua): %', sqlerrm;
  end;
  return new;
end;
$$;
drop trigger if exists trg_cv_viec_tat_chuong on public.cv_cong_viec;
create trigger trg_cv_viec_tat_chuong after update of trang_thai on public.cv_cong_viec
  for each row execute function public.cv_trg_viec_tat_chuong();

-- Dọn chuông treo hiện có theo cùng quy tắc
update cv_thong_bao t set da_xu_ly = true
from cv_cong_viec c
where c.id = t.cong_viec_id and t.can_xu_ly and not t.da_xu_ly
  and (c.trang_thai in ('hoan_thanh', 'huy')
       or (c.trang_thai = 'cho_duyet' and t.loai in ('qua_han', 'giao_viec', 'nhac_viec', 'tra_lai')));

-- 3) KHSX: thêm trạng thái Lưu trữ
alter table public.khsx_duyet drop constraint if exists khsx_duyet_trang_thai_check;
alter table public.khsx_duyet add constraint khsx_duyet_trang_thai_check
  check (trang_thai = any (array['nhap', 'cho_truong_phong', 'cho_quan_ly_bo_phan', 'cho_giam_doc', 'da_duyet', 'luu_tru']));

create or replace function public.cv_quet_qua_han()
returns integer language plpgsql security definer set search_path to 'public' as $$
declare r record; n int := 0; v_khoa text;
begin
  -- Quá hạn (không gồm chờ duyệt): báo lần đầu, rồi nhắc lại mỗi 24 giờ
  for r in
    select id, tieu_de, han, nguoi_lam, nguoi_giao from cv_cong_viec
    where trang_thai not in ('hoan_thanh', 'huy', 'cho_duyet') and han < now()
      and (qua_han_da_bao_luc is null or qua_han_da_bao_luc < han
           or qua_han_da_bao_luc < now() - interval '23 hours 50 minutes')
    for update skip locked
  loop
    perform cv_xong_tb(r.id, array['qua_han'], null);
    perform cv_gui_tb(array[r.nguoi_lam, r.nguoi_giao], 'qua_han', r.id, null,
      'Quá hạn' || case when now() - r.han >= interval '1 day'
                        then ' ' || floor(extract(epoch from now() - r.han) / 86400)::int || ' ngày' else '' end
      || ': ' || r.tieu_de || ' (hạn ' || cv_fmt(r.han) || ')', true);
    update cv_cong_viec set qua_han_da_bao_luc = now() where id = r.id;
    n := n + 1;
  end loop;

  -- Chờ duyệt quá 24 giờ: nhắc người giao mỗi 24 giờ
  for r in
    select c.id, c.tieu_de, c.nguoi_giao, c.bao_xong_luc from cv_cong_viec c
    where c.trang_thai = 'cho_duyet' and c.bao_xong_luc < now() - interval '23 hours 50 minutes'
      and not exists (select 1 from cv_thong_bao t where t.cong_viec_id = c.id and t.loai = 'cho_duyet'
                        and t.created_at >= now() - interval '23 hours 50 minutes')
  loop
    perform cv_xong_tb(r.id, array['cho_duyet'], null);
    perform cv_gui_tb(array[r.nguoi_giao], 'cho_duyet', r.id, null,
      'Chờ bạn duyệt ' || greatest(1, floor(extract(epoch from now() - r.bao_xong_luc) / 86400)::int)
      || ' ngày: ' || r.tieu_de, true);
    n := n + 1;
  end loop;

  -- KHSX tuần đã hết mà chưa duyệt xong → Lưu trữ (trigger tắt chuông cũ)
  update khsx_duyet set trang_thai = 'luu_tru', updated_by = 'Hệ thống (tuần đã hết)', updated_at = now()
  where trang_thai in ('cho_truong_phong', 'cho_quan_ly_bo_phan', 'cho_giam_doc')
    and tuan_bat_dau + 7 <= (now() at time zone 'Asia/Ho_Chi_Minh')::date;

  -- KHSX tuần chưa hết, chờ duyệt quá 24 giờ → nhắc lại
  for r in
    select d.tuan_bat_dau, d.cong_doan, d.trang_thai from khsx_duyet d
    where d.trang_thai in ('cho_truong_phong', 'cho_quan_ly_bo_phan', 'cho_giam_doc')
      and d.updated_at < now() - interval '23 hours 50 minutes'
  loop
    v_khoa := 'khsx:' || r.tuan_bat_dau || ':' || r.cong_doan;
    if not exists (select 1 from cv_thong_bao t where t.khoa = v_khoa and t.loai = 'can_duyet'
                     and t.created_at >= now() - interval '23 hours 50 minutes') then
      perform cv_pd_xong(v_khoa);
      perform cv_pd_khsx_bao(r.tuan_bat_dau, r.cong_doan, r.trang_thai);
      n := n + 1;
    end if;
  end loop;
  return n;
end;
$$;
revoke execute on function public.cv_quet_qua_han() from public, anon, authenticated;

-- Trigger KHSX: Lưu trữ thì chỉ tắt chuông (đã có cv_pd_xong ở đầu trigger) — không cần sửa.

-- 4) Sửa dòng tuần đã Lưu trữ: không đưa về chờ duyệt
create or replace function public.khsx_ghi_log_sua(p_tuan date, p_cong_doan text, p_loai text, p_vi_tri text, p_gia_tri_cu text, p_gia_tri_moi text, p_ly_do text, p_user text)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_trang_thai text;
  v_reset boolean := false;
begin
  if auth.uid() is not null and not public.has_role(VARIADIC ARRAY['admin', 'qlsx_nhan_vien', 'qlsx_truong_phong', 'ke_hoach', 'quan_ly_bo_phan']) then
    raise exception '⛔ Tài khoản không có quyền thực hiện thao tác này — cần vai trò: %', 'QLSX / Kế hoạch / QLBP' using errcode = '42501';
  end if;   -- T212
  p_user := public.duc_ten_nguoi_hien_tai(p_user);   -- T212: tên theo tài khoản
  if p_loai not in ('them_moi','sua','xoa') then
    return jsonb_build_object('ok', false, 'error', 'Loại thay đổi không hợp lệ: ' || p_loai);
  end if;

  select trang_thai into v_trang_thai from khsx_duyet where tuan_bat_dau = p_tuan and cong_doan = p_cong_doan;

  if v_trang_thai is not null and v_trang_thai <> 'nhap' then
    if p_ly_do is null or trim(p_ly_do) = '' then
      return jsonb_build_object('ok', false, 'error', 'Kế hoạch đã gửi duyệt/đã duyệt — bắt buộc nhập lý do khi sửa');
    end if;
    if v_trang_thai <> 'luu_tru' then   -- T279: tuần đã lưu trữ giữ nguyên
      update khsx_duyet set trang_thai = 'cho_truong_phong', updated_by = p_user, updated_at = now()
      where tuan_bat_dau = p_tuan and cong_doan = p_cong_doan;
      v_reset := true;
    end if;
  end if;

  insert into khsx_thay_doi_log (tuan_bat_dau, cong_doan, loai_su_kien, vi_tri, gia_tri_cu, gia_tri_moi, ly_do, nguoi_thuc_hien)
  values (p_tuan, p_cong_doan, p_loai, coalesce(p_vi_tri,''), coalesce(p_gia_tri_cu,''), coalesce(p_gia_tri_moi,''), coalesce(p_ly_do,''), p_user);

  return jsonb_build_object('ok', true, 'reset_ve_dau', v_reset);
end;
$function$;

-- Chạy quét ngay một lần để lưu trữ tuần cũ + dọn chuông
select public.cv_quet_qua_han();
