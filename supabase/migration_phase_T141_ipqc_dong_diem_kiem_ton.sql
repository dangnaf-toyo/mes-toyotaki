-- ============================================================================
-- T141 — QC Manager / admin đóng điểm kiểm IPQC TỒN ĐỌNG (chờ > 24 giờ).
--
-- Bối cảnh: hàng đợi ipqc.html / qc-manager.html hiện các điểm kiểm
-- "cho_kiem" chờ hàng chục ngày ("Đang chờ 17976p" ≈ 12 ngày) — thường là
-- điểm kiểm của dòng ca không bao giờ được Kết ca / sự cố không ai kiểm
-- (xem D18). D18 chỉ dọn tự động các (ngay, ca) ĐÃ kết ca; phần còn lại cần
-- người có thẩm quyền đóng tay, có lý do.
--
-- Thiết kế:
--  * Trạng thái đích: 'het_hieu_luc' — trạng thái đã có sẵn (schema_duc.sql:
--    'cho_kiem' | 'da_kiem' | 'het_hieu_luc'; cột text, KHÔNG có CHECK
--    constraint), mọi màn hình/hàm đã bỏ qua trạng thái này (D18, T30, D71,
--    T96). Không xoá dòng nào.
--  * Chỉ đóng điểm kiểm đang 'cho_kiem' và đã chờ > 24 giờ tính từ
--    coalesce(han_kiem, thoi_diem_tao). Điểm kiểm không thoả → trả về trong
--    danh sách bo_qua kèm lý do, không lỗi cả lô.
--  * Lý do bắt buộc ≥ 3 ký tự. Ghi:
--      - bảng nhật ký duc_ipqc_dong_ton_log (1 dòng / điểm kiểm);
--      - nối vào duc_ipqc_checkpoint.ghi_chu: "[Đóng tồn đọng <giờ> bởi
--        <người>: <lý do>]".
--  * Phiên kiểm (duc_ipqc_inspection_session, T118) còn mở của điểm kiểm bị
--    đóng: đặt completed_at = now() để trang ipqc.html không tự khôi phục
--    lại phiên của điểm kiểm đã đóng (trạng thái điểm kiểm ≠ 'da_kiem' nên
--    trigger duc_ipqc_session_complete_trigger không tính thời gian kiểm).
--  * Trigger trên duc_ipqc_checkpoint (T118 trg_ipqc_session_complete, T127
--    trg_duc_ipqc_vd_kiem_tra/ap_dung, T133 trg_ipqc_do_sau_nop) chỉ xử lý khi
--    trang_thai mới = 'da_kiem' hoặc đổi ket_qua → không bị ảnh hưởng.
--  * Quyền: has_role('admin','qc_manager').
--
-- Hoàn tác 1 điểm kiểm (nếu đóng nhầm):
--   update duc_ipqc_checkpoint set trang_thai = 'cho_kiem'
--   where id_checkpoint = '<id>' and trang_thai = 'het_hieu_luc';
--   (dữ liệu trước khi đóng nằm ở duc_ipqc_dong_ton_log.du_lieu_truoc)
--
-- Chạy trong Supabase SQL Editor (staging trước, rồi prod). Chạy lại an toàn.
-- ============================================================================

create table if not exists public.duc_ipqc_dong_ton_log (
  id               bigserial primary key,
  id_checkpoint    text        not null,
  trang_thai_truoc text,
  trang_thai_sau   text        not null default 'het_hieu_luc',
  phut_cho         integer,
  ly_do            text        not null check (length(btrim(ly_do)) >= 3),
  nguoi_dong       text,
  nguoi_dong_id    uuid        default auth.uid(),
  thoi_diem        timestamptz not null default now(),
  du_lieu_truoc    jsonb
);
create index if not exists idx_duc_ipqc_dong_ton_log_cp on public.duc_ipqc_dong_ton_log (id_checkpoint);

alter table public.duc_ipqc_dong_ton_log enable row level security;
drop policy if exists "doc dong ton ipqc" on public.duc_ipqc_dong_ton_log;
create policy "doc dong ton ipqc" on public.duc_ipqc_dong_ton_log
  for select to authenticated using (true);
