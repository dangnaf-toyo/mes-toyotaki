const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { PGlite } = require(process.env.MES_PGLITE_PATH ||
  '../../.ncp-standards-staging/.review/tools/node_modules/@electric-sql/pglite');

(async () => {
  const source = fs.readFileSync('shared/ipqc-btk-qc.js', 'utf8');
  const context = { window: { IpqcSpc: { esc: s => String(s ?? '').replaceAll('"', '&quot;') } } };
  vm.runInNewContext(source.replace('window.IpqcBtkQc = {',
    'window.test = { DUNG_CU, noiDungDong, dungCuHopLe, chonDungCu }; window.IpqcBtkQc = {'), context);
  const helpers = context.window.test;
  assert.equal(helpers.DUNG_CU.length, 16);
  const original = {
    id: 100, id_btk: 4, muc_no: 7, hang_muc: 'Đường kính', kieu: 'so',
    danh_nghia: 10, dung_sai_tren: 0.2, dung_sai_duoi: 0.1,
    tieu_chuan: '', dung_cu: 'CMM', tan_suat: '2h/lần',
  };
  const copied = helpers.noiDungDong(original);
  original.danh_nghia = 99;
  assert.equal(copied.danh_nghia, 10);
  assert.ok(!('id' in copied) && !('id_btk' in copied) && !('muc_no' in copied));
  assert.equal(copied.dung_cu, 'CMM');
  assert.ok(helpers.chonDungCu('Dụng cụ cũ', '').includes('selected disabled>Dữ liệu cũ:'));
  assert.equal((helpers.chonDungCu('CMM', '').match(/<option /g) || []).length, 17);
  assert.match(helpers.chonDungCu('Cân trọng lượng', ' disabled'), /value="Cân trọng lượng" selected/);
  console.log('PASS copied row is independent and excludes IDs/row number; legacy tools remain visible');

  const db = new PGlite();
  try {
    await db.exec(`create role anon;create role authenticated;
      create table ipqc_btk(id bigint primary key, cong_doan text not null);
      insert into ipqc_btk values(1,'duc'),(2,'gia_cong'),(3,'iqc_hoa_hoc');
      create table ipqc_btk_muc(id serial primary key,id_btk bigint not null default 1 references ipqc_btk(id),dung_cu text,note text);
      insert into ipqc_btk_muc(dung_cu)values('Dụng cụ cũ');`);
    await db.exec(fs.readFileSync('supabase/migration_phase_T186_dung_cu_tieu_chuan.sql', 'utf8'));
    const migration = fs.readFileSync('supabase/migration_phase_T400_ipqc_can_trong_luong.sql', 'utf8');
    await db.exec(migration);
    await db.exec(migration);
    for (const tool of helpers.DUNG_CU) {
      assert.ok(helpers.dungCuHopLe(tool));
      await db.query('insert into ipqc_btk_muc(dung_cu)values($1)', [tool]);
    }
    for (const bad of ['Thước đo sâu', 'CMM / OMM', 'Tự nhập']) {
      assert.equal(helpers.dungCuHopLe(bad), false);
      await assert.rejects(db.query('insert into ipqc_btk_muc(dung_cu)values($1)', [bad]));
    }
    await db.exec("update ipqc_btk_muc set note='Giữ lịch sử' where id=1");
    assert.equal((await db.query('select dung_cu from ipqc_btk_muc where id=1')).rows[0].dung_cu, 'Dụng cụ cũ');
    await db.exec("update ipqc_btk_muc set dung_cu='CMM' where id=1");
    await assert.rejects(db.exec("update ipqc_btk_muc set dung_cu='Khác' where id=1"));
    await db.exec("insert into ipqc_btk_muc(dung_cu)values(null),('')");
    for (const standard of [1, 2]) {
      const stored = await db.query('insert into ipqc_btk_muc(id_btk,dung_cu) values($1,$2) returning id,dung_cu', [standard, ' Cân trọng lượng ']);
      const {id, dung_cu} = stored.rows[0];
      assert.equal(dung_cu, 'Cân trọng lượng');
      await db.query('update ipqc_btk_muc set dung_cu=$1 where id=$2', ['CMM', id]);
      await db.query('update ipqc_btk_muc set dung_cu=$1 where id=$2', ['Cân trọng lượng', id]);
      assert.equal((await db.query('select dung_cu from ipqc_btk_muc where id=$1', [id])).rows[0].dung_cu, 'Cân trọng lượng');
    }
    await db.query('insert into ipqc_btk_muc(id_btk,dung_cu) values(3,$1)', ['Máy phân tích nguyên vật liệu']);
    await assert.rejects(db.query('insert into ipqc_btk_muc(id_btk,dung_cu) values(3,$1)', ['Cân trọng lượng']), /chỉ dùng cho tiêu chuẩn Đúc và Gia công/);
    console.log('PASS all 16 allowed tools, weighing insert/edit/reload for casting and machining, IQC chemical isolation, legacy data');
  } finally { await db.close(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
