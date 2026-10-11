-- ============================================================================
-- T82 — Khuôn "Mới — chưa vào SX" (moi_chua_sx) cũng gắn được lên máy ở Bảng
-- điều khiển Đúc (cần đúc mẫu). Chỉ còn chặn: dung_het_tuoi_tho, cho_tra_khach,
-- cho_bao_phe. Thay hàm trigger của T80, các ngoại lệ giữ nguyên.
--
-- Chạy trên CẢ 2 project (production + staging). Idempotent. Chạy sau T80.
-- ============================================================================

create or replace function duc_ca_hien_tai_chan_khuon_ngung_sx()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tt text; v_mk text := trim(coalesce(new.so_khuon, ''));
begin
  if v_mk = '' then return new; end if;
  if tg_op = 'UPDATE' and new.so_khuon is not distinct from old.so_khuon then return new; end if;
  select tinh_trang into v_tt from duc_shot_khuon where ma_khuon = v_mk;
  if v_tt is null or v_tt in ('dang_sx', 'moi_chua_sx') then return new; end if;
  -- khuôn đã nằm trên chính máy này (chuyển ca / đổi SP giữ khuôn) -> cho qua
  if exists (select 1 from duc_ca_hien_tai where ma_may = new.ma_may and trim(so_khuon) = v_mk
             and id_dong is distinct from new.id_dong) then
    return new;
  end if;
  -- đổi tên khuôn: mã cũ đã bị xoá khỏi duc_shot_khuon trước khi update dòng ca
  if tg_op = 'UPDATE' and new.ma_may is not distinct from old.ma_may
     and not exists (select 1 from duc_shot_khuon where ma_khuon = trim(coalesce(old.so_khuon, ''))) then
    return new;
  end if;
  raise exception 'Khuôn % đang ở tình trạng "%" — chỉ gắn được khuôn Đang sản xuất hoặc khuôn mới đúc mẫu (đổi ở Quản lý khuôn)', v_mk,
    case v_tt when 'dung_het_tuoi_tho' then 'Hết tuổi thọ — dừng SX'
              when 'cho_tra_khach' then 'Chờ trả khách hàng' when 'cho_bao_phe' then 'Chờ báo phế' else v_tt end;
end;
$$;
revoke execute on function duc_ca_hien_tai_chan_khuon_ngung_sx() from public, anon, authenticated;
