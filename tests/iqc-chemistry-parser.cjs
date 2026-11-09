const assert = require("node:assert/strict"),
  C = require("../shared/iqc-chemistry.js");
const standard = [
  { ma_dac_tinh: "Si", lsl: 9.6, usl: 12, don_vi: "%", bat_buoc: true },
  { ma_dac_tinh: "Fe", lsl: null, usl: 1.3, don_vi: "%", bat_buoc: true },
];
const sheet = (rows) => [{ name: "Analysis", rows }];
assert.deepEqual(
  C.parse(
    sheet([
      ["Element", "Max (%)"],
      ["Si", "12"],
      ["Fe", "1.3"],
    ]),
  ),
  [],
  "Single specification bound never becomes an actual value",
);
assert.deepEqual(
  C.parse(
    sheet([
      ["Element", "Actual maximum (%)"],
      ["Fe", "1.3"],
    ]),
  ),
  [],
  "An actual-labelled limit is still a limit",
);
assert.deepEqual(
  C.parse(sheet([["Chemical specification (%)"], ["Si", "Fe"], ["12", "1.3"]])),
  [],
  "Specification title prevents unlabelled horizontal bounds being treated as results",
);
assert.equal(C.ELEMENTS.length, 118);
assert.equal(C.element("Silicon"), "Si");
assert.equal(C.element("Nhôm"), "Al");
assert.equal(C.element("Ống nhôm"), null);
assert.equal(C.numeric("0"), "0");
assert.equal(C.numeric("1,2000"), "1.2");
assert.equal(C.numeric("1e-4"), "0.0001");
assert.equal(C.numeric(",4"), "0.4");
assert.equal(C.evaluate(standard, { Si: "10", Fe: "bad" }).results[1].result, "Không hợp lệ");
for (const bad of ["NaN", "Infinity", "<0.001", "BAL", "12,3,4", "1e400", "1.2%"])
  assert.equal(C.numeric(bad), "", bad);
assert.equal(C.compare("0.30000000000000000001", "0.3"), 1);
assert.equal(C.compare("0.00000000000000000001", "0"), 1);
assert.equal(C.convert("0.001", "%", "ppm"), "10");
assert.equal(C.convert("125", "ppm", "%"), "0.0125");
assert.equal(C.convert("1", "mg/kg", "ppm"), "1");
assert.equal(C.convert("1", "", "%"), null);
let parsed = C.parse(
  sheet([
    ["Element", "Result (%)", "Min", "Max"],
    ["Si", "10,5", "9.6", "12"],
    ["Fe", "0.4", "", "1.3"],
  ]),
);
assert.deepEqual(
  parsed.map((x) => [x.element, x.value, x.unit]),
  [
    ["Si", "10.5", "%"],
    ["Fe", "0.4", "%"],
  ],
);
assert.deepEqual(C.matched(standard, parsed).values, { Si: "10.5", Fe: "0.4" });
parsed = C.parse(
  sheet([
    ["Chemical composition wt.%"],
    ["Sample", "Si", "Fe", "Cu"],
    ["Minimum", "9.6", "0", "0"],
    ["Maximum", "12", "1.3", "3"],
    ["Mean", "11.2", "0.6", "1.1"],
  ]),
);
assert.deepEqual(
  parsed.map((x) => [x.element, x.value]),
  [
    ["Si", "11.2"],
    ["Fe", "0.6"],
    ["Cu", "1.1"],
  ],
);
parsed = C.parse(
  sheet([
    ["Element", "Min", "Max"],
    ["Si", 9.6, 12],
    ["Fe", 0, 1.3],
  ]),
);
assert.equal(parsed.length, 0, "Never use specification bounds as actuals");
parsed = C.parse(
  sheet([
    ["Element", "Result (%)"],
    ["Si", "<0.001"],
    ["Fe", "BAL"],
  ]),
);
assert.equal(parsed.length, 0);
parsed = C.parse(
  sheet([
    ["Element", "Result"],
    ["Si", "10.2%"],
    ["Fe", "0.5%"],
  ]),
);
assert.equal(C.matched(standard, parsed).values.Si, "10.2");
parsed = C.parse(
  sheet([
    ["Element", "Result"],
    ["Si", "10.2"],
    ["Fe", "0.5"],
  ]),
);
assert.deepEqual(C.matched(standard, parsed).values, {});
assert.equal(C.matched(standard, parsed, "%").values.Fe, "0.5");
parsed = C.parse(
  sheet([
    ["Element", "Result (%)"],
    ["Si", "10.2"],
    ["Si", "10.4"],
    ["Fe", "0.5"],
  ]),
);
assert.equal(C.matched(standard, parsed).values.Si, undefined);
assert.equal(C.matched(standard, parsed).choices.Si.length, 2);
assert.equal(C.evaluate(standard, { Si: "9.6", Fe: "1.3" }).conclusion, "OK");
assert.equal(C.evaluate(standard, { Si: "12.0000000000000000001", Fe: ".2" }).conclusion, "NG");
assert.equal(C.evaluate(standard, { Si: "10.1" }).conclusion, "");
assert.equal(C.evaluate(standard, { Si: "13" }).conclusion, "NG");
assert.equal(C.evaluate([], { Si: "1" }).conclusion, "");
assert.equal(C.evaluate(standard, { Si: "10.1", Fe: "0" }).conclusion, "OK");
parsed = C.parse([
  {
    name: "OCR",
    method: "ocr",
    rows: [
      ["Element", "Result (%)"],
      ["Fe", "04"],
    ],
    confidence: [99, 95],
  },
]);
assert.equal(parsed.length, 0, "Missing OCR decimal is not fabricated");
parsed = C.parse([
  {
    name: "OCR",
    method: "ocr",
    rows: [
      ["Element", "Result (%)"],
      ["Fe", "0.4"],
    ],
    confidence: [99, 80],
  },
]);
assert.equal(C.matched(standard, parsed).values.Fe, undefined, "Low confidence requires explicit review");
parsed = C.parse(
  sheet([
    ["Element", "Result", "Unit"],
    ["Fe", "4000", "ppm"],
    ["Si", "10.5", ""],
  ]),
);
assert.equal(C.matched(standard, parsed).values.Fe, "0.4");
assert.equal(C.matched(standard, parsed).values.Si, undefined, "Do not borrow another element unit");
assert.equal(
  C.matched(standard, parsed, "%").values.Fe,
  "0.4",
  "Fallback units never override explicit per-element units",
);
parsed = C.parse(
  sheet([
    ["Sample", "Si", "Fe"],
    ["Unit", "%", "ppm"],
    ["Mean", "10.5", "4000"],
  ]),
);
assert.deepEqual(C.matched(standard, parsed).values, { Si: "10.5", Fe: "0.4" });
console.log(
  "PASS chemistry: 118 canonical elements, vertical/horizontal actual columns, reject limits/LOD/balance, exact decimal/unit conversion, ambiguity, required missing and OK/NG boundaries",
);
