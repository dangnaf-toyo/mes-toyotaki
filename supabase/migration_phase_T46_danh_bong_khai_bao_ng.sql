-- ============================================================================
-- Phase T46 — Khai báo NG (phế) phát sinh khi Đánh bóng, gắn theo tem Đúc
-- nguồn đang dùng (T43). Ví dụ: tem Đúc 150pcs, sau đánh bóng chỉ ra được
-- 145pcs OK (đi vào các thùng thành phẩm) + 5pcs NG (3 nhẹ cân, 2 dập lẹm).
--
-- Người vận hành báo NG trực tiếp trên dòng "Tem Đúc đang dùng"
-- (ghi-nhan-tem-thanh-pham.html) — số lượng NG bị TRỪ THẲNG vào so_luong còn
-- lại của tem Đúc đó (giống 1 lượt "tiêu thụ" nhưng không tạo thùng thành
-- phẩm), để phần còn lại luôn đúng bằng số pcs còn có thể ra thành phẩm.
--
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create table if not exists public.cd_ng_khai_bao (
  id bigserial primary key,
  tag_no text not null references duc_tem(tag_no),
  ma_sp text,
  ten_sp text,
  cong_doan text not null,
  loai_ng text not null,
  so_luong numeric not null check (so_luong > 0),
  nguoi text,
  ngay_gio timestamptz not null default now()
);
create index if not exists idx_cd_ng_khai_bao_cong_doan_ngay on public.cd_ng_khai_bao (cong_doan, ngay_gio);
create index if not exists idx_cd_ng_khai_bao_tag_no on public.cd_ng_khai_bao (tag_no);

alter table public.cd_ng_khai_bao enable row level security;
drop policy if exists cd_ng_khai_bao_select on public.cd_ng_khai_bao;
create policy cd_ng_khai_bao_select on public.cd_ng_khai_bao for select to authenticated using (true);

create or replace function cd_khai_bao_ng(
  p_tag_no text,
  p_cong_doan text,
  p_loai_ng text,
  p_so_luong numeric,
  p_nguoi text
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_tem duc_tem%rowtype;
begin
  if p_tag_no is null or trim(p_tag_no) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu Tag No');
  end if;
  if p_cong_doan is null or trim(p_cong_doan) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu công đoạn');
  end if;
  if p_loai_ng is null or trim(p_loai_ng) = '' then
    return jsonb_build_object('ok', false, 'error', 'Thiếu chủng loại NG');
  end if;
  if p_so_luong is null or p_so_luong <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Số lượng NG phải lớn hơn 0');
  end if;

  select * into v_tem from duc_tem where tag_no = trim(p_tag_no) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Không tìm thấy tem ' || p_tag_no);
  end if;
  if v_tem.thoi_diem_bat_dau_dung is null then
    return jsonb_build_object('ok', false, 'error', 'Tem ' || p_tag_no || ' chưa được khai báo đang dùng — đọc tem trước');
  end if;
  if p_so_luong > coalesce(v_tem.so_luong, 0) then
    return jsonb_build_object('ok', false, 'error',
      'Số lượng NG (' || p_so_luong || ') vượt quá số còn lại của tem (' || coalesce(v_tem.so_luong, 0) || ' pcs)');
  end if;

  update duc_tem set so_luong = so_luong - p_so_luong where tag_no = v_tem.tag_no;

  insert into cd_ng_khai_bao (tag_no, ma_sp, ten_sp, cong_doan, loai_ng, so_luong, nguoi)
  values (v_tem.tag_no, v_tem.ma_sp, v_tem.ten_sp, trim(p_cong_doan), trim(p_loai_ng), p_so_luong, p_nguoi);

  return jsonb_build_object(
    'ok', true,
    'tag_no', v_tem.tag_no,
    'so_luong_con_lai', coalesce(v_tem.so_luong, 0) - p_so_luong
  );
end;
$$;

revoke execute on function cd_khai_bao_ng(text, text, text, numeric, text) from anon;
grant  execute on function cd_khai_bao_ng(text, text, text, numeric, text) to authenticated;
