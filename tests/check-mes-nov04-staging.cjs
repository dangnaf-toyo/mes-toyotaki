// Chỉ đọc asset staging, không đăng nhập hoặc ghi dữ liệu.
const assert=require('node:assert/strict'),vm=require('node:vm');
const base='https://mes-toyotaki.dangnaf.workers.dev/';
(async()=>{
  for(const [file,markers] of [
    ['oqc-daily.html',['oqc-dashboard.js?v=20261104-outsource']],
    ['shared/oqc-scope.js',['Kiểm tra sau Gia Công ngoài','recordLabel','matches']],
    ['shared/oqc-dashboard.js',['oqcOutsourceProcess','oqcInspectorCount',"outsourced.style.display"]],
    ['qc-manager.html',['ncp-doi-sach-board.js?v=T214','ipqc-gia-cong.html','ipqc-btk-qc.js?v=20261105-standards','ipqc-drawing-reader.js']],
    ['ncp-detail.html',['ncp-doi-sach-board.js?v=T214','ncp-doi-sach-saved']],
    ['ipqc-gia-cong.html',['gcMeasureForm','qc-manager.html?tab=tieuchuan&amp;cd=gia_cong','gcResultFile','ipqc-gc-entry.js?v=20261105-entry','ipqc-result-import.js?v=20261105-dashboard','ipqc-gia-cong.js?v=20261105-standards']],
    ['shared/ipqc-gia-cong.js',['ipqc_gc_luu_do','sourceLabel','Xem file gốc']],
    ['shared/ipqc-btk-qc.js',['ipqc_gc_luu_tieu_chuan','gcFields','gcDrawing','ipqc_gc_tieu_chuan_lich_su']],
    ['shared/ipqc-gc-entry.js',['IpqcGcEntry','measure-ng']],
    ['shared/ipqc-result-parser.js',['IpqcResultParser']],
    ['shared/ipqc-result-reader.js',['IpqcResultReader','tesseract']],
    ['shared/ipqc-result-import.js',['gia_tri_da_xac_minh','da_sua_sau_dong_bo']],
    ['shared/ncp-doi-sach-board.js',['ncp-doi-sach-saved','ncp_doi_sach_theo_doi']]
  ]){
    const response=await fetch(base+file+'?verify-nov04='+Date.now(),{headers:{'Cache-Control':'no-cache'}});
    assert.equal(response.status,200,file);
    const source=await response.text();
    if(file==='ipqc-gia-cong.html')assert.ok(!source.includes('data-tab="standards"')&&!source.includes('id="gcStandardForm"'));
    for(const marker of markers)assert.ok(source.includes(marker),file+' missing '+marker);
    if(file.endsWith('.html')){
      for(const script of source.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g))
        new vm.Script(script[1],{filename:file});
    }else new vm.Script(source,{filename:file});
    console.log('PASS deployed '+file);
  }
})().catch(error=>{console.error(error.message);process.exitCode=1;});
