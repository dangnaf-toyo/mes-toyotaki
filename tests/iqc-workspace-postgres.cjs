const fs = require("fs"),
  assert = require("node:assert/strict");
const { PGlite } = require(process.env.MES_PGLITE_PATH || "../.review/tools/node_modules/@electric-sql/pglite");
(async () => {
  const db = new PGlite();
  try {
    await db.exec(
      "create role anon;create role authenticated;create table public.iqc_lots(id serial primary key,supplier text,note text,sampled_at timestamptz);insert into iqc_lots(supplier,note,sampled_at)values('Nhà cung cấp cũ','Giữ nguyên','2026-10-01T01:00:00Z');",
    );
    const before = (await db.query("select * from iqc_lots")).rows[0];
    const migration = fs.readFileSync("supabase/migration_phase_T176_iqc_pham_vi.sql", "utf8");
    await db.exec(migration);
    await db.exec(migration);
    const after = (await db.query("select * from iqc_lots")).rows[0];
    for (const k of Object.keys(before)) assert.deepEqual(after[k], before[k]);
    assert.equal(after.pham_vi, null);
    console.log("PASS additive, idempotent migration preserves legacy columns and NULL scope");
    await db.exec("update iqc_lots set note='Sửa ghi chú cũ' where id=1;");
    assert.equal((await db.query("select supplier from iqc_lots where id=1")).rows[0].supplier, "Nhà cung cấp cũ");
    console.log("PASS legacy unrelated update retains unknown supplier/scope");
    for (const scope of ["Bán thành phẩm", "Linh kiện đầu vào", "Mạ", "In", "Anode", "Đúc", "Thành phẩm"])
      await db.query("insert into iqc_lots(supplier,pham_vi,nguoi_kiem_id,nguoi_kiem_ten)values($1,$2,$3,$4)", [
        "BRV",
        scope,
        "SX01",
        "Nguyễn Sản Xuất",
      ]);
    for (const supplier of ["BRV", "HANIN", "VIỆT PHÁP", "ASAHI", "MINGANN"])
      await db.query("insert into iqc_lots(supplier,pham_vi)values($1,$2)", [supplier, "In"]);
    assert.equal((await db.query("select count(distinct pham_vi)::int n from iqc_lots")).rows[0].n, 7);
    console.log("PASS all 7 scopes / 5 suppliers and inspector identity persist");
    for (const [supplier, scope] of [
      ["FREE", "In"],
      ["BRV", "FREE"],
      ["BRV", null],
      [null, "In"],
    ])
      await assert.rejects(() => db.query("insert into iqc_lots(supplier,pham_vi)values($1,$2)", [supplier, scope]));
    await assert.rejects(() => db.exec("update iqc_lots set pham_vi='FREE' where id=2"));
    console.log("PASS database rejects invalid new/changed scope and supplier");
    const count = (await db.query("select count(*)::int n from iqc_lots")).rows[0].n;
    assert.equal(count, 13);
    assert.deepEqual(
      (await db.query("select sampled_at from iqc_lots where id=1")).rows[0].sampled_at,
      before.sampled_at,
    );
    console.log("PASS rejected writes leave existing LOT count and sampled timestamp intact");
  } finally {
    await db.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
