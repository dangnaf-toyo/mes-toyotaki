-- T204: Lần kiểm IPQC còn chờ không bị "mồ côi" khi kết ca / xoá dòng ca.
--
-- Sự cố 03/11/2026 DC 6: điểm kiểm định kỳ tạo 18:42:07 gắn dòng Ca ngày, 18:42:44 kết ca
-- → dòng Ca ngày bị xoá khỏi duc_ca_hien_tai. IPQC bấm Cảnh báo → màn hình chặn "Phiên sản xuất
-- đã thay đổi"; bấm NG → duc_submit_ipqc_check không thấy dòng gốc → KHÔNG mở sự cố F1, không
-- dừng máy ("Dòng Ca_hien_tai gốc không còn — bỏ qua liên kết ngược").
--
-- Sửa: điểm kiểm 'cho_kiem' đi theo dòng ca mới nhất của CÙNG máy + CÙNG mã SP:
--   1) BEFORE DELETE duc_ca_hien_tai: chuyển sang dòng mới hơn (row_seq lớn hơn, khác ca) nếu đã có.
--   2) AFTER INSERT duc_ca_hien_tai: dòng mới nhận các điểm kiểm mồ côi (dòng gốc không còn) tạo
--      trong 24 giờ gần nhất — trường hợp kết ca trước khi trưởng ca nhập KH ca sau.
--   3) duc_submit_ipqc_session: trước khi lưu kết quả, nếu dòng gốc không còn thì gắn lại vào dòng
--      đang chạy của cùng máy + mã (lưới an toàn).
-- Khác máy hoặc khác mã SP → KHÔNG chuyển (giữ nguyên chặn).
-- Phiên kiểm đang mở (duc_ipqc_inspection_session.job_id) chuyển theo để trigger hoàn tất
-- (so job_id với id_dong) không báo "Máy/model/phiên sản xuất đã thay đổi".

-- ── Hàm lõi: chuyển các điểm kiểm sang 1 dòng ca ─────────────────────────────
create or replace function public.duc_ipqc_chuyen_checkpoint(p_ids text[], p_id_dong_moi text)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_dong duc_ca_hien_tai%rowtype;
  v_so int := 0;
  v_giu text;
begin
  if p_ids is null or cardinality(p_ids) = 0 or p_id_dong_moi is null then return 0; end if;
  select * into v_dong from duc_ca_hien_tai where id_dong = p_id_dong_moi;
  if not found then return 0; end if;

  with moved as (
    update duc_ipqc_checkpoint c
       set id_dong = v_dong.id_dong, ngay = v_dong.ngay, ca = v_dong.ca, phuong_an_ca = v_dong.phuong_an_ca
     where c.id_checkpoint = any(p_ids) and c.trang_thai = 'cho_kiem'
       and c.ma_may = v_dong.ma_may and c.ma_sp = v_dong.ma_sp
     returning c.id_checkpoint
  ), sess as (
    update duc_ipqc_inspection_session s set job_id = v_dong.id_dong
      from moved m where s.checkpoint_id = m.id_checkpoint and s.completed_at is null
    returning 1
  )
  select count(*) into v_so from moved;

  -- Một dòng chỉ giữ 1 điểm kiểm ĐỊNH KỲ chờ: ưu tiên cái đang có phiên kiểm mở, rồi cái tạo sớm nhất.
  -- Điểm kiểm đang có phiên mở không bao giờ bị cho hết hiệu lực.
  select c.id_checkpoint into v_giu
    from duc_ipqc_checkpoint c
   where c.id_dong = v_dong.id_dong and c.loai_kiem = 'dinh_ky' and c.trang_thai = 'cho_kiem'
   order by exists (select 1 from duc_ipqc_inspection_session s where s.checkpoint_id = c.id_checkpoint and s.completed_at is null) desc,
            c.thoi_diem_tao asc
   limit 1;
  if v_giu is not null then
    update duc_ipqc_checkpoint c set trang_thai = 'het_hieu_luc',
           ghi_chu = concat_ws(E'\n', nullif(c.ghi_chu, ''), '[T204: trùng điểm kiểm định kỳ khi chuyển sang ' || v_dong.id_dong || ']')
     where c.id_dong = v_dong.id_dong and c.loai_kiem = 'dinh_ky' and c.trang_thai = 'cho_kiem'
       and c.id_checkpoint <> v_giu
       and not exists (select 1 from duc_ipqc_inspection_session s where s.checkpoint_id = c.id_checkpoint);
  end if;
  return v_so;
end $$;
revoke execute on function public.duc_ipqc_chuyen_checkpoint(text[], text) from public, anon, authenticated;

