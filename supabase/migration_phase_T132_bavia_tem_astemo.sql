-- ============================================================================
-- T132: Tem xuất hàng Bavia — Astemo dùng PHIẾU QUẢN LÝ LÔ riêng (ảnh mẫu
-- Picture/PHIẾU QUẢN LÝ LÔ ASTEMO.png): mau = 'astemo'. Dữ liệu in thêm Ca đúc
-- của từng tem nguồn (bavia_xh_ca_tem).
-- ============================================================================
-- Ca đúc của 1 tem: ca (lịch sử đã kết hoặc ca đang chạy) có khung giờ chứa mốc
-- tem — cùng quy tắc duc_ls_dieu_chinh_tem (mốc trong khung ca, +2h sau giờ kết thúc).
create or replace function bavia_xh_ca_tem(p_tag text)
returns text
language sql stable security definer set search_path = public
as $$
  with t as (select may_tt, ma_sp, coalesce(ngay_gio_ghi_nhan, ngay_gio_in) moc from duc_tem where tag_no = p_tag)
  select x.ca from t cross join lateral (
    select ls.ca, (sw.w->>'start')::timestamptz st from duc_lich_su_san_xuat ls
      cross join lateral (select duc_get_shift_window(ls.ngay, ls.phuong_an_ca, ls.ca) w) sw
    where ls.ma_may = t.may_tt and ls.ma_sp = t.ma_sp and sw.w is not null
      and t.moc >= (sw.w->>'start')::timestamptz and t.moc < (sw.w->>'end')::timestamptz + interval '2 hours'
    union all
    select c.ca, (sw.w->>'start')::timestamptz from duc_ca_hien_tai c
      cross join lateral (select duc_get_shift_window(c.ngay, c.phuong_an_ca, c.ca) w) sw
    where c.ma_may = t.may_tt and c.ma_sp = t.ma_sp and sw.w is not null
      and t.moc >= (sw.w->>'start')::timestamptz and t.moc < (sw.w->>'end')::timestamptz + interval '2 hours'
  ) x order by x.st desc limit 1;
$$;
revoke execute on function bavia_xh_ca_tem(text) from public, anon;
grant execute on function bavia_xh_ca_tem(text) to authenticated;

create or replace function bavia_xh_thong_tin_ma(p_ma_sp text)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  p master_products%rowtype;
  v_steps text[];
  v_i int;
  v_sau text;
  v_sl numeric;
  v_mau text;
begin
  select * into p from master_products where ma_sp = trim(p_ma_sp);
  if not found then return jsonb_build_object('ok', false, 'error', 'Mã SP không có trong danh mục: ' || coalesce(p_ma_sp, '')); end if;

  if coalesce(p.ten_khach_hang, '') !~* '(FCC|ASTEMO|SOJI|MIKASA|COSMOS)' then
    return jsonb_build_object('ok', false, 'ma_sp', p.ma_sp, 'error',
      'Mã ' || p.ma_sp || ' (khách hàng: ' || coalesce(nullif(p.ten_khach_hang, ''), 'chưa khai báo') ||
      ') không thuộc FCC / Astemo / Soji / Mikasa / Cosmos — không in tem xuất hàng tại Bavia');
  end if;

  select array_agg(trim(s) order by ord) into v_steps
  from unnest(string_to_array(coalesce(p.quy_trinh_cong_doan, ''), ',')) with ordinality as u(s, ord)
  where trim(s) <> '';
  v_i := array_position(v_steps, 'Bavia');
  if v_i is null then
    return jsonb_build_object('ok', false, 'ma_sp', p.ma_sp, 'error', 'Lưu trình của mã ' || p.ma_sp || ' không có công đoạn Bavia');
  end if;
  v_sau := v_steps[v_i + 1];
  if v_sau is not null and v_sau not in ('OQC', 'Nhập kho', 'Xuất hàng') then
    return jsonb_build_object('ok', false, 'ma_sp', p.ma_sp, 'error',
      'Mã ' || p.ma_sp || ' còn công đoạn "' || v_sau || '" sau Bavia — tem xuất hàng không in tại Bavia');
  end if;

  v_sl := nullif(p.sl_thung_cong_doan ->> 'Bavia', '')::numeric;
  if coalesce(v_sl, 0) <= 0 then
    return jsonb_build_object('ok', false, 'ma_sp', p.ma_sp, 'error',
      'Mã ' || p.ma_sp || ' chưa khai báo SL/thùng cho công đoạn Bavia (Danh mục SP → SL/thùng theo công đoạn)');
  end if;

  v_mau := case when p.ten_khach_hang ~* 'FCC' then 'fcc' when p.ten_khach_hang ~* 'ASTEMO' then 'astemo' else 'chung' end;
  return jsonb_build_object('ok', true, 'ma_sp', p.ma_sp, 'ten_sp', p.ten_sp,
    'ten_khach_hang', p.ten_khach_hang, 'ma_sp_khach_hang', p.ma_sp_khach_hang,
    'nguyen_lieu', p.nguyen_lieu, 'sl_thung', v_sl, 'mau', v_mau, 'buoc_sau', v_sau);
