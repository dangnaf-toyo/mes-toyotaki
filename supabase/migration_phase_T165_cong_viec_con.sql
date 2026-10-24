-- ============================================================================
-- Phase T165 — Việc lớn → Việc con (module Quản lý công việc T161)
--
-- Một việc lớn có thể có nhiều việc con, mỗi việc con có người làm + hạn riêng.
-- Việc con là 1 việc đầy đủ (Kanban, chuông, nhận, báo xong, gia hạn, duyệt...).
--
-- Quyết định của user (24/10/2026):
--   - Người GIAO và người NHẬN việc lớn đều tạo được việc con (BGĐ cũng được).
--   - Hạn việc con ĐƯỢC muộn hơn hạn việc lớn (giao diện chỉ nhắc).
--   - Việc lớn còn việc con chưa xong: chỉ CẢNH BÁO khi báo xong / duyệt (không chặn).
--   - Người DUYỆT việc con = người giao việc lớn.
--
-- Cách làm:
--   - cv_cong_viec.viec_cha_id (1 cấp: việc con không có việc con), nguoi_tao = người
--     thực sự tạo việc con. nguoi_giao của việc con = nguoi_giao của việc lớn → mọi
--     quyền "người giao" sẵn có (duyệt, trả lại, trả lời gia hạn, mở lại) tự đúng.
--   - Người nhận việc lớn (người chia việc) được thêm quyền sửa / nhắc / huỷ / sửa
--     bước của việc con (cv_quyen_quan_ly), KHÔNG được duyệt.
--   - Xem được: người tạo việc con, người nhận việc lớn thấy việc con; người làm việc
--     con thấy việc lớn (để biết bối cảnh) — kể cả khi "hạn chế".
--   - Việc con hoàn thành → báo người nhận việc lớn; đủ hết → nhắc báo xong việc lớn.
-- An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

-- 1. Cột mới
alter table public.cv_cong_viec add column if not exists viec_cha_id bigint references public.cv_cong_viec(id) on delete cascade;
alter table public.cv_cong_viec add column if not exists nguoi_tao uuid;
alter table public.cv_cong_viec drop constraint if exists cv_cong_viec_cha_khac_minh;
alter table public.cv_cong_viec add constraint cv_cong_viec_cha_khac_minh check (viec_cha_id is distinct from id);
create index if not exists idx_cv_cong_viec_cha on public.cv_cong_viec (viec_cha_id) where viec_cha_id is not null;

