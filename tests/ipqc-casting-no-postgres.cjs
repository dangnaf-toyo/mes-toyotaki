// Local PostgreSQL only. Uses the existing save and approval functions.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const { PGlite } = require(process.env.MES_PGLITE_PATH || "@electric-sql/pglite");

function migration(phase, name) {
  return fs.readFileSync(`supabase/migration_phase_${phase}_${name}.sql`, "utf8");
}

async function run(db) {
  const one = async (sql, args = []) => (await db.query(sql, args)).rows[0];
  const base = migration("T133", "ipqc_bang_tuan_kiem");
  const workflow = migration("T163", "tieu_chuan_phe_duyet");
  const save = migration("T221", "gc_sai_lech_co_dau");
  await db.exec(`
    create role anon;
    create role authenticated;
    create schema auth;
    create function auth.uid() returns uuid language sql as
      $$select '00000000-0000-0000-0000-000000000001'::uuid$$;
    create function public.has_role(variadic text[]) returns boolean language sql as $$select true$$;
    create function public.ipqc_cd_ten(text) returns text language sql as $$select $1$$;
    create table user_roles(user_id uuid, full_name text, username text);
    insert into user_roles values(auth.uid(), 'QC', 'qc');
    create table master_products(ma_sp text primary key);
    insert into master_products values ('CAST'), ('MACHINED');
    create table duc_ipqc_checkpoint(id_checkpoint text primary key);
    insert into duc_ipqc_checkpoint values ('LEGACY'), ('CUSTOM');
    ${base.slice(base.indexOf("create table if not exists ipqc_btk ("), base.indexOf("create table if not exists ipqc_gioi_han ("))}
    ${workflow.slice(workflow.indexOf("alter table public.ipqc_btk add column"), workflow.indexOf("alter table public.duc_ipqc_tieuchuan_de_xuat enable"))}
    alter table ipqc_btk add column cong_doan text not null default 'duc', add column buoc_gia_cong text;
    alter table ipqc_btk_muc
      add column ma_dac_tinh text, add column don_vi text, add column phuong_phap text,
      add column lsl numeric, add column usl numeric, add column co_mau integer, add column nguon_nhan_dien jsonb;
    ${save.slice(save.indexOf("alter table public.ipqc_btk_muc"), save.indexOf("to authenticated;") + "to authenticated;".length)}
  `);
  await db.exec(migration("T220", "admin_duyet_tieu_chuan"));
  await db.exec(`
    insert into ipqc_btk(id, ma_sp, phien_ban, ngay_hieu_luc) values (500, 'CAST', 'A', '2025-01-01');
    insert into ipqc_btk_muc(id_btk, muc_no, hang_muc, kieu, tieu_chuan) values (500, 69, 'Legacy', 'okng', 'OK');
    insert into ipqc_do_lan(id_checkpoint,id_btk,ma_sp,dat) values ('LEGACY',500,'CAST',true);
    insert into ipqc_do_kq(id_checkpoint,muc_no,gia_tri,dat) values ('LEGACY',69,10.3,true);
  `);
  await db.exec(migration("T293", "ipqc_duc_no_hang_muc"));
  const call = async (payload, draft) =>
    (await one("select ipqc_duc_luu_bang_tuan_kiem('CAST', $1, $2) as result", [payload, draft])).result;
  const row = (muc_no, no_hien_thi) => ({ muc_no, no_hien_thi, hang_muc: "Diameter", kieu: "okng", tieu_chuan: "OK" });
  const payload = {
    id_nguon: 500, phien_ban: "B", ngay_hieu_luc: "2025-01-01",
    muc: [row(69, "1"), row(-1, "1-1"), row(-2, "1-2"), row(-3, "2-1"), row(-4, "2-2"), row(-5, "70")],
    ban_ve_vi_tri: [{ no: -1, x: 12, y: 34 }],
  };
  await assert.rejects(call({ ...payload, muc: [...payload.muc, row(-6, "1-1")] }, true), /Trùng NO 1-1/);
  const saved = await call(payload, true);
  assert.equal(saved.ok, true);
  const id = saved.id;
  assert.equal((await one("select trang_thai from ipqc_btk where id=$1", [id])).trang_thai, "ban_nhap");
  const items = (await db.query(
    "select muc_no, no_hien_thi from ipqc_btk_muc where id_btk=$1 order by thu_tu_hien_thi", [id],
  )).rows;
  assert.deepEqual(items.map(m => m.no_hien_thi), ["1", "1-1", "1-2", "2-1", "2-2", "70"]);
  assert.equal(items[0].muc_no, 69);
  assert.equal(new Set(items.map(m => m.muc_no)).size, items.length);
  assert.equal((await one("select ban_ve_vi_tri from ipqc_btk where id=$1", [id])).ban_ve_vi_tri[0].no, items[1].muc_no);
  const approve = async action =>
    (await one("select ipqc_tc_duyet('btk', $1, $2, null, null) as result", [id, action])).result;
  assert.equal((await approve("kiem_tra")).ok, false);
  const revised = items.slice(0, -1).reverse().map(m => row(m.muc_no, m.no_hien_thi));
  assert.equal((await call({ ...payload, id_nguon: id, muc: revised,
    ban_ve_vi_tri: [{ no: items[1].muc_no, x: 12, y: 34 }],
  }, false)).id, id);
  assert.equal((await approve("kiem_tra")).trang_thai, "cho_phe_duyet");
  assert.equal((await approve("phe_duyet")).trang_thai, "da_duyet");
  await db.query("insert into ipqc_do_lan(id_checkpoint,id_btk,ma_sp,dat) values ('CUSTOM',$1,'CAST',true)", [id]);
  await db.query("insert into ipqc_do_kq(id_checkpoint,muc_no,gia_tri,dat) values ('CUSTOM',$1,10.5,true)", [items[1].muc_no]);
  const results = (await db.query(`
    select k.id_checkpoint, m.id, coalesce(m.no_hien_thi, m.muc_no::text) as no, k.gia_tri
    from ipqc_do_kq k join ipqc_do_lan l using(id_checkpoint)
    join ipqc_btk_muc m on m.id_btk=l.id_btk and m.muc_no=k.muc_no order by k.id_checkpoint
  `)).rows;
  assert.deepEqual(results.map(r => [r.no, r.gia_tri]), [["1-1", "10.5"], ["69", "10.3"]]);
  assert.notEqual(results[0].id, results[1].id);
  const imported = await call({ phien_ban: "C", muc: [row("1-1"), row("2-3")] }, false);
  assert.equal(imported.ok, true);
  const importedItem = await one("select muc_no from ipqc_btk_muc where id_btk=$1 and no_hien_thi='1-1'", [imported.id]);
  assert.equal(importedItem.muc_no, items[1].muc_no);
  const gc = await one("select ipqc_btk_luu('MACHINED', $1, null, 'gia_cong') as result",
    [{ phien_ban: "A", muc: [row(2)] }]);
  assert.equal(gc.result.ok, true);
  assert.deepEqual(await one("select muc_no, no_hien_thi from ipqc_btk_muc where id_btk=$1", [gc.result.id]),
    { muc_no: 2, no_hien_thi: null });
  console.log("PASS PostgreSQL: editable NO, duplicate rejection, draft/reopen, approval, result mapping, legacy and machining.");
}

const db = new PGlite();
run(db).catch(error => {
  console.error(error);
  process.exitCode = 1;
}).finally(() => db.close());
