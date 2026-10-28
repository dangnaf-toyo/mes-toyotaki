const fs = require("fs"),
  path = require("path"),
  assert = require("node:assert/strict");
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || "../.review/tools/node_modules/playwright");
const { backend } = require("./oqc-dashboard-fixture.cjs");
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    for (const [role, actor, allowed] of [
      ["nhan_vien_oqc", "owner", [1]],
      ["qc_manager", "other", [2]],
      ["admin", "admin", [1, 2, 3]],
      ["viewer", "owner", []],
    ]) {
      const context = await browser.newContext({ viewport: { width: 1366, height: 900 } }),
        page = await context.newPage(),
        errors = [];
      page.on("pageerror", (e) => errors.push(e.stack));
      page.on("dialog", (d) => d.accept());
      await context.addInitScript({
        content:
          "window.sb=(" +
          backend.toString() +
          ")(" +
          JSON.stringify({ actor, actorRole: role, viewer: role === "viewer" }) +
          ");" +
          `
 const from=sb.from.bind(sb);sb.from=name=>{const q=from(name);q.overlaps=()=>q;return q;};
 sb.tables.oqc_daily_inspection=[1,2,3].map(id=>({id,created_by:id===1?'owner':id===2?'other':null,updated_at:'2026-10-28T00:00:00Z',inspection_date:sb.day,product_code:'A',shift:'Ca 1',total_qty:10,ok_qty:9,ng_qty:1,inspector_code:'QC01',inspector_name:'Worker One',defects:[{code:'xuoc',qty:1}]}));
 sb.tables.oqc_inspection_context=sb.tables.oqc_daily_inspection.map(r=>({inspection_id:r.id,source_date:r.inspection_date,source_product_code:r.product_code,inspection_scope:'FULL_POST_MACHINING'}));
 const rpc=sb.rpc.bind(sb);sb.rpc=async(name,args)=>{if(name==='oqc_xoa_bao_cao'){sb.calls.push({name,args});await new Promise(r=>setTimeout(r,50));sb.tables.oqc_daily_inspection=sb.tables.oqc_daily_inspection.filter(r=>r.id!==args.p_id);return {data:true,error:null};}return rpc(name,args);};
 window.MesAuth={getSession:async()=>({user:{id:'${actor}'}}),requireAuth:async()=>({user:{id:'${actor}'}}),getCurrentUserIdentity:async()=>'TEST'};window.MesNav={setTitle(){}};`,
      });
      await context.route("**/*", (route) => {
        const u = new URL(route.request().url());
        if (u.hostname !== "mes.test" || ["/shared/supabase-client.js", "/shared/navbar.js"].includes(u.pathname))
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
      await page.goto("https://mes.test/oqc-daily.html");
      await page.waitForFunction(
        () => typeof OqcDashboard !== "undefined" && OqcDashboard.getSnapshot()?.records.length === 3,
      );
      await page.evaluate(() => OqcReportAccess.ready);
      for (const id of [1, 2, 3])
        assert.equal(
          await page.locator('#rows tr[data-record-id="' + id + '"] button').count(),
          allowed.includes(id) ? 2 : 0,
        );
      const forbidden = [1, 2, 3].find((id) => !allowed.includes(id));
      if (forbidden) {
        await page.evaluate((id) => editRow(id), forbidden);
        assert.equal(await page.locator("#oqcReportDialog").isVisible(), false);
        await page.evaluate((id) => OqcReportAccess.remove(id), forbidden);
        assert.equal(await page.evaluate(() => sb.calls.filter((c) => c.name === "oqc_xoa_bao_cao").length), 0);
      }
      if (allowed.length) {
        const id = allowed[0];
        await page.evaluate((id) => Promise.all([OqcReportAccess.remove(id), OqcReportAccess.remove(id)]), id);
        await page.waitForFunction((id) => !OqcDashboard.getSnapshot().records.some((r) => r.id === id), id);
        assert.equal(await page.evaluate(() => sb.calls.filter((c) => c.name === "oqc_xoa_bao_cao").length), 1);
        assert.equal(await page.locator('#rows tr[data-record-id="' + id + '"]').count(), 0);
      }
      assert.deepEqual(errors, []);
      console.log(
        "PASS Chromium " +
          role +
          ": exact owner/Admin buttons, direct edit/delete guard, one delete request and dashboard reread",
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
