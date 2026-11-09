/* Chemical entry extends the existing daily IQC form and LOT records. */
const IqcChemicalEntry = (() => {
  const el = (id) => document.getElementById(id),
    C = IqcChemistry,
    form = el("lotForm"),
    section = el("formSection");
  const root = document.createElement("section");
  root.id = "iqc-chemical-entry";
  root.className = "iqc-chemical";
  root.hidden = true;
  root.innerHTML =
    '<h3>KIỂM TRA THÀNH PHẦN HÓA HỌC</h3><div class="iqc-chem-grid">' +
    '<label>Ngày kiểm<input id="iqcChemDate" type="date"></label><label>Ca kiểm<select id="iqcChemShift"><option value="">Chọn ca</option><option>Ca ngày</option><option>Ca đêm</option><option>Ca 1</option><option>Ca 2</option></select></label><label>Nhà cung cấp (nếu có)<input id="iqcChemSupplier"></label><div id="iqcChemInspector"></div></div>' +
    '<p id="iqcChemStandard" class="help"></p><a id="iqcChemStandardLink" target="_blank" rel="noopener">Quản lý tiêu chuẩn / phân loại NVL</a> <button type="button" id="iqcChemReloadStandard">Tải lại tiêu chuẩn áp dụng</button>' +
    '<div class="iqc-chem-grid"><label>Tải kết quả phân tích<input id="iqcChemFile" type="file" accept=".pdf,.xlsx,.xls,.jpg,.jpeg,.png"></label><label>Đơn vị khi file chưa ghi rõ<select id="iqcChemSourceUnit"><option value="">Theo đơn vị đọc được từ file</option><option value="%">% (QC xác nhận)</option><option value="ppm">ppm (QC xác nhận)</option><option value="mg/kg">mg/kg (QC xác nhận)</option></select></label><span id="iqcChemFileLink"></span></div>' +
    '<p class="help">PDF, Excel, JPG/PNG · tối đa 20 MB. File chỉ được tải lên khi lưu báo cáo. Không nhận diện được hoặc có nhiều kết quả khác nhau: QC chọn nguồn / nhập tay; không tự lấy Min/Max làm kết quả.</p>' +
    '<div class="iqc-chem-table"><table><thead><tr><th>Nguyên tố</th><th>Min</th><th>Max</th><th>Đơn vị</th><th>Kết quả</th><th>Đánh giá</th><th>Nguồn nhận diện</th></tr></thead><tbody id="iqcChemRows"></tbody></table></div>' +
    '<label class="iqc-chem-confirm"><input id="iqcChemConfirmed" type="checkbox"> Tôi đã kiểm tra và xác nhận kết quả phân tích</label><p id="iqcChemConclusion" aria-live="polite">Kết luận: Chưa kết luận</p><p id="iqcChemStatus" role="status"></p>';
  form.querySelector(".iqc-report-top").after(root);
  const catalogStatus = document.createElement("p");
  catalogStatus.id = "iqcMaterialStatus";
  catalogStatus.className = "help";
  el("productCode").closest(".field").append(catalogStatus);
  const peopleList = document.createElement("datalist");
  peopleList.id = "iqc-chemical-people";
  form.append(peopleList);
  const inspectorField = el("inspector").closest(".field"),
    inspectorAnchor = document.createComment("IQC visual inspector");
  inspectorField.before(inspectorAnchor);
  const oldList = el("inspector").getAttribute("list");
  const codeLabel = el("productCode").closest(".field").querySelector("label"),
    nameLabel = el("productName").closest(".field").querySelector("label");
  codeLabel.textContent = "Mã sản phẩm / NVL *";
  nameLabel.textContent = "Tên sản phẩm / NVL";
  let chemical = false,
    item = null,
    standard = null,
    rows = [],
    values = {},
    choices = {},
    candidates = [],
    people = [],
    lot = null,
    pendingFile = null,
    fileMeta = null,
    uploaded = null;
  let requestId = crypto.randomUUID(),
    ticket = 0,
    selectionSerial = 0,
    busy = false,
    reading = false,
    dirty = false,
    contextDate = "",
    savedControls = [],
    readerAbort = null;
  const today = () => new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Bangkok" }).format(new Date());
  const esc = (s) =>
    String(s ?? "").replace(
      /[&<>"']/g,
      (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c],
    );
  function status(text, error = false) {
    el("iqcChemStatus").textContent = text;
    el("iqcChemStatus").classList.toggle("err", error);
  }
  async function check(p) {
    const r = await p;
    if (r.error || r.data?.ok === false) throw Error(r.error?.message || r.data.error);
    return r.data;
  }
  function clear() {
    ++ticket;
    ++selectionSerial;
    readerAbort?.abort();
    reading = false;
    if (!busy) el("saveBtn").disabled = false;
    values = {};
    choices = {};
    candidates = [];
    pendingFile = null;
    fileMeta = null;
    uploaded = null;
    lot = null;
    dirty = false;
    requestId = crypto.randomUUID();
    el("iqcChemFile").value = "";
    el("iqcChemConfirmed").checked = false;
    el("iqcChemFileLink").replaceChildren();
    status("");
  }
  function mode(on) {
    if (on === chemical) return;
    chemical = on;
    root.hidden = !on;
    section.classList.toggle("iqc-is-chemical", on);
    codeLabel.textContent = on ? "Mã NVL *" : "Mã sản phẩm / NVL *";
    nameLabel.textContent = on ? "Tên NVL" : "Tên sản phẩm / NVL";
    if (on) {
      savedControls = [];
      for (const field of form.querySelectorAll(".field")) {
        if (
          root.contains(field) ||
          ["productCode", "productName", "lotNo", "inspector"].some((id) => field.contains(el(id)))
        )
          continue;
        savedControls.push({
          field,
          hidden: field.hidden,
          inputs: [...field.querySelectorAll("input,select,textarea,button")].map((e) => [e, e.disabled]),
        });
        field.hidden = true;
        field.querySelectorAll("input,select,textarea,button").forEach((e) => (e.disabled = true));
      }
      el("iqcChemInspector").append(inspectorField);
      el("inspector").setAttribute("list", peopleList.id);
      el("saveBtn").textContent = "Lưu báo cáo";
    } else {
      for (const { field, hidden, inputs } of savedControls) {
        field.hidden = hidden;
        inputs.forEach(([e, d]) => (e.disabled = d));
      }
      savedControls = [];
      inspectorAnchor.after(inspectorField);
      if (oldList) el("inspector").setAttribute("list", oldList);
      el("saveBtn").textContent = editingId ? "Cập nhật LOT" : "Lưu LOT";
    }
    for (const id of [
      "iqcChemDate",
      "iqcChemShift",
      "iqcChemSupplier",
      "iqcChemFile",
      "iqcChemSourceUnit",
      "iqcChemConfirmed",
    ])
      el(id).disabled = !on;
    el("iqcChemDate").required = on;
    el("iqcChemShift").required = on;
  }
  async function loadPeople() {
    const r = await check(sb.rpc("qc_danh_sach_tai_khoan"));
    people = (r || []).filter((p) => ["iqc", "qc_manager", "admin"].includes(p.role));
    peopleList.replaceChildren(
      ...people.map((p) => new Option(p.full_name || p.username, p.username + "_" + (p.full_name || p.username))),
    );
  }
  function assessment() {
    const a = C.evaluate(rows, values);
    for (const r of a.results) {
      const tr = [...el("iqcChemRows").rows].find((tr) => tr.dataset.element === r.element);
      if (tr) {
        const cell = tr.querySelector("[data-evaluation]");
        cell.textContent = r.result;
        cell.className = r.result === "NG" ? "ng" : r.result === "OK" ? "ok" : "";
      }
    }
    const final = el("iqcChemConfirmed").checked ? a.conclusion : "";
    el("iqcChemConclusion").textContent =
      "Kết luận: " +
      (final || "Chưa kết luận") +
      (!el("iqcChemConfirmed").checked && a.conclusion ? " · Dự kiến " + a.conclusion + ", chờ QC xác nhận" : "");
    return a;
  }
  function renderRows() {
    el("iqcChemRows").innerHTML =
      rows
        .map((r) => {
          const key = r.ma_dac_tinh,
            u = r.don_vi,
            options = choices[key] || [];
          return (
            '<tr data-element="' +
            esc(key) +
            '"><td>' +
            esc(key) +
            (r.bat_buoc === false ? "" : " *") +
            "</td><td>" +
            esc(r.lsl ?? "—") +
            "</td><td>" +
            esc(r.usl ?? "—") +
            "</td><td>" +
            esc(u) +
            '</td><td><input data-measure inputmode="decimal" value="' +
            esc(values[key] ?? "") +
            '" aria-label="Kết quả ' +
            esc(key) +
            '" placeholder="Chưa nhận diện"></td><td data-evaluation></td><td>' +
            (options.length > 1 || options.some((c) => c.requiresReview)
              ? '<select data-source><option value="">' +
                (options.some((c) => c.requiresReview)
                  ? "OCR cần kiểm tra — chọn / nhập tay"
                  : "Nhiều kết quả — chọn nguồn") +
                "</option>" +
                options
                  .map(
                    (c, i) =>
                      '<option value="' +
                      i +
                      '">' +
                      esc(
                        c.source +
                          " / dòng " +
                          c.row +
                          ": " +
                          c.value +
                          " " +
                          u +
                          (c.requiresReview ? " · OCR " + c.confidence + "%" : ""),
                      ) +
                      "</option>",
                  )
                  .join("") +
                "</select>"
              : options.length === 1
                ? esc(options[0].source + " / dòng " + options[0].row)
                : "Chưa nhận diện / nhập tay") +
            "</td></tr>"
          );
        })
        .join("") ||
      '<tr><td colspan="7">Chưa có tiêu chuẩn được duyệt cho đúng mã NVL / mác / ngày kiểm. Có thể lưu báo cáo chưa kết luận; không tự tạo nguyên tố hoặc giới hạn.</td></tr>';
    for (const tr of el("iqcChemRows").rows) {
      const input = tr.querySelector("[data-measure]");
      if (!input) continue;
      input.oninput = () => {
        values[tr.dataset.element] = input.value;
        dirty = true;
        status("Kết quả đã thay đổi. Kiểm tra và xác nhận trước khi lưu.");
        el("iqcChemConfirmed").checked = false;
        assessment();
      };
      const source = tr.querySelector("[data-source]");
      if (source)
        source.onchange = () => {
          if (source.value === "") return;
          values[tr.dataset.element] = choices[tr.dataset.element][Number(source.value)].value;
          input.value = values[tr.dataset.element];
          dirty = true;
          el("iqcChemConfirmed").checked = false;
          assessment();
        };
    }
    assessment();
  }
  async function loadStandard() {
    const turn = ++ticket,
      code = item.code,
      date = el("iqcChemDate").value;
    readerAbort?.abort();
    reading = false;
    standard = null;
    rows = [];
    el("iqcChemConfirmed").checked = false;
    el("iqcChemFile").disabled = true;
    el("saveBtn").disabled = true;
    renderRows();
    try {
      const data = await check(sb.rpc("iqc_tc_hoa_hoc", { p_ma_nvl: code, p_ngay: date }));
      if (turn !== ticket || item?.code !== code) return;
      standard = data?.tieu_chuan || null;
      rows = data?.nguyen_to || [];
      contextDate = date;
      el("iqcChemStandard").textContent = standard
        ? "Tiêu chuẩn: " +
          item.code +
          " · " +
          standard.mac_vat_lieu +
          " · Revision " +
          standard.phien_ban +
          " · hiệu lực " +
          standard.ngay_hieu_luc
        : "Chưa có tiêu chuẩn hóa học đã phê duyệt phù hợp. Kết luận giữ “Chưa kết luận”.";
      renderRows();
    } finally {
      if (turn === ticket) {
        el("iqcChemFile").disabled = !chemical;
        if (!busy) el("saveBtn").disabled = false;
      }
    }
  }
  async function refreshCatalog(force = true) {
    const c = await IqcMaterialCatalog.load(force);
    const list = el("qc02-products");
    if (list) IqcMaterialCatalog.options(list);
    catalogStatus.textContent = c.available
      ? "Mã sản phẩm và mã NVL dùng chung danh mục MES/BOM. Mã NVL có nhãn [NVL]."
      : "Chưa tải được danh mục NVL BOM; danh sách sản phẩm hiện tại vẫn sử dụng được.";
  }
  async function select() {
    const turn = ++selectionSerial,
      typed = el("productCode").value;
    await IqcMaterialCatalog.load(true);
    if (turn !== selectionSerial || typed !== el("productCode").value) return;
    const selected = IqcMaterialCatalog.resolve(typed);
    if (dirty && !confirm("Đổi mã sẽ bỏ kết quả chưa lưu. Tiếp tục?")) {
      el("productCode").value = item ? IqcMaterialCatalog.display(item) : "";
      return;
    }
    const previous = chemical;
    clear();
    item = selected;
    if (previous) editingId = null;
    const on = item?.kind === "nvl" && ["nhom", "kem"].includes(item.group);
    mode(!!on);
    if (item) el("productName").value = item.name;
    if (item?.kind === "nvl") {
      catalogStatus.textContent =
        "NVL BOM · " +
        item.code +
        " · " +
        (item.group ? { nhom: "Nhôm", kem: "Kẽm", khac: "NVL khác" }[item.group] : "Chưa phân loại") +
        (item.grade ? " · " + item.grade : "");
      if (!item.group)
        catalogStatus.append(
          document.createTextNode(" — QC cấu hình nhóm/mác tại Quản lý tiêu chuẩn trước khi kiểm hóa học."),
        );
      const configure = document.createElement("a");
      configure.href = "qc-manager.html?tab=tieuchuan&cd=iqc_hoa_hoc&ma=" + encodeURIComponent(item.code);
      configure.target = "_blank";
      configure.rel = "noopener";
      configure.textContent = " Mở phân loại / tiêu chuẩn NVL";
      configure.style.marginLeft = "6px";
      catalogStatus.append(configure);
    }
    el("iqcChemStandardLink").href =
      "qc-manager.html?tab=tieuchuan&cd=iqc_hoa_hoc&ma=" + encodeURIComponent(item?.code || "");
    if (on) {
      el("iqcChemDate").value = today();
      el("iqcChemSupplier").value = item.supplier || "";
      await Promise.all([loadStandard(), loadPeople()]);
    }
  }
  async function validateFile(file) {
    const ext = file.name.split(".").pop().toLowerCase(),
      types = {
        pdf: "application/pdf",
        xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        xls: "application/vnd.ms-excel",
        jpg: "image/jpeg",
        jpeg: "image/jpeg",
        png: "image/png",
      };
    if (!types[ext] || !file.size || file.size > 20 * 1024 * 1024)
      throw Error("Chọn PDF, XLS/XLSX, JPG/PNG từ 1 byte đến 20 MB");
    if (file.name.length > 255) throw Error("Tên file tối đa 255 ký tự");
    const b = new Uint8Array(await file.slice(0, 8).arrayBuffer()),
      s = String.fromCharCode(...b);
    const valid =
      ext === "pdf"
        ? s.startsWith("%PDF-")
        : ext === "xlsx"
          ? b[0] === 80 && b[1] === 75
          : ext === "xls"
            ? [208, 207, 17, 224].every((v, i) => b[i] === v)
            : ext === "png"
              ? [137, 80, 78, 71, 13, 10, 26, 10].every((v, i) => b[i] === v)
              : b[0] === 255 && b[1] === 216 && b[2] === 255;
    if (!valid) throw Error("Nội dung file không đúng định dạng đã chọn");
    return { ext: ext === "jpeg" ? "jpg" : ext, type: types[ext] };
  }
  function applyCandidates() {
    const matched = C.matched(rows, candidates, el("iqcChemSourceUnit").value);
    const changes = Object.keys(matched.values).filter(
      (k) => values[k] !== undefined && values[k] !== "" && C.compare(values[k], matched.values[k]) !== 0,
    );
    if (changes.length && !confirm("Thay kết quả đã nhập của " + changes.join(", ") + " bằng kết quả từ file?")) return;
    choices = matched.choices;
    Object.assign(values, matched.values);
    el("iqcChemConfirmed").checked = false;
    dirty = true;
    renderRows();
    status(
      "Đọc được " +
        candidates.length +
        " kết quả nguyên tố. Tự ghép " +
        Object.keys(matched.values).length +
        "/" +
        rows.length +
        " dòng; kiểm tra đơn vị và xác nhận trước khi lưu." +
        (matched.missing.length ? " Chưa ghép chắc chắn: " + matched.missing.join(", ") + "." : ""),
    );
  }
  el("iqcChemFile").onchange = async () => {
    const file = el("iqcChemFile").files[0];
    if (!file || !chemical) return;
    if (
      Object.values(values).some((v) => v !== "") &&
      !confirm(
        "Đọc file mới sẽ thay các kết quả đang nhập. Nguyên tố chưa nhận diện sẽ để trống để QC nhập tay. Tiếp tục?",
      )
    ) {
      el("iqcChemFile").value = "";
      return;
    }
    const turn = ++ticket;
    readerAbort?.abort();
    readerAbort = new AbortController();
    reading = true;
    el("iqcChemConfirmed").checked = false;
    el("saveBtn").disabled = true;
    status("Đang kiểm tra file phân tích...");
    try {
      const info = await validateFile(file);
      status("Đang đọc kết quả phân tích...");
      const result = await IpqcResultReader.read(file, {
        parseSheets: C.parse,
        imageScale: 3,
        signal: readerAbort.signal,
        progress: (text) => {
          if (turn === ticket) status(text);
        },
      });
      if (turn !== ticket) return;
      candidates = C.parse(result.sheets);
      pendingFile = { file, ...info };
      uploaded = null;
      fileMeta = null;
      values = {};
      choices = {};
      el("iqcChemFileLink").replaceChildren();
      applyCandidates();
      if (!candidates.length)
        status(
          "Chưa nhận diện nguyên tố/hàm lượng chắc chắn. Nhập tay kết quả còn thiếu; không tự điền dữ liệu giả.",
          true,
        );
    } catch (e) {
      if (turn === ticket) {
        el("iqcChemFile").value = "";
        status(e.message, true);
      }
    } finally {
      if (turn === ticket) {
        reading = false;
        el("saveBtn").disabled = false;
      }
    }
  };
  el("iqcChemSourceUnit").onchange = () => applyCandidates();
  el("iqcChemConfirmed").onchange = () => {
    dirty = true;
    assessment();
  };
  el("iqcChemReloadStandard").onclick = async () => {
    if (!chemical || busy || reading) return;
    if (
      (dirty || Object.values(values).some((v) => v !== "")) &&
      !confirm("Tải lại tiêu chuẩn sẽ xóa các giá trị đang nhập và yêu cầu xác nhận lại. Tiếp tục?")
    )
      return;
    values = {};
    choices = {};
    el("iqcChemConfirmed").checked = false;
    try {
      await loadStandard();
      if (candidates.length) applyCandidates();
    } catch (e) {
      status(e.message, true);
    }
  };
  el("iqcChemDate").onchange = async () => {
    if (!chemical) return;
    if (dirty && !confirm("Ngày kiểm đổi tiêu chuẩn áp dụng. Xóa các kết quả chưa lưu để tải lại?")) {
      el("iqcChemDate").value = contextDate;
      return;
    }
    values = {};
    choices = {};
    candidates = [];
    el("iqcChemConfirmed").checked = false;
    await loadStandard().catch((e) => status(e.message, true));
  };
  async function upload() {
    if (!pendingFile) return fileMeta;
    if (uploaded) return uploaded;
    const session = await MesAuth.getSession();
    if (!session) throw Error("Vui lòng đăng nhập lại");
    pendingFile.path ||= session.user.id + "/" + requestId + "/" + crypto.randomUUID() + "." + pendingFile.ext;
    const response = await sb.storage
      .from("iqc-phan-tich")
      .upload(pendingFile.path, pendingFile.file, { contentType: pendingFile.type, upsert: false });
    if (response.error && String(response.error.statusCode) !== "409") throw response.error;
    uploaded = { bucket: "iqc-phan-tich", path: pendingFile.path, name: pendingFile.file.name };
    return uploaded;
  }
  async function save() {
    if (busy || reading) return;
    busy = true;
    el("saveBtn").disabled = true;
    const locked = [...form.querySelectorAll("input,select,button,textarea")].map((e) => [e, e.disabled]);
    locked.forEach(([e]) => (e.disabled = true));
    try {
      const person = people.find(
        (p) =>
          el("inspector").value === p.username ||
          el("inspector").value === p.username + "_" + (p.full_name || p.username),
      );
      if (!person) throw Error("Chọn người kiểm từ danh sách tài khoản IQC / quản lý QC");
      const a = assessment();
      if (a.results.some((r) => r.result === "Không hợp lệ")) throw Error("Kiểm tra giá trị hàm lượng chưa hợp lệ");
      const data = {
        request_id: requestId,
        ma_nvl: item.code,
        ngay_kiem: el("iqcChemDate").value,
        ca_kiem: el("iqcChemShift").value,
        supplier: el("iqcChemSupplier").value,
        lot_no: el("lotNo").value,
        inspector: person.username,
        id_tieu_chuan: standard?.id || null,
        results: values,
        xac_nhan: el("iqcChemConfirmed").checked,
        file: await upload(),
        nguon: { candidates: candidates.map(({ samples, ...c }) => c), unit: el("iqcChemSourceUnit").value },
        updated_at: lot?.updatedAt || null,
        note: el("note").value,
      };
      const result = await check(sb.rpc("iqc_luu_hoa_hoc", { p_id: lot?.id || null, p_data: data }));
      lot = await IqcApi.getLot(result.id);
      editingId = lot.id;
      fileMeta = lot.chemical?.file || null;
      pendingFile = null;
      uploaded = null;
      requestId = crypto.randomUUID();
      dirty = false;
      el("iqcChemFile").value = "";
      await fileLink(el("iqcChemFileLink"), fileMeta);
      await loadDashboard();
      status("Đã lưu báo cáo · " + (result.result || lot.result || "Chưa kết luận") + ".");
    } catch (e) {
      status("Chưa hoàn tất: " + e.message + ". Nếu mất mạng, giữ form và thử lưu lại.", true);
    } finally {
      locked.forEach(([e, disabled]) => (e.disabled = disabled));
      busy = false;
      el("saveBtn").disabled = false;
    }
  }
  form.addEventListener(
    "submit",
    (e) => {
      if (!chemical) return;
      e.preventDefault();
      e.stopImmediatePropagation();
      save();
    },
    true,
  );
  form.addEventListener("reset", (e) => {
    if (busy) {
      e.preventDefault();
      return;
    }
    clear();
    mode(false);
    item = null;
    queueMicrotask(() => refreshCatalog(false).catch((e) => status(e.message, true)));
  });
  el("productCode").addEventListener("change", () => select().catch((e) => status(e.message, true)));
  const previousEdit = editLot;
  editLot = async (id) => {
    if (busy) {
      status("Đang lưu báo cáo. Đợi hoàn tất trước khi mở báo cáo khác.");
      return;
    }
    const record = await IqcApi.getLot(id);
    if (record.method !== "hoa_hoc") {
      mode(false);
      await previousEdit(id);
      if (record.itemKind === "nvl") el("productCode").value = "[NVL] " + record.materialCode;
      return;
    }
    await refreshCatalog();
    clear();
    lot = record;
    editingId = record.id;
    item = IqcMaterialCatalog.resolve(record.materialCode, "nvl");
    if (!item) throw Error("Không tìm thấy mã NVL của báo cáo");
    mode(true);
    el("productCode").value = IqcMaterialCatalog.display(item);
    el("productName").value = record.productName;
    el("lotNo").value = record.lotNo;
    el("iqcChemDate").value = record.inspectionDate;
    contextDate = record.inspectionDate;
    el("iqcChemShift").value = record.shift;
    el("iqcChemSupplier").value = record.supplier;
    el("iqcChemStandardLink").href =
      "qc-manager.html?tab=tieuchuan&cd=iqc_hoa_hoc&ma=" + encodeURIComponent(record.materialCode);
    standard = record.chemical?.tieu_chuan || null;
    rows = (record.chemical?.nguyen_to || []).map((r) => ({
      ma_dac_tinh: r.element,
      lsl: r.min,
      usl: r.max,
      don_vi: r.unit,
      bat_buoc: r.required,
    }));
    values = Object.fromEntries((record.chemical?.nguyen_to || []).map((r) => [r.element, r.value ?? ""]));
    fileMeta = record.chemical?.file || null;
    candidates = record.chemical?.nguon?.candidates || [];
    el("iqcChemSourceUnit").value = record.chemical?.nguon?.unit || "";
    el("iqcChemConfirmed").checked = !!record.chemical?.xac_nhan;
    await loadPeople();
    const p = people.find((p) => p.username === record.inspectorId);
    el("inspector").value = p ? p.username + "_" + (p.full_name || p.username) : record.inspector;
    el("note").value = record.note;
    el("iqcChemStandard").textContent = standard
      ? "Đã lưu theo " + record.materialCode + " · " + record.grade + " · Revision " + standard.phien_ban
      : "Báo cáo chưa có tiêu chuẩn";
    renderRows();
    await fileLink(el("iqcChemFileLink"), fileMeta);
    showPage("iqc");
    section.scrollIntoView({ block: "start" });
  };
  const previousDetail = openDetail;
  openDetail = async (id) => {
    const record = await IqcApi.getLot(id);
    if (record.method !== "hoa_hoc") return previousDetail(id);
    el("detailModal").classList.remove("hidden");
    const body = el("detailBody");
    body.replaceChildren();
    const heading = document.createElement("h3");
    heading.textContent = "Kiểm tra thành phần hóa học · " + record.lotNo;
    body.append(heading);
    const info = document.createElement("p");
    info.textContent = [
      record.inspectionDate,
      record.shift,
      record.materialCode,
      record.productName,
      record.grade,
      record.supplier,
      record.chemical?.tieu_chuan?.phien_ban,
      record.inspectorName,
    ]
      .filter(Boolean)
      .join(" · ");
    body.append(info);
    const table = document.createElement("table");
    table.innerHTML =
      "<thead><tr><th>Nguyên tố</th><th>Min</th><th>Max</th><th>Đơn vị</th><th>Kết quả</th><th>Đánh giá</th></tr></thead>";
    const tb = document.createElement("tbody");
    for (const row of record.chemical?.nguyen_to || []) {
      const tr = document.createElement("tr");
      for (const v of [
        row.element,
        row.min ?? "—",
        row.max ?? "—",
        row.unit,
        row.value ?? "Chưa nhận diện",
        row.result,
      ]) {
        const td = document.createElement("td");
        td.textContent = v;
        tr.append(td);
      }
      if (row.result === "NG") tr.className = "ng";
      tb.append(tr);
    }
    table.append(tb);
    body.append(table);
    const result = document.createElement("p");
    result.textContent =
      "Kết luận lô: " + (record.result || "Chưa kết luận") + " · Không quy đổi nguyên tố NG thành PCS NG.";
    body.append(result);
    const file = document.createElement("div");
    body.append(file);
    await fileLink(file, record.chemical?.file);
  };
  async function fileLink(target, meta) {
    target.replaceChildren();
    if (!meta) return;
    const b = document.createElement("button");
    b.type = "button";
    b.textContent = "Xem file phân tích: " + meta.name;
    b.onclick = async () => {
      try {
        const signed = await check(sb.storage.from("iqc-phan-tich").createSignedUrl(meta.path, 600));
        if (meta.type === "application/pdf") Qc02View.pdf(signed.signedUrl);
        else if (/^image\//.test(meta.type || "")) Qc02View.photo(signed.signedUrl);
        else {
          const a = document.createElement("a");
          a.href = signed.signedUrl;
          a.download = meta.name;
          a.rel = "noopener";
          a.click();
        }
      } catch (e) {
        status("Không mở được file: " + e.message, true);
      }
    };
    target.append(b);
  }
  const previousComplete = openComplete;
  openComplete = async (id) => {
    const record = await IqcApi.getLot(id);
    return record.method === "hoa_hoc" ? editLot(id) : previousComplete(id);
  };
  const previousDelete = IqcApi.deleteLot.bind(IqcApi);
  IqcApi.deleteLot = async (id) => {
    const record = await IqcApi.getLot(id);
    return record.method === "hoa_hoc" ? check(sb.rpc("iqc_luu_tru_hoa_hoc", { p_id: id })) : previousDelete(id);
  };
  refreshCatalog().catch((e) => {
    catalogStatus.textContent = "Chưa tải được danh mục NVL: " + e.message;
  });
  window.addEventListener("iqc-product-master-loaded", () =>
    refreshCatalog(false).catch((e) => status(e.message, true)),
  );
  return { refreshCatalog, isChemical: () => chemical };
})();