-- 2. Quyền xem: thêm người tạo việc con, người nhận việc lớn, người làm việc con (xem việc lớn)
create or replace function public.cv_xem_duoc(p_cong_viec_id bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (
    select 1 from cv_cong_viec c
    where c.id = p_cong_viec_id
      and (c.hien_thi = 'cong_khai'
           or c.nguoi_giao = auth.uid()
           or c.nguoi_lam = auth.uid()
           or c.nguoi_tao = auth.uid()
           or exists (select 1 from cv_nguoi_phoi_hop p where p.cong_viec_id = c.id and p.user_id = auth.uid())
           or exists (select 1 from cv_cong_viec cha where cha.id = c.viec_cha_id and cha.nguoi_lam = auth.uid())
           or exists (select 1 from cv_cong_viec con where con.viec_cha_id = c.id and con.nguoi_lam = auth.uid())
           or public.cv_la_bgd())
  );
$$;

-- 3. Quyền quản lý (sửa / nhắc / huỷ / sửa bước): người giao, BGĐ, hoặc người nhận việc lớn (với việc con)
create or replace function public.cv_quyen_quan_ly(v public.cv_cong_viec)
returns boolean language sql stable security definer set search_path = public as $$
  select public.cv_quyen_giao(v.nguoi_giao)
      or (v.viec_cha_id is not null
          and exists (select 1 from cv_cong_viec cha where cha.id = v.viec_cha_id and cha.nguoi_lam = auth.uid()));
$$;
revoke execute on function public.cv_quyen_quan_ly(public.cv_cong_viec) from public, anon;
grant execute on function public.cv_quyen_quan_ly(public.cv_cong_viec) to authenticated;

-- Đổi kiểm tra quyền trong các RPC sẵn có (giữ nguyên phần còn lại của hàm đang chạy).
do $$
declare
  f text; d text; d2 text;
  doi constant text[][] := array[
    array['cv_sua_viec(bigint,jsonb)',  'if not cv_quyen_giao(v.nguoi_giao) then', 'if not cv_quyen_quan_ly(v) then'],
    array['cv_nhac_viec(bigint)',        'if not cv_quyen_giao(v.nguoi_giao) then', 'if not cv_quyen_quan_ly(v) then'],
    array['cv_huy_viec(bigint,text)',    'if not cv_quyen_giao(v.nguoi_giao) then', 'if not cv_quyen_quan_ly(v) then'],
    array['cv_them_buoc(bigint,text)',   'or cv_quyen_giao(v.nguoi_giao)',          'or cv_quyen_quan_ly(v)'],
    array['cv_xoa_buoc(bigint)',         'or cv_quyen_giao(v.nguoi_giao)',          'or cv_quyen_quan_ly(v)']
  ];
  i int;
begin
  for i in 1 .. array_length(doi, 1) loop
    f := doi[i][1];
    d := pg_get_functiondef(('public.' || f)::regprocedure);
    if position(doi[i][3] in d) > 0 then continue; end if;          -- đã đổi (chạy lại)
    if position(doi[i][2] in d) = 0 then raise exception 'T165: không thấy đoạn kiểm tra quyền trong %', f; end if;
    d2 := replace(d, doi[i][2], doi[i][3]);
    execute d2;
  end loop;
end $$;

-- 4. Tạo việc con. p như cv_tao_viec; thiếu bo_phan/du_an_id/hien_thi/quan_trong thì lấy theo việc lớn.
create or replace function public.cv_tao_viec_con(p_cha bigint, p jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  c cv_cong_viec;
  v_uid uuid := auth.uid();
  v_id bigint;
  r cv_cong_viec;
begin
  c := cv_lay_viec(p_cha);
  if c.viec_cha_id is not null then raise exception 'Việc con không chia nhỏ tiếp được — hãy thêm việc con vào việc lớn.'; end if;
  if not (cv_quyen_giao(c.nguoi_giao) or c.nguoi_lam = v_uid) then
    raise exception 'Chỉ người giao hoặc người nhận việc lớn mới tạo được việc con.';
  end if;
  if c.trang_thai in ('hoan_thanh', 'huy') then raise exception 'Việc lớn đã hoàn thành hoặc đã huỷ, không thêm việc con được.'; end if;

  p := jsonb_build_object('bo_phan', c.bo_phan, 'du_an_id', c.du_an_id, 'hien_thi', c.hien_thi, 'quan_trong', c.quan_trong)
       || jsonb_strip_nulls(coalesce(p, '{}'::jsonb));
  v_id := cv_tao_viec(p);
  update cv_cong_viec set viec_cha_id = p_cha, nguoi_tao = v_uid, nguoi_giao = c.nguoi_giao where id = v_id
  returning * into r;

  perform cv_ghi_ls(p_cha, 'them_viec_con', cv_ten_nguoi(v_uid) || ' thêm việc con "' || r.tieu_de || '" — '
                    || coalesce(cv_ten_nguoi(r.nguoi_lam), '') || ', hạn ' || cv_fmt(r.han) || '.');
  -- Người duyệt (người giao việc lớn) biết có việc con mới sẽ chờ mình duyệt.
  perform cv_gui_tb(array[c.nguoi_giao], 'cap_nhat_viec', v_id, null,
                    cv_ten_nguoi(v_uid) || ' chia việc con "' || r.tieu_de || '" cho ' || coalesce(cv_ten_nguoi(r.nguoi_lam), '')
                    || ' (thuộc "' || c.tieu_de || '", hạn ' || cv_fmt(r.han) || '). Bạn là người duyệt.', false);
  return v_id;
end;
$$;
revoke execute on function public.cv_tao_viec_con(bigint, jsonb) from public, anon;
grant execute on function public.cv_tao_viec_con(bigint, jsonb) to authenticated;

-- 5. Việc con hoàn thành → báo người nhận việc lớn; xong hết → nhắc báo xong việc lớn.
create or replace function public.cv_trg_viec_con_xong()
returns trigger language plpgsql security definer set search_path = public as $$
declare c cv_cong_viec; v_tong int; v_xong int; v_mo int;
begin
  begin
    if new.viec_cha_id is null or new.trang_thai is not distinct from old.trang_thai
       or new.trang_thai not in ('hoan_thanh', 'huy') then
      return new;
    end if;
    select * into c from cv_cong_viec where id = new.viec_cha_id;
    if not found or c.trang_thai in ('hoan_thanh', 'huy') then return new; end if;
    select count(*) filter (where trang_thai <> 'huy'), count(*) filter (where trang_thai = 'hoan_thanh'),
           count(*) filter (where trang_thai not in ('hoan_thanh', 'huy'))
      into v_tong, v_xong, v_mo
    from cv_cong_viec where viec_cha_id = c.id;
    if new.trang_thai = 'hoan_thanh' then
      perform cv_gui_tb(array[c.nguoi_lam], 'cap_nhat_viec', c.id, null,
        'Việc con "' || new.tieu_de || '" đã hoàn thành (' || v_xong || '/' || v_tong || ') — thuộc "' || c.tieu_de || '".', false);
    end if;
    if v_mo = 0 and v_tong > 0 then
      perform cv_gui_tb(array[c.nguoi_lam], 'cap_nhat_viec', c.id, null,
        'Tất cả việc con của "' || c.tieu_de || '" đã xong — có thể báo hoàn thành việc lớn.', true);
    end if;
  exception when others then
    raise warning 'T165 thông báo việc con lỗi (bỏ qua, không chặn thao tác): %', sqlerrm;
  end;
  return new;
end;
$$;
revoke execute on function public.cv_trg_viec_con_xong() from public, anon, authenticated;
drop trigger if exists trg_cv_viec_con_xong on public.cv_cong_viec;
create trigger trg_cv_viec_con_xong after update of trang_thai on public.cv_cong_viec
  for each row execute function public.cv_trg_viec_con_xong();

-- 6. View: thêm việc lớn / người tạo / tiến độ việc con
drop view if exists public.cv_cong_viec_v;
create view public.cv_cong_viec_v with (security_invoker = true) as
select c.*,
  public.cv_ten_nguoi(c.nguoi_giao) as ten_nguoi_giao,
  public.cv_ten_nguoi(c.nguoi_lam)  as ten_nguoi_lam,
  coalesce(ph.ids, '{}'::uuid[])    as phoi_hop,
  coalesce(ph.tens, '{}'::text[])   as ten_phoi_hop,
  g.gap_hieu_luc,
  case when c.quan_trong and g.gap_hieu_luc then 1
       when c.quan_trong then 2
       when g.gap_hieu_luc then 3
       else 4 end                   as nhom,
  (c.trang_thai not in ('hoan_thanh','huy') and now() > c.han) as qua_han,
  coalesce(ck.so_buoc, 0)           as so_buoc,
  coalesce(ck.so_buoc_xong, 0)      as so_buoc_xong,
  coalesce(bl.n, 0)                 as so_binh_luan,
  d.ten                             as ten_du_an,
  round((extract(epoch from (c.han - now())) / 3600.0)::numeric, 1) as con_gio,
  public.cv_ten_nguoi(c.nguoi_tao)  as ten_nguoi_tao,
  cha.tieu_de                       as tieu_de_cha,
  coalesce(vc.tong, 0)              as so_viec_con,
  coalesce(vc.xong, 0)              as so_viec_con_xong,
  coalesce(vc.mo, 0)                as so_viec_con_mo,
  coalesce(vc.qua_han, 0)           as so_viec_con_qua_han
from public.cv_cong_viec c
cross join lateral (
  select (c.gap or (c.trang_thai not in ('hoan_thanh','huy') and c.han <= now() + interval '2 days')) as gap_hieu_luc
) g
left join lateral (
  select array_agg(p.user_id order by p.user_id) as ids,
         array_agg(public.cv_ten_nguoi(p.user_id) order by p.user_id) as tens
  from public.cv_nguoi_phoi_hop p where p.cong_viec_id = c.id
) ph on true
left join lateral (
  select count(*)::int as so_buoc, (count(*) filter (where k.xong))::int as so_buoc_xong
  from public.cv_checklist k where k.cong_viec_id = c.id
) ck on true
left join lateral (
  select count(*)::int as n from public.cv_binh_luan b where b.cong_viec_id = c.id
) bl on true
left join lateral (
  select (count(*) filter (where x.trang_thai <> 'huy'))::int as tong,
         (count(*) filter (where x.trang_thai = 'hoan_thanh'))::int as xong,
         (count(*) filter (where x.trang_thai not in ('hoan_thanh','huy')))::int as mo,
         (count(*) filter (where x.trang_thai not in ('hoan_thanh','huy') and now() > x.han))::int as qua_han
  from public.cv_cong_viec x where x.viec_cha_id = c.id
) vc on true
left join public.cv_cong_viec cha on cha.id = c.viec_cha_id
left join public.cv_du_an d on d.id = c.du_an_id;

revoke all on public.cv_cong_viec_v from public, anon, authenticated;
grant select on public.cv_cong_viec_v to authenticated;
