-- T57: xoá dữ liệu TEST của Đúc Kẽm (máy Kẽm 190T/160T, phát sinh 19–21/09/2026)
-- và Đánh bóng Kẽm (toàn bộ — tính năng mới, chưa có sản lượng thật trước đó).
-- Chạy 1 lần trên Supabase project PRODUCTION.
--
-- Xoá các bảng con tham chiếu duc_tem.tag_no TRƯỚC để tránh lỗi khoá ngoại,
-- sau đó mới xoá dòng duc_tem, rồi dọn trạm hiện tại "Đánh bóng Kẽm".

begin;

create temp table _tem_xoa as
select tag_no from duc_tem
where (
  (may_duc_chi_thi in ('Kẽm 190T', 'Kẽm 160T') or may_tt in ('Kẽm 190T', 'Kẽm 160T'))
  and ngay between '2026-09-19' and '2026-09-21'
)
or tram_cong_doan = 'Đánh bóng Kẽm';

delete from cd_tem_nguon       where tag_no_nguon in (select tag_no from _tem_xoa) or tag_no_moi in (select tag_no from _tem_xoa);
delete from cd_ng_khai_bao     where tag_no       in (select tag_no from _tem_xoa);
delete from duc_tem_nvl_lot    where tag_no       in (select tag_no from _tem_xoa);
delete from duc_tem_tach       where tag_no_cha   in (select tag_no from _tem_xoa) or tag_no_con in (select tag_no from _tem_xoa);
delete from duc_tem_cach_ly    where tag_no       in (select tag_no from _tem_xoa);
delete from oqc_pallet_item    where tag_no       in (select tag_no from _tem_xoa);
delete from bavia_xu_ly_nguon  where tag_no_nguon in (select tag_no from _tem_xoa);
delete from bavia_sua_log      where tag_ng       in (select tag_no from _tem_xoa);
delete from bavia_gom_log      where tag_moi      in (select tag_no from _tem_xoa);

delete from duc_tem where tag_no in (select tag_no from _tem_xoa);

-- Phiên trạm hiện tại của Đánh bóng Kẽm (Line 1/2) — dọn sạch để bắt đầu lại.
delete from cd_tram_hien_tai where cong_doan = 'Đánh bóng Kẽm';

-- Log NG Kanban Đúc Kẽm trong 3 ngày test (nếu có).
delete from duc_kanban_ng_log where ngay between '2026-09-19' and '2026-09-21';

drop table _tem_xoa;

commit;
