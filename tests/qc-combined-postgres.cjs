/* Run from qc-session-postgres with MES_TEST_COMBINED_QC=1.
   Both real migrations share the same local PostgreSQL fixture; no live writes. */
module.exports=async function({db,query,test,read}){
 const value=async(sql,args=[])=>(await query(sql,args))[0].v;
 const assert=require('assert/strict');
 await test('combined T118 + T120 apply/reapply in one database without changing old RPCs, completed NG, duration or NCPs',async()=>{
   await db.exec('create table if not exists master_employees(ten_nhan_vien text);');
   await db.exec(read('supabase/migration_phase_T67_oqc_daily_inspection.sql'));
   await db.exec('alter table oqc_daily_inspection add column inspection_time time,add column customer_code text,add column customer_name text,add column lot_no text,add column task_no text;');
   const source=read('supabase/migration_phase_T73_qc_checks_history_staging.sql'),start=source.indexOf('create or replace function public.oqc_save_daily_inspection_qc_v2('),end=source.indexOf('$qc$;',start);
   assert.ok(start>=0&&end>start);await db.exec(source.slice(start,end+6));
   const signatures=['duc_submit_ipqc_check(text,jsonb,text,jsonb,text,numeric,text)','duc_ipqc_decide_continue_request(bigint,text,text,text)','duc_ncp_open_case(text,text,text,text,text,text,numeric,numeric,text,text,text,text)','oqc_save_daily_inspection(bigint,jsonb,text)','oqc_save_daily_inspection_qc_v2(bigint,jsonb,text)'];
   const definitions=new Map();for(const sig of signatures)definitions.set(sig,await value('select pg_get_functiondef($1::regprocedure) as v',[sig]));
   const snapshot=async()=>({checkpoint:await query("select * from duc_ipqc_checkpoint where id_checkpoint in ('CP1','LEGACY') order by id_checkpoint"),requests:await query('select * from duc_ipqc_continue_request order by id'),ncp:await query('select * from duc_ncp order by id_ncp')});
   const before=await snapshot();
   await db.exec(read('supabase/migration_phase_T120_oqc_capacity_staging.sql'));
   await db.exec(read('supabase/migration_phase_T118_qc_sessions_sources_ng.sql'));
   await db.exec(read('supabase/migration_phase_T120_oqc_capacity_staging.sql'));
   for(const sig of signatures)assert.equal(await value('select pg_get_functiondef($1::regprocedure) as v',[sig]),definitions.get(sig),sig);
   assert.deepEqual(await snapshot(),before);
   assert.equal(Number(await value('select count(*) as v from oqc_inspection_context')),0);
 });
 await test('combined runtime: OQC 672 PCS/7h gives 100% completion and 80% efficiency while IPQC sessions/NG approvals remain intact',async()=>{
   const version=await value("select oqc_save_work_standard('MODEL-A','2026-10-01',$1::jsonb) as v",[JSON.stringify([{name:'Ngoại quan',seconds:10},{name:'JIG',seconds:8},{name:'Kích thước',seconds:12}])]);
   await db.exec("select oqc_save_capacity_plan('2026-10-20','MODEL-A','672','7',0)");
   const inspection={inspection_date:'2026-10-20',shift:'Ca 1',product_code:'MODEL-A',product_name:'Model A',inspector_code:'admin',inspector_name:'Admin',total_qty:672,defects:[{code:'xuoc',qty:2}],note:'Combined release check'};
   const id=await value("select oqc_save_scoped_inspection(null,$1,'Admin','FULL_POST_MACHINING') as v",[JSON.stringify(inspection)]);
   await db.query("select oqc_save_capacity_labor('2026-10-20',$1::jsonb)",[JSON.stringify([{people:1,hours:7}])]);
   const report=await value("select oqc_capacity_report('2026-10-20') as v"),summary=require('../shared/oqc-capacity-math.js').report(report);
   assert.equal(summary.completion,100);assert.equal(summary.efficiency,80);
   assert.equal(Number(await value('select standard_version_id as v from oqc_inspection_context where inspection_id=$1',[id])),Number(version));
   await db.exec("select duc_ipqc_session('CP2',true); select duc_ipqc_session_submit_time('CP2',false)");
   await db.query("select duc_submit_ipqc_session('CP2',$1,'OK',$2,'combined',99999,'Admin')",[JSON.stringify([{muc:'Ngoại quan',dat:true}]),JSON.stringify(['https://example.invalid/combined.jpg'])]);
   assert.equal(await value("select ket_qua as v from duc_ipqc_checkpoint where id_checkpoint='CP2'"),'OK');
   assert.equal(await value("select ket_qua as v from duc_ipqc_checkpoint where id_checkpoint='CP1'"),'NG');
   assert.ok(Number(await value("select thoi_gian_kiem_giay as v from duc_ipqc_checkpoint where id_checkpoint='CP1'"))>=120);
   assert.equal(await value("select trang_thai as v from duc_ncp where id_checkpoint_goc='CP1'"),'da_cach_ly');
   assert.deepEqual(await value("select oqc_capacity_report('2026-10-20') as v"),report);
 });
};
