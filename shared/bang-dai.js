/**
 * ============================================================================
 * bang-dai.js — T189: bảng dài (nhiều dòng, phải kéo xuống mới xem hết) trên MỌI
 * trang MES: cố định dòng tiêu đề + nút lọc ▾ từng cột kiểu AutoFilter của Excel.
 * navbar.js tự nạp file này, trang không cần sửa gì.
 *
 * Bảng được áp dụng khi: đang hiện, có dòng tiêu đề (<thead> hoặc dòng đầu toàn
 * <th>), cao hơn phần màn hình còn lại, màn hình rộng >= 700px, không nằm trong
 * hộp thoại / phần tử position:fixed, không lồng trong bảng khác.
 *
 * - Cố định tiêu đề: bảng được đặt trong 1 khung cuộn cao vừa phần màn hình còn
 *   lại dưới nó → bộ lọc sẵn có của trang (ở trên bảng) luôn hiện, chỉ thân bảng
 *   cuộn; <thead> dính ở đầu khung. Nếu phía trên bảng quá nhiều nội dung thì
 *   khung cao bằng màn hình trừ thanh menu. Bảng đã tự làm tiêu đề dính thì bỏ qua.
 * - Nút lọc ▾ ở dòng tiêu đề cuối: tìm, chọn/bỏ giá trị, "Bỏ lọc". Ẩn dòng bằng
 *   class bd-an (không xoá dữ liệu); trang vẽ lại bảng thì lọc tự áp lại theo tên cột.
 *   Bảng có ô gộp dòng (rowspan) trong thân bảng thì chỉ cố định tiêu đề, không lọc.
 *
 * Tắt cho 1 bảng / 1 vùng: thêm thuộc tính data-bang-dai="tat".
 * ============================================================================
 */
