/* Chemical standards are another category in the existing Quality standards screen and approval workflow. */
const IqcChemicalStandard = (() => {
  const el = (id) => document.getElementById(id),
    C = IqcChemistry;
  let root,
    material = null,
    versions = [],
    version = null,
    rows = [],
    canEdit = false,
    manager = false,
    userId = null,
    serial = 0,
    versionSerial = 0,
    loading = false,
    saving = false,
    permissions = {};
  const esc = (s) =>
    String(s ?? "").replace(
      /[&<>"']/g,
      (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c],
    );
  async function rpc(name, args) {
    const r = await sb.rpc(name, args);
    if (r.error || r.data?.ok === false) throw Error(r.error?.message || r.data.error);
    return r.data;
  }
  function message(text, error = false) {
    el("iqcTcMessage").textContent = text;
    el("iqcTcMessage").classList.toggle("err", error);
  }
  function make() {
    root = document.createElement("section");
    root.id = "iqc-chemical-standard";
    root.className = "panel iqc-chemical";
    root.hidden = true;
    root.innerHTML =
      '<div class="panel-head">Tiêu chuẩn thành phần hóa học IQC — NVL BOM</div><div class="panel-body">' +
      '<div class="iqc-chem-grid"><label>Mã / tên NVL<select id="iqcTcMaterial"></select></label><label>Nhóm vật liệu<select id="iqcTcGroup"><option value="">Chưa phân loại</option><option value="nhom">Nhôm</option><option value="kem">Kẽm</option><option value="khac">NVL khác — kiểm ngoại quan</option></select></label><label>Mác vật liệu<input id="iqcTcGrade"></label><button type="button" id="iqcTcClassification">Lưu phân loại theo mã NVL</button></div>' +
      '<p class="help">Phân loại theo định danh NVL. Không suy đoán từ tên; không tự tạo giới hạn hóa học. Danh mục lấy trực tiếp từ BOM.</p>' +
      '<div class="iqc-chem-grid"><label>Phiên bản tiêu chuẩn<select id="iqcTcVersions"></select></label><button type="button" id="iqcTcNew">Soạn phiên bản mới</button><label>Revision<input id="iqcTcRevision"></label><label>Ngày hiệu lực<input id="iqcTcDate" type="date"></label><label>Nội dung sửa đổi<input id="iqcTcChange"></label></div>' +
      '<div id="iqcTcApproval"></div><div class="iqc-chem-table"><table><thead><tr><th>Nguyên tố</th><th>Min</th><th>Max</th><th>Đơn vị</th><th>Bắt buộc</th><th></th></tr></thead><tbody id="iqcTcRows"></tbody></table></div>' +
      '<datalist id="iqcTcElements">' +
      C.ELEMENTS.map((e) => "<option>" + e + "</option>").join("") +
      "</datalist>" +
      '<div class="iqc-chem-actions"><button type="button" id="iqcTcAdd">+ Thêm nguyên tố</button><button type="button" id="iqcTcDraft">Lưu bản nháp</button><button type="button" id="iqcTcSend">Gửi kiểm tra / phê duyệt</button></div><p role="status" id="iqcTcMessage"></p><details><summary>Lịch sử tiêu chuẩn / phân loại</summary><div id="iqcTcHistory"></div></details></div>';
    el("tab-tieuchuan").append(root);
    el("iqcTcMaterial").onchange = () => selectMaterial().catch((e) => message(e.message, true));
    el("iqcTcVersions").onchange = () => selectVersion().catch((e) => message(e.message, true));
    el("iqcTcClassification").onclick = async () => {
      try {
        if (!material) throw Error("Chọn mã NVL trước khi phân loại.");
        await rpc("iqc_nvl_luu_phan_loai", {
          p_ma_nvl: material.code,
          p_nhom: el("iqcTcGroup").value,
          p_mac: el("iqcTcGrade").value,
        });
        await IqcMaterialCatalog.load(true);
        material = IqcMaterialCatalog.resolve(material.code, "nvl");
        message("Đã lưu phân loại NVL.");
      } catch (e) {
        message(e.message, true);
      }
    };
    el("iqcTcNew").onclick = () => {
      version = null;
      rows = [];
      el("iqcTcRevision").value = "";
      el("iqcTcChange").value = "";
      el("iqcTcDate").value = new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Bangkok" }).format(new Date());
      render();
    };
    el("iqcTcAdd").onclick = () => {
      capture();
      rows.push({ element: "", min: "", max: "", unit: "%", required: true });
      renderRows();
    };
    el("iqcTcDraft").onclick = () => save(false);
    el("iqcTcSend").onclick = () => save(true);
  }
  function editable() {
    return (
      canEdit &&
      !loading &&
      !saving &&
      (!version ||
        (["ban_nhap", "tra_lai"].includes(version.trang_thai) && (manager || version.nguoi_lap_uid === userId)))
    );
  }
  function capture() {
    rows = [...el("iqcTcRows").rows].map((tr) =>
      Object.fromEntries(
        ["element", "min", "max", "unit", "required"].map((k) => [
          k,
          k === "required"
            ? tr.querySelector("[data-k=" + k + "]").checked
            : tr.querySelector("[data-k=" + k + "]").value,
        ]),
      ),
    );
  }
  function renderRows() {
    el("iqcTcRows").innerHTML = rows
      .map(
        (r, i) =>
          '<tr><td><input list="iqcTcElements" data-k="element" value="' +
          esc(r.element) +
          '"></td><td><input inputmode="decimal" data-k="min" value="' +
          esc(r.min) +
          '"></td><td><input inputmode="decimal" data-k="max" value="' +
          esc(r.max) +
          '"></td><td><select data-k="unit">' +
          ["%", "ppm", "mg/kg"]
            .map((u) => "<option" + (u === r.unit ? " selected" : "") + ">" + u + "</option>")
            .join("") +
          '</select></td><td><input data-k="required" type="checkbox"' +
          (r.required ? " checked" : "") +
          '></td><td><button type="button" data-remove="' +
          i +
          '">Xóa</button></td></tr>',
      )
      .join("");
    el("iqcTcRows")
      .querySelectorAll("input,select,button")
      .forEach((e) => (e.disabled = !editable()));
    el("iqcTcRows")
      .querySelectorAll("[data-remove]")
      .forEach(
        (b) =>
          (b.onclick = () => {
            capture();
            rows.splice(Number(b.dataset.remove), 1);
            renderRows();
          }),
      );
  }
  async function render() {
    renderRows();
    for (const id of ["iqcTcRevision", "iqcTcDate", "iqcTcChange", "iqcTcAdd", "iqcTcDraft", "iqcTcSend"])
      el(id).disabled = !editable();
    el("iqcTcNew").disabled = !canEdit || !material || loading || saving;
    for (const id of ["iqcTcGroup", "iqcTcGrade", "iqcTcClassification"])
      el(id).disabled = !canEdit || !material || saving;
    el("iqcTcApproval").innerHTML = !material
      ? "Chọn mã NVL để xem hoặc soạn tiêu chuẩn."
      : loading || saving
        ? "Đang xử lý tiêu chuẩn..."
        : version && version.trang_thai !== "da_duyet"
          ? IpqcBtkQc.khoiDuyet(version, permissions)
          : version
            ? "Đã phê duyệt · " + esc(version.phien_ban)
            : "Bản nháp mới — phải qua kiểm tra và phê duyệt trước khi áp dụng.";
    el("iqcTcApproval")
      .querySelectorAll("[data-duyet]")
      .forEach(
        (b) =>
          (b.onclick = async () => {
            try {
              await IpqcBtkQc.duyet("btk", version.id, b.dataset.duyet);
              await selectMaterial(version.id);
            } catch (e) {
              message(e.message, true);
            }
          }),
      );
    el("iqcTcApproval").querySelector("[data-huy]")?.remove(); // Retain all entered standards and history in this category.
  }
  async function selectVersion() {
    const id = el("iqcTcVersions").value,
      code = material?.code,
      ticket = ++versionSerial;
    const selected = versions.find((v) => String(v.id) === id) || null;
    loading = true;
    await render();
    let nextRows = [];
    if (selected) {
      const r = await sb.from("ipqc_btk_muc").select("*").eq("id_btk", selected.id).order("muc_no");
      if (r.error) throw r.error;
      nextRows = (r.data || []).map((m) => ({
        element: m.ma_dac_tinh,
        min: m.lsl ?? "",
        max: m.usl ?? "",
        unit: m.don_vi,
        required: m.nguon_nhan_dien?.bat_buoc !== false,
      }));
    }
    if (ticket !== versionSerial || code !== material?.code || id !== el("iqcTcVersions").value) return;
    version = selected;
    rows = nextRows;
    loading = false;
    el("iqcTcRevision").value = version?.phien_ban || "";
    el("iqcTcDate").value = version?.ngay_hieu_luc || "";
    el("iqcTcChange").value = version?.noi_dung_sua_doi || "";
    await render();
  }
  async function selectMaterial(preferred) {
    const ticket = ++serial;
    ++versionSerial;
    material = IqcMaterialCatalog.resolve(el("iqcTcMaterial").value, "nvl");
    version = null;
    rows = [];
    loading = true;
    await render();
    if (!material) {
      versions = [];
      for (const id of ["iqcTcVersions", "iqcTcRevision", "iqcTcDate", "iqcTcChange", "iqcTcGroup", "iqcTcGrade"])
        el(id).value = "";
      return;
    }
    el("iqcTcGroup").value = material.group || "";
    el("iqcTcGrade").value = material.grade || "";
    const response = await sb
      .from("ipqc_btk")
      .select("*")
      .eq("cong_doan", "iqc_hoa_hoc")
      .eq("ma_nvl", material.code)
      .order("tao_luc", { ascending: false });
    if (response.error) throw response.error;
    if (ticket !== serial) return;
    versions = response.data || [];
    el("iqcTcVersions").replaceChildren(
      ...versions.map(
        (v) =>
          new Option(v.phien_ban + " · " + (IpqcBtkQc.TT[v.trang_thai] || v.trang_thai) + " · " + v.mac_vat_lieu, v.id),
      ),
    );
    if (preferred) el("iqcTcVersions").value = String(preferred);
    await selectVersion();
    const h = await sb
      .from("iqc_lich_su")
      .select("*")
      .in("loai", ["phan_loai", "tieu_chuan", "duyet_tieu_chuan"])
      .order("thoi_diem", { ascending: false })
      .limit(100);
    if (!h.error && ticket === serial) {
      el("iqcTcHistory").replaceChildren(
        ...(h.data || [])
          .filter((x) => x.khoa === material.code || versions.some((v) => String(v.id) === x.khoa))
          .map((x) => {
            const p = document.createElement("p");
            p.textContent =
              new Date(x.thoi_diem).toLocaleString("vi-VN", { hour12: false }) +
              " · " +
              (x.nguoi || "") +
              " · " +
              x.loai;
            return p;
          }),
      );
    }
  }
  async function save(send) {
    if (!editable() || !material) return;
    capture();
    saving = true;
    const controls = [...root.querySelectorAll("input,select,button")].map((e) => [e, e.disabled]);
    controls.forEach(([e]) => (e.disabled = true));
    const buttons = ["iqcTcDraft", "iqcTcSend"].map(el);
    buttons.forEach((b) => (b.disabled = true));
    try {
      const data = {
        ma_nvl: material.code,
        phien_ban: el("iqcTcRevision").value,
        ngay_hieu_luc: el("iqcTcDate").value,
        noi_dung_sua_doi: el("iqcTcChange").value,
        nguyen_to: rows.map((r) => ({ ...r, element: C.element(r.element) || r.element })),
      };
      const id = await rpc("iqc_tc_luu_hoa_hoc", { p_id: version?.id || null, p_data: data, p_gui: send });
      await selectMaterial(id);
      message(send ? "Đã gửi kiểm tra theo quy trình phê duyệt tiêu chuẩn." : "Đã lưu bản nháp.");
    } catch (e) {
      message(e.message, true);
    } finally {
      saving = false;
      controls.forEach(([e, disabled]) => (e.disabled = disabled));
      await render();
    }
  }
  async function show() {
    if (!root) make();
    const q = await IpqcBtkQc.quyen();
    permissions = q;
    canEdit = ["iqc", "qc_manager", "admin"].includes(q.role);
    manager = ["admin", "qc_manager"].includes(q.role);
    userId = q.uid;
    const catalog = await IqcMaterialCatalog.load(true);
    el("iqcTcMaterial").replaceChildren(
      new Option("Chọn mã / tên NVL", ""),
      ...catalog.materials.map((n) => new Option(n.code + " — " + n.name, n.code)),
    );
    for (const id of ["iqcTcGroup", "iqcTcGrade", "iqcTcClassification"]) el(id).disabled = !canEdit;
    const code = new URLSearchParams(location.search).get("ma") || material?.code;
    if (code && catalog.materials.some((x) => x.code === code)) {
      el("iqcTcMaterial").value = code;
      await selectMaterial();
    } else await selectMaterial();
    for (const child of el("tab-tieuchuan").children) if (child !== el("tc-cd-bar")) child.hidden = child !== root;
    el("tc-cd-bar")
      .querySelectorAll("[data-cd]")
      .forEach((b) => b.classList.toggle("on", b.dataset.cd === "iqc_hoa_hoc"));
    el("tc-cd-note").textContent =
      "Tiêu chuẩn hóa học theo đúng mã NVL / mác; dùng chung quy trình soạn → TP QC → GĐ SX.";
  }
  const previousChoose = chonCongDoanTc;
  chonCongDoanTc = async (cd) => {
    if (cd === "iqc_hoa_hoc") {
      try {
        await show();
      } catch (e) {
        if (root) message(e.message, true);
      }
      return;
    }
    if (root) {
      for (const child of el("tab-tieuchuan").children) child.hidden = child === root;
    }
    await previousChoose(cd);
    veCongDoanTc();
  };
  const previousOpen = moTabTieuChuan;
  moTabTieuChuan = async () => {
    await previousOpen();
    if (new URLSearchParams(location.search).get("cd") === "iqc_hoa_hoc") await show();
  };
  return { show };
})();
