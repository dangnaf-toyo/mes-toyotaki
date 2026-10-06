/* Read-only NCP detail/printing. Existing save and approval RPCs are unchanged. */
const Qc02Ncp = (() => {
  const labels = {
    id_ncp: 'Số phiếu', ma_sp: 'Mã sản phẩm', ten_sp: 'Tên sản phẩm / model', cong_doan: 'Công đoạn',
    ma_may: 'Máy', so_khuon: 'Số khuôn', mo_ta_loi: 'Nội dung lỗi', ngay_tao: 'Thời gian mở phiếu',
    nguoi_mo_case: 'Người mở phiếu', nguoi_dam_nhiem: 'Người xử lý', nguoi_dam_nhiem_doi_sach: 'Người trả lời',
    so_luong_nghi_van: 'Số lượng nghi vấn', so_luong_ng_du_kien: 'Số lượng NG tham khảo',
    so_luong_da_loc: 'Số lượng đã lọc', so_luong_loc_ok: 'OK sau lọc', so_luong_loc_ng: 'NG sau lọc',
    so_luong_sua_ok: 'Sửa OK', so_luong_phe_da_duyet: 'Phế đã duyệt', vi_tri_cach_ly: 'Vị trí cách ly',
    trang_thai: 'Trạng thái xử lý', rc_trang_thai_duyet: 'Trạng thái duyệt đối sách',
    rc_nguoi_gui_duyet: 'Người gửi duyệt', rc_thoi_diem_gui_duyet: 'Thời gian gửi duyệt',
    rc_nguoi_duyet: 'Người xác nhận', rc_thoi_diem_duyet: 'Thời gian xác nhận', rc_ghi_chu_duyet: 'Ghi chú xác nhận',
    nguyen_nhan_phat_sinh: 'Nguyên nhân phát sinh', nguyen_nhan_luu_xuat: 'Nguyên nhân lưu xuất',
    nguoi_kiem: 'Người phát hiện / kiểm tra', thoi_diem_kiem_thuc_te: 'Thời điểm kiểm tra',
    id_checkpoint_goc: 'Điểm kiểm nguồn', nguoi_de_nghi_phe: 'Người đề nghị phế', ly_do_phe: 'Lý do phế',
    nguoi_loc:'Người lọc',thoi_diem_loc:'Thời gian lọc',phuong_an_ng:'Phương án xử lý NG',
    mo_ta_phuong_an_sua:'Nội dung sửa',so_luong_sua_khong_duoc:'Số lượng không sửa được',
    nguoi_sua:'Người sửa',thoi_diem_sua:'Thời gian sửa',so_phieu_phe:'Số phiếu phế',
    so_luong_de_nghi_phe:'Số lượng đề nghị phế',thoi_diem_de_nghi_phe:'Thời gian đề nghị phế',
    nguoi_duyet_phe:'Người duyệt phế',thoi_diem_duyet_phe:'Thời gian duyệt phế',ket_qua_duyet_phe:'Kết quả duyệt phế',
    ghi_chu:'Ghi chú',last_updated_at:'Lần cập nhật cuối',checklist_json:'Các mục kiểm',
    anh_bang_chung_url:'Liên kết ảnh kiểm tra',loai_kiem:'Loại kiểm',ket_qua:'Kết quả kiểm',
    thoi_diem_tao:'Thời gian yêu cầu kiểm',han_kiem:'Mốc kiểm',ngay:'Ngày',ca:'Ca',
    thoi_gian_kiem_giay:'Thời gian kiểm (giây)',trang_thai_duyet:'Trạng thái duyệt',
    nguoi_phat_hien:'Người phát hiện', tag_no:'Mã tem', task_no:'Số task',id_checkpoint:'Mã điểm kiểm',
  };
  const status = { da_cach_ly:'Đã cách ly',dang_loc:'Đang lọc',cho_quyet_dinh:'Chờ quyết định',dang_sua:'Đang sửa',
    cho_duyet_phe:'Chờ duyệt phế',dong:'Đã xử lý xong',nhap:'Nháp',cho_duyet:'Chờ duyệt',da_duyet:'Đã duyệt',tu_choi:'Từ chối',
    da_kiem:'Đã kiểm',cho_kiem:'Chờ kiểm' };
  const dsLabels = { ps_tam_thoi: 'Đối sách phát sinh tạm thời', ps_lau_dai: 'Đối sách phát sinh lâu dài',
    lx_tam_thoi: 'Đối sách lưu xuất tạm thời', lx_lau_dai: 'Đối sách lưu xuất lâu dài' };
  function text(tag, value) { const el = document.createElement(tag); el.textContent = value ?? '—'; return el; }
  function photos(target, urls) {
    const gallery = document.createElement('div'); gallery.dataset.qcGallery = ''; gallery.className = 'qc02-ncp-photos';
    for (const raw of urls || []) {
      const url = Qc02View.safeUrl(raw, true); if (!url) continue;
      const img = document.createElement('img'); img.src = url; img.alt = 'Ảnh lỗi / bằng chứng'; img.dataset.qcPhoto = '';
      img.style.cssText = 'max-width:160px;max-height:120px;object-fit:contain;margin:6px'; gallery.append(img);
    }
    target.append(gallery);
  }
  function record(target, data) {
    const rows = Object.entries(data || {}).filter(([key]) => !key.startsWith('doi_sach_') && !key.startsWith('hinh_anh_'));
    Qc02View.table(target, ['Thông tin', 'Nội dung'], rows.map(([key, value]) => {
      let display = value && typeof value === 'object' ? JSON.stringify(value) : value ?? '—';
      if(key === 'anh_bang_chung_url') display = (Array.isArray(value) ? value.length : value ? 1 : 0) + ' ảnh (xem phần ảnh bằng chứng)';
      if(key === 'checklist_json' && Array.isArray(value)) display = value.map(item =>
        (item.muc || item.muc_kiem || 'Mục kiểm') + ': ' + (item.dat === true ? 'Đạt' : item.dat === false ? 'Không đạt' : 'Chưa đánh giá')).join('\n');
      if(key.includes('trang_thai')) display = status[value] || display;
      if(typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(value) && !Number.isNaN(Date.parse(value))) {
        display = new Date(value).toLocaleString('vi-VN',{hour12:false,timeZone:'Asia/Ho_Chi_Minh'});
      }
      return [labels[key] || key.replace(/_/g, ' '), display];
    }));
  }
  function render(target, c, checkpoint) {
    target.replaceChildren();
    const base = document.createElement('div'); record(base, { ...c,
      cong_doan:c.cong_doan || (checkpoint && checkpoint.cong_doan) || 'Chưa ghi nhận',
      nguoi_phat_hien:c.nguoi_phat_hien || (checkpoint && checkpoint.nguoi_kiem) || 'Chưa ghi nhận' }); target.append(base);
    if (checkpoint) {
      target.append(text('h3', 'Thông tin lần kiểm phát hiện'));
      const cp = document.createElement('div'); record(cp, checkpoint); target.append(cp);
    }
  }
  function printable(c, checkpoint, evidence, images, responses, isolation = []) {
    const old = document.getElementById('qc02-print'); if (old) old.remove();
    const root = document.createElement('section'); root.id = 'qc02-print';
    root.append(text('h1', 'TOYOTAKI — PHIẾU XỬ LÝ SẢN PHẨM KHÔNG PHÙ HỢP'));
    root.append(text('h2', c.id_ncp));
    const info = document.createElement('div'); render(info, c, checkpoint); root.append(info);
    root.append(text('h3', 'Ảnh lỗi / bằng chứng kiểm tra')); photos(root, evidence);
    for (const [key, title] of [['phat_sinh', 'Ảnh nguyên nhân phát sinh'], ['luu_xuat', 'Ảnh nguyên nhân lưu xuất']]) {
      root.append(text('h3', title)); photos(root, images[key]);
    }
    for (const [key, title] of Object.entries(dsLabels)) {
      root.append(text('h3', title));
      const list = responses[key] || [];
      if (!list.length) root.append(text('p', 'Chưa có đối sách.'));
      list.forEach(item => {
        const block = document.createElement('div'); block.className = 'qc02-response';
        Qc02View.table(block, ['Nội dung', 'Người thực hiện', 'Thời hạn', 'Đánh giá'], [[item.noi_dung, item.nguoi_thuc_hien, item.thoi_han, item.danh_gia]]);
        photos(block, item.hinh_anh); root.append(block);
      });
    }
    root.append(text('p', 'Xác nhận: ' + (c.rc_nguoi_duyet || 'Chưa xác nhận') + ' · ' + (c.rc_thoi_diem_duyet || '—')));
    if(isolation.length) {
      root.append(text('h3','Thông tin tem cách ly'));
      isolation.forEach(row => { const info=document.createElement('div');record(info,row);root.append(info); });
    }
    document.body.append(root); return root;
  }
  async function print(c, checkpoint, evidence, images, responses, isolation = []) {
    const root = printable(c, checkpoint, evidence, images, responses, isolation);
    await Promise.all([...root.querySelectorAll('img')].map(img => img.complete ? Promise.resolve() : new Promise(resolve => {
      const timer = setTimeout(resolve, 8000);
      img.onload = img.onerror = () => { clearTimeout(timer); resolve(); };
    })));
    window.print();
  }
  const style = document.createElement('style');
  style.textContent = '#qc02-print{display:none}@page{size:A4;margin:14mm}@media print{body>*{display:none!important}body>#qc02-print{display:block!important}#qc02-print{font:11px Arial,sans-serif;color:#111}#qc02-print h1{font-size:16px;text-align:center}#qc02-print h2{text-align:center;font-size:14px}#qc02-print h3{margin:14px 0 6px;font-size:12px}#qc02-print .qc02-ncp-photos{margin:6px 0 12px}#qc02-print table{width:100%;border-collapse:collapse;margin:6px 0}#qc02-print td,#qc02-print th{border:1px solid #888;padding:5px;white-space:pre-wrap;overflow-wrap:anywhere}#qc02-print tr,#qc02-print img,.qc02-response{break-inside:avoid}#qc02-print img{max-width:75mm!important;max-height:65mm!important}#qc02-print button{display:none}}';
  document.head.append(style);
  return { render, print, printable, photos };
})();
