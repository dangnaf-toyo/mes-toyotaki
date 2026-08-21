-- ============================================================================
-- Phase T19 — Hoàn tác tách tem (intem.html).
-- Lý do: xoá thẳng 1 tem con (đuôi -A/-B/...) bị chặn bởi khoá ngoại
-- duc_tem_tach_tag_no_con_fkey — vì tem con này đã trừ số lượng khỏi tem cha
-- lúc tách (duc_tach_tem), xoá thẳng sẽ làm mất số lượng đó vĩnh viễn.
-- RPC này xoá tem con ĐÚNG CÁCH: xoá lịch sử tách + xoá tem con, rồi cộng trả
-- lại số lượng đã tách về tem cha.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

create or replace function duc_hoan_tac_tach_tem(p_tag_no_con text, p_nguoi text)
returns text
language plpgsql
security definer
as $$
declare
  v_tach record;
begin
  select * into v_tach from duc_tem_tach where tag_no_con = p_tag_no_con;
  if not found then
    raise exception 'Tem % không phải tem được tách ra (không có trong lịch sử tách) — không hoàn tác được', p_tag_no_con;
  end if;

  begin
    delete from duc_tem_tach where tag_no_con = p_tag_no_con;
    delete from duc_tem where tag_no = p_tag_no_con;
  exception when foreign_key_violation then
    raise exception 'Tem % đã được dùng ở nơi khác (tách tiếp, gán lot NVL, đóng gói...) — không thể tự động hoàn tác, cần xử lý thủ công', p_tag_no_con;
  end;

  update duc_tem set so_luong = coalesce(so_luong, 0) + v_tach.so_luong_con where tag_no = v_tach.tag_no_cha;

  return v_tach.tag_no_cha;
end;
$$;
revoke execute on function duc_hoan_tac_tach_tem(text, text) from anon;
grant execute on function duc_hoan_tac_tach_tem(text, text) to authenticated;
