/* Actual supplied M2 PDF against an unmodified, local read-only snapshot of staging standards.
 * This complements the corresponding-standard fixture tests: unknown geometric positions stay blank. */
const fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict");
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || "playwright");
const { backend } = require("./ipqc-gc-fixture.cjs");
const verification = JSON.parse(fs.readFileSync(".review/zeiss-validation.json", "utf8"));
const snapshot = JSON.parse(
  fs
    .readFileSync(process.env.MES_CMM_SNAPSHOT || ".review/m2-staging-before.json", "utf8")
    .replace(/^\uFEFF/, ""),
).rows[0].audit;
const actual = Object.fromEntries(verification.parsed.map((c) => [c.id, c.samples[0].value]));
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    for (const model of ["TTI-MOT-04", "TTI-MOT-05"]) {
      const data = snapshot.gc.find(
        (b) => b.standard.ma_sp === model && b.standard.trang_thai === "da_duyet",
      );
      assert.ok(data, "Read current staging standards before running this test");
      // Independently checked against the supplied PDF and the recorded MES limits.
      const mapping = [
        ["1", 1],
        ["7", 2],
        ["18", 7],
        ["25", 10],
      ];
      if (model === "TTI-MOT-05") mapping.push(["15", 6]);
      const context = await browser.newContext({ viewport: { width: 1560, height: 1000 } });
      const page = await context.newPage(),
        errors = [];
      page.on("pageerror", (e) => errors.push(e.message));
      await context.addInitScript({
        content: `window.sb=(${backend.toString()})();window.IS_PROD=false;
        sb.tables.ipqc_btk=[${JSON.stringify(data.standard)}];sb.tables.ipqc_btk_muc=${JSON.stringify(data.features)};
        sb.tables.master_products=[{ma_sp:${JSON.stringify(model)},ten_sp:'Supplied PDF verification'}];
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
      await page.goto("https://mes.test/ipqc-gia-cong.html");
      await page.waitForFunction(() => document.getElementById("gcMachine").options.length === 1);
      await page.locator("#gcMeasureProduct").fill(model);
      await page.locator("#gcMeasureProduct").dispatchEvent("change");
      await page.waitForFunction(
        () => document.querySelectorAll("#gcMeasureRows [data-result]").length === 15,
      );
      const before = await page.evaluate(() => JSON.stringify([sb.tables.ipqc_btk, sb.tables.ipqc_btk_muc]));
      await page.locator("#gcResultMode").selectOption("file");
      await page.locator("#gcResultFile").setInputFiles(verification.file);
      await page.waitForFunction(() =>
        document.getElementById("gcImportStatus").textContent.includes("ZEISS Calypso"),
      );
      assert.equal(await page.locator('[data-count="read"]').textContent(), "11");
      assert.equal(
        await page.locator('[data-count="matched"]').textContent(),
        "0",
        "Unit confirmation is required",
      );
      await page.locator("#gcImportDefaultUnit").selectOption("mm");
      await page.locator("#gcImportSameUnit").check();
      assert.equal(Number(await page.locator('[data-count="matched"]').textContent()), mapping.length);
      await page.locator("#gcImportSync").click();
      const values = await page
        .locator("#gcMeasureRows [data-result]")
        .evaluateAll((xs) => xs.map((x) => ({ no: Number(x.dataset.no), value: x.value })));
      for (const { no, value } of values) {
        const mapped = mapping.find(([, n]) => n === no);
        assert.equal(
          value,
          mapped ? String(actual[mapped[0]]) : "",
          "Only evidenced mapping may fill MES feature " + no,
        );
      }
      assert.equal(await page.locator("#gcMeasureRows .measure-ng").count(), 1);
      assert.equal(await page.locator('[data-result][data-no="10"]').inputValue(), "14.5619");
      assert.equal(Number(await page.locator('[data-count="filled"]').textContent()), mapping.length);
      assert.ok(
        await page.locator("#gcSaveMeasure").isDisabled(),
        "Missing required MES measurements cannot be fabricated to save",
      );
      await page.locator("#gcImportFilter").selectOption("unmatched");
      assert.equal(await page.locator("[data-candidate]").count(), 11 - mapping.length);
      await page.locator("#gcImportFilter").selectOption("");
      await page.screenshot({ path: ".review/m2-" + model + "-matrix.png", fullPage: true });
      assert.equal(await page.evaluate(() => sb.calls.filter(c=>c.name==='ipqc_gc_luu_do').length + sb.uploads.length), 0);
      assert.equal(
        await page.evaluate(() => JSON.stringify([sb.tables.ipqc_btk, sb.tables.ipqc_btk_muc])),
        before,
      );
      assert.deepEqual(errors, []);
      console.log(
        JSON.stringify({
          model,
          revision: data.standard.phien_ban,
          read: 11,
          matched: mapping.length,
          filled: mapping.length,
          unresolved: 11 - mapping.length,
          NG: 1,
          result:
            "PASS supplied M2 PDF, actual staging standards snapshot, precise partial mapping, no guessed geometry or pre-save writes",
        }),
      );
      await context.close();
    }
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
