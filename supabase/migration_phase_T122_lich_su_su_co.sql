-- ============================================================================
-- T122 — Lịch sử đầy đủ của 1 sự cố Đúc (xem khi IPQC kiểm sản phẩm đầu tiên
-- sau xử lý sự cố): ai phát hiện / báo lúc nào, hiện trạng, nguyên nhân, ai xử
-- lý, nội dung xử lý qua các lần cập nhật, tổ khuôn, linh kiện đã thay, các lần
-- IPQC kiểm, đề nghị cho tiếp tục SX, máy chạy lại — kèm ảnh.
--
--   1) Bảng duc_su_co_nhat_ky: trước đây không lưu AI báo / AI sửa nội dung sự
--      cố (duc_open_incident nhận p_user nhưng không ghi). Trigger ghi tự động:
--        - duc_ca_hien_tai (cột open_*): mo (báo sự cố), cap_nhat (sửa nội dung
--          khi đang mở), chuyen_ca (sự cố vắt ca sang dòng ca sau), dong (dòng ca
--          hết sự cố mở — kết thúc, hoặc chuyển ca lúc kết ca).
--        - duc_su_co_log: sua_sau_dong (sửa sự cố đã đóng), xoa.
--      Người = tài khoản đăng nhập (giống nhật ký tem T109). Sự cố trước khi
--      chạy migration này không có nhật ký — RPC vẫn ghép từ dữ liệu sẵn có.
--   2) RPC duc_su_co_lich_su(p_id_su_co) trả về mọi dữ liệu của sự cố để giao
--      diện dựng dòng thời gian.
--
-- Không sửa RPC sự cố nào. Chạy trên CẢ 2 project. Idempotent.
-- ============================================================================

-- 1) Bảng nhật ký -----------------------------------------------------------------
create table if not exists duc_su_co_nhat_ky (
  id          bigserial primary key,
  id_su_co    text not null,
  su_kien     text not null check (su_kien in ('mo', 'cap_nhat', 'chuyen_ca', 'dong', 'sua_sau_dong', 'xoa')),
  id_dong     text,
  ngay        date,
  ca          text,
  du_lieu     jsonb,                 -- loai, gio_phat_sinh, van_de, noi_dung_xu_ly, dam_nhiem tại thời điểm ghi
  thay_doi    jsonb,                 -- {cot: {cu, moi}}
  nguoi       text not null default '',
  nguoi_uid   uuid,
  nguon       text not null default '',
  thoi_diem   timestamptz not null default now()
);
create index if not exists duc_su_co_nhat_ky_id_idx on duc_su_co_nhat_ky (id_su_co, thoi_diem);
alter table duc_su_co_nhat_ky enable row level security;
drop policy if exists "authenticated read" on duc_su_co_nhat_ky;
create policy "authenticated read" on duc_su_co_nhat_ky for select to authenticated using (true);
revoke all on duc_su_co_nhat_ky from anon, authenticated;
grant select on duc_su_co_nhat_ky to authenticated;
revoke all on sequence duc_su_co_nhat_ky_id_seq from anon, authenticated;

-- Tên người đang đăng nhập (dùng chung cho các trigger nhật ký sự cố).
create or replace function duc_su_co_nguoi_hien_tai()
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare v text;
begin
  select coalesce(nullif(trim(r.full_name), ''), r.email, r.username) into v
  from user_roles r where r.user_id = auth.uid() limit 1;
  return coalesce(v, nullif(auth.jwt()->>'email', ''), case when auth.uid() is null then 'Hệ thống' else '' end);
end $$;
revoke execute on function duc_su_co_nguoi_hien_tai() from public, anon, authenticated;

-- 2) Trigger trên duc_ca_hien_tai (chỉ khi cột open_* đổi) -------------------------
create or replace function duc_su_co_nk_ca_hien_tai()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nguoi text := duc_su_co_nguoi_hien_tai();
  v_nguon text := coalesce(nullif(current_setting('request.path', true), ''), 'sql');
  v_old_id text := case when tg_op = 'UPDATE' then old.open_id_su_co end;
  v_dl jsonb;
  v_diff jsonb;
