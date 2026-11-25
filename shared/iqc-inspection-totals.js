/* Pure IQC quantity rules shared by entry and dashboard. */
const IqcInspectionTotals = (() => {
  function quantity(value, label) {
    const n = Number(value);
    if (!Number.isSafeInteger(n) || n < 0) throw Error(label + ' phải là số nguyên không âm.');
    return n;
  }
  function inspection(row) {
    const checked = quantity(row.checked, 'Số lượng kiểm');
    const ok = quantity(row.ok, 'Số lượng OK');
    const ng = quantity(row.ng, 'Số lượng NG');
    if (!checked || ok + ng !== checked) throw Error('Số lượng OK + NG phải bằng số lượng kiểm.');
    return { checked, ok, ng };
  }
  function summarize(lotQty, rows, options = {}) {
    const total = quantity(lotQty, 'Số lượng LOT');
    if (!total) throw Error('Số lượng LOT phải lớn hơn 0.');
    if (options.legacyUnknown) return { total, checked: null, ok: null, ng: null, remaining: null, progress: options.paused ? 'Tạm dừng / Chờ xử lý' : 'Chưa xác định' };
    const seen = new Set();
    const counts = rows.reduce((sum, row) => {
      if (row.id != null) {
        const id = String(row.id);
        if (seen.has(id)) throw Error('Lần kiểm bị trùng.');
        seen.add(id);
      }
      const value = inspection(row);
      for (const key of ['checked', 'ok', 'ng']) sum[key] += value[key];
      return sum;
    }, { checked: 0, ok: 0, ng: 0 });
    if (!Number.isSafeInteger(counts.checked) || counts.checked > total) throw Error('Số đã kiểm vượt số lượng LOT.');
    return { total, ...counts, remaining: total - counts.checked,
      progress: options.paused ? 'Tạm dừng / Chờ xử lý' : counts.checked === 0 ? 'Chưa kiểm' : counts.checked === total ? 'Đã kiểm hết' : 'Đang kiểm',
      ngPercent: counts.checked ? 100 * counts.ng / counts.checked : 0 };
  }
  return { inspection, summarize };
})();
if (typeof module !== 'undefined') module.exports = IqcInspectionTotals;
