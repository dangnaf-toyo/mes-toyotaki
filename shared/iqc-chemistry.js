/* Chemistry-specific interpretation. No material-name guessing, generated limits, averages or balance values. */
(function (root) {
  const ELEMENTS =
    "H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe Cs Ba La Ce Pr Nd Pm Sm Eu Gd Tb Dy Ho Er Tm Yb Lu Hf Ta W Re Os Ir Pt Au Hg Tl Pb Bi Po At Rn Fr Ra Ac Th Pa U Np Pu Am Cm Bk Cf Es Fm Md No Lr Rf Db Sg Bh Hs Mt Ds Rg Cn Nh Fl Mc Lv Ts Og".split(
      " ",
    );
  const aliases = {
    aluminium: "Al",
    aluminum: "Al",
    nhom: "Al",
    silicon: "Si",
    silic: "Si",
    iron: "Fe",
    sat: "Fe",
    copper: "Cu",
    dong: "Cu",
    manganese: "Mn",
    mangan: "Mn",
    magnesium: "Mg",
    magne: "Mg",
    zinc: "Zn",
    kem: "Zn",
    nickel: "Ni",
    niken: "Ni",
    titanium: "Ti",
    titan: "Ti",
    lead: "Pb",
    chi: "Pb",
    cadmium: "Cd",
    tin: "Sn",
    thiec: "Sn",
    chromium: "Cr",
    carbon: "C",
    sulfur: "S",
    phosphorus: "P",
  };
  const plain = (v) =>
    String(v ?? "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[đĐ]/g, "d")
      .toLowerCase()
      .trim();
  function unit(v) {
    const s = plain(v).replace(/\s/g, "");
    if (/%|wt[.]?%|mass%/.test(s)) return "%";
    if (/ppm/.test(s)) return "ppm";
    if (/mg\/kg|μg\/g|µg\/g|ug\/g/.test(s)) return "mg/kg";
    return "";
  }
  function element(v) {
    const s = plain(v)
      .replace(/\([^)]*\)|\[[^\]]*\]/g, "")
      .replace(/\s*%$/, "")
      .trim();
    return ELEMENTS.find((e) => e.toLowerCase() === s) || aliases[s] || null;
  }
  function decimal(raw) {
    const s = String(raw ?? "")
      .trim()
      .replace(",", ".")
      .replace(/^([+-]?)[.](\d)/, (_, sign, digit) => sign + "0." + digit);
    if (!s || s.length > 64) return null;
    const m = /^([+-]?)(\d+)(?:[.](\d+))?(?:[eE]([+-]?\d+))?$/.exec(s);
    if (!m || Math.abs(Number(m[4] || 0)) > 30 || m[2].length + (m[3] || "").length > 40) return null;
    let c = BigInt(m[2] + (m[3] || "")) * (m[1] === "-" ? -1n : 1n),
      scale = (m[3] || "").length - Number(m[4] || 0);
    if (scale < 0) {
      c *= 10n ** BigInt(-scale);
      scale = 0;
    }
    return { c, scale };
  }
  function text(d) {
    if (!d) return "";
    const negative = d.c < 0n,
      c = String(negative ? -d.c : d.c).padStart(d.scale + 1, "0");
    const value = d.scale ? c.slice(0, -d.scale) + "." + c.slice(-d.scale) : c;
    return (negative ? "-" : "") + value.replace(/(\.\d*?)0+$/, "$1").replace(/[.]$/, "");
  }
  function numeric(v) {
    return text(decimal(v));
  }
  function compare(a, b) {
    const x = decimal(a),
      y = decimal(b);
    if (!x || !y) return null;
    const scale = Math.max(x.scale, y.scale),
      v = x.c * 10n ** BigInt(scale - x.scale) - y.c * 10n ** BigInt(scale - y.scale);
    return v < 0n ? -1 : v > 0n ? 1 : 0;
  }
  function convert(value, from, to) {
    const a = unit(from),
      b = unit(to),
      d = decimal(value);
    if (!a || !b || !d || d.c < 0n) return null;
    if (a === b || (a !== "%" && b !== "%")) return text(d);
    d.scale += a === "%" ? -4 : 4;
    if (d.scale < 0) {
      d.c *= 10n ** BigInt(-d.scale);
      d.scale = 0;
    }
    return text(d);
  }
  function evaluate(rows, values) {
    let missing = !rows.length,
      failed = false;
    const results = rows.map((r) => {
      const key = r.ma_dac_tinh || r.element,
        v = numeric(values[key]),
        min = r.lsl ?? r.min,
        max = r.usl ?? r.max;
      const required = r.bat_buoc ?? r.required ?? true;
      let result = "Chưa nhận diện";
      if (!v) {
        if (String(values[key] ?? "").trim()) {
          result = "Không hợp lệ";
          missing = true;
        } else if (required) missing = true;
      } else if (compare(v, "0") < 0 || (unit(r.don_vi || r.unit) === "%" && compare(v, "100") > 0)) {
        result = "Không hợp lệ";
        missing = true;
      } else if (
        (min != null && min !== "" && compare(v, min) < 0) ||
        (max != null && max !== "" && compare(v, max) > 0)
      ) {
        result = "NG";
        failed = true;
      } else if ((min == null || min === "") && (max == null || max === "")) {
        result = "Thiếu tiêu chuẩn";
        missing = true;
      } else result = "OK";
      return { ...r, element: key, value: v, result };
    });
    return { results, conclusion: failed ? "NG" : missing ? "" : "OK" };
  }
  const actual = (v) =>
    !limit(v) &&
    /^(result|actual|measured|concentration|content|average|mean|ham luong|ket qua|gia tri do)(\b|\s*\()/i.test(
      plain(v),
    );
  const limit = (v) =>
    /\b(min(?:imum)?|max(?:imum)?|lower|upper|specification|standard|limit|nominal|tolerance|tieu chuan|gioi han|nguong)\b/i.test(
      plain(v),
    );
  function measured(raw) {
    const source = String(raw ?? "").trim(),
      u = unit(source);
    return { value: numeric(source.replace(/\s*(?:wt[.]?\s*%|mass\s*%|%|ppm|mg\s*\/\s*kg)\s*$/i, "")), unit: u };
  }
  function parse(sheets) {
    const out = [];
    for (const [sheetIndex, sheet] of (sheets || []).entries()) {
      const rows = (sheet.rows || []).map((row) => {
        if (row.length !== 1) return row;
        const m = /^([A-Za-z]{1,2})\s+([+]?[0-9]+(?:[.,][0-9]+)?(?:[eE][+-]?[0-9]+)?)(?:\s*(%|ppm|mg\/kg))?$/.exec(
          String(row[0]).trim(),
        );
        return m ? [m[1], m[2], m[3] || ""] : row;
      });
      const headerUnits = [
        ...new Set(
          rows
            .slice(0, 8)
            .filter(
              (row) =>
                !row.some(element) &&
                !row.some((v) => measured(v).value !== "") &&
                row.some((v) =>
                  /mass|wt|unit|ham luong|concentration|composition|content|ket qua|result/i.test(String(v)),
                ),
            )
            .flat()
            .map(unit)
            .filter(Boolean),
        ),
      ];
      const globalUnit = unit(sheet.unit || "") || (headerUnits.length === 1 ? headerUnits[0] : "");
      let actualCol = null,
        headerWidth = 0,
        limitsOnlyHeader = false;
      const add = (e, value, u, row, col) => {
        // OCR "04" could mean 0.4 with a lost decimal point. Never turn it into a fabricated 4.
        if (sheet.method === "ocr" && /^0\d+$/.test(String(value).trim())) return;
        const measurement = measured(value),
          normalized = measurement.value;
        // Comparators (<LOD etc.) and "balance" aren't exact measured concentrations.
        if (!normalized || compare(normalized, "0") < 0) return;
        const confidence =
          sheet.method === "ocr" ? Number(sheet.lines?.[row]?.confidence ?? sheet.confidence?.[row]) : null;
        out.push({
          element: e,
          value: normalized,
          unit: measurement.unit || u,
          source: sheet.name || "Trang " + (sheetIndex + 1),
          sheet: sheetIndex,
          row: row + 1,
          column: col + 1,
          confidence: Number.isFinite(confidence) ? confidence : null,
          requiresReview: confidence !== null && Number.isFinite(confidence) && confidence < 90,
          samples: [{ value: Number(normalized) }],
        });
      };
      for (let i = 0; i < rows.length; i++) {
        const row = rows[i].map((v) => (v == null ? "" : String(v).trim()));
        const elements = row.map(element),
          ec = elements.filter(Boolean).length;
        if (ec >= 2) {
          const mapped = [],
            columnUnits = [];
          for (let j = i + 1; j < rows.length && j <= i + 12; j++) {
            if (rows[j].filter((v) => element(v)).length >= 2) break;
            const line = rows[j].map((v) => String(v ?? "")),
              label = line.filter((v) => !numeric(v)).join(" ");
            if (!line.some((v) => measured(v).value !== "") && line.some((v) => /unit|don vi/i.test(plain(v))))
              elements.forEach((e, k) => {
                if (e && unit(line[k])) columnUnits[k] = unit(line[k]);
              });
            if (limit(label)) continue;
            if (elements.some((e, k) => e && numeric(line[k]))) mapped.push({ line, j, preferred: actual(label) });
          }
          const preferred = mapped.filter((x) => x.preferred);
          for (const { line, j } of preferred.length ? preferred : limitsOnlyHeader ? [] : mapped)
            elements.forEach((e, k) => {
              if (e) add(e, line[k], unit(row[k]) || columnUnits[k] || globalUnit, j, k);
            });
          continue;
        }
        const h = row.findIndex(actual);
        if (h >= 0 && !elements.some(Boolean)) {
          actualCol = h;
          headerWidth = row.length;
          limitsOnlyHeader = false;
          continue;
        }
        if (!elements.some(Boolean) && row.some(limit)) {
          actualCol = null;
          limitsOnlyHeader = true;
          continue;
        }
        const k = elements.findIndex(Boolean);
        if (k < 0 || limit(row.join(" ")) || limitsOnlyHeader) continue;
        const explicitUnit = row.map(unit).find(Boolean) || globalUnit;
        if (actualCol != null && actualCol !== k && row.length >= Math.min(headerWidth, actualCol + 1))
          add(elements[k], row[actualCol], explicitUnit, i, actualCol);
        else {
          const values = row.map((v, c) => ({ v, c })).filter((x) => x.c !== k && measured(x.v).value !== "");
          if (values.length === 1) add(elements[k], values[0].v, explicitUnit, i, values[0].c);
        }
      }
    }
    // A PDF can contain both horizontal/vertical renderings. Exact duplicate observations aren't conflicts.
    return out.filter(
      (x, i) =>
        out.findIndex(
          (y) =>
            y.element === x.element &&
            y.value === x.value &&
            y.unit === x.unit &&
            y.sheet === x.sheet &&
            y.row === x.row,
        ) === i,
    );
  }
  function matched(rows, candidates, overrideUnit = "") {
    const values = {},
      choices = {},
      missing = [];
    for (const r of rows) {
      const key = r.ma_dac_tinh || r.element,
        options = [];
      for (const c of candidates.filter((c) => c.element === key)) {
        const v = convert(c.value, c.unit || overrideUnit, r.don_vi || r.unit);
        if (v != null && !options.some((x) => x.value === v)) options.push({ ...c, value: v });
      }
      choices[key] = options;
      if (options.length === 1 && !options[0].requiresReview) values[key] = options[0].value;
      else missing.push(key);
    }
    return { values, choices, missing };
  }
  const api = { ELEMENTS, element, unit, numeric, compare, convert, evaluate, parse, matched };
  root.IqcChemistry = api;
  if (typeof module !== "undefined") module.exports = api;
})(globalThis);
