-- ============================================================================
-- Phase T166 — Bảng điều khiển Bavia: Tự động hiển thị các Line và Mã SP đang làm dở
--
-- Vấn đề trước đây:
-- cd_tram_hien_tai gắn chặt theo (ngày, ca). Khi mở bảng điều khiển Bavia ở ca mới,
-- nếu chưa có ai bấm "+ Mở Line" hoặc "Nạp KHSX tuần" thì danh sách Line trống trơn
-- ("Chưa mở Line nào trong ca này"), mặc dù thực tế tại xưởng và trên hệ thống
-- các Line vẫn đang bavia dở các mã SP (tem Đúc nguồn bavia_line_nguon còn tồn
-- duc_tem.so_luong > 0 hoặc đang chạy từ ca trước chưa xong).
-- Người dùng phải tự bấm mở lại từng Line và nếu chọn nhầm mã SP thì bị báo lỗi kẹt tem dở.
--
-- Giải pháp:
-- Khi bavia_du_lieu(p_ngay, p_ca) được gọi (khi mở hoặc tải lại bavia-dashboard.html):
-- Nếu ca này CHƯA KẾT CA (not exists bavia_ket_ca):
--   1) Quét các Line Bavia đang có tem Đúc dở (bavia_line_nguon có bo_luc is null
--      và duc_tem.so_luong > 0): nếu Line đó chưa có trong ca đích (p_ngay, p_ca)
--      thì tự động tạo dòng cd_tram_hien_tai với mã SP đó (sản lượng OK/NG = 0,
--      kế thừa người thao tác / kiểm tra / phun bi từ ca gần nhất nếu có).
--   2) Quét các Line hoạt động ở ca gần nhất của Bavia (trong 3 ngày qua):
--      nếu Line đó chưa có trong ca đích và không có tem dở mã khác, tự động kế
--      thừa sang ca này để tiếp tục làm.
--
-- Frontend bavia-dashboard.html:
--   - Hiển thị badge cảnh báo số lượng dở trên thẻ Line ("Dở X pcs").
--   - Ưu tiên xếp các Line có hàng dở lên đầu danh sách.
--   - Mặc định tự động chọn Line đang có hàng dở khi mở trang.
--
-- An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create or replace function public.bavia_du_lieu(p_ngay date, p_ca text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_res jsonb;
  v_ket_ca boolean;
  r record;
  v_prev record;
  v_id text;
  v_user text := coalesce(duc_su_co_nguoi_hien_tai(), 'Hệ thống');
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập');
  end if;

  if p_ngay is null or coalesce(p_ca, '') not in ('Ca ngày', 'Ca đêm', 'Ca 1', 'Ca 2') then
    return jsonb_build_object('ok', false, 'error', 'Ngày / ca không hợp lệ');
  end if;

  v_ket_ca := exists (select 1 from bavia_ket_ca where ngay = p_ngay and ca = p_ca);

  -- Nếu ca này CHƯA kết ca: tự động mở/kế thừa các Line đang làm dở
  if not v_ket_ca then
    -- 1) Các Line có tem Đúc đang dùng dở (bavia_line_nguon có bo_luc is null và duc_tem.so_luong > 0)
    for r in
      select n.ten_line, n.ma_sp, sum(t.so_luong) as con_do
      from bavia_line_nguon n
      join duc_tem t on t.tag_no = n.tag_no
      join master_machines m on m.ma_may = n.ten_line and m.bo_phan = 'Bavia'
      where n.bo_luc is null and t.so_luong > 0
      group by n.ten_line, n.ma_sp
    loop
      if not exists (
        select 1 from cd_tram_hien_tai
        where cong_doan = 'Bavia' and ngay = p_ngay and ca = p_ca and ten_tram = r.ten_line
      ) then
        -- Lấy thông tin người/KH từ ca gần nhất của line đó nếu có
        select ten_sp, kh_ca, nguoi_thao_tac, nguoi_kiem_tra, nguoi_phun_bi
        into v_prev
        from cd_tram_hien_tai
        where cong_doan = 'Bavia' and ten_tram = r.ten_line
        order by ngay desc, (case when ca = 'Ca đêm' then 2 else 1 end) desc, last_updated_at desc
        limit 1;

        v_id := duc_normalize_name('Bavia') || '_' || to_char(p_ngay, 'DDMMYYYY') || '_'
                || duc_normalize_name(p_ca) || '_' || duc_normalize_name(r.ten_line);

        insert into cd_tram_hien_tai (
          id_tram, ngay, ca, cong_doan, ten_tram, ma_sp, ten_sp, kh_ca,
          nguoi_thao_tac, nguoi_kiem_tra, nguoi_phun_bi, so_luong_ok, so_luong_ng, version,
          last_updated_by, last_updated_at
        ) values (
          v_id, p_ngay, p_ca, 'Bavia', r.ten_line, r.ma_sp,
          coalesce(nullif(v_prev.ten_sp, ''), (bavia_thong_tin_ma(r.ma_sp))->>'ten_sp', ''),
          v_prev.kh_ca,
          coalesce(v_prev.nguoi_thao_tac, ''),
          v_prev.nguoi_kiem_tra,
          v_prev.nguoi_phun_bi,
          0, 0, 1, v_user, now()
        ) on conflict (id_tram) do nothing;
      end if;
    end loop;

    -- 2) Các Line từ ca gần nhất của Bavia (trong vòng 3 ngày) nếu line đó chưa có trong ca hiện tại
    -- và không có tem dở của mã khác
    for r in
      select distinct on (c.ten_tram)
        c.ten_tram as ten_line, c.ma_sp, c.ten_sp, c.kh_ca, c.nguoi_thao_tac, c.nguoi_kiem_tra, c.nguoi_phun_bi
      from cd_tram_hien_tai c
      join master_machines m on m.ma_may = c.ten_tram and m.bo_phan = 'Bavia'
      where c.cong_doan = 'Bavia'
        and not (c.ngay = p_ngay and c.ca = p_ca)
        and c.ngay >= p_ngay - 3
        and not exists (
          select 1 from cd_tram_hien_tai cur
          where cur.cong_doan = 'Bavia' and cur.ngay = p_ngay and cur.ca = p_ca and cur.ten_tram = c.ten_tram
        )
      order by c.ten_tram, c.ngay desc, (case when c.ca = 'Ca đêm' then 2 else 1 end) desc, c.last_updated_at desc
    loop
      if not exists (
        select 1 from bavia_line_nguon n
        join duc_tem t on t.tag_no = n.tag_no
        where n.ten_line = r.ten_line and n.bo_luc is null and t.so_luong > 0 and n.ma_sp <> r.ma_sp
      ) then
        v_id := duc_normalize_name('Bavia') || '_' || to_char(p_ngay, 'DDMMYYYY') || '_'
                || duc_normalize_name(p_ca) || '_' || duc_normalize_name(r.ten_line);

        insert into cd_tram_hien_tai (
          id_tram, ngay, ca, cong_doan, ten_tram, ma_sp, ten_sp, kh_ca,
          nguoi_thao_tac, nguoi_kiem_tra, nguoi_phun_bi, so_luong_ok, so_luong_ng, version,
          last_updated_by, last_updated_at
        ) values (
          v_id, p_ngay, p_ca, 'Bavia', r.ten_line, r.ma_sp, coalesce(r.ten_sp, ''),
          r.kh_ca, coalesce(r.nguoi_thao_tac, ''), r.nguoi_kiem_tra, r.nguoi_phun_bi,
          0, 0, 1, v_user, now()
        ) on conflict (id_tram) do nothing;
      end if;
    end loop;
  end if;

  -- Trả về gói dữ liệu đầy đủ cho frontend
  select jsonb_build_object(
    'danh_muc_line', (select coalesce(jsonb_agg(ma_may order by ma_may), '[]'::jsonb) from master_machines where bo_phan = 'Bavia'),
    'ket_ca', (select to_jsonb(k) from bavia_ket_ca k where k.ngay = p_ngay and k.ca = p_ca),
    'lines', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id_tram', l.id_tram, 'ten_line', l.ten_tram, 'ma_sp', l.ma_sp, 'ten_sp', l.ten_sp, 'kh_ca', l.kh_ca,
        'nguoi_thao_tac', l.nguoi_thao_tac, 'nguoi_kiem_tra', l.nguoi_kiem_tra, 'nguoi_phun_bi', l.nguoi_phun_bi,
        'so_luong_ok', l.so_luong_ok, 'so_luong_ng', l.so_luong_ng,
        'info', bavia_thong_tin_ma(l.ma_sp),
        'nguon', (select coalesce(jsonb_agg(jsonb_build_object(
              'id', n.id, 'tag_no', n.tag_no, 'sl_khai_bao', n.sl_khai_bao, 'con', t.so_luong, 'thoi_diem', n.thoi_diem,
              'ngay_duc', t.ngay, 'may', coalesce(t.may_tt, t.may_duc_chi_thi), 'nguoi_duc', t.nguoi_tt,
              'so_khuon', coalesce(t.so_khuon_tt, t.so_khuon)) order by n.thoi_diem, n.id), '[]'::jsonb)
            from bavia_line_nguon n join duc_tem t on t.tag_no = n.tag_no
            where n.ten_line = l.ten_tram and n.bo_luc is null
              and (t.so_luong > 0 or n.thoi_diem > now() - interval '12 hours')),
        'thung', (select coalesce(jsonb_agg(jsonb_build_object(
              'tag_tp', b.tag_tp, 'so_luong', b.so_luong, 'dang', b.dang, 'nguoi_lam', b.nguoi_lam, 'nguoi_kiem', b.nguoi_kiem,
              'nguoi_phun_bi', b.nguoi_phun_bi, 'thoi_diem', b.thoi_diem,
              'nguon', (select coalesce(jsonb_agg(jsonb_build_object('tag_no', s.tag_no_nguon, 'so_luong_lay', s.so_luong_lay)), '[]'::jsonb)
                        from cd_tem_nguon s where s.tag_no_moi = b.tag_tp)) order by b.thoi_diem desc), '[]'::jsonb)
            from bavia_thung b where b.id_tram = l.id_tram),
        'ng', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'tag_no', g.tag_no, 'loai', g.loai_ng, 'ghi_chu', g.ghi_chu,
              'so_luong', g.so_luong, 'nguoi', g.nguoi, 'ngay_gio', g.ngay_gio) order by g.ngay_gio desc), '[]'::jsonb)
            from cd_ng_khai_bao g where g.id_tram = l.id_tram),
        'test', (select coalesce(jsonb_agg(to_jsonb(h) order by h.thoi_diem desc), '[]'::jsonb)
            from bavia_hang_test h where h.id_tram = l.id_tram or (h.ten_line = l.ten_tram and h.ket_thuc_luc is null))
      ) order by l.ten_tram), '[]'::jsonb)
      from cd_tram_hien_tai l
      where l.cong_doan = 'Bavia' and l.ngay = p_ngay and l.ca = p_ca
    ),
    'cho', (select coalesce(jsonb_agg(jsonb_build_object('ma_sp', x.ma_sp, 'so_tem', x.so_tem, 'pcs', x.pcs,
              'tai_bavia', x.tai_bavia, 'ngay_tu', x.ngay_tu, 'ngay_den', x.ngay_den, 'may', x.may) order by x.ma_sp), '[]'::jsonb)
      from (
        select t.ma_sp, count(*) so_tem, sum(t.so_luong) pcs, count(*) filter (where v.vi_tri_hien_tai = 'Bavia') tai_bavia,
          min(t.ngay) ngay_tu, max(t.ngay) ngay_den, string_agg(distinct coalesce(t.may_tt, t.may_duc_chi_thi), ', ') may
        from duc_tem t
        left join cd_v_vi_tri_hien_tai v on v.tag_no = t.tag_no
        where t.tag_no not like 'TP%' and t.so_luong > 0
          and coalesce(t.trang_thai, '') not in ('Chờ sản xuất', 'NG chờ sửa')
          and t.ma_sp in (select ma_sp from cd_tram_hien_tai where cong_doan = 'Bavia' and ngay = p_ngay and ca = p_ca)
          and v.vi_tri_hien_tai = 'Bavia'
          and not exists (select 1 from bavia_line_nguon n where n.tag_no = t.tag_no and n.bo_luc is null)
        group by t.ma_sp
      ) x)
  ) into v_res;

  return v_res;
end;
$$;

revoke execute on function public.bavia_du_lieu(date, text) from public, anon;
grant execute on function public.bavia_du_lieu(date, text) to authenticated;
