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
  function history(target, log) {
    const entries=String(log || '').split(/\r?\n/).filter(line=>line.trim()).reverse();
    if(!entries.length)return;
    target.append(text('h3','Lịch sử xử lý'));
    const list=document.createElement('ul');
    entries.slice(0,5).forEach(line=>list.append(text('li',line)));target.append(list);
    const button=text('button','Xem toàn bộ lịch sử');button.type='button';
    button.onclick=()=>{
      const dialog=document.createElement('dialog');dialog.className='qc02-viewer';
      dialog.style.cssText='width:min(900px,94vw);max-height:85vh;overflow:auto;border:0;padding:20px;border-radius:10px';
      const close=text('button','Đóng');close.type='button';close.onclick=()=>dialog.close();
      dialog.append(close,text('h2','Lịch sử xử lý'));
      const all=document.createElement('ul');entries.forEach(line=>all.append(text('li',line)));dialog.append(all);
      dialog.onclose=()=>dialog.remove();dialog.onclick=e=>{if(e.target===dialog)dialog.close();};
      document.body.append(dialog);dialog.showModal();close.focus();
    };target.append(button);
  }
  function render(target, c, checkpoint, compactOnly = false) {
    target.replaceChildren();
    const grid=document.createElement('div');grid.className='qc02-record-grid';target.append(grid);
    const groups=[['Thông tin phiếu',['id_ncp','ma_sp','cong_doan','so_luong_ng_du_kien','mo_ta_loi','nguoi_mo_case','ngay_tao']],['Nguyên nhân & Đối sách',['nguyen_nhan_phat_sinh','nguyen_nhan_luu_xuat','nguoi_dam_nhiem_doi_sach','rc_thoi_diem_gui_duyet']],['Xác nhận',['rc_nguoi_duyet','rc_thoi_diem_duyet','rc_trang_thai_duyet','trang_thai']]];
    c={...c,cong_doan:c.cong_doan || checkpoint?.cong_doan || 'Chưa ghi nhận'};
    const used=new Set();for(const [title,keys] of groups){const section=document.createElement('section');section.className='qc02-record-group';section.append(text('h3',title));const data={};for(const key of keys){used.add(key);data[key]=c[key]??'—';}const info=document.createElement('div');record(info,data);section.append(info);
      if(title==='Nguyên nhân & Đối sách')for(const [key,label] of Object.entries(dsLabels)){const entries=c['doi_sach_'+key+'_json'];if(Array.isArray(entries)&&entries.length)section.append(text('p',label+': '+entries.map(item=>item.noi_dung).filter(Boolean).join('; ')));}
      grid.append(section);}
    if(compactOnly)return;
    const other=document.createElement('details');other.className='qc02-other';other.append(text('summary','Thông tin khác'));
    const rest=Object.fromEntries(Object.entries(c).filter(([key])=>!used.has(key)&&key!=='ghi_chu'&&!key.startsWith('doi_sach_')&&!key.startsWith('hinh_anh_')));
    const info=document.createElement('div');record(info,rest);other.append(info);
    if(checkpoint){other.append(text('h3','Thông tin lần kiểm nguồn'));const cp=document.createElement('div');record(cp,checkpoint);other.append(cp);}
    target.append(other);history(target,c.ghi_chu);
  }
  function printable(c, checkpoint, evidence, images, responses, isolation = []) {
    const old = document.getElementById('qc02-print'); if (old) old.remove();
    const root = document.createElement('section'); root.id = 'qc02-print';
    root.append(text('h1', 'TOYOTAKI — PHIẾU XỬ LÝ SẢN PHẨM KHÔNG PHÙ HỢP'));
    root.append(text('h2', c.id_ncp));
    const info = document.createElement('div'); record(info, {id_ncp:c.id_ncp,ma_sp:c.ma_sp,ten_sp:c.ten_sp,cong_doan:c.cong_doan || checkpoint?.cong_doan || 'Chưa ghi nhận',so_luong_ng_du_kien:c.so_luong_ng_du_kien,mo_ta_loi:c.mo_ta_loi,nguoi_mo_case:c.nguoi_mo_case,ngay_tao:c.ngay_tao}); root.append(info);
    root.append(text('h3', 'Ảnh lỗi / bằng chứng kiểm tra')); photos(root, evidence);
    if(c.nguyen_nhan_phat_sinh)root.append(text('p','Nguyên nhân phát sinh: '+c.nguyen_nhan_phat_sinh));
    if(c.nguyen_nhan_luu_xuat)root.append(text('p','Nguyên nhân lưu xuất: '+c.nguyen_nhan_luu_xuat));
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
    root.append(text('h3','Bộ phận liên quan trả lời (viết tay)'));
    for(const [label,height] of [['Nguyên nhân','28mm'],['Đối sách','35mm'],['Người trả lời / Ngày trả lời','14mm'],['Xác nhận','18mm']]){const box=document.createElement('div');box.className='qc02-handwriting';box.style.minHeight=height;box.style.border='1px solid #888';box.style.padding='6px';box.style.marginTop='6px';box.style.breakInside='avoid';box.append(text('b',label));root.append(box);}
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
