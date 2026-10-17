-- ============================================================================
-- T113 — Tài liệu kỹ thuật: gộp "Bản vẽ jig" + "Đồ gá" thành 1 mục
-- "Bản vẽ Jig, đồ gá" (giữ mã ban_ve_jig), thêm mục mới "Bản vẽ linh kiện dự
-- phòng khuôn" (ban_ve_lk_khuon).
--
-- Lúc chạy (2026-10-17) cả 2 project chưa có tài liệu / phân quyền / uỷ quyền
-- / phiếu thay đổi nào ở do_ga — vẫn chuyển tham chiếu sang ban_ve_jig trước
-- khi xoá cho chắc. An toàn chạy lại nhiều lần.
-- ============================================================================

do $$
declare
  v_jig uuid;
  v_ga  uuid;
begin
  select id into v_jig from doc_categories where ma = 'ban_ve_jig';
  select id into v_ga  from doc_categories where ma = 'do_ga';

  update doc_categories set ten = 'Bản vẽ Jig, đồ gá' where id = v_jig;

  if v_ga is not null and v_jig is not null then
    update documents                set category_id = v_jig where category_id = v_ga;
    update document_delegations     set category_id = v_jig where category_id = v_ga;
    update document_change_requests set category_id = v_jig where category_id = v_ga;
    insert into document_permissions (category_id, bo_phan, quyen, created_by)
      select v_jig, bo_phan, quyen, created_by from document_permissions where category_id = v_ga
      on conflict (category_id, bo_phan, quyen) do nothing;
    delete from doc_categories where id = v_ga;   -- document_permissions cũ xoá theo cascade
  end if;
end $$;

insert into doc_categories (ma, ten, thu_tu, cap)
values ('ban_ve_lk_khuon', 'Bản vẽ linh kiện dự phòng khuôn', 4, 'ky_thuat')
on conflict (ma) do update set ten = excluded.ten, thu_tu = excluded.thu_tu, cap = excluded.cap;
