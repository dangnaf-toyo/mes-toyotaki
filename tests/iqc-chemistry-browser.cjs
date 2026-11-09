const fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict");
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || "playwright"),
  XLSX = require("../.review/xlsx.cjs");
const { extendChemistry } = require("./iqc-chemistry-fixture.cjs");
const legacy = fs.readFileSync("tests/iqc-workspace-browser.cjs", "utf8");
const start = legacy.indexOf("function backend()"),
  end = legacy.indexOf("\n(async () => {", start);
assert.ok(start >= 0 && end > start);
const base = legacy.slice(start, end);
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const fixture = await browser.newPage();
    await fixture.setContent(
      '<html><body><h1>Chemical composition wt.%</h1><table style="font:24px Arial;border-spacing:35px 15px"><tr><th>Element</th><th>Result (%)</th><th>Min</th><th>Max</th></tr><tr><td>Si</td><td>10.5</td><td>9.6</td><td>12</td></tr><tr><td>Fe</td><td>0.4</td><td>0</td><td>1.3</td></tr></table></body></html>',
    );
    await fixture.pdf({ path: ".review/iqc-analysis.pdf", format: "A4" });
    await fixture.screenshot({ path: ".review/iqc-analysis.png" });
    await fixture.screenshot({ path: ".review/iqc-analysis.jpg", type: "jpeg" });
    await fixture.close();
    const book = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(
      book,
      XLSX.utils.aoa_to_sheet([
        ["Element", "Result (%)", "Min", "Max"],
        ["Si", 10.1, 9.6, 12],
        ["Fe", 1.4, 0, 1.3],
      ]),
      "Analysis",
    );
    fs.writeFileSync(".review/iqc-analysis.xlsx", XLSX.write(book, { type: "buffer", bookType: "xlsx" }));
    const partialBook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(
      partialBook,
      XLSX.utils.aoa_to_sheet([
        ["Element", "Result (%)"],
        ["Si", 11],
      ]),
      "Partial",
    );
    fs.writeFileSync(".review/iqc-partial.xlsx", XLSX.write(partialBook, { type: "buffer", bookType: "xlsx" }));
    const context = await browser.newContext({ viewport: { width: 1440, height: 960 } }),
      page = await context.newPage(),
      errors = [],
      alerts = [];
    page.on("pageerror", (e) => errors.push(e.message));
    page.on("dialog", (d) => {
      alerts.push(d.message());
      d.accept();
    });
    await context.addInitScript({
      content:
        base +
        `window.sb=backend();window.MesAuth={getSession:async()=>({user:{id:'00000000-0000-0000-0000-000000000001'}}),requireAuth:async()=>({user:{id:'00000000-0000-0000-0000-000000000001'}}),getCurrentUserIdentity:async()=>'ADMIN_Admin'};(${extendChemistry.toString()})();`,
    });
    await context.route("**/*", (route) => {
      const u = new URL(route.request().url());
      let file;
      if (u.pathname.startsWith("/__iqc-files__/"))
        file = path.resolve(
          ".review/iqc-analysis." +
            (u.pathname.endsWith(".pdf") ? "pdf" : u.pathname.endsWith(".png") ? "png" : "xlsx"),
        );
      else if (u.hostname === "mes.test") {
        if (["/shared/supabase-client.js", "/shared/navbar.js"].includes(u.pathname))
          return route.fulfill({ body: "", contentType: "application/javascript" });
        file = path.resolve("." + decodeURIComponent(u.pathname));
      } else if (u.hostname === "cdn.jsdelivr.net") {
        const marker = "/npm/",
          pkg = u.pathname.slice(u.pathname.indexOf(marker) + marker.length),
          cut = pkg.indexOf("/"),
          name = pkg.slice(0, cut).replace(/@[^@]+$/, "");
        if (pkg.startsWith("@tesseract.js-data/")) file = path.resolve(".review/ocr-models/eng.traineddata");
        else if (pkg.startsWith("xlsx@")) file = path.resolve(".review/xlsx.cjs");
        else file = path.resolve(".review/tools/node_modules", name, pkg.slice(cut + 1));
      } else return route.fulfill({ body: "", contentType: "application/javascript" });
      if (!file || !fs.existsSync(file)) return route.fulfill({ status: 404, body: "Missing fixture" });
      const type = file.endsWith(".pdf")
        ? "application/pdf"
        : file.endsWith(".png")
          ? "image/png"
          : file.endsWith(".wasm")
            ? "application/wasm"
            : file.endsWith(".css")
              ? "text/css"
              : file.endsWith(".html")
                ? "text/html"
                : /\.(js|cjs|mjs)$/.test(file)
                  ? "application/javascript"
                  : "application/octet-stream";
      return route.fulfill({ body: fs.readFileSync(file), contentType: type });
    });
    await page.goto("https://mes.test/iqc.html");
    await page.waitForFunction(() => document.querySelector('#qc02-products option[value="[NVL] AL-01"]'));
    const catalog = await page.locator("#qc02-products option").evaluateAll((es) => es.map((e) => e.value));
    assert.equal(catalog.length, new Set(catalog).size);
    assert.ok(catalog.includes("SP01") && catalog.includes("[NVL] SP01"));
    const select = async (code) => {
      await page.locator("#productCode").fill(code);
      await page.locator("#productCode").dispatchEvent("change");
    };
    await select("[NVL] SP01");
    await page.waitForFunction(() => document.querySelector("#iqcMaterialStatus").textContent.includes("NVL khác"));
    assert.equal(await page.locator("#iqc-chemical-entry").isVisible(), false);
    assert.equal(await page.locator("#inspectionType").isVisible(), true);
    await select("[NVL] UNCLASSIFIED");
    await page.waitForFunction(() =>
      document.querySelector("#iqcMaterialStatus").textContent.includes("Chưa phân loại"),
    );
    await page.evaluate(() =>
      sb.rpc("iqc_nvl_luu_phan_loai", { p_ma_nvl: "UNCLASSIFIED", p_nhom: "kem", p_mac: "QC-CONFIG" }),
    );
    await select("[NVL] UNCLASSIFIED");
    await page.waitForFunction(() => !document.querySelector("#iqc-chemical-entry").hidden);
    assert.match(await page.locator("#iqcMaterialStatus").textContent(), /Kẽm/);
    await select("[NVL] AL-01");
    await page.waitForFunction(() => document.querySelectorAll("#iqcChemRows [data-measure]").length === 2);
    assert.equal(await page.locator("#iqc-chemical-entry").isVisible(), true);
    assert.equal(await page.locator("#inspectionType").isVisible(), false);
    await page
      .locator("#iqcChemFile")
      .setInputFiles({ name: "invalid.png", mimeType: "image/png", buffer: Buffer.from("<html>not an image</html>") });
    await page.waitForFunction(() =>
      document.querySelector("#iqcChemStatus").textContent.includes("không đúng định dạng"),
    );
    assert.equal(await page.evaluate(() => sb.uploads.length), 0);
    await page.evaluate(() => {
      const original = IpqcResultReader.read;
      IpqcResultReader.read = () =>
        new Promise((resolve) => {
          window.releaseChemicalRead = () =>
            resolve({
              sheets: [
                {
                  name: "Delayed",
                  rows: [
                    ["Element", "Result (%)"],
                    ["Si", "10.5"],
                    ["Fe", "0.4"],
                  ],
                },
              ],
            });
          window.chemicalReadWaiting = true;
        });
      window.restoreChemicalRead = () => {
        IpqcResultReader.read = original;
      };
    });
    await page.locator("#iqcChemFile").setInputFiles(".review/iqc-analysis.pdf");
    await page.waitForFunction(() => window.chemicalReadWaiting);
    await select("[NVL] ZN-01");
    await page.waitForFunction(() => document.querySelector("#iqcChemRows tr")?.dataset.element === "Al");
    await page.evaluate(() => {
      releaseChemicalRead();
      restoreChemicalRead();
    });
    assert.deepEqual(await page.locator("#iqcChemRows [data-measure]").evaluateAll((es) => es.map((e) => e.value)), [
      "",
      "",
    ]);
    await select("[NVL] AL-01");
    await page.waitForFunction(() => document.querySelector("#iqcChemRows tr")?.dataset.element === "Si");
    console.log(
      "PASS invalid signature rejected before upload and delayed file result discarded after material switch",
    );
    assert.equal(await page.locator(".iqc-report-defects").isVisible(), false);
    assert.equal(await page.locator("#iqcChemRows tr").first().locator("td").first().textContent(), "Si *");
    await page.locator("#lotNo").fill("CHEM-AL-01");
    await page.locator("#iqcChemShift").selectOption("Ca ngày");
    await page.locator("#inspector").fill("QC01_Trần QC");
    const before = await page.evaluate(() => JSON.stringify(sb.tables.ipqc_btk_muc));
    await page.locator("#iqcChemFile").setInputFiles(".review/iqc-analysis.pdf");
    await page.waitForFunction(() => document.querySelector("#iqcChemStatus").textContent.includes("Tự ghép"));
    assert.deepEqual(await page.locator("#iqcChemRows [data-measure]").evaluateAll((es) => es.map((e) => e.value)), [
      "10.5",
      "0.4",
    ]);
    assert.equal(await page.evaluate(() => sb.uploads.length), 0);
    assert.match(await page.locator("#iqcChemConclusion").textContent(), /Chưa kết luận/);
    await page.locator("#iqcChemConfirmed").check();
    assert.match(await page.locator("#iqcChemConclusion").textContent(), /Kết luận: OK/);
    assert.equal(await page.evaluate(() => JSON.stringify(sb.tables.ipqc_btk_muc)), before);
    await page.screenshot({ path: ".review/iqc-chem-al.png", fullPage: true });
    await page.evaluate(() => (sb.failAfterChem = true));
    await page.locator("#saveBtn").click();
    await page.waitForFunction(() =>
      document.querySelector("#iqcChemStatus").textContent.includes("Lost save response"),
    );
    const count = await page.evaluate(() => sb.tables.iqc_lots.length);
    await page.locator("#saveBtn").click();
    await page.waitForFunction(() => document.querySelector("#iqcChemStatus").textContent.includes("Đã lưu báo cáo"));
    assert.equal(await page.evaluate(() => sb.tables.iqc_lots.length), count);
    assert.equal(await page.evaluate(() => sb.uploads.length), 1);
    const alId = await page.evaluate(() => sb.tables.iqc_lots.find((l) => l.lot_no === "CHEM-AL-01").id);
    assert.equal(
      await page.locator("#defectLot option").evaluateAll((es, id) => es.some((e) => e.value === id), String(alId)),
      false,
    );
    console.log(
      "PASS merged BOM/product catalog, typed identity/collision, name-independent routing, PDF Actual values, confirmation, immutable standards and idempotent save/upload",
    );
    await page.reload();
    await page.waitForFunction(() => document.querySelector('#qc02-products option[value="[NVL] AL-01"]'));
    await page.evaluate((id) => editLot(id), alId);
    assert.deepEqual(await page.locator("#iqcChemRows [data-measure]").evaluateAll((es) => es.map((e) => e.value)), [
      "10.5",
      "0.4",
    ]);
    assert.match(await page.locator("#iqcChemFileLink").textContent(), /iqc-analysis.pdf/);
    await page.evaluate((id) => openDetail(id), alId);
    assert.match(await page.locator("#detailBody").textContent(), /Si/);
    assert.match(await page.locator("#detailBody").textContent(), /Kết luận lô: OK/);
    await page.locator("#detailModal").getByRole("button", { name: "Đóng", exact: true }).click();
    for (const extension of ["png", "jpg"]) {
      await page.evaluate(() => {
        if (!window.chemReadWrapped) {
          const read = IpqcResultReader.read;
          IpqcResultReader.read = async (...args) => {
            const r = await read(...args);
            window.chemRead = r;
            window.chemReadCount = (window.chemReadCount || 0) + 1;
            return r;
          };
          window.chemReadWrapped = true;
        }
      });
      const previousRead = await page.evaluate(() => window.chemReadCount || 0);
      await page.locator("#iqcChemFile").setInputFiles(".review/iqc-analysis." + extension);
      await page.waitForFunction(
        (count) =>
          window.chemReadCount > count && document.querySelector("#iqcChemStatus").textContent.includes("Tự ghép"),
        previousRead,
        {
          timeout: 120000,
        },
      );
      for (const [element, value] of [
        ["Si", "10.5"],
        ["Fe", "0.4"],
      ]) {
        const row = page.locator('#iqcChemRows tr[data-element="' + element + '"]');
        if ((await row.locator("[data-measure]").inputValue()) === "") {
          const source = row.locator("[data-source]");
          if (await source.count()) {
            assert.match(await source.textContent(), /OCR cần kiểm tra/);
            assert.ok((await source.locator('option[value="0"]').textContent()).includes(": " + value + " %"));
            await source.selectOption("0");
          } else {
            assert.match(await row.textContent(), /Chưa nhận diện \/ nhập tay/);
            await row.locator("[data-measure]").fill(value);
            console.log(
              "PASS " + extension + " " + element + ": uncertain OCR left blank, explicit QC manual correction",
            );
          }
          assert.equal(await page.locator("#iqcChemConfirmed").isChecked(), false);
        }
        assert.equal(await row.locator("[data-measure]").inputValue(), value);
      }
    }
    console.log(
      "PASS actual PNG/JPEG OCR: element identities and actual concentrations, explicit units, no specification bounds substituted",
    );
    await page.locator("#iqcChemFile").setInputFiles(".review/iqc-partial.xlsx");
    await page.waitForFunction(() => document.querySelector('#iqcChemRows tr[data-element="Si"] input').value === "11");
    assert.equal(await page.locator('#iqcChemRows tr[data-element="Fe"] input').inputValue(), "");
    await page.locator("#iqcChemConfirmed").check();
    assert.match(await page.locator("#iqcChemConclusion").textContent(), /Chưa kết luận/);
    console.log(
      "PASS replacing a report clears unmatched previous-file values; missing required element stays pending",
    );
    await page.locator("#iqcChemFile").setInputFiles(".review/iqc-analysis.xlsx");
    await page.waitForFunction(
      () => document.querySelector('#iqcChemRows tr[data-element="Fe"] input').value === "1.4",
    );
    await page.locator("#iqcChemConfirmed").check();
    assert.match(await page.locator("#iqcChemConclusion").textContent(), /Kết luận: NG/);
    await page.locator("#saveBtn").click();
    await page.waitForFunction(() => document.querySelector("#iqcChemStatus").textContent.includes("Đã lưu báo cáo"));
    assert.equal(await page.evaluate((id) => sb.tables.iqc_lots.find((l) => l.id === id).ng_qty, alId), 0);
    assert.equal(await page.evaluate(() => sb.tables.iqc_defects.length), 0);
    console.log(
      "PASS reopen and PDF attachment persistence, Excel results, per-element NG and lot NG kept separate from PCS/visual defects",
    );
    await select("[NVL] ZN-01");
    await page.waitForFunction(() => document.querySelector("#iqcChemRows tr")?.dataset.element === "Al");
    assert.deepEqual(await page.locator("#iqcChemRows tr").evaluateAll((es) => es.map((e) => e.dataset.element)), [
      "Al",
      "Mg",
    ]);
    await page.locator("#lotNo").fill("CHEM-ZN");
    await page.locator("#iqcChemRows [data-measure]").first().fill("4");
    await page.locator("#iqcChemConfirmed").check();
    assert.match(await page.locator("#iqcChemConclusion").textContent(), /Chưa kết luận/);
    await page.locator("#iqcChemRows [data-measure]").nth(1).fill("0.04");
    await page.locator("#iqcChemConfirmed").check();
    assert.match(await page.locator("#iqcChemConclusion").textContent(), /Kết luận: OK/);
    await select("[NVL] AL-NO-TC");
    await page.waitForFunction(() =>
      document.querySelector("#iqcChemRows")?.textContent.includes("Chưa có tiêu chuẩn"),
    );
    await page.locator("#iqcChemConfirmed").check();
    assert.match(await page.locator("#iqcChemConclusion").textContent(), /Chưa kết luận/);
    await page.locator("#lotNo").fill("CHEM-NO-TC");
    await page.locator("#iqcChemShift").selectOption("Ca 1");
    await page.locator("#inspector").fill("QC01_Trần QC");
    await page.locator("#saveBtn").click();
    await page.waitForFunction(() => document.querySelector("#iqcChemStatus").textContent.includes("Đã lưu báo cáo"));
    await page.evaluate(() => showPage("stats"));
    await page.locator("#iqcDashMethod").selectOption("hoa_hoc");
    await page.locator("#iqcDashMaterialGroup").selectOption("nhom");
    assert.match(await page.locator("#iqcChemicalRates").textContent(), /1 NG/);
    await page.locator("#iqcDashChemicalResult").selectOption("NG");
    assert.equal(await page.locator("#iqcDash-total").textContent(), "1");
    await page.locator("#iqcDashChemicalResult").selectOption("pending");
    assert.equal(await page.locator("#iqcDash-total").textContent(), "1");
    const pendingId = await page.evaluate(() => sb.saved.lots.find((x) => x.lot_no === "CHEM-NO-TC").id);
    await page.locator("#iqcDashFrom").fill("2099-01-01");
    await page.locator("#iqcDashFrom").dispatchEvent("change");
    assert.equal(await page.locator("#iqcDash-total").textContent(), "0");
    await page.locator("#iqcDashFrom").fill("");
    await page.locator("#iqcDashFrom").dispatchEvent("change");
    const downloadPromise = page.waitForEvent("download");
    await page.locator("#iqcDashboard").getByRole("button", { name: "Xuất báo cáo CSV" }).click();
    const download = await downloadPromise;
    const stream = await download.createReadStream();
    const chunks = [];
    for await (const chunk of stream) chunks.push(chunk);
    const exported = Buffer.concat(chunks).toString("utf8");
    assert.match(exported, /CHEM-NO-TC/);
    assert.doesNotMatch(exported, /CHEM-AL/);
    await page.screenshot({ path: ".review/iqc-chem-dashboard.png", fullPage: true });
    console.log(
      "PASS Zinc gets its own elements/limits, missing required values or standards never OK, dashboard method/material/result filters and lot counts",
    );
    await page.evaluate(() => {
      sb.saved.headers.push({
        ...sb.saved.headers[0],
        id: 30,
        ma_sp: "AL-NO-TC",
        ma_nvl: "AL-NO-TC",
        mac_vat_lieu: "OTHER",
      });
      sb.saved.features.push({ ...sb.saved.features[0], id_btk: 30 });
    });
    await page.evaluate((id) => editLot(id), pendingId);
    assert.equal(await page.locator("#iqcChemRows [data-measure]").count(), 0);
    await page.locator("#iqcChemReloadStandard").click();
    await page.waitForFunction(() => document.querySelector("#iqcChemRows tr")?.dataset.element === "Si");
    assert.equal(await page.locator("#iqcChemConfirmed").isChecked(), false);
    await page.locator("#iqcChemRows [data-measure]").fill("10.5");
    await page.locator("#iqcChemConfirmed").check();
    await page.locator("#saveBtn").click();
    await page.waitForFunction(() => document.querySelector("#iqcChemStatus").textContent.includes("Đã lưu báo cáo"));
    assert.equal(await page.evaluate((id) => sb.saved.lots.find((x) => x.id === id).result, pendingId), "OK");
    assert.equal(await page.evaluate(() => sb.saved.lots.filter((x) => x.lot_no === "CHEM-NO-TC").length), 1);
    console.log(
      "PASS filtered CSV/date range and pending report adopts newly approved standard only after explicit reload/reconfirmation",
    );
    await page.setViewportSize({ width: 390, height: 844 });
    await page.evaluate((id) => editLot(id), alId);
    await page.screenshot({ path: ".review/iqc-chem-mobile.png", fullPage: true });
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
    await page.setViewportSize({ width: 1440, height: 960 });
    await page.goto("https://mes.test/qc-manager.html?tab=tieuchuan&cd=iqc_hoa_hoc");
    await page.waitForFunction(() => document.getElementById("iqc-chemical-standard")?.hidden === false);
    await page.locator("#iqcTcMaterial").selectOption("SP01");
    await page.locator("#iqcTcGroup").selectOption("nhom");
    await page.locator("#iqcTcGrade").fill("QC-GRADE");
    await page.locator("#iqcTcClassification").click();
    await page.waitForFunction(() => document.getElementById("iqcTcMessage").textContent.includes("Đã lưu phân loại"));
    await page.locator("#iqcTcNew").click();
    await page.locator("#iqcTcRevision").fill("A");
    await page.locator("#iqcTcChange").fill("Test approval workflow");
    assert.equal(await page.locator("#iqcTcRows tr").count(), 0);
    await page.locator("#iqcTcAdd").click();
    await page.locator("#iqcTcRows [data-k=element]").fill("Si");
    await page.locator("#iqcTcRows [data-k=min]").fill("9.6");
    await page.locator("#iqcTcRows [data-k=max]").fill("12");
    await page.locator("#iqcTcSend").click();
    await page.waitForFunction(() => document.querySelector('#iqcTcApproval [data-duyet="kiem_tra"]'));
    await page.locator('#iqcTcApproval [data-duyet="kiem_tra"]').click();
    await page.waitForFunction(() => document.querySelector('#iqcTcApproval [data-duyet="phe_duyet"]'));
    await page.locator('#iqcTcApproval [data-duyet="phe_duyet"]').click();
    await page.waitForFunction(() => document.querySelector("#iqcTcApproval").textContent.includes("Đã phê duyệt"));
    assert.equal(await page.locator("#iqcTcRows [data-k=min]").isDisabled(), true);
    await page.screenshot({ path: ".review/iqc-chem-standards.png", fullPage: true });
    await page.locator("#tc-cd-bar [data-cd=duc]").click();
    assert.equal(await page.locator("#iqc-chemical-standard").isVisible(), false);
    assert.equal(await page.locator("#btk-root").isVisible(), true);
    assert.deepEqual(errors, []);
    console.log(
      "PASS mobile layout, existing standards category, explicit classification/limits, unchanged three-step approvals, approved lock and return to casting standards; no browser errors",
    );
    await context.close();
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
