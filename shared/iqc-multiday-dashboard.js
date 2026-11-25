/* LOT-based dashboard; a LOT is counted once even if several inspections match. */
(() => {
  const root=document.getElementById('iqcDashboard'), panel=document.createElement('section');
  panel.id='iqcMultiDashboard';panel.className='section';
  panel.innerHTML=`<h3>Dashboard IQC</h3><div class="iqc-toolbar">
   <label>Từ ngày<input id="iqcMFrom" type="date"></label><label>Đến ngày<input id="iqcMTo" type="date"></label>
   <label>Nhà cung cấp<input id="iqcMSupplier" type="search"></label><label>Mã SP / NVL<input id="iqcMCode" type="search"></label>
   <label>Tên SP / NVL<input id="iqcMName" type="search"></label><label>Mã LOT<input id="iqcMLot" type="search"></label>
   <label>Người kiểm<input id="iqcMInspector" type="search"></label>
   <label>Kết quả<select id="iqcMResult"><option value="">Tất cả</option><option value="OK">PASS</option><option>NG</option><option>Chưa kết luận</option></select></label>
   <label>Trạng thái<select id="iqcMProgress"><option value="">Tất cả</option><option>Chưa kiểm</option><option>Đang kiểm</option><option>Đủ mẫu</option><option>Đã kiểm hết</option><option>PASS</option><option>NG</option><option>Chờ xử lý</option><option>Chưa xác định</option></select></label></div>
   <div id="iqcMultiCards" class="summary"></div><div class="table-wrap"><table><thead><tr><th>Mã LOT</th><th>Model / NVL</th><th>Tổng SL</th><th>Đã kiểm</th><th>OK</th><th>NG</th><th>Còn lại</th><th>Tiến độ</th><th>Chất lượng</th><th>Thao tác</th></tr></thead><tbody id="iqcMultiTable"></tbody></table></div>
   <p class="help">Các số lượng PCS chỉ áp dụng kiểm ngoại quan. LOT hóa học và LOT cũ chưa biết số đã kiểm được hiển thị riêng.</p>`;
  root.prepend(panel);
  const get=id=>document.getElementById('iqcM'+id), value=id=>get(id).value.trim(), norm=x=>String(x||'').toLocaleLowerCase('vi'), match=(v,q)=>!q||norm(v).includes(norm(q));
  const td=(row,v)=>{const c=document.createElement('td');c.textContent=String(v??'—');row.append(c);return c;};
  const planDialog=document.createElement('dialog');planDialog.innerHTML='<form id="iqcAqlForm"><h3>Duyệt kế hoạch lấy mẫu AQL</h3><p>Theo cấu hình tiêu chuẩn đã được phê duyệt.</p><label>Cỡ mẫu <input id="iqcAqlSample" readonly type="number" min="1" step="1" required></label><label>Ac <input id="iqcAqlAc" readonly type="number" min="0" step="1" required></label><label>Re <input id="iqcAqlRe" readonly type="number" min="1" step="1" required></label><label>Nguồn và phiên bản tiêu chuẩn <input id="iqcAqlSource" readonly required></label><p id="iqcAqlError" role="status"></p><button type="submit" class="button btn-primary">Duyệt kế hoạch</button> <button type="button" id="iqcAqlCancel" class="button btn-secondary">Hủy</button></form>';root.append(planDialog);
  const decisionDialog=document.createElement('dialog');decisionDialog.innerHTML='<form id="iqcDecisionForm"><h3>Kết luận chất lượng LOT</h3><label>Kết luận <select id="iqcDecisionValue"><option value="">Chưa kết luận</option><option value="OK">PASS</option><option value="NG">NG</option></select></label><label>Căn cứ tiêu chuẩn và xử lý <textarea id="iqcDecisionReason" required></textarea></label><p id="iqcDecisionError" role="status"></p><button type="submit" class="button btn-primary">Lưu kết luận</button> <button type="button" id="iqcDecisionCancel" class="button btn-secondary">Hủy</button></form>';root.append(decisionDialog);
  const dialogStyle=document.createElement('style');dialogStyle.textContent='#iqcDashboard dialog{border:0;border-radius:10px;padding:20px;max-width:480px;width:90%;box-shadow:0 8px 32px #0004}#iqcDashboard dialog::backdrop{background:#0008}#iqcDashboard dialog label{display:block;margin:10px 0}#iqcDashboard dialog input,#iqcDashboard dialog select,#iqcDashboard dialog textarea{display:block;width:100%}';document.head.append(dialogStyle);
  let planLot=null,decisionLot=null;
  document.getElementById('iqcAqlCancel').onclick=()=>planDialog.close();document.getElementById('iqcDecisionCancel').onclick=()=>decisionDialog.close();
  document.getElementById('iqcAqlForm').onsubmit=async e=>{e.preventDefault();const button=e.submitter;button.disabled=true;try{const fresh=await IqcApi.getLot(planLot),r=await sb.rpc('iqc_duyet_ke_hoach_aql',{p_id:fresh.id,p_mau:Number(document.getElementById('iqcAqlSample').value),p_ac:Number(document.getElementById('iqcAqlAc').value),p_re:Number(document.getElementById('iqcAqlRe').value),p_nguon:document.getElementById('iqcAqlSource').value,p_updated_at:fresh.updatedAt});if(r.error)throw r.error;planDialog.close();await loadDashboard();}catch(err){document.getElementById('iqcAqlError').textContent=err.message||err;}finally{button.disabled=false;}};
  document.getElementById('iqcDecisionForm').onsubmit=async e=>{e.preventDefault();const button=e.submitter;button.disabled=true;try{const fresh=await IqcApi.getLot(decisionLot),r=await sb.rpc('iqc_phan_quyet_lot',{p_id:fresh.id,p_ket_luan:document.getElementById('iqcDecisionValue').value||null,p_updated_at:fresh.updatedAt,p_ly_do:document.getElementById('iqcDecisionReason').value});if(r.error)throw r.error;decisionDialog.close();await loadDashboard();}catch(err){document.getElementById('iqcDecisionError').textContent=err.message||err;}finally{button.disabled=false;}};
  let latest=[];
  function refresh(){
    const {rounds}=IqcMultiEntry.getData();
    const from=value('From'),to=value('To');
    const rows=latest.filter(l=>{
      if(from&&to&&from>to)return false;
      const history=rounds.filter(r=>String(r.lot_id)===String(l.id));
      const dates=history.length?history.map(r=>r.ngay_kiem):[l.method==='hoa_hoc'?l.inspectionDate:l.registeredInput?.slice(0,10)];
      const inPeriod=dates.some(d=>d&&(!from||d>=from)&&(!to||d<=to));
      if((from||to)&&!inPeriod)return false;
      const inspectors=[l.inspector,l.inspectorName,...history.filter(r=>(!from||r.ngay_kiem>=from)&&(!to||r.ngay_kiem<=to)).map(r=>r.nguoi_kiem)].join(' ');
      let t=null;if(l.method!=='hoa_hoc'){try{t=IqcMultiEntry.totals(l);}catch{}}
      const state=IqcLotStatus.describe(l,t).text;const selected=value('Progress');const statusMatch=!selected||(selected==='Đủ mẫu'?state.startsWith('ĐỦ MẪU'):['PASS','NG','Chờ xử lý'].includes(selected)?state===selected.toLocaleUpperCase('vi'):t?.progress===selected);
      return match(l.supplier,value('Supplier'))&&match(l.productCode,value('Code'))&&match(l.productName,value('Name'))&&match(l.lotNo,value('Lot'))&&match(inspectors,value('Inspector'))&&(!value('Result')||(l.result||'Chưa kết luận')===value('Result'))&&statusMatch;
    });
    const table=document.getElementById('iqcMultiTable');table.replaceChildren();
    let qty=0,checked=0,ok=0,ng=0,remaining=0,unknown=0,waiting=0,doing=0,done=0,pass=0,reject=0,held=0;
    for(const l of rows){
      const tr=document.createElement('tr');let t=null;
      if(l.method!=='hoa_hoc'){try{t=IqcMultiEntry.totals(l);}catch{}}
      if(t){qty+=t.total;if(t.checked===null)unknown++;else{checked+=t.checked;ok+=t.ok;ng+=t.ng;remaining+=t.remaining;}if(t.progress==='Chưa kiểm')waiting++;if(t.progress==='Đang kiểm')doing++;if(t.progress==='Đã kiểm hết')done++;}
      td(tr,l.lotNo);td(tr,l.productCode+' · '+l.productName);
      for(const v of t?[t.total,t.checked,t.ok,t.ng,t.remaining,(l.inspectionType==='Kiểm tra AQL'&&l.multiPlan&&t.checked===Number(l.multiPlan.mau_yeu_cau))?'Đủ mẫu':t.progress]:[l.chemicalLotQty==null?'—':`${l.chemicalLotQty} ${l.chemicalLotUnit}`,'—','—','—','—','Hóa học'])td(tr,v);
      const state=IqcLotStatus.describe(l,t);if(state.text==='PASS')pass++;else if(state.text==='NG')reject++;else if(state.text==='CHỜ XỬ LÝ')held++;
      if(!t&&state.text==='CHƯA KIỂM')waiting++;
      const badge=document.createElement('span');badge.className='iqc-lot-status '+state.color;badge.textContent=state.text;td(tr,'').append(badge);const actions=td(tr,'');
      const view=document.createElement('button');view.type='button';view.textContent=l.method==='hoa_hoc'?'Xem':'Lịch sử / Tiếp tục kiểm';
      view.onclick=()=>{if(l.method==='hoa_hoc')openDetail(String(l.id));else{showPage('iqc');IqcMultiEntry.continueLot(l.id);}};actions.append(view);
      if(t){const edit=document.createElement('button');edit.type='button';edit.textContent='Sửa LOT';edit.onclick=()=>IqcLotActions.edit(l.id);actions.append(edit);}
      if(t&&l.multi){const decision=document.createElement('button');decision.type='button';decision.textContent='Kết luận';decision.onclick=()=>{decisionLot=l.id;document.getElementById('iqcDecisionValue').value=l.multiConclusion||'';document.getElementById('iqcDecisionReason').value='';document.getElementById('iqcDecisionError').textContent='';decisionDialog.showModal();};actions.append(decision);}
      if(t&&l.inspectionType==='Kiểm tra AQL'){const plan=document.createElement('button');plan.type='button';plan.textContent='Duyệt mẫu AQL';plan.onclick=async()=>{planLot=l.id;document.getElementById('iqcAqlForm').reset();const err=document.getElementById('iqcAqlError'),submit=document.querySelector('#iqcAqlForm button[type=submit]');err.textContent='Đang tra cứu…';submit.disabled=true;planDialog.showModal();try{const r=await sb.rpc('iqc_tra_ke_hoach_aql',{p_id:l.id});if(r.error)throw r.error;if(!r.data){err.textContent='Chưa có kế hoạch lấy mẫu';return;}const p=r.data;document.getElementById('iqcAqlSample').value=p.mau_yeu_cau;document.getElementById('iqcAqlAc').value=p.ac;document.getElementById('iqcAqlRe').value=p.re;document.getElementById('iqcAqlSource').value=p.nguon+' · '+p.phien_ban;err.textContent='Mã '+p.ma_chu+' · Level '+p.cap_do+' · AQL '+p.aql;submit.disabled=false;}catch(e){err.textContent=e.message||String(e);}};actions.append(plan);}
      if(t){const pause=document.createElement('button');pause.type='button';pause.textContent=l.multiPaused?'Tiếp tục LOT':'Tạm dừng';pause.onclick=async()=>{const reason=l.multiPaused?'':prompt('Lý do tạm dừng LOT:');if(reason===null||(!l.multiPaused&&!reason.trim()))return;const r=await sb.rpc('iqc_tam_dung_lot',{p_id:l.id,p_tam_dung:!l.multiPaused,p_ly_do:reason});if(r.error)alert(r.error.message);else await loadDashboard();};actions.append(pause);}
      table.append(tr);
    }
    const cards=document.getElementById('iqcMultiCards');cards.replaceChildren();
    for(const [name,n] of [['Tổng LOT',rows.length],['Chưa kiểm',waiting],['Đang kiểm',doing],['PASS',pass],['LOT NG',reject],['Chờ xử lý',held],['Tổng SL',qty],['Đã kiểm',checked],['OK',ok],['PCS NG',ng],['Tỷ lệ NG',checked?(ng/checked*100).toFixed(2)+'%':'0%'],['Còn lại',remaining],['Chưa xác định',unknown]]){const card=document.createElement('div');card.className='card';const title=document.createElement('div');title.className='card-title';title.textContent=name;const number=document.createElement('div');number.className='card-number';number.textContent=n;card.append(title,number);cards.append(card);}
  }
  panel.querySelector('.iqc-toolbar').addEventListener('input',refresh);
  // Text input already refreshes on input; a second refresh on blur would
  // replace a row between pointer-down and click on its action buttons.
  const previous=renderDashboard;renderDashboard=function(data){previous(data);latest=data.lots||[];refresh();};
  if(IqcWorkspace.getSnapshot()){latest=IqcWorkspace.getSnapshot().lots||[];refresh();}
})();
