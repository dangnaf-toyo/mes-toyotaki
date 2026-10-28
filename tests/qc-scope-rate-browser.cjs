const fs = require("fs"),
  path = require("path"),
  assert = require("node:assert/strict");
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || "../.review/tools/node_modules/playwright");
const { backend } = require("./oqc-dashboard-fixture.cjs");
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const context = await browser.newContext({ viewport: { width: 1366, height: 900 } }),
      page = await context.newPage(),
      errors = [];
    page.on("pageerror", (e) => errors.push(e.stack));
    page.on("dialog", (d) => d.accept());
    await context.addInitScript({
      content:
        "window.sb=(" +
        backend.toString() +
        ")();" +
        `
 const from=sb.from.bind(sb);sb.from=(name)=>{const q=from(name);q.overlaps=()=>q;return q;}; const records=[[1,'A',100,20],[2,'A',50,5],[3,'A',200,50],[4,'B',0,0],[5,'A',40,4]].map(([id,product_code,total_qty,ng_qty])=>({id,product_code,total_qty,ng_qty,ok_qty:total_qty-ng_qty,inspection_date:sb.day,inspection_time:'09:00',shift:'Ca 1',inspector_code:'QC01',inspector_name:'Worker One',defects:ng_qty?[{code:'xuoc',label:'Xước',qty:ng_qty}]:[]}));
 sb.tables.oqc_daily_inspection=records;sb.tables.oqc_inspection_context=records.filter(r=>r.id!==4).map(r=>({inspection_id:r.id,source_date:r.id===5?'2000-01-01':r.inspection_date,source_product_code:r.product_code,inspection_scope:r.id===2?'POST_PAINTING':'FULL_POST_MACHINING',seconds_per_piece:18}));
 sb.tables.oqc_inspection_work=records.map(r=>({inspection_id:r.id,source_date:r.inspection_date,source_product_code:r.product_code,labor:[{employee_code:'QC01',hours:1.5}],seconds_per_piece:18,planning_hours:7,target_efficiency:.9}));
 window.MesAuth={getSession:async()=>({user:{id:'test'}}),requireAuth:async()=>({user:{id:'test'}}),getCurrentUserIdentity:async()=>'TEST_Admin'};window.MesNav={setTitle(){}};`,
    });
    await context.route("**/*", async (route) => {
      const u = new URL(route.request().url());
      if (u.hostname !== "mes.test" || ["/shared/supabase-client.js", "/shared/navbar.js"].includes(u.pathname))
        return route.fulfill({ body: "", contentType: "application/javascript" });
      const file = path.resolve("." + decodeURIComponent(u.pathname));
      if (!file.startsWith(process.cwd() + path.sep) || !fs.existsSync(file))
        return route.fulfill({ status: 404, body: "" });
      return route.fulfill({
        body: fs.readFileSync(file),
        contentType: file.endsWith(".js") ? "application/javascript" : file.endsWith(".css") ? "text/css" : "text/html",
      });
    });
    await page.goto("https://mes.test/oqc-daily.html");
    await page.waitForFunction(() => typeof OqcDashboard !== "undefined" && OqcDashboard.getSnapshot());
    await page.locator("#oqcDashboardScope").selectOption("ALL");
    await page.waitForFunction(() => OqcDashboard.getSnapshot()?.records.length === 5);
    const summary = () =>
      page
        .locator("#modelSummary tr:has(td)")
        .evaluateAll((rows) => rows.map((r) => [...r.cells].map((c) => c.textContent)));
    let rows = await summary();
    assert.equal(rows.length, 4);
    assert.equal(await page.locator("#modelSummary th").count(), 11);
    assert.ok(
      rows.some(
        (r) =>
          r[0].includes("A") &&
          r[9] === "Kiểm tra sau gia công" &&
          r[10] === "23.33%" &&
          r[4] === "230" &&
          r[5] === "70",
      ),
    );
    assert.ok(rows.some((r) => r[9] === "Kiểm tra sau Sơn" && r[10] === "10.00%"));
    assert.ok(rows.some((r) => r[0].includes("A") && r[9] === "—" && r[10] === "10.00%"));
    assert.ok(rows.some((r) => r[0].includes("B") && r[9] === "—" && r[10] === "—"));
    console.log(
      "PASS model+scope groups, weighted NG/total rate, stale/missing context and zero denominator; existing OK/NG columns retained",
    );
    assert.equal(await page.locator("#rows tr").count(), 5);
    assert.equal(await page.locator("#rows tr").first().locator("td").count(), 17);
    const history = await page
      .locator("#rows tr")
      .evaluateAll((rs) =>
        Object.fromEntries(rs.map((r) => [r.dataset.recordId, [...r.cells].map((c) => c.textContent)])),
      );
    assert.equal(history[1][14], "Kiểm tra sau gia công");
    assert.equal(history[1][15], "20.00%");
    assert.equal(history[2][14], "Kiểm tra sau Sơn");
    assert.equal(history[5][14], "—");
    assert.equal(history[4][15], "—");
    assert.equal(history[1][11], "20.00%");
    console.log("PASS history scope and 2-decimal defect rate; previous %NG unchanged and legacy scope not invented");
    assert.equal(await page.locator("#oqcDefectSummary details th").count(), 7);
    assert.equal(await page.locator("#oqcDefectSummary details tr:has(td)").count(), 3);
    assert.ok((await page.locator("#oqcDefectSummary details").textContent()).includes("23.33%"));
    const firstFull = page.locator("#modelSummary tr:has(td)").filter({ hasText: "Kiểm tra sau gia công" });
    await firstFull.locator("button").click();
    await page.waitForFunction(() => document.querySelector("#oqcModelDialog")?.open);
    assert.equal(await page.locator("#oqcModelRecords tr:has(td)").count(), 2);
    assert.equal(await page.locator("#oqcModelRecords th").count(), 9);
    assert.ok((await page.locator("#oqcModelRecords").textContent()).includes("20.00%"));
    await page.evaluate(() => document.getElementById("oqcModelDialog").close());
    console.log("PASS model drilldown/day rows retain matching scope and per-report rates");
    await page.evaluate(() => editRow(1));
    await page.locator("#total").fill("120");
    await page.locator("#save").click();
    await page.waitForFunction(() => OqcDashboard.getSnapshot()?.records.find((r) => r.id === 1)?.total_qty === 120);
    rows = await summary();
    assert.ok(rows.some((r) => r[9] === "Kiểm tra sau gia công" && r[10] === "21.88%"));
    assert.equal(await page.locator('#rows tr[data-record-id="1"] td').nth(15).textContent(), "16.67%");
    assert.equal(await page.locator('#rows tr[data-record-id="1"] td').nth(14).textContent(), "Kiểm tra sau gia công");
    assert.deepEqual(errors, []);
    await page.screenshot({ path: ".review/oqc-scope-rate-desktop.png", fullPage: true });
    console.log("PASS edit/reload refreshes model and history rates and scope, zero JS errors");
    await context.close();
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
