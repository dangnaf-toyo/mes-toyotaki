/* Reproduce the staging standards' missing-unit state, with actual Calypso PDF bytes. */
const fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict");
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || "playwright");
const { backend } = require("./ipqc-gc-fixture.cjs");
const v = JSON.parse(fs.readFileSync(".review/zeiss-validation.json", "utf8")),
  N = v.features.length;
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const context = await browser.newContext({ viewport: { width: 1560, height: 1000 } }),
      page = await context.newPage(),
      errors = [];
    let overwrite = false,
      dialogs = 0;
    page.on("pageerror", (e) => errors.push(e.message));
    page.on("dialog", (d) => {
      dialogs++;
      return overwrite ? d.accept() : d.dismiss();
    });
    await context.addInitScript({
      content: `window.sb=(${backend.toString()})();window.IS_PROD=false;
    sb.tables.ipqc_btk[0].so_mau=1;sb.tables.ipqc_btk_muc=${JSON.stringify(v.features)}.map(m=>({...m,muc_no:String(m.muc_no),don_vi:null}));
    window.MesAuth={getSession:async()=>({user:{id:'u1'}}),getCurrentUserIdentity:async()=>'Inspector'};
    window.MesNav={setTitle(){}};window.sbTaiHet=async make=>await make();`,
    });
    await context.route("**/*", (route) => {
      const u = new URL(route.request().url());
      let file;
      if (u.hostname === "cdn.jsdelivr.net" && u.pathname.includes("/pdfjs-dist@"))
        file = path.resolve(".review/tools/node_modules/pdfjs-dist/build", path.basename(u.pathname));
      else if (u.hostname === "cdn.jsdelivr.net" && u.pathname.includes("/xlsx@"))
        file = path.resolve(".review/xlsx.cjs");
      else if (
        u.hostname === "mes.test" &&
        !["/shared/supabase-client.js", "/shared/navbar.js"].includes(u.pathname)
      )
        file = path.resolve("." + decodeURIComponent(u.pathname));
      if (!file) return route.fulfill({ body: "", contentType: "application/javascript" });
      return route.fulfill({
        body: fs.readFileSync(file),
        headers: { "Access-Control-Allow-Origin": "*" },
        contentType: /\.(js|mjs|cjs)$/.test(file)
          ? "application/javascript"
          : file.endsWith(".html")
            ? "text/html"
            : file.endsWith(".css")
              ? "text/css"
              : "application/octet-stream",
      });
    });
    const row = (i) => page.locator('[data-candidate="' + i + '"]');
    const values = () =>
      page.locator("#gcMeasureRows [data-result]").evaluateAll((xs) => xs.map((x) => x.value));
    const count = (k) =>
      page
        .locator('[data-count="' + k + '"]')
        .textContent()
        .then(Number);
    async function start() {
      await page.goto("https://mes.test/ipqc-gia-cong.html");
      await page.waitForFunction(() => document.getElementById("gcMachine").options.length === 1);
      await page.locator("#gcMeasureProduct").fill("PART");
      await page.locator("#gcMeasureProduct").dispatchEvent("change");
      await page.waitForFunction(
        (n) => document.querySelectorAll("#gcMeasureRows [data-result]").length === n,
        N,
      );
      await page.locator("#gcResultMode").selectOption("file");
      await page.locator("#gcResultFile").setInputFiles(v.file);
      await page.waitForFunction(
        () => document.getElementById("gcImportStatus").textContent.includes("ZEISS Calypso"),
        null,
        { timeout: 60000 },
      );
    }
    async function units() {
      await page.locator("#gcImportDefaultUnit").selectOption("mm");
      await page.locator("#gcImportSameUnit").check();
    }
    await start();
    const before = await page.evaluate(() => JSON.stringify(sb.tables.ipqc_btk_muc));
    assert.equal(await count("read"), N);
    assert.equal(await count("matched"), 0);
    assert.ok(await row(0).locator("[data-accept]").isDisabled());
    assert.match(await row(0).locator("[data-accept]").getAttribute("title"), /đơn vị/);
    await page.locator("#gcImportDefaultUnit").selectOption("mm");
    assert.equal(await count("matched"), 0, "No implicit unit assumption");
    await page.locator("#gcImportSameUnit").check();
    assert.equal(await count("matched"), N);
    assert.equal(await page.locator("[data-accept]:checked").count(), N);
    await page.locator("#gcImportSync").click();
    assert.deepEqual((await values()).map(Number), v.oracle);
    const expectedNG = v.features.filter(
      (m, i) => (m.lsl !== null && v.oracle[i] < m.lsl) || (m.usl !== null && v.oracle[i] > m.usl),
    ).length;
    assert.equal(await page.locator("#gcMeasureRows .measure-ng").count(), expectedNG);
    assert.equal(dialogs, 0, "One Apply action, without an extra confirmation dialog");
    assert.equal(await count("filled"), N);
    assert.equal(await page.evaluate(() => sb.calls.filter(c=>c.name==='ipqc_gc_luu_do').length + sb.uploads.length), 0);
    assert.ok(await page.locator("#gcResultConfirmed").isChecked());
    await page.locator('[data-tab="dashboard"]').click();
    await page.locator('[data-tab="measure"]').click();
    await page.locator("#gcImportFilter").selectOption("unmatched");
    assert.equal(await page.locator("[data-candidate]").count(), 0);
    await page.locator("#gcImportFilter").selectOption("");
    assert.deepEqual((await values()).map(Number), v.oracle);
    await page.locator("#gcResultImportPanel").screenshot({ path: ".review/cmm-apply-desktop.png" });
    await page.setViewportSize({ width: 390, height: 900 });
    assert.ok(
      await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1),
      "No page overflow on mobile",
    );
    await page.locator("#gcResultImportPanel").screenshot({ path: ".review/cmm-apply-mobile.png" });
    await page.setViewportSize({ width: 1560, height: 1000 });
    await page.locator("#gcSaveMeasure").click();
    await page.waitForFunction(() => sb.tables.ipqc_gc_lan.length === 1);
    const saved = await page.evaluate(() => sb.tables.ipqc_gc_lan[0]);
    assert.deepEqual(
      saved.kq.map((k) => k.gia_tri),
      v.oracle,
    );
    assert.equal(saved.dat, expectedNG === 0);
    assert.equal(saved.kq.filter((k) => !k.dat).length, expectedNG);
    assert.equal(saved.nhan_dien.gia_tri_da_xac_minh.length, N);
    assert.ok(saved.nhan_dien.gia_tri_da_xac_minh.every((t) => t.don_vi_bo_sung_da_xac_nhan === "mm"));
    assert.equal(await page.evaluate(() => JSON.stringify(sb.tables.ipqc_btk_muc)), before);
    await page.locator('[data-tab="dashboard"]').click();
    await page.waitForFunction(() => document.getElementById("gcDataRows").textContent.includes("Nhập từ file"));
    assert.equal(await page.locator("#gcDataRows tbody tr").count(), N);
    // Duplicate targets do not poison the whole batch. Fixing only those rows keeps prior values.
    await start();
    await units();
    await row(1).locator("[data-match]").selectOption("1");
    assert.match(await row(0).locator(".cmm-state summary").textContent(), /Trùng đặc tính/);
    await page.locator("#gcImportSync").click();
    const partial = await values();
    assert.equal(partial[0], "");
    assert.equal(partial[1], "");
    assert.deepEqual(partial.slice(2).map(Number), v.oracle.slice(2));
    assert.equal(await count("filled"), N - 2);
    assert.match(await page.locator("#gcImportStatus").textContent(), /Chưa khớp 2/);
    await row(1).locator("[data-match]").selectOption("2");
    await page.locator("#gcImportSync").click();
    assert.deepEqual((await values()).map(Number), v.oracle);
    assert.equal(await count("filled"), N);
    // Wrong known units are distinct from missing units and an explicit selection overrides cell units.
    await row(0).locator("[data-unit]").selectOption("deg");
    assert.equal(await row(0).locator(".cmm-state summary").textContent(), "Sai đơn vị");
    assert.ok(await row(0).locator("[data-accept]").isDisabled());
    await row(0).locator("[data-unit]").selectOption("mm");
    assert.equal(await row(0).locator(".cmm-state summary").textContent(), "Khớp");
    // Preserve decimal representation, manual overwrite protection, and final confirmation after edits.
    await row(0).locator("[data-import-value]").fill(v.oracle[0].toFixed(6));
    await row(0).locator("[data-import-value]").dispatchEvent("change");
    await page.locator("#gcImportSync").click();
    assert.equal((await values())[0], v.oracle[0].toFixed(6));
    await page
      .locator("[data-result]")
      .first()
      .fill(String(v.oracle[0] + 0.001));
    assert.equal(await page.locator("#gcResultConfirmed").isChecked(), false);
    await page.locator("#gcImportSync").click();
    assert.equal((await values())[0], String(v.oracle[0] + 0.001));
    overwrite = true;
    await page.locator("#gcImportSync").click();
    assert.equal((await values())[0], v.oracle[0].toFixed(6));
    assert.deepEqual(errors, []);
    // Contract failure: a non-writing setter must not produce a false success message/provenance.
    await page.goto("https://mes.test/ipqc-gia-cong.html");
    await page.waitForFunction(() => document.getElementById("gcMachine").options.length === 1);
    await page.evaluate(() => {
      const mount = IpqcGcEntry.mount;
      IpqcGcEntry.mount = (...args) => {
        const entry = mount(...args);
        window.testEntry = entry;
        let rejected = false;
        try {
          entry.setMany([
            { muc_no: 1, mau: 1, value: "123" },
            { muc_no: 2, mau: 101, value: "456" },
          ]);
        } catch {
          rejected = true;
        }
        window.atomicBatchValid = rejected && entry.get(1, 1) === "";
        entry.setMany = () => {};
        return entry;
      };
    });
    await page.locator("#gcMeasureProduct").fill("PART");
    await page.locator("#gcMeasureProduct").dispatchEvent("change");
    await page.waitForFunction(() => !!window.testEntry);
    assert.ok(await page.evaluate(() => atomicBatchValid));
    await page.locator("#gcResultMode").selectOption("file");
    await page.locator("#gcResultFile").setInputFiles(v.file);
    await page.waitForFunction(() =>
      document.getElementById("gcImportStatus").textContent.includes("ZEISS Calypso"),
    );
    await units();
    await page.locator("#gcImportSync").click();
    assert.match(await page.locator("#gcImportStatus").textContent(), /Chưa điền được đặc tính/);
    assert.equal(await count("filled"), 0);
    assert.ok((await values()).every((x) => x === ""));
    assert.equal(await page.evaluate(() => sb.calls.filter(c=>c.name==='ipqc_gc_luu_do').length), 0);
    console.log(
      JSON.stringify({
        result:
          "PASS real PDF one-click Apply with missing MES units/string keys; no implicit units; readback, partial duplicates/recovery, correct samples, decimal precision, overwrite, no pre-save writes, immutable standards, save/dashboard, tab/filter persistence, desktop/mobile",
        actuals: N,
      }),
    );
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
