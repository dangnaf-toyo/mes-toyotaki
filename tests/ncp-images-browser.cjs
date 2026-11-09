// Real Chromium + current complete pages. APIs/storage are fixtures; SQL tests cover live staging RPCs.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const {chromium}=require(process.env.MES_PLAYWRIGHT_PATH||'playwright');
const fixture=fs.readFileSync('tests/qc-session-ui.cjs','utf8');
const baseline=fixture.slice(fixture.indexOf('const job='),fixture.indexOf('function page('));
function attachmentsBackend(){
  window.sbTaiHet=async makeQuery=>makeQuery();
  const uid='00000000-0000-0000-0000-000000000001',db=window.sb;
  const saved=JSON.parse(localStorage.getItem('ncp-image-test')||'null')||{cases:[],photos:[],audit:[],requests:{},uploads:[]};
  Object.assign(db.tables,{duc_ncp:saved.cases,duc_ncp_theo_doi:saved.cases,ncp_hinh_anh:saved.photos,ncp_hinh_anh_lich_su:saved.audit,ncp_doi_sach:[],duc_tem_cach_ly:[],master_machines:[{ma_may:'DC6'}]});
  db.tables.duc_ipqc_checkpoint[0].ket_qua='NG';db.tables.duc_ipqc_checkpoint[0].so_khuon='M1';
  db.tables.duc_ipqc_checkpoint[0].anh_bang_chung_url=['https://mes.test/fixture.jpg?checkpoint'];
  db.tables.user_roles[0].user_id=uid;
  db.editable=true;db.imageState=saved;db.failUpload=false;db.failCreateResponse=false;db.failAddResponse=false;
  const persist=()=>localStorage.setItem('ncp-image-test',JSON.stringify(saved));
  const add=(id,images)=>{for(const image of images){if(saved.photos.some(p=>p.storage_path===image.path))continue;
    const p={id:crypto.randomUUID(),id_ncp:id,storage_path:image.path,ten_file:image.name,xoa_luc:null,them_luc:new Date().toISOString()};
    saved.photos.push(p);saved.audit.push({id_anh:p.id,id_ncp:id,thao_tac:'them',ten_file:image.name,ten_nguoi:'Inspector',thoi_diem:new Date().toISOString()});}};
  const original=db.rpc.bind(db);
  db.rpc=async(name,args={})=>{
    if(name==='qc_danh_sach_tai_khoan')return {data:[{user_id:uid,username:'NV01',full_name:'Inspector',role:'admin'}]};
    if(name==='ncp_anh_duoc_sua')return {data:db.editable};
    if(name==='duc_get_available_ng_checkpoints_for_ncp')return {data:[{id_checkpoint:'CP-A',ma_may:'DC6',ma_sp:'MODEL-A',so_khuon:'M1',thoi_diem_kiem_thuc_te:new Date().toISOString(),mo_ta_de_xuat:'NG source'}]};
    if(name==='ncp_mo_phieu_co_anh'){
      db.calls.push({name,args});
      if(!saved.requests[args.p_request_id]){
        const d=args.p_data,id='NCP-'+(saved.cases.length+1),c={id_ncp:id,id_checkpoint_goc:d.p_id_checkpoint_goc||null,ma_may:'DC6',ma_sp:'MODEL-A',ten_sp:'Model A',so_khuon:'M1',ngay_tao:new Date().toISOString(),rc_trang_thai_duyet:'nhap',trang_thai:'da_cach_ly',mo_ta_loi:d.description||d.p_mo_ta_loi,nguoi_dam_nhiem:'Inspector',nguoi_dam_nhiem_doi_sach:'Inspector',han_tra_loi_doi_sach:d.response_due||d.p_han_tra_loi_doi_sach,source_images:[],nguoi_mo_uid:uid};
        for(const k of ['nghi_van','ng_du_kien','da_loc','loc_ok','loc_ng','sua_ok','sua_khong_duoc','de_nghi_phe','phe_da_duyet'])c['so_luong_'+k]=k==='nghi_van'?10:0;
        saved.cases.push(c);saved.requests[args.p_request_id]=id;add(id,args.p_images);persist();
      }
      if(db.failCreateResponse){db.failCreateResponse=false;return {error:{message:'Network response lost'}};}
      return {data:{ok:true,id_ncp:saved.requests[args.p_request_id]}};
    }
    if(name==='ncp_anh_them'){
      if(!db.editable)return {error:{message:'Forbidden'}};
      add(args.p_id_ncp,args.p_images);persist();
      if(db.failAddResponse){db.failAddResponse=false;return {error:{message:'Network response lost'}};}return {data:null};
    }
    if(name==='ncp_anh_xoa'){
      if(!db.editable)return {error:{message:'Forbidden'}};
      const p=saved.photos.find(p=>p.id===args.p_id);p.xoa_luc=new Date().toISOString();
      saved.audit.push({id_anh:p.id,id_ncp:p.id_ncp,thao_tac:'xoa',ten_file:p.ten_file,ten_nguoi:'Inspector',thoi_diem:p.xoa_luc});persist();return {data:null};
    }
    return original(name,args);
  };
  db.storage={from(bucket){return {
    async upload(p,blob,options){if(db.failUpload){db.failUpload=false;return {error:{message:'Upload failed'}};}
      db.uploads.push({bucket,path:p,type:blob.type,size:blob.size,options});saved.uploads.push(p);persist();return {data:{path:p}};},
    async createSignedUrl(p){return {data:{signedUrl:'https://mes.test/fixture.jpg?path='+encodeURIComponent(p)}};}
  };}};
}
(async()=>{
  for(const file of ['qc-manager.html','ncp-detail.html'])for(const m of fs.readFileSync(file,'utf8').matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g))if(m[1].trim())new vm.Script(m[1],{filename:file});
  const browser=await chromium.launch({channel:'chrome',headless:true});
  try{
    const context=await browser.newContext({viewport:{width:1366,height:950}}),page=await context.newPage(),errors=[],dialogs=[];
    page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>{dialogs.push(d.message());d.accept();});
    await context.addInitScript({content:baseline+`window.sb=database({role:'admin'});window.MesAuth={getSession:async()=>({user:{id:'00000000-0000-0000-0000-000000000001'}}),requireAuth:async()=>({user:{id:'00000000-0000-0000-0000-000000000001'}}),getCurrentUserIdentity:async()=>'NV01_Inspector'};window.MesNav={setTitle(){}};(${attachmentsBackend.toString()})();`});
    let jpeg;
    await context.route('**/*',route=>{
      const u=new URL(route.request().url());
      if(u.pathname==='/fixture.jpg')return route.fulfill({body:jpeg,contentType:'image/jpeg'});
      if(u.hostname!=='mes.test'||['/shared/supabase-client.js','/shared/navbar.js'].includes(u.pathname))return route.fulfill({body:'',contentType:'application/javascript'});
      const file=path.resolve('.'+decodeURIComponent(u.pathname));
      if(!file.startsWith(process.cwd()+path.sep)||!fs.existsSync(file))return route.fulfill({status:404,body:''});
      return route.fulfill({body:fs.readFileSync(file),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':'text/html'});
    });
    await page.goto('https://mes.test/qc-manager.html?tab=ncp');
    const images=await page.evaluate(()=>{const c=document.createElement('canvas');c.width=480;c.height=300;const x=c.getContext('2d');x.fillStyle='#eef2ff';x.fillRect(0,0,480,300);x.fillStyle='#b91c1c';x.font='24px sans-serif';x.fillText('NCP - defect example',30,120);return Object.fromEntries(['jpeg','png','webp'].map(t=>[t,c.toDataURL('image/'+t).split(',')[1]]));});
    jpeg=Buffer.from(images.jpeg,'base64');
    const file=(name,type='jpeg')=>({name,mimeType:'image/'+type,buffer:Buffer.from(images[type],'base64')});
    const upload=page.locator('#ncp-new-images input[type=file]'),thumbs=page.locator('#ncp-new-images .ncp-defect-thumb');
    const open=async()=>{await page.evaluate(async()=>{state.machines=['DC6'];state.products=['MODEL-A'];state.productMap={'MODEL-A':'Model A'};await openNcpNewModal();});};
    const fill=async manual=>{
      if(manual){await page.locator('input[name=ncp-src][value=thu_cong]').check();await page.locator('#ncp-source-type').selectOption('department');await page.locator('#ncp-source-department').fill('Gia công');await page.locator('#ncp-source-product').fill('MODEL-A');await page.locator('#ncp-source-product').dispatchEvent('change');}
      else {await page.locator('#ncp-src-ng').selectOption('CP-A');await page.locator('#ncp-ma-may').evaluate(e=>e.value='DC6');await page.locator('#ncp-ma-sp').evaluate(e=>e.value='MODEL-A');await page.locator('#ncp-ten-sp').evaluate(e=>e.value='Model A');await page.locator('#ncp-so-khuon').evaluate(e=>e.value='M1');}
      for(const [id,value]of Object.entries({'ncp-mo-ta-loi':'Defect fixture','ncp-so-luong':'10','ncp-so-luong-ng-du-kien':'1','ncp-vi-tri':'QC fixture','ncp-nguoi-dam-nhiem':'NV01','ncp-nguoi-dam-nhiem-doi-sach':'NV01','ncp-han-tra-loi':'2026-11-10'}))await page.locator('#'+id).fill(value);
    };
    const save=async()=>{await page.evaluate(()=>submitNcpNewCase());};
    await open();await fill(true);await upload.setInputFiles(file('first.jpg'));await thumbs.waitFor();assert.equal(await thumbs.count(),1);
    await thumbs.locator('.ncp-defect-open').click();await page.locator('dialog[open]').waitFor();await page.keyboard.press('Escape');
    await save();assert.equal(await page.evaluate(()=>sb.imageState.cases.length),1);assert.equal(await page.evaluate(()=>sb.imageState.photos.length),1);
    console.log('PASS create manual case with one JPEG; immediate thumbnail and enlarge');
    await open();await fill(false);await upload.setInputFiles([file('second.png','png'),file('third.webp','webp')]);await page.waitForFunction(()=>document.querySelectorAll('#ncp-new-images .ncp-defect-thumb').length===2);
    await thumbs.first().getByRole('button',{name:'Xóa ảnh',exact:true}).click();assert.equal(await thumbs.count(),1);
    const chooser=page.waitForEvent('filechooser');await thumbs.first().getByRole('button',{name:'Thay ảnh',exact:true}).click();await (await chooser).setFiles(file('replacement.jpeg'));await page.waitForFunction(()=>document.querySelector('#ncp-new-images .ncp-defect-thumb span')?.textContent==='replacement.jpeg');
    await upload.setInputFiles(file('fourth.png','png'));await page.waitForFunction(()=>document.querySelectorAll('#ncp-new-images .ncp-defect-thumb').length===2);
    await page.screenshot({path:'.review/ncp-images-create.png'});
    await page.evaluate(()=>sb.failCreateResponse=true);await save();assert.equal(await page.evaluate(()=>sb.imageState.cases.length),2);assert.equal(await page.locator('#ncp-modal-new.show').count(),1);
    await save();assert.equal(await page.evaluate(()=>sb.imageState.cases.length),2);assert.equal(await page.evaluate(()=>sb.imageState.photos.length),3);
    const types=await page.evaluate(()=>sb.uploads.map(u=>u.type));assert.ok(types.every(t=>t==='image/jpeg'));
    console.log('PASS NG-linked case with PNG/WEBP, remove/replace before save, inert JPEG storage, lost response retry without duplicate');
    await open();await fill(true);await save();assert.equal(await page.evaluate(()=>sb.imageState.cases.length),3);assert.equal(await page.evaluate(()=>sb.imageState.photos.length),3);
    console.log('PASS create with no photos');
    await open();await fill(true);
    for(const bad of [{name:'bad.svg',mimeType:'image/svg+xml',buffer:Buffer.from('<svg onload="alert(1)"/>')},{name:'fake.png',mimeType:'image/png',buffer:Buffer.from('<script>alert(1)</script>')},{name:'big.jpg',mimeType:'image/jpeg',buffer:Buffer.alloc(5242881)}]){
      await upload.setInputFiles(bad);await page.waitForFunction(()=>document.querySelector('#ncp-new-images .ncp-image-error'));assert.equal(await thumbs.count(),0);
    }
    assert.equal(await page.evaluate(()=>sb.imageState.cases.length),3);console.log('PASS disallowed type, disguised script, oversized file rejected without changing case');
    await page.goto('https://mes.test/ncp-detail.html?id=NCP-2');
    const section=page.locator('#ncp-case-images');await page.waitForFunction(()=>document.querySelectorAll('#ncp-case-images .ncp-defect-thumb').length===2);
    assert.equal(await section.locator('img').evaluateAll(imgs=>imgs.every(i=>i.complete&&i.naturalWidth>0)),true);
    const before=await page.evaluate(()=>JSON.stringify(sb.imageState.cases[1]));
    await section.locator('input[type=file]').setInputFiles(file('after.jpg'));await page.waitForFunction(()=>document.querySelectorAll('#ncp-case-images .ncp-defect-thumb').length===3);
    await page.evaluate(()=>sb.failUpload=true);await section.getByRole('button',{name:'Lưu ảnh bổ sung',exact:true}).click();await page.waitForFunction(()=>document.querySelector('#ncp-case-images .ncp-image-error'));
    assert.equal(await page.evaluate(()=>sb.imageState.photos.filter(p=>p.id_ncp==='NCP-2'&&!p.xoa_luc).length),2);
    await page.evaluate(()=>sb.failAddResponse=true);await section.getByRole('button',{name:'Lưu ảnh bổ sung',exact:true}).click();await page.waitForFunction(()=>document.querySelector('#ncp-case-images .ncp-image-error')?.textContent.includes('Network response lost'));
    await section.getByRole('button',{name:'Lưu ảnh bổ sung',exact:true}).click();await page.waitForFunction(()=>document.querySelector('#ncp-case-images [role=status]').textContent==='Đã lưu hình ảnh.');
    assert.equal(await page.evaluate(()=>sb.imageState.photos.filter(p=>p.id_ncp==='NCP-2'&&!p.xoa_luc).length),3);
    await section.getByRole('button',{name:'Xóa ảnh',exact:true}).first().click();await page.waitForFunction(()=>document.querySelectorAll('#ncp-case-images .ncp-defect-thumb').length===2);
    await section.locator('summary').click();assert.match(await section.locator('details').textContent(),/Xóa/);assert.equal(await page.evaluate(()=>JSON.stringify(sb.imageState.cases[1])),before);
    await page.screenshot({path:'.review/ncp-images-detail.png',fullPage:true});
    await page.reload();await page.waitForFunction(()=>document.querySelectorAll('#ncp-case-images .ncp-defect-thumb').length===2);
    assert.ok(await section.locator('img').evaluateAll(imgs=>imgs.every(i=>i.complete&&i.naturalWidth>0)));
    assert.equal(await page.locator('#btn-print').count(),1);assert.equal(await page.locator('#btn-save').count(),1);
    assert.equal(await page.locator('#ipqc-evidence img').count(),1);
    assert.equal(await page.evaluate(()=>state.ipqcEvidence.length),3);
    const printCount=await page.evaluate(()=>{Qc02Ncp.printable(state.case,state.checkpoint,state.ipqcEvidence,state.images,state.doiSach,state.cachLy);const count=document.querySelectorAll('#qc02-print img').length;document.getElementById('qc02-print')?.remove();return count;});
    assert.ok(printCount>=3,'Print lost attached/checkpoint evidence');
    console.log('PASS reopen/reload persisted photos; append/retry/delete with history; case fields and print/countermeasure controls preserved');
    await page.evaluate(async()=>{sb.editable=false;await ncpCaseImages.load(state.id);});assert.equal(await section.getByRole('button',{name:'+ Thêm ảnh',exact:true}).isVisible(),false);assert.equal(await section.getByRole('button',{name:'Xóa ảnh',exact:true}).count(),0);
    await section.locator('.ncp-defect-open').first().click();await page.locator('dialog[open]').waitFor();await page.keyboard.press('Escape');
    console.log('PASS readonly user can view/enlarge, cannot add/delete');
    await page.evaluate(async()=>{sb.editable=true;await ncpCaseImages.load(state.id);});await page.setViewportSize({width:390,height:844});await page.screenshot({path:'.review/ncp-images-mobile.png',fullPage:true});
    assert.ok(await section.evaluate(el=>el.scrollWidth<=el.clientWidth+1));
    assert.deepEqual(errors,[]);console.log('PASS mobile attachment layout, inline script syntax, no browser errors');
    await context.close();
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
