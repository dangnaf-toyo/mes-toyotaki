/* MES-backed creation controls; SQL remains the authority for all approval decisions. */
const MesIpqcApproval = (() => {
  let available = [],
    selected = null,
    checkpoint = null,
    account = null,
    role = "",
    turn = 0,
    busy = false,
    token = "",
    proposalWarningId = "",
    inbox = [],
    loadingWarnings = false,
    queuedWarnings = false;
  const el = (id) => document.getElementById(id),
    val = (id) => el(id).value.trim();
  function options() {
    const text = val("runningSearch").toLocaleLowerCase();
    el("runningJob").replaceChildren(new Option("Chọn công việc đang chạy", ""));
    for (const job of available.filter((r) =>
      [r.ma_may, r.ma_sp, r.id_dong].join(" ").toLocaleLowerCase().includes(text),
    ))
      el("runningJob").add(
        new Option(job.ma_may + " / " + job.ma_sp + " / " + job.ca + " / " + job.id_dong, job.id_dong),
      );
    if (selected) el("runningJob").value = selected.id_dong;
  }
  async function refresh() {
    available = await MesIpqcFlow.jobs();
    options();
  }
  function preview() {
    const source = MesIpqcFlow.data(selected, checkpoint);
    el("proposalWarningFaults").textContent = checkpoint
      ? "Loại lỗi đã ghi nhận: " + MesIpqcFlow.defects(checkpoint).map(MesQcFields.cleanText).join(" / ")
      : "";
    for (const id of [
      "approvalDefectType",
      "approvalDefectQty",
      "actualValue",
      "standardMin",
      "standardMax",
      "warningLevel",
    ])
      el(id).closest(".field").hidden = !!checkpoint;
    el("checkpointId").value = source.checkpoint_id || "";
    el("machine").value = source.machine || "";
    el("process").value = source.process || "";
    el("productCode").value = source.product_code || "";
    el("lotNo").value = source.lot_no || "";
    el("taskNo").value = source.task_no || "";
    el("jobInfo").textContent =
      "Phiên " +
      selected.id_dong +
      " · " +
      selected.ngay +
      " · " +
      selected.ca +
      " · Người đề nghị: " +
      identity +
      (source.inspection_by ? " · Người kiểm: " + source.inspection_by : "") +
      (source.inspection_at ? " · Kiểm lúc: " + MesQcFields.display(source.inspection_at) : "");
    const target = el("warningEvidence");
    target.classList.add("warning-photos");
    target.replaceChildren();
    const urls = Array.isArray(source.inspection_evidence_urls) ? source.inspection_evidence_urls : [];
    for (const url of urls) {
      const safe = Qc02View.safeUrl(url, true);
      if (!safe) continue;
      const button = document.createElement("button");
      button.type = "button";
      button.className = "btn secondary";
      const img = document.createElement("img");
      img.src = safe;
      img.alt = "Ảnh lỗi từ lần kiểm IPQC";
      img.style.cssText = "width:90px;height:65px;object-fit:contain";
      button.append(img);
      button.onclick = () => Qc02View.photo(safe, urls);
      target.append(button);
    }
  }
  async function choose(id, requestedCheckpoint = "") {
    const request = ++turn;
    selected = null;
    checkpoint = null;
    token = crypto.randomUUID();
    el("checkpointId").value = "";
    el("jobInfo").textContent = "";
    el("warningEvidence").replaceChildren();
    const job = available.find((r) => r.id_dong === id);
    if (!job) return;
    const response = await sb
      .from("duc_ipqc_checkpoint")
      .select("*")
      .eq("id_dong", job.id_dong)
      .order("thoi_diem_tao", { ascending: false })
      .limit(200);
    if (response.error) throw new Error(response.error.message);
    if (request !== turn) return;
    const warnings = (response.data || []).filter((r) => ["NG", "CANH_BAO"].includes(r.ket_qua));
    el("warningCheckpoint").replaceChildren(new Option("Phiếu trực tiếp cho phiên đang chọn", ""));
    for (const row of warnings)
      el("warningCheckpoint").add(
        new Option(row.id_checkpoint + " · " + (MesQcFields.cleanText(row.ghi_chu) || row.ket_qua), row.id_checkpoint),
      );
    if (requestedCheckpoint) {
      checkpoint = warnings.find((r) => r.id_checkpoint === requestedCheckpoint);
      if (!checkpoint) throw new Error("Không tìm thấy cảnh báo của đúng phiên đang chạy.");
    } else if (warnings.length === 1) checkpoint = warnings[0];
    selected = job;
    el("warningCheckpoint").value = checkpoint?.id_checkpoint || "";
    el("warningCheckpoint").onchange = () => {
      checkpoint = warnings.find((r) => r.id_checkpoint === val("warningCheckpoint")) || null;
      token = crypto.randomUUID();
      if (checkpoint) el("warningContent").value = MesQcFields.cleanText(checkpoint.ghi_chu);
      preview();
    };
    if (checkpoint) el("warningContent").value = checkpoint.ghi_chu || "";
    el("producedCurrent").value = job.tt_ca ?? 0;
    preview();
  }
  async function send(event) {
    event.preventDefault();
    event.stopImmediatePropagation();
    if (busy) return;
    busy = true;
    el("createBtn").disabled = true;
    el("runningJob").disabled = true;
    el("warningCheckpoint").disabled = true;
    try {
      if (!MesIpqcFlow.canPropose(role)) throw new Error("Chỉ bộ phận Sản xuất được lập đề nghị chạy tiếp.");
      if (!selected) throw new Error("Chọn đúng công việc đang sản xuất.");
      if (proposalWarningId && checkpoint?.id_checkpoint !== proposalWarningId)
        throw new Error("Đề nghị không thuộc đúng cảnh báo đã mở.");
      if (!val("reasonDetail") || !val("proposalCountermeasure") || !val("proposalDepartment"))
        throw new Error("Nhập đối sách tạm thời và bộ phận đề nghị.");
      const dimension = !checkpoint && val("approvalDefectType") === "dimension",
        type = val("reasonType");
      if (proposalWarningId && type === "EARLY_WARNING")
        throw new Error("Chọn giới hạn thời gian hoặc số lượng chạy thêm cho đề nghị.");
      if (dimension && !val("actualValue")) throw new Error("Nhập giá trị thực tế của lỗi kích thước.");
      if (!val("warningContent") && !checkpoint) throw new Error("Nhập nội dung cảnh báo.");
      const qty = val("approvalDefectQty");
      if (qty && (!Number.isInteger(Number(qty)) || Number(qty) < 0)) throw new Error("Số lượng lỗi không hợp lệ.");
      const details = MesIpqcFlow.reason({
        client_request_id: token,
        warning_content: checkpoint ? checkpoint.ghi_chu || "" : val("warningContent"),
        warning_level: checkpoint ? (checkpoint.ket_qua === "NG" ? "NG" : "RISK") : val("warningLevel"),
        reason_type: type,
        reason_detail:
          val("reasonDetail") +
          "\nĐối sách tạm thời: " +
          val("proposalCountermeasure") +
          "\nBộ phận đề nghị: " +
          val("proposalDepartment") +
          (val("proposalNote") ? "\nGhi chú: " + val("proposalNote") : ""),
        requester_department: val("proposalDepartment"),
        temporary_countermeasure: val("proposalCountermeasure"),
        requester_note: val("proposalNote"),
        defect_type: checkpoint ? "inspection_checklist" : dimension ? "dimension" : "appearance",
        inspection_defect_items: checkpoint ? MesIpqcFlow.defects(checkpoint) : [],
        defect_qty: checkpoint ? null : qty ? Number(qty) : null,
        actual_value: dimension ? val("actualValue") : "",
        standard_min: dimension ? val("standardMin") : "",
        standard_max: dimension ? val("standardMax") : "",
        allowed_until: type === "TIME" && val("timeMode") === "until" ? iso("allowedUntil") : null,
        allowed_hours: type === "TIME" && val("timeMode") === "hours" ? val("allowedHours") : null,
        allowed_qty: ["PLAN_QTY", "DOWNSTREAM_REWORK"].includes(type) ? val("allowedQty") : null,
        produced_current: val("producedCurrent") || 0,
        repair_department: type === "DOWNSTREAM_REWORK" ? val("repairDepartment") : null,
        treatment_content: type === "DOWNSTREAM_REWORK" ? val("treatmentContent") : null,
        treatment_deadline: type === "DOWNSTREAM_REWORK" ? iso("treatmentDeadline") : null,
      });
      const result = await MesIpqcFlow.create(
        selected,
        checkpoint?.id_checkpoint || "",
        details,
        identity,
        !!checkpoint,
      );
      alert(
        (result.existing ? "Phiếu đã tồn tại." : "Đã gửi yêu cầu.") +
          " Chưa được phép tiếp tục sản xuất khi chưa có phê duyệt hợp lệ.",
      );
      resetForm();
      proposalWarningId = "";
      await Promise.all([loadRequests(), loadWarnings()]);
    } catch (error) {
      alert(error.message);
    } finally {
      busy = false;
      el("createBtn").disabled = false;
      el("runningJob").disabled = !!proposalWarningId;
      el("warningCheckpoint").disabled = !!proposalWarningId;
    }
  }
  async function init(session) {
    account = session;
    const user = await sb
      .from("user_roles")
      .select("role,bo_phan_phu_trach")
      .eq("user_id", session.user.id)
      .maybeSingle();
    role = user.error ? "" : user.data?.role || "";
    el("directProposal").hidden = !MesIpqcFlow.canPropose(role);
    el("proposalRequester").value = identity;
    if (typeof sb.channel === "function") {
      const update = () => {
        loadWarnings();
        loadRequests();
      };
      sb.channel("mes-ipqc-warning-inbox")
        .on("broadcast", { event: "changed" }, update)
        .on("postgres_changes", { event: "*", schema: "public", table: "duc_ipqc_checkpoint" }, update)
        .on("postgres_changes", { event: "*", schema: "public", table: "duc_ipqc_continue_request" }, update)
        .subscribe();
    }
    await loadWarnings();
    const previousRender = render,
      previousDecide = decide;
    render = function () {
      const all = rows;
      const visible = el("onlyMyRequests").checked ? all.filter((r) => r.requester_id === account.user.id) : all;
      rows = visible;
      previousRender();
      rows = all;
      [...el("requests").children].forEach((tr, index) => {
        const row = visible[index];
        if (!row) return;
        if (!MesIpqcFlow.canDecide(role, row.current_step))
          tr.querySelectorAll(".approve,.reject").forEach((button) => button.remove());
        if (!MesIpqcFlow.canDecide(role, row.current_step, true))
          tr.querySelectorAll(".override").forEach((button) => button.remove());
      });
      el("myRequestsCount").textContent =
        "Yêu cầu của tôi: " + all.filter((r) => r.requester_id === account.user.id).length;
    };
    decide = async function (id, decision) {
      const row = rows.find((r) => r.id === id);
      if (!row || !MesIpqcFlow.canDecide(role, row.current_step, decision === "Phê duyệt trực tiếp"))
        return alert("Tài khoản không có quyền duyệt bước này.");
      return previousDecide(id, decision);
    };
    try {
      await refresh();
    } catch (error) {
      el("jobInfo").textContent = "Không tải được danh sách công việc: " + friendly(error);
      return;
    }
    const q = new URLSearchParams(location.search);
    let jobId = q.get("jobId"),
      cp = q.get("checkpointId");
    if (cp && !jobId) {
      const r = await sb.from("duc_ipqc_checkpoint").select("id_dong").eq("id_checkpoint", cp).maybeSingle();
      if (r.error) throw new Error(r.error.message);
      jobId = r.data?.id_dong;
    }
    if (jobId && MesIpqcFlow.canPropose(role)) {
      el("runningJob").value = jobId;
      await choose(jobId, cp || "");
      el("proposalPanel").classList.remove("hidden");
      el("proposalRequester").value = identity;
      proposalWarningId = cp || "";
      el("runningJob").disabled = !!proposalWarningId;
      el("warningCheckpoint").disabled = !!proposalWarningId;
    }
  }
  el("requestForm").addEventListener("submit", send, true);
  el("runningSearch").oninput = options;
  el("runningJob").onchange = () => {
    if (busy) return;
    el("warningContent").value = "";
    choose(val("runningJob")).catch((error) => alert(error.message));
  };
  el("refreshRunning").onclick = () => refresh().catch((error) => alert(error.message));
  el("onlyMyRequests").onchange = () => render();
  el("requestForm").addEventListener("reset", () => {
    ++turn;
    selected = null;
    checkpoint = null;
    token = "";
    proposalWarningId = "";
    el("runningJob").disabled = false;
    el("warningCheckpoint").disabled = false;
    el("warningContent").readOnly = false;
    el("proposalWarningFaults").textContent = "";
    for (const id of [
      "approvalDefectType",
      "approvalDefectQty",
      "actualValue",
      "standardMin",
      "standardMax",
      "warningLevel",
    ])
      el(id).closest(".field").hidden = false;
    el("warningEvidence").replaceChildren();
    el("jobInfo").textContent = "";
    el("checkpointId").value = "";
    el("warningCheckpoint").replaceChildren(new Option("Chọn phiên sản xuất trước", ""));
  });
  /* ===== T140: lỗi dễ hiểu ===== */
  function errText(error) {
    if (!error) return "";
    if (typeof error === "string") return error;
    return [error.code, error.message, error.details, error.hint].filter(Boolean).join(" · ");
  }
  function errKind(error) {
    const t = errText(error).toLowerCase();
    if (/42501|permission denied|row-level security|not authorized|jwt|401|403/.test(t)) return "perm";
    if (/42p01|42883|pgrst202|pgrst205|does not exist|could not find the (function|table)|schema cache/.test(t))
      return "missing";
    if (/failed to fetch|networkerror|network request|load failed|timeout/.test(t)) return "net";
    return "";
  }
  const FRIENDLY = {
    perm: "Tài khoản chưa có quyền xem/duyệt mục này — liên hệ QC Manager.",
    missing: "Chức năng này chưa được cập nhật trên hệ thống — liên hệ quản trị (admin).",
    net: "Mất kết nối tới máy chủ — kiểm tra mạng rồi bấm Làm mới.",
  };
  /** Câu dễ hiểu; lỗi nghiệp vụ (RAISE từ RPC, tiếng Việt) giữ nguyên, lỗi kỹ thuật đổi thành câu chung. */
  function friendly(error) {
    const kind = errKind(error);
    if (kind) return FRIENDLY[kind];
    const msg = typeof error === "string" ? error : error?.message || "";
    return msg || "Có lỗi xảy ra — thử lại hoặc liên hệ quản trị.";
  }
  /** Hiện hộp lỗi: câu dễ hiểu + <details> "Chi tiết kỹ thuật". */
  function errorBox(target, title, error) {
    const box = document.createElement("div");
    box.className = "err-box";
    const kind = errKind(error);
    box.append((title ? title + " " : "") + (kind ? FRIENDLY[kind] : "Vui lòng thử lại sau."));
    const details = document.createElement("details"),
      summary = document.createElement("summary"),
      code = document.createElement("code");
    summary.textContent = "Chi tiết kỹ thuật";
    code.textContent = errText(error) || String(error);
    details.append(summary, code);
    box.append(details);
    target.replaceChildren(box);
  }

  /* ===== T140: hộp thư cảnh báo — lọc, chia trang, đóng cảnh báo cũ ===== */
  const PAGE_SIZE = 20,
    DAY_MS = 86400000;
  let closedMap = new Map(), // id_checkpoint -> {ly_do, nguoi_dong, dong_luc}
    closeSupport = null, // null = chưa biết, true/false sau lần đọc bảng duc_ipqc_canh_bao_dong
    page = 1,
    lastError = null;
  const picked = new Set();
  const canClose = () => ["admin", "qc_manager"].includes(role);
  const pad = (n) => String(n).padStart(2, "0");
  const dayKey = (d) => d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
  function whenOf(cp) {
    const t = cp.thoi_diem_kiem_thuc_te || cp.thoi_diem_tao;
    const d = t ? new Date(t) : null;
    return d && !isNaN(d) ? d : null;
  }
  function ageText(d) {
    if (!d) return "";
    const ms = Date.now() - d.getTime();
    if (ms < 3600000) return Math.max(1, Math.round(ms / 60000)) + " phút trước";
    if (ms < DAY_MS) return Math.round(ms / 3600000) + " giờ trước";
    return Math.floor(ms / DAY_MS) + " ngày trước";
  }
  function sourceOf(item) {
    const cp = item.checkpoint;
    return MesIpqcFlow.data(
      item.job || { id_dong: cp.id_dong, ma_may: cp.ma_may, ma_sp: cp.ma_sp, cong_doan: cp.cong_doan },
      cp,
    );
  }
  /** Tóm tắt lỗi 1 dòng: tên mục không đạt (bỏ phần mô tả sau " — ") + ghi chú; điều kiện máy chỉ khi NG. */
  function faultShort(cp) {
    const items = [];
    for (const it of Array.isArray(cp.checklist_json) ? cp.checklist_json : []) {
      if (it.dat !== false || it.code === "machine_condition") continue;
      const label = MesQcFields.cleanText(it.muc || it.label || "");
      if (!label) continue;
      const at = label.indexOf(" — ");
      items.push(at >= 0 ? label.slice(0, at) : label);
    }
    const parts = [];
    if (items.length) parts.push(items.join(", "));
    const note = MesQcFields.cleanText(cp.ghi_chu);
    if (note) parts.push(note);
    if (MesQcFields.machine(cp) === "NG") parts.push("Điều kiện máy NG");
    return parts.join(" · ") || "Không ghi chi tiết lỗi";
  }
  async function loadClosed() {
    if (closeSupport === false) return;
    const r = await sb
      .from("duc_ipqc_canh_bao_dong")
      .select("id_checkpoint,ly_do,nguoi_dong,dong_luc")
      .order("dong_luc", { ascending: false })
      .limit(5000);
    if (r.error) {
      // Bảng chưa có (chưa chạy migration T140) hoặc không có quyền đọc -> tắt chức năng đóng, trang vẫn chạy.
      closeSupport = false;
      closedMap = new Map();
      return;
    }
    closeSupport = true;
    closedMap = new Map((r.data || []).map((x) => [x.id_checkpoint, x]));
  }
  function rangeBounds() {
    const mode = val("wfRange");
    let from = null,
      to = null;
    if (mode === "7" || mode === "30") {
      const d = new Date();
      d.setHours(0, 0, 0, 0);
      d.setDate(d.getDate() - (Number(mode) - 1));
      from = dayKey(d);
    } else if (mode === "custom") {
      from = val("wfFrom") || null;
      to = val("wfTo") || null;
    }
    return { from, to };
  }
  function syncRangeInputs() {
    const custom = val("wfRange") === "custom";
    el("wfFrom").hidden = el("wfTo").hidden = !custom;
    const sep = el("warnFilters").querySelector(".sep");
    if (sep) sep.hidden = !custom;
  }
  function statusList() {
    const closedView = val("wfStatus") === "closed";
    return inbox.filter((item) => closedMap.has(item.checkpoint.id_checkpoint) === closedView);
  }
  function filtered() {
    const { from, to } = rangeBounds(),
      machine = val("wfMachine"),
      product = val("wfProduct"),
      text = val("wfSearch").toLocaleLowerCase();
    return statusList().filter((item) => {
      const cp = item.checkpoint,
        d = whenOf(cp),
        k = d ? dayKey(d) : "";
      if (from && (!k || k < from)) return false;
      if (to && (!k || k > to)) return false;
      if (machine && cp.ma_may !== machine) return false;
      if (product && cp.ma_sp !== product) return false;
      if (text) {
        const hay = [cp.ma_may, cp.ma_sp, cp.cong_doan, cp.nguoi_kiem, cp.id_checkpoint, faultShort(cp)]
          .join(" ")
          .toLocaleLowerCase();
        if (!hay.includes(text)) return false;
      }
      return true;
    });
  }
  function fillSelect(id, values, allLabel) {
    const s = el(id),
      cur = s.value;
    s.replaceChildren(new Option(allLabel, ""));
    for (const [v, n] of values) s.add(new Option(v + " (" + n + ")", v));
    s.value = values.some(([v]) => v === cur) ? cur : "";
  }
  function counts(list, key) {
    const m = new Map();
    for (const it of list) {
      const v = it.checkpoint[key];
      if (v) m.set(v, (m.get(v) || 0) + 1);
    }
    return [...m.entries()].sort((a, b) => String(a[0]).localeCompare(String(b[0]), "vi", { numeric: true }));
  }
  function thumb(cp) {
    const urls = (Array.isArray(cp.anh_bang_chung_url) ? cp.anh_bang_chung_url : [])
      .map((u) => Qc02View.safeUrl(u, true))
      .filter(Boolean);
    if (!urls.length) {
      const s = document.createElement("span");
      s.className = "no-img";
      s.textContent = "Chưa có ảnh";
      return s;
    }
    const b = document.createElement("button");
    b.type = "button";
    b.className = "thumb";
    b.title = urls.length > 1 ? "Xem " + urls.length + " ảnh" : "Xem ảnh";
    const img = document.createElement("img");
    img.src = urls[0];
    img.alt = "Ảnh cảnh báo IPQC";
    img.loading = "lazy";
    b.append(img);
    if (urls.length > 1) {
      const more = document.createElement("span");
      more.className = "more";
      more.textContent = "+" + (urls.length - 1);
      b.append(more);
    }
    b.onclick = () => Qc02View.photo(urls[0], urls);
    return b;
  }
  function statusChip(cp, d) {
    const s = document.createElement("span");
    const closed = closedMap.get(cp.id_checkpoint);
    if (closed) {
      s.className = "st st-closed";
      s.textContent = "Đã đóng";
      s.title =
        "Đóng bởi " +
        (closed.nguoi_dong || "—") +
        " lúc " +
        MesQcFields.display(closed.dong_luc) +
        "\nLý do: " +
        (closed.ly_do || "—");
    } else if (d && Date.now() - d.getTime() > 3 * DAY_MS) {
      s.className = "st st-old";
      s.textContent = "Chưa đề nghị · tồn lâu";
      s.title = "Cảnh báo quá 3 ngày chưa có đề nghị tiếp tục SX";
    } else {
      s.className = "st st-open";
      s.textContent = "Chưa đề nghị";
      s.title = "Có cảnh báo — chưa có đề nghị tiếp tục SX";
    }
    return s;
  }
  function renderBulk(list) {
    const show = canClose() && val("wfStatus") !== "closed";
    el("warnBulk").classList.toggle("hidden", !show);
    el("wfSelHead").textContent = "";
    // bỏ chọn những id không còn trong danh sách (đã có đề nghị / đã đóng)
    const alive = new Set(statusList().map((it) => it.checkpoint.id_checkpoint));
    for (const id of [...picked]) if (!alive.has(id)) picked.delete(id);
    el("wfSelCount").textContent = picked.size;
    const off = closeSupport === false;
    el("wfCloseBtn").disabled = off || !picked.size;
    el("wfCloseNote").textContent = off
      ? "Chức năng đóng cảnh báo chưa được cập nhật trên hệ thống (cần migration T140) — liên hệ admin."
      : "";
    for (const id of ["wfAll", "wfSelectOld", "wfOldDays", "wfClearSel"]) el(id).disabled = off;
    return show && !off;
  }
  function renderInbox() {
    const tbody = el("warningInbox");
    const list = filtered(),
      pages = Math.max(1, Math.ceil(list.length / PAGE_SIZE));
    if (page > pages) page = pages;
    const slice = list.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
    const openCount = inbox.filter((it) => !closedMap.has(it.checkpoint.id_checkpoint)).length;
    el("warnCount").textContent = openCount;
    el("warnCount").title = openCount + " cảnh báo chưa có đề nghị (mọi thời gian)";
    fillSelect("wfMachine", counts(statusList(), "ma_may"), "Tất cả máy");
    fillSelect("wfProduct", counts(statusList(), "ma_sp"), "Tất cả model");
    const selectable = renderBulk(list);
    if (lastError) errorBox(el("warningInboxStatus"), "Không tải được cảnh báo.", lastError);
    else
      el("warningInboxStatus").textContent =
        "Hiện " +
        list.length +
        " / " +
        statusList().length +
        (val("wfStatus") === "closed" ? " cảnh báo đã đóng" : " cảnh báo chưa có đề nghị") +
        " theo bộ lọc. Tự cập nhật mỗi 15 giây.";
    tbody.replaceChildren();
    for (const item of slice) {
      const cp = item.checkpoint,
        source = sourceOf(item),
        d = whenOf(cp),
        tr = document.createElement("tr");
      tr.title = "Mã điểm kiểm: " + cp.id_checkpoint;
      tr.dataset.checkpoint = cp.id_checkpoint;
      if (closedMap.has(cp.id_checkpoint)) tr.classList.add("is-closed");
      const td = (cls) => {
        const c = document.createElement("td");
        c.className = cls;
        tr.append(c);
        return c;
      };
      const sel = td("w-sel");
      if (selectable) {
        const cb = document.createElement("input");
        cb.type = "checkbox";
        cb.checked = picked.has(cp.id_checkpoint);
        cb.title = "Chọn để đóng";
        cb.setAttribute("aria-label", "Chọn cảnh báo " + cp.ma_may + " " + cp.ma_sp);
        cb.onchange = () => {
          if (cb.checked) picked.add(cp.id_checkpoint);
          else picked.delete(cp.id_checkpoint);
          renderBulk(list);
        };
        sel.append(cb);
      }
      const time = td("w-time");
      const t = document.createElement("div");
      t.className = "t";
      t.textContent = d
        ? pad(d.getDate()) + "/" + pad(d.getMonth() + 1) + " " + pad(d.getHours()) + ":" + pad(d.getMinutes())
        : "—";
      t.title = d ? MesQcFields.display(cp.thoi_diem_kiem_thuc_te || cp.thoi_diem_tao) : "Chưa có thời gian cảnh báo";
      const age = document.createElement("div");
      age.className = "age";
      age.textContent = ageText(d);
      time.append(t, age, statusChip(cp, d));
      const mc = td("w-mc");
      const m = document.createElement("div");
      m.className = "m";
      m.textContent = (source.machine || cp.ma_may || "—") + " · " + (source.product_code || cp.ma_sp || "—");
      const sub = document.createElement("div");
      sub.className = "sub";
      sub.textContent = source.process || cp.cong_doan || "";
      mc.append(m, sub);
      const fault = td("w-fault");
      const ft = document.createElement("div");
      ft.className = "txt";
      ft.textContent = faultShort(cp);
      ft.title = faultText(cp);
      fault.append(ft);
      td("w-img").append(thumb(cp));
      td("w-who").textContent = cp.nguoi_kiem || "—";
      const actions = td("w-act"),
        buttons = document.createElement("div");
      buttons.className = "warning-actions";
      actions.append(buttons);
      const open = document.createElement("button");
      open.type = "button";
      open.className = "btn secondary";
      open.textContent = "Xem";
      open.title = "Xem chi tiết cảnh báo";
      open.onclick = () => detail(item);
      buttons.append(open);
      if (MesIpqcFlow.canPropose(role) && !closedMap.has(cp.id_checkpoint)) {
        const propose = document.createElement("button");
        propose.type = "button";
        propose.className = "btn primary";
        propose.textContent = "Đề nghị tiếp tục SX";
        propose.onclick = () => startProposal(item).catch((error) => alert(friendly(error)));
        buttons.append(propose);
      }
      if (canClose() && closeSupport && closedMap.has(cp.id_checkpoint)) {
        const reopen = document.createElement("button");
        reopen.type = "button";
        reopen.className = "btn secondary";
        reopen.textContent = "Mở lại";
        reopen.onclick = () => reopenWarning(cp.id_checkpoint);
        buttons.append(reopen);
      }
      tbody.append(tr);
    }
    if (!slice.length && !lastError) {
      const tr = document.createElement("tr"),
        c = document.createElement("td");
      c.colSpan = 7;
      c.className = "empty help";
      c.textContent = statusList().length
        ? "Không có cảnh báo khớp bộ lọc. Thử chọn “Tất cả” ở khoảng thời gian."
        : val("wfStatus") === "closed"
          ? "Chưa có cảnh báo nào bị đóng."
          : "Không có cảnh báo chưa xử lý.";
      if (statusList().length && val("wfRange") !== "all") {
        const all = document.createElement("button");
        all.type = "button";
        all.className = "btn secondary";
        all.style.marginLeft = "8px";
        all.textContent = "Xem tất cả (" + statusList().length + ")";
        all.onclick = () => {
          el("wfRange").value = "all";
          syncRangeInputs();
          page = 1;
          renderInbox();
        };
        c.append(all);
      }
      tr.append(c);
      tbody.append(tr);
    }
    el("wfAll").checked = !!slice.length && slice.every((it) => picked.has(it.checkpoint.id_checkpoint));
    renderPager(list.length, pages);
  }
  function renderPager(total, pages) {
    const box = el("warnPager");
    box.replaceChildren();
    if (total <= PAGE_SIZE) return;
    const info = document.createElement("span");
    const a = (page - 1) * PAGE_SIZE + 1,
      b = Math.min(total, page * PAGE_SIZE);
    info.textContent = a + "–" + b + " / " + total;
    const pg = document.createElement("div");
    pg.className = "pg";
    const btn = (label, target, cur) => {
      const x = document.createElement("button");
      x.type = "button";
      x.className = "btn secondary" + (cur ? " cur" : "");
      x.textContent = label;
      x.disabled = target < 1 || target > pages;
      x.onclick = () => {
        page = target;
        renderInbox();
        el("warningPanel").scrollIntoView({ block: "start" });
      };
      pg.append(x);
    };
    btn("‹", page - 1);
    const set = new Set([1, pages, page - 1, page, page + 1].filter((n) => n >= 1 && n <= pages));
    let prev = 0;
    for (const n of [...set].sort((x, y) => x - y)) {
      if (n - prev > 1) {
        const dots = document.createElement("span");
        dots.textContent = "…";
        pg.append(dots);
      }
      btn(String(n), n, n === page);
      prev = n;
    }
    btn("›", page + 1);
    box.append(info, pg);
  }
  async function loadWarnings() {
    if (loadingWarnings) {
      queuedWarnings = true;
      return;
    }
    loadingWarnings = true;
    try {
      const [list] = await Promise.all([MesIpqcFlow.warnings(), loadClosed()]);
      inbox = list;
      lastError = null;
    } catch (error) {
      inbox = [];
      lastError = error;
    } finally {
      loadingWarnings = false;
    }
    renderInbox();
    if (queuedWarnings) {
      queuedWarnings = false;
      loadWarnings();
    }
  }
  function openCloseDialog() {
    if (!canClose() || !picked.size) return;
    const dialog = el("closeWarnDialog");
    el("closeWarnInfo").textContent =
      "Sẽ đóng " + picked.size + " cảnh báo chưa có đề nghị tiếp tục SX. Cảnh báo đã có đề nghị sẽ được bỏ qua.";
    el("closeWarnReason").value = "";
    el("closeWarnMsg").replaceChildren();
    el("closeWarnConfirm").disabled = false;
    if (typeof dialog.showModal === "function") dialog.showModal();
    else dialog.setAttribute("open", "");
    el("closeWarnReason").focus();
  }
  function closeDialog(id) {
    const dialog = el(id);
    if (typeof dialog.close === "function") dialog.close();
    else dialog.removeAttribute("open");
  }
  async function confirmClose(event) {
    event.preventDefault();
    const reason = el("closeWarnReason").value.trim();
    if (reason.length < 3) {
      el("closeWarnMsg").replaceChildren();
      const p = document.createElement("div");
      p.className = "err-box";
      p.textContent = "Nhập lý do đóng (tối thiểu 3 ký tự).";
      el("closeWarnMsg").append(p);
      return;
    }
    el("closeWarnConfirm").disabled = true;
    const ids = [...picked];
    const { data, error } = await sb.rpc("duc_ipqc_dong_canh_bao_cu", { p_ids: ids, p_ly_do: reason });
    el("closeWarnConfirm").disabled = false;
    if (error || data?.ok === false) {
      if (error && errKind(error) === "missing") {
        closeSupport = false;
        renderInbox();
      }
      if (error) errorBox(el("closeWarnMsg"), "Không đóng được cảnh báo.", error);
      else {
        const p = document.createElement("div");
        p.className = "err-box";
        p.textContent = data.error || "Không đóng được cảnh báo.";
        el("closeWarnMsg").replaceChildren(p);
      }
      return;
    }
    const skipped = Array.isArray(data?.bo_qua) ? data.bo_qua : [];
    picked.clear();
    closeDialog("closeWarnDialog");
    alert(
      "Đã đóng " +
        (data?.so_dong ?? ids.length) +
        " cảnh báo." +
        (skipped.length ? "\nBỏ qua " + skipped.length + " cảnh báo (đã có đề nghị / đã đóng / không hợp lệ)." : ""),
    );
    await loadWarnings();
  }
  async function reopenWarning(id) {
    const reason = prompt("Lý do mở lại cảnh báo (tối thiểu 3 ký tự):");
    if (reason === null) return;
    if (reason.trim().length < 3) return alert("Lý do tối thiểu 3 ký tự.");
    const { data, error } = await sb.rpc("duc_ipqc_mo_lai_canh_bao", { p_id: id, p_ly_do: reason.trim() });
    if (error) return alert(friendly(error));
    if (data?.ok === false) return alert(data.error || "Không mở lại được.");
    await loadWarnings();
  }
  (function bindInboxControls() {
    const today = dayKey(new Date());
    el("wfTo").value = today;
    const d = new Date();
    d.setDate(d.getDate() - 6);
    el("wfFrom").value = dayKey(d);
    syncRangeInputs();
    const again = () => {
      page = 1;
      renderInbox();
    };
    el("wfRange").onchange = () => {
      syncRangeInputs();
      again();
    };
    for (const id of ["wfFrom", "wfTo", "wfMachine", "wfProduct", "wfStatus"]) el(id).onchange = again;
    let timer = 0;
    el("wfSearch").oninput = () => {
      clearTimeout(timer);
      timer = setTimeout(again, 200);
    };
    el("wfAll").onchange = () => {
      const list = filtered().slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
      for (const it of list) {
        if (el("wfAll").checked) picked.add(it.checkpoint.id_checkpoint);
        else picked.delete(it.checkpoint.id_checkpoint);
      }
      renderInbox();
    };
    el("wfSelectOld").onclick = () => {
      const n = Number(el("wfOldDays").value);
      if (!Number.isFinite(n) || n < 1) return alert("Nhập số ngày ≥ 1.");
      const limit = Date.now() - n * DAY_MS;
      let added = 0;
      for (const it of statusList()) {
        const dd = whenOf(it.checkpoint);
        if (dd && dd.getTime() < limit && !picked.has(it.checkpoint.id_checkpoint)) {
          picked.add(it.checkpoint.id_checkpoint);
          added++;
        }
      }
      // Hiện cả cảnh báo cũ (có thể nằm ngoài khoảng 7 ngày đang lọc)
      if (added && val("wfRange") !== "all") el("wfRange").value = "all";
      syncRangeInputs();
      page = 1;
      renderInbox();
      if (!added) alert("Không có cảnh báo nào quá " + n + " ngày (chưa được chọn).");
    };
    el("wfClearSel").onclick = () => {
      picked.clear();
      el("wfAll").checked = false;
      renderInbox();
    };
    el("wfCloseBtn").onclick = openCloseDialog;
    el("closeWarnForm").addEventListener("submit", confirmClose);
    el("closeWarnCancel").onclick = () => closeDialog("closeWarnDialog");
  })();
  function faultText(cp) {
    const lines = [];
    for (const item of Array.isArray(cp.checklist_json) ? cp.checklist_json : []) {
      if (item.dat !== false || item.code === "machine_condition") continue;
      const label = MesQcFields.cleanText(item.muc || item.label || "");
      if (!label) continue;
      const at = label.indexOf(" — ");
      lines.push(at >= 0 ? label.slice(0, at) + "\n" + label.slice(at + 3) : label);
    }
    const note = MesQcFields.cleanText(cp.ghi_chu);
    if (note) lines.push("Nội dung cảnh báo: " + note);
    const machine = MesQcFields.machine(cp);
    lines.push("Điều kiện máy: " + (machine === "PASS" ? "ĐẠT" : machine === "NG" ? "NG" : "Chưa ghi nhận kết quả"));
    return lines.join("\n\n");
  }
  function photos(target, cp) {
    const gallery = document.createElement("div");
    gallery.className = "warning-photos";
    target.append(gallery);
    const urls = Array.isArray(cp.anh_bang_chung_url) ? cp.anh_bang_chung_url : [];
    for (const url of urls) {
      const safe = Qc02View.safeUrl(url, true);
      if (!safe) continue;
      const button = document.createElement("button");
      button.type = "button";
      button.className = "btn secondary";
      const image = document.createElement("img");
      image.src = safe;
      image.alt = "Ảnh cảnh báo IPQC";
      button.append(image);
      button.onclick = () => Qc02View.photo(safe, urls);
      gallery.append(button);
    }
    if (!gallery.children.length) gallery.textContent = "Chưa có ảnh";
  }
  function detail(item) {
    const target = el("warningDetailBody");
    target.replaceChildren();
    const cp = item.checkpoint,
      source = MesIpqcFlow.data(
        item.job || { id_dong: cp.id_dong, ma_may: cp.ma_may, ma_sp: cp.ma_sp, cong_doan: cp.cong_doan },
        cp,
      );
    function block(title, body) {
      const section = document.createElement("section");
      section.className = "warning-block";
      const h = document.createElement("h3");
      h.textContent = title;
      section.append(h);
      if (body) {
        const p = document.createElement("p");
        p.style.whiteSpace = "pre-wrap";
        p.textContent = body;
        section.append(p);
      }
      target.append(section);
      return section;
    }
    block(
      "Thông tin máy",
      "Máy: " +
        source.machine +
        "\nModel: " +
        source.product_code +
        "\nCông đoạn: " +
        source.process +
        "\nTask/tem: " +
        (source.task_no || "Chưa có liên kết xác minh") +
        "\nLOT: " +
        (source.lot_no || "Chưa có liên kết xác minh"),
    );
    block("Thông tin lỗi", faultText(cp));
    const closed = closedMap.get(cp.id_checkpoint);
    if (closed)
      block(
        "Đã đóng cảnh báo",
        "Người đóng: " +
          (closed.nguoi_dong || "—") +
          "\nThời gian: " +
          MesQcFields.display(closed.dong_luc) +
          "\nLý do: " +
          (closed.ly_do || "—"),
      );
    photos(block("Ảnh"), cp);
    block(
      "Người IPQC / thời gian",
      (cp.nguoi_kiem || "Chưa ghi nhận") + "\n" + MesQcFields.display(cp.thoi_diem_kiem_thuc_te),
    );
    const raw = document.createElement("p");
    raw.className = "raw-code";
    raw.textContent = "Mã điểm kiểm: " + cp.id_checkpoint + (cp.id_dong ? " · Phiên: " + cp.id_dong : "");
    target.append(raw);
    const dialog = el("warningDetailDialog");
    if (typeof dialog.showModal === "function") dialog.showModal();
    else dialog.setAttribute("open", "");
  }
  function auditText(detail) {
    const labels = {
      warning_content: "Nội dung cảnh báo",
      reason_detail: "Lý do",
      temporary_countermeasure: "Đối sách tạm thời",
      requester_department: "Bộ phận đề nghị",
      requester_note: "Ghi chú",
      inspection_by: "Người IPQC",
      inspection_at: "Thời gian kiểm",
      machine: "Máy",
      product_code: "Model",
      process: "Công đoạn",
      lot_no: "LOT",
      task_no: "Task/tem",
      allowed_hours: "Số giờ",
      allowed_qty: "Số lượng",
      allowed_until: "Đến thời gian",
      decision: "Quyết định",
      note: "Ghi chú",
      step_no: "Bước duyệt",
      status: "Trạng thái",
      reason_type: "Loại đề nghị",
      warning_level: "Mức cảnh báo",
      defect_type: "Loại lỗi",
      defect_qty: "Số lỗi",
      actual_value: "Giá trị thực tế",
      standard_min: "Giới hạn dưới",
      standard_max: "Giới hạn trên",
      produced_current: "Sản lượng",
      inspection_checklist: "Kết quả kiểm",
      inspection_evidence_urls: "Ảnh bằng chứng",
      inspection_defect_items: "Các mục không đạt",
      repair_department: "Bộ phận sửa",
      treatment_content: "Nội dung xử lý",
      treatment_deadline: "Thời hạn xử lý",
      requester_name: "Người đề nghị",
      production_day: "Ngày sản xuất",
      production_shift: "Ca",
      production_started_at: "Bắt đầu sản xuất",
      checkpoint_id: "Điểm kiểm",
      id_dong: "Phiên sản xuất",
      muc: "Mục kiểm",
      dat: "Kết quả",
    };
    const hidden = (key) => /^QC02_/i.test(key) || ["client_request_id", "code", "group"].includes(key);
    function value(input) {
      if (Array.isArray(input)) return input.map(value).join(" / ");
      if (input && typeof input === "object")
        return Object.entries(input)
          .filter(([key]) => !hidden(key))
          .map(([key, item]) => (labels[key] || key.replace(/_/g, " ")) + ": " + value(item))
          .join("; ");
      if (typeof input === "boolean") return input ? "Đạt" : "Không đạt";
      return MesQcFields.cleanText(input);
    }
    const rows =
      detail && typeof detail === "object"
        ? Object.entries(detail)
            .filter(([key]) => !hidden(key))
            .map(([key, item]) => (labels[key] || key.replace(/_/g, " ")) + ": " + value(item))
        : [];
    return rows.join("\n") || "Đã ghi nhận thao tác.";
  }
  async function startProposal(item) {
    if (busy) return;
    if (!MesIpqcFlow.canPropose(role)) throw new Error("Chỉ bộ phận Sản xuất được lập đề nghị.");
    await refresh();
    const job = available.find(
      (r) =>
        r.id_dong === item.checkpoint.id_dong &&
        r.ma_may === item.checkpoint.ma_may &&
        r.ma_sp === item.checkpoint.ma_sp,
    );
    if (!job) throw new Error("Phiên của cảnh báo không còn chạy; không chuyển cảnh báo sang máy/model khác.");
    resetForm();
    await choose(job.id_dong, item.checkpoint.id_checkpoint);
    proposalWarningId = item.checkpoint.id_checkpoint;
    el("runningJob").value = job.id_dong;
    el("runningJob").disabled = true;
    el("warningCheckpoint").disabled = true;
    el("proposalRequester").value = identity;
    el("warningContent").readOnly = true;
    el("reasonType").value = "TIME";
    reasonChanged();
    el("proposalPanel").classList.remove("hidden");
    el("proposalPanel").scrollIntoView({ behavior: "smooth" });
    const dialog = el("warningDetailDialog");
    if (dialog.open) {
      if (typeof dialog.close === "function") dialog.close();
      else dialog.removeAttribute("open");
    }
  }
  el("refreshWarnings").onclick = () => loadWarnings();
  el("warningDetailClose").onclick = () => {
    const dialog = el("warningDetailDialog");
    if (typeof dialog.close === "function") dialog.close();
    else dialog.removeAttribute("open");
  };
  el("directProposal").onclick = () => {
    if (!MesIpqcFlow.canPropose(role)) return;
    resetForm();
    proposalWarningId = "";
    el("runningJob").disabled = false;
    el("warningCheckpoint").disabled = false;
    el("warningContent").readOnly = false;
    el("proposalRequester").value = identity;
    el("proposalPanel").classList.remove("hidden");
  };
  return { init, refresh, loadWarnings, auditText, friendly, errorBox };
})();
