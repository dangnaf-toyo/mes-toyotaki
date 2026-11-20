const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const sandbox = {
  sb: { rpc: async () => ({ data: {
    san_pham: [{ code: "SP-01", name: "Sản phẩm" }, { code: "SHARED", name: "SP trùng" }],
    nvl: [{ code: "NVL-01", name: "Vật tư", supplierCode: "NCC-01" }, { code: "SHARED", name: "NVL trùng" }],
  } }) },
};
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync("shared/iqc-material-catalog.js", "utf8") + "\nthis.catalog = IqcMaterialCatalog;", sandbox);
(async () => {
  await sandbox.catalog.load();
  assert.equal(sandbox.catalog.resolve("sp-01").name, "Sản phẩm");
  assert.equal(sandbox.catalog.resolve("NVL-01").name, "Vật tư");
  assert.equal(sandbox.catalog.resolve("ncc-01").code, "NVL-01");
  assert.equal(sandbox.catalog.resolve("SHARED"), null);
  assert.equal(sandbox.catalog.resolve("[NVL] SHARED").kind, "nvl");
  assert.equal(sandbox.catalog.resolve("[SP] SHARED").kind, "san_pham");
  assert.equal(sandbox.catalog.resolve("không có"), null);
  console.log("IQC catalog exact resolution: OK");
})().catch((error) => { console.error(error); process.exitCode = 1; });
