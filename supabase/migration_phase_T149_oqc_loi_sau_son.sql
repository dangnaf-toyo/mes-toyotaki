-- ============================================================================
-- T149: Danh mục lỗi OQC "Kiểm tra sau Sơn" (phạm vi POST_PAINTING)
-- Trạng thái: Đã chạy STAGING 23/10/2026. Đã chạy PROD 23/10/2026.
-- (Lúc chạy trên Supabase ghi tên migration phase_T145_oqc_loi_sau_son; đổi số T149 vì T145 đã dùng cho Bavia.)
--
-- Tên lỗi lấy theo sheet NHAP_GHE (file nhập kiểm tra ghế sau sơn).
-- Nhãn công đoạn mới 'OQC_SON' = lỗi dùng khi chọn phạm vi "Kiểm tra sau Sơn" ở màn
-- hình Nhập báo cáo ngày OQC. Lỗi không có 'OQC' nên không lẫn vào danh sách kiểm
-- sau gia công, IQC, IPQC và không ảnh hưởng oqc_save_defect_order.
-- "Rỗ khí" dùng lại mã ro_khi sẵn có (thêm 'OQC_SON'); "Lỗi khác" + ghi chú nhập ở mục
-- "Lỗi khác" sẵn có trên form, không thêm mã.
-- Chạy lại nhiều lần không sao (on conflict / array_append có điều kiện).
-- ============================================================================
begin;

insert into public.quality_defect_catalog (code, label, defect_group, processes, is_active, sort_order)
values
  ('son_lom',          'Lõm',              'NG ngoại quan', array['OQC_SON'], true, 200),
  ('son_mun_son',      'Mụn sơn',          'NG ngoại quan', array['OQC_SON'], true, 201),
  ('son_sut_me',       'Sứt mẻ',           'NG ngoại quan', array['OQC_SON'], true, 202),
  ('son_bavia_son',    'Bavia sơn',        'NG ngoại quan', array['OQC_SON'], true, 203),
  ('son_day_mong_son', 'Dày, mỏng sơn',    'NG ngoại quan', array['OQC_SON'], true, 204),
  ('son_thieu_son',    'Thiếu sơn',        'NG ngoại quan', array['OQC_SON'], true, 205),
  ('son_ro_son',       'Rỗ sơn',           'NG ngoại quan', array['OQC_SON'], true, 206),
  ('son_san_son',      'Sần sơn',          'NG ngoại quan', array['OQC_SON'], true, 207),
  ('son_nhan_son',     'Nhăn sơn',         'NG ngoại quan', array['OQC_SON'], true, 208),
  ('son_khac_mau',     'Khác màu',         'NG ngoại quan', array['OQC_SON'], true, 209),
  ('son_tap_chat',     'Tạp chất, dị vật', 'NG ngoại quan', array['OQC_SON'], true, 210),
  ('son_mop_meo_chan', 'Móp méo chân',     'NG ngoại quan', array['OQC_SON'], true, 211),
  ('son_venh_chan',    'Vênh chân',        'NG ngoại quan', array['OQC_SON'], true, 212),
  ('son_dinh_dau',     'Dính dầu',         'NG ngoại quan', array['OQC_SON'], true, 213)
on conflict (code) do nothing;

update public.quality_defect_catalog
set processes = array_append(processes, 'OQC_SON'), updated_at = now()
where code = 'ro_khi' and not ('OQC_SON' = any(processes));

commit;
