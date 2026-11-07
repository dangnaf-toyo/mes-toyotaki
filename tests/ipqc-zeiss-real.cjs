/* Supply a company Calypso PDF locally; no customer document is committed. */
const fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict");
const { pathToFileURL } = require("node:url");
const P = require("../shared/ipqc-result-parser.js");
(async () => {
  assert.ok(process.env.MES_ZEISS_PDF, "Set MES_ZEISS_PDF to an actual ZEISS Calypso report");
  const { getDocument } = await import(
    pathToFileURL(path.resolve(".review/tools/node_modules/pdfjs-dist/legacy/build/pdf.mjs"))
  );
  const file = process.env.MES_ZEISS_PDF;
  const doc = await getDocument({ data: new Uint8Array(fs.readFileSync(file)), verbosity: 0 }).promise;
  const sheets = [],
    oracle = [];
  for (let page = 1; page <= doc.numPages; page++) {
    const items = (await (await doc.getPage(page)).getTextContent()).items;
    const actual = items.find((x) => x.str === "Actual"),
      nominal = items.find((x) => x.str === "Nominal");
    assert.ok(actual && nominal, "Real report must have explicit Actual and Nominal headers on page " + page);
    // Independent oracle: raw text boxes in the Actual column, with their original numbers.
    const numbers = items
      .filter(
        (x) =>
          P.number(x.str) !== null &&
          x.transform[5] < actual.transform[5] &&
          x.transform[4] >= actual.transform[4] - 2 &&
          x.transform[4] < nominal.transform[4] - 5,
      )
      .sort((a, b) => b.transform[5] - a.transform[5]);
    oracle.push(...numbers.map((x) => P.number(x.str)));
    sheets.push({ name: "Trang " + page, lines: P.pdfLines(items), method: "pdf-text" });
  }
  const parsed = P.parse(sheets);
  assert.ok(parsed.length > 10 && doc.numPages > 1, "Use a real multipage measurement report");
  assert.deepEqual(
    parsed.map((c) => c.samples[0].value),
    oracle,
    "Every Actual must match the source PDF box, never Nominal/Deviation",
  );
  assert.equal(new Set(parsed.map((c) => c.id)).size, parsed.length);
  const features = parsed.map((c, i) => ({
    id: i + 1,
    id_btk: 1,
    muc_no: i + 1,
    ma_dac_tinh: c.id,
    hang_muc: "CMM " + c.id,
    kieu: "so",
    danh_nghia: c.nominal,
    don_vi: "mm",
    dung_sai_co_dau: true,
    dung_sai_tren: c.upper,
    dung_sai_duoi: c.lower,
    lsl: c.lower === null ? null : c.nominal + c.lower,
    usl: c.upper === null ? null : c.nominal + c.upper,
    co_mau: 1,
    dung_cu: "CMM",
  }));
  assert.deepEqual(
    parsed.map((c) => P.match(c, features).muc_no),
    features.map((m) => m.muc_no),
  );
  assert.equal(P.match(parsed[0], [features[0], { ...features[0], muc_no: 999 }]).status, "ambiguous");
  assert.equal(
    P.match({ ...parsed[0], id: "7-1" }, [{ ...features[0], ma_dac_tinh: "71" }]).status,
    "unmatched",
  );
  assert.equal(
    P.match(
      parsed[0],
      features.map((m) => ({ ...m, ma_dac_tinh: null })),
    ).status,
    "unmatched",
    "No ordinal-only mapping",
  );
  const same = { ...parsed[0], id: "UNKNOWN", name: features[0].hang_muc, unit: "mm" };
  assert.equal(P.match(same, features).muc_no, 1, "Full name/spec/unit evidence");
  assert.equal(P.match({ ...same, unit: "" }, features).status, "unmatched");
  assert.equal(P.match({ ...same, upper: same.upper + 1 }, features).status, "unmatched");
  assert.ok(P.match({ ...parsed[0], unit: "mm", nominal: parsed[0].nominal + 1 }, features).warnings.length);
  const damaged = structuredClone(sheets);
  const actualLine = damaged[0].lines.find((l) => l.cells.some((c) => c.text === parsed[0].samples[0].raw));
  actualLine.cells = actualLine.cells.filter((c) => c.text !== parsed[0].samples[0].raw);
  const partial = P.parse(damaged);
  assert.equal(partial.length, parsed.length);
  assert.equal(partial[0].samples[0].value, null);
  assert.match(partial[0].samples[0].warning, /Actual/);
  assert.deepEqual(
    partial.slice(1).map((c) => c.samples[0].value),
    oracle.slice(1),
  );
  const comma = structuredClone(sheets.slice(0, 1));
  for (const l of comma[0].lines)
    for (const c of l.cells)
      if (P.number(c.text) !== null) c.text = c.text.replace(".", ",").replace("-", "−");
  assert.deepEqual(
    P.parse(comma).map((c) => c.samples[0].value),
    parsed.slice(0, P.parse(comma).length).map((c) => c.samples[0].value),
  );
  assert.equal(P.zeiss({ lines: [] }), null);
  fs.writeFileSync(
    ".review/zeiss-validation.json",
    JSON.stringify({ file, pages: doc.numPages, parsed, features, oracle }),
  );
  await doc.destroy();
  console.log(
    JSON.stringify({
      result:
        "PASS real Calypso PDF, independent Actual oracle, all pages, signs/decimal commas, missing Actual, safe/ambiguous mapping, MES mismatch warnings",
      pages: sheets.length,
      extracted: parsed.length,
      matched: parsed.length,
      unresolved: 0,
    }),
  );
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
