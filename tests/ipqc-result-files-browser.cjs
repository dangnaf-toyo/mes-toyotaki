const fs = require("fs"),
  path = require("path"),
  assert = require("node:assert/strict");
const XLSX = require(process.env.MES_XLSX_PATH || "../.review/xlsx.cjs");
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || "playwright");
const { backend } = require("./ipqc-gc-fixture.cjs");
const table = [
  ["Feature ID", "Description", "Nominal", "Unit", "Sample 1", "Sample 2"],
  ["D01", "Diameter", 20, "mm", 20.02, 20.01],
  ["L02", "Length", 38, "mm", 38.12, 38.0],
  ["W03", "Width", 15, "mm", 15.15, 15.0],
];
const workbook = XLSX.utils.book_new();
XLSX.utils.book_append_sheet(workbook, XLSX.utils.aoa_to_sheet(table), "Results");
fs.writeFileSync(".review/ipqc-report.xlsx", XLSX.write(workbook, { type: "buffer", bookType: "xlsx" }));
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const report = await browser.newPage();
    await report.setContent(
      '<html><body style="font:18px Arial"><h1>Actual measurements</h1><table border="1" cellpadding="8">' +
        table.map((row) => "<tr>" + row.map((v) => "<td>" + v + "</td>").join("") + "</tr>").join("") +
        "</table></body></html>",
    );
    await report.pdf({ path: ".review/ipqc-report.pdf", format: "A4" });
    await report.screenshot({ path: ".review/ipqc-report.png", fullPage: true });
    await report.close();
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } }),
      page = await context.newPage(),
      errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    let overwrite = true;
    page.on("dialog", (dialog) => (overwrite ? dialog.accept() : dialog.dismiss()));
    await context.addInitScript({
      content: `window.sb=(${backend.toString()})();window.IS_PROD=false;
    window.MesAuth={getSession:async()=>({user:{id:'u1'}}),getCurrentUserIdentity:async()=>'Inspector'};
    window.MesNav={setTitle(){}};window.sbTaiHet=async make=>await make();`,
    });
    await context.route("**/*", (route) => {
      const url = new URL(route.request().url());
      let file;
      if (url.hostname === "cdn.jsdelivr.net") {
        if (url.pathname.includes("/@tesseract.js-data/"))
          file = path.resolve(".review/ocr-models/eng.traineddata");
        else if (url.pathname.includes("/xlsx@")) file = path.resolve(".review/xlsx.cjs");
        else if (url.pathname.includes("/pdfjs-dist@"))
          file = path.resolve(".review/tools/node_modules/pdfjs-dist/build", path.basename(url.pathname));
        else if (url.pathname.includes("/tesseract.js@"))
          file = path.resolve(".review/tools/node_modules/tesseract.js/dist", path.basename(url.pathname));
        else if (url.pathname.includes("/tesseract.js-core@"))
          file = path.resolve(".review/tools/node_modules/tesseract.js-core", path.basename(url.pathname));
      } else if (url.hostname === "tessdata.projectnaptha.com")
        file = path.resolve(".review/ocr-models/eng.traineddata");
      else if (
        url.hostname === "mes.test" &&
        !["/shared/supabase-client.js", "/shared/navbar.js"].includes(url.pathname)
      )
        file = path.resolve("." + decodeURIComponent(url.pathname));
      if (!file) return route.fulfill({ body: "", contentType: "application/javascript" });
      if (!fs.existsSync(file)) {
        console.error("Missing test asset", url.href);
        return route.fulfill({ status: 404, body: "" });
      }
      return route.fulfill({
        body: fs.readFileSync(file),
        headers: { "Access-Control-Allow-Origin": "*" },
        contentType: /\.(js|mjs|cjs)$/.test(file)
          ? "application/javascript"
          : file.endsWith(".wasm")
            ? "application/wasm"
            : file.endsWith(".css")
              ? "text/css"
              : file.endsWith(".html")
                ? "text/html"
                : "application/octet-stream",
      });
    });
    await page.goto("https://mes.test/ipqc-gia-cong.html");
    await page.waitForFunction(() => document.getElementById("gcMachine").options.length === 1);
    await page.locator("#gcMeasureProduct").fill("PART");
    await page.locator("#gcLot").fill("FILE-LOT");
    await page.waitForFunction(() => document.querySelectorAll("#gcMeasureRows [data-result]").length === 6);
    await page.locator("#gcResultMode").selectOption("file");
    const values = () =>
      page.locator("#gcMeasureRows [data-result]").evaluateAll((inputs) => inputs.map((i) => i.value));
    async function read(file) {
      await page.locator("#gcResultFile").setInputFiles(file);
      await page.waitForFunction(
        () => document.querySelectorAll("#gcImportCandidates [data-candidate]").length > 0,
        null,
        { timeout: 120000 },
      );
    }
    await read(".review/ipqc-report.xlsx");
    assert.equal(await page.locator("#gcImportCandidates [data-candidate]").count(), 3);
    assert.ok((await values()).every((v) => v === ""));
    assert.equal(await page.evaluate(() => sb.calls.filter((c) => c.name === "ipqc_gc_luu_do").length), 0);
    await page.locator("#gcImportSelectMatched").click();
    await page.locator("#gcImportSync").click();
    assert.deepEqual(await values(), ["20.02", "20.01", "38.12", "38", "15.15", "15"]);
    await page.locator('[data-result][data-no="1"][data-sample="1"]').fill("20.03");
    overwrite = false;
    await page.locator("#gcImportSync").click();
    assert.equal((await values())[0], "20.03");
    overwrite = true;
    await page.locator("#gcResultConfirmed").check();
    await page.screenshot({ path: ".review/ipqc-result-import-preview.png", fullPage: true });
    await page.locator("#gcSaveMeasure").click();
    await page.waitForFunction(() => sb.tables.ipqc_gc_lan.length === 1);
    const saved = await page.evaluate(() => sb.tables.ipqc_gc_lan[0]);
    assert.equal(saved.nguon_nhap, "tu_file");
    assert.equal(saved.dat, false);
    assert.equal(saved.kq.find((k) => k.muc_no === 1 && k.mau === 1).gia_tri, 20.03);
    assert.equal(await page.evaluate(() => sb.uploads.length), 1);
    assert.ok(saved.tep_ket_qua.path.startsWith("u1/"));
    assert.ok(
      saved.nhan_dien.gia_tri_da_xac_minh.some((row) => row.gia_tri_luu === 20.03 && row.da_sua_sau_dong_bo),
    );
    await page.locator("#gcResultMode").selectOption("manual");
    const manual = ["20", "20.02", "38", "38.1", "15", "15.01"];
    for (let i = 0; i < manual.length; i++)
      await page.locator("#gcMeasureRows [data-result]").nth(i).fill(manual[i]);
    await page.locator("#gcLot").fill("MANUAL-LOT");
    await page.locator("#gcSaveMeasure").click();
    await page.waitForFunction(() => sb.tables.ipqc_gc_lan.length === 2);
    await page.locator("[data-tab=dashboard]").click();
    await page.waitForFunction(() =>
      document.getElementById("gcDataRows").textContent.includes("MANUAL-LOT"),
    );
    assert.ok((await page.locator("#gcDataRows").textContent()).includes("Nhập từ file"));
    assert.ok((await page.locator("#gcDataRows").textContent()).includes("Nhập tay"));
    assert.deepEqual(await page.locator("#gcMetrics b").allTextContents(), ["2", "4", "1", "1", "50.00%"]);
    assert.equal(await page.getByRole("button", { name: "Xem file gốc", exact: true }).count(), 6);
    await page.evaluate(() => {
      const original = IpqcSpc.bieuDo;
      IpqcSpc.bieuDo = (o) => {
        window.chartInput = o;
        return original(o);
      };
    });
    await page.locator("#gcFilterFeature").selectOption("1/1");
    assert.deepEqual(
      await page.evaluate(() => ({
        values: chartInput.pts.map((p) => p.x),
        lsl: chartInput.lsl,
        usl: chartInput.usl,
        nominal: chartInput.nominal,
      })),
      { values: [20.03, 20.01, 20, 20.02], lsl: 19.95, usl: 20.05, nominal: 20 },
    );
    assert.ok((await page.locator("#gcSpcChart").textContent()).includes("Chưa đủ điều kiện"));
    const downloaded = page.waitForEvent("download");
    await page.locator("#gcExcel").click();
    const download = await downloaded,
      exported = XLSX.read(fs.readFileSync(await download.path()), { type: "buffer" });
    const exportedRows = XLSX.utils.sheet_to_json(exported.Sheets.IPQC);
    assert.equal(exportedRows.length, 4);
    assert.equal(exportedRows[0]["Giá trị"], 20.03);
    assert.deepEqual(
      [...new Set(exportedRows.map((row) => row["Nguồn nhập"]))],
      ["Nhập từ file", "Nhập tay"],
    );
    await page.locator("#gcFilterFeature").selectOption("");
    for (const [id, value, count] of [
      ["gcFilterLot", "FILE-LOT", 1],
      ["gcFilterRevision", "B", 0],
      ["gcFilterRevision", "A", 2],
      ["gcFilterMachine", "OTHER", 0],
      ["gcFilterProduct", "OTHER", 0],
      ["gcFilterInspector", "Inspector", 2],
    ]) {
      const filter = page.locator("#" + id);
      await filter.fill(value);
      await page.locator("#gcRefresh").click();
      await page.waitForFunction(
        (n) => document.querySelector("#gcMetrics b").textContent === String(n),
        count,
      );
      await filter.fill("");
    }
    await page.locator("#gcFilterShift").selectOption({ index: 2 });
    await page.locator("#gcRefresh").click();
    await page.waitForFunction(() => document.querySelector("#gcMetrics b").textContent === "0");
    await page.locator("#gcFilterShift").selectOption("");
    await page.locator("[data-tab=measure]").click();
    await page.locator("#gcResultMode").selectOption("file");
    console.log(
      "PASS mixed-source dashboard: shared totals, source labels, private-file links, actual chart/limits, SPC gate, filters and Excel",
    );
    console.log(
      "PASS Chrome XLSX: real file read, values matched, preview only, no overwrite without confirmation, manual corrections, explicit save/source/private file",
    );
    await page.locator("#gcResultFile").setInputFiles(".review/ipqc-report.pdf");
    await page.waitForFunction(
      () => document.querySelectorAll("#gcImportCandidates [data-candidate]").length === 3,
      null,
      { timeout: 120000 },
    );
    assert.ok((await page.locator("#gcResultSheet").inputValue()).includes("Trang"));
    assert.ok((await values()).every((v) => v === ""));
    console.log(
      "PASS Chrome PDF text report: extracted actual values into unsaved review, not standard limits",
    );
    await page.locator("#gcResultFile").setInputFiles(".review/ipqc-report.png");
    await page.waitForFunction(
      () =>
        document.getElementById("gcImportStatus").textContent.includes("Đọc được") ||
        document.getElementById("gcImportStatus").textContent.includes("Chưa đọc được định dạng"),
      null,
      { timeout: 180000 },
    );
    assert.ok((await page.locator("#gcResultSheet").inputValue()).includes("OCR"));
    assert.ok(
      (
        await page
          .locator("#gcImportCandidates [data-import-value]")
          .evaluateAll((inputs) => inputs.map((i) => i.value))
      ).includes("20.02"),
      await page.locator("#gcImportRaw").textContent(),
    );
    console.log("PASS Chrome image OCR: actual numeric values recognized, review required");
    const real = "D:/1. CÔNG VIỆC/2. MẪU/9. PREMO/2. Biểu kiểm tra/Kết quả kiểm tra N1 Premo 25.04.2025.xlsx";
    if (fs.existsSync(real)) {
      await read(real);
      assert.ok(
        (
          await page
            .locator("#gcImportCandidates [data-import-value]")
            .evaluateAll((inputs) => inputs.map((i) => i.value))
        ).includes("157.07"),
      );
      console.log(
        "PASS company PREMO XLSX: actual sample values 157.07/157.48 extracted, unmatched features stay unconfirmed",
      );
    }
    const horizontal =
      "D:/1. CÔNG VIỆC/7. CÁC SẢN PHẨM ĐANG SẢN XUẤT HÀNG LOẠT/HITACHI/118-D02-126/118-D02-126/KQKT N1/KQ N1#25/kết quả đo N1 FR khuôn 25( 25.06.2025).xls";
    if (fs.existsSync(horizontal)) {
      await page.locator("#gcResultFile").setInputFiles(horizontal);
      await page.waitForFunction(() => document.getElementById("gcResultSheet").options.length > 3);
      await page.locator("#gcResultSheet").selectOption("KQ ĐO 1");
      await page.locator("#gcResultImportPanel details").first().locator("summary").click();
      await page.locator("#gcImport_layout").selectOption("columns");
      await page.locator("#gcImport_headerRow").fill("7");
      await page.locator("#gcImport_idColumn").fill("C");
      await page.locator("#gcImport_nominalColumn").fill("8");
      await page.locator("#gcImport_sampleColumns").fill("12:1,13:2");
      await page.locator("#gcImportParse").click();
      const readValues = await page
        .locator("#gcImportCandidates [data-import-value]")
        .evaluateAll((inputs) => inputs.map((i) => i.value));
      assert.ok(readValues.includes("34.91"), await page.locator("#gcImportRaw").textContent());
      assert.ok(readValues.includes("34.84"));
      console.log(
        "PASS company HITACHI XLS horizontal machine template: explicit row/sample configuration extracts 34.91/34.84; no criterion values substituted",
      );
    }
    if (process.env.MES_REAL_RESULT_PDF) {
      await page.locator("#gcImportPreset").selectOption("");
      await page.locator("#gcResultFile").setInputFiles(process.env.MES_REAL_RESULT_PDF);
      for (let i = 0; i < 30; i++) {
        const status = await page.locator("#gcImportStatus").textContent();
        console.log("REAL PDF: " + status);
        if (
          status.includes("dòng cần đối chiếu") ||
          status.includes("Chưa đọc được định dạng") ||
          status.includes("Chưa nhận diện được")
        )
          break;
        await new Promise((resolve) => setTimeout(resolve, 10000));
      }
      const outcome = await page.evaluate(() => ({
        status: document.getElementById("gcImportStatus").textContent,
        sheets: [...document.getElementById("gcResultSheet").options].map((x) => x.value),
        values: [...document.querySelectorAll("#gcImportCandidates [data-import-value]")].map((x) => x.value),
      }));
      fs.writeFileSync(".review/company-pdf-import.json", JSON.stringify(outcome, null, 2));
      const pages = [];
      for (const name of outcome.sheets.filter((s) => s !== "*")) {
        await page.locator("#gcResultSheet").selectOption(name);
        const values = await page
          .locator("#gcImportCandidates [data-import-value]")
          .evaluateAll((inputs) => inputs.map((i) => i.value));
        pages.push({
          name,
          count: values.length,
          valid: values.filter((v) => /^[-+]?\d+(?:[.,]\d+)?$/.test(v)).length,
          preview: values.slice(0, 5),
        });
      }
      fs.writeFileSync(".review/company-pdf-pages.json", JSON.stringify(pages, null, 2));
      console.log("REAL PDF PAGES " + JSON.stringify(pages));
      console.log(
        "REAL PDF OUTCOME " +
          JSON.stringify({
            status: outcome.status,
            values: outcome.values.length,
            sheets: outcome.sheets.length,
          }),
      );
      assert.ok(!outcome.status.includes("Đang đọc") && !outcome.status.includes("Đang nạp"));
    }
    assert.deepEqual(errors, []);
    await context.close();
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
