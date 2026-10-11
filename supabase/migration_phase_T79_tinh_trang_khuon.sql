-- ============================================================================
-- T79 — Tình trạng sử dụng của khuôn (quan-ly-khuon.html).
--
-- Tách với trang_thai_khuon (OK / Sắp BD / Cần BD / Cần làm mới — tính theo shot):
--   dang_sx            Đang sản xuất (mặc định — khuôn tự sinh sau ca sản xuất)
--   moi_chua_sx        Khuôn mới, chưa đưa vào sản xuất
--   dung_het_tuoi_tho  Hết tuổi thọ — dừng sản xuất
--   cho_tra_khach      Hết tuổi thọ — chờ trả về khách hàng
--   cho_bao_phe        Hết tuổi thọ — chờ báo phế
-- Đổi qua RPC duc_khuon_doi_tinh_trang (bắt buộc lý do, ghi lịch sử
-- duc_khuon_tinh_trang_log). Quyền: nhân viên bảo dưỡng khuôn, Quản lý bộ
-- phận Đúc, admin.
--
-- Chạy trên CẢ 2 project (production + staging). Idempotent. Chạy sau T75.
-- ============================================================================

alter table duc_shot_khuon add column if not exists tinh_trang text not null default 'dang_sx';
alter table duc_shot_khuon add column if not exists tinh_trang_ly_do text;
alter table duc_shot_khuon add column if not exists tinh_trang_luc timestamptz;
alter table duc_shot_khuon add column if not exists tinh_trang_boi text;
alter table duc_shot_khuon drop constraint if exists duc_shot_khuon_tinh_trang_check;
alter table duc_shot_khuon add constraint duc_shot_khuon_tinh_trang_check
  check (tinh_trang in ('dang_sx', 'moi_chua_sx', 'dung_het_tuoi_tho', 'cho_tra_khach', 'cho_bao_phe'));

create table if not exists duc_khuon_tinh_trang_log (
  id          bigserial primary key,
  ma_khuon    text not null,
  tu          text,
  sang        text not null,
  ly_do       text not null default '',
  nguoi       text not null default '',
  thoi_diem   timestamptz not null default now()
);
create index if not exists idx_duc_khuon_tinh_trang_log_ma on duc_khuon_tinh_trang_log (ma_khuon, thoi_diem desc);
alter table duc_khuon_tinh_trang_log enable row level security;
drop policy if exists "tinh_trang_log public read" on duc_khuon_tinh_trang_log;
create policy "tinh_trang_log public read" on duc_khuon_tinh_trang_log for select using (true);
revoke insert, update, delete on duc_khuon_tinh_trang_log from anon, authenticated;
grant select on duc_khuon_tinh_trang_log to anon, authenticated;

create or replace function duc_khuon_doi_tinh_trang(p_ma_khuon text, p_tinh_trang text, p_ly_do text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me record; v_cu text; v_ly_do text := trim(coalesce(p_ly_do, '')); v_now timestamptz := now();
begin
  select * into v_me from duc_khuon_bd_nguoi_hien_tai();
  if not (coalesce(v_me.o_role, '') in ('admin', 'nhan_vien_bao_duong_khuon')
          or (v_me.o_role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(v_me.o_bo_phan, '{}')))) then
    return jsonb_build_object('ok', false, 'error', 'Chỉ nhân viên bảo dưỡng khuôn / Quản lý bộ phận Đúc / admin được đổi tình trạng khuôn');
  end if;
  if p_tinh_trang not in ('dang_sx', 'moi_chua_sx', 'dung_het_tuoi_tho', 'cho_tra_khach', 'cho_bao_phe') then
    return jsonb_build_object('ok', false, 'error', 'Tình trạng không hợp lệ');
  end if;
  if v_ly_do = '' then return jsonb_build_object('ok', false, 'error', 'Nhập lý do đổi tình trạng'); end if;

  select tinh_trang into v_cu from duc_shot_khuon where ma_khuon = trim(p_ma_khuon) for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy khuôn ' || coalesce(p_ma_khuon, '')); end if;
  if v_cu = p_tinh_trang then return jsonb_build_object('ok', false, 'error', 'Khuôn đã ở tình trạng này'); end if;

  update duc_shot_khuon set tinh_trang = p_tinh_trang, tinh_trang_ly_do = v_ly_do,
    tinh_trang_luc = v_now, tinh_trang_boi = v_me.o_ten
  where ma_khuon = trim(p_ma_khuon);
  insert into duc_khuon_tinh_trang_log (ma_khuon, tu, sang, ly_do, nguoi, thoi_diem)
  values (trim(p_ma_khuon), v_cu, p_tinh_trang, v_ly_do, v_me.o_ten, v_now);

  return jsonb_build_object('ok', true, 'ma_khuon', trim(p_ma_khuon), 'tinh_trang', p_tinh_trang);
end;
$$;
revoke execute on function duc_khuon_doi_tinh_trang(text, text, text) from public, anon;
grant execute on function duc_khuon_doi_tinh_trang(text, text, text) to authenticated;