begin
  if new.open_id_su_co is not null then
    v_dl := jsonb_build_object('loai', new.open_loai_su_co, 'gio_phat_sinh', new.open_gio_phat_sinh, 'van_de', new.open_van_de,
      'noi_dung_xu_ly', new.open_noi_dung_xu_ly, 'dam_nhiem', new.open_dam_nhiem, 'ma_may', new.ma_may, 'ma_sp', new.ma_sp, 'so_khuon', new.so_khuon);
  end if;

  -- Dòng này vừa có sự cố mở (mới báo, hoặc sự cố vắt ca chuyển sang dòng ca sau).
  if new.open_id_su_co is not null and new.open_id_su_co is distinct from v_old_id then
    insert into duc_su_co_nhat_ky (id_su_co, su_kien, id_dong, ngay, ca, du_lieu, nguoi, nguoi_uid, nguon)
    values (new.open_id_su_co,
            case when exists (select 1 from duc_su_co_nhat_ky k where k.id_su_co = new.open_id_su_co and k.su_kien = 'mo')
                   or exists (select 1 from duc_su_co_log l where l.id_su_co = new.open_id_su_co)
                 then 'chuyen_ca' else 'mo' end,
            new.id_dong, new.ngay, new.ca, v_dl, v_nguoi, auth.uid(), v_nguon);
  end if;

  -- Sự cố đang mở bị sửa nội dung.
  if tg_op = 'UPDATE' and new.open_id_su_co is not null and new.open_id_su_co = v_old_id then
    select jsonb_object_agg(k, jsonb_build_object('cu', o, 'moi', n)) into v_diff
    from (values
      ('loai', to_jsonb(old.open_loai_su_co), to_jsonb(new.open_loai_su_co)),
      ('gio_phat_sinh', to_jsonb(old.open_gio_phat_sinh), to_jsonb(new.open_gio_phat_sinh)),
      ('van_de', to_jsonb(old.open_van_de), to_jsonb(new.open_van_de)),
      ('noi_dung_xu_ly', to_jsonb(old.open_noi_dung_xu_ly), to_jsonb(new.open_noi_dung_xu_ly)),
      ('dam_nhiem', to_jsonb(old.open_dam_nhiem), to_jsonb(new.open_dam_nhiem))
    ) t(k, o, n) where o is distinct from n;
    if v_diff is not null then
      insert into duc_su_co_nhat_ky (id_su_co, su_kien, id_dong, ngay, ca, du_lieu, thay_doi, nguoi, nguoi_uid, nguon)
      values (new.open_id_su_co, 'cap_nhat', new.id_dong, new.ngay, new.ca, v_dl, v_diff, v_nguoi, auth.uid(), v_nguon);
    end if;
  end if;

  -- Dòng này hết sự cố mở (kết thúc sự cố, hoặc kết ca chuyển sự cố sang ca sau).
  if v_old_id is not null and new.open_id_su_co is distinct from v_old_id then
    insert into duc_su_co_nhat_ky (id_su_co, su_kien, id_dong, ngay, ca, du_lieu, nguoi, nguoi_uid, nguon)
    values (v_old_id, 'dong', new.id_dong, new.ngay, new.ca,
            jsonb_build_object('loai', old.open_loai_su_co, 'gio_phat_sinh', old.open_gio_phat_sinh, 'van_de', old.open_van_de,
              'noi_dung_xu_ly', old.open_noi_dung_xu_ly, 'dam_nhiem', old.open_dam_nhiem),
            v_nguoi, auth.uid(), v_nguon);
  end if;
  return new;
exception when others then
  -- Nhật ký chỉ để tra cứu — lỗi ở đây không được chặn thao tác sự cố.
  raise warning 'duc_su_co_nk_ca_hien_tai: %', sqlerrm;
  return new;
end $$;
revoke execute on function duc_su_co_nk_ca_hien_tai() from public, anon, authenticated;

drop trigger if exists trg_duc_su_co_nk_ins on duc_ca_hien_tai;
create trigger trg_duc_su_co_nk_ins
  after insert on duc_ca_hien_tai
  for each row when (new.open_id_su_co is not null)
  execute function duc_su_co_nk_ca_hien_tai();
drop trigger if exists trg_duc_su_co_nk_upd on duc_ca_hien_tai;
create trigger trg_duc_su_co_nk_upd
  after update of open_id_su_co, open_loai_su_co, open_gio_phat_sinh, open_van_de, open_noi_dung_xu_ly, open_dam_nhiem on duc_ca_hien_tai
  for each row execute function duc_su_co_nk_ca_hien_tai();

