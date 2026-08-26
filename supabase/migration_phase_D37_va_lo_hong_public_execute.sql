-- ============================================================================
-- D37 — Vá lỗ hổng hệ thống: RPC ghi dữ liệu vẫn gọi được KHÔNG CẦN đăng nhập.
--
-- Phát hiện khi test thủ công duc_rename_khuon/duc_xoa_khuon (D35/D36) bằng
-- anon key qua REST /rpc — cả 2 hàm chạy bình thường dù không có session.
--
-- Nguyên nhân: Postgres mặc định cấp EXECUTE cho PUBLIC (pseudo-role mọi role
-- đều là thành viên, kể cả `anon`) khi tạo hàm mới. Suốt các migration trước
-- giờ chỉ làm `revoke execute ... from anon; grant ... to authenticated;` —
-- câu revoke này CHỈ gỡ quyền gán RIÊNG cho role anon, KHÔNG đụng tới quyền
-- đến từ PUBLIC. Hệ quả: gần như mọi RPC ghi dữ liệu trong toàn hệ thống
-- (Đúc/công đoạn/kho/NVL/OQC/KHSX...) chỉ bị chặn ở lớp giao diện
-- (ensureAuth() trước khi mở form), KHÔNG bị chặn thật ở database — ai cũng
-- có thể gọi thẳng REST /rest/v1/rpc/<tên hàm> bằng publishable/anon key mà
-- không cần đăng nhập.
--
-- Vá: revoke EXECUTE khỏi PUBLIC cho từng hàm ghi dữ liệu đã biết (danh sách
-- v_ten_ham bên dưới, tổng hợp từ mọi `revoke execute ... from anon` có trong
-- các file migration trước D37 + 1 hàm chỉ có `grant ... to authenticated`
-- mà quên revoke từ anon). Dùng pg_proc để lấy ĐÚNG chữ ký (regprocedure)
-- hiện tại của từng overload theo TÊN hàm — tránh phải chép tay chữ ký (rủi
-- ro sai lệch qua nhiều lần đổi tham số), đồng thời tự dọn luôn các overload
-- cũ còn sót lại trong catalog nếu có.
--
-- KHÔNG đụng 2 hàm cố tình cho phép gọi khi CHƯA đăng nhập (đã kiểm tra từng
-- cái, đúng nghiệp vụ cần vậy):
--   - resolve_login_email(text)   — cần gọi TRƯỚC khi có session để đăng nhập
--     bằng username (migration_phase_S2).
--   - cd_truy_xuat_pha_he(text)   — tra cứu phả hệ công khai qua quét QR,
--     không yêu cầu đăng nhập theo thiết kế (migration_phase_T5).
--
-- Cũng không đụng các hàm ĐỌC thuần tuý chưa từng có revoke/grant nào (vd
-- duc_get_ipqc_periodic_due, duc_get_ipqc_due_by_id_dong,
-- duc_get_available_ng_checkpoints_for_ncp, nvl_check_fifo) — đã kiểm tra
-- không có insert/update/delete bên trong, đúng chủ trương "đọc công khai"
-- nhất quán với RLS "public read" của toàn hệ thống, không phải lỗ hổng mới.
--
-- An toàn chạy lại nhiều lần (idempotent) — revoke 1 quyền không tồn tại chỉ
-- là no-op, không báo lỗi.
-- ============================================================================

do $$
declare
  v_ten_ham text[] := array[
    'cd_dong_goi_lai','cd_ghi_chuyen_cong_doan','cd_gop_tally_vao_bao_cao','cd_ket_ca_cong_doan',
    'cd_luu_bao_cao_ca','cd_next_tag_no_dong_goi','cd_tram_doi_ma_sp','cd_tram_ket_thuc',
    'cd_tram_nhap_sanluong','cd_tram_sua','cd_tram_tao','cd_tu_choi_chuyen','cd_xac_nhan_chuyen',
    'danh_sach_nguoi_dung_he_thong',
    'duc_acquire_lock','duc_assign_paired_plan','duc_carry_over_shift','duc_change_product',
    'duc_change_product_paired','duc_clear_incident_open','duc_close_f1_incident_if_open',
    'duc_configure_mold','duc_confirm_mold_issue_outcome','duc_delete_incident','duc_delete_plan',
    'duc_edit_incident','duc_edit_open_incident','duc_end_shift','duc_extend_machine_shift',
    'duc_gan_lot_nvl','duc_ghi_lich_su_bao_duong','duc_ghi_tem','duc_hoan_tac_tach_tem',
    'duc_ipqc_bat_dau_ngay','duc_ipqc_ket_thuc_ngay','duc_ipqc_save_tieu_chuan','duc_ipqc_set_tieu_chuan_pdf',
    'duc_ncp_approve_root_cause','duc_ncp_approve_scrap','duc_ncp_choose_sua','duc_ncp_open_case',
    'duc_ncp_record_repair','duc_ncp_record_sorting','duc_ncp_reopen_root_cause','duc_ncp_request_scrap',
    'duc_ncp_submit_root_cause_for_approval','duc_ncp_update_root_cause','duc_open_incident',
    'duc_record_mold_maintenance','duc_release_lock','duc_rename_khuon','duc_report_mold_issue',
    'duc_request_ipqc_check','duc_resolve_incident','duc_resolve_mold_issue_pending','duc_set_incident_open',
    'duc_submit_ipqc_check','duc_tach_tem','duc_update_mold_shots_from_shift','duc_update_shift_inputs',
    'duc_upsert_plan','duc_xoa_khuon',
    'kho_dong_phieu_xuat','kho_next_phieu_xuat_id','kho_nhap_kho_tem',
    'kho_tao_phieu_xuat','kho_them_vao_phieu_xuat','kho_xoa_khoi_phieu_xuat',
    'khsx_duyet','khsx_ghi_log_sua','khsx_gui_duyet','khsx_tu_choi',
    'nvl_add_transaction','nvl_create_tem','nvl_process_multi_transaction','nvl_recalc_all_plan_stock',
    'nvl_update_opening','nvl_update_plan_nhap','nvl_update_settings','nvl_upsert_material',
    'oqc_dong_pallet','oqc_next_pallet_id','oqc_pallet_nhap_kho','oqc_tao_pallet','oqc_them_tem_vao_pallet'
  ];
  v_ten text;
  r record;
  v_so_ham int := 0;
begin
  foreach v_ten in array v_ten_ham loop
    for r in
      select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = v_ten
    loop
      execute format('revoke execute on function %s from public', r.sig);
      v_so_ham := v_so_ham + 1;
    end loop;
  end loop;
  raise notice 'D37: đã revoke EXECUTE khỏi PUBLIC cho % overload hàm', v_so_ham;
end $$;
