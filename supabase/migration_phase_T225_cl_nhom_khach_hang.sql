-- ============================================================================
-- T225: Nhóm khách hàng của Dashboard KPI chất lượng — 1 nguồn duy nhất
--
-- Dashboard KPI chất lượng (chatluong-supabase.html, tab "Theo khách hàng") và
-- P-Chart NG Bavia (shared/bavia-ng-dash.js) cùng đọc bảng này:
--   ma_nhom      : khoá ngắn lưu trong cl_theo_khach_hang.khach_hang / cl_targets.ten
--                  (giữ nguyên để comment cũ customer_internal_FCC… và Sheet cũ vẫn khớp)
--   ten_hien_thi : tên hiển thị trên dashboard = tên đầy đủ trong Danh mục sản phẩm
--   ten_day_du   : các master_products.ten_khach_hang thuộc nhóm (rỗng = nhóm KHAC:
--                  mọi khách không thuộc nhóm nào)
--   bi_danh      : các cách viết khác có thể gặp trong file Google Sheet / Excel hàng tháng
--
-- Trigger chuẩn hoá: mỗi lần nạp cl_theo_khach_hang / cl_targets (KhachHang), tên khách
-- được đổi về ma_nhom (so khớp không phân biệt hoa thường, bỏ khoảng trắng thừa với
-- ma_nhom, ten_hien_thi, ten_day_du, bi_danh). Tên lạ → BÁO LỖI, không nạp — tránh
-- tháng sau Sheet ghi "Astemo" mà dashboard lặng lẽ mất số liệu.
-- Thêm khách / đổi tên: chỉ cần sửa bảng này (xem cuối file).
-- ============================================================================

create table if not exists cl_nhom_khach_hang (
  ma_nhom      text primary key,
  ten_hien_thi text not null,
  ten_day_du   text[] not null default '{}',
  bi_danh      text[] not null default '{}',
  thu_tu       int not null default 0
);
alter table cl_nhom_khach_hang enable row level security;
drop policy if exists "auth read" on cl_nhom_khach_hang;
create policy "auth read" on cl_nhom_khach_hang for select to authenticated using (true);
revoke all on cl_nhom_khach_hang from anon;
grant select on cl_nhom_khach_hang to authenticated;

insert into cl_nhom_khach_hang (ma_nhom, ten_hien_thi, ten_day_du, bi_danh, thu_tu) values
  ('Hitachi (ASTEMO)', 'ASTEMO PHU THO CO., LTD.', '{"ASTEMO PHU THO CO., LTD."}', '{"Hitachi","Astemo","Hitachi Astemo","Hitachi (Astemo)","Astemo Phú Thọ"}', 1),
  ('FCC',              'FCC (VIETNAM) CO.,LTD',    '{"FCC (VIETNAM) CO.,LTD"}',    '{"FCC (VIETNAM).,LTD","FCC Vietnam","FCC (Vietnam)"}', 2),
  ('FOMECO',           'FOMECO',                   '{"FOMECO"}',                   '{}', 3),
  ('EXEDY',            'EXEDY Vietnam Co.,Ltd',    '{"EXEDY Vietnam Co.,Ltd"}',    '{"EXEDY Vietnam"}', 4),
  ('KHAC',             'Khách hàng khác',          '{}',                           '{"KHÁC","Khác","Khach hang khac","Khách hàng khác","Other","Others"}', 5)
on conflict (ma_nhom) do nothing;

-- Tên (bất kỳ cách viết đã khai) → ma_nhom; null nếu không nhận ra
create or replace function cl_chuan_hoa_khach_hang(p_ten text)
returns text language sql stable set search_path to 'public' as $$
  select n.ma_nhom from cl_nhom_khach_hang n
  where lower(btrim(p_ten)) = any (
    select lower(btrim(x)) from unnest(array[n.ma_nhom, n.ten_hien_thi] || n.ten_day_du || n.bi_danh) x)
  order by n.thu_tu limit 1
$$;

create or replace function cl_trg_chuan_hoa_khach_hang()
returns trigger language plpgsql set search_path to 'public' as $$
declare v_goc text; v_ma text; v_ds text;
begin
  if tg_table_name = 'cl_targets' then
    if new.loai is distinct from 'KhachHang' then return new; end if;
    v_goc := new.ten;
  else
    v_goc := new.khach_hang;
  end if;
  v_ma := cl_chuan_hoa_khach_hang(v_goc);
  if v_ma is null then
    select string_agg(ma_nhom || ' (' || ten_hien_thi || ')', ', ' order by thu_tu) into v_ds from cl_nhom_khach_hang;
    raise exception 'Tên khách hàng "%" không có trong bảng nhóm khách hàng (cl_nhom_khach_hang). Tên hợp lệ: %. Nếu là khách mới / đổi tên: thêm vào cột bi_danh hoặc thêm nhóm mới rồi nạp lại.', v_goc, v_ds;
  end if;
  if tg_table_name = 'cl_targets' then new.ten := v_ma; else new.khach_hang := v_ma; end if;
  return new;
end $$;

drop trigger if exists trg_chuan_hoa_kh on cl_theo_khach_hang;
create trigger trg_chuan_hoa_kh before insert or update on cl_theo_khach_hang
  for each row execute function cl_trg_chuan_hoa_khach_hang();
drop trigger if exists trg_chuan_hoa_kh on cl_targets;
create trigger trg_chuan_hoa_kh before insert or update on cl_targets
  for each row execute function cl_trg_chuan_hoa_khach_hang();

-- ----------------------------------------------------------------------------
-- Ví dụ bảo trì:
--   Sheet tháng mới ghi "Hitachi Astemo Phu Tho":
--     update cl_nhom_khach_hang set bi_danh = bi_danh || 'Hitachi Astemo Phu Tho' where ma_nhom = 'Hitachi (ASTEMO)';
--   Danh mục sản phẩm đổi tên khách FCC:
--     update cl_nhom_khach_hang set ten_hien_thi = '<tên mới>', ten_day_du = ten_day_du || '<tên mới>' where ma_nhom = 'FCC';
--   Thêm nhóm khách chính mới (dashboard tự hiện thêm 1 hàng, cần có số liệu trong cl_theo_khach_hang):
--     insert into cl_nhom_khach_hang values ('OKAYA', 'OKAYA (VIET NAM) CO.,LTD', '{"OKAYA (VIET NAM) CO.,LTD"}', '{"Okaya"}', 6);
-- ----------------------------------------------------------------------------
