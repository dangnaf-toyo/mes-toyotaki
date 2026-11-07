-- ============================================================================
-- T217 — Bavia: giới hạn ca theo lần bấm Kết ca (như Đúc), không cắt cứng theo giờ
--
-- Trước đây: trang tự chọn ca theo đồng hồ (18:00 là sang Ca đêm), sản lượng tính vào
-- ca đang chọn. 06/11/2026: tăng ca sau 18:00 → Nạp KH vào Ca đêm 18:16 → 768 pcs bị
-- tính cho Ca đêm dù thực tế là ca ngày làm thêm. Chưa từng có lần kết ca Bavia nào.
--
-- Quy tắc ca đang mở (bavia_ca_dang_mo), giống adjustSuggestedForOpenShift của Đúc:
--   1) Ca theo đồng hồ: 06:00–18:00 Ca ngày, còn lại Ca đêm (00:00–06:00 thuộc ngày trước).
--   2) Ca đó đã kết → tiến sang ca kế tiếp (kết sớm thì ca sau bắt đầu ngay).
--   3) Chưa kết, và ca liền trước đã có sản lượng/NG/test mà chưa kết → vẫn là ca liền trước:
--        - Ca ngày giữ tới 06:00 hôm sau (tăng ca);
--        - Ca đêm giữ tối đa tới 08:00 (2 giờ, như quy ước D58 của Đúc).
--      Ca liền trước không có việc (Line chỉ nạp KH) thì không giữ.
--
-- Chặn: quét / đóng thùng / NG / lấy hàng test chỉ ghi vào ca đang mở; admin được ghi ca
-- khác để sửa số liệu. Mở Line và Nạp KH không chặn (chuẩn bị trước cho ca sau vẫn được).
--
-- Kết ca: Line không có việc (không thùng, NG, test) không bắt buộc người thao tác/kiểm tra —
-- trước đây chặn kết ca vì nạp KH mở cả Line không chạy. Quy tắc lý do <90% KH giữ nguyên.
--
-- Vá 5 hàm bằng pg_get_functiondef để giữ nguyên phần còn lại. An toàn chạy lại.
-- ============================================================================

-- ── Nội bộ: Line / ca đã có việc chưa ───────────────────────────────────────
create or replace function public.bavia_line_co_viec(p_id_tram text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from bavia_thung where id_tram = p_id_tram)
      or exists (select 1 from cd_ng_khai_bao where id_tram = p_id_tram)
      or exists (select 1 from bavia_hang_test where id_tram = p_id_tram);
$$;
revoke execute on function public.bavia_line_co_viec(text) from public, anon, authenticated;

create or replace function public.bavia_ca_co_viec(p_ngay date, p_ca text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from cd_tram_hien_tai c
    where c.cong_doan = 'Bavia' and c.ngay = p_ngay and c.ca = p_ca and bavia_line_co_viec(c.id_tram)
  );
$$;
revoke execute on function public.bavia_ca_co_viec(date, text) from public, anon, authenticated;

-- ── Ca đang mở ──────────────────────────────────────────────────────────────
create or replace function public.bavia_ca_dang_mo(p_luc timestamptz default now())
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_gio timestamp := p_luc at time zone 'Asia/Ho_Chi_Minh';
  v_h int := extract(hour from v_gio)::int;
  v_ngay date := v_gio::date;
  v_ca text;
  i int;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;

  if v_h >= 6 and v_h < 18 then v_ca := 'Ca ngày';
  elsif v_h >= 18 then v_ca := 'Ca đêm';
  else v_ca := 'Ca đêm'; v_ngay := v_ngay - 1;
  end if;

  if not exists (select 1 from bavia_ket_ca where ngay = v_ngay and ca = v_ca) then
    if v_ca = 'Ca đêm'
       and not exists (select 1 from bavia_ket_ca where ngay = v_ngay and ca = 'Ca ngày')
       and bavia_ca_co_viec(v_ngay, 'Ca ngày') then
      return jsonb_build_object('ok', true, 'ngay', v_ngay, 'ca', 'Ca ngày', 'giu_ca_truoc', true);
    end if;
    if v_ca = 'Ca ngày' and v_h < 8
       and not exists (select 1 from bavia_ket_ca where ngay = v_ngay - 1 and ca = 'Ca đêm')
       and bavia_ca_co_viec(v_ngay - 1, 'Ca đêm') then
      return jsonb_build_object('ok', true, 'ngay', v_ngay - 1, 'ca', 'Ca đêm', 'giu_ca_truoc', true);
    end if;
    return jsonb_build_object('ok', true, 'ngay', v_ngay, 'ca', v_ca, 'giu_ca_truoc', false);
  end if;

  -- Ca theo đồng hồ đã kết sớm → tiến sang ca kế tiếp chưa kết
  for i in 1..3 loop
    if v_ca = 'Ca ngày' then v_ca := 'Ca đêm';
    else v_ca := 'Ca ngày'; v_ngay := v_ngay + 1;
    end if;
    exit when not exists (select 1 from bavia_ket_ca where ngay = v_ngay and ca = v_ca);
  end loop;
  return jsonb_build_object('ok', true, 'ngay', v_ngay, 'ca', v_ca, 'giu_ca_truoc', false);
