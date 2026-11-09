// Read-only deployed assets. This script has no database credentials or write operations.
const assert = require("node:assert/strict");
(async () => {
  const base = "https://mes-toyotaki.dangnaf.workers.dev/";
  for (const [file, markers] of [
    ["iqc.html", ["shared/iqc-chemical-entry.js?v=T232", "shared/iqc-material-catalog.js?v=T232"]],
    ["qc-manager.html", ["NVL – Hóa học IQC", "shared/iqc-chemical-standard.js?v=T232"]],
    ["shared/iqc-chemical-entry.js", ["iqc_luu_hoa_hoc", "imageScale: 3", "Tải kết quả phân tích", "createSignedUrl"]],
    ["shared/iqc-chemical-standard.js", ["iqc_nvl_luu_phan_loai", "iqc_tc_luu_hoa_hoc", "IpqcBtkQc.duyet"]],
    ["shared/iqc-material-catalog.js", ["iqc_nvl_danh_muc", "[NVL] "]],
    ["shared/iqc-chemistry.js", ["function evaluate", "function matched", "requiresReview"]],
    ["shared/iqc-chemistry.css", [".iqc-report.iqc-is-chemical", ".iqc-chem-table"]],
    ["shared/mes-iqc-workspace.js", ["Nguyên tố không đạt", "iqcChemicalRates"]],
    ["shared/ipqc-result-reader.js", ["parseSheets = IpqcResultParser.parse", "imageScale = 1"]],
  ]) {
    const response = await fetch(base + file + "?verify=T232-20261109", { headers: { "Cache-Control": "no-cache" } });
    assert.equal(response.status, 200, file);
    const content = await response.text();
    for (const marker of markers) assert.ok(content.includes(marker), file + " missing " + marker);
    console.log("PASS deployed staging " + file);
  }
})().catch((e) => {
  console.error(e.message);
  process.exitCode = 1;
});
