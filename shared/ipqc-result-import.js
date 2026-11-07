/* Review/import controller. Sync changes the unsaved matrix; only Save uploads/persists. */
const IpqcResultImport = (() => {
  function mount({ entry, standard, features, fail, onSync = () => {} }) {
    const $ = (id) => document.getElementById(id),
      P = IpqcResultParser,
      E = IpqcSpc.esc;
    let file = null,
      documentData = null,
      candidates = [],
      serial = 0,
      abort = null,
      url = null,
      limit = 100;
    let applied = false,
      appliedRows = [],
      uploaded = null,
      syncing = false;
    const presetsKey = "mes_ipqc_result_profiles_v1";
    function message(text) {
      $("gcImportStatus").textContent = text;
    }
    function profiles() {
      try {
        return JSON.parse(localStorage.getItem(presetsKey) || "{}");
      } catch {
        return {};
      }
    }
    function profile() {
      return Object.fromEntries(
        ["layout", "headerRow", "idColumn", "nameColumn", "nominalColumn", "unitColumn", "sampleColumns"].map(
          (key) => [key, $("gcImport_" + key).value.trim()],
        ),
      );
    }
    function loadProfiles() {
      const data = profiles();
      $("gcImportPreset").innerHTML =
        '<option value="">Tự động / cấu hình mới</option>' +
        Object.keys(data)
          .map((name) => "<option>" + E(name) + "</option>")
          .join("");
    }
    function valid(candidate) {
      const m = features().find((m) => String(m.muc_no) === String(candidate.muc_no));
      if (!m || !candidate.samples.length) return false;
      return candidate.samples.every(
        (s) =>
          s.sample >= 1 &&
          s.sample <= 100 &&
          s.value !== null &&
          (m.kieu === "so"
            ? typeof s.value === "number" && !P.convert(s.value, s.unit || candidate.unit, m.don_vi).error
            : typeof s.value === "boolean"),
      );
    }
    function visible() {
      const filter = $("gcImportFilter").value;
      return candidates
        .map((c, i) => ({ ...c, index: i }))
        .filter(
          (c) =>
            !filter ||
            (filter === "matched" ? c.status === "matched" : filter === "unmatched" ? !c.muc_no : !valid(c)),
        );
    }
    function render() {
      for (const c of candidates) {
        const m = features().find((m) => String(m.muc_no) === String(c.muc_no));
        c.warnings = m ? P.specWarnings(c, m) : [];
      }
      const data = visible();
      $("gcImportCandidates").innerHTML =
        "<table><thead><tr>" +
        [
          "Nguồn / mã",
          "Tên trong file",
          "Giá trị thực tế (có thể sửa)",
          "Đặc tính tiêu chuẩn",
          "Đơn vị nguồn",
          "Đối chiếu",
          "Xác nhận",
        ]
          .map((s) => "<th>" + E(s) + "</th>")
          .join("") +
        "</tr></thead><tbody>" +
        data
          .slice(0, limit)
          .map(
            (c) =>
              '<tr data-candidate="' +
              c.index +
              '"><td>' +
              E(c.source.sheet) +
              " · " +
              E(c.source.row ? "dòng " + c.source.row : "cột " + c.source.column) +
              "<br>" +
              E(c.id) +
              "</td><td>" +
              E(c.name) +
              (c.template
                ? "<br>Nominal: " +
                  E(c.nominal ?? "?") +
                  "<br>Upper / Lower Tol.: " +
                  E(c.upper ?? "?") +
                  " / " +
                  E(c.lower ?? "?")
                : "") +
              "</td><td>" +
              c.samples
                .map(
                  (s) =>
                    "<label>Mẫu " +
                    s.sample +
                    ' <input data-import-value="' +
                    s.sample +
                    '" value="' +
                    E(s.raw) +
                    '"></label>' +
                    (s.warning ? "<br>" + E(s.warning) : ""),
                )
                .join("") +
              '</td><td><select data-match><option value="">Chưa khớp — chọn đặc tính</option>' +
              features()
                .map(
                  (m) =>
                    '<option value="' +
                    m.muc_no +
                    '"' +
                    (String(m.muc_no) === String(c.muc_no) ? " selected" : "") +
                    ">" +
                    E(
                      (m.ma_dac_tinh || m.muc_no) +
                        " · " +
                        m.hang_muc +
                        " · " +
                        (m.danh_nghia ?? "") +
                        " " +
                        (m.don_vi || ""),
                    ) +
                    "</option>",
                )
                .join("") +
              '</select></td><td><select data-unit><option value="">Chưa rõ — cần xác minh</option>' +
              ["mm", "cm", "um", "in", "deg", "rad", "standard"]
                .map(
                  (u) =>
                    '<option value="' +
                    u +
                    '"' +
                    (c.unit === u ? " selected" : "") +
                    ">" +
                    E(u === "standard" ? "Đã đối chiếu: cùng đơn vị tiêu chuẩn" : u) +
                    "</option>",
                )
                .join("") +
              "</select></td><td>" +
              E(c.reason) +
              (c.warnings.length
                ? "<br><strong>" +
                  E(c.warnings.join("; ")) +
                  ". Đánh giá theo MES; không sửa tiêu chuẩn.</strong>"
                : "") +
              (c.source.method === "ocr" ? "<br>OCR: cần đối chiếu bản gốc" : "") +
              (!valid(c) ? "<br>Chọn đặc tính/đơn vị và sửa giá trị chưa rõ" : "") +
              '</td><td><input type="checkbox" data-accept ' +
              (c.accepted ? "checked " : "") +
              (!valid(c) ? "disabled" : "") +
              ' aria-label="Xác nhận dòng ' +
              (c.index + 1) +
              '"></td></tr>',
          )
          .join("") +
        "</tbody></table>";
      $("gcImportMore").hidden = data.length <= limit;
      $("gcImportSync").disabled = !candidates.some((c) => c.accepted && valid(c));
      if (!candidates.length)
        $("gcImportCandidates").textContent =
          "Chưa nhận diện được giá trị đo theo cấu trúc đã chọn. Cấu hình cột/mẫu đọc hoặc nhập tay.";
      if (documentData && candidates.length && !applied) summary();
    }
    function parse() {
      if (!documentData) return;
      const selected = $("gcResultSheet").value;
      const sheets = documentData.sheets.filter((s) => selected === "*" || s.name === selected);
      candidates = P.parse(sheets, profile()).map((c) => ({
        ...c,
        ...P.match(c, features()),
        unit: c.unit || c.samples.find((s) => s.unit)?.unit || "",
        accepted: false,
      }));
      limit = 100;
      $("gcImportRaw").textContent = sheets
        .map(
          (s) =>
            s.name +
            "\n" +
            s.rows
              .slice(0, 25)
              .map((row) => row.map((v) => v ?? "").join(" | "))
              .join("\n"),
        )
        .join("\n\n");
      render();
      if (!candidates.length) {
        message(
          "Chưa nhận diện được giá trị đo hợp lệ theo mẫu này. Chọn trang/sheet, cấu hình cột hoặc nhập tay; chưa đồng bộ/lưu.",
        );
        return;
      }
    }
    function summary() {
      const extracted = candidates.filter((c) => c.samples.some((s) => s.value !== null));
      const matched = extracted.filter((c) => c.status === "matched").length;
      message(
        (candidates.some((c) => c.template === "zeiss-calypso") ? "Tự nhận diện ZEISS Calypso · " : "") +
          "Đọc được " +
          extracted.length +
          " / " +
          candidates.length +
          " đặc tính; " +
          matched +
          " khớp; " +
          (extracted.length - matched) +
          " đọc được nhưng chưa khớp; " +
          (candidates.length - extracted.length) +
          " lỗi trích xuất (xem lý do từng dòng). " +
          "Chưa đồng bộ/lưu. Đối chiếu đơn vị, xác nhận rồi đồng bộ vào bảng. " +
          documentData.warnings.join(" "),
      );
    }
    $("gcResultMode").onchange = () => {
      $("gcResultImportPanel").hidden = $("gcResultMode").value !== "file";
    };
    $("gcResultFile").onchange = async () => {
      const chosen = $("gcResultFile").files[0];
      if (!chosen) return;
      if (!entry()) {
        message("Chọn Model và Revision phát hành trước khi đọc file.");
        return;
      }
      if (applied) {
        message("Đã đồng bộ file của lần kiểm này. Lưu hoặc làm mới lần kiểm trước khi chọn file khác.");
        return;
      }
      abort?.abort();
      abort = new AbortController();
      const token = ++serial,
        b = standard();
      try {
        file = chosen;
        uploaded = null;
        documentData = null;
        candidates = [];
        $("gcImportSameUnit").checked = false;
        render();
        message("Đang đọc file kết quả đo…");
        if (url) URL.revokeObjectURL(url);
        url = URL.createObjectURL(file);
        const ext = file.name.split(".").at(-1).toLowerCase(),
          preview = $("gcResultOriginal");
        preview.replaceChildren();
        if (["pdf", "png", "jpg", "jpeg"].includes(ext)) {
          const el = document.createElement(ext === "pdf" ? "iframe" : "img");
          el.src = url;
          el.title = "File kết quả đo gốc";
          el.className = "drawing";
          if (ext !== "pdf") el.alt = file.name;
          preview.append(el);
        } else preview.textContent = file.name + " — xem nội dung sheet bên dưới.";
        const result = await IpqcResultReader.read(file, {
          features: features(),
          signal: abort.signal,
          progress: (text) => {
            if (token === serial) message(text);
          },
        });
        if (token !== serial || standard()?.id !== b.id) return;
        documentData = result;
        $("gcResultSheet").innerHTML =
          '<option value="*">Tất cả trang / sheet (kiểm tra dòng trùng)</option>' +
          result.sheets.map((s) => "<option>" + E(s.name) + "</option>").join("");
        const score = (s) =>
          P.parse([s]).reduce(
            (n, c) =>
              n +
              c.samples.filter((v) => v.value !== null).length +
              (P.match(c, features()).status === "matched" ? 10000 : 0),
            0,
          );
        const best = [...result.sheets].sort((a, b) => score(b) - score(a))[0];
        const zeiss = P.parse(result.sheets).some((c) => c.template === "zeiss-calypso");
        if (zeiss) {
          $("gcImportPreset").value = "";
          for (const [key] of Object.entries(profile()))
            $("gcImport_" + key).value = key === "layout" ? "auto" : "";
        }
        $("gcResultSheet").value = zeiss ? "*" : best?.name || result.sheets[0]?.name || "*";
        parse();
      } catch (error) {
        if (error.name !== "AbortError") {
          message("Chưa đọc được định dạng này; chưa đồng bộ dữ liệu. " + error.message);
          fail(error);
        }
      }
    };
    $("gcImportParse").onclick = parse;
    $("gcResultSheet").onchange = parse;
    $("gcImportFilter").onchange = () => {
      limit = 100;
      render();
    };
    $("gcImportMore").onclick = () => {
      limit += 100;
      render();
    };
    $("gcImportPreset").onchange = () => {
      const selected = profiles()[$("gcImportPreset").value] || {
        layout: "auto",
        headerRow: "",
        idColumn: "",
        nameColumn: "",
        nominalColumn: "",
        unitColumn: "",
        sampleColumns: "",
      };
      for (const [key, value] of Object.entries(selected))
        if ($("gcImport_" + key)) $("gcImport_" + key).value = value;
      parse();
    };
    $("gcImportSavePreset").onclick = () => {
      const name = $("gcImportProfileName").value.trim();
      if (!name) {
        message("Nhập tên mẫu đọc cho máy đo.");
        return;
      }
      const data = profiles();
      data[name] = profile();
      localStorage.setItem(presetsKey, JSON.stringify(data));
      loadProfiles();
      $("gcImportPreset").value = name;
      message("Đã lưu mẫu đọc trong trình duyệt này.");
    };
    $("gcImportCandidates").onchange = (event) => {
      const row = event.target.closest("[data-candidate]");
      if (!row) return;
      const c = candidates[+row.dataset.candidate];
      if (event.target.hasAttribute("data-accept")) c.accepted = event.target.checked && valid(c);
      else {
        c.accepted = false;
        if (event.target.hasAttribute("data-match")) {
          c.muc_no = Number(event.target.value) || null;
          c.status = c.muc_no ? "matched" : "unmatched";
          c.reason = "Người dùng chọn đặc tính";
        }
        if (event.target.hasAttribute("data-unit")) {
          c.unit = event.target.value;
          if (c.reason !== "Người dùng chọn đặc tính") Object.assign(c, P.match(c, features()));
        }
        if (event.target.hasAttribute("data-import-value")) {
          const s = c.samples.find((s) => s.sample === Number(event.target.dataset.importValue));
          delete s.warning;
          Object.assign(s, P.valueCell(event.target.value) || { value: null, raw: "" }, {
            manualCorrected: true,
          });
        }
      }
      render();
    };
    $("gcImportSelectMatched").onclick = () => {
      if (
        !confirm(
          "Tôi đã đối chiếu bản gốc, đặc tính, đơn vị và từng mẫu của các dòng đang hiển thị. Chọn các dòng hợp lệ này?",
        )
      )
        return;
      for (const c of visible().slice(0, limit))
        if (c.status === "matched" && valid(candidates[c.index])) candidates[c.index].accepted = true;
      render();
    };
    $("gcImportSameUnit").onchange = () => {
      if (!$("gcImportSameUnit").checked) return;
      for (const c of candidates)
        if (!c.unit) {
          c.unit = "standard";
          if (c.reason !== "Người dùng chọn đặc tính") Object.assign(c, P.match(c, features()));
        }
      render();
    };
    $("gcImportSync").onclick = () => {
      try {
        const chosen = candidates.filter((c) => c.accepted && valid(c));
        if (!chosen.length) throw Error("Chọn các giá trị đã xác minh trước.");
        const proposed = new Map(),
          trace = [];
        for (const c of chosen) {
          const m = features().find((m) => m.muc_no === Number(c.muc_no));
          for (const s of c.samples) {
            const conversion =
              m.kieu === "so" ? P.convert(s.value, s.unit || c.unit, m.don_vi) : { value: s.value };
            if (conversion.error) throw Error(conversion.error);
            const k = m.muc_no + "/" + s.sample,
              value = String(conversion.value),
              old = proposed.get(k);
            if (old && old.value !== value)
              throw Error("Có giá trị khác nhau cùng đặc tính/mẫu. Bỏ chọn dòng trùng và xác minh lại.");
            proposed.set(k, { muc_no: m.muc_no, mau: s.sample, value });
            trace.push({
              muc_no: m.muc_no,
              mau: s.sample,
              raw: s.raw,
              don_vi_nguon: s.unit || c.unit,
              value: conversion.value,
              chuyen_doi: conversion.note || null,
              source: s.source,
              sua_tay: !!s.manualCorrected,
            });
          }
        }
        const conflicts = [...proposed.values()].filter((x) => {
          const raw = entry().get(x.muc_no, x.mau),
            a = P.number(raw),
            b = P.number(x.value);
          return raw !== "" && String(raw) !== x.value && !(a !== null && b !== null && a === b);
        });
        const overwrite =
          !conflicts.length ||
          confirm(
            "Có " +
              conflicts.length +
              " ô đã có giá trị khác. Xác nhận ghi đè các ô này? Chọn Hủy để giữ giá trị đã nhập.",
          );
        const items = [...proposed.values()].filter(
          (x) => overwrite || !conflicts.some((c) => c.muc_no === x.muc_no && c.mau === x.mau),
        );
        syncing = true;
        entry().setMany(items);
        syncing = false;
        if (items.length) {
          applied = true;
          // A second sync replaces provenance for the same cell instead of recording
          // stale copies of a previously accepted value.
          const latest = new Map(appliedRows.map((t) => [t.muc_no + "/" + t.mau, t]));
          for (const t of trace.filter((t) => items.some((i) => i.muc_no === t.muc_no && i.mau === t.mau)))
            latest.set(t.muc_no + "/" + t.mau, t);
          appliedRows = [...latest.values()];
        }
        $("gcResultConfirmed").checked = false;
        message(
          "Đã điền " +
            items.length +
            " ô vào bảng chưa lưu" +
            (!overwrite ? " ; giữ " + conflicts.length + " ô đã nhập" : "") +
            ". Đối chiếu bảng và xác nhận trước khi Lưu kết quả đo.",
        );
        onSync();
      } catch (error) {
        syncing = false;
        message(error.message);
      }
    };
    loadProfiles();
    return {
      hasApplied: () => applied,
      reset() {
        ++serial;
        abort?.abort();
        if (url) URL.revokeObjectURL(url);
        url = null;
        file = null;
        documentData = null;
        candidates = [];
        applied = false;
        appliedRows = [];
        uploaded = null;
        $("gcResultFile").value = "";
        $("gcResultOriginal").replaceChildren();
        $("gcImportRaw").textContent = "";
        $("gcResultSheet").replaceChildren();
        $("gcImportSameUnit").checked = false;
        $("gcResultConfirmed").checked = false;
        $("gcImportCandidates").replaceChildren();
        message("Chọn file chứa giá trị đo thực tế của Model/Revision này.");
      },
      edited() {
        if (applied && !syncing) $("gcResultConfirmed").checked = false;
      },
      async prepareSave() {
        if (!applied) return { nguon_nhap: "nhap_tay" };
        if (!$("gcResultConfirmed").checked)
          throw Object.assign(
            Error("Đối chiếu bảng kết quả sau đồng bộ/sửa tay và xác nhận trước khi lưu."),
            {
              code: "P0001",
            },
          );
        if ($("gcResultAttach").checked && !uploaded) {
          const session = await MesAuth.getSession();
          if (!session) throw Error("Cần đăng nhập để lưu file gốc.");
          const ext = file.name.split(".").at(-1).toLowerCase(),
            mime = {
              pdf: "application/pdf",
              xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              xls: "application/vnd.ms-excel",
              jpg: "image/jpeg",
              jpeg: "image/jpeg",
              png: "image/png",
            }[ext];
          const path = session.user.id + "/" + crypto.randomUUID() + "." + ext,
            bucket = "ipqc-gia-cong-ket-qua";
          const bytes = await file.arrayBuffer(),
            digest = await crypto.subtle.digest("SHA-256", bytes);
          const r = await sb.storage.from(bucket).upload(path, file, { contentType: mime, upsert: false });
          if (r.error) throw r.error;
          uploaded = {
            bucket,
            path,
            name: file.name,
            mime,
            size: file.size,
            sha256: [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, "0")).join(""),
          };
        }
        return {
          nguon_nhap: "tu_file",
          xac_nhan_file: true,
          tep_ket_qua: $("gcResultAttach").checked ? uploaded : null,
          nhan_dien: {
            ten_file: file.name,
            profile: profile(),
            gia_tri_da_xac_minh: appliedRows.map((row) => {
              const current = entry().get(row.muc_no, row.mau),
                m = features().find((m) => m.muc_no === row.muc_no);
              const saved = m?.kieu === "so" ? P.number(current) : current === "true";
              return { ...row, gia_tri_luu: saved, da_sua_sau_dong_bo: saved !== row.value };
            }),
          },
        };
      },
    };
  }
  return { mount };
})();
