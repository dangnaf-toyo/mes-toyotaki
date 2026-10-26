-- ============================================================================
-- Phase T167 — Wallboard: 2 màn P-Chart từ đầu tháng đến hiện tại.
--   (3) P-Chart NG OQC sau gia công (cùng quy tắc phạm vi với oqc-ng-dash.js:
--       FULL_POST_MACHINING + phiếu chưa phân loại / phạm vi không khớp ngày-mã).
--   (4) P-Chart NG Bavia (nguồn bavia_ng_du_lieu — Excel quá khứ + MES).
-- wallboard_pchart(p_khoa) trả số liệu tổng hợp ngày × mã + CL / mục tiêu, cùng
-- cơ chế khoá như tong_quan_hom_nay (T160): đã đăng nhập hoặc khoá hợp lệ.
-- Ngày sản xuất hiện tại: trước 06:00 = ngày hôm trước.
-- An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create or replace function public.wallboard_pchart(p_khoa text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_local timestamp := now() at time zone 'Asia/Ho_Chi_Minh';
  v_ngay date;
  v_tu date;
  v_oqc jsonb;
  v_bv jsonb;
begin
  if auth.uid() is null and (p_khoa is null or not exists (select 1 from wallboard_khoa where khoa = p_khoa)) then
    return jsonb_build_object('ok', false, 'error', 'Link wallboard không hợp lệ hoặc đã bị thu hồi');
  end if;
  v_ngay := case when v_local::time < time '06:00' then v_local::date - 1 else v_local::date end;
  v_tu := date_trunc('month', v_ngay)::date;

  select jsonb_build_object(
    'mt', (select muc_tieu from oqc_ng_cau_hinh where ma_sp = '*'),
    'rows', coalesce((select jsonb_agg(jsonb_build_array(d, p, n, ng) order by d, p) from (
        select o.inspection_date d, o.product_code p, sum(o.total_qty) n, sum(o.ng_qty) ng
        from oqc_daily_inspection o
        left join oqc_inspection_context c on c.inspection_id = o.id
          and c.source_date = o.inspection_date and c.source_product_code = o.product_code
        where o.inspection_date between v_tu and v_ngay and o.total_qty > 0
          and coalesce(c.inspection_scope, '') in ('FULL_POST_MACHINING', '')
        group by 1, 2) x), '[]'::jsonb),
    'cfg', coalesce((select jsonb_agg(jsonb_build_array(ma_sp, cl, muc_tieu)) from oqc_ng_cau_hinh where ma_sp <> '*'), '[]'::jsonb))
  into v_oqc;

  -- Bavia: ngày có NG mà không có SL sản xuất thì bỏ (giống bavia-ng-dash.js)
  begin
    with src as (select bavia_ng_du_lieu(v_tu, v_ngay) j),
    sx as (select x->>0 d, x->>1 p, sum((x->>2)::numeric) n from src, jsonb_array_elements(src.j->'sx') x group by 1, 2),
    ng as (select x->>0 d, x->>1 p, sum((x->>3)::numeric) ng from src, jsonb_array_elements(src.j->'ng') x group by 1, 2)
    select jsonb_build_object(
      'mt', (select muc_tieu from bavia_ng_cau_hinh where ma_sp = '*'),
      'rows', coalesce((select jsonb_agg(jsonb_build_array(sx.d, sx.p, sx.n, coalesce(ng.ng, 0)) order by sx.d, sx.p)
        from sx left join ng on ng.d = sx.d and ng.p = sx.p where sx.n > 0), '[]'::jsonb),
      'cfg', coalesce((select jsonb_agg(jsonb_build_array(ma_sp, cl, muc_tieu)) from bavia_ng_cau_hinh where ma_sp <> '*'), '[]'::jsonb))
    into v_bv;
  exception when undefined_function or undefined_table then
    v_bv := null; -- DB chưa có dữ liệu Bavia (T158/T159)
  end;

  return jsonb_build_object('ok', true, 'tu', v_tu, 'den', v_ngay, 'oqc', v_oqc, 'bavia', v_bv);
end $$;
revoke all on function public.wallboard_pchart(text) from public;
grant execute on function public.wallboard_pchart(text) to anon, authenticated;
