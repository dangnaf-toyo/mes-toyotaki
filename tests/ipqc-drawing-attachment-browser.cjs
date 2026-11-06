/* Actual PDF/image rendering and persisted file bytes, isolated backend contract fixture. */
const fs = require("fs"),
  path = require("path"),
  assert = require("node:assert/strict");
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || "playwright");
const { backend } = require("./ipqc-gc-fixture.cjs");
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const report = await browser.newPage();
    await report.setContent(
      '<html><body><section style="page-break-after:always"><h1>DRAWING 1</h1><p>Diameter 20 ±0.05 mm</p></section><section><h1>DRAWING 2</h1><p>Length 38 ±0.2 mm</p></section></body></html>',
    );
    await report.pdf({ path: ".review/reference-drawing.pdf", format: "A4" });
    await report.setContent(
      '<html><body style="font:24px Arial"><h1>REFERENCE DRAWING</h1><p>Diameter 20 ±0.05 mm</p><p>Length 38 ±0.2 mm</p></body></html>',
    );
    await report.screenshot({ path: ".review/reference-drawing.png" });
    await report.screenshot({ path: ".review/reference-drawing.jpg", type: "jpeg" });
    fs.copyFileSync(".review/reference-drawing.jpg", ".review/reference-drawing.jpeg");
    await report.close();
    const objects = new Map([
      ["u1/old.png", { bytes: fs.readFileSync(".review/reference-drawing.png"), type: "image/png" }],
    ]);
    const context = await browser.newContext({ viewport: { width: 1560, height: 1000 } }),
      page = await context.newPage(),
      errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    page.on("dialog", (dialog) => dialog.accept());
    await context.exposeBinding("persistDrawing", (_, key, base64, type) => {
      objects.set(key, { bytes: Buffer.from(base64, "base64"), type });
    });
    await context.addInitScript({
      content: `window.sb=(${backend.toString()})();window.IS_PROD=false;
   window.MesAuth={getSession:async()=>({user:{id:'u1'}}),getCurrentUserIdentity:async()=>'Inspector'};
   window.MesNav={setTitle(){}};window.sbTaiHet=async make=>await make();
   window.IpqcDrawingReader={read(){throw Error('Drawing extraction must never run');}};
   sb.tables.ipqc_btk[0].tai_lieu_goc={path:'u1/old.png',name:'old.png'};
   sb.tables.ipqc_btk[0].ban_ve_vi_tri=[{no:1,x:20,y:30}];
   sb.storage.from=bucket=>({
    async upload(key,file,options){
     const data=await new Promise(resolve=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result.split(',')[1]);reader.readAsDataURL(file);});
     await persistDrawing(key,data,options.contentType);sb.uploads.push({bucket,path:key,size:file.size,options});return {data:{path:key}};
    },async createSignedUrl(key){return {data:{signedUrl:'https://storage.test/'+encodeURIComponent(key)}};}
   });
   const original=sb.rpc.bind(sb);sb.rpc=async(name,args)=>{
    if(name!=='ipqc_gc_luu_tieu_chuan')return original(name,args);
    sb.calls.push({name,args});const p=args.p_data;
    const saved={...sb.tables.ipqc_btk[0],...p,id:2,trang_thai:'cho_kiem_tra',dang_dung:false};
    const i=sb.tables.ipqc_btk.findIndex(b=>b.id===2);if(i<0)sb.tables.ipqc_btk.push(saved);else sb.tables.ipqc_btk[i]=saved;
    sb.tables.ipqc_btk_muc=sb.tables.ipqc_btk_muc.filter(m=>m.id_btk!==2).concat(p.muc.map(m=>({...m,id_btk:2})));
    return {data:{ok:true,id:2,phien_ban:p.phien_ban}};
   };`,
    });
    await context.route("**/*", async (route) => {
      const u = new URL(route.request().url());
      let file;
      if (u.hostname === "storage.test") {
        const object = objects.get(decodeURIComponent(u.pathname.slice(1)));
        return route.fulfill({
          status: object ? 200 : 404,
          body: object?.bytes || "",
          contentType: object?.type || "text/plain",
          headers: { "Access-Control-Allow-Origin": "*" },
        });
      }
      if (u.hostname === "cdn.jsdelivr.net" && u.pathname.includes("/pdfjs-dist@"))
        file = path.resolve(".review/tools/node_modules/pdfjs-dist/build", path.basename(u.pathname));
      else if (
        u.hostname === "mes.test" &&
        !["/shared/supabase-client.js", "/shared/navbar.js"].includes(u.pathname)
      )
        file = path.resolve("." + decodeURIComponent(u.pathname));
      if (!file) return route.fulfill({ body: "", contentType: "application/javascript" });
      if (!fs.existsSync(file)) return route.fulfill({ status: 404, body: "" });
      return route.fulfill({
        body: fs.readFileSync(file),
        headers: { "Access-Control-Allow-Origin": "*" },
        contentType: /\.(js|mjs)$/.test(file)
          ? "application/javascript"
          : file.endsWith(".css")
            ? "text/css"
            : "text/html",
      });
    });
    await page.goto("https://mes.test/qc-manager.html?tab=tieuchuan&cd=gia_cong&type=btk&ma=PART&version=1");
    const root = page.locator("#btk-root"),
      viewer = root.locator("[data-drawing-viewer]");
    await page.waitForFunction(() => document.querySelector("[data-drawing-viewer] img")?.naturalWidth > 0);
    assert.equal(await root.locator("[data-up]").count(), 0);
    const original = await page.evaluate(() =>
      JSON.stringify({ b: sb.tables.ipqc_btk[0], m: sb.tables.ipqc_btk_muc.filter((m) => m.id_btk === 1) }),
    );
    const originalBytes = objects.get("u1/old.png").bytes;
    await root.locator("[data-sua]").click();
    await root.locator("[data-f=phien_ban]").fill("B");
    await root.locator("[data-f=noi_dung_sua_doi]").fill("Attach reference drawing");
    for (const checkbox of await root.locator("[data-c=da_xac_nhan]").all()) await checkbox.check();
    const tableState = () =>
      root
        .locator("tr[data-r]")
        .evaluateAll((rows) =>
          rows.map((row) =>
            [...row.querySelectorAll("[data-c]")].map((input) => [
              input.dataset.c,
              input.value,
              input.checked,
            ]),
          ),
        );
    const tableBefore = await tableState();
    const fieldsBefore = await root
      .locator("[data-f]")
      .evaluateAll((inputs) => inputs.map((input) => [input.dataset.f, input.value]));
    async function save() {
      const count = await page.evaluate(
        () => sb.calls.filter((c) => c.name === "ipqc_gc_luu_tieu_chuan").length,
      );
      await root.locator("[data-luu]").click();
      await page.waitForFunction(
        (n) => sb.calls.filter((c) => c.name === "ipqc_gc_luu_tieu_chuan").length === n + 1,
        count,
      );
      await page.waitForFunction(
        () =>
          document.querySelector("#btk-root [data-f=phien_ban]")?.disabled &&
          document.querySelector("#btk-root [data-f=phien_ban]")?.value === "B",
      );
    }
    await root.locator("[data-up]").setInputFiles(".review/reference-drawing.pdf");
    await page.waitForFunction(() =>
      document.querySelector("[data-drawing-viewer] [role=status]")?.textContent.includes("Trang 1/2"),
    );
    assert.deepEqual(await tableState(), tableBefore);
    assert.deepEqual(
      await root
        .locator("[data-f]")
        .evaluateAll((inputs) => inputs.map((input) => [input.dataset.f, input.value])),
      fieldsBefore,
    );
    assert.equal(await page.evaluate(() => sb.uploads.length), 0);
    const first = await viewer.locator("canvas").evaluate((canvas) => canvas.toDataURL());
    await viewer.getByRole("button", { name: "Trang sau", exact: true }).click();
    await page.waitForFunction(() =>
      document.querySelector("[data-drawing-viewer] [role=status]").textContent.includes("Trang 2/2"),
    );
    assert.notEqual(await viewer.locator("canvas").evaluate((canvas) => canvas.toDataURL()), first);
    const width = await viewer.locator("canvas").evaluate((canvas) => canvas.style.width);
    await viewer.getByRole("button", { name: "Phóng to", exact: true }).click();
    await page.waitForFunction(
      (w) => document.querySelector("[data-drawing-viewer] canvas").style.width !== w,
      width,
    );
    await viewer.getByRole("button", { name: "Vừa khung", exact: true }).click();
    await page.waitForFunction(
      (w) => document.querySelector("[data-drawing-viewer] canvas").style.width === w,
      width,
    );
    await save();
    const saved = await page.evaluate(() => sb.tables.ipqc_btk.find((b) => b.id === 2));
    assert.equal(saved.ma_sp, "PART");
    assert.equal(saved.ma_ban_ve, "DWG");
    assert.equal(saved.phien_ban, "B");
    assert.ok(saved.tai_lieu_goc.path.startsWith("u1/"));
    assert.notEqual(saved.tai_lieu_goc.path, "u1/old.png");
    assert.equal(
      objects.get(saved.tai_lieu_goc.path).bytes.equals(fs.readFileSync(".review/reference-drawing.pdf")),
      true,
    );
    await page.waitForFunction(() =>
      document.querySelector("[data-drawing-viewer] [role=status]")?.textContent.includes("Trang 1/2"),
    );
    await root.locator("[data-pb]").selectOption("1");
    await page.waitForFunction(() => document.querySelector("[data-drawing-viewer] img")?.naturalWidth > 0);
    assert.equal(await root.locator("[data-up]").count(), 0);
    await root.locator("[data-pb]").selectOption("2");
    await page.waitForFunction(() =>
      document.querySelector("[data-drawing-viewer] [role=status]")?.textContent.includes("Trang 1/2"),
    );
    await page.screenshot({ path: ".review/ipqc-reference-pdf.png", fullPage: true });
    for (const ext of ["png", "jpg", "jpeg"]) {
      await root.locator("[data-sua]").click();
      for (const checkbox of await root.locator("[data-c=da_xac_nhan]").all()) await checkbox.check();
      const before = await tableState();
      await root.locator("[data-up]").setInputFiles(".review/reference-drawing." + ext);
      await page.waitForFunction(() => document.querySelector("[data-drawing-viewer] img")?.naturalWidth > 0);
      assert.deepEqual(await tableState(), before);
      const beforeWidth = await viewer.locator("img").evaluate((img) => img.style.width);
      await viewer.getByRole("button", { name: "Phóng to", exact: true }).click();
      assert.notEqual(await viewer.locator("img").evaluate((img) => img.style.width), beforeWidth);
      await save();
      await page.waitForFunction(() => document.querySelector("[data-drawing-viewer] img")?.naturalWidth > 0);
      const saved = await page.evaluate(() => sb.tables.ipqc_btk.find((b) => b.id === 2));
      assert.ok(saved.tai_lieu_goc.name.endsWith("." + ext));
      assert.equal(
        objects
          .get(saved.tai_lieu_goc.path)
          .bytes.equals(fs.readFileSync(".review/reference-drawing." + ext)),
        true,
      );
    }
    assert.equal(
      original,
      await page.evaluate(() =>
        JSON.stringify({ b: sb.tables.ipqc_btk[0], m: sb.tables.ipqc_btk_muc.filter((m) => m.id_btk === 1) }),
      ),
    );
    assert.equal(objects.get("u1/old.png").bytes.equals(originalBytes), true);
    assert.equal(
      await page.evaluate(() =>
        sb.uploads.every(
          (upload) => upload.bucket === "ipqc-gia-cong-ban-ve" && upload.options.upsert === false,
        ),
      ),
      true,
    );
    assert.deepEqual(errors, []);
    console.log(
      "PASS PDF 2 pages, zoom/fit, PNG/JPG/JPEG preview, byte-preserving save/reopen/replacement; no OCR/rows/confirmation changes; Model/drawing/Revision link and published standard/file unchanged",
    );
    await context.close();
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
