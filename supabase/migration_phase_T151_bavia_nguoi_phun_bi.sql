-- ============================================================================
-- T151 — Bảng điều khiển Bavia: thêm "Người phun bi" theo Line (trưởng ca nhập
-- tự do, không bắt buộc). Lưu ở cd_tram_hien_tai.nguoi_phun_bi và theo từng
-- thùng (bavia_thung.nguoi_phun_bi) để in Phiếu quản lý lô:
--   dòng Xử lý Bavia = người thao tác, Ktra ngoại quan = người kiểm tra,
--   Sandblast = người phun bi (user chốt 23/10/2026).
--
-- bavia_line_luu thêm tham số p_nguoi_phun_bi (default null = giữ giá trị cũ,
-- '' = xoá) — bavia_nap_kh gọi 7 tham số vẫn chạy và không làm mất người phun bi.
-- Các hàm khác vá tại chỗ bằng replace trên định nghĩa hiện có (có kiểm tra).
--
-- Trạng thái: Đã chạy STAGING 23/10/2026. Đã chạy PROD 23/10/2026.
-- ============================================================================

alter table public.cd_tram_hien_tai add column if not exists nguoi_phun_bi text;
alter table public.bavia_thung add column if not exists nguoi_phun_bi text;

drop function if exists public.bavia_line_luu(date, text, text, text, numeric, text, text);
create or replace function public.bavia_line_luu(
  p_ngay date, p_ca text, p_ten_line text, p_ma_sp text, p_kh_ca numeric,
  p_nguoi_thao_tac text, p_nguoi_kiem text, p_nguoi_phun_bi text default null
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_id text;
  v_info jsonb;
  v_dang_do record;
  v_user text := duc_su_co_nguoi_hien_tai();
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  if p_ngay is null or coalesce(p_ca, '') not in ('Ca ngày', 'Ca đêm', 'Ca 1', 'Ca 2') then
    return jsonb_build_object('ok', false, 'error', 'Ngày / ca không hợp lệ');
  end if;
  if exists (select 1 from bavia_ket_ca where ngay = p_ngay and ca = p_ca) then
    return jsonb_build_object('ok', false, 'error', 'Ca này đã kết ca, không sửa Line được');
  end if;
  if not exists (select 1 from master_machines where bo_phan = 'Bavia' and ma_may = p_ten_line) then
    return jsonb_build_object('ok', false, 'error', p_ten_line || ' không có trong danh mục Line Bavia');
  end if;
  v_info := bavia_thong_tin_ma(p_ma_sp);
  if not (v_info->>'ok')::boolean then return v_info; end if;

  select n.ma_sp, sum(t.so_luong) sl into v_dang_do
  from bavia_line_nguon n join duc_tem t on t.tag_no = n.tag_no
  where n.ten_line = p_ten_line and n.bo_luc is null and t.so_luong > 0 and n.ma_sp <> trim(p_ma_sp)
  group by n.ma_sp limit 1;
  if found then
    return jsonb_build_object('ok', false, 'error',
      p_ten_line || ' còn dở ' || v_dang_do.sl || ' pcs mã ' || v_dang_do.ma_sp
      || ' trên tem Đúc đang dùng. Làm hết hoặc bấm Bỏ các tem đó trước khi đổi mã.');
  end if;

  v_id := duc_normalize_name('Bavia') || '_' || to_char(p_ngay, 'DDMMYYYY') || '_'
          || duc_normalize_name(p_ca) || '_' || duc_normalize_name(p_ten_line);
  insert into cd_tram_hien_tai (id_tram, ngay, ca, cong_doan, ten_tram, ma_sp, ten_sp, kh_ca,
    nguoi_thao_tac, nguoi_kiem_tra, nguoi_phun_bi, so_luong_ok, so_luong_ng, version, last_updated_by, last_updated_at)
  values (v_id, p_ngay, p_ca, 'Bavia', p_ten_line, trim(p_ma_sp), coalesce(v_info->>'ten_sp', ''),
    nullif(p_kh_ca, 0), coalesce(p_nguoi_thao_tac, ''), nullif(trim(coalesce(p_nguoi_kiem, '')), ''),
    nullif(trim(coalesce(p_nguoi_phun_bi, '')), ''), 0, 0, 1, v_user, now())
  on conflict (id_tram) do update set
    ma_sp = excluded.ma_sp, ten_sp = excluded.ten_sp, kh_ca = excluded.kh_ca,
    nguoi_thao_tac = excluded.nguoi_thao_tac, nguoi_kiem_tra = excluded.nguoi_kiem_tra,
    nguoi_phun_bi = case when p_nguoi_phun_bi is null then cd_tram_hien_tai.nguoi_phun_bi else excluded.nguoi_phun_bi end,
    version = cd_tram_hien_tai.version + 1, last_updated_by = v_user, last_updated_at = now();

  return jsonb_build_object('ok', true, 'id_tram', v_id);
end $$;
revoke execute on function public.bavia_line_luu(date, text, text, text, numeric, text, text, text) from public, anon;
grant execute on function public.bavia_line_luu(date, text, text, text, numeric, text, text, text) to authenticated;

-- Vá các hàm hiện có: ghi người phun bi vào thùng, trả về cho màn hình và dữ liệu in.
do $do$
declare d text;
begin
  -- bavia_quet + bavia_dong_thung: thêm cột nguoi_phun_bi khi tạo bavia_thung
  foreach d in array array['public.bavia_quet(text,text)', 'public.bavia_dong_thung(text)'] loop
    declare f text := pg_get_functiondef(d::regprocedure);
    begin
      if f not like '%nguoi_phun_bi%' then
        f := replace(f, 'nguoi_lam, nguoi_kiem, nguoi_ghi, nguoi_uid)', 'nguoi_lam, nguoi_kiem, nguoi_ghi, nguoi_uid, nguoi_phun_bi)');
        f := replace(f, 'v_line.nguoi_thao_tac, v_line.nguoi_kiem_tra, v_user, auth.uid());',
                        'v_line.nguoi_thao_tac, v_line.nguoi_kiem_tra, v_user, auth.uid(), v_line.nguoi_phun_bi);');
        if f not like '%v_line.nguoi_phun_bi%' then raise exception 'Không vá được %', d; end if;
        execute f;
      end if;
    end;
  end loop;

  d := pg_get_functiondef('public.bavia_du_lieu(date,text)'::regprocedure);
  if d not like '%nguoi_phun_bi%' then
    d := replace(d, '''nguoi_thao_tac'', l.nguoi_thao_tac, ''nguoi_kiem_tra'', l.nguoi_kiem_tra,',
                    '''nguoi_thao_tac'', l.nguoi_thao_tac, ''nguoi_kiem_tra'', l.nguoi_kiem_tra, ''nguoi_phun_bi'', l.nguoi_phun_bi,');
    d := replace(d, '''nguoi_kiem'', b.nguoi_kiem,', '''nguoi_kiem'', b.nguoi_kiem, ''nguoi_phun_bi'', b.nguoi_phun_bi,');
    if d not like '%l.nguoi_phun_bi%' or d not like '%b.nguoi_phun_bi%' then raise exception 'Không vá được bavia_du_lieu'; end if;
    execute d;
  end if;

  d := pg_get_functiondef('public.bavia_du_lieu_in(text[])'::regprocedure);
  if d not like '%nguoi_phun_bi%' then
    d := replace(d, '''nguoi_bavia'', b.nguoi_lam, ''nguoi_kiem'', b.nguoi_kiem,',
                    '''nguoi_bavia'', b.nguoi_lam, ''nguoi_kiem'', b.nguoi_kiem, ''nguoi_phun_bi'', b.nguoi_phun_bi,');
    if d not like '%b.nguoi_phun_bi%' then raise exception 'Không vá được bavia_du_lieu_in'; end if;
    execute d;
  end if;
end $do$;
