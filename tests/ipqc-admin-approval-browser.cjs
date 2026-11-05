const fs = require("fs"),
  path = require("path"),
  assert = require("node:assert/strict");
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || "playwright");
const { backend } = require("./ipqc-gc-fixture.cjs");
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    for (const kind of ["btk", "checklist"])
      for (const [role, prod, status, canApprove] of [
        ["admin", false, "cho_kiem_tra", true],
        ["admin", false, "cho_phe_duyet", true],
        ["admin", true, "cho_kiem_tra", false],
        ["admin", true, "cho_phe_duyet", false],
        ["ipqc", false, "cho_kiem_tra", false],
        ["ipqc", false, "cho_phe_duyet", false],
        ["qc_manager", false, "cho_kiem_tra", true],
        ["qc_manager", false, "cho_phe_duyet", false],
        ["giam_doc_sx", false, "cho_kiem_tra", false],
        ["giam_doc_sx", false, "cho_phe_duyet", true],
      ]) {
        const context = await browser.newContext(),
          page = await context.newPage(),
          errors = [];
        page.on("pageerror", (error) => errors.push(error.message));
        let confirmApproval = false;
        page.on("dialog", (dialog) =>
          dialog.type() === "prompt"
            ? dialog.accept("Return test")
            : confirmApproval
              ? dialog.accept()
              : dialog.dismiss(),
        );
        await context.addInitScript({
          content: `window.sb=(${backend.toString()})({role:${JSON.stringify(role)}});
    window.IS_PROD=${prod};window.sbTaiHet=async make=>await make();window.MesNav={setTitle(){}};
    window.MesAuth={getSession:async()=>({user:{id:'u1'}}),getCurrentUserIdentity:async()=>'Admin'};
    const standard=sb.tables.ipqc_btk[0];standard.trang_thai=${JSON.stringify(kind === "btk" ? status : "da_duyet")};
    if(${JSON.stringify(kind)}==='checklist')sb.tables.duc_ipqc_tieuchuan_de_xuat=[{id:11,ma_sp:'PART',cong_doan:'gia_cong',
      trang_thai:${JSON.stringify(status)},danh_sach_muc_kiem_json:['Surface'],nguoi_lap_uid:'u1',noi_dung_sua_doi:'Test'}];
    const rpc=sb.rpc.bind(sb);sb.rpc=async(name,args)=>{
     if(name!=='ipqc_tc_duyet')return rpc(name,args);sb.calls.push({name,args});
     const table=args.p_loai==='btk'?'ipqc_btk':'duc_ipqc_tieuchuan_de_xuat';
     const row=sb.tables[table].find(row=>row.id===args.p_id);
     row.trang_thai=({kiem_tra:'cho_phe_duyet',phe_duyet:'da_duyet',tra_lai:'tra_lai'})[args.p_hanh_dong];
     row.nguoi_phe_duyet='Admin';row.nguoi_phe_duyet_uid='u1';row.phe_duyet_luc=new Date().toISOString();
     return {data:{ok:true,trang_thai:row.trang_thai}};
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
        const url =
          "https://mes.test/qc-manager.html?tab=tieuchuan&cd=gia_cong&ma=PART" +
          (kind === "btk" ? "&type=btk&version=1" : "");
        await page.goto(url);
        const box = page.locator(kind === "btk" ? "#btk-root" : "#tc-duyet");
        await box.locator(".tcd").waitFor();
        const approve = box.locator("[data-duyet=phe_duyet]"),
          review = box.locator("[data-duyet=kiem_tra]");
        assert.equal(
          await approve.count(),
          canApprove && status === "cho_phe_duyet" ? 1 : 0,
          [kind, role, prod, status].join("/"),
        );
        assert.equal(await review.count(), canApprove && status === "cho_kiem_tra" ? 1 : 0);
        assert.equal(await box.locator("[data-duyet=tra_lai]").count(), canApprove ? 1 : 0);
        assert.ok(!(await box.textContent()).includes("Admin phê duyệt ngay"));
        if (canApprove) {
          await box.locator("[data-duyet=tra_lai]").click();
          await page.waitForFunction(() =>
            sb.calls.some((call) => call.name === "ipqc_tc_duyet" && call.args.p_hanh_dong === "tra_lai"),
          );
          assert.equal(
            await page.evaluate(() => sb.calls.find((call) => call.name === "ipqc_tc_duyet").args.p_ly_do),
            "Return test",
          );
          await page.goto(url);
          await box.locator(".tcd").waitFor();
          if (status === "cho_kiem_tra") {
            await review.click();
            await page.waitForFunction(() =>
              sb.calls.some((call) => call.name === "ipqc_tc_duyet" && call.args.p_hanh_dong === "kiem_tra"),
            );
            await page.waitForFunction(
              (kind) =>
                !document
                  .querySelector(kind === "btk" ? "#btk-root" : "#tc-duyet")
                  .querySelector("[data-duyet=kiem_tra]"),
              kind,
            );
            if (role !== "admin") {
              assert.equal(await approve.count(), 0);
              assert.deepEqual(errors, []);
              await context.close();
              continue;
            }
            await approve.waitFor();
          }
          const count = await page.evaluate(
            () => sb.calls.filter((call) => call.name === "ipqc_tc_duyet").length,
          );
          await approve.click();
          assert.equal(
            await page.evaluate(() => sb.calls.filter((call) => call.name === "ipqc_tc_duyet").length),
            count,
          );
          confirmApproval = true;
          await approve.click();
          await page.waitForFunction(() =>
            sb.calls.some((call) => call.name === "ipqc_tc_duyet" && call.args.p_hanh_dong === "phe_duyet"),
          );
          const call = await page.evaluate(() =>
            sb.calls.find((call) => call.name === "ipqc_tc_duyet" && call.args.p_hanh_dong === "phe_duyet"),
          );
          assert.equal(call.args.p_loai, kind);
          assert.equal(call.args.p_hanh_dong, "phe_duyet");
          assert.equal(call.args.p_id, kind === "btk" ? 1 : 11);
          await page.waitForFunction(
            (kind) =>
              !document
                .querySelector(kind === "btk" ? "#btk-root" : "#tc-duyet")
                ?.querySelector("[data-duyet=phe_duyet]"),
            kind,
          );
        }
        assert.deepEqual(errors, []);
        await context.close();
      }
    console.log(
      "PASS Chrome 20 role/status/type cases: admin uses existing review/approval/return actions, same-account full workflow, normal role gates, production UI exclusion, cancel/confirm and shared RPC",
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
