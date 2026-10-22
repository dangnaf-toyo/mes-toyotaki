const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {chromium}=require(process.env.MES_PLAYWRIGHT_PATH||'playwright');
const {backend}=require('./oqc-dashboard-fixture.cjs');
(async()=>{const browser=await chromium.launch({channel:'chrome',headless:true});try{
 const context=await browser.newContext({viewport:{width:1440,height:1000},timezoneId:'America/Los_Angeles'}),page=await context.newPage(),errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 await context.addInitScript({content:'window.sb=('+backend.toString()+')();window.MesAuth={requireAuth:async()=>({user:{id:"u1"}}),getSession:async()=>({user:{id:"u1"}}),getCurrentUserIdentity:async()=>"Admin"};window.MesNav={setTitle(){}};'});
 await context.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname!=='mes.test'||['/shared/supabase-client.js','/shared/navbar.js'].includes(u.pathname))return route.fulfill({body:'',contentType:'application/javascript'});const file=path.resolve('.'+decodeURIComponent(u.pathname));if(!file.startsWith(process.cwd()+path.sep)||!fs.existsSync(file))return route.fulfill({status:404,body:''});return route.fulfill({body:fs.readFileSync(file),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':'text/html'});});
 await page.goto('https://mes.test/oqc-daily.html');await page.waitForFunction(()=>OqcDashboard.getSnapshot()?.plans.length===2);
 assert.equal(await page.locator('#oqcReportDialog').evaluate(e=>e.open),false);
 assert.equal(await page.locator('#from').inputValue(),await page.evaluate(()=>sb.day));
 await page.screenshot({path:'.review/oqc-dashboard-desktop.png',fullPage:true});
 console.log('PASS Chromium startup: dashboard loads without clicking Xem, Bangkok today, report initially closed');
 await page.locator('#oqcOpenCapa').click();await page.locator('#oqcCapaModel').selectOption('A');
 await page.waitForFunction(()=>document.getElementById('oqcCapaPreview').textContent.includes('1.260'));
 await page.screenshot({path:'.review/oqc-dashboard-capa.png',fullPage:true});await page.locator('#oqcCapaClose').click();
 for(const [code,qty,hours]of [['A',630,3.5],['A',630,3.5],['B',360,2]]){
  const before=await page.evaluate(()=>sb.tables.oqc_daily_inspection.length);await page.locator('#oqcNewReport').click();
  await page.locator('#code').selectOption(code);await page.locator('#inspectorCode').selectOption('QC01');await page.locator('#total').fill(String(qty));
  for(const input of await page.locator('#defects .defect').all())await input.fill('2');
  await page.locator('#oqcInspectionHours').fill(String(hours).replace('.',','));
  if(before===0){await page.locator('#oqcReportPhotos').setInputFiles({name:'fault.png',mimeType:'image/png',buffer:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jvhoAAAAASUVORK5CYII=','base64')});}
  await page.locator('#save').click();await page.waitForFunction(n=>sb.tables.oqc_daily_inspection.length===n,before+1);
  await page.waitForFunction(()=>!document.getElementById('oqcReportDialog').open);
 }
 await page.waitForFunction(()=>OqcDashboard.getSnapshot()?.records.length===3);
 assert.deepEqual(await page.evaluate(()=>{const s=OqcDashboardMath.summary(OqcDashboard.getSnapshot().records,OqcDashboard.getSnapshot().plans);return [s.checked,s.ng,s.hours,s.people,Math.round(s.efficiency)];}),[1620,12,9,1,90]);
 await page.screenshot({path:'.review/oqc-dashboard-results.png',fullPage:true});console.log('PASS Chromium report workflow: three submissions, correct calculated NG/unique person and allocated hours, 90% efficiency');
 await page.locator('#modelSummary button').first().click();await page.locator('#oqcModelRecords button').last().click();
 assert.match(await page.locator('#oqcRecordBody').textContent(),/Worker One/);assert.equal(await page.locator('#oqcRecordBody img').count(),1);await page.locator('#oqcRecordBody img').click();await page.locator('.qc-zoom-viewer').getByRole('button',{name:'Phóng to +',exact:true}).click();await page.locator('.qc-zoom-viewer').getByRole('button',{name:'Đóng ×',exact:true}).click();await page.locator('#oqcRecordClose').click();await page.locator('#oqcModelClose').click();
 await page.locator('#period').selectOption('week');await page.waitForFunction(()=>OqcDashboard.getSnapshot()?.from===document.getElementById('from').value&&document.getElementById('period').value==='week');
 console.log('PASS Chromium model detail and weekly filters use the current range');
 await page.setViewportSize({width:390,height:844});await page.screenshot({path:'.review/oqc-dashboard-mobile.png',fullPage:true});
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Dashboard has horizontal overflow');
 await page.locator('#oqcNewReport').click();await page.screenshot({path:'.review/oqc-dashboard-report-mobile.png',fullPage:true});
 assert.ok(await page.locator('#oqcReportDialog').evaluate(e=>e.getBoundingClientRect().width<=innerWidth));
 await page.locator('#oqcReportDialog .head button').click();await page.locator('#oqcOpenCapa').click();await page.locator('#oqcCapaModel').selectOption('A');await page.screenshot({path:'.review/oqc-dashboard-capa-mobile.png',fullPage:true});
 assert.ok(await page.locator('#oqcCapaDialog').evaluate(e=>e.getBoundingClientRect().width<=innerWidth));assert.deepEqual(errors,[]);
 console.log('PASS Chromium mobile: dashboard/form/CAPA fit viewport, tables scroll; no page errors (mock APIs)');
 await page.goto('https://mes.test/khsx-tuan.html?cd=OQC');await page.waitForFunction(()=>document.getElementById('panelCd').classList.contains('active')&&document.getElementById('qc-week-staff-summary')?.textContent.includes('90%'),null,{timeout:5000}).catch(async e=>{throw Error(JSON.stringify({errors,state:await page.evaluate(()=>({active:document.querySelector('.tab-btn.active')?.textContent,summary:document.getElementById('qc-week-staff-summary')?.textContent,msg:document.getElementById('msg')?.textContent}))}));});assert.equal(await page.locator('#panelDuc').evaluate(e=>e.classList.contains('active')),false);assert.equal(await page.locator('.tab-btn.active').textContent(),'OQC');assert.deepEqual(errors,[]);console.log('PASS Chromium existing weekly plan link opens OQC panel and 90% staffing directly');await context.close();
}finally{await browser.close();}})().catch(e=>{console.error(e.stack||e);process.exitCode=1;});
