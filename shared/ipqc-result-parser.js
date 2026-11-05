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
  const code = (value) => norm(value).replace(/\s/g, "");
  function number(value) {
    if (typeof value === "number") return Number.isFinite(value) ? value : null;
    const s = String(value ?? "")
      .trim()
      .replace(/−/g, "-");
    return /^[+-]?(?:\d+(?:[.,]\d*)?|[.,]\d+)(?:e[+-]?\d+)?$/i.test(s) ? Number(s.replace(",", ".")) : null;
  }
  function unit(value) {
    const v = String(value ?? "")
      .trim()
      .toLowerCase();
    return { µm: "um", μm: "um", micron: "um", inch: "in", inches: "in", '"': "in", "°": "deg", degree: "deg" }[v] || v;
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
      return { value: Number(((value * linear[from]) / linear[to]).toPrecision(14)), note: from + " → " + to };
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
    const m = /^([+−-]?(?:\d+(?:[.,]\d*)?|[.,]\d+)(?:e[+-]?\d+)?)\s*(mm|cm|µm|μm|um|in|inch|deg|rad|°)?$/i.exec(s);
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
    const nameRow = /^\d+$/.test(profile.nameColumn || "") ? Number(profile.nameColumn) - 1 : find(aliases.name);
    const unitRow = /^\d+$/.test(profile.unitColumn || "") ? Number(profile.unitColumn) - 1 : find(aliases.unit);
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
  function parse(sheets, profile = {}) {
    return sheets
      .flatMap((sheet) => {
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
    if (!found.length) {
      const name = norm(candidate.name)
        .replace(/\b\d+(?: \d+)?\b/g, "")
        .trim();
      found = features.filter((m) => norm(m.hang_muc) === name);
      reason = "Tên đặc tính";
      if (found.length !== 1 && candidate.nominal !== null) {
        found = features.filter(
          (m) =>
            (norm(m.hang_muc) === name || String(m.muc_no) === String(candidate.id)) &&
            number(m.danh_nghia) !== null &&
            Math.abs(Number(m.danh_nghia) - candidate.nominal) < 1e-8,
        );
        reason = "Tên/mã No và danh nghĩa";
      }
    }
    return {
      muc_no: found.length === 1 ? found[0].muc_no : null,
      reason: found.length === 1 ? reason : found.length ? "Trùng tên/mã, cần chọn lại" : "Chưa khớp tiêu chuẩn",
      status: found.length === 1 ? "matched" : found.length ? "ambiguous" : "unmatched",
    };
  }
  const api = { parse, match, convert, unit, number, norm, column, valueCell };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.IpqcResultParser = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
