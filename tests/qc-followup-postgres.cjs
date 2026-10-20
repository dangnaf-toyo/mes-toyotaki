/* T122 uses existing PostgreSQL behavior fixture. Never connects to live DB. */
module.exports=async({db,query,test,read})=>{
 const assert=require('assert/strict'),M=require('../shared/oqc-capacity-math.js');
 const value=async(sql,args=[])=>(await query(sql,args))[0].v;
 await db.exec(`create function auth.role() returns text language sql as $$select 'authenticated'::text$$;grant usage on schema auth to authenticated;grant execute on function auth.uid(),auth.role() to authenticated;`);
 await db.exec(read('supabase/migration_phase_T8_cong_doan_khsx_tuan.sql'));
 await db.exec(`grant select,insert,update,delete on cd_khsx_tuan_plan to authenticated;grant usage,select on sequence cd_khsx_tuan_plan_id_seq to authenticated;
 create table khsx_duyet(id bigserial primary key,tuan_bat_dau date,cong_doan text,trang_thai text,updated_by text,updated_at timestamptz,unique(tuan_bat_dau,cong_doan));
 create table khsx_thay_doi_log(id bigserial primary key,tuan_bat_dau date,cong_doan text,loai_su_kien text,vi_tri text,gia_tri_cu text,gia_tri_moi text,ly_do text,nguoi_thuc_hien text);`);
 const log=read('supabase/migration_phase_T11_khsx_quy_trinh_duyet.sql'),a=log.indexOf('create or replace function khsx_ghi_log_sua('),b=log.indexOf('$$;',log.indexOf('as $$',a));await db.exec(log.slice(a,b+3));
 const before=await query("select id_checkpoint,ket_qua,thoi_gian_kiem_giay from duc_ipqc_checkpoint where trang_thai='da_kiem' order by id_checkpoint");
 await test('T122 migration applies twice, preserves completed inspection history and has no plan backfill',async()=>{await db.exec(read('supabase/migration_phase_T122_qc_followup_staging.sql'));await db.exec(read('supabase/migration_phase_T122_qc_followup_staging.sql'));assert.deepEqual(await query("select id_checkpoint,ket_qua,thoi_gian_kiem_giay from duc_ipqc_checkpoint where trang_thai='da_kiem' order by id_checkpoint"),before);assert.equal(Number(await value('select count(*) as v from cd_khsx_tuan_plan')),0);});
 await test('IPQC stops at successful server write, not prepare/upload; invalid saves keep session and all 3 outcomes work',async()=>{
  for(const [n,result]of ['OK','NG','CANH_BAO'].entries()){
   const id='FOLLOW-'+n;await db.query("insert into duc_ipqc_checkpoint(id_checkpoint,ma_may,ma_sp,trang_thai,loai_kiem) values($1,'TEST','MODEL-A','cho_kiem','dinh_ky')",[id]);await db.query('select duc_ipqc_session($1,true)',[id]);const start=await value('select started_at as v from duc_ipqc_inspection_session where checkpoint_id=$1',[id]);
   await db.query('select duc_ipqc_session_submit_time($1,false)',[id]);await assert.rejects(()=>db.query("select duc_submit_ipqc_session($1,'[{\"muc\":\"A\",\"dat\":null}]',$2,'[\"https://example.invalid/test.png\"]','QA',0,'Admin')",[id,result]),/đầy đủ/);assert.equal(await value('select completed_at as v from duc_ipqc_inspection_session where checkpoint_id=$1',[id]),null);
   await db.exec('select pg_sleep(0.03)');const checks=[{muc:'A',dat:result==='OK'},{code:'machine_condition',muc:'Machine',dat:true}];await db.query("select duc_submit_ipqc_session($1,$2,$3,'[\"https://example.invalid/test.png\"]','QA',99999,'Admin')",[id,JSON.stringify(checks),result]);
   const row=(await query('select * from duc_ipqc_inspection_session where checkpoint_id=$1',[id]))[0];assert.equal(row.started_at.getTime(),start.getTime());assert.ok(row.completed_at.getTime()-row.submission_at.getTime()>=20);const cp=(await query('select * from duc_ipqc_checkpoint where id_checkpoint=$1',[id]))[0];assert.equal(cp.ket_qua,result);assert.ok(Math.abs(Number(cp.thoi_gian_kiem_giay)-(row.completed_at-row.started_at)/1000)<.002);
  }
 });
 await db.exec("insert into master_products(ma_sp,ten_sp) values('MODEL-B','Model B'),('MODEL-C','Model C')");
 const verB=await value("select oqc_save_work_standard('MODEL-B','2026-01-01','[{\"name\":\"Check\",\"seconds\":30}]') as v");
 const day='2026-11-02',save=async(p)=>{const revision=Number(await value('select coalesce((select revision from oqc_capacity_day where work_date=$1),0) as v',[day]));return value('select qc_save_linked_plan($1) as v',[JSON.stringify({date:day,hours:'7',quantity:'1000',revision,source_kind:'manual',...p})]);};
 let srcB,oqcA;
 await test('manual and machining sources link existing weekly OQC row; retries replace quantities; total 3.0 people',async()=>{
  await save({product:'MODEL-A'});await save({product:'MODEL-A'});
  srcB=await value("insert into cd_khsx_tuan_plan(tuan_bat_dau,cong_doan,ma_sp,t2) values('2026-11-02','Gia Công','MODEL-B',1000) returning id as v");
  await save({product:'MODEL-B',source_kind:'machining',source_id:srcB});await save({product:'MODEL-B',source_kind:'machining',source_id:srcB});
  const r=await value('select oqc_capacity_report($1) as v',[day]);assert.equal(r.plans.length,2);assert.ok(r.plans.every(p=>Number(p.planned_qty)===1000));assert.ok(Math.abs(M.manpower(r.plans,7).fte-2.976190476)<1e-8);assert.equal(M.manpower(r.plans,7).fte.toLocaleString('vi-VN',{minimumFractionDigits:1,maximumFractionDigits:1}),'3,0');
  assert.equal(Number(await value("select count(*) as v from cd_khsx_tuan_plan where cong_doan='OQC' and tuan_bat_dau=$1",[day])),2);
  oqcA=await value("select id as v from cd_khsx_tuan_plan where cong_doan='OQC' and ma_sp='MODEL-A' and tuan_bat_dau=$1",[day]);
 });
 await test('OQC source updates exact source ID, no loop/double count; wrong source/model rejected; stale revision rejected',async()=>{
  await save({product:'MODEL-A',source_kind:'oqc',source_id:oqcA,quantity:'900'});await save({product:'MODEL-A',source_kind:'oqc',source_id:oqcA,quantity:'900'});assert.equal(Number(await value('select t2 as v from cd_khsx_tuan_plan where id=$1',[oqcA])),900);
  await assert.rejects(()=>save({product:'MODEL-A',source_kind:'machining',source_id:srcB}),/khớp/);
  await assert.rejects(()=>value('select qc_save_linked_plan($1) as v',[JSON.stringify({date:day,product:'MODEL-A',quantity:100,hours:7,revision:0,source_kind:'manual'})]),/thay đổi/);
 });
 await test('production edits sync same snapshot, preserve norm version and missing hours/norms stay NULL',async()=>{
  await value("select oqc_save_work_standard('MODEL-A','2026-01-01','[{\"name\":\"New\",\"seconds\":60}]') as v");
  await db.query('update cd_khsx_tuan_plan set t2=800 where id=$1',[oqcA]);assert.equal(Number(await value('select planned_qty as v from oqc_capacity_plan where work_date=$1 and product_code=\'MODEL-A\'',[day])),800);assert.equal(Number(await value('select seconds_per_piece as v from oqc_capacity_plan where work_date=$1 and product_code=\'MODEL-A\'',[day])),30);
  await db.exec("insert into cd_khsx_tuan_plan(tuan_bat_dau,cong_doan,ma_sp,t2) values('2026-11-09','OQC','MODEL-C',1000)");const r=await value("select oqc_capacity_report('2026-11-09') as v");assert.equal(r.day.hours_per_person,null);assert.equal(r.plans[0].seconds_per_piece,null);assert.equal(M.report(r).staffing.fte,null);
 });
 await test('authenticated weekly save persists quantity/hours atomically; model change re-rates only the edited plan; IPQC role cannot write QC plans',async()=>{
  const payload={tuan_bat_dau:'2026-11-16',cong_doan:'OQC',ma_sp:'MODEL-B',ten_sp:'Model B',t2:1000,t3:0,t4:0,t5:0,t6:0,t7:0,cn:0,kh_tuan:1000,ghi_chu:'QA',updated_by:'Admin'};
  await db.exec('set role authenticated');let id;try{id=await value('select qc_save_oqc_week(null,$1,$2) as v',[JSON.stringify(payload),JSON.stringify({0:'8'})]);}finally{await db.exec('reset role');}
  let r=await value("select oqc_capacity_report('2026-11-16') as v");assert.equal(Number(r.day.hours_per_person),8);assert.equal(Number(r.plans[0].planned_qty),1000);assert.equal(Number(r.plans[0].seconds_per_piece),30);
  await db.query('update cd_khsx_tuan_plan set ma_sp=\'MODEL-C\' where id=$1',[id]);r=await value("select oqc_capacity_report('2026-11-16') as v");assert.equal(r.plans[0].product_code,'MODEL-C');assert.equal(r.plans[0].standard_version_id,null);
  await db.exec("select set_config('test.uid','00000000-0000-0000-0000-000000000002',false)");await assert.rejects(()=>save({product:'MODEL-A'}),/quyền/);await db.exec("select set_config('test.uid','00000000-0000-0000-0000-000000000001',false)");
 });
 await test('submitted production plan requires reason and existing approval path resets; explicit version only changes edited plan',async()=>{
  await db.exec("insert into khsx_duyet(tuan_bat_dau,cong_doan,trang_thai) values('2026-11-02','OQC','da_duyet')");await assert.rejects(()=>save({product:'MODEL-A'}),/lý do/);await save({product:'MODEL-A',reason:'QA authorized correction'});assert.equal(await value("select trang_thai as v from khsx_duyet where tuan_bat_dau='2026-11-02' and cong_doan='OQC'"),'cho_truong_phong');
  await save({product:'MODEL-B',source_kind:'machining',source_id:srcB,standard_version_id:verB,reason:'QA'});assert.equal(Number(await value('select standard_version_id as v from oqc_capacity_plan where product_code=\'MODEL-B\' and work_date=$1',[day])),Number(verB));
  assert.equal(await value("select has_function_privilege('anon','qc_save_linked_plan(jsonb)','EXECUTE') as v"),false);
 });
};
