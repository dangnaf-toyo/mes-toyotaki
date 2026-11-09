// Read-only deployed asset check; no production hosts or writes.
const assert=require('node:assert/strict');
(async()=>{
 const base='https://mes-toyotaki.dangnaf.workers.dev/';
 for(const [file,markers]of [
  ['qc-manager.html',['id="ncp-new-images"',"ncpNewImages.create('ng'",'shared/ncp-defect-images.js?v=T228']],
  ['ncp-detail.html',['id="ncp-case-images"','await ncpCaseImages.load(state.id)','id="btn-print"','id="btn-save"']],
  ['shared/ncp-defect-images.js',["const BUCKET = 'ncp-hinh-anh'",'ncp_mo_phieu_co_anh','ncp_anh_them','ncp_anh_xoa','createSignedUrl','createImageBitmap']],
  ['shared/ncp-defect-images.css',['.ncp-defect-gallery','.ncp-defect-thumb']],
  ['shared/mes-ncp-source.js',["ncpNewImages.create('source'",'await ncpNewImages.reset()']]
 ]){
  const r=await fetch(base+file+'?verify=T228-20261109',{headers:{'Cache-Control':'no-cache'}});assert.equal(r.status,200,file);
  const content=await r.text();for(const marker of markers)assert.ok(content.includes(marker),file+' missing '+marker);
  console.log('PASS deployed staging '+file);
 }
})().catch(e=>{console.error(e.message);process.exitCode=1;});
