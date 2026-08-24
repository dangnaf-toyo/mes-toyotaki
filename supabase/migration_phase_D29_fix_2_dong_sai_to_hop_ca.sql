-- ============================================================================
-- D29 — Sửa tay 2 dòng duc_ca_hien_tai bị sai tổ hợp ca/phuong_an_ca do bug
-- ở submitPlan() (đã sửa trong duc-dashboard.html, commit ac2a8bd).
--
-- 2 dòng DC 10 (23082026_Ca1_DC10_OKA-GWI-02, 23082026_Ca1_DC10_OKA-GJT-02)
-- đang có ca="Ca 1" nhưng phuong_an_ca="2 ca 12h" — tổ hợp không hợp lệ
-- (phương án "2 ca 12h" chỉ có "Ca ngày"/"Ca đêm"). Đây là nguyên nhân trực
-- tiếp khiến "Kết ca" báo lỗi "Không có bản ghi đầy đủ thông tin để lưu" khi
-- header chọn đúng phương án/ca thật nhưng không khớp được dòng nào.
--
-- Sửa: đổi ca của 2 dòng này thành "Ca ngày" (khớp đúng phuong_an_ca đang
-- ghi, và gần đúng khung giờ "Ca 1" cũ 6h-14h nằm trong "Ca ngày" 6h-18h).
-- An toàn chạy lại nhiều lần (idempotent — chỉ update nếu còn sai).
-- ============================================================================

update duc_ca_hien_tai
set ca = 'Ca ngày',
    version = coalesce(version, 0) + 1,
    last_updated_by = 'system@fix_d29',
    last_updated_at = now()
where phuong_an_ca = '2 ca 12h' and ca in ('Ca 1', 'Ca 2');

-- ── Tính lại tt_ca/tt_tuan cho 2 dòng vừa sửa (đổi ca có thể làm sai lệch
--    cách khớp id_dong trong duc_recompute_tt_ca) ───────────────────────────
do $$
declare
  r record;
begin
  for r in
    select distinct ma_may, ma_sp from duc_ca_hien_tai
    where phuong_an_ca = '2 ca 12h' and ca = 'Ca ngày'
      and last_updated_by = 'system@fix_d29'
  loop
    perform duc_recompute_tt_ca(r.ma_may, r.ma_sp);
  end loop;
end $$;
