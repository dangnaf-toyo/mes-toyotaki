const path = require("node:path"),
  fs = require("node:fs"),
  assert = require("node:assert/strict");
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || "playwright");
(async () => {
  const dashboardHtml = fs.readFileSync('bieu-do-chat-luong.html', 'utf8');
  assert.ok(dashboardHtml.indexOf('shared/ipqc-casting-history.js') < dashboardHtml.indexOf('shared/ipqc-btk-qc.js'));
  assert.ok(dashboardHtml.includes('shared/ipqc-casting-history.js?v=T234'));
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await page.setContent(
      '<meta name="viewport" content="width=device-width,initial-scale=1"><div id="entry"></div><div id="charts"></div>',
    );
    await page.addStyleTag({ path: path.resolve("shared/ipqc-casting.css") });
    for (const script of [
      "ipqc-spc.js",
      "ipqc-gc-math.js",
      "ipqc-gc-standard.js",
      "ipqc-casting-history.js",
      "ipqc-btk-do.js",
      "ipqc-btk-qc.js",
    ])
      await page.addScriptTag({ path: path.resolve("shared", script) });
    await page.evaluate(() => {
      const btk = { id: 1, ma_sp: "PART", phien_ban: "B", cong_doan: "duc", so_mau: 3, dang_dung: true };
      const muc = Array.from({ length: 30 }, (_, i) => ({
        muc_no: i + 1,
        hang_muc: "Đường kính " + (i + 1),
        kieu: "so",
        danh_nghia: 115.7,
        dung_sai_tren: 0.4,
        dung_sai_duoi: 0.4,
      }));
      const kq = ["2-1", "2-2", "69", "70"].map((ma_cvt, i) => ({
        muc_no: 2,
        mau: i + 1,
        ma_cvt,
        gia_tri: i === 2 ? 116.15 : 115.85,
        dat: i !== 2,
      }));
      const lan = [
        {
          id_checkpoint: "NEW",
          id_btk: 1,
          ma_may: "M1",
          nguoi: "QC01",
          thoi_diem: new Date().toISOString(),
          tieu_chuan: btk,
          muc_tieu_chuan: muc,
          so_muc_da_kiem: 1,
          so_muc_chua_kiem: 29,
          kq,
        },
        {
          id_checkpoint: "LEGACY",
          id_btk: 1,
          ma_may: "M2",
          nguoi: "QC02",
          thoi_diem: new Date().toISOString(),
          tieu_chuan: btk,
          muc_tieu_chuan: muc,
          kq: [{ muc_no: 2, mau: 1, gia_tri: 115.9, dat: true }],
        },
        {
          id_checkpoint: "OLD-REVISION",
          id_btk: 99,
          ma_may: "M1",
          nguoi: "QC03",
          thoi_diem: new Date().toISOString(),
          tieu_chuan: { phien_ban: "A" },
          muc_tieu_chuan: [{ muc_no: 2, hang_muc: "Old diameter" }],
          kq: [{ muc_no: 2, mau: 1, gia_tri: 999, dat: true }],
        },
      ];
      window.dataset = { btk, muc, lan, gioi_han: [] };
      window.sbTaiHet = async (make) => {
        const data = [];
        for (let offset = 0; ; offset += 1000) {
          const r = await make().range(offset, offset + 999);
          if (r.error) return r;
          data.push(...r.data);
          if (r.data.length < 1000) return { data, error: null };
        }
      };
      const gcBtk = { ...btk, id: 2, cong_doan: "gia_cong", so_mau: 2 };
      window.gcDataset = {
        btk: gcBtk,
        muc: [muc[1]],
        gioi_han: [],
        lan: [
          {
            ...lan[0],
            id_btk: 2,
            kq: [
              { muc_no: 2, mau: 1, gia_tri: 115.85, dat: true },
              { muc_no: 2, mau: 2, gia_tri: 116.15, dat: false },
            ],
          },
        ],
      };
      window.MesAuth = { getSession: async () => ({ user: { id: "u1" } }), getCurrentUserIdentity: async () => "QC01" };
      window.sb = {
        rpc: async (_, args) => ({ data: args.p_cong_doan === "gia_cong" ? gcDataset : dataset, error: null }),
        from(table) {
          let rows =
            table === "ipqc_btk"
              ? [btk, gcBtk, { ...btk, id: 99, phien_ban: "A", dang_dung: false }]
              : table === "ipqc_do_lan"
                ? lan.map((l) => ({ ...l, ma_sp: "PART" }))
                : table === "ipqc_btk_muc"
                  ? [
                      ...muc.map((m) => ({ ...m, id_btk: 1 })),
                      ...lan[2].muc_tieu_chuan.map((m) => ({ ...m, id_btk: 99 })),
                    ]
                  : table === "ipqc_do_kq"
                    ? window.largeResults ||
                      lan.flatMap((l) => l.kq.map((k) => ({ ...k, id_checkpoint: l.id_checkpoint })))
                    : [];
          let single = false;
          const q = {
            select() {
              return q;
            },
            eq(k, v) {
              rows = rows.filter((r) => r[k] === v);
              return q;
            },
            order() {
              return q;
            },
            limit(n) {
              rows = rows.slice(0, n);
              return q;
            },
            range(from, to) {
              rows = rows.slice(from, to + 1);
              return q;
            },
            maybeSingle() {
              single = true;
              return q;
            },
            then(fn) {
              return Promise.resolve({ data: single ? rows[0] || null : rows, error: null }).then(fn);
            },
          };
          return q;
        },
      };
    });
    await page.evaluate(async () => {
      window.ctl = await IpqcBtkDo.mount(document.querySelector("#entry"), { ma_sp: "PART", ma_may: "M1" });
      ctl.setEnabled(true);
      await IpqcBtkQc.mountChart(document.querySelector("#charts"));
    });
    await page.locator("[data-l=no]").selectOption("2");
    await page.locator("[data-l=cvt]").waitFor();
    assert.equal(await page.locator("[data-l=cvt]").inputValue(), "2-1");
    const history = page.locator("#charts [data-casting-history]");
    assert.match(await history.textContent(), /OK: 5 · NG: 1 · Tỷ lệ NG: 16.7%/);
    assert.equal(await history.locator("details").count(), 3);
    await history.locator("[data-inspection=NEW] summary").click();
    assert.equal(await history.locator("[data-inspection=NEW] tbody tr").count(), 33);
    assert.match(await history.locator("[data-inspection=NEW]").textContent(), /69.*116.15.*NG/);
    assert.match(await history.textContent(), /Chưa có mã CVT/);
    assert.match(await history.textContent(), /999/);
    await page.locator("[data-l=cvt]").selectOption("69");
    await page.waitForFunction(() => document.querySelector("[data-trai] svg")?.textContent.includes("116.15"));
    assert.ok(!(await page.locator("[data-trai] svg").first().textContent()).includes("999.00"));
    await page.locator("[data-l=may]").selectOption("M2");
    assert.equal(await history.locator("details").count(), 1);
    assert.match(await history.textContent(), /NG: 0/);
    await page.locator("[data-l=cvt]").selectOption("");
    await page.waitForFunction(() => document.querySelector("[data-trai] svg")?.textContent.includes("115.90"));
    await page.locator("[data-l=cd]").selectOption("gia_cong");
    await page.waitForFunction(() => document.querySelector("[data-trai] svg")?.textContent.includes("116.15"));
    assert.equal(await page.locator("[data-l=cvt]").count(), 0);
    assert.equal(await page.locator("#charts [data-casting-history]").count(), 0);
    assert.match(await page.locator("[data-trai]").textContent(), /2 mẫu\/lần/);
    // Real browser mobile layout, keyboard inputs and add/delete interactions.
    await page.setViewportSize({ width: 390, height: 844 });
    await page.locator('#entry [data-select="2"]').check();
    await page.locator('#entry [data-code="2:0"]').fill("2-1");
    await page.locator('#entry [data-v="2:0"]').fill("115.85");
    await page.locator('#entry [data-add="2"]').click();
    await page.locator('#entry [data-code="2:1"]').fill("70");
    await page.locator('#entry [data-v="2:1"]').fill("116.15");
    assert.equal(await page.evaluate(() => ctl.trangThai().ng), 1);
    assert.equal(
      await page.evaluate(() => {
        const el = document.querySelector("#entry");
        return el.scrollWidth <= el.clientWidth;
      }),
      true,
    );
    await page.locator('#entry [data-delete="2:1"]').click();
    assert.equal(await page.evaluate(() => ctl.trangThai().du), true);
    fs.mkdirSync(".review", { recursive: true });
    await page.locator("#entry").screenshot({ path: ".review/ipqc-casting-mobile.png" });
    await page.evaluate(async () => {
      const node = document.createElement("div");
      node.id = "single";
      document.body.append(node);
      await IpqcCastingHistory.load(node, "OLD-REVISION");
    });
    assert.match(await page.locator("#single").textContent(), /Old diameter.*999.*OK/);
    await page.evaluate(async () => {
      window.largeResults = Array.from({ length: 1002 }, (_, i) => ({
        id_checkpoint: "NEW",
        muc_no: 2,
        mau: i + 1,
        ma_cvt: "P-" + i,
        gia_tri: 115.7,
        dat: true,
      }));
      await IpqcCastingHistory.load(document.querySelector("#single"), "NEW");
    });
    assert.equal(await page.locator("#single tbody tr").count(), 1031);
    assert.match(await page.locator("#single").textContent(), /P-1001/);
    assert.deepEqual(errors, []);
    console.log(
      "PASS Chrome: CVT series isolated by code/revision, stored OK/NG ratio, old values, complete per-item history, machine filter, 390px add/delete/entry without overflow.",
    );
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
