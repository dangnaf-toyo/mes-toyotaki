/* Compact IQC entry workspace. Move existing controls; retain LOT/defect save rules. */
(() => {
  const el = (id) => document.getElementById(id),
    make = (tag, cls) => {
      const e = document.createElement(tag);
      e.className = cls || "";
      return e;
    };
  const page = el("pageIqc"),
    section = el("formSection"),
    form = el("lotForm");
  section.classList.add("iqc-report");
  page.prepend(section);
  section.querySelector(".section-header").classList.add("hidden");
  const top = make("div", "iqc-report-top"),
    side = make("div", "iqc-report-side"),
    optional = make("details", "iqc-report-extra");
  optional.innerHTML = "<summary>Thông tin bổ sung</summary>";
  const extra = make("div", "iqc-extra-grid");
  optional.append(extra);
  const field = (id) => el(id).closest(".field");
  function move(target, ids) {
    for (const id of ids) target.append(field(id));
  }
  move(top, ["receivedDate", "supplier", "productCode", "lotNo", "iqcScope", "productName", "lotQty"]);
  move(side, ["inspector", "inspectionType", "aql", "sampleQty", "result", "okQty", "ngQty", "okPct", "ngPct"]);
  move(extra, ["pickupDate", "completionDate", "location", "status", "note"]);
  side.append(optional);
  const standard = el("iqc-form-standard");
  side.append(standard);
  const oldGrid = form.querySelector(".form-grid");
  oldGrid.replaceWith(top, side);
  const guidance = section.querySelector(":scope > .help");
  guidance.removeAttribute("style");
  guidance.className = "help iqc-rule";
  optional.append(guidance);
  const labels = {
    receivedDate: "Ngày giờ nhận",
    supplier: "Nhà cung cấp *",
    productCode: "Mã sản phẩm *",
    lotNo: "Số LOT *",
    productName: "Tên sản phẩm",
    lotQty: "Số lượng sản phẩm (PCS) *",
    inspector: "Người kiểm *",
    inspectionType: "Tiêu chuẩn *",
    sampleQty: "Rút kiểm",
    pickupDate: "Bắt đầu kiểm",
    completionDate: "Hoàn thành kiểm",
  };
  for (const [id, title] of Object.entries(labels)) {
    const label = field(id).querySelector("label");
    if (label) label.textContent = title;
  }
  el("note").rows = 2;
  // Keep confirmations and their handlers, with shorter buttons and inline status.
  for (const button of form.querySelectorAll(".confirm-ok")) {
    button.textContent = "✓";
    button.title = "Xác nhận thời gian";
    button.setAttribute("aria-label", "Xác nhận thời gian");
  }
  for (const id of ["pickupDate", "completionDate"])
    field(id)
      .querySelectorAll(".help")
      .forEach((e) => e.classList.add("hidden"));
  const actions = form.querySelector(".actions");
  actions.classList.add("iqc-report-actions");
  const reset = actions.querySelector('button[type="button"]');
  reset.textContent = "Làm mới";
  const dashboardButton = make("button", "button btn-secondary");
  dashboardButton.type = "button";
  dashboardButton.textContent = "Dashboard IQC";
  dashboardButton.onclick = () => showPage("stats");
  actions.append(dashboardButton);
  const defectPanel = make("div", "iqc-report-defects"),
    empty = make("div", "iqc-defect-empty");
  empty.innerHTML = "<h3>Lỗi IQC</h3><p>Lưu LOT hoặc mở Sửa ở danh sách để nhập lỗi.</p>";
  const open = make("button", "button btn-secondary");
  open.type = "button";
  open.textContent = "+ Nhập lỗi";
  open.onclick = () => openDefect();
  empty.append(open);
  defectPanel.append(empty);
  const editor = el("defectModal");
  // Retain the internal LOT key used by the defect API, without a second LOT field.
  el("defectLot").closest(".field").classList.add("hidden");
  const lotContext = make("p", "help");
  lotContext.id = "iqcDefectLotContext";
  editor.querySelector(".modal-body").prepend(lotContext);
  let activeLot = null,
    pendingSave = null;
  function context() {
    const lot = dashboard.lots.find((l) => String(l.id) === String(activeLot));
    lotContext.textContent = lot ? "Lỗi của: " + lot.lotNo : "Lỗi của LOT vừa lưu";
  }
  for (const method of ["addLot", "updateLot"]) {
    const save = IqcApi[method].bind(IqcApi);
    IqcApi[method] = async (...args) => {
      const result = await save(...args);
      pendingSave = result.id;
      return result;
    };
  }
  const oldReset = resetForm;
  resetForm = function () {
    oldReset();
    activeLot = pendingSave;
    pendingSave = null;
    closeDefect();
    context();
  };
  editor.classList.remove("modal");
  editor.classList.add("iqc-inline-editor");
  editor.querySelector(".modal-box").removeAttribute("style");
  editor.querySelector(".modal-body > .help").textContent =
    "Mỗi dòng là một loại lỗi và số lượng. Lưu lỗi cho LOT đã chọn.";
  defectPanel.append(editor);
  section.append(defectPanel);
  const oldPopulate = populateDefectLots;
  populateDefectLots = function (selected) {
    const previous = el("defectLot").value;
    oldPopulate(selected);
    if (!selected && !editor.classList.contains("hidden")) {
      if (previous && [...el("defectLot").options].some((o) => o.value === previous)) el("defectLot").value = previous;
      else
        el("defectLot").insertBefore(new Option("-- Chọn LOT đã lưu --", "", true, true), el("defectLot").firstChild);
    }
  };
  // The editor stays outside lotForm: its buttons cannot accidentally submit a LOT.
  const oldOpen = openDefect;
  openDefect = function () {
    const selected = editingId || activeLot;
    if (!selected) return alert("Lưu LOT trước hoặc mở Sửa ở danh sách LOT để nhập lỗi.");
    oldOpen();
    showPage("iqc");
    empty.classList.add("hidden");
    activeLot = selected;
    el("defectLot").value = selected;
    context();
    editor.scrollIntoView({ block: "nearest" });
  };
  const oldEditDefect = editDefect;
  editDefect = function (id) {
    oldEditDefect(id);
    activeLot = el("defectLot").value;
    context();
    showPage("iqc");
    empty.classList.add("hidden");
    editor.scrollIntoView({ block: "nearest" });
  };
  const oldClose = closeDefect;
  closeDefect = function () {
    oldClose();
    empty.classList.remove("hidden");
  };
  // Ancillary tables remain available without crowding the entry screen.
  for (const [target, title] of [
    [el("lotTable"), "Danh sách LOT IQC"],
    [el("historyTable"), "Lịch sử kiểm tra"],
    [el("defectTable"), "Danh sách lỗi đã lưu"],
  ]) {
    const panel = target.closest(".section"),
      details = make("details", "iqc-report-list"),
      summary = make("summary");
    summary.textContent = title;
    panel.before(details);
    details.append(summary, panel);
  }
  const summary = page.querySelector(":scope > .summary");
  if (summary) summary.classList.add("hidden");
  const oldEdit = editLot;
  editLot = async function (id) {
    showPage("iqc");
    await oldEdit(id);
    activeLot = id;
    closeDefect();
    context();
    optional.open = true;
  };
})();
