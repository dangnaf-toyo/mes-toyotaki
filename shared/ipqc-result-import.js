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
      syncing = false,
      rendering = false;
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
        '<option value="">Tự động</option>' +
        Object.keys(data)
          .map((name) => "<option>" + E(name) + "</option>")
          .join("");
    }
    const feature = (c) => features().find((m) => Number(m.muc_no) === Number(c.muc_no));
    const supplementaryUnit = () =>
      $("gcImportSameUnit").checked ? P.unit($("gcImportDefaultUnit").value) : "";
    const sourceUnit = (c, s) =>
      P.unit(c.unitOverride !== undefined ? c.unitOverride : s?.unit || c.unit) || supplementaryUnit();
    const mesUnit = (m) => P.unit(m.don_vi) || supplementaryUnit();
    function rematch(c) {
      if (c.manualMapping) return;
      Object.assign(
        c,
        P.match(
          { ...c, unit: sourceUnit(c, c.samples[0]) },
          features().map((m) => ({ ...m, don_vi: mesUnit(m) })),
        ),
      );
    }
    function assess(c) {
      const m = feature(c),
        errors = [];
      let label = "Khớp";
      if (!m)
        return {
          label: c.status === "ambiguous" ? "Trùng đặc tính" : "Chưa ghép",
          errors: ["Chọn đặc tính MES tương ứng."],
          warnings: [],
        };
      if (!c.samples.length) errors.push("Không có giá trị đo.");
      for (const s of c.samples) {
        if (!Number.isInteger(s.sample) || s.sample < 1 || s.sample > 100)
          errors.push("Mã mẫu không hợp lệ (1–100).");
        if (m.kieu === "so") {
          if (typeof s.value !== "number" || !Number.isFinite(s.value)) {
            label = "Lỗi giá trị";
            errors.push("Mẫu " + s.sample + ": " + (s.warning || "Actual không phải số."));
          } else if (!sourceUnit(c, s) || !mesUnit(m)) {
            label = "Cần đơn vị";
            errors.push(
              !sourceUnit(c, s)
                ? "File chưa ghi đơn vị. Chọn đơn vị của giá trị đo."
                : "MES chưa có đơn vị. Chọn đơn vị bổ sung và tích Đã đối chiếu đơn vị.",
            );
          } else {
            const conversion = P.convert(s.value, sourceUnit(c, s), mesUnit(m));
            if (conversion.error) {
              label = "Sai đơn vị";
              errors.push(sourceUnit(c, s) + " → " + mesUnit(m) + ": không tương thích.");
            }
          }
        } else if (typeof s.value !== "boolean") {
          label = "Lỗi giá trị";
          errors.push("Mẫu " + s.sample + ": cần OK hoặc NG.");
        }
      }
      const warnings = P.specWarnings(
        { ...c, unit: sourceUnit(c, c.samples[0]) },
        { ...m, don_vi: mesUnit(m) },
      ).filter((warning) => warning !== "Sai đơn vị" || !errors.length);
      if (c.source.method === "ocr") warnings.push("Đối chiếu giá trị OCR với file gốc.");
      return {
        label: errors.length ? (label === "Khớp" ? "Lỗi giá trị" : label) : "Khớp",
        errors: [...new Set(errors)],
        warnings,
      };
    }
    function validate() {
      const cells = new Map();
      for (const c of candidates) {
        c.validation = assess(c);
        c.selected = !c.excluded && !c.validation.errors.length;
        if (!c.selected) continue;
        for (const s of c.samples) {
          const key = Number(c.muc_no) + "/" + s.sample;
          if (!cells.has(key)) cells.set(key, []);
          cells.get(key).push(c);
        }
      }
      for (const [key, rows] of cells)
        if (rows.length > 1)
          for (const c of rows) {
            c.validation.label = "Trùng đặc tính";
            c.validation.errors.push(
              "Nhiều dòng cùng đặc tính/mẫu " +
                key +
                ". Bỏ chọn dòng thừa hoặc sửa mapping; không tự gộp mẫu.",
            );
            c.validation.duplicate = true;
          }
    }
    const valid = (c) => !c.validation.errors.length;
    function visible() {
      const filter = $("gcImportFilter").value;
      return candidates
        .map((c, i) => ({ ...c, index: i }))
        .filter((c) => !filter || (filter === "matched" ? valid(c) : !valid(c)));
    }
    function render() {
      if (rendering) return;
      rendering = true;
      try {
        validate();
        const data = visible();
        $("gcImportCandidates").innerHTML =
          "<table><thead><tr>" +
          ["STT", "Đặc tính CMM", "Giá trị đo", "Đặc tính MES", "Đơn vị", "Trạng thái", "Chọn"]
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
                (c.index + 1) +
                '</td><td title="' +
                E(
                  c.source.sheet +
                    " · " +
                    (c.source.row || c.source.column) +
                    " · Nominal: " +
                    (c.nominal ?? "?") +
                    " · Tol: " +
                    (c.upper ?? "?") +
                    " / " +
                    (c.lower ?? "?"),
                ) +
                '"><strong>' +
                E(c.id || c.name) +
                "</strong>" +
                (c.name && c.name !== c.id ? "<small>" + E(c.name) + "</small>" : "") +
                "</td><td>" +
                c.samples
                  .map(
                    (s) =>
                      '<label class="cmm-value">M' +
                      s.sample +
                      ' <input data-import-value="' +
                      s.sample +
                      '" value="' +
                      E(s.raw) +
                      '" aria-label="' +
                      E(c.id + " · Mẫu " + s.sample) +
                      '"></label>',
                  )
                  .join("") +
                '</td><td><select data-match aria-label="Đặc tính MES dòng ' +
                (c.index + 1) +
                '"><option value="">Chọn đặc tính</option>' +
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
                '</select></td><td><select data-unit aria-label="Đơn vị dòng ' +
                (c.index + 1) +
                '"><option value="">Chưa rõ</option>' +
                [...new Set(["mm", "cm", "um", "in", "deg", "rad", sourceUnit(c, c.samples[0])])]
                  .filter(Boolean)
                  .map(
                    (u) =>
                      '<option value="' +
                      u +
                      '"' +
                      (sourceUnit(c, c.samples[0]) === u ? " selected" : "") +
                      ">" +
                      E(u) +
                      "</option>",
                  )
                  .join("") +
                '</select></td><td><details class="cmm-state"><summary class="' +
                (valid(c) ? "good" : /Sai|Lỗi/.test(c.validation.label) ? "bad" : "warn") +
                '">' +
                E(c.validation.label) +
                (c.validation.warnings.length ? " ⚠" : "") +
                '</summary><div id="cmm-reason-' +
                c.index +
                '">' +
                [
                  ...c.validation.errors,
                  ...c.validation.warnings,
                  c.manualMapping ? "Ghép thủ công." : c.reason,
                ]
                  .filter(Boolean)
                  .map((s) => "<p>" + E(s) + "</p>")
                  .join("") +
                '</div></details></td><td><label class="cmm-pick"><input type="checkbox" data-accept ' +
                (c.selected ? "checked " : "") +
                (!valid(c) && !c.validation.duplicate
                  ? 'disabled title="' + E(c.validation.errors.join(" ")) + '" '
                  : "") +
                ' aria-describedby="cmm-reason-' +
                c.index +
                '" aria-label="Chọn dòng ' +
                (c.index + 1) +
                '"></label></td></tr>',
            )
            .join("") +
          "</tbody></table>";
        $("gcImportMore").hidden = data.length <= limit;
        $("gcImportSync").disabled = !candidates.length;
        if (!candidates.length)
          $("gcImportCandidates").textContent = "Chưa đọc được giá trị đo. Chọn mẫu CMM hoặc nhập tay.";
        summary();
      } finally {
        rendering = false;
      }
    }
    function parse() {
      if (!documentData) return;
      const selected = $("gcResultSheet").value;
      const sheets = documentData.sheets.filter((s) => selected === "*" || s.name === selected);
      candidates = P.parse(sheets, profile()).map((c) => ({
        ...c,
        ...P.match(c, features()),
        unit: c.unit || c.samples.find((s) => s.unit)?.unit || "",
      }));
      for (const c of candidates) rematch(c);
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
        message("Chưa đọc được giá trị đo. Chọn trang hoặc mẫu CMM.");
        return;
      }
      message(
        (candidates.some((c) => c.template === "zeiss-calypso") ? "ZEISS Calypso · " : "") +
          candidates.length +
          " đặc tính. " +
          documentData.warnings.join(" "),
      );
    }
    function summary() {
      const extracted = candidates.filter((c) => c.samples.some((s) => s.value !== null));
      const matched = candidates.filter(valid).length;
      $("gcImportSummary").innerHTML = [
        ["read", "Đã đọc", extracted.length],
        ["matched", "Đã khớp", matched],
        ["unmatched", "Chưa khớp", candidates.length - matched],
        ["filled", "Đã điền", appliedRows.length],
      ]
        .map(([key, label, n]) => "<span>" + label + ': <b data-count="' + key + '">' + n + "</b></span>")
        .join("");
    }
    $("gcResultMode").onchange = () => {
      $("gcResultImportPanel").hidden = $("gcResultMode").value !== "file";
    };
    $("gcResultFile").onchange = async () => {
      const chosen = $("gcResultFile").files[0];
      if (!chosen) return;
      if (!entry()) {
        message("Chọn Model và Revision trước.");
        return;
      }
      if (applied) {
        message("Đã điền từ file này. Lưu hoặc làm mới lần kiểm trước khi đổi file.");
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
        $("gcImportDefaultUnit").value = "";
        render();
        message("Đang đọc file CMM…");
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
        } else preview.textContent = file.name;
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
          '<option value="*">Tất cả trang</option>' +
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
          message("Không đọc được file: " + error.message);
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
        message("Nhập tên mẫu CMM.");
        return;
      }
      const data = profiles();
      data[name] = profile();
      localStorage.setItem(presetsKey, JSON.stringify(data));
      loadProfiles();
      $("gcImportPreset").value = name;
      message("Đã lưu mẫu CMM.");
    };
    $("gcImportCandidates").onchange = (event) => {
      // Replacing a focused input can fire a native change/blur event. Its value
      // was already captured; do not enter another DOM replacement from that event.
      if (rendering) return;
      const row = event.target.closest("[data-candidate]");
      if (!row) return;
      const c = candidates[+row.dataset.candidate];
      if (event.target.hasAttribute("data-accept")) c.excluded = !event.target.checked;
      else {
        if (event.target.hasAttribute("data-match")) {
          c.muc_no = Number(event.target.value) || null;
          c.status = c.muc_no ? "matched" : "unmatched";
          c.manualMapping = !!c.muc_no;
          c.reason = "Ghép thủ công";
        }
        if (event.target.hasAttribute("data-unit")) {
          c.unitOverride = event.target.value;
          rematch(c);
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
      message("Đã cập nhật đối chiếu.");
    };
    $("gcImportSameUnit").onchange = $("gcImportDefaultUnit").onchange = () => {
      for (const c of candidates) rematch(c);
      render();
      message(
        supplementaryUnit()
          ? "Đã xác nhận đơn vị bổ sung: " + supplementaryUnit() + "."
          : "Chọn đơn vị rồi tích Đã đối chiếu đơn vị.",
      );
    };
    $("gcImportSync").onclick = () => {
      try {
        validate();
        const chosen = candidates.filter((c) => c.selected && valid(c));
        if (!chosen.length) {
          const reason = candidates.find((c) => !valid(c))?.validation.errors[0];
          throw Error(reason || "Chọn dòng cần điền.");
        }
        if (!entry()) throw Error("Chưa có bảng kết quả. Chọn lại Model và Revision.");
        const proposed = new Map(),
          trace = [];
        for (const c of chosen) {
          const m = feature(c),
            no = Number(m.muc_no);
          for (const s of c.samples) {
            const conversion =
              m.kieu === "so" ? P.convert(s.value, sourceUnit(c, s), mesUnit(m)) : { value: s.value };
            if (conversion.error) throw Error(conversion.error);
            const k = no + "/" + s.sample,
              value =
                m.kieu === "so" && sourceUnit(c, s) === mesUnit(m) && P.number(s.raw) !== null
                  ? s.raw.trim().replace(/−/g, "-").replace(",", ".")
                  : String(conversion.value),
              old = proposed.get(k);
            if (old && old.value !== value)
              throw Error("Có giá trị khác nhau cùng đặc tính/mẫu. Bỏ chọn dòng trùng và xác minh lại.");
            proposed.set(k, { muc_no: no, mau: s.sample, value });
            trace.push({
              muc_no: no,
              mau: s.sample,
              raw: s.raw,
              don_vi_nguon: sourceUnit(c, s),
              don_vi_mes: mesUnit(m),
              don_vi_bo_sung_da_xac_nhan: supplementaryUnit() || null,
              ghep_thu_cong: !!c.manualMapping,
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
          !conflicts.length || confirm("Ghi đè " + conflicts.length + " ô đã nhập? Hủy để giữ nguyên.");
        const items = [...proposed.values()].filter(
          (x) => overwrite || !conflicts.some((c) => c.muc_no === x.muc_no && c.mau === x.mau),
        );
        syncing = true;
        entry().setMany(items);
        for (const item of items)
          if (entry().get(item.muc_no, item.mau) !== item.value)
            throw Error(
              "Chưa điền được đặc tính " +
                item.muc_no +
                " / mẫu " +
                item.mau +
                ". Kiểm tra lại bảng kết quả.",
            );
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
        $("gcResultConfirmed").checked = items.length > 0;
        render();
        const unresolved = candidates.filter((c) => !valid(c)).length;
        message(
          "Đã điền " +
            items.length +
            " ô · Chưa khớp " +
            unresolved +
            " dòng" +
            (!overwrite ? " · Giữ " + conflicts.length + " ô đã nhập" : "") +
            ". Chưa lưu.",
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
        $("gcImportDefaultUnit").value = "";
        $("gcResultConfirmed").checked = false;
        $("gcImportCandidates").replaceChildren();
        summary();
        message("Chọn file CMM.");
      },
      edited() {
        if (applied && !syncing) $("gcResultConfirmed").checked = false;
      },
      async prepareSave() {
        if (!applied) return { nguon_nhap: "nhap_tay" };
        if (!$("gcResultConfirmed").checked)
          throw Object.assign(Error("Tích Đã kiểm tra kết quả trước khi lưu."), {
            code: "P0001",
          });
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
                m = features().find((m) => Number(m.muc_no) === row.muc_no);
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
