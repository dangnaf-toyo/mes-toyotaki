/* In-page OQC workspace; move existing controls without replacing their handlers. */
const OqcWorkspace = (() => {
  const $ = (id) => document.getElementById(id),
    node = (tag, cls, text) => {
      const e = document.createElement(tag);
      e.className = cls || "";
      if (text) e.textContent = text;
      return e;
    };
  const duplicate = "iqc_7f55011aff5e";
  // T149: tên lỗi xếp theo bảng chữ cái tiếng Việt (A, Ă, Â, B, C, D, Đ...)
  const collator = new Intl.Collator("vi", { sensitivity: "base", numeric: true });
  let renderedProcess = null;
  /* Phạm vi áp dụng cho bảng lỗi: khi sửa phiếu lấy phạm vi đã lưu của phiếu (ô chọn được gán sau khi vẽ). */
  function currentScope() {
    const row = editing && dataRows.find((r) => r.id === editing);
    return (row && row.context && row.context.inspection_scope) || $("inspectionScope")?.value || "";
  }
  /* T149: "Kiểm tra sau Sơn" dùng danh mục lỗi sơn (OQC_SON), phạm vi khác dùng danh mục OQC cũ. */
  const processOf = (scope) => (scope === "POST_PAINTING" ? "OQC_SON" : "OQC");
  function visibleDefects(group) {
    const process = processOf(currentScope()),
      row = editing && dataRows.find((r) => r.id === editing),
      saved = new Set(((row && row.defects) || []).map((d) => d.code));
    return catalog
      .filter(
        (d) =>
          d.defect_group === group &&
          (editing || d.code !== duplicate) &&
          ((d.processes || []).includes(process) || saved.has(d.code)), // phiếu cũ: luôn hiện lỗi đã lưu
      )
      .sort((a, b) => collator.compare(a.label, b.label) || a.code.localeCompare(b.code));
  }
  /* T149: thứ tự lỗi theo bảng chữ cái thay cho oqc_defect_order_version; giữ hàm để dashboard gọi không lỗi. */
  async function loadOrder() {}
  /* Vẽ lại bảng lỗi khi đổi phạm vi; giữ SL / chi tiết đã nhập của lỗi vẫn còn hiện. */
  function syncScope() {
    if (processOf(currentScope()) === renderedProcess) return;
    const keep = {};
    document.querySelectorAll("#defects .oqc-ditem").forEach((it) => {
      const q = it.querySelector(".defect");
      keep[q.dataset.code] = { qty: q.value, detail: it.querySelector(".detail").value };
    });
    renderDefects();
    document.querySelectorAll("#defects .oqc-ditem").forEach((it) => {
      const q = it.querySelector(".defect"),
        k = keep[q.dataset.code];
      if (k) {
        q.value = k.qty;
        it.querySelector(".detail").value = k.detail;
        delete keep[q.dataset.code];
      }
    });
    const dropped = Object.values(keep).filter((k) => Number(k.qty) > 0).length;
    if (dropped && $("oqcFormMessage"))
      $("oqcFormMessage").textContent =
        "Đã đổi phạm vi: bỏ số lượng của " + dropped + " lỗi không thuộc danh mục phạm vi mới — kiểm tra lại bảng lỗi.";
    calc();
  }
  function mount({ formPanel, capaDialog }) {
    const form = $("form"),
      top = node("div", "oqc-report-top"),
      middle = node("div", "oqc-report-middle"),
      left = node("section", "oqc-report-left"),
      right = node("section", "oqc-defects-layout"),
      footer = node("div", "oqc-report-footer"),
      photo = node("div", "oqc-report-photos"),
      buttons = node("div", "oqc-report-buttons");
    form.append(top, middle, footer);
    middle.append(left, right);
    footer.append(photo, buttons);
    const field = (id) => $(id)?.closest(".field");
    for (const id of ["date", "shift", "code", "inspectionTask", "inspectionScope"]) top.append(field(id));
    const lot = field("inspectionLot");
    lot.hidden = true;
    form.append(lot);
    const oldName = field("name");
    field("code").append($("name"));
    oldName.remove();
    const labels = {
      date: "Ngày kiểm",
      shift: "Ca",
      code: "Model / tên SP",
      inspectionLot: "LOT",
      inspectionTask: "Task / tem",
      inspectionScope: "Phạm vi",
      inspectorCode: "Người kiểm",
      oqcInspectionHours: "Số giờ kiểm",
      total: "Đã kiểm",
      ng: "NG",
      ok: "OK",
      okPct: "% OK",
      ngPct: "% NG",
      plan: "KH / Đã kiểm / Còn lại",
    };
    for (const [id, label] of Object.entries(labels))
      if (field(id)?.querySelector("label")) field(id).querySelector("label").textContent = label;
    for (const id of ["inspectorCode", "oqcInspectionHours", "total", "ok", "ng", "okPct", "ngPct", "plan"])
      left.append(field(id));
    const extra = node("details", "oqc-extra-info");
    extra.append(node("summary", "", "Thông tin bổ sung"));
    for (const id of ["inspectorName", "note"]) extra.append(field(id));
    extra.append($("oqc-standard"), $("oqcAdditionalLabor"));
    left.append(extra, $("oqcLaborTotal"));
    $("oqcInspectionHours").title =
      "Giờ của người kiểm đang chọn dành riêng cho báo cáo/model này; cộng trực tiếp vào giờ công.";
    const defectBox = node("div");
    defectBox.id = "defects";
    $("defects").replaceWith(defectBox);
    right.append(defectBox);
    const others = node("section", "oqc-defect-group oqc-other-group"),
      otherTitle = node("div", "oqc-group-heading");
    otherTitle.append(node("b", "", "Lỗi khác"), $("addOtherDefect"));
    others.append(otherTitle);
    const table = node("table", "defect-table oqc-other-table");
    table.innerHTML = "<thead><tr><th>Nhóm</th><th>Tên lỗi</th><th>Chi tiết</th><th>Số lượng</th></tr></thead>";
    table.append($("otherDefects"));
    others.append(table);
    right.append(others);
    const oldRender = renderDefects;
    renderDefects = function () {
      const groups = [...new Set(["NG ngoại quan", "NG kích thước", "NG khác", ...catalog.map((d) => d.defect_group)])];
      renderedProcess = processOf(currentScope());
      $("defects").replaceChildren();
      let k = 0;
      for (const group of groups) {
        const rows = visibleDefects(group);
        if (!rows.length) continue;
        /* T139: mỗi lỗi 1 ô gọn (tên | chi tiết | SL), xếp nhiều cột để cả bảng lỗi vừa 1 màn hình */ const box = node(
            "section",
            "oqc-dgroup",
          ),
          heading = node("h3", "", group),
          grid = node("div", "oqc-dgrid");
        grid.innerHTML = rows
          .map((d) => {
            const id = "oqcDq" + k++;
            return (
              '<div class="oqc-ditem"><label for="' +
              id +
              '" title="' +
              E(d.label) +
              '">' +
              E(d.label) +
              '</label><input class="detail" data-code="' +
              E(d.code) +
              '" placeholder="chi tiết" aria-label="Chi tiết ' +
              E(d.label) +
              '"><input class="defect" id="' +
              id +
              '" data-code="' +
              E(d.code) +
              '" data-label="' +
              E(d.label) +
              '" data-group="' +
              E(group) +
              '" type="number" min="0" step="1" value="0" inputmode="numeric" aria-label="Số lượng ' +
              E(d.label) +
              '"></div>'
            );
          })
          .join("");
        box.append(heading, grid);
        $("defects").append(box);
      }
      document.querySelectorAll("#defects .defect").forEach((e) => {
        e.oninput = calc;
        e.onfocus = () => e.select();
      });
      markDefects();
    };
    const guide = $("oqcDefectGuide");
    guide.title = guide.textContent;
    guide.textContent = "ⓘ Mỗi PCS NG ghi một lỗi chính";
    guide.className = "oqc-guide";
    left.append(guide);
    const total = node("div", "oqc-defect-total", "Tổng lỗi: ");
    const count = node("span");
    count.id = "defectTotal";
    count.textContent = $("defectTotal").textContent;
    $("defectTotal").remove();
    total.append(count);
    left.append(total);
    const photosLabel = node("label", "", "Ảnh lỗi");
    photosLabel.htmlFor = "oqcReportPhotos";
    photo.append(photosLabel, $("oqcReportPhotos"), $("oqcReportPhotoList"));
    $("oqcReportPhotos").title = "Chọn tối đa 10 ảnh. Bấm ảnh đã lưu để phóng to.";
    buttons.append($("save"));
    const reset = node("button", "btn secondary", "Làm mới");
    reset.type = "button";
    reset.onclick = () => resetForm();
    buttons.append(reset);
    const back = node("button", "btn secondary", "Dashboard OQC");
    back.type = "button";
    back.onclick = () => document.getElementById("oqcDashboardHome").click();
    buttons.append(back);
    footer.append(photo, buttons, $("oqcFormMessage"));
    const policy = $("oqcReportPolicy");
    policy.className = "oqc-guide";
    left.append(policy);
    middle.append(left, right);
    form.replaceChildren(top, middle, footer, lot);
    formPanel.querySelector(".body").replaceChildren(form);
    formPanel.querySelector(".head").remove();
    const capaBody = capaDialog.querySelector(".body"),
      layout = node("div", "oqc-capa-layout"),
      capaLeft = node("section", "oqc-capa-left"),
      capaRight = node("section", "oqc-capa-right");
    capaBody.append(layout);
    layout.append(capaLeft, capaRight);
    capaLeft.append(capaBody.querySelector(".grid"), $("oqcCapaSteps").closest(".oqc-data-scroll"), $("oqcCapaAdd"));
    capaLeft.querySelector("th").textContent = "Tên công đoạn";
    capaLeft.querySelector("th:last-child").textContent = "Thao tác";
    capaRight.innerHTML =
      '<div class="field"><label for="oqcPlanningHours">Giờ làm việc/người/ngày</label><input id="oqcPlanningHours" inputmode="decimal" autocomplete="off" placeholder="Nhập số giờ"></div><div class="field"><label for="oqcTargetEfficiency">Hiệu suất mục tiêu (%)</label><input id="oqcTargetEfficiency" inputmode="decimal" autocomplete="off" placeholder="Nhập %"></div><div class="oqc-capa-metrics"><p>Tổng giây/PCS <b id="oqcSeconds">Chưa đủ dữ liệu</b></p><p>CAPA chuẩn/giờ <b id="oqcHourly">Chưa đủ dữ liệu</b></p><p>CAPA kế hoạch/người/ngày <b id="oqcDaily">Chưa đủ dữ liệu</b></p></div>';
    capaRight.title =
      "CAPA chuẩn = 3.600 / tổng giây. CAPA kế hoạch = CAPA chuẩn × giờ làm việc × hiệu suất mục tiêu / 100; làm tròn xuống PCS. Cấu hình dùng chung OQC theo ngày áp dụng; báo cáo đã lưu giữ phiên bản riêng.";
    capaRight.append($("oqcCapaPreview"), $("oqcCapaSave"), $("oqcCapaMessage"));
    $("oqcCapaSave").textContent = "Lưu áp dụng";
    const history = node("details", "oqc-capa-history");
    history.append(node("summary", "", "Lịch sử phiên bản"), $("oqcCapaHistory"));
    const configHistory = node("div");
    configHistory.id = "oqcConfigHistory";
    history.append(configHistory);
    layout.append(capaLeft, capaRight);
    capaBody.replaceChildren(layout, history);
    capaDialog.querySelector(".head").remove();
    for (const id of ["oqcPlanningHours", "oqcTargetEfficiency"]) $(id).disabled = true;
    for (const field of form.querySelectorAll(".field"))
      for (const hint of field.querySelectorAll("small")) {
        field.title = hint.textContent;
        hint.hidden = true;
      }
    // T139: tô ô lỗi đã nhập SL; chiều cao form = phần còn lại của màn hình (menu/banner/header cao thấp tuỳ máy) để nút Lưu luôn thấy.
    const oldCalc = calc;
    calc = function () {
      const r = oldCalc.apply(this, arguments);
      markDefects();
      return r;
    };
    const fit = () => {
      if (!form.offsetParent) return;
      const top = form.getBoundingClientRect().top + window.scrollY;
      form.style.setProperty("--oqc-top", Math.round(top) + "px");
    };
    window.addEventListener("resize", fit);
    if (window.ResizeObserver) new ResizeObserver(fit).observe(form);
    setTimeout(fit, 0);
    // T149: bảng lỗi theo phạm vi — đổi phạm vi, làm mới form hay mở phiếu sửa đều vẽ lại khi phạm vi khác danh mục đang hiện.
    $("inspectionScope").addEventListener("change", syncScope);
    const oldReset = resetForm;
    resetForm = function () {
      const r = oldReset.apply(this, arguments);
      syncScope();
      return r;
    };
    const oldEdit = editRow;
    editRow = function () {
      const r = oldEdit.apply(this, arguments);
      syncScope();
      return r;
    };
    syncScope();
  }
  function markDefects() {
    document.querySelectorAll("#defects .oqc-ditem").forEach((it) => {
      const q = it.querySelector(".defect");
      it.classList.toggle("has", Number(q && q.value) > 0);
    });
  }
  return { mount, loadOrder };
})();
