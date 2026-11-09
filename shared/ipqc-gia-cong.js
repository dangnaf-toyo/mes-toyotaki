/* Machining IPQC: shared versioned standards, server judgement, snapshot dashboards. */
const IpqcGiaCong = (() => {
  const legacy = new URLSearchParams(location.search);
  if (legacy.has("standard")) {
    const target = new URL("qc-manager.html", location.href);
    target.search = new URLSearchParams({
      tab: "tieuchuan",
      cd: "gia_cong",
      type: "btk",
      ma: legacy.get("standard"),
      version: legacy.get("version") || "",
    });
    location.replace(target.href);
    return {};
  }
  const $ = (id) => document.getElementById(id),
    S = IpqcSpc,
    E = S.esc;
  const today = () => new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Ho_Chi_Minh" }).format(new Date());
  const stamp = (value) =>
    value
      ? new Date(value).toLocaleString("vi-VN", { timeZone: "Asia/Ho_Chi_Minh", hour12: false })
      : "Chưa ghi nhận";
  const inspectionDay = (row) =>
    row.ngay_kiem ||
    new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Ho_Chi_Minh" }).format(new Date(row.thoi_diem));
  const dayLabel = (value) => (value ? value.split("-").reverse().join("/") : "—");
  let products = [],
    machines = [],
    rights = {};
  let measureSerial = 0,
    measureRows = [],
    measureStandard = null,
    measureEntry = null,
    measureImport = null,
    measureSaving = false,
    measureLoading = false,
    measureDay = "",
    measureRequest = null,
    results = [],
    rowLimit = 100,
    dashboardSerial = 0;
  function notify(text, error = false) {
    $("gcMessage").textContent = text;
    $("gcMessage").className = "notice " + (error ? "bad" : "good");
    $("gcErrorDetails").hidden = true;
  }
  function fail(error) {
    console.error(error);
    notify(
      error.code === "P0001"
        ? error.message
        : error.code === "42501"
          ? "Bạn chưa có quyền thực hiện thao tác này. Liên hệ quản lý QC."
          : "Chưa thực hiện được. Xem chi tiết lỗi.",
      true,
    );
    $("gcErrorDetails").hidden = false;
    $("gcErrorDetails").querySelector("pre").textContent = [
      error.code,
      error.message,
      error.details,
      error.hint,
    ]
      .filter(Boolean)
      .join("\n");
  }
  async function rpc(name, args) {
    const r = await sb.rpc(name, args);
    if (r.error) throw r.error;
    if (r.data?.ok === false) throw Object.assign(Error(r.data.error), { code: "P0001" });
    return r.data;
  }
  function table(target, headers, data) {
    if (!data.length) {
      target.innerHTML = '<p class="muted">Chưa có dữ liệu</p>';
      return;
    }
    target.innerHTML =
      "<table><thead><tr>" +
      headers.map((h) => "<th>" + E(h) + "</th>").join("") +
      "</tr></thead><tbody>" +
      data.map((row) => "<tr>" + row.map((v) => "<td>" + E(v ?? "") + "</td>").join("") + "</tr>").join("") +
      "</tbody></table>";
  }
  function numeric(value) {
    return value === "" || value == null ? null : Number(String(value).replace(",", "."));
  }
  function bounds(row) {
    return IpqcGcStandard.numericBounds(row);
  }
  function changeTab(tab) {
    document.querySelectorAll("[data-panel]").forEach((p) => (p.hidden = p.dataset.panel !== tab));
    document
      .querySelectorAll("[data-tab]")
      .forEach((b) => b.classList.toggle("active", b.dataset.tab === tab));
    if (tab === "dashboard") loadDashboard().catch(fail);
  }
  document.querySelectorAll("[data-tab]").forEach((b) => (b.onclick = () => changeTab(b.dataset.tab)));
  const stepOf = (b) => String(b?.buoc_gia_cong || "").trim();
  function measureStep() {
    const v = $("gcMeasureStep").value;
    return $("gcMeasureStepWrap").hidden || !v ? null : v.slice(2);
  }
  function renderSteps(list, chosen) {
    $("gcMeasureStepWrap").hidden = list.length < 2;
    $("gcMeasureStep").innerHTML =
      '<option value="">— Chọn bước —</option>' +
      list.map((s) => '<option value="s:' + E(s) + '">' + E(s || "Không ghi bước") + "</option>").join("");
    $("gcMeasureStep").value = chosen === null ? "" : "s:" + chosen;
  }
  async function loadMeasureStandard(forceReset = false) {
    const serial = ++measureSerial,
      model = $("gcMeasureProduct").value.trim(),
      day = $("gcInspectionDate").value,
      step = measureStep();
    // Native blur can repeat a Model change after its data already loaded. Do not
    // disable the destination input while focus is moving into the measurement grid.
    if (
      !forceReset &&
      measureEntry &&
      measureStandard?.ma_sp === model &&
      measureDay === day &&
      (step === null || stepOf(measureStandard) === step)
    ) {
      measureLoading = false;
      $("gcMeasureInput").disabled = false;
      return;
    }
    measureLoading = true;
    $("gcMeasureInput").disabled = true;
    try {
      const resolved =
        model && day
          ? await rpc("ipqc_gc_tieu_chuan_theo_ngay", { p_ma_sp: model, p_ngay_kiem: day, p_buoc: step })
          : { status: "none", message: model ? "Chọn ngày kiểm." : "Chọn Model." };
      if (serial !== measureSerial) return;
      const selected = resolved.status === "ok" ? resolved.btk : null;
      if (!forceReset && selected && String(selected.id) === String(measureStandard?.id) && measureEntry) {
        measureDay = day;
        return;
      }
      if (
        !forceReset &&
        measureEntry?.status().filled &&
        !confirm("Đổi tiêu chuẩn sẽ xóa kết quả chưa lưu. Tiếp tục?")
      ) {
        $("gcMeasureProduct").value = measureStandard.ma_sp;
        $("gcInspectionDate").value = measureDay;
        $("gcMeasureStep").value = "s:" + stepOf(measureStandard);
        return;
      }
      renderSteps(resolved.buoc || [], selected ? stepOf(selected) : null);
      measureStandard = null;
      measureImport?.reset();
      $("gcResultConfirmation").hidden = true;
      measureRequest = null;
      measureRows = [];
      measureEntry = null;
      $("gcAddSample").disabled = true;
      $("gcSaveMeasure").disabled = true;
      measureDay = day;
      if (!selected) {
        $("gcMeasureInfo").textContent =
          resolved.status === "chon_buoc"
            ? "Chọn bước gia công."
            : model && day
              ? "Chưa có tiêu chuẩn."
              : model
                ? "Chọn ngày kiểm."
                : "Chọn Model.";
        $("gcMeasureInfo").title =
          resolved.status === "chon_buoc"
            ? "Model này có nhiều bước gia công đang có hiệu lực."
            : "";
        $("gcMeasureRows").replaceChildren();
        return;
      }
      measureRows = resolved.muc || [];
      measureStandard = selected;
      if (!measureRows.length) {
        $("gcMeasureInfo").textContent = "Tiêu chuẩn chưa có đặc tính.";
        $("gcMeasureRows").textContent = "Chưa có dữ liệu";
        return;
      }
      $("gcMeasureInfo").textContent = "Đã tải " + measureRows.length + " đặc tính.";
      $("gcMeasureInfo").title =
        selected.ma_sp + " · Revision " + selected.phien_ban + " · Hiệu lực " + selected.ngay_hieu_luc;
      measureEntry = IpqcGcEntry.mount($("gcMeasureRows"), measureRows, selected, updateMeasureStatus);
      const canMeasure = ["admin", "qc_manager", "ipqc"].includes(rights.role);
      measureEntry.setDisabled(!canMeasure);
      $("gcAddSample").disabled = !canMeasure;
    } finally {
      if (serial === measureSerial) {
        measureLoading = false;
        $("gcMeasureInput").disabled =
          !measureEntry ||
          !measureRows.length ||
          measureStandard?.ma_sp !== $("gcMeasureProduct").value.trim() ||
          measureDay !== $("gcInspectionDate").value;
        if (measureEntry) updateMeasureStatus(measureEntry.status());
      }
    }
  }
  function updateMeasureStatus(state) {
    measureImport?.edited();
    $("gcMeasureSummary").textContent =
      "Đã nhập " +
      state.filled +
      "/" +
      state.total +
      " giá trị · " +
      (state.complete ? (state.dat ? "Lần kiểm: OK" : "Lần kiểm: NG") : "Chưa đủ mẫu");
    $("gcMeasureSummary").className = state.complete ? (state.dat ? "good" : "bad") : "muted";
    $("gcSaveMeasure").disabled =
      measureSaving ||
      measureLoading ||
      !state.complete ||
      !["admin", "qc_manager", "ipqc"].includes(rights.role);
  }
  $("gcAddSample").onclick = () => measureEntry?.addSample();
  $("gcMeasureProduct").onchange = () => {
    $("gcMeasureStep").value = "";
    loadMeasureStandard().catch(fail);
  };
  $("gcInspectionDate").onchange = $("gcMeasureStep").onchange = () => loadMeasureStandard().catch(fail);
  $("gcMeasureForm").onsubmit = async (event) => {
    event.preventDefault();
    if (
      !measureStandard ||
      measureSaving ||
      measureLoading ||
      measureStandard.ma_sp !== $("gcMeasureProduct").value.trim() ||
      measureDay !== $("gcInspectionDate").value
    )
      return;
    measureSaving = true;
    const inputStates = [...$("gcMeasureForm").querySelectorAll("input,select,button")].map((el) => [
      el,
      el.disabled,
    ]);
    for (const [el] of inputStates) el.disabled = true;
    const button = $("gcSaveMeasure");
    button.disabled = true;
    try {
      const kq = measureEntry.payload();
      const payload = {
        ma_sp: measureStandard.ma_sp,
        id_btk: measureStandard.id,
        ma_may: $("gcMachine").value,
        ca: $("gcShift").value,
        ngay_kiem: $("gcInspectionDate").value,
        co_mau_thuc_te: measureEntry.sampleCounts(),
        ...(await measureImport.prepareSave()),
        kq,
      };
      const signature = JSON.stringify(payload);
      if (measureRequest?.signature !== signature) measureRequest = { id: crypto.randomUUID(), signature };
      const id = await rpc("ipqc_gc_luu_do", { p_data: { ...payload, request_id: measureRequest.id } });
      const saved = await sb.from("ipqc_gc_lan").select("dat,thoi_diem").eq("id", id).single();
      if (saved.error) throw saved.error;
      notify("Lưu thành công · " + (saved.data.dat ? "OK" : "NG"));
      measureRequest = null;
      await loadMeasureStandard(true);
      await loadDashboard();
    } catch (error) {
      fail(error);
    } finally {
      measureSaving = false;
      for (const [el, disabled] of inputStates) if (el.isConnected) el.disabled = disabled;
      button.disabled =
        !measureEntry?.status().complete || !["admin", "qc_manager", "ipqc"].includes(rights.role);
    }
  };
  function filteredResults() {
    const key = $("gcFilterFeature").value;
    if (!key) return results;
    const [version, no] = key.split("/");
    return results
      .filter((r) => String(r.id_btk) === version)
      .map((r) => ({ ...r, kq: r.kq.filter((k) => String(k.muc_no) === no) }))
      .filter((r) => r.kq.length)
      .map((r) => ({ ...r, dat: r.kq.every((k) => k.dat), so_mau: new Set(r.kq.map((k) => k.mau)).size }));
  }
  async function loadDashboard() {
    const serial = ++dashboardSerial;
    const result = await sbTaiHet(() => {
      let q = sb
        .from("ipqc_lan_tong_hop")
        .select("*")
        .gte("ngay_kiem", $("gcFrom").value)
        .lte("ngay_kiem", $("gcTo").value)
        .order("ngay_kiem")
        .order("thoi_diem")
        .order("id");
      for (const [id, column] of [
        ["gcDashboardProcess", "cong_doan"],
        ["gcFilterProduct", "ma_sp"],
        ["gcFilterMachine", "ma_may"],
        ["gcFilterShift", "ca"],
      ])
        if ($(id).value) q = q.eq(column, $(id).value);
      if ($("gcFilterInspector").value) q = q.ilike("nguoi_kiem", "%" + $("gcFilterInspector").value + "%");
      return q;
    });
    if (result.error) throw result.error;
    if (serial !== dashboardSerial) return;
    results = result.data || [];
    rowLimit = 100;
    const old = $("gcFilterFeature").value,
      options = new Map();
    for (const r of results)
      for (const m of r.tieu_chuan?.muc || [])
        options.set(
          r.id_btk + "/" + m.muc_no,
          [r.ma_sp, r.revision, m.ma_dac_tinh || m.muc_no, m.hang_muc].join(" · "),
        );
    $("gcFilterFeature").innerHTML =
      '<option value="">Tất cả</option>' +
      [...options].map(([key, label]) => '<option value="' + E(key) + '">' + E(label) + "</option>").join("");
    if (options.has(old)) $("gcFilterFeature").value = old;
    renderDashboard();
  }
  function renderDashboard() {
    const data = filteredResults(),
      ok = data.filter((r) => r.dat).length,
      ng = data.length - ok,
      samples = data.reduce((n, r) => n + Number(r.so_mau || 0), 0);
    $("gcMetrics").innerHTML = [
      ["Lần kiểm", data.length],
      ["Số mẫu", samples],
      ["OK", ok],
      ["NG", ng],
      ["Tỷ lệ NG", data.length ? ((ng / data.length) * 100).toFixed(2) + "%" : "Chưa có dữ liệu"],
    ]
      .map(([key, value]) => '<div class="metric">' + E(key) + "<b>" + E(value) + "</b></div>")
      .join("");
    const detail = [],
      sourceRecords = [];
    const defects = new Map();
    for (const r of data)
      for (const k of r.kq || []) {
        const m = r.tieu_chuan?.muc?.find((m) => m.muc_no === k.muc_no) || {},
          limits = bounds(m);
        detail.push([
          r.cong_doan,
          r.ma_sp,
          r.revision,
          r.buoc_gia_cong,
          r.ma_may,
          r.ca,
          r.ma_lo,
          r.nguoi_kiem,
          dayLabel(inspectionDay(r)),
          stamp(r.thoi_diem),
          m.ma_dac_tinh || k.muc_no,
          m.hang_muc,
          k.mau,
          k.gia_tri ?? (k.dat ? "OK" : "NG"),
          limits.lsl,
          limits.usl,
          k.dat ? "OK" : "NG",
          sourceLabel(r.nguon_nhap),
          r.tep_ket_qua?.name || "—",
        ]);
        sourceRecords.push(r);
        if (!k.dat) {
          const key = [r.ma_sp, r.revision, m.ma_dac_tinh || k.muc_no, m.hang_muc].join(" · ");
          defects.set(key, (defects.get(key) || 0) + 1);
        }
      }
    table(
      $("gcDataRows"),
      [
        "Công đoạn",
        "Model",
        "Revision",
        "Bước",
        "Máy",
        "Ca",
        "Lô",
        "Người kiểm",
        "Ngày kiểm",
        "Tạo lúc",
        "Mã đặc tính",
        "Tên",
        "Mẫu",
        "Giá trị",
        "LSL",
        "USL",
        "Kết quả",
        "Nguồn nhập",
        "File gốc",
      ],
      detail.slice(0, rowLimit),
    );
    [...$("gcDataRows").querySelectorAll("tbody tr")].forEach((tr, index) => {
      const row = sourceRecords[index],
        file = row?.tep_ket_qua;
      if (!file?.path || file.bucket !== "ipqc-gia-cong-ket-qua") return;
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = "Xem file gốc";
      button.title = file.name;
      button.onclick = async () => {
        const popup = window.open("about:blank", "_blank");
        if (popup) popup.opener = null;
        try {
          const result = await sb.storage.from(file.bucket).createSignedUrl(file.path, 300);
          if (result.error) throw result.error;
          const url = new URL(result.data.signedUrl);
          if (url.protocol !== "https:") throw Error("Đường dẫn file không hợp lệ.");
          if (popup) popup.location.assign(url.href);
          else notify("Trình duyệt đã chặn tab file. Cho phép mở tab và thử lại.");
        } catch (error) {
          popup?.close();
          fail(error);
        }
      };
      tr.lastElementChild.replaceChildren(button);
    });
    $("gcMoreRows").hidden = detail.length <= rowLimit;
    table(
      $("gcTopNg"),
      ["Đặc tính / Revision", "Số giá trị NG"],
      [...defects].sort((a, b) => b[1] - a[1]),
    );
    renderCharts(data);
  }
  function sourceLabel(source) {
    return { nhap_tay: "Nhập tay", tu_file: "Nhập từ file" }[source] || "Chưa ghi nhận";
  }
  function renderCharts(data) {
    const selected = $("gcFilterFeature").value;
    $("gcValueChart").replaceChildren();
    $("gcSpcChart").replaceChildren();
    $("gcCapability").textContent = "";
    if (!selected) {
      $("gcValueChart").textContent = "Chọn đặc tính.";
      return;
    }
    const [, no] = selected.split("/"),
      m = data[0]?.tieu_chuan?.muc?.find((m) => String(m.muc_no) === no);
    if (!m || m.kieu === "okng") {
      $("gcValueChart").textContent = "Đặc tính OK/NG không có giá trị số để vẽ SPC.";
      return;
    }
    const limits = bounds(m),
      values = [],
      groups = [];
    for (const r of data) {
      const ks = r.kq.filter((k) => String(k.muc_no) === no && k.gia_tri != null),
        vs = ks.map((k) => Number(k.gia_tri));
      ks.forEach((k) =>
        values.push({
          x: Number(k.gia_tri),
          tg: dayLabel(inspectionDay(r)),
          nhan: dayLabel(inspectionDay(r)) + " · mẫu " + k.mau + " · " + (k.dat ? "OK" : "NG"),
          mau: k.dat ? "#0f5fa5" : "#b91c1c",
        }),
      );
      if (vs.length)
        groups.push({
          x: vs.reduce((n, v) => n + v, 0) / vs.length,
          r: Math.max(...vs) - Math.min(...vs),
          vals: vs,
          tg: dayLabel(inspectionDay(r)),
        });
    }
    $("gcValueChart").innerHTML = S.bieuDo({
      pts: values,
      lsl: limits.lsl,
      usl: limits.usl,
      nominal: numeric(m.danh_nghia),
    });
    const n = groups[0]?.vals.length,
      same = groups.every((g) => g.vals.length === n),
      oneMachine = new Set(data.map((r) => r.ma_may)).size === 1;
    if (groups.length < 25 || !same || !oneMachine || n > 5) {
      $("gcSpcChart").textContent =
        "Chưa đủ điều kiện SPC: cần 25 nhóm, cùng cỡ mẫu (1–5), tiêu chuẩn và máy.";
      $("gcCapability").textContent = "Chưa đủ điều kiện đánh giá Cp/Cpk.";
      return;
    }
    const lim = S.gioiHan({ gioi_han: [] }, Number(no), n, groups);
    const violations = S.quyTac(
      groups.map((g) => g.x),
      lim,
    );
    $("gcSpcChart").innerHTML =
      "<p>" +
      (n === 1 ? "I–MR" : "Xbar–R") +
      ' · <span title="UCL/LCL khác giới hạn kỹ thuật LSL/USL.">UCL/LCL thống kê</span></p>' +
      S.bieuDo({ pts: groups, lim }) +
      S.bieuDo({
        pts:
          n === 1
            ? groups.slice(1).map((g, i) => ({ ...g, x: Math.abs(g.x - groups[i].x) }))
            : groups.map((g) => ({ ...g, x: g.r })),
        lim: { cl: lim.clR, ucl: lim.uclR, lcl: 0 },
        nhanGH: ["UCL", "Trung bình biên độ", "LCL"],
      });
    if (
      values.length >= 100 &&
      groups.length >= 30 &&
      !violations.length &&
      $("gcCapabilityConfirmed").checked
    ) {
      const cap = IpqcGcMath.capability(groups, limits);
      $("gcCapability").textContent = cap
        ? "Cp: " +
          (cap.cp?.toFixed(3) ?? "—") +
          " · Cpk: " +
          (cap.cpk?.toFixed(3) ?? "—") +
          " · σ trong nhóm: " +
          cap.sigma.toPrecision(4)
        : "Thiếu giới hạn kỹ thuật hoặc độ biến thiên để tính Cp/Cpk.";
    } else $("gcCapability").textContent = "Chưa đủ điều kiện Cp/Cpk.";
  }
  $("gcFilterFeature").onchange = () => {
    rowLimit = 100;
    $("gcCapabilityConfirmed").checked = false;
    renderDashboard();
  };
  $("gcCapabilityConfirmed").onchange = () => renderCharts(filteredResults());
  $("gcRefresh").onclick = () => {
    $("gcCapabilityConfirmed").checked = false;
    loadDashboard().catch(fail);
  };
  $("gcMoreRows").onclick = () => {
    rowLimit += 100;
    renderDashboard();
  };
  $("gcExcel").onclick = () => {
    const out = [];
    for (const r of filteredResults())
      for (const k of r.kq) {
        const m = r.tieu_chuan?.muc?.find((m) => m.muc_no === k.muc_no) || {},
          limits = bounds(m);
        out.push({
          "Công đoạn": r.cong_doan,
          Model: r.ma_sp,
          Revision: r.revision,
          Bước: r.buoc_gia_cong,
          Máy: r.ma_may,
          Ca: r.ca,
          "Mã lô": r.ma_lo,
          "Người kiểm": r.nguoi_kiem,
          "Ngày kiểm": inspectionDay(r),
          "Tạo lúc": stamp(r.thoi_diem),
          "Cập nhật lúc": r.cap_nhat_luc ? stamp(r.cap_nhat_luc) : "",
          "Đặc tính": m.ma_dac_tinh || k.muc_no,
          Tên: m.hang_muc,
          Mẫu: k.mau,
          "Giá trị": k.gia_tri,
          LSL: limits.lsl,
          USL: limits.usl,
          "Kết quả": k.dat ? "OK" : "NG",
          "Nguồn nhập": sourceLabel(r.nguon_nhap),
          "File gốc": r.tep_ket_qua?.name || "",
        });
      }
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, XLSX.utils.json_to_sheet(out), "IPQC");
    XLSX.writeFile(workbook, "IPQC-theo-bo-loc.xlsx");
  };
  async function boot() {
    MesNav.setTitle("IPQC Gia công");
    rights = await IpqcBtkQc.quyen();
    [products, machines] = await Promise.all([
      Qc02Data.readAll("master_products"),
      (async () => {
        const r = await sbTaiHet(() => sb.from("master_machines").select("*").order("ma_may"));
        if (r.error) throw r.error;
        return r.data || [];
      })(),
    ]);
    $("gcProducts").innerHTML = products
      .map((p) => '<option value="' + E(p.ma_sp) + '">' + E(p.ten_sp || "") + "</option>")
      .join("");
    $("gcMachine").innerHTML = machines
      .filter((m) => m.bo_phan === "Gia công - Sơn")
      .map((m) => "<option>" + E(m.ma_may) + "</option>")
      .join("");
    $("gcMachines").innerHTML = machines.map((m) => "<option>" + E(m.ma_may) + "</option>").join("");
    $("gcFrom").value = $("gcTo").value = today();
    $("gcInspectionDate").value = today();
    await loadMeasureStandard();
    const params = new URLSearchParams(location.search);
    if (params.get("view") === "dashboard") changeTab("dashboard");
    if (params.has("ma")) {
      $("gcMeasureProduct").value = params.get("ma");
      await loadMeasureStandard();
      changeTab("measure");
    }
    setInterval(() => ($("clock").textContent = stamp(new Date())), 1000);
    setInterval(() => {
      if (!document.querySelector('[data-panel="dashboard"]').hidden) loadDashboard().catch(fail);
    }, 60000);
  }
  measureImport = IpqcResultImport.mount({
    entry: () => measureEntry,
    standard: () => measureStandard,
    features: () => measureRows,
    fail,
    onSync: () => {
      $("gcResultConfirmation").hidden = !measureImport.hasApplied();
    },
  });
  boot().catch(fail);
  return { refresh: loadDashboard };
})();
