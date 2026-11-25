/* Entry and history for visual IQC inspections. Chemical IQC keeps its own form. */
(() => {
  const $id = id => document.getElementById(id), form = $id('lotForm');
  const section = document.createElement('section');
  section.id = 'iqcMultiEntry';
  section.className = 'section';
  section.innerHTML = `<h3>Kiểm tra LOT</h3>
    <label>LOT đang kiểm <select id="iqcMultiLot"><option value="">LOT mới</option></select></label>
    <p id="iqcMultiProgress">LOT mới</p>
    <div class="iqc-multi-grid"><label>Thời gian bắt đầu <input id="iqcMultiStart" readonly></label><label>Thời gian hoàn thành <input id="iqcMultiEnd" readonly></label><input id="iqcMultiDate" type="hidden">
    <label>SL kiểm <input id="iqcMultiChecked" type="number" min="1" step="1"></label>
    <label>OK <input id="iqcMultiOk" type="number" min="0" step="1" value="0"></label>
    <label>NG <input id="iqcMultiNg" type="number" min="0" step="1" value="0"></label></div>
    <h3>Lỗi IQC</h3><input id="iqcMultiDefectSearch" type="search" placeholder="Tìm lỗi IQC"><p id="iqcMultiCatalogStatus" class="help"></p><datalist id="iqcMultiDefects"></datalist><div class="iqc-multi-head"><b>Tên lỗi</b><b>Chi tiết / vị trí</b><b>Nhóm</b><b>SL lỗi</b></div><div id="iqcMultiRows"></div>
    <button type="button" id="iqcMultiAdd" class="button btn-secondary">+ Lỗi khác</button>
    <div id="iqcMultiHistory"></div><p id="iqcMultiStatus" role="status"></p><button type="button" id="iqcMultiRetry" hidden>Tải lại LOT đã lưu</button>`;
  form.querySelector('.iqc-report-side').after(section);
  const style = document.createElement('style');
  style.textContent = '#iqcMultiEntry{padding:12px 14px}.iqc-multi-grid{display:flex;gap:8px;flex-wrap:wrap;align-items:end}.iqc-multi-grid label{display:flex;flex-direction:column;gap:4px}.iqc-multi-head,.iqc-multi-row{display:grid;grid-template-columns:minmax(140px,2fr) minmax(130px,2fr) minmax(100px,1fr) 85px 65px;gap:6px;align-items:center}.iqc-multi-head{font-size:11px;color:var(--text-muted)}.iqc-multi-row{margin:3px 0}.iqc-multi-row[hidden]{display:none}.iqc-multi-row label{font-size:0}.iqc-multi-row input{width:100%;font-size:13px}.iqc-is-chemical #iqcMultiEntry,.iqc-report-defects{display:none!important}.iqc-report-defects:has(#defectModal:not(.hidden)){display:block!important}.iqc-is-chemical .iqc-report-defects{display:none!important}.iqc-hide-received{display:none!important}@media(max-width:700px){.iqc-multi-head{display:none}.iqc-multi-row{grid-template-columns:1fr 1fr;gap:4px;padding:5px 0;border-bottom:1px solid #ddd}.iqc-multi-row label{font-size:11px}.iqc-multi-row input{display:block}}';
  document.head.append(style);
  $id('receivedDate').required=false;
  $id('receivedDate').closest('.field').classList.add('iqc-hide-received');
  for(const id of ['pickupDate','completionDate'])$id(id).closest('.field').classList.add('iqc-hide-received');
  $id('inspector').required=false;
  $id('inspector').closest('.field').querySelector('label').textContent='Người kiểm (khi kiểm)';
  $id('inspectionType').required=false;
  $id('inspectionType').closest('.field').querySelector('label').textContent='Hình thức kiểm';
  if(!$id('inspectionType').value)$id('inspectionType').value='Kiểm tra 100%';

  $id('sampleQty').closest('.field').classList.add('iqc-hide-received');
  for(const id of ['resultField','okQtyField','ngQtyField','okPctField','ngPctField'])$id(id).classList.add('iqc-hide-received');
  const chemistryHistory=document.createElement('details');chemistryHistory.innerHTML='<summary>Lịch sử kết quả phân tích của LOT</summary><div></div>';
  $id('iqc-chemical-entry').append(chemistryHistory);
  const chemistryRegister=document.createElement('div');chemistryRegister.innerHTML='<h4>Đăng ký LOT chưa phân tích</h4><label>Số lượng LOT <input id="iqcChemLotQty" type="number" min="0.001" step="any"></label> <label>Đơn vị <select id="iqcChemLotUnit"><option value="kg">kg</option><option value="PCS">PCS</option><option value="tấn">tấn</option></select></label> <button type="button" id="iqcChemRegister">Đăng ký LOT</button><p id="iqcChemRegisterStatus" role="status"></p>';
  $id('iqc-chemical-entry').prepend(chemistryRegister);
  let chemistryRegisterId=crypto.randomUUID(),chemistryRegisterBusy=false;
  $id('iqcChemRegister').onclick=async()=>{
    if(chemistryRegisterBusy)return;
    try{
      await IqcMaterialCatalog.load(true);const item=IqcMaterialCatalog.resolve($id('productCode').value),qty=Number($id('iqcChemLotQty').value);
      if(!item||item.kind!=='nvl'||!['nhom','kem'].includes(item.group))throw Error('Chọn mã Nhôm/Kẽm trong danh mục.');
      if(!$id('lotNo').value.trim()||!$id('iqcChemSupplier').value.trim()||!Number.isFinite(qty)||qty<=0)throw Error('Nhập LOT, nhà cung cấp và số lượng.');
      chemistryRegisterBusy=true;$id('iqcChemRegister').disabled=true;
      const r=await sb.rpc('iqc_dang_ky_lot_hoa_hoc',{p_request_id:chemistryRegisterId,p_ma_nvl:item.code,p_lot_no:$id('lotNo').value.trim(),p_supplier:$id('iqcChemSupplier').value.trim(),p_so_luong:qty,p_don_vi:$id('iqcChemLotUnit').value});
      if(r.error)throw r.error;
      $id('iqcChemRegisterStatus').textContent='Đã đăng ký LOT chưa kiểm.';
      chemistryRegisterId=crypto.randomUUID();resetForm();await loadDashboard();showPage('iqc');
    }catch(e){$id('iqcChemRegisterStatus').textContent='Chưa xác nhận được đăng ký: '+(e.message||e)+'. Giữ dữ liệu và thử lại.';}finally{chemistryRegisterBusy=false;$id('iqcChemRegister').disabled=false;}
  };
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
  let lots = [], rounds = [], defects = [], plans = [], catalog = [], selectedLot = null, editRound = null, requestId = crypto.randomUUID(), saving = false, committedLot = null;
  let startId=null,startPromise=null,startEpoch=0,dirtyVisual=false;
  const today = () => new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Bangkok'}).format(new Date());
  const displayTime = value => value ? new Intl.DateTimeFormat('vi-VN',{timeZone:'Asia/Ho_Chi_Minh',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false}).format(new Date(value)) : 'Chưa xác định';
  function resetStart(){startEpoch++;startId=null;startPromise=null;$id('iqcMultiStart').value='';$id('iqcMultiEnd').value='';}
  async function ensureStarted(){
    if(editRound)return;
    if(startPromise)return startPromise;
    const epoch=startEpoch,id=crypto.randomUUID(),lotId=selectedLot?.id||null;startId=id;
    startPromise=(async()=>{const r=await sb.rpc('iqc_bat_dau_lan_kiem',{p_id:id,p_lot_id:lotId});if(r.error)throw r.error;if(epoch!==startEpoch)throw Error('LOT đã thay đổi; bắt đầu lại lần kiểm.');$id('iqcMultiStart').value=displayTime(r.data.bat_dau_luc);return id;})();
    try{return await startPromise;}catch(e){if(epoch===startEpoch){startId=null;startPromise=null;}throw e;}
  }
  section.addEventListener('focusin',e=>{if(IqcChemicalEntry.isChemical()||editRound||!e.target.matches('#iqcMultiChecked,#iqcMultiOk,#iqcMultiNg,#iqcMultiRows input'))return;ensureStarted().catch(err=>{$id('iqcMultiStatus').textContent='Không bắt đầu được lần kiểm: '+(err.message||err);});});
  form.addEventListener('input',e=>{if(!IqcChemicalEntry.isChemical() && !['iqcMultiDefectSearch','iqcMultiLot'].includes(e.target.id))dirtyVisual=true;});
  const text = (tag, value) => { const n=document.createElement(tag); n.textContent=value; return n; };
  const field = (label, cls, type='text') => { const l=text('label',label), i=document.createElement('input'); i.className=cls;i.type=type;if(type==='number'){i.min='1';i.step='1';} l.append(i);return l; };
  function addDefect(row={}) {
    const div=document.createElement('div');div.className='iqc-multi-row';
    const name=field('Tên lỗi','name'), detail=field('Chi tiết','detail'), group=field('Nhóm','group'), qty=field('Số lượng','qty','number');
    name.querySelector('input').setAttribute('list','iqcMultiDefects');
    for(const [el,value] of [[name,row.ten_loi],[detail,row.chi_tiet],[group,row.nhom_loi],[qty,row.so_luong]]) el.querySelector('input').value=value ?? '';
    if(row.catalog){div.dataset.catalog='1';name.querySelector('input').readOnly=true;group.querySelector('input').readOnly=true;qty.querySelector('input').min='0';qty.querySelector('input').value=row.so_luong??0;}
    const del=text('button','Xóa');del.type='button';del.className='button btn-secondary';del.onclick=()=>div.remove();
    if(row.catalog)del.hidden=true;
    div.append(name,detail,group,qty,del);$id('iqcMultiRows').append(div);
  }
  $id('iqcMultiAdd').onclick=()=>addDefect();
  function readDefects() { return [...$id('iqcMultiRows').children].map(row=>({catalog:!!row.dataset.catalog,ten_loi:row.querySelector('.name').value.trim(),chi_tiet:row.querySelector('.detail').value.trim(),nhom_loi:row.querySelector('.group').value.trim(),so_luong:Number(row.querySelector('.qty').value)})).filter(x=>x.catalog ? x.so_luong!==0 : (x.ten_loi || x.chi_tiet || x.nhom_loi || x.so_luong)).map(({catalog,...x})=>x); }
  function resetDefects(saved=[]) {
    $id('iqcMultiRows').replaceChildren();
    const rest=[...saved];
    for(const c of catalog){const i=rest.findIndex(x=>x.ten_loi===c.label && (x.nhom_loi||'')===(c.defect_group||''));const previous=i>=0?rest.splice(i,1)[0]:{};addDefect({ten_loi:c.label,nhom_loi:c.defect_group,so_luong:0,...previous,catalog:true});}
    rest.forEach(addDefect);
  }
  $id('iqcMultiDefectSearch').addEventListener('input',()=>{const q=$id('iqcMultiDefectSearch').value.toLocaleLowerCase('vi');for(const row of $id('iqcMultiRows').children)row.hidden=!!q&&!row.querySelector('.name').value.toLocaleLowerCase('vi').includes(q);});
  async function loadDefectCatalog(){
    const r=await sbTaiHet(()=>sb.from('quality_defect_catalog').select('label,defect_group').contains('processes',['IQC']).eq('is_active',true).order('sort_order').order('label'));
    if(r.error)throw r.error;
    const map=new Map();for(const x of r.data||[]){const label=String(x.label||'').trim();if(!label)continue;const key=(label+'|'+(x.defect_group||'')).toLocaleLowerCase('vi');if(!map.has(key))map.set(key,{...x,label});}
    catalog=[...map.values()];$id('iqcMultiDefects').replaceChildren(...catalog.map(x=>new Option(x.label,x.label)));
    $id('iqcMultiCatalogStatus').textContent=catalog.length?'Danh mục lỗi IQC · '+catalog.length+' loại':'Chưa có lỗi IQC trong danh mục MES.';
    if(!$id('iqcMultiRows').children.length)resetDefects();
    else for(const c of catalog){const found=[...$id('iqcMultiRows').children].some(row=>row.querySelector('.name').value.trim()===c.label&&row.querySelector('.group').value.trim()===(c.defect_group||''));if(!found)addDefect({ten_loi:c.label,nhom_loi:c.defect_group,so_luong:0,catalog:true});}
  }
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
    if(selectedLot.inspectionType==='Kiểm tra AQL'){const p=plans.find(x=>String(x.lot_id)===String(selectedLot.id));$id('iqcMultiProgress').textContent+=p?` · Level ${p.cap_do} / AQL ${p.aql} · Mẫu ${p.mau_yeu_cau} · Ac ${p.ac} / Re ${p.re} · ${t.checked===null?'Chưa xác định':t.checked===Number(p.mau_yeu_cau)?'Đủ mẫu':t.checked>Number(p.mau_yeu_cau)?'Vượt mẫu — cần đối soát':'Chưa đủ mẫu'}`:' · Chưa có kế hoạch lấy mẫu';}
    target.append(text('h4','Lịch sử lần kiểm'));
    const history=rounds.filter(x=>String(x.lot_id)===String(selectedLot.id)).sort((a,b)=>(a.ngay_kiem||'').localeCompare(b.ngay_kiem||'')||a.id-b.id);
    if(!history.length && t.checked)target.append(text('p',`Tổng lịch sử cũ · Kiểm ${t.checked} · OK ${t.ok} · NG ${t.ng} (không có chi tiết từng lần)`));
    const oldDefects=(dashboard.defects||[]).filter(d=>String(d.lotId)===String(selectedLot.id));
    if(oldDefects.length){const p=text('p','Lỗi lưu theo LOT trước đây: '+oldDefects.map(d=>`${d.defectName||d.defectType} (${d.defectQty})`).join(', '));target.append(p);}
    for(const r of history){
      const line=document.createElement('p');line.textContent=`${r.loai==='so_du_cu'?'Tổng lịch sử cũ':displayTime(r.bat_dau_luc)+' → '+displayTime(r.ket_thuc_luc)+' · '+r.nguoi_kiem} · Kiểm ${r.so_kiem} · OK ${r.so_ok} · NG ${r.so_ng} `;
      if(r.loai==='so_du_cu'){target.append(line);continue;}
      const edit=text('button','Sửa');edit.type='button';edit.onclick=()=>{
        resetStart();editRound=r;$id('iqcMultiDate').value=r.ngay_kiem;$id('inspector').value=r.nguoi_kiem;$id('iqcMultiStart').value=displayTime(r.bat_dau_luc);$id('iqcMultiEnd').value=displayTime(r.ket_thuc_luc);
        $id('iqcMultiChecked').value=r.so_kiem;$id('iqcMultiOk').value=r.so_ok;$id('iqcMultiNg').value=r.so_ng;
        resetDefects(defects.filter(d=>String(d.lan_kiem_id)===String(r.id)));requestId=crypto.randomUUID();$id('iqcMultiStatus').textContent='Đang sửa lần kiểm '+r.id;
      };line.append(edit);
      const editTime=text('button','Sửa thời gian');editTime.type='button';editTime.onclick=async()=>{try{const start=prompt('Bắt đầu thực tế (YYYY-MM-DDTHH:mm:ss, giờ Việt Nam):');if(start===null)return;const end=prompt('Hoàn thành thực tế (YYYY-MM-DDTHH:mm:ss, giờ Việt Nam):');if(end===null)return;const reason=prompt('Lý do sửa:');if(reason===null)return;if(!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$/.test(start)||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$/.test(end))throw Error('Nhập đúng định dạng và đủ giây.');const q=await sb.rpc('iqc_sua_thoi_gian_lan_kiem',{p_id:r.id,p_bat_dau:start+'+07:00',p_ket_thuc:end+'+07:00',p_sua_luc:r.sua_luc,p_ly_do:reason});if(q.error)throw q.error;await loadDashboard();}catch(e){alert(e.message||e);}};line.append(editTime);
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
    const [d,rr,dr,pr]=await Promise.all([oldGet(),sbTaiHet(()=>sb.from('iqc_lan_kiem').select('*').order('id')),sbTaiHet(()=>sb.from('iqc_lan_kiem_loi').select('*').order('id')),sbTaiHet(()=>sb.from('iqc_aql_ke_hoach').select('*').order('lot_id'))]);
    if(rr.error||dr.error||pr.error)throw rr.error||dr.error||pr.error;
    lots=d.lots;rounds=rr.data||[];defects=dr.data||[];plans=pr.data||[];
    for(const lot of lots){ lot.multiPlan=plans.find(p=>String(p.lot_id)===String(lot.id))||null; const related=rounds.filter(r=>String(r.lot_id)===String(lot.id)); if(related.length){const t=IqcInspectionTotals.summarize(lot.lotQty,related.map(r=>({id:r.id,checked:r.so_kiem,ok:r.so_ok,ng:r.so_ng})),{paused:lot.multiPaused});const oldNg=related.some(r=>r.loai==='so_du_cu'&&r.ket_luan_cu==='NG');Object.assign(lot,{multi:t,okQty:t.ok,ngQty:t.ng,status:t.progress==='Đã kiểm hết'?'Đã kiểm tra':'Đang kiểm tra',result:lot.multiConclusion||(oldNg?'NG':'')});} }
    populateLots();if(selectedLot){selectedLot=lots.find(x=>String(x.id)===String(selectedLot.id))||selectedLot;renderHistory();}
    return d;
  };
  async function continueLot(id) {
    const lot=lots.find(l=>String(l.id)===String(id));if(!lot||lot.method==='hoa_hoc')return;
    const opened=await editLot(id);if(opened===false){$id('iqcMultiLot').value=selectedLot?String(selectedLot.id):'';return false;}selectedLot=lot;lockLot(true);editRound=null;resetStart();$id('iqcMultiLot').value=String(id);resetDefects();
    const last=rounds.filter(r=>String(r.lot_id)===String(id)&&r.loai!=='so_du_cu').sort((a,b)=>Number(b.id)-Number(a.id))[0];if(last?.nguoi_kiem)$id('inspector').value=last.nguoi_kiem;
    $id('iqcMultiDate').value=today();for(const id of ['iqcMultiChecked','iqcMultiOk','iqcMultiNg'])$id(id).value='';requestId=crypto.randomUUID();renderHistory();$id('formSection').scrollIntoView({behavior:'smooth'});
  }
  const previousEdit=editLot;
  editLot=async id=>{
    if(!saving&&!IqcChemicalEntry.isChemical()&&dirtyVisual&&!confirm('Đổi LOT sẽ bỏ dữ liệu chưa lưu. Tiếp tục?'))return false;
    if(!IqcChemicalEntry.isChemical())lockLot(false);
    await previousEdit(id);
    const lot=lots.find(l=>String(l.id)===String(id));
    if(lot&&lot.method!=='hoa_hoc'){selectedLot=lot;lockLot(true);editRound=null;resetStart();requestId=crypto.randomUUID();$id('iqcMultiLot').value=String(id);resetDefects();$id('iqcMultiDate').value=today();for(const key of ['iqcMultiChecked','iqcMultiOk','iqcMultiNg'])$id(key).value='';renderHistory();}
    else {selectedLot=null;if(lot?.method==='hoa_hoc'){chemistryRegister.hidden=true;await loadChemistryHistory(id);}}
    dirtyVisual=false;return true;
  };
  window.addEventListener('iqc-catalog-refreshed',()=>{if(IqcChemicalEntry.isChemical()&&editingId)loadChemistryHistory(editingId).catch(console.error);});
  $id('iqcMultiLot').onchange=async e=>{if(e.target.value)await continueLot(e.target.value);else {if(dirtyVisual&&!confirm('Bỏ dữ liệu chưa lưu để nhập LOT mới?')){e.target.value=selectedLot?String(selectedLot.id):'';return;}resetForm();selectedLot=null;renderHistory();}};
  async function reloadSaved() {
    const d=await IqcApi.getDashboardData();renderDashboard(d);await continueLot(committedLot);
    committedLot=null;$id('iqcMultiRetry').hidden=true;$id('saveBtn').disabled=false;
  }
  $id('iqcMultiRetry').onclick=async()=>{try{await reloadSaved();}catch(e){$id('iqcMultiStatus').textContent='Đã lưu; chưa tải lại được LOT: '+(e.message||e);}};
  form.addEventListener('reset',e=>{if(e.defaultPrevented)return;selectedLot=null;editRound=null;dirtyVisual=false;lockLot(false);resetStart();chemistryRegister.hidden=false;requestId=crypto.randomUUID();chemistryRegisterId=crypto.randomUUID();queueMicrotask(()=>{resetDefects();$id('iqcMultiDate').value=today();if(!$id('inspectionType').value){$id('inspectionType').value='Kiểm tra 100%';$id('inspectionType').dispatchEvent(new Event('change'));}renderHistory();});});
  $id('iqcMultiDate').value=today();
  loadDefectCatalog().catch(e=>{$id('iqcMultiCatalogStatus').textContent='Không tải được danh mục lỗi IQC: '+(e.message||e);});
  form.addEventListener('submit',async e=>{
    if(IqcChemicalEntry.isChemical())return;
    e.preventDefault();e.stopImmediatePropagation();if(saving||committedLot)return;
    try {
      const raw={checked:$id('iqcMultiChecked').value,ok:$id('iqcMultiOk').value,ng:$id('iqcMultiNg').value}, rows=readDefects();
      const createOnly=!selectedLot&&!editRound&&!raw.checked&&!Number(raw.ok)&&!Number(raw.ng)&&!rows.length;
      const amount=createOnly?null:IqcInspectionTotals.inspection(raw);
      if(rows.some(r=>!r.ten_loi||!Number.isSafeInteger(r.so_luong)||r.so_luong<1))throw Error('Nhập tên và số lượng cho từng lỗi.');
      const date=$id('iqcMultiDate').value,inspector=$id('inspector').value.trim();if(!createOnly&&(!date||!inspector))throw Error('Nhập người kiểm.');
      const people=inspector?await Qc02Data.employees():[];const person=people.find(p=>p.code+'_'+p.name===inspector);if(inspector&&!person)throw Error('Chọn người kiểm từ danh mục nhân sự.');
      const lan=createOnly?null:{ngay_kiem:date,nguoi_kiem:inspector,so_kiem:amount.checked,so_ok:amount.ok,so_ng:amount.ng,loi:rows};
      if(lan&&!editRound)lan.bat_dau_id=await ensureStarted();
      let result;
      saving=true;$id('saveBtn').disabled=true;
      if(editRound) result=await sb.rpc('iqc_sua_lan_kiem',{p_id:editRound.id,p_lan:lan,p_sua_luc:editRound.sua_luc,p_request_id:requestId});
      else {
        let lot=null;
        if(!selectedLot){
          await IqcMaterialCatalog.load(true);const product=IqcMaterialCatalog.resolve($id('productCode').value);if(!product)throw Error('Chọn mã sản phẩm hoặc NVL trong danh mục.');
          if(product.kind==='nvl'&&['nhom','kem'].includes(product.group))throw Error('NVL này cần kiểm hóa học.');
          lot={supplier:$id('supplier').value,product_code:product.code,product_name:product.name,lot_no:$id('lotNo').value,lot_qty:Number($id('lotQty').value),pham_vi:$id('iqcScope').value,doi_tuong:product.kind,ma_nvl:product.kind==='nvl'?product.code:null,inspection_type:$id('inspectionType').value||'Kiểm tra 100%',aql:$id('aql').value,sample_qty:Number($id('sampleQty').value)||null,inspector,nguoi_kiem_id:person?.code||null,nguoi_kiem_ten:person?.name||null};
        }
        result=await sb.rpc('iqc_luu_lan_kiem',{p_lot_id:selectedLot?.id||null,p_lot:lot,p_lan:lan,p_request_id:requestId});
      }
      if(result.error)throw result.error;
      requestId=crypto.randomUUID();editRound=null;dirtyVisual=false;committedLot=result.data.lot_id;$id('iqcMultiStatus').textContent='Đã lưu lần kiểm.';
      try{await reloadSaved();}catch(err){$id('iqcMultiRetry').hidden=false;$id('iqcMultiStatus').textContent='Đã lưu; chưa tải lại được LOT: '+(err.message||err);}
    }catch(err){$id('iqcMultiStatus').textContent='Chưa xác nhận được lần lưu: '+(err.message||err)+'. Giữ dữ liệu và thử lại.';}finally{saving=false;$id('saveBtn').disabled=!!committedLot;}
  },true);
  window.IqcMultiEntry={continueLot,totals,hasUnsaved:()=>!IqcChemicalEntry.isChemical()&&dirtyVisual,getData:()=>({lots,rounds,defects,plans})};
})();
