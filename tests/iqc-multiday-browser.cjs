const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {chromium}=require(process.env.MES_PLAYWRIGHT_PATH||'playwright');
const {extendChemistry}=require('./iqc-chemistry-fixture.cjs');
const legacy=fs.readFileSync('tests/iqc-workspace-browser.cjs','utf8');
const base=legacy.slice(legacy.indexOf('function backend()'),legacy.indexOf('\n(async () => {'));
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try{
  const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());
  await page.addInitScript({content:base+`window.sb=backend();window.MesAuth={getSession:async()=>({user:{id:'00000000-0000-0000-0000-000000000001'}}),requireAuth:async()=>({user:{id:'00000000-0000-0000-0000-000000000001'}}),getCurrentUserIdentity:async()=>'ADMIN_Admin'};(${extendChemistry.toString()})();
  sb.tables.master_products.push({ma_sp:'MULTI',ten_sp:'Model test'});sb.tables.iqc_lan_kiem=[];sb.tables.iqc_lan_kiem_loi=[];const old=sb.rpc.bind(sb);let seq=1;
  sb.rpc=async(name,args={})=>{if(name==='iqc_luu_lan_kiem'){let lot=sb.tables.iqc_lots.find(x=>String(x.id)===String(args.p_lot_id));if(!lot){lot={id:'lot-'+seq,created_at:new Date().toISOString(),...args.p_lot,inspector:args.p_lan?.nguoi_kiem,status:'Chưa lấy hàng',phuong_thuc:'ngoai_quan'};sb.tables.iqc_lots.push(lot);}if(args.p_lan){const r={id:seq++,lot_id:lot.id,...args.p_lan,sua_luc:new Date().toISOString()};sb.tables.iqc_lan_kiem.push(r);for(const d of args.p_lan.loi)sb.tables.iqc_lan_kiem_loi.push({id:seq++,lan_kiem_id:r.id,...d});}return {data:{lot_id:lot.id},error:null};}if(name==='iqc_sua_lan_kiem'){const r=sb.tables.iqc_lan_kiem.find(x=>x.id===args.p_id);Object.assign(r,args.p_lan,{sua_luc:new Date().toISOString()});sb.tables.iqc_lan_kiem_loi=sb.tables.iqc_lan_kiem_loi.filter(x=>x.lan_kiem_id!==r.id);for(const d of args.p_lan.loi)sb.tables.iqc_lan_kiem_loi.push({id:seq++,lan_kiem_id:r.id,...d});return {data:{lot_id:r.lot_id},error:null};}return old(name,args)};`});
  await page.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname!=='mes.test'||['/shared/supabase-client.js','/shared/navbar.js'].includes(u.pathname))return route.fulfill({body:'',contentType:'application/javascript'});const f=path.resolve('.'+decodeURIComponent(u.pathname));if(!f.startsWith(process.cwd()+path.sep)||!fs.existsSync(f))return route.fulfill({status:404,body:''});return route.fulfill({body:fs.readFileSync(f),contentType:f.endsWith('.js')?'application/javascript':f.endsWith('.css')?'text/css':'text/html'});});
  await page.goto('https://mes.test/iqc.html');await page.waitForSelector('#iqcMultiEntry');
  await page.locator('#receivedDate').fill('2026-11-20T08:00');await page.locator('#supplier').selectOption('BRV');
  await page.locator('#productCode').fill('MULTI');await page.waitForFunction(()=>document.querySelector('#productName').value==='Model test');
  await page.locator('#lotNo').fill('LOT-100');await page.locator('#lotQty').fill('10000');await page.locator('#iqcScope').selectOption('Đúc');
  await page.locator('#inspectionType').selectOption('Kiểm tra 100%');await page.locator('#inspector').fill('QC01_Trần QC');
  await page.locator('#iqcMultiChecked').fill('2000');await page.locator('#iqcMultiOk').fill('1980');await page.locator('#iqcMultiNg').fill('20');
  await page.locator('#iqcMultiAdd').click();await page.locator('#iqcMultiRows .name').fill('Xước');await page.locator('#iqcMultiRows .qty').fill('20');
  await page.locator('#saveBtn').click();await page.waitForFunction(()=>sb.tables.iqc_lan_kiem.length===1);
  assert.equal(await page.evaluate(()=>sb.tables.iqc_lan_kiem_loi[0].ten_loi),'Xước');
  await page.waitForFunction(()=>document.querySelector('#iqcMultiProgress').textContent.includes('Đã kiểm 2000'));
  await page.locator('#iqcMultiChecked').fill('3000');await page.locator('#iqcMultiOk').fill('2960');await page.locator('#iqcMultiNg').fill('40');await page.locator('#saveBtn').click();
  await page.waitForFunction(()=>sb.tables.iqc_lan_kiem.length===2,{},{timeout:5000}).catch(async e=>{console.error('STATUS',await page.locator('#iqcMultiStatus').textContent(), 'INVALID',await page.locator(':invalid').evaluateAll(es=>es.map(x=>x.id)), 'ERRORS',errors);throw e});await page.waitForFunction(()=>document.querySelector('#iqcMultiProgress').textContent.includes('Đã kiểm 5000'));
  assert.equal(await page.locator('#lotNo').evaluate(e=>e.readOnly),true);
  await page.locator('#iqcMultiHistory button').first().click();await page.locator('#iqcMultiChecked').fill('1000');await page.locator('#iqcMultiOk').fill('990');await page.locator('#iqcMultiNg').fill('10');await page.locator('#saveBtn').click();
  await page.waitForFunction(()=>document.querySelector('#iqcMultiProgress').textContent.includes('Đã kiểm 4000'));
  await page.evaluate(()=>showPage('stats'));await page.locator('#iqcMLot').fill('LOT-100');
  assert.equal(await page.locator('#iqcMultiTable tr').count(),1);assert.match(await page.locator('#iqcMultiTable').textContent(),/4000/);
  assert.deepEqual(errors,[]);console.log('PASS visual LOT creation with defect, continued inspection and LOT dashboard');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
