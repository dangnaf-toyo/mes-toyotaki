/* Parse actual measurements; never create standard limits or fill missing measurements. */
(function (root) {
  const norm = (value) =>
    String(value ?? "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/đ/g, "d")
      .replace(/Đ/g, "D")
      .toLowerCase()
      .replace(/[øφ⌀]/g, " duong kinh ")
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
  // Keep separators: characteristic 7-1 is not characteristic 71.
  const code = (value) =>
    String(value ?? "")
      .trim()
      .toLowerCase()
      .replace(/\s+/g, "");
  function number(value) {
    if (typeof value === "number") return Number.isFinite(value) ? value : null;
    const s = String(value ?? "")
      .trim()
      .replace(/−/g, "-");
    return /^[+-]?(?:\d+(?:[.,]\d*)?|[.,]\d+)(?:e[+-]?\d+)?$/i.test(s) ? Number(s.replace(",", ".")) : null;
  }
  function unit(value) {
    const v = String(value ?? "")
      .normalize("NFKC")
      .trim()
      .toLowerCase()
      .replace(/^[\[(]\s*|\s*[\])]$/g, "");
    return (
      {
        µm: "um",
        μm: "um",
        micron: "um",
        millimeter: "mm",
        millimeters: "mm",
        millimetre: "mm",
        millimetres: "mm",
        inch: "in",
        inches: "in",
        '"': "in",
        "°": "deg",
        degree: "deg",
      }[v] || v
    );
  }
  function convert(value, from, to) {
    if (!Number.isFinite(value)) return { error: "Giá trị không phải số hữu hạn" };
    if (from === "standard") return { value, note: "Người dùng xác nhận cùng đơn vị tiêu chuẩn" };
    from = unit(from);
    to = unit(to);
    if (!from || !to) return { error: "Chưa rõ đơn vị; cần xác minh" };
    if (from === to) return { value };
    const linear = { mm: 1, cm: 10, m: 1000, um: 0.001, in: 25.4 };
    if (linear[from] && linear[to])
      return {
        value: Number(((value * linear[from]) / linear[to]).toPrecision(14)),
        note: from + " → " + to,
      };
    if (from === "rad" && to === "deg") return { value: (value * 180) / Math.PI, note: "rad → deg" };
    if (from === "deg" && to === "rad") return { value: (value * Math.PI) / 180, note: "deg → rad" };
    return { error: "Không hỗ trợ chuyển đơn vị " + from + " → " + to };
  }
  const aliases = {
    id: /^(ma dac tinh|ma kich thuoc|feature id|feature code|characteristic id|id|no|stt|item|item no)$/,
    name: /^(hang muc|ten dac tinh|ten|vi tri|characteristic|feature|description|name|element)$/,
    nominal: /^(nominal|nominal value|danh nghia|kich thuoc|dimension|basic)$/,
    unit: /^(don vi|unit|units)$/,
  };
  function sampleHeader(value) {
    const s = norm(value);
    let m = /^(?:mau|sample|actual|measured|measure|gia tri do|ket qua do)(?: value)?\s*(\d+)?$/.exec(s);
    if (m) return Number(m[1] || 1);
    m = /^(\d+)\s*(?:cavity|cav|mau|sample)(?:\s*\d+)?(?:\s|$)/.exec(s);
    return m ? Number(m[1]) : null;
  }
  function column(value) {
    if (typeof value === "number") return value - 1;
    const s = String(value || "")
      .trim()
      .toUpperCase();
    if (!/^[A-Z]+$/.test(s)) return -1;
    return [...s].reduce((n, c) => n * 26 + c.charCodeAt(0) - 64, 0) - 1;
  }
  function configuredSamples(value) {
    return String(value || "")
      .split(",")
      .filter((s) => s.trim())
      .map((s, i) => {
        const [address, sample] = s.trim().split(":");
        return { col: column(address), sample: Number(sample || i + 1) };
      })
      .filter((x) => x.col >= 0 && Number.isInteger(x.sample) && x.sample >= 1 && x.sample <= 100);
  }
  function header(row, profile = {}) {
    const result = { samples: [] };
    for (const [i, value] of row.entries()) {
      const text = norm(value);
      for (const [key, pattern] of Object.entries(aliases)) if (pattern.test(text)) result[key] = i;
      const sample = sampleHeader(value);
      if (sample) result.samples.push({ col: i, sample, label: String(value) });
    }
    if (!result.samples.length) {
      const i = row.findIndex((v) => /^(actual value|result|ket qua)$/.test(norm(v)));
      if (i >= 0) result.samples = [{ col: i, sample: 1, label: String(row[i]) }];
    }
    for (const key of ["id", "name", "nominal", "unit"])
      if (profile[key + "Column"]) result[key] = column(profile[key + "Column"]);
    if (profile.sampleColumns) result.samples = configuredSamples(profile.sampleColumns);
    return result;
  }
  function valueCell(raw) {
    const s = String(raw ?? "").trim();
    if (!s) return null;
    const ok = norm(s);
    if (["ok", "pass", "dat"].includes(ok)) return { value: true, raw: s };
    if (["ng", "fail", "khong dat"].includes(ok)) return { value: false, raw: s };
    const m =
      /^([+−-]?(?:\d+(?:[.,]\d*)?|[.,]\d+)(?:e[+-]?\d+)?)\s*(mm|cm|µm|μm|um|in|inch|deg|rad|°)?$/i.exec(s);
    if (!m) return { value: null, raw: s, warning: "Không đọc được giá trị số/OK-NG" };
    return { value: number(m[1]), raw: s, unit: unit(m[2] || "") };
  }
  function rows(sheet, profile) {
    const matrix = sheet.rows || [],
      out = [];
    let index = profile.headerRow
      ? Number(profile.headerRow) - 1
      : matrix.findIndex(
          (r, i) =>
            i < 100 &&
            (header(r, profile).id !== undefined || header(r, profile).name !== undefined) &&
            header(r, profile).samples.length,
        );
    if (index < 0) return out;
    const h = header(matrix[index] || [], profile);
    if (!h.samples.length) return out;
    for (let i = index + 1; i < matrix.length; i++) {
      const row = matrix[i] || [],
        id = h.id === undefined ? "" : String(row[h.id] ?? "").trim(),
        name = h.name === undefined ? "" : String(row[h.name] ?? "").trim();
      if (!id && !name) continue;
      const samples = h.samples.flatMap((s) => {
        const value = valueCell(row[s.col]);
        return value
          ? [
              {
                ...value,
                sample: s.sample,
                source: {
                  sheet: sheet.name,
                  row: i + 1,
                  column: s.col + 1,
                  method: sheet.method || "excel",
                  confidence: sheet.confidence?.[i],
                },
              },
            ]
          : [];
      });
      if (!samples.length) continue;
      if (sheet.method === "ocr" && row.length !== (matrix[index] || []).length && !profile.sampleColumns) {
        for (const sample of samples) {
          sample.value = null;
          sample.warning = "OCR chưa xác định chắc cột mẫu; cấu hình cột hoặc xác minh/sửa từng giá trị";
        }
      }
      out.push({
        id,
        name,
        nominal: number(row[h.nominal]),
        unit: unit(row[h.unit]),
        samples,
        source: { sheet: sheet.name, row: i + 1, method: sheet.method || "excel" },
      });
    }
    return out;
  }
  function columns(sheet, profile) {
    const matrix = sheet.rows || [],
      out = [];
    const isId = (value) => aliases.id.test(norm(value)) || norm(value) === "hang muc kiem tra";
    const idRow = profile.headerRow
      ? Number(profile.headerRow) - 1
      : matrix.findIndex((r, i) => i < 100 && r.some(isId));
    if (idRow < 0) return out;
    const labelCol = profile.idColumn ? column(profile.idColumn) : matrix[idRow].findIndex(isId);
    if (labelCol < 0) return out;
    const find = (pattern) => matrix.findIndex((r) => r.some((v) => pattern.test(norm(v))));
    const nominalRow = /^\d+$/.test(profile.nominalColumn || "")
      ? Number(profile.nominalColumn) - 1
      : find(/^(nominal|nominal value|danh nghia|kich thuoc|dimension|basic|tieu chuan)$/);
    const nameRow = /^\d+$/.test(profile.nameColumn || "")
      ? Number(profile.nameColumn) - 1
      : find(aliases.name);
    const unitRow = /^\d+$/.test(profile.unitColumn || "")
      ? Number(profile.unitColumn) - 1
      : find(aliases.unit);
    const configured = String(profile.sampleColumns || "")
      .split(",")
      .filter(Boolean)
      .map((s, i) => {
        const [r, n] = s.split(":");
        return { row: Number(r) - 1, sample: Number(n || i + 1) };
      });
    const sampleRows = configured.length
      ? configured
      : matrix.flatMap((r, i) => {
          const s = sampleHeader(r[labelCol]);
          return s ? [{ row: i, sample: s }] : [];
        });
    for (let c = labelCol + 1; c < (matrix[idRow] || []).length; c++) {
      const id = String(matrix[idRow][c] ?? "").trim();
      if (!id) continue;
      const samples = sampleRows.flatMap(({ row, sample }) => {
        const value = valueCell(matrix[row]?.[c]);
        return value
          ? [
              {
                ...value,
                sample,
                source: { sheet: sheet.name, row: row + 1, column: c + 1, method: sheet.method || "excel" },
              },
            ]
          : [];
      });
      if (samples.length)
        out.push({
          id,
          name: String(matrix[nameRow]?.[c] || ""),
          nominal: number(matrix[nominalRow]?.[c]),
          unit: unit(matrix[unitRow]?.[c]),
          samples,
          source: { sheet: sheet.name, column: c + 1, method: sheet.method || "excel" },
        });
    }
    return out;
  }
  function text(sheet) {
    const out = [];
    for (const [i, row] of (sheet.rows || []).entries()) {
      const line = row
        .filter((v) => v != null && String(v).trim())
        .join(" ")
        .trim();
      const m =
        /^(.{1,120}?)\s*(?:=|:)\s*(.+)$/.exec(line) ||
        /^([A-Za-z][A-Za-z0-9_.-]{1,24})\s+([+−-]?\d+(?:[.,]\d+)?\s*(?:mm|cm|um|in|deg)?)$/.exec(line);
      if (!m) continue;
      const labels = m[1].trim(),
        parts = m[2].split(/[;|]/),
        samples = parts.flatMap((part, j) => {
          const cell = valueCell(part);
          return cell
            ? [
                {
                  ...cell,
                  sample: j + 1,
                  source: {
                    sheet: sheet.name,
                    row: i + 1,
                    method: sheet.method || "text",
                    confidence: sheet.confidence?.[i],
                  },
                },
              ]
            : [];
        });
      if (!samples.length) continue;
      const nominal = /[øφ⌀]|chieu|length|width|height|radius/i.test(labels)
        ? number(labels.match(/\d+(?:[.,]\d+)?/)?.[0])
        : null;
      out.push({
        id: labels,
        name: labels,
        nominal,
        unit: samples.find((s) => s.unit)?.unit || "",
        samples,
        source: { sheet: sheet.name, row: i + 1, method: sheet.method || "text" },
      });
    }
    return out;
  }
  function pdfLines(items) {
    const lines = [];
    for (const item of items
      .filter((x) => x.str?.trim())
      .sort((a, b) => b.transform[5] - a.transform[5] || a.transform[4] - b.transform[4])) {
      let line = lines.find((l) => Math.abs(l.y - item.transform[5]) < 2);
      if (!line) {
        line = { y: item.transform[5], cells: [] };
        lines.push(line);
      }
      const cell = { text: item.str.trim(), x0: item.transform[4], x1: item.transform[4] + item.width };
      const previous = line.cells.at(-1);
      if (previous && cell.x0 - previous.x1 < Math.max(4, Math.abs(item.height || 10) * 0.7)) {
        previous.text += " " + cell.text;
        previous.x1 = cell.x1;
      } else line.cells.push(cell);
    }
    return lines;
  }
  function zeiss(sheet) {
    const lines = sheet.lines || [];
    const keys = {
      actual: /^actual(?: value)?(?: mm| in| um| deg)?$/,
      nominal: /^nominal(?: value)?$/,
      upper: /^upper tol(?:erance)?$/,
      lower: /^lower tol(?:erance)?$/,
      deviation: /^deviation$/,
    };
    const headerIndex = lines.findIndex((l) =>
      Object.values(keys).every((re) => l.cells.some((c) => re.test(norm(c.text)))),
    );
    if (headerIndex < 0) return null;
    const header = Object.entries(keys)
      .map(([key, re]) => {
        const c = lines[headerIndex].cells.find((c) => re.test(norm(c.text)));
        return { key, ...c, center: (c.x0 + c.x1) / 2 };
      })
      .sort((a, b) => a.center - b.center);
    const actual = header.find((c) => c.key === "actual");
    // Calypso prints the characteristic label above its numeric line, without an ID header.
    // Keep the positional lines instead of flattening the label into the Actual column.
    const out = [];
    let pending = null;
    const reportUnit = unit(
      sheet.unit ||
        lines
          .map((l) => l.cells.map((c) => c.text).join(" "))
          .join("\n")
          .match(/(?:\bunits?\s*[:=]|actual\s*[\[(])\s*(mm|cm|µm|μm|um|in|inch|deg|rad|°)\b/i)?.[1],
    );
    function finish() {
      if (!pending) return;
      const source = { sheet: sheet.name, row: pending.row, method: sheet.method, template: "zeiss-calypso" };
      const cell = valueCell(pending.values.actual || "") || {
        value: null,
        raw: "",
        warning: "Thiếu ô Actual trong PDF",
      };
      if (typeof cell.value !== "number") {
        cell.value = null;
        cell.warning ||= "Ô Actual không đọc được số";
      }
      out.push({
        id: pending.id,
        name: pending.name,
        nominal: number(pending.values.nominal),
        upper: number(pending.values.upper),
        lower: number(pending.values.lower),
        deviation: number(pending.values.deviation),
        unit: cell.unit || reportUnit,
        template: "zeiss-calypso",
        samples: [{ ...cell, sample: 1, source }],
        source,
      });
      pending = null;
    }
    for (let i = headerIndex + 1; i < lines.length; i++) {
      const line = lines[i];
      if (line.cells.some((c) => /^actual$/.test(norm(c.text)))) {
        finish();
        continue;
      }
      const label = line.cells.filter(
        (c) =>
          c.x0 < actual.x0 - actual.text.length * 0.8 &&
          /[a-z0-9]/i.test(c.text) &&
          (number(c.text) === null || (c.x0 + c.x1) / 2 < actual.x0 - actual.text.length * 0.8),
      );
      if (label.length) {
        finish();
        const title = label
          .map((c) => c.text)
          .join(" ")
          .trim();
        const parts = /^(\S+)\s+(.+)$/.exec(title);
        pending = { id: title, name: parts?.[2] || "", row: i + 1, values: {} };
      }
      if (!pending) continue;
      for (const c of line.cells.filter((c) => !label.includes(c))) {
        const x = (c.x0 + c.x1) / 2;
        const h = header.reduce((a, b) => (Math.abs(a.center - x) < Math.abs(b.center - x) ? a : b));
        // Bars, page numbers and annotation text are not measurements. Numeric cells on
        // a label line are deviation graphics, except when all numeric columns are inline.
        const numericCount = line.cells.filter(
          (v) => valueCell(v.text)?.value != null && !label.includes(v),
        ).length;
        if (label.length && numericCount < 2) continue;
        if (x < header[0].center - 50 || x > header.at(-1).center + 80) continue;
        if (valueCell(c.text)?.value != null || (h.key === "actual" && /\d|[?]/.test(c.text))) {
          if (pending.values[h.key] !== undefined) pending.values[h.key] += " " + c.text;
          else pending.values[h.key] = c.text;
        }
      }
      if (
        line.cells.filter((c) => !label.includes(c) && typeof valueCell(c.text)?.value === "number").length >=
        2
      )
        finish();
    }
    finish();
    return out;
  }
  function parse(sheets, profile = {}) {
    return sheets
      .flatMap((sheet) => {
        if (!profile.layout || profile.layout === "auto") {
          const detected = zeiss(sheet);
          if (detected !== null) return detected;
        }
        if (profile.layout === "columns") return columns(sheet, profile);
        if (profile.layout === "text") return text(sheet);
        const found = rows(sheet, profile);
        return found.length || profile.layout === "rows" ? found : text(sheet);
      })
      .slice(0, 5000);
  }
  function match(candidate, features) {
    let found = features.filter((m) => m.ma_dac_tinh && code(m.ma_dac_tinh) === code(candidate.id)),
      reason = "Mã đặc tính";
    if (!found.length && candidate.template === "zeiss-calypso") {
      // A descriptive name/position is usable without inventing a characteristic ID.
      // Repeated names are narrowed by the full dimensional specification below.
      const named = candidate.name ? features.filter((m) => norm(m.hang_muc) === norm(candidate.name)) : [];
      if (named.length === 1) found = named;
      else {
        found = features.filter(
          (m) =>
            candidate.nominal !== null &&
            candidate.upper !== null &&
            candidate.lower !== null &&
            candidate.unit &&
            number(m.danh_nghia) !== null &&
            m.don_vi &&
            (number(m.usl) !== null || number(m.dung_sai_tren) !== null) &&
            (number(m.lsl) !== null || number(m.dung_sai_duoi) !== null) &&
            !specWarnings(candidate, m).length,
        );
        if (named.length) found = found.filter((m) => named.includes(m));
      }
      reason = "Tên, danh nghĩa, dung sai và đơn vị";
    } else if (!found.length) {
      const name = norm(candidate.name)
        .replace(/\b\d+(?: \d+)?\b/g, "")
        .trim();
      found = features.filter((m) => norm(m.hang_muc) === name);
      reason = "Tên đặc tính";
      if (found.length !== 1 && candidate.nominal !== null) {
        found = features.filter(
          (m) =>
            norm(m.hang_muc) === name &&
            number(m.danh_nghia) !== null &&
            Math.abs(Number(m.danh_nghia) - candidate.nominal) < 1e-8,
        );
        reason = "Tên và danh nghĩa";
      }
    }
    return {
      muc_no: found.length === 1 ? found[0].muc_no : null,
      reason:
        found.length === 1 ? reason : found.length ? "Trùng tên/mã, cần chọn lại" : "Chưa khớp tiêu chuẩn",
      status: found.length === 1 ? "matched" : found.length ? "ambiguous" : "unmatched",
      warnings: found.length === 1 ? specWarnings(candidate, found[0]) : [],
    };
  }
  function specWarnings(candidate, feature) {
    const warnings = [];
    const diff = (a, b) => Math.abs(a - b) > 1e-8;
    const converted = (v) => convert(v, candidate.unit, feature.don_vi);
    if (candidate.nominal !== null && number(feature.danh_nghia) !== null) {
      const n = converted(candidate.nominal);
      if (!n.error && diff(n.value, Number(feature.danh_nghia))) warnings.push("Danh nghĩa báo cáo khác MES");
    }
    for (const [key, bound, sign] of [
      ["upper", "usl", 1],
      ["lower", "lsl", -1],
    ]) {
      if (candidate[key] == null || candidate.nominal == null) continue;
      const n = converted(candidate.nominal + candidate[key]);
      const tolerance = number(feature[key === "upper" ? "dung_sai_tren" : "dung_sai_duoi"]);
      const limit =
        number(feature[bound]) ??
        (number(feature.danh_nghia) !== null && tolerance !== null
          ? Number(feature.danh_nghia) + (feature.dung_sai_co_dau ? tolerance : sign * Math.abs(tolerance))
          : null);
      if (!n.error && limit !== null && diff(n.value, limit))
        warnings.push((key === "upper" ? "Giới hạn trên" : "Giới hạn dưới") + " báo cáo khác MES");
    }
    if (candidate.unit && feature.don_vi && converted(0).error) warnings.push("Sai đơn vị");
    return warnings;
  }
  const api = { parse, match, convert, unit, number, norm, column, valueCell, pdfLines, zeiss, specWarnings };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.IpqcResultParser = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
