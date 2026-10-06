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
        cell.textContent = value == null || value === '' ? '—' : String(value); tr.append(cell);
      }
      t.append(tr);
    }
    target.append(t);
    if (!rows.length) target.append(document.createTextNode('Chưa có dữ liệu.'));
  }
  function safeUrl(url, image = false) {
    try {
      const parsed = new URL(url, location.href);
      if (['https:', 'http:', 'blob:'].includes(parsed.protocol)) return parsed.href;
      if (image && /^data:image\/(png|jpeg|jpg|gif|webp);base64,/i.test(url)) return url;
    } catch { /* invalid URL */ }
    return '';
  }
  function openDialog(dialog) {
    if(typeof dialog.showModal === 'function') { document.body.append(dialog);dialog.showModal();return; }
    const backdrop=document.createElement('div');
    backdrop.style.cssText='position:fixed;inset:0;background:rgba(15,23,42,.85);z-index:10000;display:flex;align-items:center;justify-content:center';
    dialog.style.display='block';dialog.style.position='relative';
    dialog.close=()=>{if(dialog.onclose)dialog.onclose();backdrop.remove();};
    backdrop.onclick=e=>{if(e.target===backdrop)dialog.close();};
    backdrop.append(dialog);document.body.append(backdrop);dialog.setAttribute('open','');
  }
  function photo(url, urls = [url]) {
    const gallery = [...new Set(urls.map(u => safeUrl(u, true)).filter(Boolean))];
    if (!gallery.length) return;
    let index = Math.max(0, gallery.indexOf(safeUrl(url, true)));
    const dialog = document.createElement('dialog');
    dialog.className = 'qc02-viewer';
    dialog.style.cssText = 'max-width:95vw;max-height:95vh;border:0;border-radius:8px;padding:12px';
    const close = document.createElement('button'); close.textContent = 'Đóng';
    const prev = document.createElement('button'); prev.textContent = '← Trước';
    const next = document.createElement('button'); next.textContent = 'Sau →';
    const count = document.createElement('span');
    const img = document.createElement('img'); img.alt = 'Ảnh QC';
    img.style.cssText = 'display:block;max-width:85vw;max-height:80vh;object-fit:contain';
    const update = () => { img.src = gallery[index]; count.textContent = ` ${index + 1}/${gallery.length} `; };
    prev.onclick = () => { index = (index + gallery.length - 1) % gallery.length; update(); };
    next.onclick = () => { index = (index + 1) % gallery.length; update(); };
    prev.hidden = next.hidden = gallery.length < 2;
    close.onclick = () => dialog.close();
    dialog.onclick = event => { if (event.target === dialog) dialog.close(); };
    dialog.onkeydown = event => {
      if (event.key === 'ArrowLeft') prev.click();
      if (event.key === 'ArrowRight') next.click();
    };
    dialog.onclose = () => dialog.remove();
    dialog.append(close, prev, count, next, img); update(); openDialog(dialog); close.focus();
  }
  function pdf(url) {
    const src = safeUrl(url);
    if (!src) return;
    const dialog = document.createElement('dialog'); dialog.className = 'qc02-viewer';
    dialog.style.cssText = 'width:94vw;height:90vh;border:0;padding:12px;border-radius:8px';
    const close = document.createElement('button'); close.textContent = 'Đóng'; close.onclick = () => dialog.close();
    const frame = document.createElement('iframe'); frame.title = 'Tiêu chuẩn kiểm tra PDF'; frame.src = src;
    frame.style.cssText = 'width:100%;height:calc(100% - 40px);border:0;display:block';
    dialog.onclick = e => { if (e.target === dialog) dialog.close(); };
    dialog.onclose = () => dialog.remove(); dialog.append(close, frame); openDialog(dialog);close.focus();
  }
  const style = document.createElement('style');
  style.textContent = '.qc02-viewer::backdrop{background:rgba(15,23,42,.85)}.qc02-viewer button{margin:4px;padding:8px 12px;cursor:pointer}img[data-qc-photo],.img-thumb img,.photo-thumb img{cursor:zoom-in}';
  document.head.append(style);
  document.addEventListener('click', event => {
    const link = event.target.closest('[data-qc-photo],.photo-thumb img,.img-thumb img');
    if (link) {
      event.preventDefault(); event.stopImmediatePropagation();
      const group = link.closest('[data-qc-gallery],.img-gallery,.ds-row-img,.photo-grid,td') || link.parentElement;
      const urls = [...group.querySelectorAll('[data-qc-photo],.photo-thumb img,.img-thumb img')].map(el => el.href || el.src);
      photo(link.href || link.src, urls);
    }
  }, true);
  function machineNote(note, checked) {
    const clean = String(note || '').replace(/\n?\[QC02_MACHINE_CHECK:(?:0|1)\]/g, '');
    return clean + '\n[QC02_MACHINE_CHECK:' + (checked ? '1' : '0') + ']';
  }
  function machineChecked(note) {
    const match = String(note || '').match(/\[QC02_MACHINE_CHECK:(0|1)\]/);
    return match ? match[1] === '1' : null;
  }
  return { overdue, summarize, table, photo, pdf, safeUrl, machineNote, machineChecked };
})();
