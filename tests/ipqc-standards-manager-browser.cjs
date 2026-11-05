/* Real shared editor and QC Manager UI, isolated API fixture; live RPCs tested in SQL rollback. */
const fs = require("fs"),
  path = require("path"),
  assert = require("node:assert/strict");
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || "playwright");
const { backend } = require("./ipqc-gc-fixture.cjs");
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } }),
      page = await context.newPage(),
      errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    page.on("dialog", (dialog) => dialog.accept());
    await context.addInitScript({
      content: `window.sb=(${backend.toString()})();window.IS_PROD=false;
    window.sbTaiHet=async make=>await make();window.MesNav={setTitle(){}};
    window.MesAuth={getSession:async()=>({user:{id:'u1'}}),getCurrentUserIdentity:async()=>'Inspector'};
    sb.tables.ipqc_btk[0].tai_lieu_goc={path:'u1/old.pdf',name:'old.pdf'};
    sb.tables.ipqc_btk[0].ban_ve_vi_tri=[{no:1,x:20,y:30}];
    sb.tables.ipqc_btk_muc.forEach(row=>row.phuong_phap='CMM point');
    sb.tables.ipqc_gc_tieu_chuan_lich_su=[{id:1,id_btk:1,thoi_diem:'2026-01-01',du_lieu:{tieu_chuan:{phien_ban:'A',ma_ban_ve:'DWG'},muc:[{}]}}];
    const rpc=sb.rpc.bind(sb);sb.rpc=async(name,args)=>{
      if(name!=='ipqc_gc_luu_tieu_chuan')return rpc(name,args);
      sb.calls.push({name,args});const p=args.p_data;
      if(window.failNextStandard){window.failNextStandard=false;return {error:{message:'Temporary save failure'}};}
      const id=2;sb.tables.ipqc_btk.push({...sb.tables.ipqc_btk[0],...p,id,trang_thai:'cho_kiem_tra',dang_dung:false});
      sb.tables.ipqc_btk_muc.push(...p.muc.map(row=>({...row,id_btk:id})));
      return {data:{ok:true,id,phien_ban:p.phien_ban}};
    };`,
    });
    await context.route("**/*", (route) => {
      const u = new URL(route.request().url());
      if (
        u.hostname !== "mes.test" ||
        ["/shared/supabase-client.js", "/shared/navbar.js"].includes(u.pathname)
      )
        return route.fulfill({ body: "", contentType: "application/javascript" });
      const file = path.resolve("." + decodeURIComponent(u.pathname));
      if (!file.startsWith(process.cwd() + path.sep) || !fs.existsSync(file))
        return route.fulfill({ status: 404, body: "" });
      return route.fulfill({
        body: fs.readFileSync(file),
        contentType: file.endsWith(".js")
          ? "application/javascript"
          : file.endsWith(".css")
            ? "text/css"
            : "text/html",
      });
    });
    await page.goto("https://mes.test/qc-manager.html?tab=tieuchuan&cd=gia_cong&type=btk&ma=PART&version=1");
    const root = page.locator("#btk-root");
    await root.locator("[data-f=ma_ban_ve]").waitFor();
    assert.equal(await page.locator('#tab-tieuchuan a[href="ipqc-gia-cong.html"]').count(),0);
    assert.equal(await root.locator("[data-f=phien_ban]").inputValue(), "A");
    assert.equal(await root.locator("[data-f=ma_ban_ve]").inputValue(), "DWG");
    assert.ok((await root.textContent()).includes("CMM point") === false); // value is in readonly inputs.
    assert.equal(await root.locator("[data-c=phuong_phap]").first().inputValue(), "CMM point");
    assert.ok((await root.textContent()).includes("Lịch sử lưu nội dung tiêu chuẩn"));
    assert.equal(await root.locator('iframe[title="Bản vẽ gốc"]').count(), 1);
    const before = await page.evaluate(() =>
      JSON.stringify({ b: sb.tables.ipqc_btk[0], m: sb.tables.ipqc_btk_muc.filter((m) => m.id_btk === 1) }),
    );
    await root.locator("[data-sua]").click();
    assert.equal(new URL(page.url()).pathname, "/qc-manager.html");
    await root.locator("[data-f=phien_ban]").fill("B");
    await root.locator("[data-f=noi_dung_sua_doi]").fill("Revise in shared manager");
    await root.locator("[data-c=usl]").first().fill("20.04");
    await root.locator("[data-c=usl]").first().dispatchEvent("change");
    await root.locator('[data-sao-chep="0"]').click();
    await root.locator("[data-dan-moi]").click();
    assert.equal(await root.locator("[data-f=phien_ban]").inputValue(), "B");
    assert.equal(await root.locator("[data-f=noi_dung_sua_doi]").inputValue(), "Revise in shared manager");
    assert.equal(await root.locator("[data-c=usl]").nth(3).inputValue(), "20.04");
    assert.equal(await root.locator("[data-c=co_mau]").nth(3).inputValue(), "2");
    await root.locator('[data-xoa="3"]').click();
    await root.locator("[data-luu]").click();
    assert.ok((await root.locator("[data-msg]").textContent()).includes("xác nhận từng đặc tính"));
    assert.equal(
      await page.evaluate(() => sb.calls.filter((c) => c.name === "ipqc_gc_luu_tieu_chuan").length),
      0,
    );
    for (const checkbox of await root.locator("[data-c=da_xac_nhan]").all()) await checkbox.check();
    await page.evaluate(()=>{window.failNextStandard=true;});
    await root.locator("[data-luu]").click();
    await page.waitForFunction(()=>document.querySelector('#btk-root [data-msg]').textContent.includes('Temporary save failure'));
    assert.equal(await root.locator('[data-luu]').isEnabled(),true);
    await root.locator("[data-luu]").click();
    await page.waitForFunction(() => sb.tables.ipqc_btk.length === 2);
    await page.waitForFunction(() => document.querySelector("#btk-root [data-f=phien_ban]")?.value === "B");
    const payload = await page.evaluate(
      () => sb.calls.find((c) => c.name === "ipqc_gc_luu_tieu_chuan").args.p_data,
    );
    assert.equal(payload.muc[0].usl, "20.04");
    assert.equal(payload.buoc_gia_cong, "Phay mặt A");
    assert.equal(payload.tai_lieu_goc.path, "u1/old.pdf");
    assert.equal(payload.ban_ve_vi_tri[0].x, 20);
    assert.equal(payload.muc[0].phuong_phap, "CMM point");
    assert.equal(payload.muc[0].don_vi, "mm");
    assert.equal(
      before,
      await page.evaluate(() =>
        JSON.stringify({ b: sb.tables.ipqc_btk[0], m: sb.tables.ipqc_btk_muc.filter((m) => m.id_btk === 1) }),
      ),
    );
    await page.screenshot({ path: ".review/ipqc-shared-standards.png", fullPage: true });
    await page.locator("#tc-cd-bar [data-cd=duc]").click();
    await page.waitForFunction(() =>
      document.querySelector("#btk-root [data-sidettl]").textContent.includes("Đúc"),
    );
    assert.equal(await root.locator("[data-f=ma_ban_ve]").count(), 0);
    await page.goto("https://mes.test/ipqc-gia-cong.html?standard=PART&version=1");
    await page.waitForURL("**/qc-manager.html?**");
    assert.equal(new URL(page.url()).searchParams.get("version"), "1");
    await root.locator("[data-f=ma_ban_ve]").waitFor();
    await page.goto("https://mes.test/ipqc-gia-cong.html");
    assert.equal(
      await page.locator("[data-tab=standards],[data-panel=standards],#gcStandardForm").count(),
      0,
    );
    assert.equal(await page.locator('body > header a, main > nav a, main > nav [onclick]').count(),0);
    assert.deepEqual(await page.locator('main > nav button').allTextContents(),['Nhập kết quả','Dashboard IPQC']);
    await page.waitForFunction(() => document.getElementById("gcMachine").options.length === 1);
    await page.locator("#gcMeasureProduct").fill("PART");
    await page.locator("#gcMeasureProduct").dispatchEvent("change");
    await page.waitForFunction(() => document.querySelectorAll("#gcMeasureRows [data-result]").length === 6);
    assert.deepEqual(errors, []);
    console.log(
      "PASS shared standards manager: GC metadata/limits/samples, revision review, private original, history, copy/paste, explicit confirmation, original data unchanged, casting separation, legacy links and measurement revision",
    );
    await context.close();
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
