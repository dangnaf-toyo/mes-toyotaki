-- ============================================================================
-- Phase T287b — Truy xuất nguồn gốc: ca + khoảng giờ đúc thực của tem đúc.
--
-- Tem đúc (TKD) chỉ có giờ in tem (hoặc giờ ghi nhận Kanban) = lúc ĐẦY THÙNG,
-- còn "ngay" là ngày lịch lúc in → tem in 01:13 ngày 15/11 thực ra thuộc
-- Ca đêm 14/11. Hàm trả cho từng tem:
--   moc    = coalesce(ngay_gio_ghi_nhan, ngay_gio_in)  (lúc đầy thùng)
--   tu     = max(đầu ca, mốc tem trước cùng máy + mã SP) (bắt đầu đúc thùng)
--   ngay_ca, ca = ca sản xuất (theo báo cáo kết ca nếu kết trong ≤2h sau giờ
--                 kết ca chuẩn, ngược lại theo khung giờ ca chuẩn)
-- Chỉ đọc, security invoker (duc_tem, duc_bao_cao_ca đều đọc công khai).
-- An toàn chạy lại nhiều lần.
-- ============================================================================

create or replace function duc_tem_khoang_sx(p_tags text[])
returns table(tag_no text, moc timestamptz, tu timestamptz, ngay_ca date, ca text)
language plpgsql
stable
as $$
#variable_conflict use_column
declare
  r record;
  v_moc timestamptz;
  v_local timestamp;
  v_pa text;
  v_ngay date;
  v_ca text;
  v_bd timestamp;   -- đầu ca (giờ VN)
  v_kt timestamp;   -- cuối ca chuẩn (giờ VN)
  v_s record;
  v_truoc timestamptz;
begin
  for r in
    select t.tag_no, t.may_tt, t.ma_sp, coalesce(t.ngay_gio_ghi_nhan, t.ngay_gio_in) m
    from duc_tem t
    where t.tag_no = any(p_tags) and t.may_tt is not null
      and coalesce(t.ngay_gio_ghi_nhan, t.ngay_gio_in) is not null
  loop
    v_moc := r.m;
    v_local := v_moc at time zone 'Asia/Ho_Chi_Minh';
    v_ngay := null; v_ca := null; v_bd := null; v_kt := null;

    -- 1) Ca theo báo cáo kết ca: ca kết đầu tiên sau mốc, nếu mốc chưa quá
    --    giờ kết ca chuẩn + 2h (tránh ca kết muộn do tự kết ca).
    select b.ngay, b.ca, b.phuong_an_ca into v_s
    from duc_bao_cao_ca b
    where b.thoi_diem_ket_ca >= v_moc and b.thoi_diem_ket_ca < v_moc + interval '1 day'
    order by b.thoi_diem_ket_ca limit 1;
    if found then
      v_bd := v_s.ngay + case v_s.ca when 'Ca ngày' then time '06:00' when 'Ca đêm' then time '18:00'
                                     when 'Ca 1' then time '06:00' when 'Ca 2' then time '14:00' end;
      v_kt := v_s.ngay + case v_s.ca when 'Ca ngày' then interval '18 hours' when 'Ca đêm' then interval '30 hours'
                                     when 'Ca 1' then interval '14 hours' when 'Ca 2' then interval '22 hours' end;
      if v_bd is not null and v_local >= v_bd - interval '1 hour' and v_local < v_kt + interval '2 hours' then
        v_ngay := v_s.ngay; v_ca := v_s.ca;
      else
        v_bd := null; v_kt := null;
      end if;
    end if;

    -- 2) Không khớp báo cáo → theo khung giờ ca chuẩn.
    if v_ca is null then
      select b.phuong_an_ca into v_pa from duc_bao_cao_ca b
      where b.ngay between v_local::date - 1 and v_local::date
      order by b.thoi_diem_ket_ca desc nulls last limit 1;
      v_pa := coalesce(v_pa, '2 ca 12h');
      if v_pa = '2 ca 8h' then
        if v_local::time >= time '06:00' and v_local::time < time '14:00' then
          v_ngay := v_local::date; v_ca := 'Ca 1'; v_bd := v_ngay + time '06:00';
        elsif v_local::time >= time '14:00' and v_local::time < time '22:00' then
          v_ngay := v_local::date; v_ca := 'Ca 2'; v_bd := v_ngay + time '14:00';
        end if;
      else
        if v_local::time >= time '06:00' and v_local::time < time '18:00' then
          v_ngay := v_local::date; v_ca := 'Ca ngày'; v_bd := v_ngay + time '06:00';
        else
          v_ngay := case when v_local::time < time '06:00' then v_local::date - 1 else v_local::date end;
          v_ca := 'Ca đêm'; v_bd := v_ngay + time '18:00';
        end if;
      end if;
    end if;

    -- 3) Mốc tem trước cùng máy + mã SP (trong 14h) = lúc bắt đầu đúc thùng này.
    select max(coalesce(x.ngay_gio_ghi_nhan, x.ngay_gio_in)) into v_truoc
    from duc_tem x
    where x.may_tt = r.may_tt and x.ma_sp = r.ma_sp and x.tag_no <> r.tag_no
      and coalesce(x.ngay_gio_ghi_nhan, x.ngay_gio_in) < v_moc
      and coalesce(x.ngay_gio_ghi_nhan, x.ngay_gio_in) > v_moc - interval '14 hours';

    tag_no := r.tag_no;
    moc := v_moc;
    tu := greatest(v_truoc, (v_bd at time zone 'Asia/Ho_Chi_Minh'));
    if tu is not null and tu > v_moc then tu := null; end if;
    ngay_ca := v_ngay;
    ca := v_ca;
    return next;
  end loop;
end;
$$;

grant execute on function duc_tem_khoang_sx(text[]) to anon, authenticated;
