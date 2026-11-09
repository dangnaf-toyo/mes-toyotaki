const fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict");
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || "playwright");
const XLSX = require("../.review/xlsx.cjs"),
  { backend } = require("./ipqc-gc-fixture.cjs");
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const context = await browser.newContext({
        viewport: { width: 1560, height: 1000 },
        timezoneId: "Pacific/Honolulu",
      }),
      page = await context.newPage(),
      errors = [];
    let allowChange = false,
      dialogs = 0;
    page.on("pageerror", (e) => errors.push(e.message));
    page.on("dialog", (d) => {
      dialogs++;
      return allowChange ? d.accept() : d.dismiss();
    });
    await context.addInitScript({
      content: `const RealDate=Date;window.Date=class extends RealDate{constructor(...a){super(...(a.length?a:['2026-11-06T18:00:00Z']));}static now(){return new RealDate('2026-11-06T18:00:00Z').getTime();}};
    window.sb=(${backend.toString()})();window.IS_PROD=false;
    const a={...sb.tables.ipqc_btk[0],id:1,phien_ban:'A',ngay_hieu_luc:'2026-01-01',dang_dung:false,buoc_gia_cong:null,so_mau:1};
    const b={...a,id:2,phien_ban:'B',ngay_hieu_luc:'2026-02-01',dang_dung:true};
    sb.tables.ipqc_btk=[a,b,{...a,id:3,phien_ban:'PENDING',ngay_hieu_luc:'2026-01-10',trang_thai:'cho_kiem_tra'}];
    const feature=sb.tables.ipqc_btk_muc[0];sb.tables.ipqc_btk_muc=[{...feature,id_btk:1,muc_no:1,co_mau:1},{...feature,id_btk:2,muc_no:1,danh_nghia:30,lsl:29.9,usl:30.1,co_mau:1}];
    window.MesAuth={getSession:async()=>({user:{id:'u1'}}),getCurrentUserIdentity:async()=>'Inspector'};
    window.MesNav={setTitle(){}};window.sbTaiHet=async make=>await make();`,
    });
    await context.route("**/*", (route) => {
      const u = new URL(route.request().url());
      let file;
      if (u.hostname === "cdn.jsdelivr.net" && u.pathname.includes("/xlsx@"))
        file = path.resolve(".review/xlsx.cjs");
      else if (
        u.hostname === "mes.test" &&
        !["/shared/supabase-client.js", "/shared/navbar.js"].includes(u.pathname)
      )
        file = path.resolve("." + decodeURIComponent(u.pathname));
      if (!file) return route.fulfill({ body: "", contentType: "application/javascript" });
      return route.fulfill({
        body: fs.readFileSync(file),
        contentType: /\.(js|cjs)$/.test(file)
          ? "application/javascript"
          : file.endsWith(".html")
            ? "text/html"
            : file.endsWith(".css")
              ? "text/css"
              : "application/octet-stream",
      });
    });
    await page.goto("https://mes.test/ipqc-gia-cong.html");
    await page.waitForFunction(() => document.getElementById("gcInspectionDate").value);
    assert.equal(
      await page.locator("#gcInspectionDate").inputValue(),
      "2026-11-07",
      "Vietnam date, not browser/UTC date",
    );
    for (const id of ["gcMeasureVersion", "gcLot", "gcFilterRevision", "gcFilterStep", "gcFilterLot"])
      assert.equal(await page.locator("#" + id).count(), 0, id);
    assert.deepEqual(await page.locator("#gcResultMode option").allTextContents(), ["Thủ công", "Tự động"]);
    assert.equal(await page.locator("#gcResultMode").inputValue(), "manual");
    assert.ok(await page.locator("#gcResultImportPanel").isHidden());
    await page.locator("#gcMeasureProduct").fill("PART");
    await page.locator("#gcMeasureProduct").dispatchEvent("change");
    await page.waitForFunction(
      () =>
        document.getElementById("gcMeasureInfo").title.includes("Revision B") &&
        !document.getElementById("gcMeasureInput").disabled,
    );
    await page.locator("[data-result]").fill("30.02");
    assert.equal(
      await page.locator("#gcMeasureProduct").inputValue(),
      "PART",
      "Blur must not divert measurement input into Model",
    );
    await page.locator("#gcInspectionDate").fill("2026-01-15");
    await page.locator("#gcInspectionDate").dispatchEvent("change");
    await page.waitForFunction(() => document.getElementById("gcInspectionDate").value === "2026-11-07");
    assert.equal(
      await page.locator("[data-result]").inputValue(),
      "30.02",
      "Cancel changing standards keeps unsaved values",
    );
    allowChange = true;
    await page.locator("#gcInspectionDate").fill("2026-01-15");
    await page.locator("#gcInspectionDate").dispatchEvent("change");
    await page.waitForFunction(
      () =>
        document.getElementById("gcMeasureInfo").title.includes("Revision A") &&
        !document.getElementById("gcMeasureInput").disabled,
    );
    assert.equal(await page.locator("[data-result]").inputValue(), "");
    await page.locator("[data-result]").fill("20.01");
    assert.ok(await page.locator("[data-result]").evaluate((e) => e.classList.contains("measure-ok")));
    await page.locator("#gcInspectionDate").fill("2026-01-16");
    await page.locator("#gcInspectionDate").dispatchEvent("change");
    await page.waitForFunction(() => !document.getElementById("gcMeasureInput").disabled);
    assert.equal(
      await page.locator("[data-result]").inputValue(),
      "20.01",
      "Same effective standard preserves values across date changes",
    );
    await page.locator("#gcResultMode").selectOption("file");
    assert.ok(await page.locator("#gcResultImportPanel").isVisible());
    await page.locator("#gcResultMode").selectOption("manual");
    await page.screenshot({ path: ".review/ipqc-date-entry-desktop.png", fullPage: true });
    await page.locator("#gcSaveMeasure").click();
    await page.waitForFunction(() => sb.tables.ipqc_gc_lan.length === 1);
    const saved = await page.evaluate(() => sb.tables.ipqc_gc_lan[0]);
    assert.equal(saved.ngay_kiem, "2026-01-16");
    assert.equal(saved.id_btk, 1);
    assert.equal(saved.revision, "A");
    assert.equal(saved.dat, true);
    assert.equal(saved.thoi_diem, "2026-11-06T18:00:00.000Z");
    assert.ok(saved.cap_nhat_luc);
    assert.equal(saved.ma_lo, undefined);
    await page.locator('[data-tab="dashboard"]').click();
    await page.waitForFunction(() => document.querySelector("#gcMetrics b")?.textContent === "0");
    await page.locator("#gcFrom").fill("2026-01-16");
    await page.locator("#gcTo").fill("2026-01-16");
    await page.locator("#gcRefresh").click();
    await page.waitForFunction(() => document.querySelector("#gcMetrics b")?.textContent === "1");
    assert.deepEqual(await page.locator("#gcMetrics b").allTextContents(), ["1", "1", "1", "0", "0.00%"]);
    assert.ok((await page.locator("#gcDataRows").textContent()).includes("16/01/2026"));
    await page.locator("#gcFilterFeature").selectOption("1/1");
    assert.match(await page.locator("#gcSpcChart").textContent(), /Chưa đủ điều kiện SPC/);
    const exported = page.waitForEvent("download");
    await page.locator("#gcExcel").click();
    const download = await exported,
      workbook = XLSX.read(fs.readFileSync(await download.path()), { type: "buffer" }),
      rows = XLSX.utils.sheet_to_json(workbook.Sheets.IPQC);
    assert.equal(rows[0]["Ngày kiểm"], "2026-01-16");
    assert.equal(rows[0].Revision, "A");
    assert.equal(rows[0]["Giá trị"], 20.01);
    assert.ok(rows[0]["Tạo lúc"].includes("7/11/2026"));
    await page.screenshot({ path: ".review/ipqc-date-dashboard-desktop.png", fullPage: true });
    await page.setViewportSize({ width: 390, height: 900 });
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
    await page.screenshot({ path: ".review/ipqc-date-dashboard-mobile.png", fullPage: true });
    await page.setViewportSize({ width: 1560, height: 1000 });
    await page.locator('[data-tab="measure"]').click();
    await page.locator("#gcInspectionDate").fill("2025-12-31");
    await page.locator("#gcInspectionDate").dispatchEvent("change");
    await page.waitForFunction(
      () => document.getElementById("gcMeasureInfo").textContent === "Chưa có tiêu chuẩn.",
    );
    assert.equal(await page.locator("[data-result]").count(), 0);
    assert.ok(await page.locator("#gcSaveMeasure").isDisabled());
    await page.evaluate(() =>
      sb.tables.ipqc_btk.push({ ...sb.tables.ipqc_btk[1], id: 4, phien_ban: "C", dang_dung: false }),
    );
    await page.locator("#gcInspectionDate").fill("2026-02-15");
    await page.locator("#gcInspectionDate").dispatchEvent("change");
    await page.waitForFunction(() =>
      document.getElementById("gcMeasureInfo").textContent.includes("chồng lấn"),
    );
    assert.equal(await page.locator("[data-result]").count(), 0);
    assert.ok(await page.locator("#gcSaveMeasure").isDisabled());
    await page.evaluate(() => {
      sb.tables.ipqc_btk = sb.tables.ipqc_btk.filter((b) => b.id !== 4);
      const rpc = sb.rpc.bind(sb);
      sb.rpc = async (n, a) => {
        if (n === "ipqc_gc_tieu_chuan_theo_ngay")
          await new Promise((r) => setTimeout(r, a.p_ngay_kiem === "2026-01-15" ? 150 : 10));
        return rpc(n, a);
      };
    });
    await page.locator("#gcInspectionDate").fill("2026-01-15");
    await page.locator("#gcInspectionDate").dispatchEvent("change");
    await page.locator("#gcInspectionDate").fill("2026-02-15");
    await page.locator("#gcInspectionDate").dispatchEvent("change");
    await page.waitForTimeout(250);
    assert.match(await page.locator("#gcMeasureInfo").getAttribute("title"), /Revision B/);
    assert.ok(await page.locator("[data-result]").isEnabled());
    assert.deepEqual(errors, []);
    assert.ok(dialogs >= 2);
    console.log(
      "PASS Vietnam inspection-day default, minimal UI/modes, historical auto standard, date boundary/ambiguity, preserve/cancel unsaved data, blur/race safety, explicit save/audit, dashboard by inspection date, revision-specific charts/Excel and responsive layout",
    );
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
