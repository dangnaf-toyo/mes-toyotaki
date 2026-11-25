/* LOT-based dashboard; a LOT is counted once even if several inspections match. */
(() => {
  const root=document.getElementById('iqcDashboard'), panel=document.createElement('section');
  panel.id='iqcMultiDashboard';panel.className='section';
  panel.innerHTML=`<h3>Dashboard IQC</h3><div class="iqc-toolbar">
   <label>Từ ngày<input id="iqcMFrom" type="date"></label><label>Đến ngày<input id="iqcMTo" type="date"></label>
   <label>Nhà cung cấp<input id="iqcMSupplier" type="search"></label><label>Mã SP / NVL<input id="iqcMCode" type="search"></label>
   <label>Tên SP / NVL<input id="iqcMName" type="search"></label><label>Mã LOT<input id="iqcMLot" type="search"></label>
   <label>Người kiểm<input id="iqcMInspector" type="search"></label>
   <label>Kết quả<select id="iqcMResult"><option value="">Tất cả</option><option>OK</option><option>NG</option><option>Chưa kết luận</option></select></label>
   <label>Trạng thái<select id="iqcMProgress"><option value="">Tất cả</option><option>Chưa kiểm</option><option>Đang kiểm</option><option>Đã kiểm hết</option><option>Tạm dừng / Chờ xử lý</option><option>Chưa xác định</option></select></label></div>
   <div id="iqcMultiCards" class="summary"></div><div class="table-wrap"><table><thead><tr><th>Ngày nhận</th><th>Mã LOT</th><th>Model / NVL</th><th>Tổng SL</th><th>Đã kiểm</th><th>OK</th><th>NG</th><th>Còn lại</th><th>Trạng thái</th><th>Kết quả</th><th>Thao tác</th></tr></thead><tbody id="iqcMultiTable"></tbody></table></div>
   <p class="help">Các số lượng PCS chỉ áp dụng kiểm ngoại quan. LOT hóa học và LOT cũ chưa biết số đã kiểm được hiển thị riêng.</p>`;
  root.prepend(panel);
  const get=id=>document.getElementById('iqcM'+id), value=id=>get(id).value.trim(), norm=x=>String(x||'').toLocaleLowerCase('vi'), match=(v,q)=>!q||norm(v).includes(norm(q));
  const td=(row,v)=>{const c=document.createElement('td');c.textContent=String(v??'—');row.append(c);return c;};
  let latest=[];
  function refresh(){
    const {rounds}=IqcMultiEntry.getData();
    const from=value('From'),to=value('To');
    const rows=latest.filter(l=>{
      if(from&&to&&from>to)return false;
      const history=rounds.filter(r=>String(r.lot_id)===String(l.id));
      const dates=history.length?history.map(r=>r.ngay_kiem):[l.method==='hoa_hoc'?l.inspectionDate:l.receivedInput?.slice(0,10)];
      const inPeriod=dates.some(d=>d&&(!from||d>=from)&&(!to||d<=to));
      if((from||to)&&!inPeriod)return false;
      const inspectors=[l.inspector,l.inspectorName,...history.filter(r=>(!from||r.ngay_kiem>=from)&&(!to||r.ngay_kiem<=to)).map(r=>r.nguoi_kiem)].join(' ');
      let t=null;if(l.method!=='hoa_hoc'){try{t=IqcMultiEntry.totals(l);}catch{}}
      return match(l.supplier,value('Supplier'))&&match(l.productCode,value('Code'))&&match(l.productName,value('Name'))&&match(l.lotNo,value('Lot'))&&match(inspectors,value('Inspector'))&&(!value('Result')||(l.result||'Chưa kết luận')===value('Result'))&&(!value('Progress')||t?.progress===value('Progress'));
    });
    const table=document.getElementById('iqcMultiTable');table.replaceChildren();
    let qty=0,checked=0,ok=0,ng=0,remaining=0,unknown=0,waiting=0,doing=0,done=0;
    for(const l of rows){
      const tr=document.createElement('tr');let t=null;
      if(l.method!=='hoa_hoc'){try{t=IqcMultiEntry.totals(l);}catch{}}
      if(t){qty+=t.total;if(t.checked===null)unknown++;else{checked+=t.checked;ok+=t.ok;ng+=t.ng;remaining+=t.remaining;}if(t.progress==='Chưa kiểm')waiting++;if(t.progress==='Đang kiểm')doing++;if(t.progress==='Đã kiểm hết')done++;}
      td(tr,l.receivedDate);td(tr,l.lotNo);td(tr,l.productCode+' · '+l.productName);
      for(const v of t?[t.total,t.checked,t.ok,t.ng,t.remaining,t.progress]:['—','—','—','—','—','Hóa học'])td(tr,v);
      td(tr,l.result||'Chưa kết luận');const actions=td(tr,'');
      const view=document.createElement('button');view.type='button';view.textContent=l.method==='hoa_hoc'?'Xem':'Lịch sử / Tiếp tục kiểm';
      view.onclick=()=>{if(l.method==='hoa_hoc')openDetail(String(l.id));else{showPage('iqc');IqcMultiEntry.continueLot(l.id);}};actions.append(view);
      if(t){const edit=document.createElement('button');edit.type='button';edit.textContent='Sửa LOT';edit.onclick=async()=>{try{const fresh=await IqcApi.getLot(l.id);const amount=prompt('Tổng số lượng LOT:',fresh.lotQty);if(amount===null)return;const supplier=prompt('Nhà cung cấp:',fresh.supplier);if(supplier===null)return;const received=prompt('Ngày giờ nhận (YYYY-MM-DDTHH:mm):',fresh.receivedInput);if(received===null)return;const note=prompt('Ghi chú LOT:',fresh.note||'');if(note===null)return;const r=await sb.rpc('iqc_sua_thong_tin_lot',{p_id:l.id,p_updated_at:fresh.updatedAt,p_lot:{received_at:MesQcFields.iso(received),lot_qty:Number(amount),supplier,note,location:fresh.location}});if(r.error)throw r.error;await loadDashboard();}catch(e){alert(e.message||e);}};actions.append(edit);}
      if(t&&l.multi){const decision=document.createElement('button');decision.type='button';decision.textContent='Kết luận';decision.onclick=async()=>{try{const input=prompt('Nhập OK, NG hoặc để trống để bỏ kết luận:',l.multiConclusion||'');if(input===null)return;const result=input.trim().toUpperCase();if(result&&!['OK','NG'].includes(result))throw Error('Chỉ nhập OK, NG hoặc để trống.');const fresh=await IqcApi.getLot(l.id);const r=await sb.rpc('iqc_danh_gia_lot',{p_id:l.id,p_ket_luan:result||null,p_updated_at:fresh.updatedAt});if(r.error)throw r.error;await loadDashboard();}catch(e){alert(e.message||e);}};actions.append(decision);}
      if(t){const pause=document.createElement('button');pause.type='button';pause.textContent=l.multiPaused?'Tiếp tục LOT':'Tạm dừng';pause.onclick=async()=>{const reason=l.multiPaused?'':prompt('Lý do tạm dừng LOT:');if(reason===null||(!l.multiPaused&&!reason.trim()))return;const r=await sb.rpc('iqc_tam_dung_lot',{p_id:l.id,p_tam_dung:!l.multiPaused,p_ly_do:reason});if(r.error)alert(r.error.message);else await loadDashboard();};actions.append(pause);}
      table.append(tr);
    }
    const cards=document.getElementById('iqcMultiCards');cards.replaceChildren();
    for(const [name,n] of [['Tổng LOT',rows.length],['Chưa kiểm',waiting],['Đang kiểm',doing],['Đã kiểm hết',done],['Tổng SL',qty],['Đã kiểm',checked],['OK',ok],['NG',ng],['Tỷ lệ NG',checked?(ng/checked*100).toFixed(2)+'%':'0%'],['Còn lại',remaining],['Chưa xác định',unknown]]){const card=document.createElement('div');card.className='card';const title=document.createElement('div');title.className='card-title';title.textContent=name;const number=document.createElement('div');number.className='card-number';number.textContent=n;card.append(title,number);cards.append(card);}
  }
  panel.querySelector('.iqc-toolbar').addEventListener('input',refresh);
  panel.querySelector('.iqc-toolbar').addEventListener('change',refresh);
  const previous=renderDashboard;renderDashboard=function(data){previous(data);latest=data.lots||[];refresh();};
  if(IqcWorkspace.getSnapshot()){latest=IqcWorkspace.getSnapshot().lots||[];refresh();}
})();
