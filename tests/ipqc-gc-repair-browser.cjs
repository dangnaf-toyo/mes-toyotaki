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
   }else {
    await page.waitForFunction(()=>document.querySelectorAll('#gcMeasureRows [data-result]').length===6);
    assert.equal(await page.locator('#gcMeasureRows table').count(),1);
    assert.equal(await page.locator('#gcSaveMeasure').isDisabled(),true);
    const input=(no,sample)=>page.locator('[data-result][data-no="'+no+'"][data-sample="'+sample+'"]');
    for(const [no,values]of [[1,['20.02','20.01']],[2,['38.12','38.0']],[3,['15.15','15.0']]])
     for(let i=0;i<values.length;i++)await input(no,i+1).fill(values[i]);
    assert.equal(await input(3,1).evaluate(e=>e.classList.contains('measure-ng')),true);
    assert.ok((await page.locator('#gcMeasureSummary').textContent()).includes('NG'),
      await page.locator('#gcMeasureRows').textContent()+' / '+await page.locator('#gcMeasureSummary').textContent());
    await input(1,1).focus();await page.keyboard.press('Enter');
    assert.equal(await input(1,2).evaluate(e=>e===document.activeElement),true);
    await page.locator('#gcAddSample').click();
    assert.equal(await page.locator('#gcMeasureRows [data-result]').count(),9);
    assert.equal(await input(1,1).inputValue(),'20.02');
    assert.equal(await page.locator('#gcSaveMeasure').isDisabled(),true);
    for(const [no,value]of [[1,'20'],[2,'38.1'],[3,'15']])await input(no,3).fill(value);
    await page.locator('#gcLot').fill('LOT-MANUAL');
    await page.locator('#gcSaveMeasure').click();
    await page.waitForFunction(()=>sb.tables.ipqc_gc_lan.length===1);
    assert.equal(await page.evaluate(()=>sb.tables.ipqc_gc_lan[0].dat),false);
    assert.equal(await page.evaluate(()=>sb.calls.find(c=>c.name==='ipqc_gc_luu_do').args.p_data.kq.length),9);
    await page.screenshot({path:'.review/ipqc-gc-entry.png',fullPage:true});
   }
   await page.locator('[data-tab=dashboard]').click();
   if(empty)await page.waitForFunction(()=>document.getElementById('gcDataRows').textContent.includes('Chưa có dữ liệu'));
   else await page.waitForFunction(()=>document.getElementById('gcDataRows').textContent.includes('LOT-MANUAL'));
   assert.deepEqual(errors,[]);await context.close();
  }
  console.log('PASS real Chromium/catalog implementation: machine order uses ma_may; empty standards/dashboard are normal states; released features load');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
