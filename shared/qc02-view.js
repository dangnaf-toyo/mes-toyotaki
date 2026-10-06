/* Read-only QC views. Submission and database contracts remain in each page. */
const Qc02View = (() => {
  function overdue(minutes) {
    return minutes != null && Number.isFinite(Number(minutes)) && Number(minutes) > 120;
  }
  function summarize(rows) {
    const machines = new Map(), defects = new Map();
    for (const r of rows) {
      const name = r.ma_may || '(không rõ)';
      const m = machines.get(name) || { machine: name, total: 0, ok: 0, ng: 0, warning: 0 };
      m.total++;
      if (r.ket_qua === 'OK') m.ok++;
      if (r.ket_qua === 'NG') m.ng++;
      if (r.ket_qua === 'CANH_BAO') m.warning++;
      machines.set(name, m);
      const checklist = r.checklist || r.checklist_json;
      for (const item of Array.isArray(checklist) ? checklist : []) {
        if (!item || item.dat !== false) continue;
        const label = item.muc || item.muc_kiem || item.ten || item.label || 'Mục không đạt';
        defects.set(label, (defects.get(label) || 0) + 1);
      }
    }
    return { machines: [...machines.values()].sort((a, b) => a.machine.localeCompare(b.machine)),
      defects: [...defects].sort((a, b) => b[1] - a[1]) };
  }
  function table(target, headers, rows) {
    target.replaceChildren();
    const t = document.createElement('table');
    for (const values of [headers, ...rows]) {
      const tr = document.createElement('tr');
      for (const value of values) {
        const cell = document.createElement(values === headers ? 'th' : 'td');
        cell.textContent = String(value ?? '—'); tr.append(cell);
      }
      t.append(tr);
    }
    target.append(t);
    if (!rows.length) target.append(document.createTextNode('Chưa có dữ liệu.'));
  }
  function photo(url) {
    let parsed;
    try { parsed = new URL(url, location.href); } catch { return; }
    if (!['https:', 'http:'].includes(parsed.protocol)) return;
    const dialog = document.createElement('dialog');
    dialog.style.cssText = 'max-width:95vw;max-height:95vh;border:0;border-radius:8px;padding:12px';
    const close = document.createElement('button'); close.textContent = 'Đóng';
    const img = document.createElement('img'); img.alt = 'Ảnh bằng chứng IPQC'; img.src = parsed.href;
    img.style.cssText = 'display:block;max-width:85vw;max-height:80vh;object-fit:contain';
    close.onclick = () => dialog.close();
    dialog.onclose = () => dialog.remove();
    dialog.append(close, img); document.body.append(dialog); dialog.showModal(); close.focus();
  }
  document.addEventListener('click', event => {
    const link = event.target.closest('a[data-qc-photo]');
    if (link && typeof HTMLDialogElement !== 'undefined' && typeof HTMLDialogElement.prototype.showModal === 'function') {
      event.preventDefault(); photo(link.href);
    }
  });
  return { overdue, summarize, table, photo };
})();
