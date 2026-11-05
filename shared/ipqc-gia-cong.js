/* Machining IPQC: shared versioned standards, server judgement, snapshot dashboards. */
const IpqcGiaCong = (() => {
  const $ = (id) => document.getElementById(id),
    S = IpqcSpc,
    E = S.esc;
  const today = () => new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Ho_Chi_Minh" }).format(new Date());
  const stamp = (value) =>
    value ? new Date(value).toLocaleString("vi-VN", { timeZone: "Asia/Ho_Chi_Minh", hour12: false }) : "Chưa ghi nhận";
  let products = [],
    machines = [],
    versions = [],
    rights = {},
    rows = [],
    viewed = null,
    sourceDocument = null,
    drawingFile = null,
    previewUrl = null;
  let drawingBusy = false,
    readSerial = 0,
    versionSerial = 0,
    measureSerial = 0,
    uploadDocument = null,
    measureRows = [],
    measureStandard = null,
    measureEntry = null,
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
      error.code === "P0001" ? error.message :
        error.code === '42501' ? 'Bạn chưa có quyền thực hiện thao tác này. Liên hệ quản lý QC.' :
        'Chưa tải hoặc lưu được dữ liệu. Thử lại; mở chi tiết nếu cần báo quản lý QC.',
      true,
    );
    $("gcErrorDetails").hidden = false;
    $("gcErrorDetails").querySelector('pre').textContent =
      [error.code,error.message,error.details,error.hint].filter(Boolean).join('\n');
  }
  async function rpc(name, args) {
    const r = await sb.rpc(name, args);
    if (r.error) throw r.error;
    if (r.data?.ok === false) throw Object.assign(Error(r.data.error), { code: "P0001" });
    return r.data;
  }
  function table(target, headers, data) {
    if (!data.length) { target.innerHTML='<p class="muted">Chưa có dữ liệu</p>';return; }
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
    return {
      lsl:
        numeric(row.lsl) ??
        (numeric(row.danh_nghia) != null && numeric(row.dung_sai_duoi) != null
          ? numeric(row.danh_nghia) - Math.abs(numeric(row.dung_sai_duoi))
          : null),
      usl:
        numeric(row.usl) ??
        (numeric(row.danh_nghia) != null && numeric(row.dung_sai_tren) != null
          ? numeric(row.danh_nghia) + Math.abs(numeric(row.dung_sai_tren))
          : null),
    };
  }
  function changeTab(tab) {
    document.querySelectorAll("[data-panel]").forEach((p) => (p.hidden = p.dataset.panel !== tab));
    document.querySelectorAll("[data-tab]").forEach((b) => b.classList.toggle("active", b.dataset.tab === tab));
    if (tab === "dashboard") loadDashboard().catch(fail);
  }
  document.querySelectorAll("[data-tab]").forEach((b) => (b.onclick = () => changeTab(b.dataset.tab)));
  function productInfo() {
    const p = products.find((p) => p.ma_sp === $("gcProduct").value);
    $("gcProductInfo").textContent = p
      ? [p.ten_sp, p.ten_khach_hang].filter(Boolean).join(" · ")
      : "Chọn đúng mã trong danh mục sản phẩm.";
  }
  function sourcePosition(source) {
    const p = source?.vi_tri;
    return p ? " · vị trí (" + [p.x0 ?? p.x, p.y0 ?? p.y].map((v) => Number(v).toFixed(0)).join(", ") + ")" : "";
  }
  async function refreshVersions() {
    const r = await sbTaiHet(() => sb.from("ipqc_btk").select("*").eq("cong_doan", "gia_cong").order("id"));
    if (r.error) throw r.error;
    versions = r.data || [];
    const stepFilter=$('gcFilterStep'),oldStep=stepFilter.value;
    stepFilter.innerHTML='<option value="">Tất cả nguyên công</option>'+[...new Set(versions
      .map(v=>v.buoc_gia_cong).filter(Boolean))].sort().map(step=>'<option>'+E(step)+'</option>').join('');
    stepFilter.value=oldStep;
    const old = $("gcVersion").value;
    $("gcVersion").innerHTML =
      '<option value="">Tiêu chuẩn mới</option>' +
      versions
        .filter((v) => v.ma_sp === $("gcProduct").value)
        .map(
          (v) =>
            `<option value="${v.id}">${E(v.phien_ban)} · ${E(v.buoc_gia_cong || "Chưa khai báo bước")} · ${E(IpqcBtkQc.TT[v.trang_thai] || v.trang_thai)}</option>`,
        )
        .join("");
    $("gcVersion").value = old;
    await refreshMeasureVersions();
  }
  function editEnabled(enabled) {
    $("gcStandardForm")
      .querySelectorAll("input,select,textarea,button")
      .forEach((e) => (e.disabled = !enabled));
    $("gcSaveStandard").disabled = !enabled || drawingBusy;
    for (const id of ["gcClone", "gcLoadVersion", "gcProduct", "gcVersion"]) $(id).disabled = drawingBusy;
  }
  async function previewSaved() {
    if (previewUrl) {
      URL.revokeObjectURL(previewUrl);
      previewUrl = null;
    }
    const box = $("gcDrawingPreview");
    box.replaceChildren();
    let url = null;
    if (drawingFile) {
      url = previewUrl = URL.createObjectURL(drawingFile);
    } else if (sourceDocument?.path) {
      const r = await sb.storage.from("ipqc-gia-cong-ban-ve").createSignedUrl(sourceDocument.path, 3600);
      if (r.error) throw r.error;
      url = r.data.signedUrl;
    } else if (viewed?.ban_ve_url && /^https:\/\//i.test(viewed.ban_ve_url)) url = viewed.ban_ve_url;
    if (!url) {
      box.textContent = "Chưa có bản vẽ gốc.";
      return;
    }
    const pdf =
      drawingFile?.type === "application/pdf" ||
      /\.pdf$/i.test(sourceDocument?.name || "") ||
      /\.pdf(?:\?|$)/i.test(url);
    const element = document.createElement(pdf ? "iframe" : "img");
    element.className = "drawing";
    element.src = url;
    element.title = "Bản vẽ gốc";
    if (!pdf) element.alt = "Bản vẽ gốc";
    box.append(element);
  }
  function renderFeatures() {
    const fields = [
      "ma_dac_tinh",
      "hang_muc",
      "kieu",
      "danh_nghia",
      "dung_sai_tren",
      "dung_sai_duoi",
      "lsl",
      "usl",
      "don_vi",
      "phuong_phap",
      "dung_cu",
      "tan_suat",
      "co_mau",
      "tieu_chuan",
    ];
    $("gcFeatureRows").innerHTML = rows
      .map(
        (r, i) =>
          '<tr data-row="' +
          i +
          '"><td>' +
          E(r.muc_no) +
          "</td>" +
          fields
            .map((key) => {
              if (key === "kieu")
                return (
                  '<td><select data-field="kieu"><option value="so"' +
                  (r.kieu === "so" ? " selected" : "") +
                  '>Đo số</option><option value="okng"' +
                  (r.kieu === "okng" ? " selected" : "") +
                  ">OK/NG</option></select></td>"
                );
              if (key === "dung_cu") {
                const legacy =
                  r.dung_cu && !IpqcBtkQc.DUNG_CU.includes(r.dung_cu)
                    ? '<option selected disabled value="' + E(r.dung_cu) + '">Cũ: ' + E(r.dung_cu) + "</option>"
                    : "";
                return (
                  '<td><select data-field="dung_cu"><option value="">Chọn dụng cụ</option>' +
                  legacy +
                  IpqcBtkQc.DUNG_CU.map(
                    (t) => "<option" + (t === r.dung_cu ? " selected" : "") + ">" + E(t) + "</option>",
                  ).join("") +
                  "</select></td>"
                );
              }
              const attributes =
                key === "co_mau"
                  ? ' type="number" min="1" max="100" step="1"'
                  : /danh_nghia|dung_sai|lsl|usl/.test(key)
                    ? ' inputmode="decimal"'
                    : "";
              return '<td><input data-field="' + key + '" value="' + E(r[key] ?? "") + '"' + attributes + "></td>";
            })
            .join("") +
          '<td class="source">' +
          (r.nguon_nhan_dien
            ? E(
                "Trang " +
                  r.nguon_nhan_dien.trang +
                  sourcePosition(r.nguon_nhan_dien) +
                  " · " +
                  r.nguon_nhan_dien.phuong_phap +
                  " · độ tin cậy " +
                  (r.nguon_nhan_dien.do_tin_cay ?? "chưa xác định"),
              ) +
              "<br>" +
              E(r.nguon_nhan_dien.text)
            : "Nhập thủ công") +
          '</td><td><input type="checkbox" data-field="da_xac_nhan"' +
          (r.da_xac_nhan ? " checked" : "") +
          ' aria-label="Xác nhận đặc tính ' +
          E(r.muc_no) +
          '"></td><td><button type="button" data-recalculate="' +
          i +
          '">Tính lại giới hạn</button><button type="button" data-delete="' +
          i +
          '">Xóa dòng</button></td></tr>',
      )
      .join("");
    editEnabled(rights.soan && (!viewed || viewed.trang_thai !== "da_duyet"));
  }
  function calculate(row) {
    const n = numeric(row.danh_nghia),
      upper = numeric(row.dung_sai_tren),
      lower = numeric(row.dung_sai_duoi);
    row.lsl = n != null && lower != null ? Number((n + lower).toPrecision(12)) : "";
    row.usl = n != null && upper != null ? Number((n + upper).toPrecision(12)) : "";
  }
  $("gcFeatureRows").oninput = (event) => {
    const field = event.target.dataset.field,
      element = event.target.closest("[data-row]");
    if (!field || !element) return;
    const row = rows[+element.dataset.row];
    row[field] = field === "da_xac_nhan" ? event.target.checked : event.target.value;
    if (field !== "da_xac_nhan") {
      row.da_xac_nhan = false;
      element.querySelector('[data-field="da_xac_nhan"]').checked = false;
    }
    if (field === "lsl" || field === "usl") row.limitsManual = true;
    if (["danh_nghia", "dung_sai_tren", "dung_sai_duoi"].includes(field) && !row.limitsManual) {
      calculate(row);
      for (const key of ["lsl", "usl"]) element.querySelector('[data-field="' + key + '"]').value = row[key];
    }
  };
  $("gcFeatureRows").onclick = (event) => {
    const remove = event.target.closest("[data-delete]"),
      recalculate = event.target.closest("[data-recalculate]");
    if (remove) {
      rows.splice(+remove.dataset.delete, 1);
      renderFeatures();
    }
    if (recalculate) {
      const row = rows[+recalculate.dataset.recalculate];
      row.limitsManual = false;
      calculate(row);
      row.da_xac_nhan = false;
      renderFeatures();
    }
  };
  $("gcAddFeature").onclick = () => {
    const no = Math.max(0, ...rows.map((r) => +r.muc_no || 0)) + 1;
    rows.push({
      muc_no: no,
      ma_dac_tinh: "KT-" + String(no).padStart(3, "0"),
      hang_muc: "",
      kieu: "so",
      co_mau: 1,
      da_xac_nhan: false,
    });
    renderFeatures();
  };
  $("gcConfirmFeatures").onclick = () => {
    rows.forEach((r) => (r.da_xac_nhan = true));
    renderFeatures();
  };
  $("gcProduct").onchange = () => {
    productInfo();
    refreshVersions().catch(fail);
  };
  $("gcLoadVersion").onclick = async () => {
    const serial = ++versionSerial;
    ++readSerial;
    drawingBusy = false;
    try {
      viewed = versions.find((v) => String(v.id) === $("gcVersion").value) || null;
      drawingFile = null;
      uploadDocument = null;
      if (!viewed) {
        rows = [];
        sourceDocument = null;
        $("gcStandardForm").reset();
        $("gcEffective").value = today();
        renderFeatures();
        await previewSaved();
        return;
      }
      $("gcProduct").value = viewed.ma_sp;
      productInfo();
      for (const [id, key] of [
        ["gcDrawingCode", "ma_ban_ve"],
        ["gcRevision", "phien_ban"],
        ["gcProcess", "buoc_gia_cong"],
        ["gcEffective", "ngay_hieu_luc"],
        ["gcChange", "noi_dung_sua_doi"],
      ])
        $(id).value = viewed[key] || "";
      const data = await sb.from("ipqc_btk_muc").select("*").eq("id_btk", viewed.id).order("muc_no");
      if (serial !== versionSerial) return;
      if (data.error) throw data.error;
      rows = (data.data || []).map((r) => ({
        ...r,
        limitsManual: r.lsl != null || r.usl != null,
        dung_sai_duoi: r.dung_sai_duoi == null ? "" : -Number(r.dung_sai_duoi),
        co_mau: r.co_mau || viewed.so_mau || 1,
        da_xac_nhan: false,
      }));
      sourceDocument = viewed.tai_lieu_goc;
      $("gcApproval").innerHTML = IpqcBtkQc.khoiDuyet(viewed, rights);
      renderFeatures();
      await previewSaved();
      const history = await sb
        .from("ipqc_gc_tieu_chuan_lich_su")
        .select("id,thoi_diem,du_lieu")
        .eq("id_btk", viewed.id)
        .order("id");
      if (serial !== versionSerial) return;
      if (history.error) throw history.error;
      table(
        $("gcStandardHistory"),
        ["Lần lưu", "Thời điểm", "Revision", "Bản vẽ", "Số đặc tính"],
        (history.data || []).map((r) => [
          r.id,
          stamp(r.thoi_diem),
          r.du_lieu.tieu_chuan.phien_ban,
          r.du_lieu.tieu_chuan.ma_ban_ve,
          r.du_lieu.muc?.length || 0,
        ]),
      );
    } catch (error) {
      fail(error);
    }
  };
  $("gcClone").onclick = () => {
    viewed = null;
    $("gcRevision").value = "";
    $("gcChange").value = "Revision mới";
    $("gcEffective").value = today();
    rows.forEach((r) => (r.da_xac_nhan = false));
    $("gcApproval").replaceChildren();
    renderFeatures();
  };
  $("gcApproval").onclick = async (event) => {
    const button = event.target.closest("[data-duyet]");
    if (!button || !viewed) return;
    button.disabled = true;
    try {
      await IpqcBtkQc.duyet("btk", viewed.id, button.dataset.duyet);
      await refreshVersions();
      $("gcLoadVersion").click();
    } catch (error) {
      fail(error);
      button.disabled = false;
    }
  };
  $("gcDrawing").onchange = async () => {
    const file = $("gcDrawing").files[0];
    if (!file) return;
    const serial = ++readSerial;
    drawingBusy = true;
    drawingFile = file;
    uploadDocument = null;
    editEnabled(false);
    try {
      await previewSaved();
      const read = await IpqcDrawingReader.read(file, (text) => {
        if (serial === readSerial) $("gcReadProgress").textContent = text;
      });
      if (serial !== readSerial) return;
      rows = read.rows;
      sourceDocument = null;
      $("gcReadWarning").textContent = read.warnings.join("\n");
      $("gcReadProgress").textContent =
        "Đã nhận diện " + rows.length + " ứng viên. Kiểm tra từng dòng trước khi gửi duyệt.";
    } catch (error) {
      if (serial === readSerial) {
        rows = [];
        $("gcReadWarning").textContent = "Không đọc được bản vẽ. Có thể nhập thủ công; không tự tạo kích thước.";
        fail(error);
      }
    } finally {
      if (serial === readSerial) {
        drawingBusy = false;
        renderFeatures();
      }
    }
  };
  $("gcStandardForm").onsubmit = async (event) => {
    event.preventDefault();
    if (drawingBusy || !rights.soan) return;
    const button = $("gcSaveStandard");
    button.disabled = true;
    try {
      if (!products.some((p) => p.ma_sp === $("gcProduct").value))
        throw Object.assign(Error("Chọn model từ danh mục."), { code: "P0001" });
      if (!rows.length || rows.some((r) => !r.da_xac_nhan))
        throw Object.assign(Error("Đối chiếu và xác nhận từng đặc tính trước khi gửi duyệt."), { code: "P0001" });
      if (drawingFile && !uploadDocument) {
        const session = await MesAuth.getSession();
        const user = session?.user || session?.data?.session?.user;
        if (!user?.id) throw Error("Cần đăng nhập");
        const path = user.id + "/" + crypto.randomUUID() + "/" + drawingFile.name.replace(/[^a-zA-Z0-9._-]/g, "_");
        const uploaded = await sb.storage
          .from("ipqc-gia-cong-ban-ve")
          .upload(path, drawingFile, {
            contentType:
              drawingFile.type ||
              (/\.pdf$/i.test(drawingFile.name)
                ? "application/pdf"
                : /\.png$/i.test(drawingFile.name)
                  ? "image/png"
                  : "image/jpeg"),
          });
        if (uploaded.error) throw uploaded.error;
        uploadDocument = { path, name: drawingFile.name, size: drawingFile.size };
      }
      const payload = {
        ma_sp: $("gcProduct").value,
        ma_ban_ve: $("gcDrawingCode").value,
        phien_ban: $("gcRevision").value,
        buoc_gia_cong: $("gcProcess").value,
        ngay_hieu_luc: $("gcEffective").value,
        noi_dung_sua_doi: $("gcChange").value,
        so_mau: 1,
        tai_lieu_goc: uploadDocument || sourceDocument,
        muc: rows.map((r) => ({
          ...r,
          danh_nghia: numeric(r.danh_nghia),
          dung_sai_tren: numeric(r.dung_sai_tren),
          dung_sai_duoi: numeric(r.dung_sai_duoi),
          lsl: numeric(r.lsl),
          usl: numeric(r.usl),
          co_mau: Number(r.co_mau || 1),
        })),
      };
      const saved = await rpc("ipqc_gc_luu_tieu_chuan", { p_data: payload });
      await refreshVersions();
      $("gcVersion").value = String(saved.id);
      $("gcLoadVersion").click();
      notify("Đã lưu bản nháp. Chờ Trưởng phòng QC kiểm tra và Giám đốc sản xuất phát hành.");
    } catch (error) {
      fail(error);
    } finally {
      button.disabled = false;
    }
  };
  async function refreshMeasureVersions() {
    const previous=$('gcMeasureVersion').value;
    const options = versions
      .filter(
        (v) =>
          v.ma_sp === $("gcMeasureProduct").value &&
          v.trang_thai === "da_duyet" && v.dang_dung !== false &&
          (!v.ngay_hieu_luc || v.ngay_hieu_luc <= today()),
      )
      .sort((a, b) => (b.ngay_hieu_luc || "").localeCompare(a.ngay_hieu_luc || "") || b.id - a.id);
    $("gcMeasureVersion").innerHTML = options
      .map((v) => `<option value="${v.id}">${E(v.phien_ban)} · ${E(v.buoc_gia_cong || "Chưa khai báo bước")}</option>`)
      .join("");
    if(options.some(v=>String(v.id)===previous))$('gcMeasureVersion').value=previous;
    if(measureEntry&&String(measureStandard?.id)===$('gcMeasureVersion').value)return;
    await loadMeasureStandard();
  }
  async function loadMeasureStandard() {
    const serial = ++measureSerial,
      selected = versions.find((v) => String(v.id) === $("gcMeasureVersion").value) || null;
    measureStandard = null;
    measureRequest = null;
    measureRows = [];measureEntry=null;
    $("gcAddSample").disabled = true;
    $("gcSaveMeasure").disabled = true;
    if (!selected) {
      $("gcMeasureInfo").textContent = "Chưa có tiêu chuẩn Gia công đã duyệt/có hiệu lực cho model này.";
      $("gcMeasureRows").replaceChildren();
      return;
    }
    const r = await sb.from("ipqc_btk_muc").select("*").eq("id_btk", selected.id).order("muc_no");
    if (serial !== measureSerial) return;
    if (r.error) throw r.error;
    measureRows = r.data || [];
    measureStandard = selected;
    if(!measureRows.length){
      $('gcMeasureInfo').textContent='Tiêu chuẩn đã chọn chưa có đặc tính kiểm tra. Liên hệ quản lý QC.';
      $('gcMeasureRows').textContent='Chưa có dữ liệu';return;
    }
    $('gcMeasureInfo').textContent=selected.ma_sp+' · Revision '+selected.phien_ban+
      (selected.buoc_gia_cong?' · Nguyên công: '+selected.buoc_gia_cong:'')+
      ' · Tiêu chuẩn áp dụng '+(selected.ngay_hieu_luc||'theo phiên bản đã phát hành');
    measureEntry=IpqcGcEntry.mount($('gcMeasureRows'),measureRows,selected,updateMeasureStatus);
    const canMeasure=['admin','qc_manager','ipqc'].includes(rights.role);
    measureEntry.setDisabled(!canMeasure);$('gcAddSample').disabled=!canMeasure;
  }
  function updateMeasureStatus(state){
    $('gcMeasureSummary').textContent='Đã nhập '+state.filled+'/'+state.total+' giá trị · '+
      (state.complete?(state.dat?'Lần kiểm: OK':'Lần kiểm: NG'):'Chưa đủ dữ liệu để kết luận lần kiểm');
    $('gcMeasureSummary').className=state.complete?(state.dat?'good':'bad'):'muted';
    $('gcSaveMeasure').disabled=!state.complete||!['admin','qc_manager','ipqc'].includes(rights.role);
  }
  $('gcAddSample').onclick=()=>measureEntry?.addSample();
  $('gcMeasureProduct').onchange=()=>refreshMeasureVersions().catch(fail);
  $('gcMeasureVersion').onchange=()=>loadMeasureStandard().catch(fail);
  $("gcMeasureForm").onsubmit = async (event) => {
    event.preventDefault();
    if (!measureStandard) return;
    const button = $("gcSaveMeasure");
    button.disabled = true;
    try {
      const kq = measureEntry.payload();
      const payload = {
        ma_sp: measureStandard.ma_sp,
        id_btk: measureStandard.id,
        ma_may: $("gcMachine").value,
        ca: $("gcShift").value,
        ma_lo: $("gcLot").value,
        co_mau_thuc_te:measureEntry.sampleCounts(),
        kq,
      };
      const signature = JSON.stringify(payload);
      if (measureRequest?.signature !== signature) measureRequest = { id: crypto.randomUUID(), signature };
      const id = await rpc("ipqc_gc_luu_do", { p_data: { ...payload, request_id: measureRequest.id } });
      const saved = await sb.from("ipqc_gc_lan").select("dat,thoi_diem").eq("id", id).single();
      if (saved.error) throw saved.error;
      notify("Đã lưu " + (saved.data.dat ? "OK" : "NG") + " · " + stamp(saved.data.thoi_diem));
      measureRequest = null;
      await loadMeasureStandard();
      await loadDashboard();
    } catch (error) {
      fail(error);
    } finally {
      button.disabled = !measureEntry?.status().complete;
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
        .gte("thoi_diem", $("gcFrom").value + "T00:00:00+07:00")
        .lte("thoi_diem", $("gcTo").value + "T23:59:59.999999+07:00")
        .order("thoi_diem")
        .order("id");
      for (const [id, column] of [
        ["gcDashboardProcess", "cong_doan"],
        ["gcFilterProduct", "ma_sp"],
        ["gcFilterRevision", "revision"],
        ["gcFilterStep", "buoc_gia_cong"],
        ["gcFilterMachine", "ma_may"],
        ["gcFilterShift", "ca"],
        ["gcFilterLot", "ma_lo"],
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
      ["Lượt kiểm", data.length],
      ["Tổng mẫu", samples],
      ["OK", ok],
      ["NG", ng],
      ["Tỷ lệ NG", data.length ? ((ng / data.length) * 100).toFixed(2) + "%" : "Chưa có dữ liệu"],
    ]
      .map(([key, value]) => '<div class="metric">' + E(key) + "<b>" + E(value) + "</b></div>")
      .join("");
    const detail = [];
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
          stamp(r.thoi_diem),
          m.ma_dac_tinh || k.muc_no,
          m.hang_muc,
          k.mau,
          k.gia_tri ?? (k.dat ? "OK" : "NG"),
          limits.lsl,
          limits.usl,
          k.dat ? "OK" : "NG",
        ]);
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
        "Thời điểm",
        "Mã đặc tính",
        "Tên",
        "Mẫu",
        "Giá trị",
        "LSL",
        "USL",
        "Kết quả",
      ],
      detail.slice(0, rowLimit),
    );
    $("gcMoreRows").hidden = detail.length <= rowLimit;
    table(
      $("gcTopNg"),
      ["Đặc tính / Revision", "Số giá trị NG"],
      [...defects].sort((a, b) => b[1] - a[1]),
    );
    renderCharts(data);
  }
  function renderCharts(data) {
    const selected = $("gcFilterFeature").value;
    $("gcValueChart").replaceChildren();
    $("gcSpcChart").replaceChildren();
    $("gcCapability").textContent = "";
    if (!selected) {
      $("gcValueChart").textContent =
        "Chọn một đặc tính và phiên bản để xem biểu đồ; không trộn dung sai giữa Revision.";
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
          tg: stamp(r.thoi_diem),
          nhan: stamp(r.thoi_diem) + " · mẫu " + k.mau + " · " + (k.dat ? "OK" : "NG"),
          mau: k.dat ? "#0f5fa5" : "#b91c1c",
        }),
      );
      if (vs.length)
        groups.push({
          x: vs.reduce((n, v) => n + v, 0) / vs.length,
          r: Math.max(...vs) - Math.min(...vs),
          vals: vs,
          tg: stamp(r.thoi_diem),
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
        "SPC cần ít nhất 25 nhóm cùng cỡ mẫu (1–5), cùng Revision/đặc tính và một máy. Chưa đủ điều kiện.";
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
      " · UCL/LCL ước lượng từ dữ liệu, khác LSL/USL kỹ thuật.</p>" +
      S.bieuDo({ pts: groups, lim }) +
      S.bieuDo({
        pts:
          n === 1
            ? groups.slice(1).map((g, i) => ({ ...g, x: Math.abs(g.x - groups[i].x) }))
            : groups.map((g) => ({ ...g, x: g.r })),
        lim: { cl: lim.clR, ucl: lim.uclR, lcl: 0 },
        nhanGH: ["UCL", "Trung bình biên độ", "LCL"],
      });
    if (values.length >= 100 && groups.length >= 30 && !violations.length && $("gcCapabilityConfirmed").checked) {
      const cap = IpqcGcMath.capability(groups, limits);
      $("gcCapability").textContent = cap
        ? "Cp: " +
          (cap.cp?.toFixed(3) ?? "—") +
          " · Cpk: " +
          (cap.cpk?.toFixed(3) ?? "—") +
          " · σ trong nhóm: " +
          cap.sigma.toPrecision(4)
        : "Thiếu giới hạn kỹ thuật hoặc độ biến thiên để tính Cp/Cpk.";
    } else
      $("gcCapability").textContent =
        "Cp/Cpk cần ít nhất 100 giá trị, 30 nhóm, không có tín hiệu mất kiểm soát và xác nhận điều kiện quá trình/phân phối. Chưa đánh giá.";
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
          "Thời điểm": stamp(r.thoi_diem),
          "Đặc tính": m.ma_dac_tinh || k.muc_no,
          Tên: m.hang_muc,
          Mẫu: k.mau,
          "Giá trị": k.gia_tri,
          LSL: limits.lsl,
          USL: limits.usl,
          "Kết quả": k.dat ? "OK" : "NG",
        });
      }
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, XLSX.utils.json_to_sheet(out), "IPQC");
    XLSX.writeFile(workbook, "IPQC-theo-bo-loc.xlsx");
  };
  async function boot() {
    if (IS_PROD) throw Error("Chức năng này đang triển khai trên staging.");
    MesNav.setTitle("IPQC Gia công");
    rights = await IpqcBtkQc.quyen();
    [products, machines] = await Promise.all([
      Qc02Data.readAll("master_products"),
      (async()=>{
        const r=await sbTaiHet(()=>sb.from('master_machines').select('*').order('ma_may'));
        if(r.error)throw r.error;
        return r.data||[];
      })(),
    ]);
    $("gcProducts").innerHTML = products
      .map((p) => '<option value="' + E(p.ma_sp) + '">' + E(p.ten_sp || "") + "</option>")
      .join("");
    const customers = [...new Set(products.map((p) => p.ten_khach_hang || p.ma_khach_hang).filter(Boolean))].sort();
    $("gcCustomer").innerHTML =
      '<option value="">Tất cả</option>' + customers.map((c) => "<option>" + E(c) + "</option>").join("");
    $("gcCustomer").onchange = () => {
      const subset = products.filter(
        (p) => !$("gcCustomer").value || (p.ten_khach_hang || p.ma_khach_hang) === $("gcCustomer").value,
      );
      $("gcProducts").innerHTML = subset
        .map((p) => '<option value="' + E(p.ma_sp) + '">' + E(p.ten_sp || "") + "</option>")
        .join("");
      if (!subset.some((p) => p.ma_sp === $("gcProduct").value)) {
        $("gcProduct").value = "";
        productInfo();
        refreshVersions().catch(fail);
      }
    };
    $("gcMachine").innerHTML = machines
      .filter((m) => m.bo_phan === "Gia công - Sơn")
      .map((m) => "<option>" + E(m.ma_may) + "</option>")
      .join("");
    $("gcMachines").innerHTML = machines.map((m) => "<option>" + E(m.ma_may) + "</option>").join("");
    $("gcEffective").value = $("gcFrom").value = $("gcTo").value = today();
    await refreshVersions();
    renderFeatures();
    const params = new URLSearchParams(location.search);
    if (params.get("view") === "dashboard") changeTab("dashboard");
    if (params.has("standard")) {
      changeTab("standards");
      $("gcProduct").value = params.get("standard");
      productInfo();
      await refreshVersions();
      $("gcVersion").value =
        params.get("version") || String(versions.filter((v) => v.ma_sp === params.get("standard")).at(-1)?.id || "");
      await $("gcLoadVersion").onclick();
    }
    if (params.has("ma")) {
      $("gcMeasureProduct").value = params.get("ma");
      await refreshMeasureVersions();
      changeTab("measure");
    }
    setInterval(() => ($("clock").textContent = stamp(new Date())), 1000);
  }
  boot().catch(fail);
  return { refresh: loadDashboard };
})();
