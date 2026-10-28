/* IQC workspace reuses MES panels, shared QC masters and the existing LOT workflows. */
const IqcWorkspace = (() => {
  "use strict";
  const scopes = ["Bán thành phẩm", "Linh kiện đầu vào", "Mạ", "In", "Anode", "Đúc", "Thành phẩm"];
  const suppliers = ["BRV", "HANIN", "VIỆT PHÁP", "ASAHI", "MINGANN"];
  const node = (tag, text) => {
    const e = document.createElement(tag);
    if (text != null) e.textContent = text;
    return e;
  };
  const scope = node("div");
  scope.className = "field";
  scope.innerHTML =
    '<label for="iqcScope">Phạm vi *</label><select id="iqcScope" required><option value="">-- Chọn phạm vi --</option>' +
    scopes.map((s) => "<option>" + s + "</option>").join("") +
    "</select>";
  $("supplier").closest(".field").after(scope);
  const style = node("style");
  style.textContent =
    ".iqc-toolbar{display:flex;gap:8px;align-items:end;flex-wrap:wrap;padding:12px 14px}.iqc-toolbar label{display:flex;flex-direction:column;gap:4px;font-size:11px;color:var(--text-muted)}.iqc-toolbar input,.iqc-toolbar select{width:170px}.iqc-charts{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}.iqc-chart{padding:14px;overflow:auto}.iqc-chart table{min-width:280px}.iqc-rates{display:flex;gap:24px;padding:12px 14px}.iqc-chart-bar{display:flex;height:12px;background:var(--bg-sunken);min-width:70px}.iqc-chart-bar i{background:var(--run-fg)}.iqc-chart-bar b{background:var(--alarm-fg)}@media(max-width:900px){.iqc-charts{grid-template-columns:1fr}.iqc-toolbar input,.iqc-toolbar select{width:145px}}";
  document.head.append(style);
  function filters(prefix, full) {
    const bar = node("div");
    bar.className = "iqc-toolbar";
    const fields = [
      ["From", "Từ ngày", "date"],
      ["To", "Đến ngày", "date"],
      ["Product", "Mã / tên SP", "search"],
    ];
    for (const [key, title, type] of fields) {
      const label = node("label", title),
        input = node("input");
      input.id = prefix + key;
      input.type = type;
      if (key === "Product") input.setAttribute("list", "qc02-products");
      label.append(input);
      bar.append(label);
    }
    if (full)
      for (const [key, title, values] of [
        ["Supplier", "Nhà cung cấp", suppliers],
        ["Scope", "Phạm vi", scopes],
        ["Inspector", "Người kiểm", []],
        ["Result", "Kết quả", ["OK", "NG", "Chưa có"]],
      ]) {
        const label = node("label", title),
          input = node(key === "Inspector" ? "input" : "select");
        input.id = prefix + key;
        if (key === "Inspector") {
          input.type = "search";
          input.setAttribute("list", "qc02-employees");
        } else {
          input.append(new Option("Tất cả", ""));
          for (const v of values) input.append(new Option(v, v));
        }
        label.append(input);
        bar.append(label);
      }
    const clear = node("button", "Xóa bộ lọc");
    clear.className = "button btn-secondary";
    clear.onclick = () => {
      bar.querySelectorAll("input,select").forEach((e) => (e.value = ""));
      refreshViews();
    };
    bar.append(clear);
    bar.addEventListener("input", refreshViews);
    bar.addEventListener("change", refreshViews);
    return bar;
  }
  const lotSection = $("lotTable").closest(".section");
  lotSection.querySelector(".table-wrap").before(filters("iqcFilter", true));
  const historyScope = node("select");
  historyScope.id = "iqcHistoryScope";
  historyScope.append(new Option("Tất cả phạm vi", ""));
  for (const scope of scopes) historyScope.append(new Option(scope, scope));
  const historyLabel = node("label", "Phạm vi kiểm");
  historyLabel.append(historyScope);
  $("historyProductCode").before(historyLabel);
  let historyRows = [];
  const baseHistory = renderHistory;
  renderHistory = function (rows) {
    historyRows = rows;
    baseHistory(rows.filter((l) => !historyScope.value || l.scope === historyScope.value));
  };
  historyScope.onchange = () => renderHistory(historyRows);
  const baseClearHistory = clearHistory;
  clearHistory = function () {
    historyScope.value = "";
    historyRows = [];
    baseClearHistory();
  };
  const dash = node("div");
  dash.id = "iqcDashboard";
  dash.className = "container hidden";
  dash.append(filters("iqcDash", false));
  const cards = node("div");
  cards.className = "summary";
  for (const [key, label] of Object.entries({
    total: "Tổng LOT IQC",
    waiting: "LOT chờ kiểm",
    checking: "LOT đang kiểm",
    done: "LOT đã kiểm",
    ok: "LOT OK",
    ng: "LOT NG",
  })) {
    const card = node("div");
    card.className = "card";
    card.innerHTML =
      '<div class="card-title">' + label + '</div><div class="card-number" id="iqcDash-' + key + '">0</div>';
    cards.append(card);
  }
  dash.append(cards);
  const rates = node("div");
  rates.className = "section iqc-rates";
  rates.id = "iqcRates";
  dash.append(rates);
  const charts = node("div");
  charts.className = "iqc-charts";
  for (const [key, title] of [
    ["Date", "OK / NG theo thời gian"],
    ["Supplier", "Theo nhà cung cấp"],
    ["Scope", "Theo phạm vi"],
  ]) {
    const chart = node("div");
    chart.className = "section iqc-chart";
    chart.append(node("h3", title));
    if (key === "Date") {
      const interval = node("select");
      interval.id = "iqcInterval";
      interval.append(new Option("Theo ngày", "day"), new Option("Theo tháng", "month"));
      interval.onchange = refreshViews;
      chart.append(interval);
    }
    const target = node("div");
    target.id = "iqcChart" + key;
    chart.append(target);
    charts.append(chart);
  }
  dash.append(charts);
  const note = node(
    "div",
    "Tỷ lệ OK / NG tính trên LOT đã có kết quả. Ngày thống kê là ngày nhận hàng (GMT+7). LOT cũ chưa có phạm vi được thống kê riêng. Tự làm mới mỗi 15 giây.",
  );
  note.className = "help";
  dash.append(note);
  const status = node("p");
  status.id = "iqcRefreshStatus";
  status.setAttribute("role", "status");
  dash.append(status);
  $("pageStats").after(dash);
  function csv(rows) {
    const data = [
      [
        "Ngày nhận",
        "Mã sản phẩm",
        "Tên sản phẩm",
        "LOT",
        "Nhà cung cấp",
        "Phạm vi",
        "ID người kiểm",
        "Người kiểm",
        "Trạng thái",
        "Kết quả",
        "SL LOT",
      ],
      ...rows.map((l) => [
        l.receivedDate,
        l.productCode,
        l.productName,
        l.lotNo,
        l.supplier,
        l.scope || "—",
        l.inspectorId,
        l.inspectorName || l.inspector,
        l.status,
        l.result,
        l.lotQty,
      ]),
    ];
    return (
      "\ufeff" +
      data
        .map((row) =>
          row
            .map(
              (v) =>
                '"' +
                String(v ?? "")
                  .replace(/^[=+@\-]/, "'$&")
                  .replaceAll('"', '""') +
                '"',
            )
            .join(","),
        )
        .join("\r\n")
    );
  }
  for (const [prefix, bar] of [
    ["iqcFilter", lotSection.querySelector(".iqc-toolbar")],
    ["iqcDash", dash.querySelector(".iqc-toolbar")],
  ]) {
    const exportButton = node("button", "Xuất báo cáo CSV");
    exportButton.className = "button btn-secondary";
    exportButton.onclick = () => {
      if (!source) return;
      const url = URL.createObjectURL(
          new Blob([csv(filtered(source.lots, prefix, prefix === "iqcFilter"))], { type: "text/csv;charset=utf-8" }),
        ),
        a = node("a");
      a.href = url;
      a.download = "bao-cao-iqc.csv";
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    };
    bar.append(exportButton);
  }
  const oldShow = showPage;
  showPage = function (p) {
    oldShow(p === "stats" ? "iqc" : p);
    currentPage = p;
    $("pageIqc").classList.toggle("hidden", p !== "iqc");
    $("pageStats").classList.add("hidden");
    dash.classList.toggle("hidden", p !== "stats");
    $("tabIqc").classList.toggle("active", p === "iqc");
    $("tabStats").classList.toggle("active", p === "stats");
    if (p === "stats") loadDashboard();
  };
  const day = (l) => l.receivedInput?.slice(0, 10) || "";
  function filtered(rows, prefix, full) {
    const from = val(prefix + "From"),
      to = val(prefix + "To"),
      product = val(prefix + "Product")
        .trim()
        .toLocaleLowerCase("vi");
    if (from && to && from > to) return [];
    return rows.filter(
      (l) =>
        (!from || day(l) >= from) &&
        (!to || day(l) <= to) &&
        (!product ||
          (l.productCode + " " + l.productName + (full ? " " + (l.scope || "") : ""))
            .toLocaleLowerCase("vi")
            .includes(product)) &&
        (!full ||
          ((!val(prefix + "Supplier") || l.supplier === val(prefix + "Supplier")) &&
            (!val(prefix + "Scope") || l.scope === val(prefix + "Scope")) &&
            (!val(prefix + "Inspector") ||
              (l.inspector + " " + l.inspectorName)
                .toLocaleLowerCase("vi")
                .includes(val(prefix + "Inspector").toLocaleLowerCase("vi"))) &&
            (!val(prefix + "Result") || (l.result || "Chưa có") === val(prefix + "Result")))),
    );
  }
  function summarize(lots) {
    return {
      total: lots.length,
      waiting: lots.filter((l) => ["Chưa lấy hàng", "Đang chờ kiểm"].includes(l.status)).length,
      checking: lots.filter((l) => l.status === "Đang kiểm tra").length,
      done: lots.filter((l) => l.status === "Đã kiểm tra").length,
      ok: lots.filter((l) => l.result === "OK").length,
      ng: lots.filter((l) => l.result === "NG").length,
    };
  }
  function chart(target, rows, key) {
    const groups = new Map();
    for (const l of rows) {
      const k = key(l) || "—";
      const g = groups.get(k) || { total: 0, ok: 0, ng: 0 };
      g.total++;
      if (l.result === "OK") g.ok++;
      if (l.result === "NG") g.ng++;
      groups.set(k, g);
    }
    const table = node("table"),
      head = node("thead");
    head.innerHTML = "<tr><th>Nhóm</th><th>LOT</th><th>OK</th><th>NG</th><th>OK / NG</th></tr>";
    table.append(head);
    const body = node("tbody");
    for (const [k, g] of [...groups].sort(([a], [b]) => a.localeCompare(b, "vi"))) {
      const row = node("tr");
      for (const v of [k, g.total, g.ok, g.ng]) row.append(node("td", String(v)));
      const bar = node("td");
      bar.innerHTML =
        '<div class="iqc-chart-bar"><i style="width:' +
        (g.ok / g.total) * 100 +
        '%"></i><b style="width:' +
        (g.ng / g.total) * 100 +
        '%"></b></div>';
      row.append(bar);
      body.append(row);
    }
    table.append(body);
    target.replaceChildren(groups.size ? table : node("p", "Không có dữ liệu trong khoảng lọc."));
  }
  const oldRender = renderDashboard;
  let source = null;
  function refreshViews() {
    if (!source) return;
    oldRender({ ...source, lots: filtered(source.lots, "iqcFilter", true) });
    dashboard = source;
    populateDefectLots();
    const rows = filtered(source.lots, "iqcDash", false),
      s = summarize(rows);
    for (const k of Object.keys(s)) $("iqcDash-" + k).textContent = s[k];
    const checked = s.ok + s.ng;
    $("iqcRates").textContent =
      "Tỷ lệ OK: " +
      (checked ? ((100 * s.ok) / checked).toFixed(2) : "0.00") +
      "% · Tỷ lệ NG: " +
      (checked ? ((100 * s.ng) / checked).toFixed(2) : "0.00") +
      "% · Có kết quả: " +
      checked +
      " / " +
      s.total +
      " LOT";
    chart($("iqcChartDate"), rows, (l) => day(l).slice(0, val("iqcInterval") === "month" ? 7 : 10));
    chart($("iqcChartSupplier"), rows, (l) => l.supplier);
    chart($("iqcChartScope"), rows, (l) => l.scope);
  }
  renderDashboard = function (d) {
    source = d;
    refreshViews();
  };
  // Keep the existing inspector string format; store identity and name separately as well.
  async function identity(value, previous) {
    const rows = await Qc02Data.employees();
    const match = rows.find((r) => r.code + "_" + r.name === value);
    if (match) return { inspector: value, inspectorId: match.code, inspectorName: match.name };
    if (previous && previous.inspector === value)
      return {
        inspector: value,
        inspectorId: previous.inspectorId || null,
        inspectorName: previous.inspectorName || null,
      };
    throw Error("Chọn người kiểm từ danh sách nhân sự / tài khoản chung.");
  }
  async function prepare(data, previous) {
    if (!suppliers.includes(data.supplier)) throw Error("Chọn nhà cung cấp trong 5 lựa chọn.");
    if (!scopes.includes(data.scope)) throw Error("Phạm vi là bắt buộc.");
    const products = await Qc02Data.readAll("master_products"),
      product = products.find((r) => r.ma_sp === data.productCode);
    if (!product && previous?.productCode !== data.productCode) throw Error("Chọn mã sản phẩm từ danh mục chung.");
    return { ...data, productName: product?.ten_sp ?? data.productName, ...(await identity(data.inspector, previous)) };
  }
  const add = IqcApi.addLot.bind(IqcApi),
    update = IqcApi.updateLot.bind(IqcApi),
    complete = IqcApi.completeLot.bind(IqcApi);
  IqcApi.addLot = async (data) => add(await prepare(data));
  IqcApi.updateLot = async (id, data) => update(id, await prepare(data, await IqcApi.getLot(id)));
  IqcApi.completeLot = async (id, data) =>
    complete(id, { ...data, ...(await identity(data.inspector, await IqcApi.getLot(id))) });
  let busy = false;
  async function refresh() {
    if (busy || document.hidden) return;
    busy = true;
    try {
      const d = await IqcApi.getDashboardData();
      renderDashboard(d);
      status.textContent =
        "Cập nhật: " + new Date().toLocaleString("vi-VN", { timeZone: "Asia/Bangkok", hour12: false });
      status.className = "help";
      await Promise.all([refreshEmployees(), refreshProducts()]);
    } catch (e) {
      status.textContent =
        "Không làm mới được dữ liệu IQC. Kiểm tra kết nối và bấm Làm mới; số liệu có thể chưa mới nhất.";
      status.className = "ng";
      throw e;
    } finally {
      busy = false;
    }
  }
  async function refreshEmployees() {
    const rows = await Qc02Data.employees();
    const list = $("qc02-employees");
    if (list) {
      list.replaceChildren(...rows.map((r) => new Option(r.name, r.code + "_" + r.name)));
    }
  }
  async function refreshProducts() {
    const rows = await Qc02Data.readAll("master_products"),
      list = $("qc02-products");
    if (list) list.replaceChildren(...rows.map((r) => new Option(r.ten_sp || r.ma_sp, r.ma_sp)));
    const selected = rows.find((r) => r.ma_sp === val("productCode"));
    if (selected) $("productName").value = selected.ten_sp || "";
  }
  $("productCode").addEventListener("change", () =>
    refreshProducts().catch((e) => console.error("Không tải được danh mục sản phẩm", e)),
  );
  const safeRefresh = () => refresh().catch((e) => console.error("Không làm mới được IQC", e));
  setInterval(safeRefresh, 15000);
  window.addEventListener("focus", safeRefresh);
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) safeRefresh();
  });
  if (sb.channel)
    sb.channel("iqc-workspace")
      .on("postgres_changes", { event: "*", schema: "public", table: "iqc_lots" }, safeRefresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "iqc_defects" }, safeRefresh)
      .subscribe();
  safeRefresh();
  return { scopes, suppliers, summarize, refresh, refreshViews, csv, getSnapshot: () => source };
})();