revoke insert, update, delete on public.duc_ipqc_dong_ton_log from anon, authenticated;

create or replace function public.duc_ipqc_dong_diem_kiem_ton(
  p_ids   text[],
  p_ly_do text,
  p_nguoi text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ly_do  text := btrim(coalesce(p_ly_do, ''));
  v_nguoi  text := nullif(btrim(coalesce(p_nguoi, '')), '');
  v_id     text;
  cp       duc_ipqc_checkpoint%rowtype;
  v_moc    timestamptz;
  v_phut   integer;
  v_dong   text[] := '{}';
  v_bo_qua jsonb  := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Cần đăng nhập MES'; end if;
  if not public.has_role('admin', 'qc_manager') then
    raise exception 'Chỉ QC Manager hoặc admin được đóng điểm kiểm tồn đọng';
  end if;
  if length(v_ly_do) < 3 then raise exception 'Lý do đóng phải có ít nhất 3 ký tự'; end if;
  if p_ids is null or cardinality(p_ids) = 0 then raise exception 'Chưa chọn điểm kiểm nào'; end if;
  if cardinality(p_ids) > 500 then raise exception 'Mỗi lần đóng tối đa 500 điểm kiểm'; end if;

  -- Tên người đóng lấy theo tài khoản đăng nhập (không tin p_nguoi trình duyệt gửi; giữ tham số để tương thích).
  v_nguoi := coalesce(
    (select nullif(btrim(coalesce(r.username, '') || '_' || coalesce(r.full_name, '')), '_') from user_roles r where r.user_id = auth.uid() limit 1),
    (select email from auth.users where id = auth.uid()), auth.uid()::text);

  foreach v_id in array (select array_agg(distinct x) from unnest(p_ids) x where x is not null) loop
    select * into cp from duc_ipqc_checkpoint where id_checkpoint = v_id for update;
    if not found then
      v_bo_qua := v_bo_qua || jsonb_build_object('id', v_id, 'ly_do', 'Không tìm thấy điểm kiểm');
      continue;
    end if;
    if cp.trang_thai is distinct from 'cho_kiem' then
      v_bo_qua := v_bo_qua || jsonb_build_object('id', v_id, 'ly_do', 'Không còn ở trạng thái chờ kiểm (' || coalesce(cp.trang_thai, 'null') || ')');
      continue;
    end if;
    v_moc := coalesce(cp.han_kiem, cp.thoi_diem_tao);
    v_phut := case when v_moc is null then null else floor(extract(epoch from now() - v_moc) / 60)::int end;
    if v_moc is not null and v_moc > now() - interval '24 hours' then
      v_bo_qua := v_bo_qua || jsonb_build_object('id', v_id, 'ly_do', 'Mới chờ ' || v_phut || ' phút — chưa quá 24 giờ');
      continue;
    end if;

    insert into duc_ipqc_dong_ton_log (id_checkpoint, trang_thai_truoc, phut_cho, ly_do, nguoi_dong, du_lieu_truoc)
    values (v_id, cp.trang_thai, v_phut, v_ly_do, v_nguoi, to_jsonb(cp));

    update duc_ipqc_checkpoint
       set trang_thai = 'het_hieu_luc',
           ghi_chu = concat_ws(E'\n', nullif(ghi_chu, ''),
             '[Đóng tồn đọng ' || to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'DD/MM/YYYY HH24:MI')
             || ' bởi ' || v_nguoi || ': ' || v_ly_do || ']')
     where id_checkpoint = v_id;

    update duc_ipqc_inspection_session
       set completed_at = greatest(started_at, clock_timestamp())
     where checkpoint_id = v_id and completed_at is null;

    v_dong := v_dong || v_id;
  end loop;

  return jsonb_build_object('ok', true, 'so_dong', cardinality(v_dong), 'da_dong', to_jsonb(v_dong), 'bo_qua', v_bo_qua);
end $$;

revoke execute on function public.duc_ipqc_dong_diem_kiem_ton(text[], text, text) from public, anon;
grant execute on function public.duc_ipqc_dong_diem_kiem_ton(text[], text, text) to authenticated;

notify pgrst, 'reload schema';
