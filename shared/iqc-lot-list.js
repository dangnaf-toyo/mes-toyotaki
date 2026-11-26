/* Default IQC landing view: one row per LOT, with separate progress and quality. */
(() => {
  const page=document.getElementById('pageIqc'),form=document.getElementById('formSection');
  const nav=document.createElement('nav');nav.className='iqc-lot-nav';
  nav.innerHTML='<button type="button" class="button btn-secondary" id="iqcListTab">Danh sách LOT</button><button type="button" class="button btn-secondary" id="iqcNewTab">Nhập LOT mới</button><button type="button" class="button btn-secondary" id="iqcDashboardTab">Dashboard IQC</button>';
  const view=document.createElement('section');view.id='iqcLotList';view.className='section';
  view.innerHTML='<h3>Danh sách LOT</h3><div class="iqc-list-filters"><label>Tìm LOT / mã <input id="iqcLotQuick" type="search"></label><label>Nhà cung cấp <input id="iqcLotSupplier" type="search"></label><label>Ngày kiểm <input id="iqcLotStartDate" type="date"></label><label>Ngày hoàn thành <input id="iqcLotEndDate" type="date"></label><label>Tiến độ <select id="iqcLotProgress"><option value="">Tất cả</option><option>Chưa kiểm</option><option>Đang kiểm</option><option>Hoàn thành</option><option>Cần đối soát</option></select></label></div><div class="table-wrap"><table><thead><tr><th>Số LOT</th><th>Mã SP/NVL</th><th>Nhà cung cấp</th><th>Tổng SL</th><th>Đã kiểm</th><th>OK</th><th>NG</th><th>Còn lại</th><th>Bắt đầu kiểm</th><th>Hoàn thành</th><th>Tiến độ</th><th>Kết luận</th><th>Thao tác</th></tr></thead><tbody id="iqcLotRows"></tbody></table></div>';
  const style=document.createElement('style');style.textContent='.iqc-lot-nav{display:flex;gap:8px;margin:12px 0}.iqc-list-view .iqc-report-list{display:none}.iqc-lot-status{display:inline-block;padding:4px 8px;border-radius:5px;font-weight:700}.iqc-lot-status.gray{background:#e5e7eb;color:#374151}.iqc-lot-status.yellow{background:#fef08a;color:#713f12}.iqc-lot-status.green{background:#bbf7d0;color:#14532d}.iqc-lot-status.red{background:#fecaca;color:#7f1d1d}.iqc-lot-status.orange{background:#fed7aa;color:#7c2d12}';document.head.append(style);
  page.prepend(nav,view);
  let data=[];
  function activate(which){const isList=which==='list';view.hidden=!isList;form.hidden=isList;page.classList.toggle('iqc-list-view',isList);document.getElementById('iqcListTab').setAttribute('aria-pressed',String(isList));document.getElementById('iqcNewTab').setAttribute('aria-pressed',String(!isList));}
  function cell(row,v){const d=document.createElement('td');d.textContent=v==null?'—':String(v);row.append(d);return d;}
  function progressOf(lot,t){
    const rows=IqcMultiEntry.getData().rounds.filter(r=>String(r.lot_id)===String(lot.id)&&r.loai!=='so_du_cu');
    const starts=rows.map(r=>r.bat_dau_luc).filter(Boolean).sort(), ends=rows.map(r=>r.ket_thuc_luc).filter(Boolean).sort();
    const target=lot.inspectionType==='Kiểm tra AQL'?Number(lot.multiPlan?.mau_yeu_cau)||null:Number(lot.lotQty)||null;
    const done=!!(t&&t.checked!==null&&target&&t.checked===target);let completed='';
    if(done&&ends.length){let sum=0;for(const r of [...rows].filter(x=>x.ket_thuc_luc).sort((a,b)=>String(a.ket_thuc_luc).localeCompare(String(b.ket_thuc_luc)))){sum+=Number(r.so_kiem)||0;if(sum>=target){completed=r.ket_thuc_luc;break;}}}
    const state=lot.method==='hoa_hoc'?(!lot.chemical&&!lot.inspectionDate?'Chưa kiểm':lot.result==='OK'||lot.result==='NG'?'Hoàn thành':'Đang kiểm'):!t||t.checked===null?'Chưa xác định':t.checked===0?'Chưa kiểm':lot.inspectionType==='Kiểm tra AQL'&&target&&t.checked>target?'Cần đối soát':done?'Hoàn thành':'Đang kiểm';
    return {state,start:starts[0]||'',end:completed,starts};
  }
  function render(){
    const q=document.getElementById('iqcLotQuick').value.trim().toLocaleLowerCase('vi'),body=document.getElementById('iqcLotRows');body.replaceChildren();
    for(const lot of data){if(q&&!`${lot.lotNo} ${lot.productCode} ${lot.productName} ${lot.supplier}`.toLocaleLowerCase('vi').includes(q))continue;
      const tr=document.createElement('tr');let t=null;if(lot.method!=='hoa_hoc'){try{t=IqcMultiEntry.totals(lot);}catch{}}
      const progress=progressOf(lot,t), day=x=>x?new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Ho_Chi_Minh'}).format(new Date(x)):'';
      if(document.getElementById('iqcLotSupplier').value&&!String(lot.supplier||'').toLocaleLowerCase('vi').includes(document.getElementById('iqcLotSupplier').value.toLocaleLowerCase('vi')))continue;
      if(document.getElementById('iqcLotProgress').value&&progress.state!==document.getElementById('iqcLotProgress').value)continue;
      if(document.getElementById('iqcLotStartDate').value&&!progress.starts.some(x=>day(x)===document.getElementById('iqcLotStartDate').value))continue;
      if(document.getElementById('iqcLotEndDate').value&&day(progress.end)!==document.getElementById('iqcLotEndDate').value)continue;
      const date=x=>x?new Intl.DateTimeFormat('vi-VN',{timeZone:'Asia/Ho_Chi_Minh',dateStyle:'short',timeStyle:'short'}).format(new Date(x)):'';
      cell(tr,lot.lotNo);cell(tr,lot.productCode+' · '+lot.productName);cell(tr,lot.supplier);for(const v of t?[t.total,t.checked,t.ok,t.ng,t.remaining]:[lot.chemicalLotQty==null?'—':`${lot.chemicalLotQty} ${lot.chemicalLotUnit}`,'—','—','—','—'])cell(tr,v);
      cell(tr,date(progress.start));cell(tr,date(progress.end));const badge=document.createElement('span');badge.className='iqc-lot-status '+(progress.state==='Hoàn thành'?'green':progress.state==='Đang kiểm'?'yellow':progress.state==='Cần đối soát'?'orange':'gray');badge.textContent=progress.state;cell(tr,'').append(badge);
      const quality=lot.multiPaused?'Chờ xử lý':lot.result==='OK'?'PASS':lot.result==='NG'?'NG':'Chưa kết luận';cell(tr,quality);
      const actions=cell(tr,''),button=(label,handler)=>{const b=document.createElement('button');b.type='button';b.className='button btn-secondary btn-small';b.textContent=label;b.onclick=handler;actions.append(b);};
      button('Xem',()=>openDetail(String(lot.id)));
      if(lot.method!=='hoa_hoc'){button('Tiếp tục kiểm',async()=>{await IqcMultiEntry.continueLot(lot.id);activate('form');});button('Lịch sử',async()=>{await IqcMultiEntry.continueLot(lot.id);activate('form');document.getElementById('iqcMultiHistory').scrollIntoView({block:'nearest'});});}
      else button('Tiếp tục kiểm',async()=>{await editLot(lot.id);activate('form');});
      if(lot.method!=='hoa_hoc')button('Sửa',()=>IqcLotActions.edit(lot.id));else button('Sửa',async()=>{await editLot(lot.id);activate('form');});body.append(tr);
    }
  }
  for(const id of ['iqcLotQuick','iqcLotSupplier','iqcLotStartDate','iqcLotEndDate','iqcLotProgress'])document.getElementById(id).addEventListener('input',render);
  document.getElementById('iqcListTab').onclick=()=>activate('list');
  document.getElementById('iqcNewTab').onclick=()=>{if(IqcMultiEntry.hasUnsaved()&&!confirm('Bỏ dữ liệu chưa lưu để nhập LOT mới?'))return;resetForm();activate('form');};
  document.getElementById('iqcDashboardTab').onclick=()=>showPage('stats');
  const oldRender=renderDashboard;renderDashboard=function(d){oldRender(d);data=d.lots||[];render();};
  const oldShow=showPage;showPage=function(p){oldShow(p);if(p==='iqc')activate('list');};
  const oldEdit=editLot;editLot=async function(id){const result=await oldEdit(id);if(result!==false)activate('form');return result;};
  const oldDefect=openDefect;openDefect=function(){oldDefect();activate('form');};
  const oldEditDefect=editDefect;editDefect=function(id){oldEditDefect(id);activate('form');};
  if(IqcWorkspace.getSnapshot()){data=IqcWorkspace.getSnapshot().lots||[];render();}
  activate('list');
})();
