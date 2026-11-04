-- T210 — Phân cấp phê duyệt công việc can thiệp khuôn (QĐ bảo dưỡng khuôn 04/11/2026)
--   Cấp 0: tự làm (ghi phiếu) · Cấp 1: Tổ trưởng khuôn · Cấp 2: QLBP Đúc · Cấp 3: Giám đốc SX.
--   Cấp trên duyệt thay cấp dưới. Ca đêm (18:00–06:00) trưởng ca được duyệt cấp ≤2,
--   sau đó QLBP Đúc phải xác nhận "đã nắm".
--   Phiếu can thiệp gắn với: phiếu xử lý bất thường (nguon='xlbt', nguon_id = id_su_co)
--   hoặc check sheet KH bảo dưỡng (nguon='cs', nguon_id = id kế hoạch).
--   CHẶN CỨNG (server): bắt đầu xử lý (xlbt/check sheet), giao QC và đóng sự cố A2/B1/F1.
--   Chỉ áp cho việc phát sinh từ mốc duc_cau_hinh['ct_tu_thoi_diem'] (đặt lúc chạy migration).

-- ── 1. Danh mục hạng mục công việc + cam kết an toàn ─────────────────────────
create table if not exists public.duc_khuon_ct_danh_muc (
  ma text primary key,
  loai text not null check (loai in ('cong_viec', 'an_toan')),
  cap int check (cap between 0 and 3),
  noi_dung text not null,
  thu_tu int not null default 0,
  hieu_luc boolean not null default true,
  check ((loai = 'cong_viec') = (cap is not null))
);
alter table public.duc_khuon_ct_danh_muc enable row level security;
drop policy if exists ct_dm_read on public.duc_khuon_ct_danh_muc;
create policy ct_dm_read on public.duc_khuon_ct_danh_muc for select to authenticated using (true);
drop policy if exists ct_dm_admin on public.duc_khuon_ct_danh_muc;
create policy ct_dm_admin on public.duc_khuon_ct_danh_muc for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));
grant select, insert, update, delete on public.duc_khuon_ct_danh_muc to authenticated;

insert into public.duc_khuon_ct_danh_muc (ma, loai, cap, noi_dung, thu_tu) values
 ('C0-01','cong_viec',0,'Vệ sinh mặt phân khuôn, lòng khuôn bằng dụng cụ đồng / gỗ / nhựa',10),
 ('C0-02','cong_viec',0,'Thổi sạch rãnh thoát khí, đậu ngót',11),
 ('C0-03','cong_viec',0,'Thông rửa, kiểm tra rò đường nước làm mát',12),
 ('C0-04','cong_viec',0,'Bôi trơn chốt dẫn hướng, bạc dẫn, ty đẩy, slide trượt',13),
 ('C0-05','cong_viec',0,'Thay pin đẩy, chốt hồi, lò xo, đầu nối nước, gioăng trong danh mục linh kiện tiêu hao chuẩn',14),
 ('C0-06','cong_viec',0,'Kiểm tra, bảo dưỡng định kỳ khác (không thay đổi hình dạng, kích thước phần tạo hình)',15),
 ('C1-01','cong_viec',1,'Xử lý bã trầu, đánh bóng lòng khuôn chỗ bám nhôm, vết xước nhẹ bằng đá dầu / giấy nhám mịn',20),
 ('C1-02','cong_viec',1,'Xử lý bám dính nhôm bằng giấy giáp mịn, đá mài dầu (bằng tay)',21),
 ('C1-03','cong_viec',1,'Thay pin đẩy, chốt pin tạo lỗ không phải nguyên bản (nội bộ chế lại đúng bản vẽ chuẩn)',22),
 ('C1-04','cong_viec',1,'Xử lý bavia mỏng tại mặt phân khuôn, không dùng máy mài',23),
 ('C2-01','cong_viec',2,'Xử lý bám dính nhôm có dùng dụng cụ cầm tay (máy mài, máy rung, máy khoan…)',30),
 ('C2-02','cong_viec',2,'Hàn đắp lòng khuôn, hàn mặt phân khuôn',31),
 ('C2-03','cong_viec',2,'Chế tạo insert, gia công lại các chi tiết tạo hình sản phẩm',32),
 ('C2-04','cong_viec',2,'Sửa kích thước rãnh dẫn, cổng rót, đậu ngót, rãnh thoát khí',33),
 ('C2-05','cong_viec',2,'Khoan, bịt một cav; đổi sơ đồ đường nước làm mát',34),
 ('C3-01','cong_viec',3,'Đưa khuôn ra ngoài xử lý',40),
 ('C3-02','cong_viec',3,'Dời vị trí cổng rót, đổi phương án cổng rót',41),
 ('C3-03','cong_viec',3,'Tạo insert thay thế cho vị trí bị hỏng',42),
 ('C3-04','cong_viec',3,'Chế tạo linh kiện dự phòng không có bản vẽ chuẩn',43),
 ('AT-01','an_toan',null,'Sửa khuôn trên máy: đã ngắt nguồn và treo khoá, thẻ an toàn',10),
 ('AT-02','an_toan',null,'Không dùng búa, tuốc nơ vít, dụng cụ thép cạy / gõ vào lòng khuôn',11),
 ('AT-03','an_toan',null,'Không dùng máy mài cầm tay trên bề mặt tạo hình',12),
 ('AT-04','an_toan',null,'Không làm nguội khuôn nóng bằng nước',13),
 ('AT-05','an_toan',null,'Không hàn khuôn khi chưa gia nhiệt trước',14)
