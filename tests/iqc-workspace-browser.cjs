const fs = require("fs"),
  path = require("path"),
  assert = require("node:assert/strict");
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || "../.review/tools/node_modules/playwright");
function backend() {
  const tables = {
    master_products: [{ ma_sp: "SP01", ten_sp: "Sản phẩm 01" }],
    master_employees: [
      { ma_nv: "SX01", ten_nhan_vien: "Nguyễn Sản Xuất", vai_tro: "nhan_vien_duc" },
      { ma_nv: "QC01", ten_nhan_vien: "Trần QC", vai_tro: "iqc" },
    ],
    iqc_lots: [
      {
        id: "old",
        supplier: "NCC cũ",
        product_code: "SP-CU",
        product_name: "Sản phẩm cũ",
        lot_no: "LOT-CU",
        lot_qty: 50,
        status: "Đã kiểm tra",
        result: "OK",
        inspector: "Người kiểm cũ",
        received_at: "2026-10-01T01:00:00Z",
        sampled_at: "2026-10-01T02:00:00Z",
        created_at: "2026-10-01T01:00:00Z",
      },
    ],
    iqc_defects: [],
  };
  const db = {
    tables,
    auth: { getSession: async () => ({ data: { session: { user: { id: "test-user" } } } }) },
    channel() {
      return {
        on() {
          return this;
        },
        subscribe() {
          return this;
        },
      };
    },
    rpc: async () => ({ data: [{ username: "TK01", full_name: "Lê Văn Kho", role: "kho_nvl" }], error: null }),
    from(table) {
      let filters = [],
        range = [0, 999],
        one = false,
        mutation = null;
      const q = {
        select() {
          return q;
        },
        order() {
          return q;
        },
        range(a, b) {
          range = [a, b];
          return q;
        },
        limit(n) {
          range = [0, n - 1];
          return q;
        },
        eq(k, v) {
          filters.push((r) => r[k] === v);
          return q;
        },
        gte(k, v) {
          filters.push((r) => r[k] >= v);
          return q;
        },
        lte(k, v) {
          filters.push((r) => r[k] <= v);
          return q;
        },
        or() {
          return q;
        },
        single() {
          one = true;
          return q;
        },
        maybeSingle() {
          one = true;
          return q;
        },
        insert(data) {
          mutation = ["insert", Array.isArray(data) ? data[0] : data];
          return q;
        },
        update(data) {
          mutation = ["update", data];
          return q;
        },
        delete() {
          mutation = ["delete"];
          return q;
        },
        then(resolve, reject) {
          tables[table] ??= [];
          let rows = tables[table].filter((r) => filters.every((f) => f(r)));
          if (mutation) {
            if (mutation[0] === "insert") {
              const r = { id: "new-" + tables[table].length, created_at: new Date().toISOString(), ...mutation[1] };
              tables[table].push(r);
              rows = [r];
            }
            if (mutation[0] === "update") rows.forEach((r) => Object.assign(r, mutation[1]));
            if (mutation[0] === "delete") tables[table] = tables[table].filter((r) => !rows.includes(r));
          }
          rows = rows.slice(range[0], range[1] + 1);
          return Promise.resolve({ data: one ? rows[0] || null : rows, error: null }).then(resolve, reject);
        },
      };
      return q;
    },
  };
  return db;
}
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const context = await browser.newContext({
        viewport: { width: 1440, height: 1000 },
        timezoneId: "America/Los_Angeles",
      }),
      page = await context.newPage(),
      errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    page.on("dialog", (d) => d.accept());
    await context.addInitScript({
      content:
        "window.sb=(" +
        backend.toString() +
        ')();window.sbTaiHet=async mk=>{let data=[];for(let off=0;;off+=1000){const r=await mk().range(off,off+999);if(r.error)return r;data.push(...r.data);if(r.data.length<1000)return {data,error:null};}};window.MesAuth={getSession:async()=>({user:{id:"test-user"}}),requireAuth:async()=>({user:{id:"test-user"}}),getCurrentUserIdentity:async()=>"TEST_Admin"};window.MesNav={setTitle(){}};',
    });
    await context.route("**/*", (route) => {
      const u = new URL(route.request().url());
      if (u.hostname !== "mes.test" || ["/shared/supabase-client.js", "/shared/navbar.js"].includes(u.pathname))
        return route.fulfill({ body: "", contentType: "application/javascript" });
      const file = path.resolve("." + decodeURIComponent(u.pathname));
      if (!file.startsWith(process.cwd() + path.sep) || !fs.existsSync(file))
        return route.fulfill({ status: 404, body: "" });
      return route.fulfill({
        body: fs.readFileSync(file),
        contentType: file.endsWith(".js") ? "application/javascript" : "text/html",
      });
    });
    await page.goto("https://mes.test/iqc.html");
    await page.waitForFunction(
      () => typeof IqcWorkspace !== "undefined" && IqcWorkspace.getSnapshot()?.lots.length === 1,
    );
    assert.deepEqual(errors, []);
    assert.equal(await page.locator("#sampledDate").count(), 0);
    assert.deepEqual(
      await page.locator("#supplier option").evaluateAll((es) => es.map((e) => e.value).filter(Boolean)),
      ["BRV", "HANIN", "VIỆT PHÁP", "ASAHI", "MINGANN"],
    );
    assert.deepEqual(
      await page.locator("#iqcScope option").evaluateAll((es) => es.map((e) => e.value).filter(Boolean)),
      ["Bán thành phẩm", "Linh kiện đầu vào", "Mạ", "In", "Anode", "Đúc", "Thành phẩm"],
    );
    assert.equal(await page.locator("#iqcScope").getAttribute("required"), "");
    console.log("PASS form: sampled input removed; exactly 5 suppliers, 7 required scopes");
    assert.ok((await page.locator("#qc02-employees").textContent()).includes("Nguyễn Sản Xuất"));
    assert.ok((await page.locator("#qc02-employees").textContent()).includes("Lê Văn Kho"));
    await page.evaluate(async () => {
      sb.tables.master_employees.push({ ma_nv: "NEW", ten_nhan_vien: "Nhân sự mới", vai_tro: "kho_nvl" });
      sb.tables.master_products.push({ ma_sp: "SP02", ten_sp: "Sản phẩm mới" });
      await IqcWorkspace.refresh();
    });
    assert.equal(await page.locator('#qc02-employees option[value="NEW_Nhân sự mới"]').count(), 1);
    await page.locator("#productCode").fill("SP02");
    await page.locator("#productCode").dispatchEvent("focus");
    await page.locator("#productCode").dispatchEvent("change");
    await page.waitForFunction(() => document.getElementById("productName").value === "Sản phẩm mới");
    console.log("PASS all-role personnel/account union and fresh product/name after master changes");
    await page.locator("#inspectionType").selectOption("Kiểm tra N5");
    await page.locator("#supplier").selectOption("BRV");
    await page.locator("#iqcScope").selectOption("Mạ");
    await page.locator("#lotNo").fill("TEST-LOT");
    await page.locator("#lotQty").fill("50");
    await page.locator("#inspector").fill("SX01_Nguyễn Sản Xuất");
    await page.locator("#receivedDate").fill("2026-10-27T09:00");
    await page.evaluate(() => confirmDate("receivedDate", "receivedConfirm"));
    await page.locator("#saveBtn").click();
    await page.waitForFunction(() => sb.tables.iqc_lots.length === 2);
    const saved = await page.evaluate(() => sb.tables.iqc_lots[1]);
    assert.equal(saved.pham_vi, "Mạ");
    assert.equal(saved.nguoi_kiem_id, "SX01");
    assert.equal(saved.nguoi_kiem_ten, "Nguyễn Sản Xuất");
    assert.equal(saved.product_name, "Sản phẩm mới");
    assert.equal(saved.sampled_at, undefined);
    await page.waitForFunction(() => IqcWorkspace.getSnapshot()?.lots.length === 2);
    console.log("PASS actual form submit with non-QC inspector: stores code/name/scope, no sampled timestamp");
    await page.locator("#tabStats").click();
    await page.waitForFunction(() => document.getElementById("iqcDash-total").textContent === "2");
    assert.equal(await page.locator("#iqcDash-waiting").textContent(), "1");
    assert.equal(await page.locator("#iqcDash-ok").textContent(), "1");
    assert.ok((await page.locator("#iqcChartScope").textContent()).includes("Chưa xác định"));
    assert.ok((await page.locator("#iqcChartScope").textContent()).includes("Mạ"));
    await page.locator("#iqcDashProduct").fill("SP02");
    assert.equal(await page.locator("#iqcDash-total").textContent(), "1");
    await page.locator("#iqcDashProduct").fill("");
    await page.screenshot({ path: ".review/iqc-dashboard-desktop.png", fullPage: true });
    console.log("PASS dashboard real fixture totals, waiting, legacy unknown scope and product filter");
    await page.evaluate(async () => {
      const lot = await IqcApi.getLot("new-1");
      await IqcApi.updateLot(lot.id, {
        ...lot,
        receivedDate: lot.receivedInput,
        pickupDate: lot.pickupInput,
        scope: "In",
        supplier: "HANIN",
        inspector: "TK01_Lê Văn Kho",
        note: "Đã chỉnh sửa",
      });
      await IqcWorkspace.refresh();
    });
    assert.ok((await page.locator("#iqcChartScope").textContent()).includes("In"));
    assert.ok((await page.locator("#iqcChartSupplier").textContent()).includes("HANIN"));
    await page.evaluate(async () => {
      await IqcApi.completeLot("new-1", {
        completionDate: "2026-10-27T10:00",
        result: "NG",
        inspector: "NEW_Nhân sự mới",
      });
      await IqcWorkspace.refresh();
    });
    assert.equal(await page.locator("#iqcDash-ng").textContent(), "1");
    assert.equal(await page.locator("#iqcDash-done").textContent(), "2");
    assert.match(await page.locator("#iqcRates").textContent(), /50.00%/);
    console.log("PASS edit and completion reread update dashboard counts, supplier, scope and 50% rates");
    await page.locator("#tabIqc").click();
    await page.locator("#iqcFilterScope").selectOption("In");
    assert.equal(await page.locator("#lotTable tr").count(), 1);
    await page.locator("#iqcFilterScope").selectOption("");
    await page.locator("#iqcFilterInspector").fill("Lê Văn Kho");
    assert.equal(await page.locator("#lotTable tr").count(), 0);
    await page.locator("#iqcFilterInspector").fill("");
    await page.evaluate(async () => renderHistory(await IqcApi.searchLotHistory("", "", "")));
    assert.ok((await page.locator("#historyTable").textContent()).includes("In"));
    await page.evaluate(() => openDetail("old"));
    await page.waitForFunction(() =>
      document.getElementById("detailBody").textContent.includes("Chưa xác định (dữ liệu cũ)"),
    );
    assert.ok((await page.locator("#detailBody").textContent()).includes("Người kiểm cũ"));
    assert.equal(await page.evaluate(() => sb.tables.iqc_lots[0].sampled_at), "2026-10-01T02:00:00Z");
    await page.evaluate(() => closeDetail());
    await page.screenshot({ path: ".review/iqc-report-desktop.png", fullPage: true });
    console.log("PASS report filters, scope in history/detail and preserved historical sampled timestamp/inspector");
    const csv = await page.evaluate(() => IqcWorkspace.csv(IqcWorkspace.getSnapshot().lots));
    assert.ok(csv.includes("Phạm vi"));
    assert.ok(csv.includes("In"));
    assert.ok(csv.includes("Nhân sự mới"));
    console.log("PASS CSV report includes scope and inspector identity");
    const denied = await page.evaluate(async () => {
      const data = { supplier: "BRV", scope: "In", productCode: "SP01", inspector: "SX01_Nguyễn Sản Xuất" };
      const out = [];
      for (const patch of [{ scope: "" }, { supplier: "FREE" }, { productCode: "FREE" }, { inspector: "FREE" }]) {
        try {
          await IqcApi.addLot({ ...data, ...patch });
          out.push(false);
        } catch {
          out.push(true);
        }
      }
      return out;
    });
    assert.deepEqual(denied, [true, true, true, true]);
    assert.deepEqual(errors, []);
    console.log("PASS invalid supplier/scope/product/inspector rejected; zero browser JS errors");
    const total = await page.evaluate(async () => {
      const existing = sb.tables.iqc_lots.slice();
      sb.tables.iqc_lots.push(...Array.from({ length: 1001 }, (_, i) => ({ id: 'page-' + i, status: 'Đang chờ kiểm' })));
      try { return (await IqcApi.getDashboardData()).summary.total; }
      finally { sb.tables.iqc_lots = existing; }
    });
    assert.equal(total,1003);
    console.log('PASS dashboard reads all 1003 LOTs across backend pagination');
    await context.close();
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
