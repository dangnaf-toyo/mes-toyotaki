-- T366: Chặn BỎ QUA CÔNG ĐOẠN khi Chuyển công đoạn.
-- Tem (tem Đúc gốc, không phải TP/GC) đã được chuyển TỚI công đoạn X mà X chưa làm gì
-- với tem đó (sau lúc nhận) thì không cho chuyển tiếp sang công đoạn kế tiếp.
-- "Đã làm" ở X:
--   Bavia    : bavia_thung / bavia_xu_ly_nguon / bavia_xh_ghi_nhan / tách tem (duc_tem_tach) / khai báo line (bavia_line_nguon)
--   Gia Công : gc_tem_buoc (không bỏ)
--   mọi CĐ   : đang khai báo nguồn đang dùng ở X (duc_tem.cong_doan_dang_dung = X)
-- Không áp dụng cho: Đúc, OQC, Nhập kho, Xuất hàng; tem không có dòng nhận trực tiếp
-- (tem con tạo tại công đoạn đó) cũng không chặn.
-- Kiểm trong cd_kiem_xe_bavia (màn Chuyển công đoạn gọi lúc quét + trước khi gửi, cd_ghi_chuyen_cong_doan cũng gọi).

create or replace function public.cd_kiem_bo_qua_cong_doan(p_tag_no text)
returns text
language plpgsql stable security definer
set search_path to 'public'
as $$
declare
  v_tag text := upper(trim(coalesce(p_tag_no, '')));
  v_loc text;
  v_nhan timestamptz;
  v_lam boolean := false;
begin
  if v_tag = '' or v_tag ~ '^(TP|GC)' then return null; end if;
  v_loc := cd_vi_tri_tem(v_tag);
  if v_loc is null or v_loc in ('Đúc', 'OQC', 'Nhập kho', 'Xuất hàng') then return null; end if;

  select max(thoi_gian_chuyen) into v_nhan from cd_chuyen_cong_doan_log
  where tag_no = v_tag and cong_doan_nhan = v_loc
    and coalesce(trang_thai_xac_nhan, '') <> 'Đã từ chối';
  if v_nhan is null then return null; end if;

  v_lam := exists (select 1 from duc_tem where tag_no = v_tag and cong_doan_dang_dung = v_loc);

  if not v_lam and v_loc = 'Bavia' then
    v_lam := exists (select 1 from bavia_thung where tag_tp = v_tag and thoi_diem >= v_nhan)
      or exists (select 1 from duc_tem_tach where tag_no_cha = v_tag and thoi_diem >= v_nhan)
      or exists (select 1 from bavia_line_nguon where tag_no = v_tag and thoi_diem >= v_nhan)
      or exists (select 1 from bavia_xh_ghi_nhan where tag_no = v_tag and thoi_diem >= v_nhan and not coalesce(da_huy, false))
      or exists (select 1 from bavia_xu_ly_nguon n join bavia_xu_ly x on x.id = n.id_xu_ly
                 where n.tag_no_nguon = v_tag and x.thoi_diem >= v_nhan);
  elsif not v_lam and v_loc = 'Gia Công' then
    v_lam := exists (select 1 from gc_tem_buoc where tag_no = v_tag and bo_luc is null and bat_dau >= v_nhan);
  end if;

  if v_lam then return null; end if;
  return 'Lỗi bỏ qua công đoạn. Bạn cần hoàn thành kiện hàng này ở công đoạn ' || v_loc
    || ' trước khi chuyển sang công đoạn kế tiếp';
end $$;

revoke execute on function public.cd_kiem_bo_qua_cong_doan(text) from public, anon;
grant execute on function public.cd_kiem_bo_qua_cong_doan(text) to authenticated;

create or replace function public.cd_kiem_xe_bavia(p_tag_no text, p_sl numeric default null::numeric)
returns text
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare
  v_tag text := upper(trim(coalesce(p_tag_no, '')));
  v_tem duc_tem%rowtype;
  v_info jsonb;
  v_loi text;
begin
  if v_tag = '' or v_tag ~ '^(TP|GC)' then return null; end if;
  if cd_vi_tri_tem(v_tag) = 'Gia Công' and exists (select 1 from bavia_thung where tag_tp = v_tag and dang = 3) then -- T340
    return 'Xe ' || v_tag || ' phải gia công ở Bảng điều khiển Gia công, đầy thùng quét tem GC vào ô QR máy. Không chuyển nguyên xe.' /* T365 */;
  end if;
  v_loi := cd_kiem_bo_qua_cong_doan(v_tag); -- T366
  if v_loi is not null then return v_loi; end if;
  if cd_vi_tri_tem(v_tag) is distinct from 'Bavia' then return null; end if;
  select * into v_tem from duc_tem where tag_no = v_tag;
  if not found then return null; end if;
  if exists (select 1 from bavia_thung where tag_tp = v_tag and dang = 3) then
    if p_sl is not null and p_sl <> coalesce(v_tem.so_luong, 0) then
      return 'Xe ' || v_tag || ' chuyển nguyên xe: phải chuyển đủ ' || coalesce(v_tem.so_luong, 0) || ' pcs, không tách.';
    end if;
    return null;
  end if;
  v_info := bavia_thong_tin_ma(v_tem.ma_sp);
  if coalesce((v_info->>'ok')::boolean, false) and coalesce((v_info->>'nguyen_xe')::boolean, false) then
    return 'Xe ' || v_tag || ' chưa bấm "Xong xe" ở Bavia. Bấm Xong xe rồi quét lại.';
  end if;
  return null;
end $function$;
