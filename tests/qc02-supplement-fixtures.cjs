// Generate offline browser fixtures; every API call is mocked and writes are rejected.
// Usage: node tests/qc02-supplement-fixtures.cjs <temporary-output-directory>
const fs = require('fs'), path = require('path'), vm = require('vm');
const output = process.argv[2];
if (!output) throw Error('Provide a temporary output directory');
fs.mkdirSync(output, { recursive: true });
const png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=';
const row = { id_ncp:'NCP-001',ma_sp:'MODEL1',ten_sp:'Model One',ma_may:'DC1',mo_ta_loi:'Test defect',
  so_luong_nghi_van:10,so_luong_loc_ng:2,ngay_tao:new Date().toISOString(),trang_thai:'da_cach_ly',rc_trang_thai_duyet:'nhap',
  nguoi_mo_case:'EMP1_Inspector',nguyen_nhan_phat_sinh:'Cause',doi_sach_ps_tam_thoi_json:[{noi_dung:'Action',nguoi_thuc_hien:'EMP1_Inspector',hinh_anh:[png]}],
  hinh_anh_phat_sinh_json:[png],id_checkpoint_goc:'CP1' };
const tables = { master_products:[{ma_sp:'MODEL1',ten_sp:'Model One'}],master_employees:[{ma_nv:'EMP1',ten_nhan_vien:'Inspector',vai_tro:'oqc'}],
  duc_ncp:[row],duc_ipqc_checkpoint:[{id_checkpoint:'CP1',ma_may:'DC1',ma_sp:'MODEL1',nguoi_kiem:'EMP1_Inspector',trang_thai:'da_kiem',ket_qua:'NG',anh_bang_chung_url:[png],checklist_json:[{muc:'Size',dat:false}]}],
  duc_ipqc_tieuchuan:[{ma_sp:'MODEL1',file_pdf_url:'https://example.invalid/standard.pdf',danh_sach_muc_kiem_json:['Size']}],
  iqc_lots:[{id:'LOT1',supplier:'Supplier',product_code:'MODEL1',product_name:'Model One',lot_no:'LOT-001',lot_qty:10,received_at:new Date().toISOString(),result:'NG',inspector:'EMP1_Inspector'}],
  iqc_defects:[{id:'DEF1',lot_id:'LOT1',defect_name:'Size',defect_qty:1,images:png}],quality_defect_catalog:[],user_roles:[{role:'admin'}] };
