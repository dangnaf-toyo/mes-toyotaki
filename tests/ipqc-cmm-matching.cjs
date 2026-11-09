const assert = require("node:assert/strict"),
  P = require("../shared/ipqc-result-parser.js");
const m = {
  muc_no: 2,
  ma_dac_tinh: null,
  hang_muc: "Đường kính",
  danh_nghia: 25,
  dung_sai_co_dau: true,
  dung_sai_tren: 0.2,
  dung_sai_duoi: 0.1,
  lsl: 25.1,
  usl: 25.2,
  don_vi: "mm",
};
const c = { template: "zeiss-calypso", id: "7", name: "", nominal: 25, upper: 0.2, lower: 0.1, unit: "mm" };
assert.equal(
  P.match(c, [m]).muc_no,
  2,
  "Unique nominal/tolerance/unit evidence, not CMM number 7 = MES row 7",
);
assert.equal(P.match(c, [m, { ...m, muc_no: 7 }]).status, "ambiguous");
assert.equal(
  P.match(c, [{ ...m, don_vi: null }]).status,
  "unmatched",
  "Missing MES unit must be explicitly supplemented in the controller",
);
assert.equal(P.match({ ...c, unit: "" }, [m]).status, "unmatched");
assert.equal(P.match({ ...c, nominal: 26 }, [m]).status, "unmatched");
assert.equal(P.match({ ...c, lower: null }, [m]).status, "unmatched");
assert.equal(P.match({ ...c, unit: "deg" }, [m]).status, "unmatched");
for (const unit of ["mm", " MM ", "[mm]", "(mm)", "ｍｍ", "millimeter", "millimetres"])
  assert.equal(P.convert(25.123456789, unit, "mm").value, 25.123456789);
assert.ok(P.convert(25, "deg", "mm").error);
assert.ok(P.convert(25, "mm", null).error);
console.log(
  "PASS CMM unique signed specification matching, repeated-feature ambiguity, no ordinal mapping, explicit missing units, normalized mm and incompatible units",
);
