/* Additive OQC views. Existing RPC, personnel permissions and catalog are retained. */
const MesOqcRecord = (() => {
  let otherRows = [], original = null, serial = 0;
  const byId = id => document.getElementById(id);
  const safe = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function date(row) {
    const value = String(row?.inspection_date || '');
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
    if (!m || Number(m[2]) < 1 || Number(m[2]) > 12 || Number(m[3]) < 1 || Number(m[3]) > new Date(Date.UTC(Number(m[1]),Number(m[2]),0)).getUTCDate()) return 'Chưa có dữ liệu';
    return m[3] + '/' + m[2] + '/' + m[1];
  }
  function renderOther() {
    byId('otherDefects').innerHTML = otherRows.map(r => `<tr data-other-id="${r.key}"><td>${safe(r.group||'NG khác')}</td><td><input data-other="label" value="${safe(r.label)}" placeholder="Tên lỗi"></td><td><input data-other="detail" value="${safe(r.detail)}" placeholder="Ghi chú (tùy chọn)"></td><td><input type="number" min="0" step="1" data-other="qty" value="${safe(r.qty)}"><button type="button" class="btn secondary" data-remove-other="${r.key}">Xóa dòng</button></td></tr>`).join('');
  }
  function add(value = {}) {
    otherRows.push({ ...value, key: ++serial, code: value.code || 'ng_khac_' + crypto.randomUUID(), label: value.label || '', group: value.group || 'NG khác', detail: value.detail || '', qty: value.qty ?? 0 });
    renderOther(); calc();
  }
  const oldCalc = calc, oldPayload = defectsPayload, oldEdit = editRow, oldReset = resetForm;
  calc = function() {
    oldCalc();
    const total = Number(byId('total').value) || 0;
    const ng = (Number(byId('ng').value) || 0) + otherRows.reduce((n,r) => n + (Number(r.qty) || 0), 0), ok = total-ng;
    byId('ng').value=ng; byId('defectTotal').textContent=ng; byId('ok').value=ok>=0?ok:'';
    byId('okPct').value=total&&ok>=0?(ok/total*100).toLocaleString('vi-VN',{maximumFractionDigits:2})+'%':'0%';
    byId('ngPct').value=total?(ng/total*100).toLocaleString('vi-VN',{maximumFractionDigits:2})+'%':'0%';
  };
  defectsPayload = function() {
    const used = new Set();
    const standard = oldPayload().map(item => {
      const old = (original?.defects || []).find(d => d.code===item.code && !used.has(d));
      if(old)used.add(old);
      return {...old,...item};
    });
    const extras=otherRows.filter(r=>Number(r.qty)>0||r.label.trim()).map(({key,...r})=>({...r,qty:Number(r.qty)}));
    if(extras.some(r=>!r.label.trim()||!Number.isInteger(r.qty)||r.qty<0))throw new Error('Mỗi lỗi khác cần tên lỗi và số lượng NG nguyên, không âm.');
    const zeroMetadata=(original?.defects||[]).filter((item,index,items)=>{
      const input=[...document.querySelectorAll('#defects .defect')].find(i=>i.dataset.code===item.code);
      return input&&Number(input.value)===0&&index===items.findIndex(d=>d.code===item.code);
    }).map(item=>({...item,qty:0,detail:[...document.querySelectorAll('#defects .detail')].find(i=>i.dataset.code===item.code)?.value||''}));
    return [...standard,...zeroMetadata,...extras];
  };
  editRow = function(id) {
    const row=dataRows.find(r=>r.id===id);if(!row)return;
    original=row;otherRows=[];oldEdit(id);
    // Preserve unknown/retired defect codes and duplicate legacy lines.
    const seen=new Set();
    for(const item of row.defects||[]){
      const known=catalog.some(c=>c.code===item.code)&&!seen.has(item.code);
      if(known){seen.add(item.code);const input=[...document.querySelectorAll('#defects .defect')].find(i=>i.dataset.code===item.code);const detail=[...document.querySelectorAll('#defects .detail')].find(i=>i.dataset.code===item.code);if(input)input.value=item.qty;if(detail)detail.value=item.detail||'';}
      else otherRows.push({...item,key:++serial,label:item.label||item.name||item.code||'Lỗi cũ',detail:item.detail||item.note||'',qty:item.qty??0});
    }
    byId('date').readOnly=true; renderOther();calc();
  };
  resetForm = function() { original=null;otherRows=[];byId('date').readOnly=false;oldReset();renderOther(); };
  byId('addOtherDefect').onclick=()=>add();
  byId('otherDefects').addEventListener('input',event=>{
    const row=otherRows.find(r=>String(r.key)===event.target.closest('tr')?.dataset.otherId);
    if(row&&event.target.dataset.other){row[event.target.dataset.other]=event.target.value;calc();}
  });
  byId('otherDefects').addEventListener('click',event=>{
    const button=event.target.closest('[data-remove-other]');if(!button)return;
    otherRows=otherRows.filter(r=>String(r.key)!==button.dataset.removeOther);renderOther();calc();
  });
  const oldSubmit=byId('form').onsubmit;
  byId('form').onsubmit=async event=>{
    if(byId('save').disabled){event.preventDefault();return;}
    try{
      for(const input of document.querySelectorAll('#defects .defect'))if(!Number.isInteger(Number(input.value))||Number(input.value)<0)throw new Error('Số lượng lỗi phải là số nguyên, không âm.');
      for(const row of otherRows)if(!Number.isInteger(Number(row.qty))||Number(row.qty)<0||(!row.label.trim()&&Number(row.qty)>0))throw new Error('Kiểm tra tên và số lượng từng lỗi khác.');
      if(original)byId('date').value=original.inspection_date||'';
      await oldSubmit(event);
    }catch(error){event.preventDefault();message(error.message,true);byId('save').disabled=false;}
  };
  function photos(row) {
    const result=[];
    function append(value){if(Array.isArray(value))value.forEach(append);else if(typeof value==='string'){try{const parsed=JSON.parse(value);if(Array.isArray(parsed)){append(parsed);return;}}catch{}const url=Qc02View.safeUrl(value,true);if(url)result.push(url);}}
    append(row.images);append(row.image_urls);append(row.anh_urls);for(const defect of row.defects||[]){append(defect.images);append(defect.image_urls);append(defect.anh_urls);}
    return [...new Set(result)];
  }
  function detail(id) {
    const row=dataRows.find(r=>r.id===id);if(!row)return;
    const dialog=byId('oqcRecordDialog'),target=byId('oqcRecordBody');target.replaceChildren();
    Qc02View.table(target,['Thông tin','Nội dung'],[
      ['Ngày kiểm tra',date(row)],['Giờ kiểm tra','Chưa có dữ liệu'],['Ca',row.shift],['Model',row.product_code],['Tên sản phẩm',row.product_name],['Mã nhân viên',row.inspector_code],['Người kiểm',row.inspector_name],['Tổng kiểm',row.total_qty],['OK',row.ok_qty],['NG',row.ng_qty],['% NG',Number(row.total_qty)>0?(Number(row.ng_qty)/Number(row.total_qty)*100).toFixed(2)+'%':'0%'],['Ghi chú',row.note]
    ]);
    const defects=document.createElement('div');target.append(defects);Qc02View.table(defects,['Nhóm lỗi','Tên lỗi','Số lượng','Ghi chú'],(row.defects||[]).map(d=>[d.group,d.label||d.name||d.code,d.qty,d.detail||d.note]));
    const urls=photos(row),gallery=document.createElement('div');gallery.className='oqc-record-gallery';gallery.dataset.qcGallery='';
    urls.forEach(url=>{const link=document.createElement('a');link.href=url;link.dataset.qcPhoto='';link.className='oqc-record-photo';const img=document.createElement('img');img.src=url;img.alt='Ảnh lỗi OQC';img.style.cssText='width:120px;height:90px;object-fit:contain';link.append(img);link.onclick=e=>{e.preventDefault();e.stopPropagation();Qc02View.photo(url,urls);};gallery.append(link);});target.append(gallery);
    if(typeof dialog.showModal==='function')dialog.showModal();else dialog.setAttribute('open','');
  }
  byId('rows').addEventListener('click',event=>{
    if(event.target.closest('button,a,input,select'))return;
    const row=event.target.closest('[data-record-id]');if(row)detail(Number(row.dataset.recordId));
  });
  byId('rows').addEventListener('keydown',event=>{if(event.target.matches('[data-record-id]')&&['Enter',' '].includes(event.key)){event.preventDefault();detail(Number(event.target.dataset.recordId));}});
  byId('oqcRecordClose').onclick=()=>{const d=byId('oqcRecordDialog');if(typeof d.close==='function')d.close();else d.removeAttribute('open');};
  byId('oqcRecordDialog').addEventListener('click',event=>{if(event.target===event.currentTarget)byId('oqcRecordClose').click();});
  exportExcel=function(){
    const out=dataRows.map(r=>{const values={Ngày:r.inspection_date,Ca:r.shift,Model:r.product_code,'Tên SP':r.product_name,'Mã NV':r.inspector_code,'Người kiểm':r.inspector_name,'Tổng kiểm':r.total_qty,OK:r.ok_qty,NG:r.ng_qty,'%OK':r.total_qty?r.ok_qty/r.total_qty:0,'%NG':r.total_qty?r.ng_qty/r.total_qty:0},counts=new Map();for(const d of r.defects||[]){const label=(d.label||d.name||d.code)+(d.detail?' — '+d.detail:'');counts.set(label,(counts.get(label)||0)+Number(d.qty||0));}for(const [label,qty] of counts){const key=Object.hasOwn(values,label)||['__proto__','constructor','prototype'].includes(label)?'Lỗi: '+label:label;values[key]=qty;}return values;});
    const ws=XLSX.utils.json_to_sheet(out),wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,ws,'OQC');XLSX.writeFile(wb,'thong-ke-oqc.xlsx');
  };
  return {date,detail,add,photos};
})();