-- 3) Trigger trên duc_su_co_log: sửa / xoá sự cố đã đóng ---------------------------
create or replace function duc_su_co_nk_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_diff jsonb;
  v_r duc_su_co_log;
begin
  if tg_op = 'DELETE' then v_r := old; else v_r := new; end if;
  if v_r.id_su_co is null then return null; end if;
  if tg_op = 'UPDATE' then
    select jsonb_object_agg(k, jsonb_build_object('cu', o, 'moi', n)) into v_diff
    from (values
      ('loai', to_jsonb(old.loai_su_co), to_jsonb(new.loai_su_co)),
      ('gio_phat_sinh', to_jsonb(old.gio_phat_sinh), to_jsonb(new.gio_phat_sinh)),
      ('gio_tro_lai', to_jsonb(old.gio_tro_lai), to_jsonb(new.gio_tro_lai)),
      ('van_de', to_jsonb(old.van_de), to_jsonb(new.van_de)),
      ('noi_dung_xu_ly', to_jsonb(old.noi_dung_xu_ly), to_jsonb(new.noi_dung_xu_ly)),
      ('dam_nhiem', to_jsonb(old.dam_nhiem), to_jsonb(new.dam_nhiem))
    ) t(k, o, n) where o is distinct from n;
    if v_diff is null then return null; end if;
  end if;
  insert into duc_su_co_nhat_ky (id_su_co, su_kien, ngay, ca, du_lieu, thay_doi, nguoi, nguoi_uid, nguon)
  values (v_r.id_su_co, case when tg_op = 'DELETE' then 'xoa' else 'sua_sau_dong' end, v_r.ngay, v_r.ca,
          to_jsonb(v_r), v_diff, duc_su_co_nguoi_hien_tai(), auth.uid(),
          coalesce(nullif(current_setting('request.path', true), ''), 'sql'));
  return null;
exception when others then
  raise warning 'duc_su_co_nk_log: %', sqlerrm;
  return null;
end $$;
revoke execute on function duc_su_co_nk_log() from public, anon, authenticated;

drop trigger if exists trg_duc_su_co_nk_log on duc_su_co_log;
create trigger trg_duc_su_co_nk_log
  after update or delete on duc_su_co_log
  for each row execute function duc_su_co_nk_log();

