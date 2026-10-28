/* Extends existing PostgreSQL integration fixture with real RPC/trigger/RLS checks. */
module.exports = async ({ db, q, v, test, read }) => {
  const assert = require("assert/strict"),
    admin = "00000000-0000-0000-0000-000000000001",
    owner = "00000000-0000-0000-0000-000000000002",
    other = "00000000-0000-0000-0000-000000000003";
  const actor = async (uid) => {
    await db.exec("reset role");
    await db.query("select set_config('test.uid',$1,false)", [uid || ""]);
    await db.exec("set role authenticated");
  };
  const data = (extra = {}) => ({
    request_id: crypto.randomUUID(),
    inspection_date: "2026-10-29",
    shift: "Ca 1",
    product_code: "A",
    inspector_code: "QC02",
    total_qty: 10,
    ng_qty: 1,
    defects: [{ code: "x", qty: 1 }],
    scope: "FULL_POST_MACHINING",
    labor: [{ employee_code: "QC02", hours: 20 }],
    images: [],
    ...extra,
  });
  const save = (id, p) => v("select oqc_save_dashboard_inspection($1,$2) as v", [id, JSON.stringify(p)]);
  await db.exec(
    "update user_roles set role='qc_manager' where user_id='" +
      other +
      "';alter table oqc_inspection_context add column if not exists lan_son smallint;",
  );
  const latest = read("supabase/migration_phase_T153_oqc_lan_son.sql");
  const start = latest.indexOf("create or replace function public.oqc_save_dashboard_inspection("),
    end = latest.indexOf("end$$;", start);
  await db.exec(latest.slice(start, end + 7));
  await db.exec(read("supabase/migration_phase_oqc_report_input_20261021_staging.sql"));
  await test("ownership migration is additive/idempotent; old report data and creator remain unchanged", async () => {
    const before = await q("select * from oqc_daily_inspection order by id");
    await db.exec(read("supabase/migration_phase_T177_oqc_quyen_nguoi_nhap.sql"));
    await db.exec(read("supabase/migration_phase_T177_oqc_quyen_nguoi_nhap.sql"));
    const after = await q("select * from oqc_daily_inspection order by id");
    assert.deepEqual(
      after.map(({ da_xoa, ngay_xoa, nguoi_xoa, ...r }) => r),
      before,
    );
    await assert.rejects(
      () =>
        db.query(
          "insert into oqc_daily_inspection(inspection_date,shift,product_code,product_name,inspector_code,inspector_name,total_qty,ok_qty,ng_qty,created_by) values('2026-10-29','Ca 1','A','Model A','QC01','Worker 1',10,10,0,$1)",
          [owner],
        ),
      /giả mạo/,
    );
  });
  let id;
  await test("new report creator is authenticated owner, not selected inspector; other QC manager cannot edit via current RPC", async () => {
    await actor(owner);
    id = await save(null, data());
    const row = (await q("select * from oqc_daily_inspection where id=$1", [id]))[0];
    assert.equal(row.created_by, owner);
    await save(id, data({ expected_updated_at: row.updated_at.toISOString(), note: "Owner edit" }));
    const current = (await q("select * from oqc_daily_inspection where id=$1", [id]))[0];
    await actor(other);
    await assert.rejects(
      () => save(id, data({ expected_updated_at: current.updated_at.toISOString(), note: "Intruder" })),
      /người nhập/,
    );
  });
  await test("Admin edits other owner, owner cannot forge or replace created_by; all legacy writer paths hit guard", async () => {
    await actor(admin);
    let row = (await q("select * from oqc_daily_inspection where id=$1", [id]))[0];
    await save(id, data({ expected_updated_at: row.updated_at.toISOString(), note: "Admin edit" }));
    row = (await q("select * from oqc_daily_inspection where id=$1", [id]))[0];
    assert.equal(row.created_by, owner);
    await actor(other);
    await assert.rejects(
      () =>
        v("select oqc_save_daily_report($1,$2) as v", [
          id,
          JSON.stringify(data({ inspection_hours: 20, expected_updated_at: row.updated_at.toISOString() })),
        ]),
      /người nhập/,
    );
    await db.exec("reset role");
    await db.exec("select set_config('mes.oqc_dashboard_write',txid_current()::text,true)");
    await assert.rejects(
      () => db.query("update oqc_daily_inspection set created_by=$1 where id=$2", [other, id]),
      /người nhập|form cũ/,
    );
  });
  await test("other owner cannot delete; stale timestamp rejected; owner deletion preserves record, work and immutable audit", async () => {
    await actor(other);
    const r = (await q("select * from oqc_daily_inspection where id=$1", [id]))[0];
    await assert.rejects(() => v("select oqc_xoa_bao_cao($1,$2) as v", [id, r.updated_at]), /người nhập/);
    await actor(owner);
    await assert.rejects(() => v("select oqc_xoa_bao_cao($1,$2) as v", [id, "2000-01-01"]), /thay đổi/);
    assert.equal(await v("select oqc_xoa_bao_cao($1,$2) as v", [id, r.updated_at]), true);
    assert.equal((await q("select * from oqc_daily_inspection where id=$1", [id])).length, 0);
    await db.exec("reset role");
    assert.equal((await q("select * from oqc_daily_inspection where id=$1", [id]))[0].da_xoa, true);
    assert.equal((await q("select * from oqc_inspection_work where inspection_id=$1", [id])).length, 1);
    assert.equal(
      Number(
        await v("select count(*) as v from oqc_dashboard_audit where inspection_id=$1 and entity='inspection_delete'", [
          id,
        ]),
      ),
      1,
    );
    await assert.rejects(() => db.query("delete from oqc_daily_inspection where id=$1", [id]), /vĩnh viễn/);
  });
  await test("deleted hours excluded from allocation; deleted reports cannot be edited or resurrected; anonymous denied", async () => {
    await actor(owner);
    assert.ok(await save(null, data({ product_code: "B" })));
    await assert.rejects(
      () => save(id, data({ labor: [], expected_updated_at: new Date().toISOString() })),
      /đã thay đổi|đã bị xóa/,
    );
    assert.equal(
      await v("select has_function_privilege('anon','oqc_xoa_bao_cao(bigint,timestamptz)','execute') as v"),
      false,
    );
    assert.equal(await v("select has_function_privilege('anon','oqc_quyen_bao_cao()','execute') as v"), false);
    await db.exec("reset role");
    await db.query("select set_config('test.uid',$1,false)", [admin]);
  });
};
