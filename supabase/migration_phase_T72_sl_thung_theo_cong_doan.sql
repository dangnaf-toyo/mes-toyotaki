-- ============================================================================
-- Phase T72 — SL/thùng tem thành phẩm khai báo theo MÃ SP × CÔNG ĐOẠN trong
-- Danh mục sản phẩm (quan-ly-danh-muc.html), thay cho hằng số cứng
-- TP_PACKAGING = { "Đánh bóng Kẽm": 60, "OQC": 60 } trong intem.html /
-- ghi-nhan-tem-thanh-pham.html và ô nhập tay SL/thùng của Bavia.
--
-- master_products.sl_thung_cong_doan jsonb — VD {"Đánh bóng Kẽm":60,"OQC":60,"Bavia":36}.
-- Công đoạn chưa khai → không in được tem thành phẩm công đoạn đó cho mã SP đó.
-- KHÁC sl_dong_goi_chuan (quy cách thùng Đúc / tem chỉ thị Kanban — giữ nguyên).
--
-- RPC cd_tao_lo_tem_thanh_pham KHÔNG đổi — vẫn nhận p_sl_thung từ trang in.
-- Chạy trong Supabase SQL Editor. An toàn chạy lại nhiều lần (idempotent).
-- ============================================================================

alter table public.master_products add column if not exists sl_thung_cong_doan jsonb;

-- Điền sẵn đúng số đang dùng (để không chặn in tem của mã đang chạy):
--   - Đánh bóng Kẽm = 60 cho mã có công đoạn này trong quy trình hoặc đã từng in tem TP ở đó
--   - OQC = 60 cho BPH-SHO-* (định mức cũ ghi chú "riêng BPH-SHO 60pcs")
-- Chỉ điền khi khoá đó CHƯA có — không ghi đè số người dùng đã sửa.
update public.master_products p
   set sl_thung_cong_doan = jsonb_build_object('Đánh bóng Kẽm', 60) || coalesce(p.sl_thung_cong_doan, '{}'::jsonb)
 where not (coalesce(p.sl_thung_cong_doan, '{}'::jsonb) ? 'Đánh bóng Kẽm')
   and (
     coalesce(p.quy_trinh_cong_doan, '') like '%Đánh bóng Kẽm%'
     or exists (select 1 from public.duc_tem t
                 where t.ma_sp = p.ma_sp and t.tag_no like 'TP%' and t.tram_cong_doan = 'Đánh bóng Kẽm')
   );

update public.master_products p
   set sl_thung_cong_doan = jsonb_build_object('OQC', 60) || coalesce(p.sl_thung_cong_doan, '{}'::jsonb)
 where not (coalesce(p.sl_thung_cong_doan, '{}'::jsonb) ? 'OQC')
   and p.ma_sp like 'BPH-SHO%';

-- Kiểm tra
select ma_sp, quy_trinh_cong_doan, sl_thung_cong_doan
  from public.master_products
 where sl_thung_cong_doan is not null
 order by ma_sp;
