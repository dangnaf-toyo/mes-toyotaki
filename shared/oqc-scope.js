/* Display/filter values only. Persisted scope and subprocess remain separate. */
(function (root) {
  "use strict";
  const outsourced = "POST_OUTSOURCED_MACHINING";
  const current = ["FULL_POST_MACHINING", "POST_PAINTING", outsourced];
  const processes = { ma: "Mạ", in: "In", anode: "Anode" };
  const labels = {
    "": "Chưa xác định (dữ liệu cũ)",
    FULL_POST_MACHINING: "Kiểm tra sau gia công",
    POST_PAINTING: "Kiểm tra sau Sơn",
    POST_OUTSOURCED_MACHINING: "Kiểm tra sau Gia Công ngoài",
    SAMPLING: "Kiểm lấy mẫu (dữ liệu cũ)",
    OTHER: "Phạm vi khác (dữ liệu cũ)",
  };
  function process(scope, value) {
    return scope === outsourced && Object.hasOwn(processes, value) ? value : "";
  }
  function label(scope, value) {
    const base = labels[scope || ""] || "Phạm vi cũ: " + scope;
    const detail = process(scope, value);
    return detail ? base + " - " + processes[detail] : base;
  }
  function recordLabel(row) {
    return label(row.context?.inspection_scope, row.cong_doan_gia_cong_ngoai);
  }
  function matches(row, filter) {
    const scope = row.context?.inspection_scope || "";
    if (filter === "ALL") return true;
    if (filter === "UNKNOWN") return !scope;
    if (filter === "LEGACY") return !!scope && !current.includes(scope);
    const [base, detail] = String(filter).split(":");
    return (
      scope === base &&
      (!detail || (base === outsourced && Object.hasOwn(processes, detail) && row.cong_doan_gia_cong_ngoai === detail))
    );
  }
  const filters = [
    ["ALL", "Tất cả kết quả"],
    ...current.map((value) => [value, label(value)]),
    ...Object.keys(processes).map((value) => [outsourced + ":" + value, label(outsourced, value)]),
    ["UNKNOWN", "Chưa xác định (dữ liệu cũ)"],
    ["LEGACY", "Phạm vi cũ khác"],
  ];
  const api = { outsourced, current, processes, labels, process, label, recordLabel, matches, filters };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.OqcScope = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
