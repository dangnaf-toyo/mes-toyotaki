-- T210d — User 04/11/2026: bỏ bước bắt buộc "cam kết an toàn" trong phân cấp can thiệp khuôn.
-- Đã duyệt (hoặc cấp 0 / không tác động) là được bắt đầu, giao QC, đóng sự cố. Giữ cột an_toan + RPC cũ (không dùng).
do $p$
declare d text; n text;
begin
  d := pg_get_functiondef('public.duc_khuon_ct_kiem(text,text,text,timestamptz)'::regprocedure);
  n := replace(d, E'  if jsonb_array_length(c.an_toan) = 0 then\n    return ''⛔ Chưa tick cam kết an toàn trước khi can thiệp khuôn (ngắt nguồn, treo khoá, không dùng búa / máy mài trên bề mặt tạo hình…).'';\n  end if;\n',
                  E'  -- T210d (user 04/11): bỏ bắt buộc cam kết an toàn.\n');
  if n <> d then execute n; end if;
  d := pg_get_functiondef('public.duc_khuon_ct_duyet(bigint,boolean,text,timestamptz)'::regprocedure);
  n := replace(d, '— tick cam kết an toàn rồi bắt đầu.', '— được bắt đầu xử lý.');
  if n <> d then execute n; end if;
end $p$;
update public.duc_khuon_ct_danh_muc set hieu_luc = false where loai = 'an_toan';
