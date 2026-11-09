const assert = require("node:assert/strict");
const P = require("../shared/ipqc-result-parser.js");
const features = [
  { muc_no: 1, ma_dac_tinh: "D01", hang_muc: "Đường kính", danh_nghia: 20, don_vi: "mm" },
  { muc_no: 2, ma_dac_tinh: "L02", hang_muc: "Chiều dài", danh_nghia: 38, don_vi: "mm" },
  { muc_no: 3, ma_dac_tinh: "W03", hang_muc: "Chiều rộng", danh_nghia: 15, don_vi: "mm" },
];
const rows = [
  ["Feature ID", "Description", "Nominal", "LSL", "USL", "Unit", "Sample 1", "Sample 2"],
  ["D01", "Đường kính", 20, 19.95, 20.05, "mm", 20.02, 20.01],
  ["L02", "Chiều dài", 38, 37.8, 38.2, "mm", 38.12, null],
  ["W03", "Chiều rộng", 15, 14.9, 15.1, "mm", 15.15, 15],
];
let parsed = P.parse([{ name: "Measurements", rows }]);
assert.equal(parsed.length, 3);
assert.deepEqual(
  parsed[0].samples.map((s) => s.value),
  [20.02, 20.01],
);
assert.equal(parsed[1].samples.length, 1);
assert.equal(P.match(parsed[0], features).muc_no, 1);
assert.deepEqual(
  parsed[2].samples.map((s) => s.value),
  [15.15, 15],
);
assert.equal(P.match({ id: "", name: "Chiều rộng", nominal: 15 }, features).muc_no, 3);
assert.equal(P.match({ id: "1", name: "", nominal: null }, features).status, "unmatched");
assert.equal(
  P.match({ id: "", name: "Chiều dài", nominal: null }, [...features, { ...features[1], muc_no: 4 }]).status,
  "ambiguous",
);
assert.equal(P.convert(0.8, "in", "mm").value, 20.32);
assert.ok(P.convert(1, "", "mm").error);
assert.ok(P.convert(1, "deg", "mm").error);
assert.equal(P.number(""), null);
assert.equal(P.number("NaN"), null);
assert.equal(P.number("20,02"), 20.02);
const text = P.parse([{ name: "Text", rows: [["Ø20 = 20.02"], ["Chiều dài 38 = 38.12"], ["Chiều rộng 15 = 15.15"]] }]);
assert.deepEqual(
  text.map((c) => c.samples[0].value),
  [20.02, 38.12, 15.15],
);
assert.deepEqual(
  text.map((c) => P.match(c, features).muc_no),
  [1, 2, 3],
);
const transposed = P.parse(
  [
    {
      name: "Horizontal",
      rows: [
        ["No", "D01", "L02"],
        ["Nominal", 20, 38],
        ["Unit", "mm", "mm"],
        ["Sample 1", 20.02, 38.12],
        ["Sample 2", 20.01, 38.0],
      ],
    },
  ],
  { layout: "columns" },
);
assert.equal(transposed.length, 2);
assert.deepEqual(
  transposed[0].samples.map((x) => x.value),
  [20.02, 20.01],
);
const cavity = P.parse([
  {
    name: "Cavity",
    rows: [
      ["No", "Hạng mục", "kích thước", "Min", "Max", "1(cavity1)", "2(cavity1)", "Result"],
      [1, "Kích thước", 157.5, 157, 157.8, 157.07, 157.48, "OK"],
    ],
  },
]);
assert.deepEqual(
  cavity[0].samples.map((s) => s.value),
  [157.07, 157.48],
);
console.log(
  "PASS actual values excluded from nominal/limits, sample identity, no missing-value fabrication, exact/ambiguous matching, text reports, horizontal template and controlled units",
);
