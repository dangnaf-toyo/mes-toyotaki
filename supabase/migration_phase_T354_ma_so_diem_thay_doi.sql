-- T354: Mã số quản lý riêng cho mỗi phiếu điểm thay đổi Đúc.
-- Mẫu: TD-<máy>-yyMMdd-nn (vd TD-DC4-261126-01) — nn đếm theo máy + ngày ghi (giờ VN).
-- Tự cấp khi ghi phiếu (trigger), không sửa được. An toàn chạy lại.

alter table public.duc_thay_doi add column if not exists ma_so text;

-- 1) Cấp mã cho phiếu cũ theo thứ tự ghi (chạy trước khi gắn trigger khoá mã).
drop trigger if exists trg_duc_td_ma_so on public.duc_thay_doi;
with x as (
  select id, 'TD-' || upper(regexp_replace(ma_may, '\s+', '', 'g')) || '-'
           || to_char(thoi_diem_ghi at time zone 'Asia/Ho_Chi_Minh', 'YYMMDD') || '-' as tt,
         row_number() over (partition by upper(regexp_replace(ma_may, '\s+', '', 'g')),
                                         to_char(thoi_diem_ghi at time zone 'Asia/Ho_Chi_Minh', 'YYMMDD')
                            order by thoi_diem_ghi, id) as n
    from duc_thay_doi where ma_so is null
)
update duc_thay_doi d set ma_so = x.tt || lpad(x.n::text, 2, '0') from x where d.id = x.id;

create unique index if not exists duc_thay_doi_ma_so_uq on public.duc_thay_doi (ma_so);

-- 2) Trigger tự cấp mã khi ghi phiếu mới; không cho đổi mã đã cấp.
create or replace function public.duc_td_cap_ma_so()
returns trigger language plpgsql set search_path = public as $$
declare v_tien_to text; v_n int;
begin
  if tg_op = 'UPDATE' then
    new.ma_so := old.ma_so;
    return new;
  end if;
  v_tien_to := 'TD-' || upper(regexp_replace(coalesce(new.ma_may, ''), '\s+', '', 'g')) || '-'
            || to_char(coalesce(new.thoi_diem_ghi, now()) at time zone 'Asia/Ho_Chi_Minh', 'YYMMDD') || '-';
  perform pg_advisory_xact_lock(hashtext('duc_td_ma_so:' || v_tien_to));
  select coalesce(max(substring(ma_so from length(v_tien_to) + 1)::int), 0) + 1 into v_n
    from duc_thay_doi
   where ma_so like v_tien_to || '%' and substring(ma_so from length(v_tien_to) + 1) ~ '^\d+$';
  new.ma_so := v_tien_to || lpad(v_n::text, 2, '0');
  return new;
end $$;
revoke execute on function public.duc_td_cap_ma_so() from public, anon, authenticated;

create trigger trg_duc_td_ma_so before insert or update of ma_so on public.duc_thay_doi
  for each row execute function public.duc_td_cap_ma_so();

-- 3) duc_td_ghi trả thêm ma_so; chuông cần duyệt ghi kèm mã số.
do $$
declare d text;
begin
  d := pg_get_functiondef('public.duc_td_ghi'::regproc);
  if position('''ma_so''' in d) = 0 then
    d := replace(d, '''khan'', v_khan,', '''khan'', v_khan, ''ma_so'', (select ma_so from duc_thay_doi where id = v_id),');
    execute d;
  end if;
  d := pg_get_functiondef('public.duc_td_bao_duyet'::regproc);
  if position('v.ma_so' in d) = 0 then
    d := replace(d, '|| duc_td_nhom_ten(g) || ''): ''', '|| duc_td_nhom_ten(g) || ''): '' || coalesce(v.ma_so || '' · '', '''')');
    execute d;
  end if;
end $$;
