/* ============================================================================
 * shared/doc-viewer.js — T115. Bộ xem tài liệu view-only (PDF + ảnh) có thanh
 * công cụ: phóng to / thu nhỏ, % zoom, khớp chiều rộng / khớp trang, kéo (pan),
 * zoom vùng (kéo khung chữ nhật), xoay 90°, chuyển trang, toàn màn hình.
 *
 * Vẽ lên <canvas> bằng PDF.js (không dùng trình xem PDF của trình duyệt) →
 * không có nút tải/in của trình duyệt, không lộ signed URL trong DOM.
 *
 * Dùng:
 *   const v = DocViewer.mount(wrapEl, toolbarEl);   // 1 lần
 *   await v.open(blob, watermarkHtml);              // blob PDF hoặc ảnh
 *   v.clear(html);                                  // về trạng thái trống
 *
 * Thao tác: kéo chuột / 1 ngón = pan; Ctrl + lăn chuột / chụm 2 ngón = zoom
 * tại vị trí con trỏ; phím + − 0 (100%) W (khớp rộng) F (khớp trang) R (xoay)
 * PageUp/PageDown khi vùng xem đang được chọn.
 * ========================================================================== */
(function () {
  const PDFJS_BASE = 'https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/';   // jsdelivr có đủ cmaps (font Nhật/Việt)
  const MIN_SCALE = 0.1, MAX_SCALE = 8;
  const MAX_CANVAS_PX = 24e6;          // giới hạn điểm ảnh 1 canvas (bộ nhớ)
  const PAD = 12;                      // khoảng đệm quanh trang (khớp CSS)

  let pdfjsPromise = null;
  function loadPdfJs() {
    if (window.pdfjsLib) return Promise.resolve(window.pdfjsLib);
    if (pdfjsPromise) return pdfjsPromise;
    pdfjsPromise = new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = PDFJS_BASE + 'build/pdf.min.js';
      s.onload = () => {
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = PDFJS_BASE + 'build/pdf.worker.min.js';
        resolve(window.pdfjsLib);
      };
      s.onerror = () => { pdfjsPromise = null; reject(new Error('Không tải được thư viện PDF.js')); };
      document.head.appendChild(s);
    });
    return pdfjsPromise;
  }

  const CSS = `
.dv-scroll{position:absolute;inset:0;overflow:auto;scrollbar-gutter:stable;cursor:grab;touch-action:none;outline:none}
.dv-scroll.dragging{cursor:grabbing}
.dv-scroll.mode-zoom{cursor:zoom-in}
.dv-pages{box-sizing:border-box;display:flex;flex-direction:column;align-items:center;gap:${PAD}px;padding:${PAD}px;width:max-content;min-width:100%}
.dv-page{position:relative;background:#fff;box-shadow:0 2px 10px rgba(0,0,0,.5);flex:none}
.dv-page canvas{position:absolute;inset:0;width:100%;height:100%;display:block}
.dv-rect{position:absolute;border:2px dashed #38BDF8;background:rgba(56,189,248,.12);pointer-events:none;z-index:6;display:none}
.dv-tools{display:none;align-items:center;gap:4px;flex-wrap:wrap;margin-left:auto}
.dv-tools.on{display:flex}
.dv-tools button{min-width:30px;height:28px;padding:0 8px;border:1px solid var(--border-strong,#B8C1CC);background:#fff;color:var(--text,#0F172A);border-radius:5px;font-family:inherit;font-size:12px;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;gap:4px}
.dv-tools button:hover:not(:disabled){background:var(--bg-sunken,#F5F7FA)}
.dv-tools button:disabled{opacity:.4;cursor:not-allowed}
.dv-tools button.active,.dv-tools button.active:hover:not(:disabled){background:var(--accent,#0F5FA5);border-color:var(--accent,#0F5FA5);color:#fff}
.dv-tools .sep{width:1px;height:20px;background:var(--border,#D9DFE5);margin:0 3px}
.dv-tools .pct{width:58px;height:28px;border:1px solid var(--border-strong,#B8C1CC);border-radius:5px;text-align:center;font-family:'JetBrains Mono',monospace;font-size:11.5px}
.dv-tools .pg{display:inline-flex;align-items:center;gap:4px;font-size:11.5px;color:var(--text-muted,#64748B)}
.dv-tools .pg input{width:40px;height:28px;border:1px solid var(--border-strong,#B8C1CC);border-radius:5px;text-align:center;font-family:'JetBrains Mono',monospace;font-size:11.5px}
`;
  function injectCss() {
    if (document.getElementById('dv-css')) return;
    const st = document.createElement('style');
    st.id = 'dv-css';
    st.textContent = CSS;
    document.head.appendChild(st);
  }

  function mount(wrap, toolbar) {
    injectCss();
    toolbar.classList.add('dv-tools');
    toolbar.innerHTML = `
      <span class="pg" data-pg-box><button type="button" data-act="prev" title="Trang trước (PageUp)">‹</button>
        <input type="text" data-pg inputmode="numeric"> / <span data-pg-total>1</span>
        <button type="button" data-act="next" title="Trang sau (PageDown)">›</button></span>
      <span class="sep" data-pg-box></span>
      <button type="button" data-act="out" title="Thu nhỏ (−)">−</button>
      <input type="text" class="pct" data-pct title="Mức zoom — gõ số rồi Enter">
      <button type="button" data-act="in" title="Phóng to (+)">+</button>
      <button type="button" data-act="fitw" title="Khớp chiều rộng (W)">↔ Rộng</button>
      <button type="button" data-act="fitp" title="Khớp cả trang (F)">⤢ Trang</button>
      <span class="sep"></span>
      <button type="button" data-act="pan" title="Kéo để di chuyển (pan)">✋ Kéo</button>
      <button type="button" data-act="zrect" title="Kéo khung để phóng to vùng đó">⬚ Zoom vùng</button>
      <button type="button" data-act="rot" title="Xoay 90° (R)">⟳ Xoay</button>
      <button type="button" data-act="fs" title="Toàn màn hình">⛶</button>`;

    const v = {
      wrap, toolbar, scroll: null, pagesEl: null, rect: null,
      pdf: null, img: null, pages: [], scale: 1, rotation: 0, mode: 'pan',
      fit: 'page', renderTimer: null, observer: null, token: 0,
    };
    const $ = sel => toolbar.querySelector(sel);

    // ── kích thước trang theo scale/rotation hiện tại ─────────────────────
    function baseSize(p) {
      const rot = (v.rotation + p.rot0) % 180 !== 0;
      return rot ? { w: p.h, h: p.w } : { w: p.w, h: p.h };
    }
    function layout() {
      v.pages.forEach(p => {
        const b = baseSize(p);
        p.el.style.width = Math.round(b.w * v.scale) + 'px';
        p.el.style.height = Math.round(b.h * v.scale) + 'px';
        p.dirty = true;
      });
      $('[data-pct]').value = Math.round(v.scale * 100) + '%';
      $('[data-act="out"]').disabled = v.scale <= MIN_SCALE + 1e-6;
      $('[data-act="in"]').disabled = v.scale >= MAX_SCALE - 1e-6;
      $('[data-act="fitw"]').classList.toggle('active', v.fit === 'width');
      $('[data-act="fitp"]').classList.toggle('active', v.fit === 'page');
      scheduleRender();
    }

    function scheduleRender() {
      clearTimeout(v.renderTimer);
      v.renderTimer = setTimeout(renderVisible, 120);
    }
    function isVisible(p) {
      const r = p.el.getBoundingClientRect(), s = v.scroll.getBoundingClientRect();
      return r.bottom > s.top - 300 && r.top < s.bottom + 300 && r.right > s.left - 300 && r.left < s.right + 300;
    }
    function renderVisible() {
      v.pages.forEach(p => { if (p.dirty && isVisible(p)) renderPage(p); });
    }

    async function renderPage(p) {
      p.dirty = false;
      const token = v.token;
      const b = baseSize(p);
      const cssW = b.w * v.scale, cssH = b.h * v.scale;
      let dpr = window.devicePixelRatio || 1;
      if (cssW * cssH * dpr * dpr > MAX_CANVAS_PX) dpr = Math.sqrt(MAX_CANVAS_PX / (cssW * cssH));
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.floor(cssW * dpr));
      canvas.height = Math.max(1, Math.floor(cssH * dpr));
      const ctx = canvas.getContext('2d');
      try {
        if (v.pdf) {
          if (p.task) { try { p.task.cancel(); } catch (_) {} }
          const page = await v.pdf.getPage(p.no);
          if (token !== v.token) return;
          const vp = page.getViewport({ scale: v.scale * dpr, rotation: (p.rot0 + v.rotation) % 360 });
          p.task = page.render({ canvasContext: ctx, viewport: vp });
          await p.task.promise;
          p.task = null;
        } else if (v.img) {
          ctx.fillStyle = '#fff';
          ctx.fillRect(0, 0, canvas.width, canvas.height);
          ctx.translate(canvas.width / 2, canvas.height / 2);
          ctx.rotate(v.rotation * Math.PI / 180);
          const iw = p.w * v.scale * dpr, ih = p.h * v.scale * dpr;
          ctx.imageSmoothingQuality = 'high';
          ctx.drawImage(v.img, -iw / 2, -ih / 2, iw, ih);
        }
      } catch (e) {
        if (e && e.name === 'RenderingCancelledException') return;
        throw e;
      }
      if (token !== v.token) return;
      // Thay canvas cũ sau khi vẽ xong → zoom không bị nháy trắng.
      p.el.querySelectorAll('canvas').forEach(c => c.remove());
      p.el.appendChild(canvas);
    }

    // ── zoom ─────────────────────────────────────────────────────────────
    function clampScale(s) { return Math.min(MAX_SCALE, Math.max(MIN_SCALE, s)); }
    // Zoom giữ nguyên điểm nội dung dưới (clientX, clientY); mặc định = tâm vùng xem.
    function zoomTo(newScale, clientX, clientY) {
      newScale = clampScale(newScale);
      if (!v.pages.length || Math.abs(newScale - v.scale) < 1e-6) return;
      const s = v.scroll, r = s.getBoundingClientRect();
      const ax = clientX ?? r.left + s.clientWidth / 2;
      const ay = clientY ?? r.top + s.clientHeight / 2;
      const p = v.pages.find(pg => { const b = pg.el.getBoundingClientRect(); return ay >= b.top && ay <= b.bottom; })
        || v.pages[currentPageIdx()];
      const b0 = p.el.getBoundingClientRect();
      const fx = (ax - b0.left) / b0.width, fy = (ay - b0.top) / b0.height;
      v.scale = newScale;
      v.fit = null;
      layout();
      const b1 = p.el.getBoundingClientRect();
      s.scrollLeft += (b1.left + fx * b1.width) - ax;
      s.scrollTop += (b1.top + fy * b1.height) - ay;
      scheduleRender();
    }
    function zoomStep(dir) {
      const steps = [0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 8];
      const cur = v.scale;
      const next = dir > 0 ? steps.find(x => x > cur + 1e-3) : [...steps].reverse().find(x => x < cur - 1e-3);
      zoomTo(next ?? (dir > 0 ? MAX_SCALE : MIN_SCALE));
    }
    function currentPageIdx() {
      const s = v.scroll.getBoundingClientRect();
      const mid = s.top + Math.min(s.height / 3, 200);
      let best = 0;
      v.pages.forEach((p, i) => { if (p.el.getBoundingClientRect().top <= mid) best = i; });
      return best;
    }
    function fitWidth() {
      if (!v.pages.length) return;
      const avail = v.scroll.clientWidth - 2 * PAD;
      const maxW = Math.max(...v.pages.map(p => baseSize(p).w));
      v.scale = clampScale(avail / maxW);
      v.fit = 'width';
      layout();
    }
    function fitPage(keepPage) {
      if (!v.pages.length) return;
      const idx = keepPage ? currentPageIdx() : 0;
      const b = baseSize(v.pages[idx]);
      v.scale = clampScale(Math.min((v.scroll.clientWidth - 2 * PAD) / b.w, (v.scroll.clientHeight - 2 * PAD) / b.h));
      v.fit = 'page';
      layout();
      goPage(idx);
    }
    function goPage(i) {
      i = Math.max(0, Math.min(v.pages.length - 1, i));
      const p = v.pages[i];
      if (!p) return;
      v.scroll.scrollTop = p.el.offsetTop - PAD;
      updatePageBox();
    }
    function updatePageBox() {
      if (!v.pages.length) return;
      const i = currentPageIdx();
      const inp = $('[data-pg]');
      if (document.activeElement !== inp) inp.value = i + 1;
      $('[data-act="prev"]').disabled = i <= 0;
      $('[data-act="next"]').disabled = i >= v.pages.length - 1;
    }
    function setMode(m) {
      v.mode = m;
      $('[data-act="pan"]').classList.toggle('active', m === 'pan');
      $('[data-act="zrect"]').classList.toggle('active', m === 'zoom');
      if (v.scroll) v.scroll.classList.toggle('mode-zoom', m === 'zoom');
    }

    // ── thanh công cụ ────────────────────────────────────────────────────
    toolbar.addEventListener('click', e => {
      const b = e.target.closest('button[data-act]');
      if (!b || !v.pages.length) return;
      const act = b.dataset.act;
      if (act === 'in') zoomStep(1);
      else if (act === 'out') zoomStep(-1);
      else if (act === 'fitw') fitWidth();
      else if (act === 'fitp') fitPage(true);
      else if (act === 'pan') setMode('pan');
      else if (act === 'zrect') setMode(v.mode === 'zoom' ? 'pan' : 'zoom');
      else if (act === 'rot') rotate();
      else if (act === 'prev') goPage(currentPageIdx() - 1);
      else if (act === 'next') goPage(currentPageIdx() + 1);
      else if (act === 'fs') toggleFullscreen();
      if (v.scroll && act !== 'fs') v.scroll.focus({ preventScroll: true });
    });
    $('[data-pct]').addEventListener('keydown', e => {
      if (e.key !== 'Enter') return;
      const n = parseFloat(String(e.target.value).replace(/[^\d.]/g, ''));
      if (n > 0) zoomTo(n / 100); else layout();
      e.target.blur();
    });
    $('[data-pct]').addEventListener('blur', () => { $('[data-pct]').value = Math.round(v.scale * 100) + '%'; });
    $('[data-pg]').addEventListener('keydown', e => {
      if (e.key !== 'Enter') return;
      const n = parseInt(e.target.value, 10);
      if (n > 0) goPage(n - 1);
      e.target.blur();
    });

    function rotate() {
      const i = currentPageIdx();
      v.rotation = (v.rotation + 90) % 360;
      if (v.fit === 'width') fitWidth();
      else if (v.fit === 'page') { fitPage(false); goPage(i); }
      else layout();
      goPage(i);
    }
    function toggleFullscreen() {
      const host = wrap.closest('.panel') || wrap;
      if (document.fullscreenElement) document.exitFullscreen();
      else if (host.requestFullscreen) host.requestFullscreen();
    }
    document.addEventListener('fullscreenchange', () => {
      $('[data-act="fs"]').classList.toggle('active', !!document.fullscreenElement);
    });

    // Khung xem đổi kích thước (toàn màn hình, xoay máy) → giữ chế độ khớp.
    let lastW = 0, lastH = 0;
    new ResizeObserver(() => {
      if (!v.scroll || !v.pages.length) return;
      const w = v.scroll.clientWidth, h = v.scroll.clientHeight;
      if (w === lastW && h === lastH) return;
      lastW = w; lastH = h;
      if (v.fit === 'width') fitWidth();
      else if (v.fit === 'page') fitPage(true);
      else scheduleRender();
    }).observe(wrap);

    // ── pan / zoom vùng / chụm 2 ngón ───────────────────────────────────
    function wireScroll(s) {
      const pts = new Map();
      let drag = null, pinch = null;
      s.addEventListener('pointerdown', e => {
        if (e.button !== 0 && e.pointerType === 'mouse') return;
        s.setPointerCapture(e.pointerId);
        pts.set(e.pointerId, { x: e.clientX, y: e.clientY });
        if (pts.size === 2) {
          const [a, b] = [...pts.values()];
          pinch = { d: Math.hypot(a.x - b.x, a.y - b.y), scale: v.scale };
          drag = null;
          v.rect.style.display = 'none';
        } else if (pts.size === 1) {
          if (v.mode === 'zoom' && e.pointerType === 'mouse') {
            drag = { zoom: true, x: e.clientX, y: e.clientY };
          } else {
            drag = { x: e.clientX, y: e.clientY, sl: s.scrollLeft, st: s.scrollTop };
            s.classList.add('dragging');
          }
        }
      });
      s.addEventListener('pointermove', e => {
        if (!pts.has(e.pointerId)) return;
        pts.set(e.pointerId, { x: e.clientX, y: e.clientY });
        if (pinch && pts.size === 2) {
          const [a, b] = [...pts.values()];
          const d = Math.hypot(a.x - b.x, a.y - b.y);
          if (pinch.d > 0) zoomTo(pinch.scale * d / pinch.d, (a.x + b.x) / 2, (a.y + b.y) / 2);
        } else if (drag && drag.zoom) {
          const r = wrap.getBoundingClientRect();
          Object.assign(v.rect.style, {
            display: 'block',
            left: (Math.min(drag.x, e.clientX) - r.left) + 'px',
            top: (Math.min(drag.y, e.clientY) - r.top) + 'px',
            width: Math.abs(e.clientX - drag.x) + 'px',
            height: Math.abs(e.clientY - drag.y) + 'px',
          });
        } else if (drag) {
          s.scrollLeft = drag.sl - (e.clientX - drag.x);
          s.scrollTop = drag.st - (e.clientY - drag.y);
        }
      });
      const end = e => {
        if (!pts.has(e.pointerId)) return;
        pts.delete(e.pointerId);
        if (drag && drag.zoom) {
          v.rect.style.display = 'none';
          const w = Math.abs(e.clientX - drag.x), h = Math.abs(e.clientY - drag.y);
          if (w > 8 && h > 8) {
            // phóng khung đã kéo cho vừa vùng xem
            const k = Math.min(s.clientWidth / w, s.clientHeight / h);
            const cx = (drag.x + e.clientX) / 2, cy = (drag.y + e.clientY) / 2;
            zoomTo(v.scale * k, cx, cy);
            const r = s.getBoundingClientRect();
            // đưa tâm khung về giữa vùng xem
            s.scrollLeft += (cx - r.left) - s.clientWidth / 2;
            s.scrollTop += (cy - r.top) - s.clientHeight / 2;
          } else {
            zoomTo(v.scale * 1.5, e.clientX, e.clientY);   // bấm 1 lần = phóng 1.5×
          }
          setMode('pan');   // zoom vùng dùng 1 lần rồi trở về kéo
        }
        if (pts.size < 2) pinch = null;
        if (pts.size === 0) { drag = null; s.classList.remove('dragging'); }
        else if (pts.size === 1 && !drag) {
          const [p] = [...pts.values()];
          drag = { x: p.x, y: p.y, sl: s.scrollLeft, st: s.scrollTop };
        }
      };
      s.addEventListener('pointerup', end);
      s.addEventListener('pointercancel', end);
      s.addEventListener('wheel', e => {
        if (!(e.ctrlKey || e.metaKey)) return;     // lăn thường = cuộn như bình thường
        e.preventDefault();
        zoomTo(v.scale * Math.exp(-e.deltaY * 0.0015), e.clientX, e.clientY);
      }, { passive: false });
      s.addEventListener('scroll', () => { updatePageBox(); scheduleRender(); }, { passive: true });
      s.addEventListener('keydown', e => {
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        const k = e.key;
        if (k === '+' || k === '=') zoomStep(1);
        else if (k === '-' || k === '_') zoomStep(-1);
        else if (k === '0') zoomTo(1);
        else if (k === 'w' || k === 'W') fitWidth();
        else if (k === 'f' || k === 'F') fitPage(true);
        else if (k === 'r' || k === 'R') rotate();
        else if (k === 'PageDown') goPage(currentPageIdx() + 1);
        else if (k === 'PageUp') goPage(currentPageIdx() - 1);
        else return;
        e.preventDefault();
      });
    }

    function reset() {
      v.token++;
      v.pages.forEach(p => { if (p.task) { try { p.task.cancel(); } catch (_) {} } });
      if (v.pdf) { try { v.pdf.destroy(); } catch (_) {} }
      v.pdf = null; v.img = null; v.pages = [];
      v.scale = 1; v.rotation = 0; v.fit = 'page';
      toolbar.classList.remove('on');
    }

    v.clear = function (html) {
      reset();
      wrap.innerHTML = html || '';
    };

    v.open = async function (blob, overlayHtml) {
      reset();
      const token = v.token;
      const isPdf = /pdf/i.test(blob.type) || (await blob.slice(0, 5).text()) === '%PDF-';
      const pages = [];
      if (isPdf) {
        const lib = await loadPdfJs();
        const data = new Uint8Array(await blob.arrayBuffer());
        const pdf = await lib.getDocument({
          data,
          cMapUrl: PDFJS_BASE + 'cmaps/', cMapPacked: true,
          standardFontDataUrl: PDFJS_BASE + 'standard_fonts/',
        }).promise;
        if (token !== v.token) { pdf.destroy(); return; }
        v.pdf = pdf;
        for (let i = 1; i <= pdf.numPages; i++) {
          const page = await pdf.getPage(i);
          const vp = page.getViewport({ scale: 1, rotation: 0 });   // khổ chưa xoay; /Rotate của trang tính ở baseSize
          pages.push({ no: i, w: vp.width, h: vp.height, rot0: page.rotate || 0 });
        }
      } else if (/^image\//i.test(blob.type)) {
        const url = URL.createObjectURL(blob);
        const img = new Image();
        await new Promise((res, rej) => { img.onload = res; img.onerror = () => rej(new Error('Không đọc được ảnh')); img.src = url; });
        URL.revokeObjectURL(url);
        v.img = img;
        pages.push({ no: 1, w: img.naturalWidth, h: img.naturalHeight, rot0: 0 });
      } else {
        throw new Error('Định dạng file xem không hỗ trợ (' + (blob.type || 'không rõ') + ')');
      }
      if (token !== v.token) return;

      wrap.innerHTML = '<div class="dv-scroll" tabindex="0"><div class="dv-pages"></div></div><div class="dv-rect"></div>' + (overlayHtml || '');
      v.scroll = wrap.querySelector('.dv-scroll');
      v.pagesEl = wrap.querySelector('.dv-pages');
      v.rect = wrap.querySelector('.dv-rect');
      v.pages = pages.map(p => {
        const el = document.createElement('div');
        el.className = 'dv-page';
        v.pagesEl.appendChild(el);
        return Object.assign(p, { el, dirty: true, task: null });
      });
      wireScroll(v.scroll);
      setMode('pan');
      toolbar.querySelectorAll('[data-pg-box]').forEach(x => { x.style.display = pages.length > 1 ? '' : 'none'; });
      $('[data-pg-total]').textContent = pages.length;
      toolbar.classList.add('on');
      lastW = v.scroll.clientWidth; lastH = v.scroll.clientHeight;
      // 1 trang (bản vẽ) → khớp cả trang; nhiều trang → khớp chiều rộng.
      if (pages.length > 1) fitWidth(); else fitPage(false);
      updatePageBox();
      v.scroll.focus({ preventScroll: true });
    };

    return v;
  }

  window.DocViewer = { mount };
})();
