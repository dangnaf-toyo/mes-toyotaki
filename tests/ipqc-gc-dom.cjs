/* Real DOM/event tests using isolated fixture records; no network or persistent writes. */
const fs = require("fs"),
  vm = require("node:vm"),
  assert = require("node:assert/strict");
const { parseHTML } = require(process.env.MES_LINKEDOM_PATH || "../.review/tools/node_modules/linkedom");
const { window } = parseHTML(fs.readFileSync("ipqc-gia-cong.html", "utf8")),
  document = window.document;
Object.defineProperty(window.HTMLSelectElement.prototype, "value", {
  configurable: true,
  get() {
    const options = [...this.querySelectorAll("option")];
    return (
      (options.find((o) => o.hasAttribute("selected")) || options[0])?.getAttribute("value") ??
      (options.find((o) => o.hasAttribute("selected")) || options[0])?.textContent ??
      ""
    );
  },
  set(value) {
    this.querySelectorAll("option").forEach((o) => {
      if ((o.getAttribute("value") ?? o.textContent) === String(value)) o.setAttribute("selected", "");
      else o.removeAttribute("selected");
    });
  },
});
document.querySelectorAll("form").forEach(
  (f) =>
    (f.reset = () => {
      f.querySelectorAll("input,textarea").forEach((i) => (i.value = i.getAttribute("value") || ""));
    }),
);
const standard = {
  id: 1,
  ma_sp: "PART",
  phien_ban: "A",
  cong_doan: "gia_cong",
  trang_thai: "da_duyet",
  ngay_hieu_luc: "2026-01-01",
  so_mau: 1,
  ma_ban_ve: "DWG",
  buoc_gia_cong: "Phay",
};
const feature = {
  id: 1,
  id_btk: 1,
  muc_no: 1,
  ma_dac_tinh: "D01",
  hang_muc: "Diameter",
  kieu: "so",
  danh_nghia: 20,
  dung_sai_tren: 0.05,
  dung_sai_duoi: 0.05,
  lsl: 19.95,
  usl: 20.05,
  co_mau: 2,
  dung_cu: "CMM",
};
const records = {
  master_machines: [{ma_may:'Phay 01',bo_phan:'Gia công - Sơn'}],
  ipqc_btk: [standard],
  ipqc_btk_muc: [feature],
  user_roles: [{ user_id: "u1", role: "admin" }],
  ipqc_gc_tieu_chuan_lich_su: [],
  ipqc_gc_lan: [{ id: "saved", dat: false, thoi_diem: new Date().toISOString() }],
  ipqc_lan_tong_hop: [],
};
let measured, standardPayload, exportRows;
const errors = [];
function query(name) {
  let data = [...(records[name] || [])],
    single = false;
  const q = {
    select() {
      return q;
    },
    eq(k, v) {
      data = data.filter((r) => String(r[k]) === String(v));
      return q;
    },
    gte() {
      return q;
    },
    lte() {
      return q;
    },
    ilike() {
      return q;
    },
    order() {
      return q;
    },
    range() {
      return q;
    },
    single() {
      single = true;
      return q;
    },
    maybeSingle() {
      single = true;
      return q;
    },
    then(resolve, reject) {
      return Promise.resolve({ data: single ? data[0] || null : data, error: null }).then(resolve, reject);
    },
  };
  return q;
}
const context = {
  window,
  document,
  Node: window.Node,
  URL,
  URLSearchParams,
  Date,
  Math,
  Map,
  Set,
  Intl,
  crypto: require("node:crypto").webcrypto,
  console: { ...console, error: (e) => errors.push(String(e)) },
  location: { search: "", hostname: "localhost" },
  IS_PROD: false,
  setInterval() {},
  localStorage:{getItem:()=>null,setItem(){}},
  MesAuth: { getSession: async () => ({ user: { id: "u1" } }) },
  MesNav: { setTitle() {} },
  sbTaiHet: async (make) => await make(),
  Qc02Data: {
    readAll: async (name) =>
      name === "master_products"
        ? [{ ma_sp: "PART", ten_sp: "Part", ten_khach_hang: "Customer" }]
        : [{ ma_may: "Phay 01", bo_phan: "Gia công - Sơn" }],
  },
  sb: {
    from: query,
    async rpc(name, args) {
      if (name === "ipqc_gc_tieu_chuan_theo_ngay") return {data:{status:"ok",btk:standard,muc:[feature]}};
      if (name === "ipqc_gc_luu_do") {
        measured = args.p_data;
        return { data: "saved" };
      }
      if (name === "ipqc_gc_luu_tieu_chuan") {
        standardPayload = args.p_data;
        return { data: { ok: true, id: 1 } };
      }
      return { data: null };
    },
  },
  XLSX: {
    utils: {
      book_new: () => ({}),
      book_append_sheet() {},
      json_to_sheet: (rows) => {
        exportRows = rows;
        return rows;
      },
    },
    writeFile() {},
  },
  confirm: () => true,
  alert() {},
  prompt: () => null,
};
context.globalThis = context;
vm.createContext(context);
for (const f of ["shared/ipqc-spc.js", "shared/ipqc-btk-qc.js"]) vm.runInContext(fs.readFileSync(f, "utf8"), context);
context.IpqcSpc = context.window.IpqcSpc;
context.IpqcBtkQc = context.window.IpqcBtkQc;
context.IpqcGcMath = require("../shared/ipqc-gc-math.js");
vm.runInContext(fs.readFileSync('shared/ipqc-gc-standard.js','utf8'),context);
vm.runInContext(fs.readFileSync('shared/ipqc-gc-entry.js','utf8'),context);
for(const file of ['shared/ipqc-result-parser.js','shared/ipqc-result-reader.js','shared/ipqc-result-import.js'])
  vm.runInContext(fs.readFileSync(file,'utf8'),context);