on conflict (ma) do nothing;

-- ── 2. Phiếu can thiệp khuôn + nhật ký ──────────────────────────────────────
create table if not exists public.duc_khuon_can_thiep (
  id bigserial primary key,
  nguon text not null check (nguon in ('xlbt', 'cs')),
  nguon_id text not null,
  ma_khuon text, ma_may text, ma_sp text,
  hang_muc jsonb not null default '[]'::jsonb,        -- [{ma, cap, noi_dung}] đang khai
  hang_muc_duyet jsonb not null default '[]'::jsonb,  -- bộ hạng mục đã được duyệt (so khi khai lại)
  khong_chac boolean not null default false,
  cap int check (cap between 0 and 3),
  mo_ta text not null default '',
  trang_thai text not null check (trang_thai in ('cho_duyet', 'da_duyet', 'tu_choi', 'khong_tac_dong')),
  nguoi_de_nghi text, de_nghi_uid uuid, de_nghi_luc timestamptz,
  nguoi_duyet text, duyet_uid uuid, duyet_luc timestamptz, vai_tro_duyet text,
  duyet_thay_ca_dem boolean not null default false,
  ly_do_tu_choi text,
  qlbp_xac_nhan text, qlbp_xac_nhan_luc timestamptz,
  an_toan jsonb not null default '[]'::jsonb, nguoi_an_toan text, an_toan_luc timestamptz,
  tao_luc timestamptz not null default now(), cap_nhat_luc timestamptz not null default now(),
  unique (nguon, nguon_id)
);
create index if not exists duc_khuon_can_thiep_khuon_idx on public.duc_khuon_can_thiep (ma_khuon, tao_luc desc);
create index if not exists duc_khuon_can_thiep_cho_idx on public.duc_khuon_can_thiep (trang_thai) where trang_thai = 'cho_duyet';

create table if not exists public.duc_khuon_can_thiep_nhat_ky (
  id bigserial primary key,
  id_ct bigint not null references public.duc_khuon_can_thiep(id) on delete cascade,
  su_kien text not null,
  du_lieu jsonb not null default '{}'::jsonb,
  nguoi text, nguoi_uid uuid,
  thoi_diem timestamptz not null default now()
);
create index if not exists duc_khuon_ct_nk_idx on public.duc_khuon_can_thiep_nhat_ky (id_ct, thoi_diem);

alter table public.duc_khuon_can_thiep enable row level security;
alter table public.duc_khuon_can_thiep_nhat_ky enable row level security;
drop policy if exists ct_read on public.duc_khuon_can_thiep;
create policy ct_read on public.duc_khuon_can_thiep for select to authenticated using (true);
drop policy if exists ct_nk_read on public.duc_khuon_can_thiep_nhat_ky;
create policy ct_nk_read on public.duc_khuon_can_thiep_nhat_ky for select to authenticated using (true);
grant select on public.duc_khuon_can_thiep, public.duc_khuon_can_thiep_nhat_ky to authenticated;

insert into public.duc_cau_hinh (khoa, gia_tri)
values ('ct_tu_thoi_diem', to_jsonb(now()))
on conflict (khoa) do nothing;

