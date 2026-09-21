-- D56: tự động "kết ca hộ" các ca ĐÃ BỊ BỎ QUÊN quá lâu (không đụng ca đang
-- chạy bình thường) — phòng lặp lại sự cố DC4-8 kẹt nguyên 1 ngày ở Ca ngày
-- 20/09 vì trưởng ca quên kết ca (xem hội thoại/agent trước đó).
--
-- Ý TƯỞNG BAN ĐẦU của user là "6h sáng thứ 2 reset toàn bộ máy về dừng sản
-- xuất" — nhưng làm y hệt vậy có rủi ro: xoá thẳng dữ liệu ca hiện tại của
-- máy nào đó đang chạy thật xuyên đêm Chủ nhật→thứ 2 sẽ tạo ra ĐÚNG kiểu lỗi
-- mất/trùng dữ liệu vừa mất công sửa (D53-D55). Nên hàm dưới đây CHỈ tự đóng
-- những ca đã kết thúc quá 12 tiếng mà CHƯA có báo cáo (duc_bao_cao_ca) —
-- tức rõ ràng bị bỏ quên, không phải ca đang chạy/mới xong trong ngày. Dùng
-- ĐÚNG hàm duc_end_shift() sẵn có (không carry-over gì) để vừa lưu báo cáo
-- thật cho ca đó (không mất dữ liệu), vừa dọn sạch duc_ca_hien_tai cho các
-- máy đó (= "dừng sản xuất") — trưởng ca ca mới sẽ phải bấm "+ Gán kế hoạch"
-- load lại KH, đúng như user muốn.
--
-- Ca nào có sự cố đang mở (chưa xử lý xong) sẽ KHÔNG tự đóng được (do
-- duc_end_shift() chặn — đúng thiết kế, cần người xử lý sự cố trước) — hàm
-- bắt lỗi, bỏ qua ca đó, không làm hỏng các ca khác trong cùng lượt chạy.
--
-- Lịch chạy: mỗi thứ 2 đầu tuần lúc 6h00 sáng (giờ VN) = 23h00 UTC Chủ nhật.
-- Chạy 1 lần trên Supabase project PRODUCTION.

create or replace function duc_auto_close_forgotten_shifts()
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row record;
  v_shift_window jsonb;
  v_result jsonb;
  v_closed jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
begin
  for v_row in
    select ngay, ca, min(phuong_an_ca) as phuong_an_ca
    from duc_ca_hien_tai
    where ma_sp is not null and ma_sp <> ''
    group by ngay, ca
  loop
    v_shift_window := duc_get_shift_window(v_row.ngay, v_row.phuong_an_ca, v_row.ca);
    if v_shift_window is null then continue; end if;

    -- Chỉ đụng ca đã kết thúc quá 12 tiếng — ca hôm nay/ca vừa xong trong
    -- ngày vẫn để trưởng ca tự kết ca bình thường, không tự động đụng vào.
    if (now() - (v_shift_window->>'end')::timestamptz) < interval '12 hours' then continue; end if;

    -- Đã có báo cáo cho đúng ngày/ca này rồi thì bỏ qua (đã kết ca thật).
    if exists (select 1 from duc_bao_cao_ca where ngay = v_row.ngay and ca = v_row.ca) then continue; end if;

    begin
      v_result := duc_end_shift(
        v_row.ngay, v_row.ca, v_row.phuong_an_ca,
        'Hệ thống (tự động)', '[]'::jsonb,
        'Tự động kết ca — trưởng ca chưa kết ca quá 12 tiếng sau giờ kết thúc ca. Kiểm tra lại nếu số liệu bất thường.',
        'system@auto_close_shift'
      );
      if coalesce((v_result->>'ok')::boolean, false) then
        v_closed := v_closed || jsonb_build_array(jsonb_build_object('ngay', v_row.ngay, 'ca', v_row.ca, 'id_bao_cao', v_result->>'id_bao_cao'));
      else
        v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('ngay', v_row.ngay, 'ca', v_row.ca, 'error', v_result->>'error'));
      end if;
    exception when others then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('ngay', v_row.ngay, 'ca', v_row.ca, 'error', sqlerrm));
    end;
  end loop;

  return jsonb_build_object('closed', v_closed, 'skipped', v_skipped);
end;
$$;
revoke execute on function duc_auto_close_forgotten_shifts() from anon;
grant execute on function duc_auto_close_forgotten_shifts() to authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'duc-auto-close-forgotten-shifts') then
    perform cron.unschedule('duc-auto-close-forgotten-shifts');
  end if;
end $$;

select cron.schedule(
  'duc-auto-close-forgotten-shifts',
  '0 23 * * 0',   -- Chủ nhật 23:00 UTC = Thứ 2 06:00 giờ VN (Asia/Ho_Chi_Minh)
  $$select duc_auto_close_forgotten_shifts();$$
);
