const assert = require('node:assert/strict');
const fs = require('node:fs');
const { PGlite } = require(process.env.MES_PGLITE_PATH || '@electric-sql/pglite');

const stages = [
  ['multiday', 'multiday'],
  ['progressive', 'progressive'],
  ['aql_selection', 'aql-selection'],
  ['compact_times', 'compact-times'],
  ['oqc_defect_catalog', 'oqc-defect-catalog'],
];

async function run() {
  const db = new PGlite();
  const sql = (path) => db.exec(fs.readFileSync(path, 'utf8'));
  try {
    // Minimal fixtures for Supabase and the existing product, material and IPQC masters.
    await db.exec(`
      create role anon;
      create role authenticated;
      create schema auth;
      create schema storage;
      create function auth.uid() returns uuid language sql stable as
        $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
      create table user_roles(user_id uuid primary key, username text, role text, full_name text);
      insert into user_roles(user_id,username,role) values
        ('00000000-0000-0000-0000-000000000001','ADMIN','admin'),
        ('00000000-0000-0000-0000-000000000002','IQC','iqc'),
        ('00000000-0000-0000-0000-000000000003','IPQC','ipqc'),
        ('00000000-0000-0000-0000-000000000004','OQC','nhan_vien_oqc');
      create function has_role(variadic roles text[]) returns boolean language sql stable security definer as
        $$ select exists(select 1 from user_roles where user_id=auth.uid() and role=any(roles)) $$;
      create function duc_ten_nguoi_hien_tai() returns text language sql stable as
        $$ select username from user_roles where user_id=auth.uid() $$;
      grant usage on schema auth to authenticated;
      create table storage.buckets(id text primary key, name text, public boolean, file_size_limit int, allowed_mime_types text[]);
      create table storage.objects(bucket_id text, name text, owner_id text, metadata jsonb);
      create function storage.foldername(name text) returns text[] language sql immutable as
        $$ select string_to_array(name, '/') $$;
      create table master_products(ma_sp text primary key, ten_sp text);
      insert into master_products values ('IQC-TEST','Fixture');
      create table vat_lieu_mac(ma_mac text primary key, loai_kim_loai text);
      insert into vat_lieu_mac values ('ADC12','nhom');
      create table nvl_materials(ma_nvl text primary key, ten_nvl text, nhom_vat_tu text,
        ma_mac text, nha_cung_cap text, ma_nvl_ncc text);
      insert into nvl_materials values ('AL-TEST','Nhôm','kim_loai','ADC12','TEST NCC',null),
        ('NVL-TEST','Linh kiện','linh_kien',null,'BRV',null);
      create table ipqc_btk(id bigserial primary key, ma_sp text, cong_doan text,
        phien_ban text, ngay_hieu_luc date, phe_duyet_luc timestamptz, noi_dung_sua_doi text,
        nguoi_lap text, nguoi_lap_uid uuid, trang_thai text, dang_dung boolean, gui_luc timestamptz,
        constraint ipqc_btk_cong_doan_check check(cong_doan in ('duc','gia_cong')),
        constraint ipqc_btk_trang_thai_check check(trang_thai is not null));
      create table ipqc_btk_muc(id bigserial primary key, id_btk bigint references ipqc_btk(id),
        muc_no int, hang_muc text, ma_dac_tinh text, kieu text, lsl numeric, usl numeric, don_vi text,
        nguon_nhan_dien jsonb, xac_nhan_boi uuid, xac_nhan_luc timestamptz);
    `);
    await sql('supabase/migration_phase_S9_iqc_tables.sql');
    await db.exec(`insert into iqc_lots(lot_no, supplier, note, lot_qty) values ('LEGACY','NCC cũ','Giữ nguyên',1500)`);
    await sql('supabase/migration_phase_T176_iqc_pham_vi.sql');
    await sql('supabase/migration_phase_T232_iqc_nvl_hoa_hoc.sql');
    await sql('supabase/migration_iqc_catalog_source.sql');
    await db.exec(`
      insert into ipqc_btk(ma_sp,ma_nvl,cong_doan,phien_ban,ngay_hieu_luc,trang_thai,nhom_vat_lieu,mac_vat_lieu)
      values ('AL-TEST','AL-TEST','iqc_hoa_hoc','v1',current_date,'da_duyet','nhom','ADC12');
      insert into ipqc_btk_muc(id_btk,muc_no,hang_muc,ma_dac_tinh,lsl,usl,don_vi,nguon_nhan_dien)
      values (1,1,'Si','Si',9,12,'%', '{"bat_buoc":true}');
      grant select,insert,update on iqc_lots to authenticated;
    `);
    const legacy = async () => (await db.query(`select to_jsonb(l) as row from iqc_lots l where lot_no='LEGACY'`)).rows[0].row;
    const before = await legacy();

    for (const [migration, test] of stages) {
      await sql(`supabase/migration_iqc_${migration}_staging.sql`);
      if (migration !== 'oqc_defect_catalog') await db.exec('begin');
      try {
        await sql(`tests/iqc-${test}-staging-rollback.sql`);
      } finally {
        if (migration !== 'oqc_defect_catalog') await db.exec('rollback');
      }
      console.log(`PASS ${migration} migration and transaction fixture`);
    }

    const after = await legacy();
    for (const key of Object.keys(before)) assert.deepEqual(after[key], before[key], key);

    const permissions = await db.query(`
      select has_function_privilege('anon','iqc_luu_lan_kiem(bigint,jsonb,jsonb,uuid)','EXECUTE') as anon_write,
        has_function_privilege('anon','iqc_chon_aql(bigint,text,text,text,text,timestamptz)','EXECUTE') as anon_aql,
        has_function_privilege('authenticated','iqc_tinh_tong_lot(bigint)','EXECUTE') as internal_rpc,
        has_table_privilege('authenticated','iqc_lan_kiem','INSERT') as direct_write,
        has_function_privilege('authenticated','iqc_luu_lan_kiem(bigint,jsonb,jsonb,uuid)','EXECUTE') as authenticated_rpc
    `);
    assert.deepEqual(permissions.rows[0], {
      anon_write: false, anon_aql: false, internal_rpc: false, direct_write: false, authenticated_rpc: true,
    });
    await db.exec('begin');
    try {
      await db.exec(`insert into iqc_phan_tich_hoa_hoc_lich_su(lot_id,noi_dung) values (1,'{}');`);
      await db.exec(`set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true)`);
      assert.equal((await db.query('select * from iqc_phan_tich_hoa_hoc_lich_su')).rows.length, 0);
      await assert.rejects(db.query('select iqc_bat_dau_lan_kiem(gen_random_uuid(),1)'));
    } finally {
      await db.exec('rollback');
    }
    await db.exec(`begin; set local role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true)`);
    try {
      await db.query('select iqc_bat_dau_lan_kiem(gen_random_uuid(),1)');
    } finally {
      await db.exec('rollback');
    }
    console.log('PASS historical columns preserved and final role grants/RLS');
  } finally {
    await db.close();
  }
}

run().catch((error) => {
  console.error(error.message, error.detail || '', error.where || '');
  process.exitCode = 1;
});
