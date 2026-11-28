/* Entry and history for visual IQC inspections. Chemical IQC keeps its own form. */
(() => {
  const $id = id => document.getElementById(id), form = $id('lotForm');
  const side = form.querySelector('.iqc-report-side');
  const checks = document.createElement('div');
  checks.className = 'iqc-checks';
  checks.innerHTML = `
    <label class="field">LOT đang kiểm <select id="iqcMultiLot"><option value="">LOT mới</option></select></label>
    <div class="iqc-round-times" hidden>
      <label>Bắt đầu lần này <input id="iqcMultiStart" type="datetime-local" step="1"></label>
      <label>Hoàn thành LOT <input id="iqcMultiEnd" type="datetime-local" step="1"></label>
      <input id="iqcMultiDate" type="hidden">
    </div>
    <div class="iqc-round-quantities">
      <label class="field">SL kiểm lần này <input id="iqcMultiChecked" type="number" min="1" step="1"></label>
      <label class="field">OK <input id="iqcMultiOk" type="number" min="0" step="1" value="0"></label>
      <label class="field">NG <input id="iqcMultiNg" type="number" min="0" step="1" value="0"></label>
    </div>
    <dl id="iqcMultiSummary" class="iqc-round-summary" aria-label="Tổng hợp LOT">
      <div><dt>Đã kiểm</dt> <dd id="iqcTotalChecked">0</dd></div>
      <div><dt>Còn lại</dt> <dd id="iqcTotalRemaining">—</dd></div>
      <div><dt>OK</dt> <dd id="iqcTotalOk">0</dd></div>
      <div><dt>NG</dt> <dd id="iqcTotalNg">0</dd></div>
      <div><dt>% OK</dt> <dd id="iqcTotalOkRate">—</dd></div>
      <div><dt>% NG</dt> <dd id="iqcTotalNgRate">—</dd></div>
      <div><dt>Tổng lỗi</dt> <dd id="iqcTotalDefects">0</dd></div>
    </dl>
    <p id="iqcMultiProgress" class="help">LOT mới</p>
    <p id="iqcLotStartedAt" class="help"></p>`;
  side.querySelector('.iqc-report-extra').before(checks);

  const section = document.createElement('section');
  section.id = 'iqcMultiEntry';
  section.innerHTML = `
    <div class="iqc-defect-toolbar">
      <h3>Lỗi IQC</h3>
      <input id="iqcMultiDefectSearch" type="search" aria-label="Tìm mã hoặc tên lỗi" placeholder="Tìm mã hoặc tên lỗi">
      <span id="iqcMultiCatalogStatus" class="help"></span>
    </div>
    <datalist id="iqcMultiDefects"></datalist><div id="iqcMultiRows" class="iqc-defect-catalog"></div>
    <section class="iqc-other-defects"><div class="iqc-other-title"><h4>Lỗi khác</h4><button type="button" id="iqcMultiAdd" class="button btn-secondary">+ Thêm lỗi khác</button></div><div class="iqc-other-head"><b>Tên lỗi</b><b>Chi tiết</b><b>Số lượng</b><b></b></div><div id="iqcMultiOtherRows"></div></section>
    <div id="iqcMultiHistory"></div><p id="iqcMultiStatus" role="status"></p><button type="button" id="iqcMultiRetry" hidden>Tải lại LOT đã lưu</button>`;
  side.after(section);
  $id('receivedDate').required=false;
  $id('receivedDate').closest('.field').classList.add('iqc-hide-received');
  for(const id of ['pickupDate','completionDate'])$id(id).closest('.field').classList.add('iqc-hide-received');
  $id('inspector').required=false;
  $id('inspector').closest('.field').querySelector('label').textContent='Người kiểm (khi kiểm)';
  $id('inspectionType').closest('.field').after($id('location').closest('.field'));
  $id('inspectionType').required=false;
  $id('inspectionType').closest('.field').querySelector('label').textContent='Hình thức kiểm';
  if(!$id('inspectionType').value)$id('inspectionType').value='Kiểm tra 100%';

  $id('aqlField').classList.add('iqc-hide-received');
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
  const timeInput=value=>value?new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Ho_Chi_Minh',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false}).format(new Date(value)).replace(' ','T'):'';
  function resetStart(){startEpoch++;startId=null;startPromise=null;$id('iqcMultiStart').value='';$id('iqcMultiEnd').value='';}
  async function ensureStarted(){
    if(editRound)return;
    if(startPromise)return startPromise;
    const epoch=startEpoch,id=crypto.randomUUID(),lotId=selectedLot?.id||null;startId=id;
    startPromise=(async()=>{const r=await sb.rpc('iqc_bat_dau_lan_kiem',{p_id:id,p_lot_id:lotId});if(r.error)throw r.error;if(epoch!==startEpoch)throw Error('LOT đã thay đổi; bắt đầu lại lần kiểm.');if(!$id('iqcMultiStart').value)$id('iqcMultiStart').value=timeInput(r.data.bat_dau_luc);return id;})();
    try{return await startPromise;}catch(e){if(epoch===startEpoch){startId=null;startPromise=null;}throw e;}
  }
  form.addEventListener('focusin',e=>{if(IqcChemicalEntry.isChemical()||editRound||!e.target.matches('#iqcMultiStart,#iqcMultiChecked,#iqcMultiOk,#iqcMultiNg,#iqcMultiRows input,#iqcMultiOtherRows input'))return;ensureStarted().catch(err=>{$id('iqcMultiStatus').textContent='Không bắt đầu được lần kiểm: '+(err.message||err);});});
  form.addEventListener('input',e=>{if(!IqcChemicalEntry.isChemical() && !['iqcMultiDefectSearch','iqcMultiLot','iqcAqlLevel','iqcAqlValue','iqcAqlMode'].includes(e.target.id))dirtyVisual=true;});
  const text = (tag, value) => { const n=document.createElement(tag); n.textContent=value; return n; };
  const input = (cls, type='text') => { const n=document.createElement('input');n.className=cls;n.type=type;if(type==='number'){n.min='0';n.step='1';}return n; };
  function addOtherDefect(row={}) {
    const div=document.createElement('div');div.className='iqc-other-row';
    div.dataset.code = row.ma_loi || '';
    div.dataset.group = row.nhom_loi ?? (row.ten_loi ? '' : 'Lỗi khác');
    const name=input('name'),detail=input('detail'),qty=input('qty','number'),del=text('button','Xóa');
    name.placeholder='Tên lỗi';detail.placeholder='Chi tiết';qty.placeholder='SL';qty.value=row.so_luong??'';name.value=row.ten_loi??'';detail.value=row.chi_tiet??'';
    del.type='button';del.className='button btn-secondary';del.onclick=()=>{div.remove();dirtyVisual=true;refreshDefectFeedback();};
    div.append(name,detail,qty,del);$id('iqcMultiOtherRows').append(div);return div;
  }
  function catalogDefect(c, row={}) {
    const div=document.createElement('div');div.className='iqc-catalog-defect';div.dataset.catalog='1';div.dataset.code=c.ma_loi||c.code||'';div.dataset.group=c.defect_group||'';
    const name=input('name'),detailButton=text('button','Chi tiết'),qty=input('qty','number'),detail=text('div',''),detailInput=input('detail');
    const code=div.dataset.code,label=String(c.label||'').replace(new RegExp('^'+code.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'\\s*[-–—:·]?\\s*','i'),'');div.dataset.label=row.ten_loi??label;div.dataset.group=row.ten_loi ? (row.nhom_loi || '') : div.dataset.group;name.readOnly=true;name.value=`${code ? code+' ' : ''}${label}`;qty.value=row.so_luong??0;detailInput.value=row.chi_tiet??'';detailInput.placeholder='Chi tiết / vị trí';detail.className='iqc-catalog-detail';detail.hidden=true;detail.append(detailInput);
    name.title = name.value;
    qty.setAttribute('aria-label', `Số lượng ${name.value}`);
    detailInput.setAttribute('aria-label', `Chi tiết ${name.value}`);
    detailButton.type='button';detailButton.className='button btn-secondary btn-small';detailButton.setAttribute('aria-expanded','false');detailButton.onclick=()=>{detail.hidden=!detail.hidden;detailButton.setAttribute('aria-expanded',String(!detail.hidden));if(!detail.hidden)detailInput.focus();};
    if(detailInput.value){detail.hidden=false;detailButton.setAttribute('aria-expanded','true');}
    div.append(name,detailButton,qty,detail);return div;
  }
  $id('iqcMultiAdd').onclick=()=>addOtherDefect();
  function readDefects() {
    const known=[...$id('iqcMultiRows').querySelectorAll('.iqc-catalog-defect')].map(row=>({ma_loi:row.dataset.code||null,ten_loi:row.dataset.label,chi_tiet:row.querySelector('.detail').value.trim(),nhom_loi:row.dataset.group||null,so_luong:Number(row.querySelector('.qty').value)})).filter(x=>x.so_luong!==0||x.chi_tiet);
    const others=[...$id('iqcMultiOtherRows').children].map(row=>({ma_loi:row.dataset.code||null,ten_loi:row.querySelector('.name').value.trim(),chi_tiet:row.querySelector('.detail').value.trim(),nhom_loi:row.dataset.group||null,so_luong:Number(row.querySelector('.qty').value)})).filter(x=>x.ten_loi||x.chi_tiet||x.so_luong);
    return [...known,...others];
  }
  function refreshDefectFeedback(){
    for(const row of $id('iqcMultiRows').querySelectorAll('.iqc-catalog-defect'))row.classList.toggle('has-ng',Number(row.querySelector('.qty').value)>0);
    for(const row of $id('iqcMultiOtherRows').children)row.classList.toggle('has-ng',Number(row.querySelector('.qty').value)>0);
    const defectsTotal=readDefects().reduce((sum,d)=>sum+(Number(d.so_luong)||0),0),lotQty=Number(selectedLot?.lotQty||$id('lotQty').value)||0;
    const thisChecked=Number($id('iqcMultiChecked').value)||0,thisOk=Number($id('iqcMultiOk').value)||0,thisNg=Number($id('iqcMultiNg').value)||0;
    let checked=thisChecked,ok=thisOk,ng=thisNg;
    if(selectedLot){
      const t=totals(selectedLot);
      if(t.checked!=null){
        checked+=t.checked-Number(editRound?.so_kiem||0);
        ok+=t.ok-Number(editRound?.so_ok||0);
        ng+=t.ng-Number(editRound?.so_ng||0);
      }
    }
    const remaining=Math.max(0,lotQty-checked),pct=(x)=>checked?((x/checked)*100).toFixed(1)+'%':'—';
    $id('iqcTotalChecked').textContent = checked;
    $id('iqcTotalRemaining').textContent = lotQty ? remaining : '—';
    $id('iqcTotalOk').textContent = ok;
    $id('iqcTotalNg').textContent = ng;
    $id('iqcTotalOkRate').textContent = pct(ok);
    $id('iqcTotalNgRate').textContent = pct(ng);
    $id('iqcTotalDefects').textContent = defectsTotal;
  }
  $id('iqcMultiRows').addEventListener('input',refreshDefectFeedback);$id('iqcMultiOtherRows').addEventListener('input',refreshDefectFeedback);
  for(const id of ['iqcMultiChecked','iqcMultiOk','iqcMultiNg','lotQty'])$id(id).addEventListener('input',refreshDefectFeedback);
  function resetDefects(saved=[]) {
    $id('iqcMultiRows').replaceChildren();$id('iqcMultiOtherRows').replaceChildren();
    const rest=[...saved], groups=new Map();
    for(const c of catalog){
      const group=c.defect_group||'Khác';
      if(!groups.has(group)){const box=document.createElement('section'),heading=text('h4',group);box.className='iqc-defect-group';box.append(heading);groups.set(group,{box,heading,count:0});$id('iqcMultiRows').append(box);}
      const g=groups.get(group),code=c.ma_loi||c.code||'';
      const savedIndex=rest.findIndex(x=>x.ma_loi ? x.ma_loi===code : x.ten_loi===c.label && (x.nhom_loi||'')===group);
      const previous=savedIndex>=0?rest.splice(savedIndex,1)[0]:{};
      g.box.append(catalogDefect(c,previous));g.count++;
    }
    for(const g of groups.values())g.heading.textContent=`${g.heading.textContent} (${g.count})`;
    rest.forEach(addOtherDefect);filterDefects();refreshDefectFeedback();
  }
  function filterDefects(){const q=$id('iqcMultiDefectSearch').value.trim().toLocaleLowerCase('vi');for(const group of $id('iqcMultiRows').children){let visible=0;for(const row of group.querySelectorAll('.iqc-catalog-defect')){const name=(row.dataset.code+' '+row.querySelector('.name').value).toLocaleLowerCase('vi');row.hidden=!!q&&!name.includes(q);if(!row.hidden)visible++;}group.hidden=!visible;}}
  $id('iqcMultiDefectSearch').addEventListener('input',filterDefects);

  async function loadDefectCatalog(){
    const r=await sbTaiHet(()=>sb.from('quality_defect_catalog').select('code,ma_loi,label,defect_group').overlaps('processes',['IQC','OQC','OQC_SON']).eq('is_active',true).order('sort_order').order('label'));
    if(r.error)throw r.error;
    const map=new Map();for(const x of r.data||[]){const label=String(x.label||'').trim();if(!label)continue;const key=(label+'|'+(x.defect_group||'')).toLocaleLowerCase('vi');if(!map.has(key))map.set(key,{...x,label});}
    catalog=[...map.values()].sort((a,b)=>String(a.ma_loi||a.code||'').localeCompare(String(b.ma_loi||b.code||''),'vi',{numeric:true,sensitivity:'base'}));$id('iqcMultiDefects').replaceChildren(...catalog.map(x=>new Option(x.label,x.label)));
    $id('iqcMultiCatalogStatus').textContent=catalog.length?`Danh mục lỗi dùng chung OQC/IQC · ${catalog.length} mã`:'Chưa có lỗi trong danh mục dùng chung.';
    if(!$id('iqcMultiRows').children.length)resetDefects();
    else resetDefects(readDefects());
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
    if(!selectedLot){$id('iqcMultiProgress').textContent='LOT mới';$id('iqcLotStartedAt').textContent='';refreshDefectFeedback();return;}
    const firstStart=rounds.filter(r=>String(r.lot_id)===String(selectedLot.id)&&r.bat_dau_luc).map(r=>r.bat_dau_luc).sort()[0];$id('iqcLotStartedAt').textContent=firstStart?'Bắt đầu LOT: '+displayTime(firstStart):'';
    const t=totals(selectedLot);
    $id('iqcMultiProgress').textContent=t.checked===null?'Số đã kiểm của LOT cũ chưa xác định. Không tự suy từ cỡ mẫu.':`Tổng ${t.total} · Đã kiểm ${t.checked} · OK ${t.ok} · NG ${t.ng} · Còn ${t.remaining} · Tỷ lệ NG ${t.checked?((t.ng/t.checked)*100).toFixed(2):'0.00'}% · ${t.progress}`;
    refreshDefectFeedback();
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
        resetStart();editRound=r;$id('iqcMultiDate').value=r.ngay_kiem;$id('inspector').value=r.nguoi_kiem;$id('iqcMultiStart').value=timeInput(r.bat_dau_luc);$id('iqcMultiEnd').value='';
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
    const [d,rr,dr,pr,cr]=await Promise.all([oldGet(),sbTaiHet(()=>sb.from('iqc_lan_kiem').select('*').order('id')),sbTaiHet(()=>sb.from('iqc_lan_kiem_loi').select('*').order('id')),sbTaiHet(()=>sb.from('iqc_aql_ke_hoach').select('*').order('lot_id')),sbTaiHet(()=>sb.from('iqc_aql_lua_chon').select('*').order('lot_id'))]);
    if(rr.error||dr.error||pr.error||cr.error)throw rr.error||dr.error||pr.error||cr.error;
    lots=d.lots;rounds=rr.data||[];defects=dr.data||[];plans=pr.data||[];
    for(const lot of lots){ lot.multiChoice=(cr.data||[]).find(c=>String(c.lot_id)===String(lot.id))||null;if(lot.multiChoice)lot.aql=lot.multiChoice.aql; lot.multiPlan=plans.find(p=>String(p.lot_id)===String(lot.id))||null; const related=rounds.filter(r=>String(r.lot_id)===String(lot.id)); if(related.length){const t=IqcInspectionTotals.summarize(lot.lotQty,related.map(r=>({id:r.id,checked:r.so_kiem,ok:r.so_ok,ng:r.so_ng})),{paused:lot.multiPaused});const oldNg=related.some(r=>r.loai==='so_du_cu'&&r.ket_luan_cu==='NG');Object.assign(lot,{multi:t,okQty:t.ok,ngQty:t.ng,status:t.progress==='Đã kiểm hết'?'Đã kiểm tra':'Đang kiểm tra',result:lot.multiConclusion||(oldNg?'NG':'')});} }
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
      const start=$id('iqcMultiStart').value,end=$id('iqcMultiEnd').value;if(start&&end&&end<start)throw Error('Thời gian hoàn thành không được trước thời gian bắt đầu.');
      let timeReason=null;if(editRound&&((start&&Date.parse(start+'+07:00')!==Date.parse(editRound.bat_dau_luc))||(end&&Date.parse(end+'+07:00')!==Date.parse(editRound.ket_thuc_luc)))){timeReason=prompt('Lý do sửa thời gian:');if(timeReason===null)return;if(!timeReason.trim())throw Error('Nhập lý do sửa thời gian.');}
      const lan=createOnly?null:{ngay_kiem:date,nguoi_kiem:inspector,so_kiem:amount.checked,so_ok:amount.ok,so_ng:amount.ng,loi:rows,...(start?{bat_dau_luc:start+'+07:00'}:{}),...(end?{ket_thuc_luc:end+'+07:00'}:{}),...(timeReason?{ly_do_thoi_gian:timeReason}:{})};
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
