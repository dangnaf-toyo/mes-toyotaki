// Offline contract and auth tests; no live Supabase writes or credentials.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
(async () => {
  const {buildDirectory} = await import('../supabase/functions/qc02-personnel-directory/directory.mjs');
  const master=[{ma_nv:'old1',ten_nhan_vien:'Staff',vai_tro:'oqc',bo_phan:'OQC'},
    {ten_nhan_vien:'Same Name',vai_tro:'nhan_vien',bo_phan:'Đúc'}];
  const accounts=[{user_id:'U1',username:'OLD1',full_name:'Staff account',role:'nhan_vien_oqc',bo_phan_phu_trach:['OQC']},
    {user_id:'U2',username:'NEWQC',full_name:'New QC',role:'nhan_vien_oqc',bo_phan_phu_trach:['OQC']},
    {user_id:'U3',username:'LOCKED',full_name:'Locked QC',role:'nhan_vien_oqc'},
    {user_id:'U4',username:'OTHER',full_name:'Same Name',role:'nhan_vien_duc'}];
  const users=[{id:'U1'},{id:'U2'},{id:'U3',banned_until:'2099-01-01T00:00:00Z'},{id:'U4'}];
  const rows=buildDirectory(master,accounts,users);
  assert.equal(rows.filter(r=>r.code.toLowerCase()==='old1').length,1);
  assert.equal(rows.find(r=>r.code==='OLD1').linked,true);
  assert(rows.some(r=>r.code==='NEWQC'&&r.roles.includes('oqc')&&r.departments.includes('OQC')));
  assert(!rows.some(r=>r.code==='LOCKED'));
  assert.equal(rows.filter(r=>r.name==='Same Name').length,2,'names do not imply identity');
  assert(rows.every(r=>!('email' in r)&&!('user_id' in r)&&!('banned_until' in r)));
  let handler,token='valid',role='nhan_vien_oqc',reads=0;
  const tables={master_employees:master,user_roles:accounts};
  const client={auth:{getUser:async jwt=>({data:{user:jwt===token?{id:'U2'}:null},error:null}),
    admin:{listUsers:async()=>({data:{users},error:null})}},from(table){
    let caller=false;const q={select(){return q},eq(){caller=true;return q},maybeSingle:async()=>({data:role?{role}:null,error:null}),order(){return q},range:async(a,b)=>{reads++;return {data:tables[table].slice(a,b+1),error:null}}};return q;
  }};
  const context={Response,Request,Date,Map,Set,JSON,Error,buildDirectory,createClient:()=>client,
    Deno:{env:{get:()=> 'server-only'},serve:h=>handler=h}};
  const source=require('node:module').stripTypeScriptTypes(fs.readFileSync('supabase/functions/qc02-personnel-directory/index.ts','utf8')).replace(/^import .*;\r?\n/gm,'');
  new vm.Script(source).runInNewContext(context);
  const call=auth=>handler(new Request('https://example.invalid',{method:'POST',headers:auth?{Authorization:'Bearer '+auth}:{}}));
  assert.equal((await call()).status,401);assert.equal((await call('invalid')).status,401);assert.equal(reads,0);
  role=null;assert.equal((await call('valid')).status,403);assert.equal(reads,0);role='nhan_vien_oqc';
  const response=await call('valid');assert.equal(response.status,200);const data=await response.json();
  assert(data.complete&&data.employees.some(r=>r.code==='NEWQC'));
  assert.equal(response.headers.get('cache-control'),'no-store');
  assert.equal((await handler(new Request('https://example.invalid',{method:'GET'}))).status,405);
  console.log('PASS: new account/employee, role/department, coded mapping, homonyms, banned account, minimal fields, auth 401/403, read-only handler');
})().catch(e=>{console.error(e);process.exitCode=1;});
