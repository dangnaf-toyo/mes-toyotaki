-- T397: Báo cáo kết ca lưu danh sách sự cố đang mở chuyển tiếp sang ca sau
-- (duc_bao_cao_ca.su_co_chuyen_tiep). Phút = từ lúc phát sinh (hoặc đầu ca nếu
-- sự cố đã chuyển từ ca trước) đến lúc kết ca (v_we = least(now, giờ hết ca)).
-- Lý do phải lưu: lúc chuyển tiếp, ca sau đặt lại giờ phát sinh = đầu ca sau,
-- nên sau này không dựng lại được giờ phát sinh gốc.
alter table public.duc_bao_cao_ca add column if not exists su_co_chuyen_tiep jsonb;

do $do$
declare
  d text := pg_get_functiondef('public.duc_end_shift'::regproc);
  a_old text := 'update duc_bao_cao_ca set dung_khong_ro = v_dkr where id_bao_cao = v_id_bao_cao;';
  a_new text := $s$update duc_bao_cao_ca set dung_khong_ro = v_dkr,
    su_co_chuyen_tiep = (   -- T397
      select coalesce(jsonb_agg(jsonb_build_object(
               'ma_may', c.ma_may, 'ma_sp', c.ma_sp, 'id_su_co', c.open_id_su_co,
               'loai_su_co', c.open_loai_su_co, 'gio_phat_sinh', c.open_gio_phat_sinh, 'tinh_tu', greatest(c.open_gio_phat_sinh, v_ws),
               'den', v_we, 'phut', greatest(0, round(extract(epoch from (v_we - greatest(c.open_gio_phat_sinh, v_ws))) / 60)),
               'van_de', c.open_van_de, 'noi_dung_xu_ly', c.open_noi_dung_xu_ly, 'dam_nhiem', c.open_dam_nhiem)
             order by c.ma_may), '[]'::jsonb)
        from (select distinct on (coalesce(open_id_su_co, ma_may)) * from duc_ca_hien_tai
               where ngay = p_ngay and ca = p_ca and open_gio_phat_sinh is not null
               order by coalesce(open_id_su_co, ma_may), row_seq desc) c)
    where id_bao_cao = v_id_bao_cao;$s$;
  b_old text := $s$'tem_mo_coi', v_tem_mo_coi, 'dung_khong_ro', v_dkr);$s$;
  b_new text := $s$'tem_mo_coi', v_tem_mo_coi, 'dung_khong_ro', v_dkr,
    'su_co_chuyen_tiep', (select su_co_chuyen_tiep from duc_bao_cao_ca where id_bao_cao = v_id_bao_cao));$s$;
begin
  if position('T397' in d) > 0 then raise notice 'T397 đã áp'; return; end if;
  if position(a_old in d) = 0 or position(b_old in d) = 0 then
    raise exception 'duc_end_shift khác bản mong đợi — không áp T397';
  end if;
  execute replace(replace(d, a_old, a_new), b_old, b_new);
end
$do$;

revoke execute on function public.duc_end_shift(date, text, text, text, jsonb, text, text) from public, anon;