vm.runInContext(fs.readFileSync("shared/ipqc-gia-cong.js", "utf8"), context);
const $ = (id) => document.getElementById(id),
  tick = async () => {
    for (let i = 0; i < 12; i++) await new Promise(setImmediate);
  };
(async () => {
  await tick();
  assert.deepEqual(errors, []);
  $("gcMeasureProduct").value = "PART";
  await $("gcMeasureProduct").onchange();
  await tick();
  const inputs = [...$("gcMeasureRows").querySelectorAll("[data-result]")];
  assert.equal(inputs.length, 2);
  inputs[0].value = "19.95";
  inputs[1].value = "20.06";
  $("gcMeasureRows").oninput();
  assert.ok($("gcMeasureRows").textContent.includes("NG"));
  await $("gcMeasureForm").onsubmit({ preventDefault() {} });
  assert.equal(measured.kq[1].gia_tri, 20.06);
  assert.equal(measured.id_btk, 1);
  assert.equal(measured.ma_may, "Phay 01");
  assert.equal(measured.ngay_kiem, $("gcInspectionDate").value);
  records.ipqc_lan_tong_hop.push(
    {
      id: "gc-1",
      cong_doan: "gia_cong",
      ma_sp: "PART",
      revision: "A",
      ma_may: "Phay 01",
      ca: "Ca ngày",
      ma_lo: "LOT-1",
      nguoi_kiem: "QC",
      thoi_diem: new Date().toISOString(),
      id_btk: 1,
      so_mau: 2,
      dat: false,
      tieu_chuan: { btk: standard, muc: [feature] },
      kq: [
        { muc_no: 1, mau: 1, gia_tri: 19.95, dat: true },
        { muc_no: 1, mau: 2, gia_tri: 20.06, dat: false },
      ],
    },
    {
      id: "duc-1",
      cong_doan: "duc",
      ma_sp: "PART",
      revision: "A",
      ma_may: "01",
      id_btk: 2,
      so_mau: 1,
      dat: true,
      thoi_diem: new Date().toISOString(),
      tieu_chuan: { btk: { ...standard, id: 2 }, muc: [feature] },
      kq: [{ muc_no: 1, mau: 1, gia_tri: 20, dat: true }],
    },
  );
  document.querySelector('[data-tab="dashboard"]').onclick();
  await tick();
  assert.equal($("gcMetrics").querySelector("b").textContent, "1");
  $("gcDashboardProcess").value = "";
  $("gcRefresh").onclick();
  await tick();
  assert.equal($("gcMetrics").querySelector("b").textContent, "2");
  $("gcFilterFeature").value = "1/1";
  $("gcFilterFeature").onchange();
  assert.ok($("gcValueChart").innerHTML.includes("Danh nghĩa"));
  assert.ok($("gcValueChart").innerHTML.includes("USL"));
  assert.ok($("gcSpcChart").textContent.includes("Chưa đủ điều kiện"));
  $("gcExcel").onclick();
  assert.equal(exportRows.length, 2);
  assert.equal(exportRows[1]["Giá trị"], 20.06);
  assert.deepEqual(errors, []);
  console.log(
    "PASS result form, approved revision, multi-sample NG; casting/machining/all dashboard, per-revision chart, SPC gating and filtered Excel",
  );
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