const setup = `
window.qcErrors=[]; window.qcQueries=[];window.qcPrints=0;window.qcSubmissions=[];
window.onerror=m=>qcErrors.push(String(m));window.onunhandledrejection=e=>qcErrors.push(String(e.reason));
console.error=(...x)=>qcErrors.push(x.map(String).join(' '));window.alert=m=>qcErrors.push(String(m));window.print=()=>qcPrints++;
const mockTables=${JSON.stringify(tables)};
const testCanvas=document.createElement('canvas');testCanvas.width=600;testCanvas.height=240;
const testContext=testCanvas.getContext('2d');testContext.fillStyle='#ddd';testContext.fillRect(0,0,600,240);
testContext.fillStyle='#222';testContext.font='24px sans-serif';testContext.fillText('QC TEST IMAGE — MOCK DATA',30,50);
testContext.strokeStyle='#c00';testContext.lineWidth=5;testContext.strokeRect(180,90,120,90);
const sampleImage=testCanvas.toDataURL('image/png');
for(const table of Object.keys(mockTables))mockTables[table]=JSON.parse(JSON.stringify(mockTables[table]).split(${JSON.stringify(png)}).join(sampleImage));
const MesAuth={getSession:async()=>({user:{id:'U1',email:'user@example.invalid'}}),requireAuth:async()=>({user:{id:'U1'}}),getCurrentUserIdentity:async()=> 'EMP1_Inspector'};
const MesNav={setTitle(){}};
const sb={from(name){let single=false,start=0,end=100000,filters=[];const q={};
for(const method of ['select','order','or','gte','lte','lt','contains','in','limit'])q[method]=(...args)=>{qcQueries.push([name,method,...args]);return q};
q.eq=(k,v)=>{filters.push([k,v]);return q};q.range=(a,b)=>{start=a;end=b;return q};
q.single=q.maybeSingle=()=>{single=true;return q};q.then=(resolve)=>{let data=(mockTables[name]||[]).filter(row=>filters.every(([k,v])=>row[k]===v)).slice(start,end+1);return Promise.resolve({data:single?data[0]||null:data,error:null}).then(resolve)};
for(const method of ['insert','update','delete','upsert'])q[method]=()=>{throw Error('Unexpected DB write '+name)};return q},
rpc:async(name,payload)=>{if(name==='duc_get_ipqc_periodic_due')return {data:[],error:null};if(name==='duc_submit_ipqc_check'){qcSubmissions.push(payload);return {data:{ok:true},error:null}}throw Error('Unexpected RPC '+name)}};
`;
const assertions = {
  'iqc.html': `await openDetail('LOT1');check(document.getElementById('detailBody').textContent.includes('LOT-001'),'LOT detail');check(document.querySelector('#iqc-lot-all table'),'full LOT record');check(document.querySelector('#qc02-products option[value="MODEL1"]'),'model master');check(document.querySelector('#qc02-employees option'),'employee master');await IqcApi.searchLotHistory('', '2026-10-01','2026-10-07');check(qcQueries.some(q=>q[0]==='iqc_lots'&&q[1]==='lt'&&q[3]==='2026-10-07T17:00:00.000Z'),'inclusive Vietnam date');`,
  'ipqc.html': `check(document.getElementById('ck-machine-condition'),'machine checkbox');const notes=Qc02View.machineNote('original',true);check(Qc02View.machineChecked(notes)===true,'checked saved');check(Qc02View.machineChecked(Qc02View.machineNote(notes,false))===false,'unchecked saved');check(Qc02View.machineChecked('legacy')===null,'legacy preserved');uploadEvidencePhotos=async()=>[${JSON.stringify(png)}];state.current={id_checkpoint:'CP1',ma_may:'DC1',ma_sp:'MODEL1'};state.photos=[{}];state.checklistAnswers=[{muc:'Size',dat:true}];document.getElementById('ck-machine-condition').checked=true;await submitCheck('OK');check(qcSubmissions.length===1,'existing submit called');check(qcSubmissions[0].p_checklist.length===1&&qcSubmissions[0].p_checklist[0].dat===true,'no neutral item in scored checklist');check(Qc02View.machineChecked(qcSubmissions[0].p_ghi_chu)===true,'condition persisted in real payload');check(qcSubmissions[0].p_ket_qua==='OK','result preserved');`,
  'qc-manager.html': `await loadNcpList();document.getElementById('qc02-ncp-search').value='001';renderNcpList();check(document.querySelector('#ncp-open-tbody a[href="ncp-detail.html?id=NCP-001"]'),'NCP number link');document.getElementById('qc02-ncp-search').value='notfound';renderNcpList();check(!document.querySelector('#ncp-open-tbody tr'),'partial search');check(document.getElementById('fl-nguoi-kiem'),'existing filter retained');`,
  'ncp-detail.html': `check(document.getElementById('qc02-ncp-detail').textContent.includes('NCP-001'),'full NCP detail');await printQc02Ncp();check(qcPrints===1,'print invoked');check(document.querySelector('#qc02-print img'),'print images');check(document.getElementById('qc02-print').textContent.includes('Action'),'print countermeasure');check(document.getElementById('qc02-print').textContent.includes('Cause'),'print cause');`,
  'oqc-daily.html': `check(document.getElementById('filterProduct')&&document.getElementById('filterInspector')&&document.getElementById('filterShift'),'OQC filters retained');check(document.querySelector('#employees option[value="EMP1"]'),'OQC master retained');`,
};
for (const [file, checks] of Object.entries(assertions)) {
  let html = fs.readFileSync(file, 'utf8');
  html = html.replace(/<link\b[^>]*>/gi, '');
  html = html.replace(/<script\b[^>]*src="([^"]+)"[^>]*><\/script>/gi, (_, src) =>
    src.startsWith('shared/qc02-') ? '<script>' + fs.readFileSync(src,'utf8') + '</script>' : '');
  html = html.replace('<head>', '<head><meta http-equiv="Content-Security-Policy" content="connect-src \'none\'; img-src data: blob:; frame-src \'none\'"><script>' + setup + '</script>');
  const test = `<script>window.addEventListener('load',()=>setTimeout(async()=>{const check=(v,m)=>{if(!v)throw Error(m)};try{${checks}
const group=document.createElement('div');group.dataset.qcGallery='';document.body.append(group);for(const url of [${JSON.stringify(png)},${JSON.stringify(png+'#two')}]){const link=document.createElement('a');link.href=url;link.dataset.qcPhoto='';group.append(link);}group.firstChild.click();const viewer=document.querySelector('dialog[open]');check(viewer,'shared image popup');viewer.querySelectorAll('button')[2].click();check(viewer.querySelector('span').textContent.includes('2/2'),'next image');viewer.querySelectorAll('button')[1].click();check(viewer.querySelector('span').textContent.includes('1/2'),'previous image');viewer.click();check(!viewer.open,'backdrop close');
Qc02View.pdf('https://example.invalid/standard.pdf');check(document.querySelector('dialog[open] iframe'),'PDF viewer');document.querySelector('dialog[open] button').click();
check(Qc02View.safeUrl('javascript:alert(1)',true)==='','unsafe URL rejected');
setTimeout(()=>{document.body.dataset.testResult=qcErrors.length?'FAIL: '+qcErrors.join('; '):'PASS'},100);
}catch(e){document.body.dataset.testResult='FAIL: '+e.stack;}},200));</script>`;
  const end = html.lastIndexOf('</body>');
  html = html.slice(0,end) + test + html.slice(end);
  // Existing templates contain escaped closing script tags; validate classic scripts after replacement.
  for(const m of html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)) new vm.Script(m[1],{filename:file});
  fs.writeFileSync(path.join(output,file),html);
}
console.log(output);
