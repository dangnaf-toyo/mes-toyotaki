const assert = require("node:assert/strict"),
  G = require("../shared/ipqc-gc-standard.js");
for (const [nominal, upper, lower, lsl, usl] of [
  ["20", "+0.05", "-0.05", "19.95", "20.05"],
  ["14.6", "+0.3", "+0.1", "14.7", "14.9"],
  ["14.6", "-0.1", "-0.3", "14.3", "14.5"],
  ["20", "0", "-0.1", "19.9", "20"],
  ["20", "+0.1", "0", "20", "20.1"],
]) {
  const row = {
    kieu: "so",
    danh_nghia: nominal,
    dung_sai_tren: upper,
    dung_sai_duoi: lower,
    dung_sai_co_dau: true,
  };
  assert.deepEqual(G.bounds(row), { lsl, usl });
  assert.equal(G.validate(row), "");
}
assert.equal(G.add("0.1", "0.2"), "0.3");
assert.equal(G.add("1.000001", "-0.000002"), "0.999999");
assert.equal(G.add("14,6", "+0,1"), "14.7");
assert.equal(G.add("20", ""), null);
assert.equal(G.add("", "0"), null);
assert.equal(
  G.dimension({ danh_nghia: "14.6", dung_sai_tren: ".3", dung_sai_duoi: ".1", dung_sai_co_dau: true }),
  "14.6 (+0.3/+0.1)",
);
const old = { kieu: "so", danh_nghia: 20, dung_sai_tren: 0.05, dung_sai_duoi: 0.05 };
assert.deepEqual(G.bounds(old), { lsl: "19.95", usl: "20.05" });
assert.equal(old.dung_sai_duoi, 0.05);
assert.deepEqual(G.bounds({ ...old, lsl: 19.94, usl: 20.04 }), { lsl: "19.94", usl: "20.04" });
assert.deepEqual(G.bounds({ ...old, dung_sai_co_dau: true, dung_sai_duoi: null }), {
  lsl: null,
  usl: "20.05",
});
assert.equal(
  G.validate({ ...old, dung_sai_co_dau: true, dung_sai_duoi: 0.2 }),
  "LSL không được lớn hơn USL.",
);
console.log(
  "PASS signed/legacy deviations, all five drawing examples, exact decimal addition, empty/zero distinction and inverted-limit guard",
);
