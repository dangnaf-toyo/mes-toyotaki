/* Real Chromium form/filter/export tests with isolated API fixtures; no database writes. */
const fs = require("fs");
const path = require("path");
const assert = require("node:assert/strict");
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || "playwright");
const { backend } = require("./oqc-dashboard-fixture.cjs");

(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const context = await browser.newContext({ viewport: { width: 1366, height: 900 }, timezoneId: "Asia/Bangkok" });
    const day = new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Bangkok" }).format(new Date());
    const definitions = [
      ["POST_OUTSOURCED_MACHINING", "ma", 100, 5],
      ["POST_OUTSOURCED_MACHINING", "in", 200, 20],
      ["POST_OUTSOURCED_MACHINING", "anode", 300, 60],
      ["POST_OUTSOURCED_MACHINING", null, 50, 5],
      ["FULL_POST_MACHINING", null, 80, 8],
      ["POST_PAINTING", null, 90, 9],
      [null, null, 40, 4],
      ["SAMPLING", null, 30, 3],
    ];
    const rows = definitions.map(([scope, process, total, ng], i) => ({
      id: i + 1,
      inspection_date: day,
      shift: "Ca 1",
      product_code: "A",
      product_name: "Model A",
      inspector_code: "QC01",
      inspector_name: "Worker One",
      created_by: "u1",
      total_qty: total,
      ok_qty: total - ng,
      ng_qty: ng,
      so_nguoi_kiem: 1,
      cong_doan_gia_cong_ngoai: process,
      defects: [{ code: "xuoc", label: "Xước", qty: ng, group: "NG ngoại quan" }],
      updated_at: "2026-11-01T00:00:00Z",
      note: "Historical fixture",
    }));
    const contexts = definitions.flatMap(([scope], i) =>
      scope
        ? [
            {
              inspection_id: i + 1,
              source_date: day,
              source_product_code: "A",
              inspection_scope: scope,
              seconds_per_piece: null,
              standard_version_id: null,
            },
          ]
        : [],
    );
    await context.addInitScript({
      content: `
      window.sb=(${backend.toString()})(${JSON.stringify({ tables: { oqc_daily_inspection: rows, oqc_inspection_context: contexts } })});
      window.MesAuth={requireAuth:async()=>({user:{id:'u1'}}),getSession:async()=>({user:{id:'u1'}}),getCurrentUserIdentity:async()=>'Admin'};
      window.MesNav={setTitle(){}};
      window.testExcel=[];
      window.XLSX={utils:{json_to_sheet:rows=>{window.testExcel=rows;return {};},book_new:()=>({}),book_append_sheet(){}},writeFile(){}};
    `,
    });
    await context.route("**/*", (route) => {
      const url = new URL(route.request().url());
      if (url.hostname !== "mes.test" || ["/shared/supabase-client.js", "/shared/navbar.js"].includes(url.pathname))
        return route.fulfill({ body: "", contentType: "application/javascript" });
      const file = path.resolve("." + decodeURIComponent(url.pathname));
      if (!file.startsWith(process.cwd() + path.sep) || !fs.existsSync(file))
        return route.fulfill({ status: 404, body: "" });
      return route.fulfill({
        body: fs.readFileSync(file),
        contentType: file.endsWith(".js") ? "application/javascript" : file.endsWith(".css") ? "text/css" : "text/html",
      });
    });
    const page = await context.newPage(),
      errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.goto("https://mes.test/oqc-daily.html");
    await page.waitForFunction(() => OqcDashboard.getSnapshot()?.records.length === 1);
    async function filter(value, ids) {
      await page.locator("#oqcDashboardScope").selectOption(value);
      await page.waitForFunction(
        ({ value, ids }) => {
          const s = OqcDashboard.getSnapshot();
          return s?.scope === value && s.records.length === ids.length && s.records.every((r) => ids.includes(r.id));
        },
        { value, ids },
      );
      const actual = await page.evaluate(() => {
        const s = OqcDashboard.getSnapshot(),
          m = OqcDashboardMath.summary(s.records, s.plans);
        exportExcel();
        return { checked: m.checked, ok: m.ok, ng: m.ng, rate: m.ngRate, excel: window.testExcel };
      });
      const expected = await page.evaluate(
        (ids) => sb.tables.oqc_daily_inspection.filter((r) => ids.includes(r.id)),
        ids,
      );
      const checked = expected.reduce((n, r) => n + r.total_qty, 0),
        ng = expected.reduce((n, r) => n + r.ng_qty, 0);
      assert.equal(actual.checked, checked);
      assert.equal(actual.ng, ng);
      assert.equal(actual.ok, checked - ng);
      assert.equal(actual.rate, checked ? (ng / checked) * 100 : null);
      assert.equal(actual.excel.length, ids.length);
      assert.equal(
        actual.excel.reduce((n, r) => n + r["Tổng kiểm"], 0),
        checked,
      );
      assert.equal(
        actual.excel.reduce((n, r) => n + r.NG, 0),
        ng,
      );
      return actual;
    }
    await filter("ALL", [1, 2, 3, 4, 5, 6, 7, 8]);
    assert.equal(await page.locator("#oqcOutsourceFilter").count(), 0);
    const options = await page.locator("#oqcDashboardScope option").allTextContents();
    for (const label of [
      "Tất cả kết quả",
      "Kiểm tra sau gia công",
      "Kiểm tra sau Sơn",
      "Kiểm tra sau Gia Công ngoài",
      "Kiểm tra sau Gia Công ngoài - Mạ",
      "Kiểm tra sau Gia Công ngoài - In",
      "Kiểm tra sau Gia Công ngoài - Anode",
    ])
      assert.ok(options.includes(label));

    const created = {};
    for (const [process, label] of [
      ["ma", "Mạ"],
      ["in", "In"],
      ["anode", "Anode"],
    ]) {
      await page.locator("#oqcNewReport").click();
      assert.equal(await page.locator("#oqcOutsourceProcess").isVisible(), false);
      await page.locator("#code").selectOption("A");
      await page.locator("#inspectorCode").selectOption("QC01");
      await page.locator("#total").fill("17");
      await page.locator("#inspectionScope").selectOption("POST_OUTSOURCED_MACHINING");
      const processField = page.locator("#oqcOutsourceProcess");
      assert.equal(await processField.isVisible(), true);
      assert.deepEqual(await processField.locator('option:not([value=""])').allTextContents(), ["Mạ", "In", "Anode"]);
      assert.equal(await processField.evaluate((e) => e.multiple), false);
      const scopeBox = await page.locator("#inspectionScope").boundingBox(),
        processBox = await processField.boundingBox();
      assert.ok(processBox.y >= scopeBox.y + scopeBox.height, "Subprocess must be below scope");
      await page.locator("#save").click();
      assert.equal(await processField.evaluate((e) => e.validity.valueMissing), true);
      assert.equal(
        await page.evaluate(() => sb.calls.filter((c) => c.name === "oqc_save_daily_report").length),
        Object.keys(created).length,
      );
      await processField.selectOption(process);
      await page.locator("#inspectionScope").selectOption("POST_PAINTING");
      assert.equal(await processField.isVisible(), false);
      assert.equal(await processField.evaluate((e) => e.required), false);
      await page.locator("#inspectionScope").selectOption("POST_OUTSOURCED_MACHINING");
      await processField.selectOption(process);
      await page.locator("#oqcInspectionHours").fill("1");
      await page.locator("#defects .defect").first().fill("2");
      if (process === "ma") await page.screenshot({ path: ".review/oqc-outsource-form.png", fullPage: true });
      await page.locator("#save").click();
      await page.waitForFunction(() => document.getElementById("oqcReportDialog").classList.contains("hidden"));
      const saved = await page.evaluate(() => sb.tables.oqc_daily_inspection.at(-1));
      created[process] = saved.id;
      assert.equal(saved.cong_doan_gia_cong_ngoai, process);
      await page.evaluate((id) => editRow(id), saved.id);
      await page.waitForFunction(
        (process) => document.getElementById("oqcOutsourceProcess").value === process,
        process,
      );
      assert.equal(await processField.isVisible(), true);
      await page.locator("#oqcDashboardHome").click();
      await page.evaluate((id) => MesOqcRecord.detail(id), saved.id);
      await page.waitForFunction(
        (label) =>
          document.getElementById("oqcRecordBody").textContent.includes("Kiểm tra sau Gia Công ngoài - " + label),
        label,
      );
      await page.locator("#oqcRecordClose").click();
    }
    console.log(
      "PASS Chromium: three subprocess saves/reopens, one choice, required validation, exact placement and conditional visibility",
    );

    for (const [process, seed, label] of [
      ["ma", 1, "Mạ"],
      ["in", 2, "In"],
      ["anode", 3, "Anode"],
    ]) {
      const actual = await filter("POST_OUTSOURCED_MACHINING:" + process, [seed, created[process]]);
      assert.ok(actual.excel.every((r) => r["Phạm vi kiểm tra"] === "Kiểm tra sau Gia Công ngoài - " + label));
      const historyLabels = await page
        .locator("#rows tr")
        .evaluateAll((rows) => rows.map((r) => r.children[r.children.length - 3].textContent));
      assert.ok(historyLabels.every((value) => value === "Kiểm tra sau Gia Công ngoài - " + label));
      const summary = page
        .locator("#modelSummary tr")
        .filter({ has: page.getByText("Kiểm tra sau Gia Công ngoài - " + label, { exact: true }) });
      await summary.locator("button").click();
      assert.ok((await page.locator("#oqcModelTitle").textContent()).includes(label));
      assert.equal(await page.locator("#oqcModelRecords tr").count(), 3);
      assert.ok(
        (await page.locator("#oqcModelRecords").textContent()).includes("Kiểm tra sau Gia Công ngoài - " + label),
      );
      await page.locator("#oqcModelClose").click();
    }
    const outsideIds = [1, 2, 3, 4, ...Object.values(created)];
    await filter("POST_OUTSOURCED_MACHINING", outsideIds);
    assert.equal(await page.locator("#modelSummary tr").count(), 5, "Four separate outsourced groups plus header");
    assert.equal(
      await page.locator("#oqcDefectSummary details table tr").count(),
      5,
      "Trend details keep four subprocess groups",
    );
    await page.screenshot({ path: ".review/oqc-outsource-dashboard.png", fullPage: true });
    for (const [value, ids, label] of [
      ["FULL_POST_MACHINING", [5], "Kiểm tra sau gia công"],
      ["POST_PAINTING", [6], "Kiểm tra sau Sơn"],
      ["UNKNOWN", [7], null],
      ["LEGACY", [8], null],
    ]) {
      const actual = await filter(value, ids);
      if (label) assert.equal(actual.excel[0]["Phạm vi kiểm tra"], label);
    }
    const allIds = [1, 2, 3, 4, 5, 6, 7, 8, ...Object.values(created)];
    await filter("ALL", allIds);
    await page.evaluate(() => editRow(4));
    assert.equal(await page.locator("#oqcOutsourceProcess").inputValue(), "");
    assert.equal(await page.locator("#oqcOutsourceProcess").evaluate((e) => e.required), false);
    await page.locator(".oqc-extra-info > summary").click();
    await page.locator("#note").fill("Legacy note correction");
    await page.locator("#save").click();
    await page.waitForFunction(() => document.getElementById("oqcReportDialog").classList.contains("hidden"));
    assert.equal(
      await page.evaluate(() => sb.tables.oqc_daily_inspection.find((r) => r.id === 4).cong_doan_gia_cong_ngoai),
      null,
    );
    console.log(
      "PASS Chromium: exact scope labels, separate summary/drilldown/trend groups, all scope filters, OK/NG/rates and actual Excel override; legacy NULL retained",
    );
    await page.setViewportSize({ width: 390, height: 844 });
    await page.locator("#oqcNewReport").click();
    await page.locator("#inspectionScope").selectOption("POST_OUTSOURCED_MACHINING");
    await page.locator("#oqcOutsourceProcess").selectOption("anode");
    assert.equal(await page.locator("#oqcOutsourceProcess").isVisible(), true);
    assert.ok(await page.locator("#oqcOutsourceProcess").evaluate((e) => e.getBoundingClientRect().width >= 300));
    await page.screenshot({ path: ".review/oqc-outsource-mobile.png", fullPage: true });
    assert.deepEqual(errors, []);
    console.log("PASS Chromium desktop/mobile, no page errors; all APIs are isolated fixtures");
    await context.close();
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