-- 4) RPC lấy toàn bộ lịch sử 1 sự cố -------------------------------------------------
create or replace function duc_su_co_lich_su(p_id_su_co text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_mo jsonb; v_log jsonb; v_sc record; v_phat_hien jsonb; v_ipqc jsonb; v_cp_ids text[];
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if coalesce(trim(p_id_su_co), '') = '' then return jsonb_build_object('ok', false, 'error', 'Thiếu mã sự cố'); end if;

  select to_jsonb(x) into v_mo from (
    select id_dong, ngay, ca, ma_may, ma_sp, ten_sp, so_khuon, open_loai_su_co loai, open_gio_phat_sinh gio_phat_sinh,
           open_van_de van_de, open_noi_dung_xu_ly noi_dung_xu_ly, open_dam_nhiem dam_nhiem
    from duc_ca_hien_tai where open_id_su_co = p_id_su_co order by row_seq desc nulls last limit 1) x;

  select coalesce(jsonb_agg(to_jsonb(l) order by l.gio_phat_sinh, l.thoi_diem_luu), '[]'::jsonb) into v_log
  from duc_su_co_log l where l.id_su_co = p_id_su_co;

  -- Thông tin gốc: phần log sớm nhất, hoặc dòng đang mở.
  select coalesce(l.ma_may, v_mo->>'ma_may') ma_may, coalesce(l.loai_su_co, v_mo->>'loai') loai,
         least(l.gio_phat_sinh, (v_mo->>'gio_phat_sinh')::timestamptz) gio_phat_sinh
  into v_sc
  from (select 1) d left join lateral (select * from duc_su_co_log where id_su_co = p_id_su_co order by gio_phat_sinh limit 1) l on true;
  if v_sc.ma_may is null then return jsonb_build_object('ok', false, 'error', 'Không tìm thấy sự cố ' || p_id_su_co); end if;

  -- F1 do IPQC phát hiện NG: lần kiểm NG cùng máy, sát giờ phát sinh.
  if left(coalesce(v_sc.loai, ''), 2) = 'F1' then
    select to_jsonb(c) into v_phat_hien from (
      select id_checkpoint, loai_kiem, nguoi_kiem, ket_qua, thoi_diem_kiem_thuc_te, checklist_json, anh_bang_chung_url, ghi_chu
      from duc_ipqc_checkpoint
      where ma_may = v_sc.ma_may and trang_thai = 'da_kiem' and ket_qua <> 'OK'
        and thoi_diem_kiem_thuc_te between v_sc.gio_phat_sinh - interval '3 minutes' and v_sc.gio_phat_sinh + interval '3 minutes'
      order by abs(extract(epoch from thoi_diem_kiem_thuc_te - v_sc.gio_phat_sinh)) limit 1) c;
  end if;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.thoi_diem_kiem_thuc_te nulls last, c.thoi_diem_tao), '[]'::jsonb),
         array_agg(c.id_checkpoint)
  into v_ipqc, v_cp_ids
  from (select id_checkpoint, loai_kiem, trang_thai, nguoi_kiem, ket_qua, thoi_diem_tao, thoi_diem_kiem_thuc_te,
               checklist_json, anh_bang_chung_url, ghi_chu
        from duc_ipqc_checkpoint where id_su_co_goc = p_id_su_co) c;

  return jsonb_build_object('ok', true,
    'id_su_co', p_id_su_co,
    'dang_mo', v_mo,
    'log', v_log,
    'phat_hien_ipqc', v_phat_hien,
    'ipqc', v_ipqc,
    'nhat_ky', (select coalesce(jsonb_agg(to_jsonb(k) order by k.thoi_diem, k.id), '[]'::jsonb) from duc_su_co_nhat_ky k where k.id_su_co = p_id_su_co),
    'anh', (select coalesce(jsonb_agg(jsonb_build_object('loai', a.loai, 'url', a.url, 'nguoi', a.nguoi, 'thoi_diem', a.thoi_diem) order by a.thoi_diem, a.id), '[]'::jsonb)
            from duc_su_co_anh a where a.id_su_co = p_id_su_co),
    'to_khuon', (select to_jsonb(x) from duc_khuon_xu_ly_bat_thuong x where x.id_su_co = p_id_su_co),
    'linh_kien', (select coalesce(jsonb_agg(jsonb_build_object('thoi_diem', g.thoi_diem, 'loai', g.loai, 'ma_lk', g.ma_lk, 'ten_lk', g.ten_lk,
                    'so_luong', g.so_luong, 'ma_khuon', g.ma_khuon, 'vi_tri', g.vi_tri, 'muc_dich', g.muc_dich, 'ket_qua_thao', g.ket_qua_thao,
                    'nguoi', g.nguoi, 'ghi_chu', g.ghi_chu) order by g.thoi_diem, g.id), '[]'::jsonb)
                  from khuon_lk_giao_dich g where g.id_su_co = p_id_su_co),
    'tiep_tuc', (select coalesce(jsonb_agg(jsonb_build_object('request_code', r.request_code, 'checkpoint_id', r.checkpoint_id,
                    'requester_name', r.requester_name, 'reason_type', r.reason_type, 'reason_detail', r.reason_detail,
                    'treatment_content', r.treatment_content, 'status', r.status, 'created_at', r.created_at,
                    'allowed_until', r.allowed_until, 'allowed_qty', r.allowed_qty,
                    'audit', (select coalesce(jsonb_agg(jsonb_build_object('action', a.action, 'actor_name', a.actor_name, 'detail', a.detail,
                                'created_at', a.created_at) order by a.created_at), '[]'::jsonb)
                              from duc_ipqc_continue_audit a where a.request_id = r.id)) order by r.created_at), '[]'::jsonb)
                 from duc_ipqc_continue_request r
                 where r.checkpoint_id = any(coalesce(v_cp_ids, array[]::text[]) || coalesce(array[v_phat_hien->>'id_checkpoint'], array[]::text[])))
  );
end $$;
revoke execute on function duc_su_co_lich_su(text) from public, anon;
grant execute on function duc_su_co_lich_su(text) to authenticated;
