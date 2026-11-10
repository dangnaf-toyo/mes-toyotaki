const assert = require("node:assert/strict");
const { page, wait, selected } = require("./qc-session-ui.cjs");
const { IDBFactory } = require(process.env.MES_FAKE_IDB_PATH || "fake-indexeddb");
const fixture = {
  btk: { id: 7, ma_sp: "TTI-MOT-04", phien_ban: "A", so_mau: 3 },
  muc: Array.from({ length: 30 }, (_, i) => ({
    muc_no: i + 1,
    kieu: "so",
    hang_muc: "Đường kính " + (i + 1),
    danh_nghia: 115.7,
    dung_sai_tren: 0.4,
    dung_sai_duoi: 0.4,
  })),
  lan: [],
  gioi_han: [],
};
function profile(p) {
  const rpc = p.db.rpc.bind(p.db);
  p.db.rpc = async (name, args) => {
    if (name === "ipqc_do_du_lieu") return { data: JSON.parse(JSON.stringify(fixture)), error: null };
    if (name === "duc_submit_ipqc_cvt") {
      p.db.calls.push({ name, args });
      return rpc("duc_submit_ipqc_session", args);
    }
    return rpc(name, args);
  };
  p.w.confirm = () => true;
}
function change(p, selector, value) {
  const input = p.w.document.querySelector(selector);
  assert.ok(input, selector);
  if (input.type === "checkbox") {
    input.checked = value;
    input.dispatchEvent(new p.w.Event("change", { bubbles: true }));
  } else {
    input.value = value;
    input.dispatchEvent(new p.w.Event("input", { bubbles: true }));
  }
}
function value(p, no, i, code, v) {
  change(p, `[data-code="${no}:${i}"]`, code);
  change(p, `[data-v="${no}:${i}"]`, v);
}
(async () => {
  const idb = new IDBFactory(),
    p = page("ipqc.html", { indexedDB: idb });
  profile(p);
  await selected(p);
  await wait();
  assert.equal(p.w.document.querySelector("[data-select]").disabled, true);
  assert.equal(p.run("state.btk.trangThai().dat"), null);
  await p.run("MesIpqcSession.start()");
  for (const no of [2, 5, 12, 20]) change(p, `[data-select="${no}"]`, true);
  value(p, 2, 0, "2-1", "115,85");
  for (const [i, code, v] of [
    [1, "2-2", "115.91"],
    [2, "69", "116.15"],
    [3, "70", "115.76"],
  ]) {
    p.w.document.querySelector('[data-add="2"]').click();
    value(p, 2, i, code, v);
  }
  for (const no of [5, 12, 20]) value(p, no, 0, "70", "115.7");
  let d = p.run("state.btk.trangThai()");
  assert.equal(d.du, true);
  assert.equal(d.measured, 4);
  assert.equal(d.unchecked, 26);
  assert.equal(d.cvt, 7);
  assert.equal(d.ng, 1);
  assert.equal(d.dat, false);
  assert.equal(p.run("state.checklistAnswers[0].dat"), false);
  assert.equal(p.w.document.querySelector('[data-it="1"] [data-status]').textContent, "Chưa kiểm");
  assert.deepEqual(
    Array.from(p.w.document.querySelectorAll('[data-it="2"] [data-row-result]'), (x) => x.textContent),
    ["OK", "OK", "NG", "OK"],
  );
  value(p, 2, 3, "69", "115.76");
  assert.match(p.run("state.btk.trangThai().errors.join()"), /trùng mã CVT/);
  await p.w.finishCastingCheck();
  assert.equal(p.db.calls.filter((c) => c.name === "duc_submit_ipqc_cvt").length, 0);
  value(p, 2, 3, "70", "Infinity");
  assert.equal(p.run("state.btk.trangThai().du"), false);
  value(p, 2, 3, "70", "0x10");
  assert.equal(p.run("state.btk.trangThai().du"), false);
  value(p, 2, 3, "70", "115.76");
  p.w.document.querySelector('[data-add="2"]').click();
  assert.equal(p.run("state.btk.trangThai().du"), false);
  assert.equal(p.w.document.querySelector('[data-it="2"] [data-status]').textContent, "Thiếu kết quả");
  p.w.document.querySelector('[data-delete="2:4"]').click();
  assert.equal(p.run("state.btk.trangThai().du"), true);
  change(p, '[data-select="30"]', true);
  assert.equal(p.run("state.btk.trangThai().du"), false);
  change(p, '[data-select="30"]', false);
  assert.equal(p.run("state.btk.trangThai().du"), true);
  await new Promise((r) => setTimeout(r, 180));
  const p2 = page("ipqc.html", { indexedDB: idb, tables: p.db.tables });
  profile(p2);
  await selected(p2);
  await wait();
  assert.equal(p2.run("state.btk.trangThai().cvt"), 7);
  assert.equal(p2.run("state.btk.trangThai().unchecked"), 26);
  assert.equal(p2.w.document.querySelector('[data-code="2:2"]').value, "69");
  p2.dom.window.close();
  p.run(
    'state.checklistAnswers.forEach(a=>a.dat=true); apDungBtk(state.btk.trangThai()); state.photos=[{blob:new Blob(["photo"],{type:"image/jpeg"}),mime:"image/jpeg",dataUrl:"data:image/jpeg;base64,AA=="}]',
  );
  p.w.document.getElementById("ck-ghi-chu").value = "CVT 69 vượt giới hạn";
  await p.w.finishCastingCheck();
  const call = p.db.calls.find((c) => c.name === "duc_submit_ipqc_cvt");
  assert.ok(call);
  assert.equal(call.args.p_ket_qua, "NG");
  assert.equal(call.args.p_do.kq.length, 7);
  assert.equal(call.args.p_do.muc_da_chon.join(","), "2,5,12,20");
  assert.equal(call.args.p_do.kq.map((k) => k.ma_cvt).join(","), "2-1,2-2,69,70,70,70,70");
  assert.equal(p.db.tables.duc_ipqc_checkpoint[0].ket_qua, "NG");
  p.dom.window.close();
  console.log(
    "PASS casting: 4/30 items, multiple/free CVT codes, per-row OK/NG, add/delete, missing/duplicates/invalid inputs, scoped draft resume, atomic submit and NG flow (APIs mocked).",
  );

  const q = page("ipqc.html");
  profile(q);
  await selected(q);
  await q.run("MesIpqcSession.start()");
  change(q, '[data-select="1"]', true);
  value(q, 1, 0, "A<&", "115.7");
  assert.equal(q.run("state.btk.trangThai().du"), true);
  q.run(
    'state.checklistAnswers.forEach(a=>a.dat=true);state.photos=[{blob:new Blob(["p"],{type:"image/jpeg"}),mime:"image/jpeg"}]',
  );
  await q.w.finishCastingCheck();
  assert.equal(q.db.tables.duc_ipqc_checkpoint[0].ket_qua, "OK");
  q.dom.window.close();
  console.log("PASS casting: one CVT can finish OK with 29 uninspected items.");
})();
