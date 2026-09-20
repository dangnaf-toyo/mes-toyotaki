-- ============================================================================
-- Phase T49 — Tồn kho theo mã SP (T48) tách riêng 2 loại tại mỗi công đoạn:
--   - 'wip'            : tem gốc (không phải tem thành phẩm TP...) còn đang ở
--                        công đoạn đó, CHƯA đóng vào thùng thành phẩm — gồm
--                        cả WIP đang làm dở lẫn tem Đúc đã chuyển tới nhưng
--                        chưa tới lượt.
--   - 'tp_da_dong_goi' : tem thành phẩm (TP...) ĐÃ quét ghi nhận
--                        (trang_thai='Đã đóng gói TP'), còn nằm tại công
--                        đoạn tạo ra nó (chưa chuyển tiếp đi đâu).
-- Tem thành phẩm CHƯA quét ghi nhận (trang_thai='Chờ đóng gói TP') bị LOẠI
-- HẲN khỏi cả 2 loại — chỉ là nhãn in trước, chưa phải hàng tồn thật.
--
-- Sửa luôn 1 bug của T48: tem thành phẩm (TP...) CHƯA từng "Chuyển công
-- đoạn" (chưa có dòng trong cd_chuyen_cong_doan_log) bị coalesce về "Đúc"
-- sai hoàn toàn — giờ mặc định về đúng công đoạn nó được tạo ra
-- (duc_tem.tram_cong_doan), không phải Đúc.
--
-- Đổi kiểu trả về (thêm cột loai) nên phải DROP trước khi CREATE lại.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

drop function if exists cd_ton_kho_theo_ma_sp(text);

create or replace function cd_ton_kho_theo_ma_sp(p_ma_sp text)
returns table(cong_doan text, loai text, so_luong numeric)
language sql
stable
as $$
  select vi_tri, 'wip'::text as loai, sum(so_luong) as so_luong
  from (
    select coalesce(v.vi_tri_hien_tai, 'Đúc') as vi_tri, t.so_luong
    from duc_tem t
    left join cd_v_vi_tri_hien_tai v on v.tag_no = t.tag_no
    where t.ma_sp = p_ma_sp
      and coalesce(t.so_luong, 0) > 0
      and t.tag_no not like 'TP%'
  ) s
  group by vi_tri

  union all

  select vi_tri, 'tp_da_dong_goi'::text as loai, sum(so_luong) as so_luong
  from (
    select coalesce(v.vi_tri_hien_tai, t.tram_cong_doan) as vi_tri, t.so_luong
    from duc_tem t
    left join cd_v_vi_tri_hien_tai v on v.tag_no = t.tag_no
    where t.ma_sp = p_ma_sp
      and coalesce(t.so_luong, 0) > 0
      and t.tag_no like 'TP%'
      and t.trang_thai = 'Đã đóng gói TP'
  ) s
  group by vi_tri;
$$;

revoke execute on function cd_ton_kho_theo_ma_sp(text) from anon;
grant execute on function cd_ton_kho_theo_ma_sp(text) to authenticated;