(function () {
  if (window.BangDai) return;
  const MIN_W = 700, MIN_DONG_LOC = 8, CAO_TOI_THIEU = 300;
  const boLocTheoBang = new Map();   // chữ ký tiêu đề → { [cột]: Set giá trị được chọn }

  function css(){
    if (document.getElementById('bd-css')) return;
    const st = document.createElement('style');
    st.id = 'bd-css';
    st.textContent =
      '.bd-khung{overflow:auto;position:relative}' +
      '.bd-khung>table>thead{position:sticky;top:0;z-index:3}' +
      '.bd-khung>table>thead>tr:last-child>th{box-shadow:inset 0 -1px 0 rgba(15,23,42,.22)}' +
      '.bd-an{display:none!important}' +
      '.bd-th-loc{padding-right:22px!important}' +
      '.bd-th-tuongdoi{position:relative}' +
      '.bd-nut{position:absolute;right:3px;top:50%;transform:translateY(-50%);width:17px;height:17px;padding:0;border:1px solid transparent;' +
        'border-radius:4px;background:transparent;cursor:pointer;color:inherit;opacity:.55;line-height:15px;font-size:10px;font-family:inherit}' +
      '.bd-nut::before{content:"\\25BE"}' +
      '.bd-nut:hover{opacity:1;border-color:currentColor}' +
      '.bd-nut.dang-loc{opacity:1;background:#2563EB;color:#fff;border-color:#2563EB}' +
      '.bd-nut.dang-loc::before{content:"\\29E9"}' +
      '.bd-pop{position:absolute;z-index:100001;background:#fff;color:#0F172A;border:1px solid #CBD5E1;border-radius:8px;' +
        'box-shadow:0 10px 28px rgba(15,23,42,.22);width:250px;font:13px/1.35 system-ui,-apple-system,"Segoe UI",sans-serif;text-align:left;' +
        'font-weight:400;text-transform:none;letter-spacing:normal}' +
      '.bd-pop .bd-tim{display:block;width:calc(100% - 16px);margin:8px;padding:6px 8px;border:1px solid #CBD5E1;border-radius:6px;font:inherit;box-sizing:border-box}' +
      '.bd-pop .bd-ds{max-height:260px;overflow:auto;border-top:1px solid #E2E8F0;border-bottom:1px solid #E2E8F0;padding:4px 0}' +
      '.bd-pop label{display:flex;gap:7px;align-items:center;padding:3px 10px;cursor:pointer;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
      '.bd-pop label:hover{background:#F1F5F9}' +
      '.bd-pop label span{overflow:hidden;text-overflow:ellipsis;flex:1}' +
      '.bd-pop label small{color:#64748B}' +
      '.bd-pop .bd-tat{font-weight:700}' +
      '.bd-pop .bd-act{display:flex;gap:6px;justify-content:flex-end;padding:8px}' +
      '.bd-pop .bd-act button{border:1px solid #CBD5E1;background:#fff;border-radius:6px;padding:5px 10px;font:inherit;font-weight:600;cursor:pointer;color:#0F172A}' +
      '.bd-pop .bd-act .ok{background:#0F5FA5;border-color:#0F5FA5;color:#fff}' +
      '@media print{.bd-khung{max-height:none!important;overflow:visible!important}.bd-nut{display:none}}';
    document.head.appendChild(st);
  }

  // ── Cấu trúc bảng ───────────────────────────────────────────────────────────
  function dongTieuDe(tb){
    if (tb.tHead && tb.tHead.rows.length) return tb.tHead.rows[tb.tHead.rows.length - 1];
    const r = tb.rows[0];
    if (r && r.cells.length && [...r.cells].every(c => c.tagName === 'TH')) return r;
    return null;
  }
  function dongDuLieu(tb, hdr){
    const out = [];
    for (const b of tb.tBodies) for (const r of b.rows) if (r !== hdr) out.push(r);
    return out;
  }
  // Ô theo vị trí cột logic (cộng dồn colspan).
  function oTaiCot(r, cot){
    let i = 0;
    for (const c of r.cells) { const n = c.colSpan || 1; if (cot >= i && cot < i + n) return n === 1 ? c : null; i += n; }
    return null;
  }
  function soCot(r){ let n = 0; for (const c of r.cells) n += c.colSpan || 1; return n; }
  function giaTri(c){
    if (!c) return '';
    const f = c.querySelector('input:not([type=checkbox]):not([type=hidden]),select,textarea');
    if (f) return (f.tagName === 'SELECT' ? (f.options[f.selectedIndex] || {}).text || '' : f.value || '').trim();
    return (c.textContent || '').replace(/\s+/g, ' ').trim();
  }
  function chuKy(hdr){ return [...hdr.cells].map(c => (c.textContent || '').replace(/\s+/g, ' ').trim()).join('|'); }

  function boQua(tb){
    if (tb.closest('[data-bang-dai="tat"],dialog,[role="dialog"],.modal,.modal-mask,.knvd-mask,.bd-pop')) return true;
    if (tb.parentElement && tb.parentElement.closest('table')) return true;
    for (let e = tb.parentElement; e && e !== document.body; e = e.parentElement) {
      if (getComputedStyle(e).position === 'fixed') return true;
    }
    return false;
  }

  // ── Khung cuộn + tiêu đề dính ───────────────────────────────────────────────
  function navH(){
    const v = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--navbar-h'));
    return isNaN(v) ? 0 : v;
  }
  function nenCua(el){
    for (let e = el; e; e = e.parentElement) {
      const b = getComputedStyle(e).backgroundColor;
      if (b && b !== 'transparent' && !/rgba\(.*,\s*0\)$/.test(b)) return b;
    }
    return '#fff';
  }
  // Trang đã tự làm tiêu đề dính VÀ nó có tác dụng: nằm trong khung cuộn dọc thật,
  // hoặc dính theo cửa sổ với top không bị thanh menu che. Sticky trong khung chỉ cuộn
  // ngang (không giới hạn cao) thì vô tác dụng → vẫn đặt khung của bang-dai.
  function daTuDinh(tb, hdr){
    const o = [...hdr.cells].find(c => getComputedStyle(c).position === 'sticky') ||
      (tb.tHead && getComputedStyle(tb.tHead).position === 'sticky' ? tb.tHead : null);
    if (!o) return false;
    for (let e = tb.parentElement; e && e !== document.body && e !== document.documentElement; e = e.parentElement) {
      const s = getComputedStyle(e);
      if (/(auto|scroll|hidden)/.test(s.overflowY + s.overflowX)) return e.scrollHeight > e.clientHeight + 2;
    }
    return (parseFloat(getComputedStyle(o).top) || 0) >= navH();
  }
  function khungCuon(tb){
    if (tb.parentElement.classList.contains('bd-khung')) return tb.parentElement;
    // Dùng lại khung cuộn ngang sẵn có nếu nó chỉ bọc riêng bảng này.
    const p = tb.parentElement, ox = getComputedStyle(p).overflowX;
    if ((ox === 'auto' || ox === 'scroll') && p.children.length === 1 && p !== document.body) { p.classList.add('bd-khung'); return p; }
    const k = document.createElement('div');
    k.className = 'bd-khung';
    p.insertBefore(k, tb);
    k.appendChild(tb);
    return k;
  }
  // Chiều cao khung: phần màn hình còn lại dưới mép trên của khung (bộ lọc phía trên
  // vẫn hiện); quá thấp thì cao bằng màn hình trừ thanh menu.
  function caoTai(el){
    const top = el.getBoundingClientRect().top + window.scrollY;
    let cao = window.innerHeight - top - 12;
    if (cao < CAO_TOI_THIEU) cao = window.innerHeight - navH() - 20;
    return Math.max(CAO_TOI_THIEU, Math.floor(cao));
  }
  function datCao(k){
    const v = caoTai(k) + 'px';
    if (k.style.maxHeight !== v) k.style.maxHeight = v;
  }
  function codinh(tb, hdr){
    if (!tb.tHead) {   // không có <thead>: dính từng ô tiêu đề
      [...hdr.cells].forEach(c => { c.style.position = 'sticky'; c.style.top = '0'; c.style.zIndex = '3'; });
    }
    datCao(khungCuon(tb));
    const hang = tb.tHead ? [...tb.tHead.rows] : [hdr];
    hang.forEach(r => [...r.cells].forEach(c => {
      const cs = getComputedStyle(c);
      if (tb.tHead && cs.position === 'sticky' && cs.top !== '0px') c.style.top = '0';   // dính sẵn theo trang → về đầu khung
      const b = cs.backgroundColor;
      if (!b || b === 'transparent' || /rgba\(.*,\s*0\)$/.test(b)) c.style.backgroundColor = nenCua(r);
    }));
  }

  // ── Lọc ─────────────────────────────────────────────────────────────────────
  function apLoc(tb){
    const hdr = dongTieuDe(tb); if (!hdr) return;
    const loc = boLocTheoBang.get(chuKy(hdr)) || {};
    const cots = Object.keys(loc).map(Number);
    const n = soCot(hdr);
    dongDuLieu(tb, hdr).forEach(r => {
      let an = false;
      if (cots.length && soCot(r) >= Math.ceil(n / 2)) {
        an = cots.some(cot => !loc[cot].has(giaTri(oTaiCot(r, cot))));
      }
      r.classList.toggle('bd-an', an);
    });
    hdr.querySelectorAll('.bd-nut').forEach(b => b.classList.toggle('dang-loc', !!loc[b.dataset.cot]));
  }

  let popMo = null;
  function dongPop(){ if (popMo) { popMo.remove(); popMo = null; } }
  function moPop(btn, tb){
    dongPop();
    const hdr = dongTieuDe(tb), ky = chuKy(hdr), cot = +btn.dataset.cot;
    const loc = boLocTheoBang.get(ky) || {};
    // Giá trị của cột trong các dòng đang thỏa các bộ lọc CỘT KHÁC (giống Excel).
    const khac = Object.keys(loc).map(Number).filter(c => c !== cot);
    const n = soCot(hdr), dem = new Map();
    dongDuLieu(tb, hdr).forEach(r => {
      if (soCot(r) < Math.ceil(n / 2)) return;
      if (khac.some(c => !loc[c].has(giaTri(oTaiCot(r, c))))) return;
      const v = giaTri(oTaiCot(r, cot));
      dem.set(v, (dem.get(v) || 0) + 1);
    });
    const ds = [...dem.keys()].sort((a, b) => a === '' ? 1 : b === '' ? -1 : a.localeCompare(b, 'vi', { numeric: true }));
    const chon = new Set(loc[cot] ? ds.filter(v => loc[cot].has(v)) : ds);
    const esc = s => String(s).replace(/[&<>"]/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[ch]));

    const pop = document.createElement('div');
    pop.className = 'bd-pop';
    pop.innerHTML = '<input class="bd-tim" type="text" placeholder="Tìm trong cột...">' +
      '<div class="bd-ds"><label class="bd-tat"><input type="checkbox" data-tat> <span>(Chọn tất cả)</span></label>' +
      ds.map((v, i) => '<label data-v="' + esc(v.toLowerCase()) + '"><input type="checkbox" data-i="' + i + '"' + (chon.has(v) ? ' checked' : '') + '> <span>' +
        (v === '' ? '<i>(Trống)</i>' : esc(v)) + '</span><small>' + dem.get(v) + '</small></label>').join('') + '</div>' +
      '<div class="bd-act"><button type="button" data-bo>Bỏ lọc</button><button type="button" class="ok" data-ok>Lọc</button></div>';
    document.body.appendChild(pop);
    const r = btn.getBoundingClientRect();
    pop.style.top = (r.bottom + window.scrollY + 4) + 'px';
    pop.style.left = Math.max(8, Math.min(r.right + window.scrollX - 250, window.scrollX + document.documentElement.clientWidth - 258)) + 'px';
    popMo = pop;

    const tat = pop.querySelector('[data-tat]'), tim = pop.querySelector('.bd-tim');
    const hop = () => [...pop.querySelectorAll('input[data-i]')].filter(x => x.closest('label').style.display !== 'none');
    const capNhatTat = () => { const h = hop(); tat.checked = h.length > 0 && h.every(x => x.checked); };
    capNhatTat();
    tat.onchange = () => hop().forEach(x => { x.checked = tat.checked; });
    pop.querySelector('.bd-ds').addEventListener('change', e => { if (e.target.dataset.i != null) capNhatTat(); });
    tim.oninput = () => {
      const q = tim.value.trim().toLowerCase();
      pop.querySelectorAll('label[data-v]').forEach(l => { l.style.display = !q || l.dataset.v.includes(q) ? '' : 'none'; });
      capNhatTat();
    };
    const luu = s => {
      const m = Object.assign({}, boLocTheoBang.get(ky) || {});
      if (s) m[cot] = s; else delete m[cot];
      if (Object.keys(m).length) boLocTheoBang.set(ky, m); else boLocTheoBang.delete(ky);
      apLoc(tb); dongPop();
    };
    pop.querySelector('[data-bo]').onclick = () => luu(null);
    pop.querySelector('[data-ok]').onclick = () => {
      // Đang tìm: chỉ lấy giá trị khớp ô tìm (như Excel); không tìm: lấy các ô đã tích.
      const q = tim.value.trim();
      const s = new Set([...pop.querySelectorAll('input[data-i]')]
        .filter(x => x.checked && (!q || x.closest('label').style.display !== 'none')).map(x => ds[+x.dataset.i]));
      luu(s.size === ds.length && !q ? null : s);
    };
    tim.onkeydown = e => { if (e.key === 'Enter') pop.querySelector('[data-ok]').click(); };
    setTimeout(() => tim.focus(), 0);
  }
  document.addEventListener('mousedown', e => {
    if (popMo && !popMo.contains(e.target) && !e.target.closest('.bd-nut')) dongPop();
  }, true);
  document.addEventListener('keydown', e => { if (e.key === 'Escape') dongPop(); });

  function ganNutLoc(tb, hdr){
    if (dongDuLieu(tb, hdr).some(r => [...r.cells].some(c => (c.rowSpan || 1) > 1))) return;
    let cot = 0;
    [...hdr.cells].forEach(c => {
      const n = c.colSpan || 1;
      const ten = (c.textContent || '').trim();
      if (n === 1 && ten && !c.querySelector('.bd-nut,input,select,button')) {
        const b = document.createElement('button');
        b.type = 'button'; b.className = 'bd-nut'; b.dataset.cot = cot; b.title = 'Lọc cột "' + ten + '"';
        b.addEventListener('click', e => { e.stopPropagation(); e.preventDefault(); popMo && popMo._nut === b ? dongPop() : (moPop(b, tb), popMo._nut = b); });
        c.classList.add('bd-th-loc');
        // Ô đã sticky/absolute (trang tự cố định) thì giữ nguyên, nút vẫn bám theo ô.
        if (getComputedStyle(c).position === 'static') c.classList.add('bd-th-tuongdoi');
        c.appendChild(b);
      }
      cot += n;
    });
  }

  // ── Quét trang ──────────────────────────────────────────────────────────────
  function quet(){
    if (window.innerWidth < MIN_W) return;
    document.querySelectorAll('table').forEach(tb => {
      if (!tb.offsetParent || boQua(tb)) return;
      const hdr = dongTieuDe(tb); if (!hdr) return;
      if (tb.parentElement.classList.contains('bd-khung')) datCao(tb.parentElement);
      else {
        if (tb.offsetHeight <= caoTai(tb)) return;   // vừa màn hình, không cần
        if (!daTuDinh(tb, hdr)) codinh(tb, hdr);
      }
      if (dongDuLieu(tb, hdr).length >= MIN_DONG_LOC && !hdr.querySelector('.bd-nut')) ganNutLoc(tb, hdr);
      if (boLocTheoBang.has(chuKy(hdr))) apLoc(tb);
    });
  }
  let hen = 0;
  function henQuet(){ if (hen) return; hen = setTimeout(() => { hen = 0; requestAnimationFrame(quet); }, 200); }

  function batDau(){
    css();
    quet();
    new MutationObserver(ms => {
      if (ms.every(m => [...m.addedNodes, ...m.removedNodes].every(n => n.nodeType !== 1 || n.classList && (n.classList.contains('bd-pop') || n.classList.contains('bd-nut'))))) return;
      henQuet();
    }).observe(document.body, { childList: true, subtree: true });
    window.addEventListener('resize', henQuet);
    window.addEventListener('load', henQuet);
    // Chuyển tab / mở rộng vùng thường chỉ đổi thuộc tính hidden/class (không đổi cây DOM).
    document.addEventListener('click', e => { if (!e.target.closest('.bd-pop,.bd-nut')) henQuet(); }, true);
  }
  window.BangDai = { quet: henQuet };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', batDau); else batDau();
})();
