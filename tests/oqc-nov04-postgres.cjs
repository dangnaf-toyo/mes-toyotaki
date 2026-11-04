const fs=require('fs'),assert=require('node:assert/strict');
const {PGlite}=require(process.env.MES_PGLITE_PATH||'../../.ncp-standards-staging/.review/tools/node_modules/@electric-sql/pglite');
(async()=>{const db=new PGlite();try{
 await db.exec(`create role anon;create role authenticated;create schema auth;
 create function auth.uid()returns uuid language sql as $$select '00000000-0000-0000-0000-000000000001'::uuid$$;
 create function has_role(variadic text[])returns boolean language sql as $$select coalesce(current_setting('test.allowed',true),'yes')='yes'$$;
 create function oqc_capacity_number(text,boolean default false)returns numeric language sql as $$select $1::numeric$$;
 create function oqc_capacity_actor()returns text language sql as $$select 'Test'::text$$;
 create table oqc_daily_inspection(id bigserial primary key,ng_qty numeric,updated_at timestamptz default now());
 create table oqc_daily_inspection_audit(inspection_id bigint,actor_id uuid,actor_name text,old_data jsonb,new_data jsonb);
 create table oqc_inspection_context(inspection_id bigint,inspection_scope text);
 create function oqc_save_dashboard_inspection(p_id bigint,p_data jsonb)returns bigint language plpgsql as $$declare v bigint;begin
 if p_id is null then insert into oqc_daily_inspection(ng_qty)values(0)returning id into v;else v:=p_id;end if;return v;end$$;`);
 for(const f of ['T210_oqc_so_nguoi_kiem','T211_oqc_gia_cong_ngoai','T216_oqc_cong_doan_guard'])await db.exec(fs.readFileSync('supabase/migration_phase_'+f+'.sql','utf8'));
 const base={total_qty:1200,defects:[],labor:[{employee_code:'QC1',hours:2}],inspector_code:'QC1',inspection_hours:2,so_nguoi_kiem:3,scope:'FULL_POST_MACHINING'};
 const save=async(p,id=null)=>(await db.query('select oqc_save_daily_report($1,$2)id',[id,JSON.stringify(p)])).rows[0].id;
 const id=await save(base);let r=(await db.query('select * from oqc_daily_inspection where id=$1',[id])).rows[0];
 assert.equal(r.so_nguoi_kiem,3);assert.equal(Number(r.gio_kiem_thuc_te),2);
 for(const count of [0,-1,1.5])await assert.rejects(save({...base,so_nguoi_kiem:count}));
 await assert.rejects(save({...base,scope:'POST_OUTSOURCED_MACHINING'}));
 for(const process of ['ma','in','anode']){
  const k=await save({...base,scope:'POST_OUTSOURCED_MACHINING',cong_doan_gia_cong_ngoai:process});
  assert.equal((await db.query('select cong_doan_gia_cong_ngoai c from oqc_daily_inspection where id=$1',[k])).rows[0].c,process);
 }
 await assert.rejects(save({...base,scope:'POST_OUTSOURCED_MACHINING',cong_doan_gia_cong_ngoai:'unknown'}));
 await db.query("insert into oqc_inspection_context values($1,'POST_OUTSOURCED_MACHINING')",[id]);
 await save({...base,scope:'POST_OUTSOURCED_MACHINING'},id);
 await db.exec("select set_config('test.allowed','no',false)");
 await assert.rejects(save(base));
 console.log('PASS saved/reloaded headcount and hours; invalid counts rejected; Ma/In/Anode mandatory for new outsourcing; unknown legacy retained; role gate preserved');
}finally{await db.close();}})().catch(e=>{console.error(e.message);process.exitCode=1;});
