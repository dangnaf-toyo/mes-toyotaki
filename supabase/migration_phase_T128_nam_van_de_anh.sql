-- ============================================================================
-- T128: Hộp "Đã nắm thông tin" của trưởng ca khi lên khuôn hiện đủ thông tin +
-- hình ảnh giống khung "Vấn đề lần sản xuất trước" ở màn hình IPQC
-- (duc_ipqc_vd_danh_sach): thêm 'anh' (ảnh IPQC phát hiện vấn đề) và 'lan_truoc'
-- (lần IPQC gần nhất đã trả lời: chưa kiểm được + lý do...).
-- Chỉ thay hàm đọc, không đổi bảng / quyền.
-- ============================================================================
create or replace function duc_khuon_vd_lan_truoc(p_ma_khuon text, p_ma_may text)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare v_ngay date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Cần đăng nhập'); end if;
  return jsonb_build_object('ok', true,
    'bat', coalesce((select gia_tri = 'true'::jsonb from duc_cau_hinh where khoa = 'chan_khuon_chua_nam_van_de'), false),
    'chay_tiep', duc_khuon_dang_tren_may(p_ma_khuon, p_ma_may, v_ngay, null),
    'da_nam', duc_khuon_da_nam_van_de(p_ma_khuon, p_ma_may),
    'van_de', (select coalesce(jsonb_agg(jsonb_build_object(
        'id_van_de', v.id_van_de, 'mo_ta', v.mo_ta, 'ngay_phat_hien', v.ngay_phat_hien, 'ca', v.ca_phat_hien,
        'ma_may', v.ma_may, 'ma_sp', v.ma_sp, 'trang_thai', v.trang_thai, 'noi_dung_xu_ly', v.noi_dung_xu_ly,
        'nguoi_xu_ly', v.nguoi_xu_ly, 'ngay_xu_ly', v.ngay_xu_ly, 'lan_tai_phat', v.lan_tai_phat, 'id_su_co', v.id_su_co,
        'anh', (select c.anh_bang_chung_url from duc_ipqc_checkpoint c where c.id_van_de_lien_quan = v.id_van_de limit 1),
        'lan_truoc', (select jsonb_build_object('ket_qua', x.ket_qua, 'ly_do', x.ly_do, 'nguoi', x.nguoi, 'thoi_diem', x.thoi_diem)
                      from duc_ipqc_vd_xac_nhan x where x.id_van_de = v.id_van_de and x.da_ap_dung order by x.thoi_diem desc limit 1))
        order by v.ngay_phat_hien, v.id_van_de), '[]'::jsonb) from duc_khuon_vd_mo(p_ma_khuon) v));
end $$;
revoke execute on function duc_khuon_vd_lan_truoc(text, text) from public, anon;
grant execute on function duc_khuon_vd_lan_truoc(text, text) to authenticated;
