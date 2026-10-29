const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const {PGlite}=require(process.env.MES_PGLITE_PATH || '../../.ncp-standards-staging/.review/tools/node_modules/@electric-sql/pglite');
const schema=JSON.parse(fs.readFileSync('tests/ncp-standards-schema.fixture.json','utf8').replace(/^\uFEFF/,'')).rows[0].schema;
(async()=>{
 for(const f of ['qc-manager.html','ncp-detail.html','ipqc.html']){
  const s=fs.readFileSync(f,'utf8');for(const m of s.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g))if(m[1].trim())new vm.Script(m[1],{filename:f});
 }console.log('PASS inline JavaScript syntax');
 const db=new PGlite();try{
 await db.exec(`create role anon;create role authenticated;create schema auth;
 create function auth.uid() returns uuid language sql as $$select '00000000-0000-0000-0000-000000000001'::uuid$$;
 create function has_role(variadic roles text[]) returns boolean language sql as $$select true$$;
 create schema cron;create function cron.schedule(text,text,text) returns bigint language sql as $$select 1::bigint$$;`);
 const tables=Object.groupBy(schema.columns,c=>c.table_name);
 for(const [name,cols]of Object.entries(tables)){
  await db.exec(`create table public.${name} (`+cols.map(c=>{
   let type=c.data_type==='ARRAY'?'text[]':c.data_type;
   if(c.column_default?.startsWith('nextval'))type='bigserial';
   return `${c.column_name} ${type}`+(c.column_default&&!c.column_default.startsWith('nextval')?' default '+c.column_default:'');
  }).join(',')+')');
 }
 for(const c of schema.constraints)if(!c.def.startsWith('FOREIGN'))await db.exec(`alter table ${c.table} add constraint ${c.name} ${c.def}`);
 for(const i of schema.indexes)if(!schema.constraints.some(c=>c.name===i.indexname))await db.exec(i.indexdef);
 await db.exec(`create table duc_ipqc_checkpoint(id_checkpoint text primary key,id_ncp_lien_quan text,ma_sp text,ma_may text,ket_qua text,id_dong text);
 create table duc_ca_hien_tai(id_dong text,so_khuon text);
 create table master_products(ma_sp text,ten_sp text,ma_khach_hang text,ten_khach_hang text);
 create table master_machines(ma_may text);
 create table ipqc_gioi_han(id bigserial,ma_sp text,muc_no integer,so_mau integer,cl numeric,ucl numeric,lcl numeric,cl_r numeric,ucl_r numeric,n_lan integer,cach text,tu_luc timestamptz,den_luc timestamptz,ghi_chu text,nguoi text,dang_dung boolean default true);
 create function duc_ncp_so_quan_ly_moi() returns text language sql as $$select 'TEST-NCP'$$;
 create function duc_ncp_append_log(text,text) returns void language sql as $$select$$;`);
 for(const name of ['duc_ncp_open_case','duc_ncp_update_root_cause','ipqc_tc_luu_checklist','ipqc_do_luu']){
  const signature=schema.functions[name].match(/FUNCTION (public\.[\s\S]*?)\n RETURNS/)[1];
  await db.exec(`create function ${signature} returns jsonb language sql as $$select '{}'::jsonb$$;`);
 }
 // Existing shared notification implementation; fixtures use isolated local recipients only.
 for(const name of ['cv_pd_ds_ten','cv_pd_gui','cv_pd_xong'])await db.exec(schema.functions[name]);
 await db.exec(`create function cv_pd_ds_role(text[]) returns uuid[] language sql as $$select array['00000000-0000-0000-0000-000000000001'::uuid]$$;`);
 for(const f of ['T184_ncp_han_doi_sach','T185_tieu_chuan_phien_ban']){
  await db.exec(fs.readFileSync('supabase/migration_phase_'+f+'.sql','utf8'));console.log('PASS migration '+f);
 }
 await db.exec(`insert into duc_ncp(id_ncp,rc_trang_thai_duyet,doi_sach_ps_tam_thoi_json) values('legacy','nhap','[]');`);
 assert.equal((await db.query("select han_tra_loi_doi_sach from duc_ncp where id_ncp='legacy'")).rows[0].han_tra_loi_doi_sach,null);
 for(const [id,days,expected]of [['upcoming',3,'sap_den_han'],['today',0,'hom_nay'],['overdue',-1,'qua_han']]){
  await db.query(`insert into duc_ncp(id_ncp,rc_trang_thai_duyet,han_tra_loi_doi_sach)values($1,'nhap',(now() at time zone 'Asia/Ho_Chi_Minh')::date+$2::integer)`,[id,days]);
  assert.equal((await db.query('select trang_thai_han from duc_ncp_theo_doi where id_ncp=$1',[id])).rows[0].trang_thai_han,expected);
 }
 await db.exec(`update duc_ncp set rc_trang_thai_duyet='cho_duyet',doi_sach_ps_tam_thoi_json='[{"noi_dung":"Đã trả lời"}]' where id_ncp='overdue';`);
 assert.equal((await db.query("select trang_thai_han from duc_ncp_theo_doi where id_ncp='overdue'")).rows[0].trang_thai_han,'hoan_thanh');
 console.log('PASS legacy NULL deadline, due boundaries, completed response');
 await db.exec(`insert into ipqc_btk(ma_sp,phien_ban,cong_doan,trang_thai,dang_dung,ngay_hieu_luc) values('SAME','A','duc','da_duyet',true,current_date),('SAME','A','gia_cong','da_duyet',true,current_date);`);
 const a=(await db.query("select ipqc_tc_hieu_luc('SAME','duc') v")).rows[0].v;
 const b=(await db.query("select ipqc_tc_hieu_luc('SAME','gia_cong') v")).rows[0].v;
 assert.equal(a.btk.cong_doan,'duc');assert.equal(b.btk.cong_doan,'gia_cong');assert.notEqual(a.btk.id,b.btk.id);
 console.log('PASS same product/version isolated by process');
 await db.exec("insert into ipqc_btk(ma_sp,phien_ban,cong_doan,trang_thai,dang_dung,ngay_hieu_luc) values('SAME','FUTURE','duc','da_duyet',false,current_date+7)");
 assert.equal((await db.query("select ipqc_tc_hieu_luc('SAME','duc')->'btk'->>'phien_ban' v")).rows[0].v,'A');
 console.log('PASS future effective version does not replace current standard');
 await db.exec("insert into user_roles(user_id,username)values('00000000-0000-0000-0000-000000000001','TEST')");
 await db.exec("create or replace function auth.uid() returns uuid language sql as $$select null::uuid$$");
 const n1=(await db.query('select ncp_quet_nhac_han() n')).rows[0].n;
 const n2=(await db.query('select ncp_quet_nhac_han() n')).rows[0].n;
 assert.equal(n1,2);assert.equal(n2,0);assert.equal((await db.query("select count(*)::int n from ncp_nhac_han_log where id_ncp='overdue'")).rows[0].n,0);
 console.log('PASS reminder rescan deduplication and completed response exclusion');
 }finally{await db.close();}
})().catch(e=>{console.error(e.message, e.query?.slice(0,1500),e.position);process.exitCode=1;});
