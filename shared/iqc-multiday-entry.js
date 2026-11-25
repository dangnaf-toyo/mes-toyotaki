/* Entry and history for visual IQC inspections. Chemical IQC keeps its own form. */
(() => {
  const $id = id => document.getElementById(id), form = $id('lotForm');
  const section = document.createElement('section');
  section.id = 'iqcMultiEntry';
  section.className = 'section';
  section.innerHTML = `<h3>Kiểm tra LOT</h3>
    <label>LOT đang kiểm <select id="iqcMultiLot"><option value="">LOT mới</option></select></label>
    <p id="iqcMultiProgress">LOT mới</p>
    <div class="iqc-multi-grid"><label>Ngày kiểm <input id="iqcMultiDate" type="date"></label>
    <label>SL kiểm <input id="iqcMultiChecked" type="number" min="1" step="1"></label>
    <label>OK <input id="iqcMultiOk" type="number" min="0" step="1" value="0"></label>
    <label>NG <input id="iqcMultiNg" type="number" min="0" step="1" value="0"></label></div>
    <h3>Lỗi IQC</h3><datalist id="iqcMultiDefects"></datalist><div id="iqcMultiRows"></div>
    <button type="button" id="iqcMultiAdd" class="button btn-secondary">+ Lỗi khác</button>
    <div id="iqcMultiHistory"></div><p id="iqcMultiStatus" role="status"></p><button type="button" id="iqcMultiRetry" hidden>Tải lại LOT đã lưu</button>`;
  form.querySelector('.iqc-report-side').after(section);
  const style = document.createElement('style');
  style.textContent = '#iqcMultiEntry{padding:12px 14px} .iqc-multi-grid,.iqc-multi-row{display:flex;gap:8px;flex-wrap:wrap;align-items:end} .iqc-multi-grid label,.iqc-multi-row label{display:flex;flex-direction:column;gap:4px} .iqc-multi-row{margin:8px 0}.iqc-is-chemical #iqcMultiEntry,.iqc-report-defects{display:none!important}.iqc-report-defects:has(#defectModal:not(.hidden)){display:block!important}.iqc-is-chemical .iqc-report-defects{display:none!important}';
  document.head.append(style);
  const chemistryHistory=document.createElement('details');chemistryHistory.innerHTML='<summary>Lịch sử kết quả phân tích của LOT</summary><div></div>';
  $id('iqc-chemical-entry').append(chemistryHistory);
  async function loadChemistryHistory(lotId){
    const target=chemistryHistory.querySelector('div');target.replaceChildren();
    if(!lotId)return;
    const q=await sbTaiHet(()=>sb.from('iqc_phan_tich_hoa_hoc_lich_su').select('*').eq('lot_id',lotId).order('id',{ascending:true}));
    if(q.error){target.textContent='Không tải được lịch sử phân tích: '+q.error.message;return;}
    for(const h of q.data||[]){const line=document.createElement('p');const elements=(h.noi_dung?.nguyen_to||[]).map(x=>`${x.element}: ${x.value??'—'} ${x.unit||''} (${x.result||'chưa kết luận'})`).join(' · ');
      line.textContent=`${h.ngay_kiem||'—'} · ${h.inspector||'—'} · ${h.ket_qua||'Chưa kết luận'} · ${elements}`;
      const f=h.noi_dung?.file;if(f?.bucket&&f?.path){const b=document.createElement('button');b.type='button';b.textContent='Xem file';b.onclick=async()=>{const r=await sb.storage.from(f.bucket).createSignedUrl(f.path,60);if(r.error)alert(r.error.message);else window.open(r.data.signedUrl,'_blank','noopener');};line.append(b);}target.append(line);
    }
    if(!target.childNodes.length)target.textContent='Chưa có bản lưu lịch sử mới; kết quả hiện tại vẫn được giữ trong LOT.';
  }
  let lots = [], rounds = [], defects = [], selectedLot = null, editRound = null, requestId = crypto.randomUUID(), saving = false, committedLot = null;
  const today = () => new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Bangkok'}).format(new Date());
  const text = (tag, value) => { const n=document.createElement(tag); n.textContent=value; return n; };
  const field = (label, cls, type='text') => { const l=text('label',label), i=document.createElement('input'); i.className=cls;i.type=type;if(type==='number'){i.min='1';i.step='1';} l.append(i);return l; };
  function addDefect(row={}) {
    const div=document.createElement('div');div.className='iqc-multi-row';
    const name=field('Tên lỗi','name'), detail=field('Chi tiết','detail'), group=field('Nhóm','group'), qty=field('Số lượng','qty','number');
    name.querySelector('input').setAttribute('list','iqcMultiDefects');
    for(const [el,value] of [[name,row.ten_loi],[detail,row.chi_tiet],[group,row.nhom_loi],[qty,row.so_luong]]) el.querySelector('input').value=value ?? '';
    const del=text('button','Xóa');del.type='button';del.className='button btn-secondary';del.onclick=()=>div.remove();
    div.append(name,detail,group,qty,del);$id('iqcMultiRows').append(div);
  }
  $id('iqcMultiAdd').onclick=()=>addDefect();
  function readDefects() { return [...$id('iqcMultiRows').children].map(row=>({ten_loi:row.querySelector('.name').value.trim(),chi_tiet:row.querySelector('.detail').value.trim(),nhom_loi:row.querySelector('.group').value.trim(),so_luong:Number(row.querySelector('.qty').value)})).filter(x=>x.ten_loi || x.chi_tiet || x.nhom_loi || x.so_luong); }
  function totals(lot) {
    const list=rounds.filter(r=>String(r.lot_id)===String(lot.id));
    const legacy=Number(lot.okQty||0)+Number(lot.ngQty||0);
    const known=!list.length && lot.inspectionType==='Kiểm tra 100%' && Number.isSafeInteger(legacy) && legacy>0 && legacy<=lot.lotQty;
    const unknown=!list.length && !known && (lot.status==='Đã kiểm tra' || (lot.inspectionType==='Kiểm tra AQL' && !['Chưa lấy hàng','Đang chờ kiểm'].includes(lot.status)) || lot.okQty || lot.ngQty || (dashboard.defects||[]).some(d=>String(d.lotId)===String(lot.id)));
    const data=known?[{id:'legacy',checked:legacy,ok:lot.okQty,ng:lot.ngQty}]:list.map(r=>({id:r.id,checked:r.so_kiem,ok:r.so_ok,ng:r.so_ng}));
    return IqcInspectionTotals.summarize(lot.lotQty,data,{legacyUnknown:unknown,paused:lot.multiPaused});
  }
  function renderHistory() {
    const target=$id('iqcMultiHistory');target.replaceChildren();
    if(!selectedLot){$id('iqcMultiProgress').textContent='LOT mới';return;}
    const t=totals(selectedLot);
    $id('iqcMultiProgress').textContent=t.checked===null?'Số đã kiểm của LOT cũ chưa xác định. Không tự suy từ cỡ mẫu.':`Tổng ${t.total} · Đã kiểm ${t.checked} · OK ${t.ok} · NG ${t.ng} · Còn ${t.remaining} · ${t.progress}`;
    target.append(text('h4','Lịch sử lần kiểm'));
    const history=rounds.filter(x=>String(x.lot_id)===String(selectedLot.id)).sort((a,b)=>(a.ngay_kiem||'').localeCompare(b.ngay_kiem||'')||a.id-b.id);
    if(!history.length && t.checked)target.append(text('p',`Tổng lịch sử cũ · Kiểm ${t.checked} · OK ${t.ok} · NG ${t.ng} (không có chi tiết từng lần)`));
    const oldDefects=(dashboard.defects||[]).filter(d=>String(d.lotId)===String(selectedLot.id));
    if(oldDefects.length){const p=text('p','Lỗi lưu theo LOT trước đây: '+oldDefects.map(d=>`${d.defectName||d.defectType} (${d.defectQty})`).join(', '));target.append(p);}
    for(const r of history){
      const line=document.createElement('p');line.textContent=`${r.loai==='so_du_cu'?'Tổng lịch sử cũ':r.ngay_kiem+' · '+r.nguoi_kiem} · Kiểm ${r.so_kiem} · OK ${r.so_ok} · NG ${r.so_ng} `;
      if(r.loai==='so_du_cu'){target.append(line);continue;}
      const edit=text('button','Sửa');edit.type='button';edit.onclick=()=>{
        editRound=r;$id('iqcMultiDate').value=r.ngay_kiem;$id('inspector').value=r.nguoi_kiem;
        $id('iqcMultiChecked').value=r.so_kiem;$id('iqcMultiOk').value=r.so_ok;$id('iqcMultiNg').value=r.so_ng;
        $id('iqcMultiRows').replaceChildren();defects.filter(d=>String(d.lan_kiem_id)===String(r.id)).forEach(addDefect);requestId=crypto.randomUUID();$id('iqcMultiStatus').textContent='Đang sửa lần kiểm '+r.id;
      };line.append(edit);
      const details=defects.filter(d=>String(d.lan_kiem_id)===String(r.id));if(details.length){const ul=document.createElement('ul');for(const d of details)ul.append(text('li',`${d.ten_loi} · ${d.chi_tiet||'—'} · ${d.so_luong}`));line.append(ul);}target.append(line);
    }
  }
  function populateLots() {
    const current=$id('iqcMultiLot').value;
    $id('iqcMultiLot').replaceChildren(new Option('LOT mới',''),...lots.filter(l=>l.method!=='hoa_hoc').map(l=>new Option(`${l.lotNo} · ${l.productCode}`,l.id)));
    if([...$id('iqcMultiLot').options].some(o=>o.value===current))$id('iqcMultiLot').value=current;
  }
  function lockLot(locked) {
    for(const id of ['receivedDate','productCode','productName','lotNo','lotQty'])$id(id).readOnly=locked;
    for(const id of ['supplier','iqcScope','inspectionType'])$id(id).disabled=locked;
  }
  const oldGet=IqcApi.getDashboardData.bind(IqcApi);
  IqcApi.getDashboardData=async()=>{
    const [d,rr,dr]=await Promise.all([oldGet(),sbTaiHet(()=>sb.from('iqc_lan_kiem').select('*').order('id')),sbTaiHet(()=>sb.from('iqc_lan_kiem_loi').select('*').order('id'))]);
    if(rr.error||dr.error)throw rr.error||dr.error;
    lots=d.lots;rounds=rr.data||[];defects=dr.data||[];
    for(const lot of lots){ const related=rounds.filter(r=>String(r.lot_id)===String(lot.id)); if(related.length){const t=IqcInspectionTotals.summarize(lot.lotQty,related.map(r=>({id:r.id,checked:r.so_kiem,ok:r.so_ok,ng:r.so_ng})),{paused:lot.multiPaused});const oldNg=related.some(r=>r.loai==='so_du_cu'&&r.ket_luan_cu==='NG');Object.assign(lot,{multi:t,okQty:t.ok,ngQty:t.ng,status:t.progress==='Đã kiểm hết'?'Đã kiểm tra':'Đang kiểm tra',result:t.ng||oldNg?'NG':lot.multiConclusion});} }
    populateLots();if(selectedLot){selectedLot=lots.find(x=>String(x.id)===String(selectedLot.id))||selectedLot;renderHistory();}
    return d;
  };
  async function continueLot(id) {
    const lot=lots.find(l=>String(l.id)===String(id));if(!lot||lot.method==='hoa_hoc')return;
    await editLot(id);selectedLot=lot;lockLot(true);editRound=null;$id('iqcMultiLot').value=String(id);$id('iqcMultiRows').replaceChildren();
    $id('iqcMultiDate').value=today();for(const id of ['iqcMultiChecked','iqcMultiOk','iqcMultiNg'])$id(id).value='';requestId=crypto.randomUUID();renderHistory();$id('formSection').scrollIntoView({behavior:'smooth'});
  }
  const previousEdit=editLot;
  editLot=async id=>{
    if(!IqcChemicalEntry.isChemical())lockLot(false);
    await previousEdit(id);
    const lot=lots.find(l=>String(l.id)===String(id));
    if(lot&&lot.method!=='hoa_hoc'){selectedLot=lot;lockLot(true);editRound=null;requestId=crypto.randomUUID();$id('iqcMultiLot').value=String(id);$id('iqcMultiRows').replaceChildren();$id('iqcMultiDate').value=today();for(const key of ['iqcMultiChecked','iqcMultiOk','iqcMultiNg'])$id(key).value='';renderHistory();}
    else {selectedLot=null;if(lot?.method==='hoa_hoc')await loadChemistryHistory(id);}
  };
  window.addEventListener('iqc-catalog-refreshed',()=>{if(IqcChemicalEntry.isChemical()&&editingId)loadChemistryHistory(editingId).catch(console.error);});
  $id('iqcMultiLot').onchange=async e=>{if(e.target.value)await continueLot(e.target.value);else {resetForm();selectedLot=null;renderHistory();}};
  async function reloadSaved() {
    const d=await IqcApi.getDashboardData();renderDashboard(d);await continueLot(committedLot);
    committedLot=null;$id('iqcMultiRetry').hidden=true;$id('saveBtn').disabled=false;
  }
  $id('iqcMultiRetry').onclick=async()=>{try{await reloadSaved();}catch(e){$id('iqcMultiStatus').textContent='Đã lưu; chưa tải lại được LOT: '+(e.message||e);}};
  form.addEventListener('reset',()=>{selectedLot=null;editRound=null;lockLot(false);requestId=crypto.randomUUID();queueMicrotask(()=>{$id('iqcMultiRows').replaceChildren();$id('iqcMultiDate').value=today();renderHistory();});});
  $id('iqcMultiDate').value=today();
  IqcApi.getAppearanceDefects().then(rows=>$id('iqcMultiDefects').replaceChildren(...rows.map(x=>new Option(x,x)))).catch(console.error);
  form.addEventListener('submit',async e=>{
    if(IqcChemicalEntry.isChemical())return;
    e.preventDefault();e.stopImmediatePropagation();if(saving||committedLot)return;
    try {
      const raw={checked:$id('iqcMultiChecked').value,ok:$id('iqcMultiOk').value,ng:$id('iqcMultiNg').value}, rows=readDefects();
      const createOnly=!selectedLot&&!editRound&&!raw.checked&&!Number(raw.ok)&&!Number(raw.ng)&&!rows.length;
      const amount=createOnly?null:IqcInspectionTotals.inspection(raw);
      if(rows.some(r=>!r.ten_loi||!Number.isSafeInteger(r.so_luong)||r.so_luong<1))throw Error('Nhập tên và số lượng cho từng lỗi.');
      const date=$id('iqcMultiDate').value,inspector=$id('inspector').value.trim();if(!date||!inspector)throw Error('Nhập ngày và người kiểm.');
      const people=await Qc02Data.employees();const person=people.find(p=>p.code+'_'+p.name===inspector);if(!person)throw Error('Chọn người kiểm từ danh mục nhân sự.');
      const lan=createOnly?null:{ngay_kiem:date,nguoi_kiem:inspector,so_kiem:amount.checked,so_ok:amount.ok,so_ng:amount.ng,loi:rows};
      let result;
      saving=true;$id('saveBtn').disabled=true;
      if(editRound) result=await sb.rpc('iqc_sua_lan_kiem',{p_id:editRound.id,p_lan:lan,p_sua_luc:editRound.sua_luc,p_request_id:requestId});
      else {
        let lot=null;
        if(!selectedLot){
          await IqcMaterialCatalog.load(true);const product=IqcMaterialCatalog.resolve($id('productCode').value);if(!product)throw Error('Chọn mã sản phẩm hoặc NVL trong danh mục.');
          if(product.kind==='nvl'&&['nhom','kem'].includes(product.group))throw Error('NVL này cần kiểm hóa học.');
          lot={received_at:MesQcFields.iso($id('receivedDate').value),supplier:$id('supplier').value,product_code:product.code,product_name:product.name,lot_no:$id('lotNo').value,lot_qty:Number($id('lotQty').value),pham_vi:$id('iqcScope').value,doi_tuong:product.kind,ma_nvl:product.kind==='nvl'?product.code:null,inspection_type:$id('inspectionType').value,inspector,nguoi_kiem_id:person.code,nguoi_kiem_ten:person.name};
        }
        result=await sb.rpc('iqc_luu_lan_kiem',{p_lot_id:selectedLot?.id||null,p_lot:lot,p_lan:lan,p_request_id:requestId});
      }
      if(result.error)throw result.error;
      requestId=crypto.randomUUID();editRound=null;committedLot=result.data.lot_id;$id('iqcMultiStatus').textContent='Đã lưu lần kiểm.';
      try{await reloadSaved();}catch(err){$id('iqcMultiRetry').hidden=false;$id('iqcMultiStatus').textContent='Đã lưu; chưa tải lại được LOT: '+(err.message||err);}
    }catch(err){$id('iqcMultiStatus').textContent='Chưa xác nhận được lần lưu: '+(err.message||err)+'. Giữ dữ liệu và thử lại.';}finally{saving=false;$id('saveBtn').disabled=!!committedLot;}
  },true);
  window.IqcMultiEntry={continueLot,totals,getData:()=>({lots,rounds,defects})};
})();
