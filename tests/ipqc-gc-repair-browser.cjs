const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const {chromium}=require(process.env.MES_PLAYWRIGHT_PATH||'playwright');
const {backend}=require('./ipqc-gc-fixture.cjs');
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try{
  for(const empty of [true,false]){
   const context=await browser.newContext({viewport:{width:1366,height:900}}),page=await context.newPage(),errors=[];
   page.on('pageerror',e=>errors.push(e.message));
   await context.addInitScript({content:`window.sb=(${backend.toString()})({empty:${empty}});
    window.IS_PROD=false;window.MesAuth={getSession:async()=>({user:{id:'u1'}}),getCurrentUserIdentity:async()=>'Inspector'};
    window.MesNav={setTitle(){}};window.sbTaiHet=async make=>await make();`});
   await context.route('**/*',route=>{
    const url=new URL(route.request().url());
    if(url.hostname!=='mes.test'||['/shared/supabase-client.js','/shared/navbar.js'].includes(url.pathname))
     return route.fulfill({body:'',contentType:'application/javascript'});
    const file=path.resolve('.'+decodeURIComponent(url.pathname));
    if(!file.startsWith(process.cwd()+path.sep)||!fs.existsSync(file))return route.fulfill({status:404,body:''});
    return route.fulfill({body:fs.readFileSync(file),contentType:file.endsWith('.js')?'application/javascript':
     file.endsWith('.css')?'text/css':'text/html'});
   });
   await page.goto('https://mes.test/ipqc-gia-cong.html');
   await page.waitForFunction(()=>document.getElementById('gcMachine').options.length===1);
   assert.equal(await page.locator('#gcErrorDetails').isVisible(),false);
   assert.equal(await page.evaluate(()=>sb.orders.some(x=>x.table==='master_machines'&&x.column==='ten_nhan_vien')),false);
   await page.locator('[data-tab=measure]').click();
   await page.locator('#gcMeasureProduct').fill('PART');
   await page.locator('#gcMeasureProduct').dispatchEvent('change');
   if(empty){
    await page.waitForFunction(()=>document.getElementById('gcMeasureInfo').textContent.includes('Chưa có tiêu chuẩn'));
    assert.equal(await page.locator('#gcSaveMeasure').isDisabled(),true);
   }else await page.waitForFunction(()=>document.querySelectorAll('#gcMeasureRows [data-result]').length===6);
   await page.locator('[data-tab=dashboard]').click();
   await page.waitForFunction(()=>document.getElementById('gcDataRows').textContent.includes('Chưa có dữ liệu'));
   assert.deepEqual(errors,[]);await context.close();
  }
  console.log('PASS real Chromium/catalog implementation: machine order uses ma_may; empty standards/dashboard are normal states; released features load');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