end $$;
revoke execute on function bavia_xh_thong_tin_ma(text) from public, anon;
grant execute on function bavia_xh_thong_tin_ma(text) to authenticated;

create or replace function bavia_xh_du_lieu_in(p_tags text[])
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'tag_no', t.tag_no, 'ma_sp', t.ma_sp, 'ten_sp', t.ten_sp, 'so_luong', t.so_luong_tt,
      'ma_sp_khach_hang', coalesce(t.ma_sp_khach_hang, p.ma_sp_khach_hang),
      'ten_khach_hang', coalesce(t.ten_khach_hang, p.ten_khach_hang),
      'nguyen_lieu', t.nguyen_lieu, 'lot', t.lot, 'ngay', t.ngay, 'so_khuon', t.so_khuon,
      'may', t.may_duc_chi_thi, 'nguoi', t.nguoi_tt, 'luc', t.ngay_gio_ghi_nhan,
      'thung_le', t.ghi_chu like '%thùng lẻ%',
      'mau', case when coalesce(t.ten_khach_hang, p.ten_khach_hang) ~* 'FCC' then 'fcc'
                   when coalesce(t.ten_khach_hang, p.ten_khach_hang) ~* 'ASTEMO' then 'astemo' else 'chung' end,
      'nguon', (select coalesce(jsonb_agg(jsonb_build_object('tag_no', s.tag_no, 'so_luong_lay', n.so_luong_lay,
                  'ngay', s.ngay, 'may', coalesce(s.may_tt, s.may_duc_chi_thi), 'nguoi', s.nguoi_tt, 'so_khuon', s.so_khuon,
                  'ngay_gio_in', s.ngay_gio_in, 'ca', bavia_xh_ca_tem(s.tag_no)) order by s.ngay, s.tag_no), '[]'::jsonb)
                from cd_tem_nguon n join duc_tem s on s.tag_no = n.tag_no_nguon where n.tag_no_moi = t.tag_no),
      -- NG Bavia: tính cho thùng ĐẦU TIÊN lấy từ mỗi lần quét.
      'ng_bavia', (select coalesce(sum(g.sl_ng), 0) from bavia_xh_thung_nguon tn join bavia_xh_ghi_nhan g on g.id = tn.id_ghi_nhan
                   where tn.tag_tp = t.tag_no
                     and tn.tag_tp = (select min(x.tag_tp) from bavia_xh_thung_nguon x where x.id_ghi_nhan = g.id)),
      'nguoi_bavia', (select string_agg(distinct g.nguoi, ', ') from bavia_xh_thung_nguon tn join bavia_xh_ghi_nhan g on g.id = tn.id_ghi_nhan
                      where tn.tag_tp = t.tag_no)
    ) order by t.tag_no), '[]'::jsonb)
  from duc_tem t left join master_products p on p.ma_sp = t.ma_sp
  where t.tag_no = any(p_tags);
$$;
revoke execute on function bavia_xh_du_lieu_in(text[]) from public, anon;
grant execute on function bavia_xh_du_lieu_in(text[]) to authenticated;
