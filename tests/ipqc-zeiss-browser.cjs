/* Real PDF bytes and real PDF.js in Chrome; isolated MES API fixture, never production. */
const fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict");
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || "playwright");
const { backend } = require("./ipqc-gc-fixture.cjs");
const validation = JSON.parse(fs.readFileSync(".review/zeiss-validation.json", "utf8"));
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const context = await browser.newContext({ viewport: { width: 1560, height: 1000 } }),
      page = await context.newPage(),
      errors = [],
      ocrRequests = [];
    let overwrite = true;
    page.on("dialog", (d) => (overwrite ? d.accept() : d.dismiss()));
    page.on("pageerror", (e) => errors.push(e.message));
    await context.addInitScript({
      content: `window.sb=(${backend.toString()})();window.IS_PROD=false;
   sb.tables.ipqc_btk[0].so_mau=1;sb.tables.ipqc_btk_muc=${JSON.stringify(validation.features)};
   window.MesAuth={getSession:async()=>({user:{id:'u1'}}),getCurrentUserIdentity:async()=>'Inspector'};
   window.MesNav={setTitle(){}};window.sbTaiHet=async make=>await make();`,
    });
    await context.route("**/*", (route) => {
      const u = new URL(route.request().url());
      let file;
      if (/tesseract|tessdata/.test(u.href)) ocrRequests.push(u.href);
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
    async function start() {
      await page.goto("https://mes.test/ipqc-gia-cong.html");
      await page.waitForFunction(() => document.getElementById("gcMachine").options.length === 1);
      await page.locator("#gcMeasureProduct").fill("PART");
      await page.locator("#gcLot").fill("REAL-ZEISS");
      await page.waitForFunction(
        (n) => document.querySelectorAll("#gcMeasureRows [data-result]").length === n,
        validation.features.length,
      );
      await page.locator("#gcResultMode").selectOption("file");
    }
    async function read() {
      await page.locator("#gcResultFile").setInputFiles(validation.file);
      await page.waitForFunction(
        () => document.getElementById("gcImportStatus").textContent.includes("Tự nhận diện ZEISS"),
        null,
        { timeout: 60000 },
      );
      assert.equal(
        await page.locator("#gcImportCandidates [data-candidate]").count(),
        validation.parsed.length,
      );
      assert.equal(await page.locator("#gcResultSheet").inputValue(), "*");
    }
    const values = () =>
      page.locator("#gcMeasureRows [data-result]").evaluateAll((xs) => xs.map((x) => x.value));
    // Readable but unmatched is kept for manual selection, and does not trigger OCR.
    await start();
    await page.evaluate(() =>
      sb.tables.ipqc_btk_muc.forEach((m) => {
        m.ma_dac_tinh = null;
        m.hang_muc = "Unmatched " + m.muc_no;
      }),
    );
    await page.locator("#gcMeasureProduct").fill("");
    await page.locator("#gcMeasureProduct").dispatchEvent("change");
    await page.locator("#gcMeasureProduct").fill("PART");
    await page.locator("#gcMeasureProduct").dispatchEvent("change");
    await page.waitForFunction(() =>
      document.getElementById("gcMeasureRows").textContent.includes("Unmatched"),
    );
    await read();
    assert.match(
      await page.locator("#gcImportStatus").textContent(),
      /0 khớp; 36 đọc được nhưng chưa khớp; 0 lỗi trích xuất/,
    );
    assert.equal(
      await page.locator("[data-import-value]").first().inputValue(),
      validation.parsed[0].samples[0].raw,
    );
    assert.ok((await values()).every((v) => v === ""));
    await page.locator("[data-match]").first().selectOption("1");
    await page.locator("#gcImportSameUnit").check();
    await page.locator("[data-accept]").first().check();
    await page.locator("#gcImportSync").click();
    assert.equal((await values())[0], String(validation.oracle[0]));
    assert.equal(await page.evaluate(() => sb.calls.length), 0);
    assert.equal(ocrRequests.length, 0);
    // Exact-code matches, bulk confirmation and matrix sync use all four pages.
    await start();
    const before = await page.evaluate(() => JSON.stringify([sb.tables.ipqc_btk, sb.tables.ipqc_btk_muc]));
    await read();
    assert.match(
      await page.locator("#gcImportStatus").textContent(),
      /36 khớp; 0 đọc được nhưng chưa khớp; 0 lỗi trích xuất/,
    );
    assert.ok((await values()).every((v) => v === ""));
    assert.equal(await page.evaluate(() => sb.calls.length + sb.uploads.length), 0);
    await page.locator("#gcImportSameUnit").check();
    await page.locator("#gcImportSelectMatched").click();
    await page.locator("#gcImportSync").click();
    assert.deepEqual((await values()).map(Number), validation.oracle);
    const first = page.locator('[data-result][data-no="1"][data-sample="1"]');
    await first.fill(String(validation.oracle[0] + 0.001));
    overwrite = false;
    await page.locator("#gcImportSync").click();
    assert.equal(await first.inputValue(), String(validation.oracle[0] + 0.001));
    overwrite = true;
    await page.locator("#gcImportSync").click();
    assert.equal(await first.inputValue(), String(validation.oracle[0]));
    const expectedNG = validation.features.filter(
      (m, i) =>
        (m.lsl !== null && validation.oracle[i] < m.lsl) || (m.usl !== null && validation.oracle[i] > m.usl),
    ).length;
    assert.equal(await page.locator("#gcMeasureRows .measure-ng").count(), expectedNG);
    assert.equal(await page.evaluate(() => sb.calls.length + sb.uploads.length), 0);
    await page.screenshot({ path: ".review/zeiss-browser-filled.png", fullPage: true });
    await page.locator("#gcResultConfirmed").check();
    await page.locator("#gcSaveMeasure").click();
    await page.waitForFunction(() => sb.tables.ipqc_gc_lan.length === 1);
    const saved = await page.evaluate(() => sb.tables.ipqc_gc_lan[0]);
    assert.deepEqual(
      saved.kq.map((x) => x.gia_tri),
      validation.oracle,
    );
    assert.equal(saved.dat, expectedNG === 0);
    assert.equal(saved.nguon_nhap, "tu_file");
    assert.equal(saved.nhan_dien.gia_tri_da_xac_minh.length, 36);
    assert.equal(
      await page.evaluate(() => JSON.stringify([sb.tables.ipqc_btk, sb.tables.ipqc_btk_muc])),
      before,
    );
    await page.locator('[data-tab="dashboard"]').click();
    await page.waitForFunction(() =>
      document.getElementById("gcDataRows").textContent.includes("REAL-ZEISS"),
    );
    assert.equal(await page.locator("#gcDataRows tbody tr").count(), 36);
    assert.ok((await page.locator("#gcDataRows").textContent()).includes(String(validation.oracle[0])));
    assert.deepEqual(ocrRequests, []);
    assert.deepEqual(errors, []);
    await page.locator('[data-tab="measure"]').click();
    await page
      .locator("#gcResultFile")
      .setInputFiles({ name: "broken.pdf", mimeType: "application/pdf", buffer: Buffer.from("invalid PDF") });
    await page.waitForFunction(() =>
      document.getElementById("gcImportStatus").textContent.includes("Chưa đọc được định dạng"),
    );
    assert.equal(await page.evaluate(() => sb.tables.ipqc_gc_lan.length), 1);
    console.log(
      JSON.stringify({
        result:
          "PASS Chrome real multipage ZEISS upload/read, unmatched/manual map, exact mapping, confirmation/sync, overwrite protection, OK/NG, explicit save/source/dashboard, immutable standards, corrupt PDF, no OCR",
        extracted: 36,
        matched: 36,
        unresolved: 0,
        NG: expectedNG,
      }),
    );
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
