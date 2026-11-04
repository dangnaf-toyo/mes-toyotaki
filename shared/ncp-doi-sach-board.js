/* Multiple countermeasures per NCP. All identity and timestamps are assigned by the server. */
const NcpDoiSachBoard = (() => {
  const host = document.getElementById('tab-ncp') || document.querySelector('.app');
  if (!host) return;
  const current = new URLSearchParams(location.search).get('id');
  const E = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const time = value => value ? new Date(value).toLocaleString('vi-VN', {timeZone:'Asia/Ho_Chi_Minh',hour12:false}) : 'Chưa ghi nhận (cũ)';
  const type = {noi_bo:'Nội bộ',khach_hang:'Khách hàng'};
  const status = {chua_tra_loi:'Chưa trả lời',da_tra_loi:'Đã trả lời',qua_han:'Quá hạn'};
  const panel = document.createElement('section'); panel.className='panel';
  panel.innerHTML = `<h3>Theo dõi đối sách nội bộ / khách hàng</h3><div style="display:flex;gap:8px;flex-wrap:wrap">
    <label>Loại <select data-type><option value="">Tất cả</option><option value="noi_bo">Nội bộ</option><option value="khach_hang">Khách hàng</option></select></label>
    <label>Trạng thái <select data-status><option value="">Tất cả</option><option value="chua_tra_loi">Chưa trả lời</option><option value="da_tra_loi">Đã trả lời</option><option value="qua_han">Quá hạn</option></select></label>
    <button type="button" class="btn" data-add>Thêm đối sách</button><button type="button" class="btn" data-refresh>Tải lại</button></div>
    <p data-msg role="status"></p><div style="overflow:auto" data-list></div><button class="btn" data-more hidden>Tải thêm</button>`;
  host.append(panel);
  if(current){const history=document.createElement('details');history.innerHTML='<summary>Lịch sử hạn trả lời phiếu</summary><div></div>';panel.append(history);
    sb.from('ncp_lich_su_han').select('*').eq('id_ncp',current).order('id').then(result=>{
      history.querySelector('div').innerHTML=result.error?'Chưa tải được lịch sử.':(result.data||[]).map(x=>`<p>${E(time(x.thoi_diem))} · ${E(x.nguoi_thuc_hien||'Hệ thống')} · ${E(x.han_cu||'Chưa đặt hạn')} → ${E(x.han_moi||'Chưa đặt hạn')}</p>`).join('')||'Chưa có lần thay đổi hạn.';});}
  const dialog=document.createElement('dialog');dialog.style.cssText='width:min(800px,94vw);max-height:90vh;overflow:auto;border:1px solid #cbd5e1;border-radius:10px';
  dialog.innerHTML=`<form><h3>Đối sách</h3><div class="field-row"><label>Mã phiếu <select name="id_ncp" required></select></label></div>
    <div class="field-row"><label>Loại <select name="loai" required><option value="">Chọn loại</option><option value="noi_bo">Nội bộ</option><option value="khach_hang">Khách hàng</option></select></label></div>
    <div class="field-row"><label>Nội dung vấn đề <textarea name="van_de" required></textarea></label></div>
    <div class="field-row"><label>Người phụ trách <input name="nguoi_phu_trach" id="ncp-board-owner"></label></div>
    <div class="field-row"><label>Hạn trả lời (giờ Việt Nam) <input name="han_tra_loi" type="datetime-local" step="1"></label></div>
    <div class="field-row"><label>Nội dung trả lời <textarea name="noi_dung_tra_loi"></textarea></label></div>
    <p data-error role="alert"></p><button class="btn" type="submit">Lưu</button> <button class="btn" type="button" data-close>Đóng</button>
    <h4>Lịch sử thay đổi</h4><div data-history></div></form>`;
  document.body.append(dialog);
  const form=dialog.querySelector('form');let rows=[],selected=null,limit=50;
  Qc02Data.attachEmployees(['ncp-board-owner']);
  async function load(){
    const msg=panel.querySelector('[data-msg]');
    try{
      const result=await sbTaiHet(()=>{let q=sb.from('ncp_doi_sach_theo_doi').select('*').order('id');return current?q.eq('id_ncp',current):q;});
      if(result.error)throw result.error;rows=result.data||[];render();msg.textContent='';
    }catch(e){msg.textContent='Chưa tải được đối sách. Thử lại.';console.error(e);}
  }
  function render(){
    const filtered=rows.filter(r=>(!panel.querySelector('[data-type]').value||r.loai===panel.querySelector('[data-type]').value)&&
      (!panel.querySelector('[data-status]').value||r.trang_thai===panel.querySelector('[data-status]').value));
    panel.querySelector('[data-list]').innerHTML='<table style="width:100%"><thead><tr><th>Phiếu / loại</th><th>Vấn đề</th><th>Phụ trách</th><th>Tạo lúc</th><th>Hạn trả lời</th><th>Trả lời lúc</th><th>Trạng thái</th><th></th></tr></thead><tbody>'+filtered.slice(0,limit).map(r=>
      `<tr><td><a href="ncp-detail.html?id=${encodeURIComponent(r.id_ncp)}">${E(r.id_ncp)}</a><br>${E(type[r.loai]||'Chưa phân loại (cũ)')}</td><td>${E(r.van_de)}</td><td>${E(r.nguoi_phu_trach)}</td><td>${E(time(r.tao_luc))}</td><td>${r.han_tra_loi?E(time(r.han_tra_loi)):'Chưa đặt hạn'}</td><td>${r.noi_dung_tra_loi?E(time(r.tra_loi_luc)):'—'}${r.tra_loi_muon?'<br>Trả lời quá hạn':''}</td><td style="background:${r.trang_thai==='da_tra_loi'?'#dcfce7':r.trang_thai==='qua_han'?'#fee2e2':'#fef3c7'};color:#172033">${E(status[r.trang_thai])}</td><td><button class="btn" type="button" data-edit="${r.id}">Xem / sửa</button></td></tr>`).join('')+'</tbody></table>';
    panel.querySelector('[data-more]').hidden=filtered.length<=limit;
  }
  async function open(row){
    selected=row;form.reset();const cases=await Qc02Data.readAll('duc_ncp');
    form.elements.id_ncp.innerHTML=cases.map(r=>`<option value="${E(r.id_ncp)}">${E(r.id_ncp)}</option>`).join('');
    form.elements.id_ncp.value=row?.id_ncp||current||cases[0]?.id_ncp||'';form.elements.id_ncp.disabled=!!row||!!current;
    for(const key of ['loai','van_de','nguoi_phu_trach','noi_dung_tra_loi'])form.elements[key].value=row?.[key]||'';
    if(row?.han_tra_loi)form.elements.han_tra_loi.value=new Date(new Date(row.han_tra_loi).getTime()+7*3600000).toISOString().slice(0,19);
    dialog.querySelector('[data-error]').textContent='';dialog.querySelector('[data-history]').textContent='';dialog.showModal();
    if(row){const h=await sb.from('ncp_doi_sach_lich_su').select('*').eq('id_doi_sach',row.id).order('id');
      dialog.querySelector('[data-history]').innerHTML=(h.data||[]).map(x=>`<p>${E(time(x.thoi_diem))} · ${E(x.nguoi_thuc_hien||'Hệ thống')}<br>Hạn: ${E(x.du_lieu_cu?.han_tra_loi?time(x.du_lieu_cu.han_tra_loi):'Chưa đặt hạn')} → ${E(x.du_lieu_moi?.han_tra_loi?time(x.du_lieu_moi.han_tra_loi):'Chưa đặt hạn')}</p>`).join('');}
  }
  form.onsubmit=async event=>{event.preventDefault();const button=form.querySelector('[type=submit]');button.disabled=true;
    try{const data=Object.fromEntries(new FormData(form));data.id_ncp=selected?.id_ncp||current||form.elements.id_ncp.value;
      data.han_tra_loi=form.elements.han_tra_loi.value?form.elements.han_tra_loi.value+'+07:00':null;data.cap_nhat_luc=selected?.cap_nhat_luc||null;
      const r=await sb.rpc('ncp_luu_doi_sach',{p_id:selected?.id||null,p_data:data});if(r.error)throw r.error;dialog.close();await load();
    }catch(e){dialog.querySelector('[data-error]').textContent=e.message;}finally{button.disabled=false;}};
  panel.querySelector('[data-add]').onclick=()=>open(null).catch(e=>{panel.querySelector('[data-msg]').textContent='Chưa mở được đối sách. Thử lại.';console.error(e);});
  panel.querySelector('[data-refresh]').onclick=load;dialog.querySelector('[data-close]').onclick=()=>dialog.close();
  panel.onchange=()=>{limit=50;render();};panel.querySelector('[data-more]').onclick=()=>{limit+=50;render();};
  panel.onclick=event=>{const button=event.target.closest('[data-edit]');if(button)open(rows.find(r=>r.id===button.dataset.edit)).catch(console.error);};
  load();setInterval(load,60000);return{refresh:load};
})();
