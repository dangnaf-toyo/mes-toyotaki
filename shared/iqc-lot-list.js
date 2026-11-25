/* Default IQC landing view: one row per LOT, with separate progress and quality. */
(() => {
  const page=document.getElementById('pageIqc'),form=document.getElementById('formSection');
  const nav=document.createElement('nav');nav.className='iqc-lot-nav';
  nav.innerHTML='<button type="button" class="button btn-secondary" id="iqcListTab">Danh sách LOT</button><button type="button" class="button btn-secondary" id="iqcNewTab">Nhập LOT mới</button><button type="button" class="button btn-secondary" id="iqcDashboardTab">Dashboard IQC</button>';
  const view=document.createElement('section');view.id='iqcLotList';view.className='section';
  view.innerHTML='<h3>Danh sách LOT</h3><label>Tìm LOT / Model / nhà cung cấp <input id="iqcLotQuick" type="search"></label><div class="table-wrap"><table><thead><tr><th>Số LOT</th><th>Mã SP/NVL</th><th>Nhà cung cấp</th><th>Tổng SL</th><th>Đã kiểm</th><th>Còn lại</th><th>OK</th><th>NG</th><th>Tiến độ / mẫu</th><th>Trạng thái LOT</th><th>Thao tác</th></tr></thead><tbody id="iqcLotRows"></tbody></table></div>';
  const style=document.createElement('style');style.textContent='.iqc-lot-nav{display:flex;gap:8px;margin:12px 0}.iqc-list-view .iqc-report-list{display:none}.iqc-lot-status{display:inline-block;padding:4px 8px;border-radius:5px;font-weight:700}.iqc-lot-status.gray{background:#e5e7eb;color:#374151}.iqc-lot-status.yellow{background:#fef08a;color:#713f12}.iqc-lot-status.green{background:#bbf7d0;color:#14532d}.iqc-lot-status.red{background:#fecaca;color:#7f1d1d}.iqc-lot-status.orange{background:#fed7aa;color:#7c2d12}';document.head.append(style);
  page.prepend(nav,view);
  let data=[];
  function activate(which){const isList=which==='list';view.hidden=!isList;form.hidden=isList;page.classList.toggle('iqc-list-view',isList);document.getElementById('iqcListTab').setAttribute('aria-pressed',String(isList));document.getElementById('iqcNewTab').setAttribute('aria-pressed',String(!isList));}
  function cell(row,v){const d=document.createElement('td');d.textContent=v==null?'—':String(v);row.append(d);return d;}
  function render(){
    const q=document.getElementById('iqcLotQuick').value.trim().toLocaleLowerCase('vi'),body=document.getElementById('iqcLotRows');body.replaceChildren();
    for(const lot of data){if(q&&!`${lot.lotNo} ${lot.productCode} ${lot.productName} ${lot.supplier}`.toLocaleLowerCase('vi').includes(q))continue;
      const tr=document.createElement('tr');let t=null;if(lot.method!=='hoa_hoc'){try{t=IqcMultiEntry.totals(lot);}catch{}}
      cell(tr,lot.lotNo);cell(tr,lot.productCode+' · '+lot.productName);cell(tr,lot.supplier);for(const v of t?[t.total,t.checked,t.remaining,t.ok,t.ng]:[lot.chemicalLotQty==null?'—':`${lot.chemicalLotQty} ${lot.chemicalLotUnit}`,'—','—','—','—'])cell(tr,v);
      let progress=t?.progress||(lot.method==='hoa_hoc'?'Hóa học':'Chưa xác định');if(lot.inspectionType==='Kiểm tra AQL'){const p=IqcMultiEntry.getData().plans.find(x=>String(x.lot_id)===String(lot.id));progress+=p?` · Mẫu ${t?.checked??'—'} / ${p.mau_yeu_cau} (${t?.checked===Number(p.mau_yeu_cau)?'đủ mẫu':t?.checked!=null&&t.checked>Number(p.mau_yeu_cau)?'vượt mẫu, cần đối soát':'chưa đủ mẫu'})`:' · Chưa duyệt mẫu AQL';}cell(tr,progress);const status=IqcLotStatus.describe(lot,t),badge=document.createElement('span');badge.className='iqc-lot-status '+status.color;badge.textContent=status.text;cell(tr,'').append(badge);
      const actions=cell(tr,''),button=(label,handler)=>{const b=document.createElement('button');b.type='button';b.className='button btn-secondary btn-small';b.textContent=label;b.onclick=handler;actions.append(b);};
      button('Xem',()=>openDetail(String(lot.id)));
      if(lot.method!=='hoa_hoc'){button('Tiếp tục kiểm',async()=>{await IqcMultiEntry.continueLot(lot.id);activate('form');});button('Lịch sử',async()=>{await IqcMultiEntry.continueLot(lot.id);activate('form');document.getElementById('iqcMultiHistory').scrollIntoView({block:'nearest'});});}
      else button('Tiếp tục kiểm',async()=>{await editLot(lot.id);activate('form');});
      if(lot.method!=='hoa_hoc')button('Sửa',()=>IqcLotActions.edit(lot.id));else button('Sửa',async()=>{await editLot(lot.id);activate('form');});body.append(tr);
    }
  }
  document.getElementById('iqcLotQuick').addEventListener('input',render);
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
