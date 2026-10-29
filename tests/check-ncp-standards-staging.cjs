// Read-only deployment verification. This script never accesses production.
const assert=require('node:assert/strict');
(async()=>{
 const base='https://mes-toyotaki.dangnaf.workers.dev/';
 for(const [file,markers]of [
  ['qc-manager.html',['id="ncp-han-tra-loi"','duc_ncp_theo_doi','ncpDeadlineCells','tc-cd-bar']],
  ['ncp-detail.html',['id="f-han-tra-loi"','p_han_tra_loi_doi_sach']],
  ['shared/ipqc-btk-do.js',['p_id_btk: btk.id','data.lan=(data.lan||[]).filter']],
  ['shared/mes-ncp-source.js',["response_due:el('ncp-han-tra-loi').value"]]
 ]){
  const r=await fetch(base+file+'?verify=20261029-ncp',{headers:{'Cache-Control':'no-cache'}});
  assert.equal(r.status,200,file);const s=await r.text();
  for(const marker of markers)assert.ok(s.includes(marker),file+' missing '+marker);
  console.log('PASS deployed '+file);
 }
})().catch(e=>{console.error(e.message);process.exitCode=1;});