-- ── 1) Xoá dòng ca (kết ca / xoá KH) → chuyển sang dòng mới hơn cùng máy + mã ─
create or replace function public.duc_ipqc_checkpoint_truoc_xoa_dong()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_moi text; v_ids text[];
begin
  if old.id_dong is null or coalesce(old.ma_sp, '') = '' then return old; end if;
  select array_agg(id_checkpoint) into v_ids from duc_ipqc_checkpoint
   where id_dong = old.id_dong and trang_thai = 'cho_kiem';
  if v_ids is null then return old; end if;
  select c.id_dong into v_moi from duc_ca_hien_tai c
   where c.ma_may = old.ma_may and c.ma_sp = old.ma_sp and c.id_dong <> old.id_dong
     and c.row_seq > old.row_seq
     and (c.ngay, c.ca) is distinct from (old.ngay, old.ca)
   order by c.row_seq desc limit 1;
  if v_moi is not null then perform duc_ipqc_chuyen_checkpoint(v_ids, v_moi); end if;
  return old;
end $$;
revoke execute on function public.duc_ipqc_checkpoint_truoc_xoa_dong() from public, anon, authenticated;

drop trigger if exists trg_duc_ipqc_checkpoint_truoc_xoa_dong on public.duc_ca_hien_tai;
create trigger trg_duc_ipqc_checkpoint_truoc_xoa_dong
  before delete on public.duc_ca_hien_tai
  for each row execute function public.duc_ipqc_checkpoint_truoc_xoa_dong();

-- ── 2) Dòng ca mới → nhận điểm kiểm mồ côi (≤ 24 giờ) cùng máy + mã ─────────
create or replace function public.duc_ipqc_checkpoint_nhan_mo_coi()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_ids text[];
begin
  if new.id_dong is null or new.ma_may is null or coalesce(new.ma_sp, '') = '' then return new; end if;
  select array_agg(cp.id_checkpoint) into v_ids from duc_ipqc_checkpoint cp
   where cp.ma_may = new.ma_may and cp.ma_sp = new.ma_sp and cp.trang_thai = 'cho_kiem'
     and cp.id_dong is not null and cp.id_dong <> new.id_dong
     and cp.thoi_diem_tao > now() - interval '24 hours'
     and not exists (select 1 from duc_ca_hien_tai c where c.id_dong = cp.id_dong);
  if v_ids is not null then perform duc_ipqc_chuyen_checkpoint(v_ids, new.id_dong); end if;
  return new;
end $$;
revoke execute on function public.duc_ipqc_checkpoint_nhan_mo_coi() from public, anon, authenticated;

drop trigger if exists trg_duc_ipqc_checkpoint_nhan_mo_coi on public.duc_ca_hien_tai;
create trigger trg_duc_ipqc_checkpoint_nhan_mo_coi
  after insert on public.duc_ca_hien_tai
  for each row execute function public.duc_ipqc_checkpoint_nhan_mo_coi();

-- ── 3) Lưới an toàn lúc nộp kết quả ──────────────────────────────────────────
create or replace function public.duc_submit_ipqc_session(p_id_checkpoint text, p_checklist jsonb, p_ket_qua text, p_anh_urls jsonb, p_ghi_chu text, p_thoi_gian_kiem_giay numeric, p_nguoi_kiem text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare s public.duc_ipqc_inspection_session%rowtype; result jsonb; cp public.duc_ipqc_checkpoint%rowtype; v_moi text;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập MES';end if;
 select * into cp from duc_ipqc_checkpoint where id_checkpoint=p_id_checkpoint for update;
 -- T204: dòng ca gốc đã kết/xoá → gắn sang dòng đang chạy của CÙNG máy + mã SP (nếu có).
 if found and cp.trang_thai='cho_kiem' and cp.id_dong is not null
    and not exists(select 1 from duc_ca_hien_tai where id_dong=cp.id_dong) then
   select c.id_dong into v_moi from duc_ca_hien_tai c
    where c.ma_may=cp.ma_may and c.ma_sp=cp.ma_sp order by c.row_seq desc limit 1;
   if v_moi is not null then perform duc_ipqc_chuyen_checkpoint(array[p_id_checkpoint], v_moi); end if;
 end if;
 select * into s from duc_ipqc_inspection_session where checkpoint_id=p_id_checkpoint and owner_id=auth.uid() for update;
 if not found then raise exception 'Hãy bấm Bắt đầu kiểm tra';end if;
 if s.completed_at is not null then
   if exists(select 1 from duc_ipqc_checkpoint where id_checkpoint=p_id_checkpoint and ket_qua=p_ket_qua and trang_thai='da_kiem') then return jsonb_build_object('ok',true,'existing',true);end if;
   raise exception 'Phiên đã lưu kết quả khác';
 end if;
 if jsonb_typeof(p_checklist) is distinct from 'array' or jsonb_array_length(p_checklist)=0 then raise exception 'Xác nhận đầy đủ tất cả hạng mục kiểm';end if;
 if exists(select 1 from jsonb_array_elements(p_checklist) x where jsonb_typeof(x->'dat') is distinct from 'boolean') then raise exception 'Xác nhận đầy đủ tất cả hạng mục kiểm';end if;
 result:=public.duc_submit_ipqc_check(p_id_checkpoint,p_checklist,p_ket_qua,p_anh_urls,p_ghi_chu,null,p_nguoi_kiem);
 if coalesce((result->>'ok')::boolean,false)=false then raise exception '%',coalesce(result->>'error','Không lưu được kết quả');end if;
 return result;
end $function$;