end $$;
revoke execute on function public.bavia_ca_dang_mo(timestamptz) from public, anon;
grant execute on function public.bavia_ca_dang_mo(timestamptz) to authenticated;

-- ── Nội bộ: thông báo lỗi nếu ghi vào ca không phải ca đang mở (null = được ghi) ─
create or replace function public.bavia_loi_ca_khong_mo(p_ngay date, p_ca text)
returns text
language plpgsql stable security definer set search_path = public
as $$
declare
  v_mo jsonb;
begin
  -- Ca đã kết: để kiểm tra "đã kết ca" sẵn có trong từng hàm báo lỗi.
  if exists (select 1 from bavia_ket_ca where ngay = p_ngay and ca = p_ca) then return null; end if;
  if public.has_role('admin') then return null; end if;
  v_mo := bavia_ca_dang_mo();
  if (v_mo->>'ngay')::date = p_ngay and v_mo->>'ca' = p_ca then return null; end if;
  return 'Ca đang mở là ' || (v_mo->>'ca') || ' ' || to_char((v_mo->>'ngay')::date, 'DD/MM')
      || '. Không ghi sản lượng vào ' || p_ca || ' ' || to_char(p_ngay, 'DD/MM')
      || ' được. Bấm "Về ca đang mở" rồi làm lại.';
end $$;
revoke execute on function public.bavia_loi_ca_khong_mo(date, text) from public, anon, authenticated;

-- ── Vá các hàm ghi sản lượng ────────────────────────────────────────────────
do $do$
declare
  v_ten text;
  v_cu text;
  v_moi text;
  v_moc constant text := 'if exists (select 1 from bavia_ket_ca where ngay = v_line.ngay and ca = v_line.ca) then';
  v_chen constant text :=
    E'if bavia_loi_ca_khong_mo(v_line.ngay, v_line.ca) is not null then -- T217\n'
    || E'    return jsonb_build_object(''ok'', false, ''error'', bavia_loi_ca_khong_mo(v_line.ngay, v_line.ca));\n'
    || E'  end if;\n  ';
begin
  foreach v_ten in array array[
    'bavia_quet(text, text)',
    'bavia_dong_thung(text)',
    'bavia_ng(text, text, text, text, numeric)',
    'bavia_test_lay(text, text, numeric, text, text, text)'
  ] loop
    v_cu := pg_get_functiondef(('public.' || v_ten)::regprocedure);
    if position('bavia_loi_ca_khong_mo' in v_cu) > 0 then continue; end if;
    if (length(v_cu) - length(replace(v_cu, v_moc, ''))) / length(v_moc) <> 1 then
      raise exception 'T217: % không có đúng 1 mốc kiểm tra kết ca', v_ten;
    end if;
    execute replace(v_cu, v_moc, v_chen || v_moc);
  end loop;

  -- Kết ca: chỉ bắt buộc người ở Line có việc
  v_cu := pg_get_functiondef('public.bavia_ket_ca_luu(date, text, jsonb)'::regprocedure);
  if position('bavia_line_co_viec' in v_cu) = 0 then
    v_moi := replace(v_cu, 'if coalesce(l.nguoi_thao_tac, '''') = '''' then',
                           'if coalesce(l.nguoi_thao_tac, '''') = '''' and bavia_line_co_viec(l.id_tram) then');
    v_moi := replace(v_moi, 'if coalesce(l.nguoi_kiem_tra, '''') = '''' then',
                            'if coalesce(l.nguoi_kiem_tra, '''') = '''' and bavia_line_co_viec(l.id_tram) then');
    if (length(v_moi) - length(v_cu)) <> 2 * length(' and bavia_line_co_viec(l.id_tram)') then
      raise exception 'T217: bavia_ket_ca_luu không khớp mốc kiểm tra người';
    end if;
    execute v_moi;
  end if;
end $do$;
