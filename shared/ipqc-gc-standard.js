/* Machining standard semantics. Legacy magnitudes remain unchanged in storage. */
(function (root) {
  function decimal(value) {
    const text = String(value ?? "")
      .trim()
      .replace(",", ".");
    const m = /^([+-]?)(\d+(?:\.\d*)?|\.\d+)(?:e([+-]?\d+))?$/i.exec(text);
    if (!m || m[2].length > 80 || Math.abs(Number(m[3] || 0)) > 80) return null;
    const [whole, fraction = ""] = m[2].split(".");
    let scale = fraction.length - Number(m[3] || 0),
      n = BigInt((whole || "0") + fraction) * (m[1] === "-" ? -1n : 1n);
    if (scale < 0) {
      n *= 10n ** BigInt(-scale);
      scale = 0;
    }
    return { n, scale };
  }
  function textDecimal({ n, scale }) {
    const sign = n < 0n ? "-" : "";
    let digits = (n < 0n ? -n : n).toString().padStart(scale + 1, "0");
    if (scale)
      digits = (digits.slice(0, -scale) + "." + digits.slice(-scale)).replace(/0+$/, "").replace(/\.$/, "");
    return sign + digits;
  }
  function normalized(value) {
    const v = decimal(value);
    return v ? textDecimal(v) : null;
  }
  function add(a, b) {
    const x = decimal(a),
      y = decimal(b);
    if (!x || !y) return null;
    const scale = Math.max(x.scale, y.scale);
    return textDecimal({
      n: x.n * 10n ** BigInt(scale - x.scale) + y.n * 10n ** BigInt(scale - y.scale),
      scale,
    });
  }
  function compare(a, b) {
    const x = decimal(a),
      y = decimal(b);
    if (!x || !y) return null;
    const scale = Math.max(x.scale, y.scale),
      d = x.n * 10n ** BigInt(scale - x.scale) - y.n * 10n ** BigInt(scale - y.scale);
    return d < 0n ? -1 : d > 0n ? 1 : 0;
  }
  function signed(value) {
    const n = normalized(value);
    return n == null ? "—" : compare(n, "0") > 0 ? "+" + n : n;
  }
  function toSigned(row) {
    if (row.dung_sai_co_dau === true) return { ...row };
    const upper = normalized(row.dung_sai_tren),
      lower = normalized(row.dung_sai_duoi);
    return {
      ...row,
      dung_sai_tren: upper == null ? null : upper.replace(/^\-/, ""),
      dung_sai_duoi: lower == null ? null : compare(lower, "0") === 0 ? "0" : "-" + lower.replace(/^\-/, ""),
      dung_sai_co_dau: true,
    };
  }
  function bounds(row) {
    const r = toSigned(row);
    return {
      lsl: normalized(r.lsl) ?? add(r.danh_nghia, r.dung_sai_duoi),
      usl: normalized(r.usl) ?? add(r.danh_nghia, r.dung_sai_tren),
    };
  }
  function numericBounds(row) {
    const b = bounds(row);
    return { lsl: b.lsl == null ? null : Number(b.lsl), usl: b.usl == null ? null : Number(b.usl) };
  }
  function dimension(row) {
    const r = toSigned(row);
    return (
      (normalized(r.danh_nghia) ?? "—") + " (" + signed(r.dung_sai_tren) + "/" + signed(r.dung_sai_duoi) + ")"
    );
  }
  function validate(row) {
    if (row.kieu !== "so") return "";
    for (const key of ["danh_nghia", "dung_sai_tren", "dung_sai_duoi", "lsl", "usl"])
      if (String(row[key] ?? "").trim() !== "" && normalized(row[key]) == null)
        return "Nhập giá trị thập phân hợp lệ.";
    const b = bounds(row);
    return compare(b.lsl, b.usl) === 1 ? "LSL không được lớn hơn USL." : "";
  }
  const api = { add, normalized, compare, signed, toSigned, bounds, numericBounds, dimension, validate };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.IpqcGcStandard = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