-- ── 3. Hàm phụ trợ ──────────────────────────────────────────────────────────
create or replace function public.duc_khuon_ct_moc() returns timestamptz
language sql stable security definer set search_path to 'public' as $$
  select coalesce((select (gia_tri #>> '{}')::timestamptz from duc_cau_hinh where khoa = 'ct_tu_thoi_diem'), 'infinity'::timestamptz);
$$;

create or replace function public.duc_khuon_ct_la_ca_dem() returns boolean
language sql stable as $$
  select extract(hour from (now() at time zone 'Asia/Ho_Chi_Minh')) >= 18
      or extract(hour from (now() at time zone 'Asia/Ho_Chi_Minh')) < 6;
$$;

-- Thẩm quyền duyệt của người đang đăng nhập cho 1 cấp → nhãn vai trò, null = không có quyền.
create or replace function public.duc_khuon_ct_quyen_duyet(p_cap int) returns text
language sql stable security definer set search_path to 'public' as $$
  select case
    when u.role = 'admin' then 'Admin'
    when u.role = 'giam_doc_sx' then 'Giám đốc SX'
    when u.role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(u.bo_phan_phu_trach, '{}')) and p_cap <= 2 then 'QLBP Đúc'
    when u.role = 'to_truong_khuon' and p_cap <= 1 then 'Tổ trưởng khuôn'
    when u.role = 'truong_ca' and p_cap <= 2 and duc_khuon_ct_la_ca_dem() then 'Trưởng ca (duyệt thay ca đêm)'
  end
  from user_roles u where u.user_id = auth.uid();
$$;

-- Người được khai / sửa phiếu can thiệp: tổ khuôn, QLBP Đúc, GĐSX, admin; trưởng ca (chỉ phiếu sự cố).
create or replace function public.duc_khuon_ct_duoc_khai(p_nguon text) returns boolean
language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from user_roles u where u.user_id = auth.uid()
    and (duc_khuon_bd_la_nguoi_lap(u.role, u.bo_phan_phu_trach) or u.role = 'giam_doc_sx'
         or (u.role = 'truong_ca' and p_nguon = 'xlbt')));
$$;

-- Thông tin nguồn: khuôn / máy / SP, mốc thời gian (để so mốc áp dụng), đã hoàn thành chưa.
create or replace function public.duc_khuon_ct_nguon(p_nguon text, p_nguon_id text,
  out o_ok boolean, out o_ma_khuon text, out o_ma_may text, out o_ma_sp text, out o_loai text,
  out o_moc timestamptz, out o_xong boolean)
language plpgsql stable security definer set search_path to 'public' as $$
declare v_kh duc_khuon_bd_kh_tuan; v_cs duc_khuon_checksheet;
begin
  o_ok := false; o_xong := false;
  if p_nguon = 'xlbt' then
    select s.ma_may, s.so_khuon, s.ma_sp, s.loai, s.gio into o_ma_may, o_ma_khuon, o_ma_sp, o_loai, o_moc
    from (
      select ma_may, so_khuon, ma_sp, loai_su_co loai, gio_phat_sinh gio from duc_su_co_log where id_su_co = p_nguon_id
      union all
      select ma_may, so_khuon, ma_sp, open_loai_su_co, open_gio_phat_sinh from duc_ca_hien_tai where open_id_su_co = p_nguon_id
      union all
      select c.ma_may, c.so_khuon, c.ma_sp, t.loai_su_co, t.gio_phat_sinh
        from duc_su_co_mo_them t join duc_ca_hien_tai c on c.id_dong = t.id_dong where t.id_su_co = p_nguon_id
    ) s where left(coalesce(s.loai, ''), 2) in ('A2', 'B1', 'F1')
    order by s.gio limit 1;
    if o_moc is null then return; end if;
    o_loai := left(o_loai, 2);
    o_xong := exists (select 1 from duc_khuon_xu_ly_bat_thuong where id_su_co = p_nguon_id and trang_thai = 'hoan_thanh');
    o_ok := true;
  elsif p_nguon = 'cs' then
    select * into v_kh from duc_khuon_bd_kh_tuan where id::text = p_nguon_id;
    if not found then return; end if;
    select * into v_cs from duc_khuon_checksheet where id_ke_hoach = v_kh.id;
    o_ma_khuon := v_kh.ma_khuon; o_loai := v_kh.loai;
    o_moc := coalesce(v_cs.gio_bat_dau, now());
    o_xong := coalesce(v_cs.trang_thai = 'hoan_thanh', false);
    select split_part(ten_sp_gan_nhat, ' (', 1) into o_ma_sp from duc_shot_khuon where ma_khuon = v_kh.ma_khuon;
    o_ok := true;
  end if;
end $$;

create or replace function public.duc_khuon_ct_ghi_nk(p_id bigint, p_su_kien text, p_du_lieu jsonb) returns void
language sql security definer set search_path to 'public' as $$
  insert into duc_khuon_can_thiep_nhat_ky (id_ct, su_kien, du_lieu, nguoi, nguoi_uid)
  values (p_id, p_su_kien, coalesce(p_du_lieu, '{}'::jsonb), (select o_ten from duc_khuon_bd_nguoi_hien_tai()), auth.uid());
$$;

-- Người nhận chuông khi phiếu chờ duyệt cấp p_cap (ca đêm: thêm trưởng ca cho cấp ≤2).
create or replace function public.duc_khuon_ct_nguoi_duyet_ds(p_cap int) returns uuid[]
language sql stable security definer set search_path to 'public' as $$
  select coalesce(array_agg(distinct u), '{}') from (
    select unnest(case p_cap when 1 then cv_pd_ds_role(array['to_truong_khuon'])
                              when 2 then cv_pd_ds_role(array['quan_ly_bo_phan'], 'Đúc')
                              else cv_pd_ds_role(array['giam_doc_sx']) end) u
    union all
    select unnest(cv_pd_ds_role(array['truong_ca'])) where p_cap <= 2 and duc_khuon_ct_la_ca_dem()
  ) x;
$$;

-- KIỂM TRA CHẶN CỨNG — trả câu báo lỗi (null = cho qua).
--   'bat_dau' : bắt đầu xử lý (phiếu tổ khuôn / check sheet) → có hạng mục, đã duyệt, đã cam kết an toàn,
--               giờ bắt đầu không sớm hơn giờ duyệt.
--   'giao_qc' : giao QC sự cố A2/B1/F1 → phải khai có / không tác động khuôn; có thì đủ như 'bat_dau'.
--   'dong'    : đóng sự cố → chặn nếu phiếu đang chờ duyệt / bị từ chối / chưa cam kết an toàn.
create or replace function public.duc_khuon_ct_kiem(p_nguon text, p_nguon_id text, p_muc text, p_bat_dau timestamptz default null)
returns text
language plpgsql stable security definer set search_path to 'public' as $$
declare n record; c duc_khuon_can_thiep; v_cap_txt text;
begin
  select * into n from duc_khuon_ct_nguon(p_nguon, p_nguon_id);
  if not n.o_ok then return null; end if;
  if p_nguon = 'xlbt' and n.o_moc < duc_khuon_ct_moc() then return null; end if;
  if p_nguon = 'cs' and coalesce(p_bat_dau, now()) < duc_khuon_ct_moc() then return null; end if;

  select * into c from duc_khuon_can_thiep where nguon = p_nguon and nguon_id = p_nguon_id;
  if c.id is null then
    if p_muc = 'dong' then return null; end if;
    if p_muc = 'giao_qc' then
      return '⛔ Chưa khai can thiệp khuôn cho sự cố ' || p_nguon_id || '. Bấm "🔧 Can thiệp khuôn" để chọn việc đã / đang làm trên khuôn'
        || case when n.o_loai = 'A2' then '' else ' (hoặc chọn "Không tác động vào khuôn" nếu chỉ chỉnh thông số / máy)' end || '.';
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
  if p_muc = 'bat_dau' and p_bat_dau is not null and c.cap >= 1 and c.duyet_luc is not null
     and p_bat_dau < c.duyet_luc - interval '5 minutes' then
    return '⛔ Giờ bắt đầu xử lý (' || to_char(p_bat_dau at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ') sớm hơn giờ được duyệt ('
      || to_char(c.duyet_luc at time zone 'Asia/Ho_Chi_Minh', 'HH24:MI DD/MM') || ') — không được làm trước khi duyệt.';
  end if;
  return null;
end $$;

-- ── 4. Thao tác (RPC) ────────────────────────────────────────────────────────
-- Lấy phiếu can thiệp của 1 nguồn + quyền của người đang xem.
create or replace function public.duc_khuon_ct_lay(p_nguon text, p_nguon_id text) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
declare n record; c duc_khuon_can_thiep; v_nk jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into n from duc_khuon_ct_nguon(p_nguon, p_nguon_id);
  select * into c from duc_khuon_can_thiep where nguon = p_nguon and nguon_id = p_nguon_id;
  select coalesce(jsonb_agg(jsonb_build_object('su_kien', k.su_kien, 'du_lieu', k.du_lieu, 'nguoi', k.nguoi, 'thoi_diem', k.thoi_diem)
           order by k.thoi_diem), '[]'::jsonb) into v_nk
    from duc_khuon_can_thiep_nhat_ky k where k.id_ct = c.id;
  return jsonb_build_object('ok', true,
    'ct', case when c.id is null then null else to_jsonb(c) end,
    'nhat_ky', v_nk,
    'nguon', jsonb_build_object('ok', n.o_ok, 'ma_khuon', n.o_ma_khuon, 'ma_may', n.o_ma_may, 'ma_sp', n.o_ma_sp,
                                'loai', n.o_loai, 'xong', n.o_xong),
    'ap_dung', n.o_ok and (p_nguon = 'cs' or n.o_moc >= duc_khuon_ct_moc()),
    'duoc_khai', duc_khuon_ct_duoc_khai(p_nguon),
    'quyen_duyet', case when c.id is null then null else duc_khuon_ct_quyen_duyet(c.cap) end,
    'la_ca_dem', duc_khuon_ct_la_ca_dem());
end $$;

-- Khai hạng mục công việc (tự tính cấp). Cấp 0 hoặc người khai đủ thẩm quyền → duyệt luôn; ngược lại chờ duyệt + chuông.
create or replace function public.duc_khuon_ct_luu(p_nguon text, p_nguon_id text, p_hang_muc text[],
  p_khong_chac boolean default false, p_mo_ta text default '') returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare
  n record; c duc_khuon_can_thiep; v_items jsonb; v_n int; v_cap int; v_tt text; v_quyen text;
  v_ten text := (select o_ten from duc_khuon_bd_nguoi_hien_tai());
  v_giu_duyet boolean := false; v_id bigint; v_dem boolean := false;
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
    into v_items, v_n, v_cap
  from duc_khuon_ct_danh_muc d
  where d.loai = 'cong_viec' and d.hieu_luc and d.ma = any(p_hang_muc);
  if v_n <> (select count(distinct x) from unnest(p_hang_muc) x) then
    return jsonb_build_object('ok', false, 'error', 'Có hạng mục không hợp lệ — tải lại trang');
  end if;
  v_cap := least(3, v_cap + case when coalesce(p_khong_chac, false) then 1 else 0 end);

  select * into c from duc_khuon_can_thiep where nguon = p_nguon and nguon_id = p_nguon_id for update;
  -- Đã duyệt mà khai lại trong phạm vi đã duyệt (không thêm việc mới, không lên cấp) → giữ duyệt.
  v_giu_duyet := c.id is not null and c.trang_thai = 'da_duyet' and v_cap <= coalesce(c.cap, 0)
    and not exists (select 1 from jsonb_array_elements(v_items) i
                    where not exists (select 1 from jsonb_array_elements(c.hang_muc_duyet) j where j->>'ma' = i->>'ma'));
  v_quyen := duc_khuon_ct_quyen_duyet(v_cap);
  v_tt := case when v_cap = 0 or v_giu_duyet or v_quyen is not null then 'da_duyet' else 'cho_duyet' end;
  v_dem := v_tt = 'da_duyet' and not v_giu_duyet and v_cap > 0 and v_quyen like 'Trưởng ca%';

  insert into duc_khuon_can_thiep as t (nguon, nguon_id, ma_khuon, ma_may, ma_sp, hang_muc, hang_muc_duyet, khong_chac, cap, mo_ta,
      trang_thai, nguoi_de_nghi, de_nghi_uid, de_nghi_luc, nguoi_duyet, duyet_uid, duyet_luc, vai_tro_duyet, duyet_thay_ca_dem)
  values (p_nguon, p_nguon_id, n.o_ma_khuon, n.o_ma_may, n.o_ma_sp, v_items,
      case when v_tt = 'da_duyet' then v_items else '[]'::jsonb end, coalesce(p_khong_chac, false), v_cap, coalesce(trim(p_mo_ta), ''),
      v_tt, v_ten, auth.uid(), now(),
      case when v_tt = 'da_duyet' then case when v_cap = 0 then '' else v_ten end end,
      case when v_tt = 'da_duyet' and v_cap > 0 then auth.uid() end,
      case when v_tt = 'da_duyet' then now() end,
      case when v_tt = 'da_duyet' then case when v_cap = 0 then 'Cấp 0 — không cần duyệt' else v_quyen || ' — tự duyệt khi khai' end end,
      v_dem)
  on conflict (nguon, nguon_id) do update set
    ma_khuon = excluded.ma_khuon, ma_may = coalesce(excluded.ma_may, t.ma_may), ma_sp = coalesce(excluded.ma_sp, t.ma_sp),
    hang_muc = excluded.hang_muc, khong_chac = excluded.khong_chac, cap = excluded.cap, mo_ta = excluded.mo_ta,
    trang_thai = excluded.trang_thai,
    hang_muc_duyet = case when v_giu_duyet then t.hang_muc_duyet else excluded.hang_muc_duyet end,
    nguoi_de_nghi = case when v_giu_duyet then t.nguoi_de_nghi else excluded.nguoi_de_nghi end,
    de_nghi_uid = case when v_giu_duyet then t.de_nghi_uid else excluded.de_nghi_uid end,
    de_nghi_luc = case when v_giu_duyet then t.de_nghi_luc else excluded.de_nghi_luc end,
    nguoi_duyet = case when v_giu_duyet then t.nguoi_duyet else excluded.nguoi_duyet end,
    duyet_uid = case when v_giu_duyet then t.duyet_uid else excluded.duyet_uid end,
    duyet_luc = case when v_giu_duyet then t.duyet_luc else excluded.duyet_luc end,
    vai_tro_duyet = case when v_giu_duyet then t.vai_tro_duyet else excluded.vai_tro_duyet end,
    duyet_thay_ca_dem = case when v_giu_duyet then t.duyet_thay_ca_dem else excluded.duyet_thay_ca_dem end,
    qlbp_xac_nhan = case when v_giu_duyet then t.qlbp_xac_nhan end,
    qlbp_xac_nhan_luc = case when v_giu_duyet then t.qlbp_xac_nhan_luc end,
    ly_do_tu_choi = null, cap_nhat_luc = now()
  returning id into v_id;

  perform duc_khuon_ct_ghi_nk(v_id, 'khai', jsonb_build_object('hang_muc', v_items, 'cap', v_cap, 'khong_chac', coalesce(p_khong_chac, false),
    'trang_thai', v_tt, 'vai_tro_duyet', case when v_tt = 'da_duyet' and not v_giu_duyet then coalesce(v_quyen, 'Cấp 0') end, 'mo_ta', p_mo_ta));

  begin
    perform cv_pd_xong('khuon_ct:' || v_id);
    if v_tt = 'cho_duyet' then
      perform cv_pd_gui(duc_khuon_ct_nguoi_duyet_ds(v_cap), 'bd_khuon', 'duyet_can_thiep', 'khuon_ct:' || v_id,
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

  return jsonb_build_object('ok', true, 'id', v_id, 'cap', v_cap, 'trang_thai', v_tt, 'giu_duyet', v_giu_duyet);
end $$;

-- Trưởng ca khai sự cố B1/F1 "không tác động vào khuôn" (chỉ chỉnh thông số / máy) → được giao QC.
create or replace function public.duc_khuon_ct_khong_tac_dong(p_id_su_co text, p_ghi_chu text default '') returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare n record; c duc_khuon_can_thiep; v_id bigint; v_ten text := (select o_ten from duc_khuon_bd_nguoi_hien_tai());
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if not duc_khuon_ct_duoc_khai('xlbt') then return jsonb_build_object('ok', false, 'error', 'Tài khoản không được khai'); end if;
  select * into n from duc_khuon_ct_nguon('xlbt', p_id_su_co);
  if not n.o_ok then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố A2/B1/F1 ' || coalesce(p_id_su_co, '')); end if;
  if n.o_loai = 'A2' then
    return jsonb_build_object('ok', false, 'error', 'Sự cố A2 (khuôn) luôn có tác động vào khuôn — chọn hạng mục công việc.');
  end if;
  select * into c from duc_khuon_can_thiep where nguon = 'xlbt' and nguon_id = p_id_su_co for update;
  if c.id is not null and c.trang_thai in ('cho_duyet', 'da_duyet') and jsonb_array_length(c.hang_muc) > 0 then
    return jsonb_build_object('ok', false, 'error', 'Sự cố đã khai công việc can thiệp khuôn cấp ' || c.cap || ' (' || coalesce(c.nguoi_de_nghi, '') ||
      ') — không chuyển sang "Không tác động" được.');
  end if;
  insert into duc_khuon_can_thiep as t (nguon, nguon_id, ma_khuon, ma_may, ma_sp, trang_thai, mo_ta, nguoi_de_nghi, de_nghi_uid, de_nghi_luc)
  values ('xlbt', p_id_su_co, n.o_ma_khuon, n.o_ma_may, n.o_ma_sp, 'khong_tac_dong', coalesce(trim(p_ghi_chu), ''), v_ten, auth.uid(), now())
  on conflict (nguon, nguon_id) do update set trang_thai = 'khong_tac_dong', hang_muc = '[]'::jsonb, hang_muc_duyet = '[]'::jsonb,
    cap = null, mo_ta = excluded.mo_ta, nguoi_de_nghi = excluded.nguoi_de_nghi, de_nghi_uid = excluded.de_nghi_uid,
    de_nghi_luc = now(), ly_do_tu_choi = null, cap_nhat_luc = now()
  returning id into v_id;
  perform duc_khuon_ct_ghi_nk(v_id, 'khong_tac_dong', jsonb_build_object('ghi_chu', p_ghi_chu));
  perform cv_pd_xong('khuon_ct:' || v_id);
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- Duyệt / từ chối.
create or replace function public.duc_khuon_ct_duyet(p_id bigint, p_dong_y boolean, p_ly_do text default '') returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare c duc_khuon_can_thiep; v_quyen text; v_ten text := (select o_ten from duc_khuon_bd_nguoi_hien_tai()); v_dem boolean;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select * into c from duc_khuon_can_thiep where id = p_id for update;
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu'); end if;
  if c.trang_thai <> 'cho_duyet' then return jsonb_build_object('ok', false, 'error', 'Phiếu không ở trạng thái chờ duyệt (đã có người xử lý) — tải lại'); end if;
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
    nguoi_duyet = v_ten, duyet_uid = auth.uid(), duyet_luc = now(), vai_tro_duyet = v_quyen,
    duyet_thay_ca_dem = v_dem, qlbp_xac_nhan = null, qlbp_xac_nhan_luc = null,
    ly_do_tu_choi = case when p_dong_y then null else trim(p_ly_do) end, cap_nhat_luc = now()
  where id = p_id;
  perform duc_khuon_ct_ghi_nk(p_id, case when p_dong_y then 'duyet' else 'tu_choi' end,
    jsonb_build_object('vai_tro', v_quyen, 'ly_do', p_ly_do, 'cap', c.cap));
  begin
    perform cv_pd_xong('khuon_ct:' || p_id);
    perform cv_pd_gui(array[c.de_nghi_uid], 'bd_khuon', case when p_dong_y then 'ct_da_duyet' else 'ct_tu_choi' end, 'khuon_ct_kq:' || p_id,
      'bao-duong-khuon-tuan.html#cardCt',
      case when p_dong_y then '✅ Đã duyệt cấp ' || c.cap || ' khuôn ' || coalesce(c.ma_khuon, '?') || ' (' || v_ten || ') — được bắt đầu xử lý.'
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

-- QLBP Đúc xác nhận đã nắm việc trưởng ca duyệt thay ca đêm.
create or replace function public.duc_khuon_ct_qlbp_xac_nhan(p_id bigint, p_ghi_chu text default '') returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare c duc_khuon_can_thiep; v_ten text := (select o_ten from duc_khuon_bd_nguoi_hien_tai());
begin
  if not exists (select 1 from user_roles u where u.user_id = auth.uid() and (u.role in ('admin', 'giam_doc_sx')
                 or (u.role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(u.bo_phan_phu_trach, '{}'))))) then
    return jsonb_build_object('ok', false, 'error', 'Chỉ Quản lý bộ phận Đúc (hoặc GĐSX) xác nhận');
  end if;
  select * into c from duc_khuon_can_thiep where id = p_id for update;
  if c.id is null or not c.duyet_thay_ca_dem then return jsonb_build_object('ok', false, 'error', 'Phiếu không phải duyệt thay ca đêm'); end if;
  if c.qlbp_xac_nhan is not null then return jsonb_build_object('ok', false, 'error', 'Đã xác nhận bởi ' || c.qlbp_xac_nhan); end if;
  update duc_khuon_can_thiep set qlbp_xac_nhan = v_ten, qlbp_xac_nhan_luc = now(), cap_nhat_luc = now() where id = p_id;
  perform duc_khuon_ct_ghi_nk(p_id, 'qlbp_xac_nhan', jsonb_build_object('ghi_chu', p_ghi_chu));
  perform cv_pd_xong('khuon_ct_bc:' || p_id);
  return jsonb_build_object('ok', true);
end $$;

-- Cam kết an toàn trước khi bắt đầu (phải tick đủ mọi mục đang hiệu lực).
create or replace function public.duc_khuon_ct_an_toan(p_id bigint, p_ma text[]) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare c duc_khuon_can_thiep; v_thieu text; v_ten text := (select o_ten from duc_khuon_bd_nguoi_hien_tai());
begin
  select * into c from duc_khuon_can_thiep where id = p_id for update;
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy phiếu'); end if;
  if not duc_khuon_ct_duoc_khai(c.nguon) then return jsonb_build_object('ok', false, 'error', 'Tài khoản không được khai'); end if;
  if c.trang_thai <> 'da_duyet' then return jsonb_build_object('ok', false, 'error', 'Công việc chưa được duyệt — chưa cam kết an toàn được'); end if;
  select string_agg(noi_dung, '; ' order by thu_tu) into v_thieu from duc_khuon_ct_danh_muc
   where loai = 'an_toan' and hieu_luc and not (ma = any(coalesce(p_ma, '{}')));
  if v_thieu is not null then return jsonb_build_object('ok', false, 'error', 'Chưa tick đủ cam kết an toàn: ' || v_thieu); end if;
  update duc_khuon_can_thiep set an_toan = to_jsonb(p_ma), nguoi_an_toan = v_ten, an_toan_luc = now(), cap_nhat_luc = now() where id = p_id;
  perform duc_khuon_ct_ghi_nk(p_id, 'an_toan', jsonb_build_object('ma', p_ma));
  return jsonb_build_object('ok', true);
end $$;

-- Danh sách cần xử lý: chờ duyệt + duyệt thay ca đêm chưa được QLBP xác nhận.
create or replace function public.duc_khuon_ct_cho_duyet() returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
declare v_out jsonb; v_la_qlbp boolean;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  v_la_qlbp := exists (select 1 from user_roles u where u.user_id = auth.uid() and (u.role in ('admin', 'giam_doc_sx')
                 or (u.role = 'quan_ly_bo_phan' and 'Đúc' = any(coalesce(u.bo_phan_phu_trach, '{}')))));
  select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object(
           'quyen_duyet', duc_khuon_ct_quyen_duyet(c.cap),
           'quyen_xac_nhan', v_la_qlbp and c.duyet_thay_ca_dem and c.qlbp_xac_nhan is null,
           'loai_nguon', case when c.nguon = 'xlbt'
               then (select left(l.loai_su_co, 2) from duc_su_co_log l where l.id_su_co = c.nguon_id limit 1)
               else (select k.loai from duc_khuon_bd_kh_tuan k where k.id::text = c.nguon_id) end)
         order by (c.trang_thai = 'cho_duyet') desc, c.de_nghi_luc), '[]'::jsonb)
    into v_out
  from duc_khuon_can_thiep c
  where c.trang_thai = 'cho_duyet'
     or (c.duyet_thay_ca_dem and c.qlbp_xac_nhan is null and c.trang_thai in ('da_duyet') and c.duyet_luc > now() - interval '30 days');
  return jsonb_build_object('ok', true, 'rows', v_out, 'la_ca_dem', duc_khuon_ct_la_ca_dem());
end $$;

-- Lịch sử can thiệp theo khuôn (null = mọi khuôn), kèm kết quả xử lý + IPQC sau sự cố.
create or replace function public.duc_khuon_ct_lich_su(p_ma_khuon text default null, p_tu date default null) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
declare v_out jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  select coalesce(jsonb_agg(r order by r->>'tao_luc' desc), '[]'::jsonb) into v_out from (
    select to_jsonb(c) || jsonb_build_object(
      'xl', case when c.nguon = 'xlbt' then (select jsonb_build_object('trang_thai', x.trang_thai, 'nguoi', concat_ws(' + ', nullif(x.nguoi_dam_nhiem, ''), nullif(x.nguoi_dam_nhiem_phu, '')),
                  'bat_dau', x.bat_dau, 'ket_thuc', x.ket_thuc, 'noi_dung', x.noi_dung_xu_ly) from duc_khuon_xu_ly_bat_thuong x where x.id_su_co = c.nguon_id)
                 else (select jsonb_build_object('trang_thai', s.trang_thai, 'nguoi', concat_ws(' + ', nullif(s.nguoi_thuc_hien, ''), nullif(s.nguoi_thuc_hien_phu, '')),
                  'bat_dau', s.gio_bat_dau, 'ket_thuc', s.gio_ket_thuc, 'noi_dung', s.ghi_chu, 'ket_luan', s.ket_luan, 'loai', s.loai)
                  from duc_khuon_checksheet s where s.id_ke_hoach::text = c.nguon_id) end,
      'qc', case when c.nguon = 'xlbt' then (select jsonb_build_object('ket_qua', cp.ket_qua, 'thoi_diem', cp.thoi_diem_kiem_thuc_te)
                  from duc_ipqc_checkpoint cp where cp.id_su_co_goc = c.nguon_id and cp.trang_thai = 'da_kiem'
                  order by cp.thoi_diem_kiem_thuc_te desc limit 1) end
    ) r
    from duc_khuon_can_thiep c
    where (p_ma_khuon is null or c.ma_khuon = p_ma_khuon)
      and c.tao_luc >= coalesce(p_tu, current_date - 90)::timestamp at time zone 'Asia/Ho_Chi_Minh'
    order by c.tao_luc desc limit 500
  ) z;
  return jsonb_build_object('ok', true, 'rows', v_out);
end $$;

-- ── 5. Chèn điểm chặn vào các hàm có sẵn (vá theo mốc văn bản — báo lỗi nếu hàm đã khác) ──
do $patch$
declare d text; n text;
begin
  -- 5a. Phiếu xử lý bất thường: có giờ bắt đầu → phải đủ điều kiện can thiệp.
  d := pg_get_functiondef('public.duc_khuon_xlbt_luu(text,text,text,text,timestamptz,timestamptz,text)'::regprocedure);
  if position('duc_khuon_ct_kiem' in d) = 0 then
    n := replace(d, E'  v_anh_truoc int; v_anh_sau int;\n', E'  v_anh_truoc int; v_anh_sau int;\n  v_ct_loi text;   -- T210\n');
    n := replace(n, E'  if p_hanh_dong = ''hoan_thanh'' then\n    if v_chinh = ''''',
      E'  -- T210: phân cấp phê duyệt can thiệp khuôn — chưa duyệt / chưa cam kết an toàn thì chưa được bắt đầu.\n'
      || E'  if p_bat_dau is not null or p_hanh_dong = ''hoan_thanh'' then\n'
      || E'    v_ct_loi := duc_khuon_ct_kiem(''xlbt'', v_id, ''bat_dau'', p_bat_dau);\n'
      || E'    if v_ct_loi is not null then return jsonb_build_object(''ok'', false, ''chan_ct'', true, ''error'', v_ct_loi); end if;\n'
      || E'  end if;\n\n'
      || E'  if p_hanh_dong = ''hoan_thanh'' then\n    if v_chinh = ''''');
    if n = d or position('v_ct_loi :=' in n) = 0 or position('v_ct_loi text;' in n) = 0 then raise exception 'T210: không vá được duc_khuon_xlbt_luu'; end if;
    execute n;
  end if;

  -- 5b. Check sheet bảo dưỡng.
  d := pg_get_functiondef('public.duc_khuon_cs_luu(bigint,jsonb,boolean)'::regprocedure);
  if position('duc_khuon_ct_kiem' in d) = 0 then
    n := replace(d, 'v_n_vd int := 0; r record;', 'v_n_vd int := 0; r record; v_ct_loi text;');
    n := replace(n, E'  if p_hoan_thanh then\n    if exists',
      E'  -- T210: phân cấp phê duyệt can thiệp khuôn.\n'
      || E'  if v_bd is not null or p_hoan_thanh then\n'
      || E'    v_ct_loi := duc_khuon_ct_kiem(''cs'', p_id_ke_hoach::text, ''bat_dau'', coalesce(v_bd, now()));\n'
      || E'    if v_ct_loi is not null then return jsonb_build_object(''ok'', false, ''chan_ct'', true, ''error'', v_ct_loi); end if;\n'
      || E'  end if;\n\n'
      || E'  if p_hoan_thanh then\n    if exists');
    if n = d or position('v_ct_loi :=' in n) = 0 or position('v_ct_loi text;' in n) = 0 then raise exception 'T210: không vá được duc_khuon_cs_luu'; end if;
    execute n;
  end if;

  -- 5c. Giao QC sự cố A2/B1/F1.
  d := pg_get_functiondef('public.duc_giao_qc_x(text,text,text)'::regprocedure);
  if position('duc_khuon_ct_kiem' in d) = 0 then
    n := replace(d, 'v_lan int; v_now timestamptz := now();', 'v_lan int; v_now timestamptz := now(); v_ct_loi text;');
    n := replace(n, E'  select max(thoi_diem) into v_lan_cuoi from duc_su_co_giao_qc where id_su_co = v_id;',
      E'  -- T210: phải khai can thiệp khuôn (hoặc "không tác động") và được duyệt trước khi giao QC.\n'
      || E'  if left(coalesce(v_loai, ''''), 2) in (''A2'', ''B1'', ''F1'') then\n'
      || E'    v_ct_loi := duc_khuon_ct_kiem(''xlbt'', v_id, ''giao_qc'');\n'
      || E'    if v_ct_loi is not null then return jsonb_build_object(''ok'', false, ''chan_ct'', true, ''error'', v_ct_loi); end if;\n'
      || E'  end if;\n\n'
      || E'  select max(thoi_diem) into v_lan_cuoi from duc_su_co_giao_qc where id_su_co = v_id;');
    if n = d or position('v_ct_loi :=' in n) = 0 or position('v_ct_loi text;' in n) = 0 then raise exception 'T210: không vá được duc_giao_qc_x'; end if;
    execute n;
  end if;

  -- 5d. Đóng sự cố (mọi đường đóng đều qua duc_resolve_incident; đổi SP T188 bỏ qua).
  d := pg_get_functiondef('public.duc_resolve_incident(text,timestamptz,text,text,text)'::regprocedure);
  if position('duc_khuon_ct_kiem' in d) = 0 then
    n := replace(d, E'  v_vuot_ipqc boolean := false;\n', E'  v_vuot_ipqc boolean := false;\n  v_ct_loi text;   -- T210\n');
    n := replace(n, E'  -- T170 CHẶN CỨNG:',
      E'  -- T210: công việc can thiệp khuôn đang chờ duyệt / bị từ chối / chưa cam kết an toàn → chưa đóng được.\n'
      || E'  if v_doi_sp is null and v_cht.open_id_su_co is not null and left(coalesce(v_cht.open_loai_su_co, ''''), 2) in (''A2'', ''B1'', ''F1'') then\n'
      || E'    v_ct_loi := duc_khuon_ct_kiem(''xlbt'', v_cht.open_id_su_co, ''dong'');\n'
      || E'    if v_ct_loi is not null then return jsonb_build_object(''ok'', false, ''chan_ct'', true, ''error'', v_ct_loi); end if;\n'
      || E'  end if;\n\n'
      || E'  -- T170 CHẶN CỨNG:');
    if n = d or position('v_ct_loi :=' in n) = 0 or position('v_ct_loi text;' in n) = 0 then raise exception 'T210: không vá được duc_resolve_incident'; end if;
    execute n;
  end if;
end $patch$;

-- ── 6. Quyền ───────────────────────────────────────────────────────────────
revoke execute on function public.duc_khuon_ct_moc(), public.duc_khuon_ct_la_ca_dem(), public.duc_khuon_ct_quyen_duyet(int),
  public.duc_khuon_ct_duoc_khai(text), public.duc_khuon_ct_nguon(text, text), public.duc_khuon_ct_ghi_nk(bigint, text, jsonb),
  public.duc_khuon_ct_nguoi_duyet_ds(int), public.duc_khuon_ct_kiem(text, text, text, timestamptz)
  from public, anon, authenticated;
revoke execute on function public.duc_khuon_ct_lay(text, text), public.duc_khuon_ct_luu(text, text, text[], boolean, text),
  public.duc_khuon_ct_khong_tac_dong(text, text), public.duc_khuon_ct_duyet(bigint, boolean, text),
  public.duc_khuon_ct_qlbp_xac_nhan(bigint, text), public.duc_khuon_ct_an_toan(bigint, text[]),
  public.duc_khuon_ct_cho_duyet(), public.duc_khuon_ct_lich_su(text, date)
  from public, anon;
grant execute on function public.duc_khuon_ct_lay(text, text), public.duc_khuon_ct_luu(text, text, text[], boolean, text),
  public.duc_khuon_ct_khong_tac_dong(text, text), public.duc_khuon_ct_duyet(bigint, boolean, text),
  public.duc_khuon_ct_qlbp_xac_nhan(bigint, text), public.duc_khuon_ct_an_toan(bigint, text[]),
  public.duc_khuon_ct_cho_duyet(), public.duc_khuon_ct_lich_su(text, date)
  to authenticated;
