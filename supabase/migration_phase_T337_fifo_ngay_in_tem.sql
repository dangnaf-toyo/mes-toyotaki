-- ============================================================================
-- Phase T337 — Chuyển công đoạn: kiểm FIFO theo NGÀY IN TEM (duc_tem.ngay_gio_in)
-- Tem quét để chuyển phải là tem có ngày in CŨ NHẤT của cùng mã SP đang ở
-- cùng công đoạn giao. Lấy sai → màn hình hiện cảnh báo (KHÔNG chặn).
-- Chỉ xét tem in trong 14 ngày gần nhất (user chốt 23/11/2026 — dữ liệu cũ
-- còn hàng nghìn tem tồn không quét chuyển, xét hết sẽ báo sai liên tục).
-- Bỏ qua: tem hết SL, tem chỉ thị chưa ghi nhận, tem đang cách ly NCP, các
-- tem đã quét cùng lô (p_bo_qua).
-- ============================================================================
create or replace function public.cd_fifo_tem_cu_hon(p_tag_no text, p_bo_qua text[] default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_tem duc_tem%rowtype;
  v_vt text;
  r record;
  v_n int := 0;
  v_tag text;
  v_in timestamptz;
begin
  select * into v_tem from duc_tem where tag_no = trim(p_tag_no);
  if not found or v_tem.ngay_gio_in is null then
    return jsonb_build_object('so_lo', 0);
  end if;
  v_vt := cd_vi_tri_tem(v_tem.tag_no);
  for r in
    select t.tag_no, t.ngay_gio_in from duc_tem t
    where t.ma_sp = v_tem.ma_sp
      and t.tag_no <> v_tem.tag_no
      and t.so_luong > 0
      and coalesce(t.trang_thai, '') not in ('Chờ sản xuất', 'Chờ đóng gói TP')
      and t.ngay_gio_in < v_tem.ngay_gio_in
      and t.ngay_gio_in >= now() - interval '14 days'
      and not (t.tag_no = any(coalesce(p_bo_qua, '{}'::text[])))
    order by t.ngay_gio_in, t.tag_no
  loop
    if cd_vi_tri_tem(r.tag_no) = v_vt and duc_tem_id_ncp_cach_ly(r.tag_no) is null then
      v_n := v_n + 1;
      if v_tag is null then v_tag := r.tag_no; v_in := r.ngay_gio_in; end if;
    end if;
  end loop;
  return jsonb_build_object('so_lo', v_n, 'vi_tri', v_vt, 'tag_no', v_tag, 'ngay_gio_in', v_in);
end $$;

revoke execute on function public.cd_fifo_tem_cu_hon(text, text[]) from public, anon;
grant execute on function public.cd_fifo_tem_cu_hon(text, text[]) to authenticated;
