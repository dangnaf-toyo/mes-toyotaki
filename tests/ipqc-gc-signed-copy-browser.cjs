/* Actual UI/event workflow with an isolated backend fixture; RPCs verified separately in staging rollback. */
const fs = require("fs"),
  path = require("path"),
  assert = require("node:assert/strict");
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || "playwright");
const { backend } = require("./ipqc-gc-fixture.cjs");
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const context = await browser.newContext({ viewport: { width: 1560, height: 1000 } }),
      page = await context.newPage(),
      errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    page.on("dialog", (dialog) => dialog.accept());
    await context.addInitScript({
      content: `window.sb=(${backend.toString()})();window.IS_PROD=false;
   window.MesAuth={getSession:async()=>({user:{id:'u1'}}),getCurrentUserIdentity:async()=>'Admin'};
   window.MesNav={setTitle(){}};window.sbTaiHet=async make=>await make();
   sb.tables.master_products.push({ma_sp:'TARGET',ten_sp:'Target Product',ten_khach_hang:'Target Customer'},
    {ma_sp:'BLOCKED',ten_sp:'Pending Product',ten_khach_hang:'Other Customer'});
   const base=sb.tables.ipqc_btk[0];base.tai_lieu_goc={path:'u1/source.pdf',name:'source.pdf'};base.ma_ban_ve='SOURCE-DRAWING';
   sb.tables.ipqc_btk.push({...base,id:2,ma_sp:'TARGET',tai_lieu_goc:null},{...base,id:4,ma_sp:'BLOCKED',dang_dung:false,trang_thai:'cho_kiem_tra'},
    {...base,id:5,phien_ban:'OLD',dang_dung:false});
   const feature=sb.tables.ipqc_btk_muc[0];
   sb.tables.ipqc_btk_muc=Array.from({length:50},(_,i)=>({...feature,id:i+1,id_btk:1,muc_no:i+1,ma_dac_tinh:'D'+(i+1),hang_muc:'Feature '+(i+1),
    kieu:i===49?'okng':'so',tieu_chuan:i===49?'OK surface':null,phuong_phap:'CMM point',nguon_nhan_dien:{ghi_chu:'Keep '+i}}));
   sb.tables.ipqc_btk_muc.push({...feature,id:100,id_btk:2},{...feature,id:101,id_btk:4});
   sb.tables.ipqc_btk_muc.push(...sb.tables.ipqc_btk_muc.filter(m=>m.id_btk===1).slice(0,10).map((m,i)=>({...m,id:300+i,id_btk:5})));
   const rpc=sb.rpc.bind(sb);sb.rpc=async(name,args)=>{
    if(name==='ipqc_gc_sao_chep_tieu_chuan'){
     sb.calls.push({name,args});const source=sb.tables.ipqc_btk.find(b=>b.id===args.p_nguon_id),target=args.p_ma_dich;
     if(sb.tables.ipqc_btk.some(b=>b.ma_sp===target&&b.phien_ban===args.p_phien_ban))return {error:{message:'Revision đích đã tồn tại'}};
     const id=3;const origin={model_nguon:source.ma_sp,phien_ban_nguon:source.phien_ban,id_nguon:source.id,nguoi_sao_chep:'Admin',thoi_diem:new Date().toISOString()};
     sb.tables.ipqc_btk.push({...source,id,ma_sp:target,phien_ban:args.p_phien_ban,trang_thai:'ban_nhap',dang_dung:false,
      ma_ban_ve:null,tai_lieu_goc:null,ban_ve_url:null,ban_ve_vi_tri:[],nguon_sao_chep:origin,noi_dung_sua_doi:'Sao chép từ PART / Revision A'});
     const copied=sb.tables.ipqc_btk_muc.filter(m=>m.id_btk===source.id).map((m,i)=>{
      const signed=IpqcGcStandard.toSigned(m),limits=IpqcGcStandard.bounds(m);
      return {...signed,...limits,id:200+i,id_btk:id,xac_nhan_boi:null,xac_nhan_luc:null};});
     sb.tables.ipqc_btk_muc.push(...copied);return {data:{ok:true,id,ma_sp:target,phien_ban:args.p_phien_ban,trang_thai:'ban_nhap'}};
    }
    if(name==='ipqc_gc_luu_tieu_chuan'){
     sb.calls.push({name,args});const p=args.p_data,prior=sb.tables.ipqc_btk.find(b=>b.id===3);
     Object.assign(prior,p,{trang_thai:'cho_kiem_tra',dang_dung:false});
     sb.tables.ipqc_btk_muc=sb.tables.ipqc_btk_muc.filter(m=>m.id_btk!==3).concat(p.muc.map((m,i)=>{
      const row={...m,id:200+i,id_btk:3,dung_sai_co_dau:true};
      for(const key of ['danh_nghia','dung_sai_tren','dung_sai_duoi','lsl','usl'])row[key]=IpqcGcStandard.normalized(m[key])==null?null:Number(m[key]);
      return row;
     }));
     return {data:{ok:true,id:3,phien_ban:p.phien_ban}};
    }
    if(name==='ipqc_tc_duyet'){
     sb.calls.push({name,args});const b=sb.tables.ipqc_btk.find(b=>b.id===args.p_id);
     b.trang_thai=args.p_hanh_dong==='kiem_tra'?'cho_phe_duyet':'da_duyet';
     if(b.trang_thai==='da_duyet'){sb.tables.ipqc_btk.filter(v=>v.ma_sp===b.ma_sp).forEach(v=>v.dang_dung=v.id===b.id);}
     return {data:{ok:true}};
    }
    return rpc(name,args);
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
    await root.locator("[data-copy-model]").waitFor();
    assert.equal(await root.locator("[data-c=dung_sai_duoi]").first().inputValue(), "-0.05");
    const before = await page.evaluate(() =>
      JSON.stringify({
        b: sb.tables.ipqc_btk.filter((b) => [1, 2].includes(b.id)),
        m: sb.tables.ipqc_btk_muc.filter((m) => [1, 2].includes(m.id_btk)),
      }),
    );
    await root.locator("[data-copy-model]").click();
    const dialog = page.getByRole("dialog", { name: "Sao chép tiêu chuẩn sang Model khác" });
    await dialog.locator("[data-copy-source]").selectOption("5");
    assert.ok((await dialog.locator("[data-copy-summary]").textContent()).includes("10 hạng mục"));
    await dialog.locator("[data-copy-source]").selectOption("1");
    await dialog.locator("[data-copy-target]").selectOption("BLOCKED");
    await page.waitForFunction(() =>
      document.querySelector("[data-copy-warning]").textContent.includes("đã có bản nháp"),
    );
    assert.equal(await dialog.locator("[data-copy-submit]").isDisabled(), true);
    await dialog.locator("[data-copy-target]").selectOption("TARGET");
    await page.waitForFunction(() => document.querySelector("[data-copy-revision]").value === "B");
    assert.ok((await dialog.locator("[data-copy-summary]").textContent()).includes("50 hạng mục"));
    await dialog.locator("[data-copy-revision]").fill("A");
    await dialog.locator("[data-copy-confirm]").check();
    await dialog.locator("[data-copy-submit]").click();
    await page.waitForFunction(() =>
      document.querySelector("[data-copy-message]").textContent.includes("đã tồn tại"),
    );
    await dialog.locator("[data-copy-revision]").fill("B");
    await dialog.locator("[data-copy-submit]").click();
    await page.waitForFunction(() => document.querySelector("#btk-root [data-f=phien_ban]")?.value === "B");
    assert.ok((await root.textContent()).includes("Target Customer"));
    assert.ok((await root.textContent()).includes("Nguồn sao chép: PART"));
    assert.equal(await root.locator("tr[data-r]").count(), 50);
    assert.equal(await root.locator("[data-duyet]").count(), 0);
    assert.equal(await root.locator("[data-f=ma_ban_ve]").inputValue(), "");
    assert.equal(await root.locator("[data-drawing-viewer]").count(), 0);
    assert.equal(
      before,
      await page.evaluate(() =>
        JSON.stringify({
          b: sb.tables.ipqc_btk.filter((b) => [1, 2].includes(b.id)),
          m: sb.tables.ipqc_btk_muc.filter((m) => [1, 2].includes(m.id_btk)),
        }),
      ),
    );
    await root.locator("[data-sua]").click();
    const first = root.locator("tr[data-r]").first(),
      input = (key) => first.locator("[data-c=" + key + "]");
    for (const [nominal, upper, lower, lsl, usl] of [
      ["20", "+0.05", "-0.05", "19.95", "20.05"],
      ["14.6", "+0.3", "+0.1", "14.7", "14.9"],
      ["14.6", "-0.1", "-0.3", "14.3", "14.5"],
      ["20", "0", "-0.1", "19.9", "20"],
      ["20", "+0.1", "0", "20", "20.1"],
    ]) {
      await input("danh_nghia").fill(nominal);
      await input("dung_sai_tren").fill(upper);
      await input("dung_sai_duoi").fill(lower);
      assert.equal(await input("lsl").inputValue(), lsl);
      assert.equal(await input("usl").inputValue(), usl);
    }
    await input("danh_nghia").fill("14.6");
    await input("dung_sai_tren").fill("+0.3");
    await input("dung_sai_duoi").fill("");
    assert.equal(await input("lsl").inputValue(), "");
    await input("dung_sai_duoi").fill("+0.5");
    assert.ok(
      (await first.locator("[data-gc-limit-error]").textContent()).includes("LSL không được lớn hơn USL"),
    );
    for (const checkbox of await root.locator("[data-c=da_xac_nhan]").all()) await checkbox.check();
    await root.locator("[data-luu]").click();
    assert.equal(
      await page.evaluate(() => sb.calls.filter((c) => c.name === "ipqc_gc_luu_tieu_chuan").length),
      0,
    );
    await input("dung_sai_duoi").fill("+0.1");
    assert.equal(await first.locator("[data-gc-dimension]").textContent(), "14.6 (+0.3/+0.1)");
    for (const checkbox of await root.locator("[data-c=da_xac_nhan]").all()) await checkbox.check();
    await root.locator("[data-luu]").click();
    await root.locator("[data-duyet=kiem_tra]").waitFor();
    assert.equal(await input("dung_sai_tren").inputValue(), "0.3");
    assert.equal(await input("dung_sai_duoi").inputValue(), "0.1");
    assert.equal(await first.locator("[data-gc-dimension]").textContent(), "14.6 (+0.3/+0.1)");
    assert.equal(await input("lsl").inputValue(), "14.7");
    assert.equal(await input("usl").inputValue(), "14.9");
    assert.equal(
      before,
      await page.evaluate(() =>
        JSON.stringify({
          b: sb.tables.ipqc_btk.filter((b) => [1, 2].includes(b.id)),
          m: sb.tables.ipqc_btk_muc.filter((m) => [1, 2].includes(m.id_btk)),
        }),
      ),
    );
    await page.screenshot({ path: ".review/ipqc-signed-copy.png", fullPage: true });
    await root.locator("[data-duyet=kiem_tra]").click();
    await root.locator("[data-duyet=phe_duyet]").click();
    await page.waitForFunction(() => sb.tables.ipqc_btk.find((b) => b.id === 3).trang_thai === "da_duyet");
    const snapshot = await page.evaluate(() => ({
      standards: sb.tables.ipqc_btk,
      features: sb.tables.ipqc_btk_muc,
    }));
    await context.addInitScript({
      content:
        "sb.tables.ipqc_btk=" +
        JSON.stringify(snapshot.standards) +
        ";sb.tables.ipqc_btk_muc=" +
        JSON.stringify(snapshot.features) +
        ";",
    });
    await page.goto("https://mes.test/ipqc-gia-cong.html?ma=TARGET");
    await page.waitForFunction(() => document.getElementById("gcMeasureVersion").value === "3");
    assert.equal(await page.locator("#gcMeasureRows [data-result]").count(), 100);
    await page.locator('[data-result][data-no="1"][data-sample="1"]').fill("14.69");
    assert.equal(
      await page
        .locator('[data-result][data-no="1"][data-sample="1"]')
        .evaluate((input) => input.classList.contains("measure-ng")),
      true,
    );
    assert.deepEqual(errors, []);
    await context.close();
    console.log(
      "PASS Chrome five signed examples/empty/invalid/save/reopen; 50-feature copy dialog, pending-target protection, independent draft/customer/file/history, normal release and approved signed measurement",
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
