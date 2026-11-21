// T302/T304: chọn sự cố Đúc — chọn Loại → ô xổ xuống Vấn đề → ô xổ xuống Xử lý (điền vào ô chữ, vẫn sửa / gõ thêm được).
// Danh mục: bảng duc_su_co_mau (ma, loai[], thu_tu, van_de, xu_ly[]). Bảng lỗi / chưa chạy SQL → không hiện nút, form như cũ.
//
// SuCoMau.gan({ loai, vanDe, xuLy, vanDeText })
//   loai      : <select> loại sự cố, hoặc chuỗi loại cố định ("F1 — ...")
//   vanDe     : <textarea> vấn đề (null = không ghi vấn đề, nút vấn đề chỉ để lọc cách xử lý)
//   xuLy      : <textarea> nội dung xử lý
//   vanDeText : vấn đề có sẵn (khi vanDe = null) để tự chọn sẵn nút khớp
// B1/F1 cho chọn nhiều vấn đề. Gọi lại mỗi lần mở hộp (dùng lại khung nút đã tạo).
(function () {
  if (window.SuCoMau) return;
  let cache = null, dang = null;
  function tai() {
    if (cache) return Promise.resolve(cache);
    if (dang) return dang;
    dang = (async () => {
      try {
        const { data, error } = await sb.from('duc_su_co_mau').select('ma,loai,thu_tu,van_de,xu_ly').eq('hieu_luc', true).order('thu_tu');
        if (error) throw error;
        cache = data || [];
      } catch (e) { console.warn('duc_su_co_mau:', e.message || e); cache = []; }
      dang = null;
      return cache;
    })();
    return dang;
  }

  let css = false;
  function napCss() {
    if (css) return; css = true;
    const st = document.createElement('style');
    st.textContent =
      '.scm{margin:2px 0 6px}.scm:empty{display:none}' +
      '.scm button.scm-dd{display:flex;align-items:center;gap:6px;width:100%;padding:6px 10px;border:1px solid var(--border-strong,#CBD5E1);border-radius:6px;' +
        'background:var(--bg-panel,#fff);color:var(--text,#14181F);font-family:inherit;font-size:12px;line-height:1.35;cursor:pointer;text-align:left}' +
      '.scm button.scm-dd:hover,.scm button.scm-dd.mo{border-color:var(--accent,#2563EB)}' +
      '.scm .scm-dd-t{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' +
      '.scm .scm-dd-t.trong{color:var(--text-muted,#64748B)}' +
      '.scm .scm-dd-m{flex:none;color:var(--text-muted,#64748B);font-size:14px}' +
      '.scm .scm-ds{margin-top:2px;border:1px solid var(--accent,#2563EB);border-radius:6px;background:var(--bg-panel,#fff);max-height:240px;overflow:auto;box-shadow:0 4px 12px rgba(15,23,42,.12)}' +
      '.scm button.scm-o{display:block;width:100%;padding:7px 10px 7px 28px;border:0;border-bottom:1px solid var(--border,#E2E8F0);background:none;position:relative;' +
        'color:var(--text,#14181F);font-family:inherit;font-size:12px;line-height:1.35;cursor:pointer;text-align:left}' +
      '.scm button.scm-o:last-child{border-bottom:0}' +
      '.scm button.scm-o:hover{background:#F1F5F9}' +
      '.scm button.scm-o.on{background:#DBEAFE;color:#1E3A8A;font-weight:600}' +
      '.scm button.scm-o.on::before{content:"✓";position:absolute;left:10px}' +
      '.scm button.scm-o.khac{color:var(--text-muted,#64748B);font-style:italic}';
    document.head.appendChild(st);
  }
  // Bấm ra ngoài → đóng mọi danh sách đang xổ.
  const dsMo = new Set();
  document.addEventListener('mousedown', (e) => {
    if (e.target.closest && e.target.closest('.scm')) return;
    dsMo.forEach((st) => { st.mo = {}; dsMo.delete(st); tai().then(st.ve); });
  });

  const maLoai = (v) => String(v || '').trim().split(/[\s—–-]/)[0].toUpperCase();
  const NHIEU = { B1: 1, F1: 1 };
  const chuan = (s) => String(s || '').toLowerCase().normalize('NFC');
  const coChu = (txt, cum) => chuan(txt).indexOf(chuan(cum)) >= 0;

  function hop(el) {
    if (!el) return null;
    if (el._scmHop) return el._scmHop;
    const d = document.createElement('div');
    d.className = 'scm';
    el.parentNode.insertBefore(d, el);
    el._scmHop = d;
    return d;
  }
  function opt(text, on, click, khac) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'scm-o' + (on ? ' on' : '') + (khac ? ' khac' : '');
    b.textContent = text;
    b.onclick = click;
    return b;
  }
  // Ô xổ xuống: dòng tóm tắt (bấm để mở / đóng) + danh sách lựa chọn.
  function oXo(hopEl, st, khoa, tomTat, trong, mo) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'scm-dd' + (mo ? ' mo' : '');
    const t = document.createElement('span');
    t.className = 'scm-dd-t' + (tomTat ? '' : ' trong');
    t.textContent = tomTat || trong;
    if (tomTat) b.title = tomTat;
    const m = document.createElement('span');
    m.className = 'scm-dd-m';
    m.textContent = mo ? '▴' : '▾';
    b.append(t, m);
    b.onclick = () => { st.mo = mo ? {} : { [khoa]: 1 }; st.mo[khoa] ? dsMo.add(st) : dsMo.delete(st); tai().then(st.ve); };
    hopEl.appendChild(b);
    if (!mo) return null;
    const ds = document.createElement('div');
    ds.className = 'scm-ds';
    hopEl.appendChild(ds);
    return ds;
  }
  function batInput(ta) { ta.dispatchEvent(new Event('input', { bubbles: true })); }
  // Thêm / bỏ 1 cụm trong ô chữ, giữ nguyên phần người dùng tự gõ.
  function themCum(ta, cum, sep) {
    const v = ta.value.trim();
    ta.value = v ? v.replace(/[,;.\s]*$/, sep === ', ' ? '' : '.') + (sep === ', ' ? ', ' : ' ') + cum : cum;
    batInput(ta);
  }
  function boCum(ta, cum) {
    const i = chuan(ta.value).indexOf(chuan(cum));
    if (i < 0) return;
    ta.value = (ta.value.slice(0, i) + ta.value.slice(i + cum.length))
      .replace(/^[\s,;]+/, '').replace(/\s*,\s*,\s*/g, ', ').replace(/[\s,;]+$/, '').replace(/\s{2,}/g, ' ');
    batInput(ta);
  }

  function gan(o) {
    napCss();
    const ta = o.xuLy;
    if (!ta) return;
    const st = ta._scm || (ta._scm = {});
    st.o = o;
    st.chon = null;   // null = chưa chọn tay → tự khớp theo chữ vấn đề
    st.mo = {};       // danh sách đang xổ: { vd: 1 } hoặc { xl: 1 }
    const hopVd = hop(o.vanDe || ta), hopXl = o.vanDe ? hop(ta) : (st.hopXl || (st.hopXl = (() => {
      const d = document.createElement('div'); d.className = 'scm'; hopVd.after(d); return d;
    })()));
    if (!o.vanDe) hopVd.classList.add('scm-vd');
    const loaiNow = () => maLoai(typeof o.loai === 'string' ? o.loai : (o.loai && o.loai.value));

    function ve(list) {
      const code = loaiNow();
      const ds = list.filter((x) => (x.loai || []).indexOf(code) >= 0);
      hopVd.innerHTML = ''; hopXl.innerHTML = '';
      if (!ds.length) return;
      const nhieu = !!NHIEU[code];
      const txtVd = o.vanDe ? o.vanDe.value : (o.vanDeText || '');
      if (!st.chon) st.chon = ds.filter((x) => txtVd && coChu(txtVd, x.van_de)).map((x) => x.ma);
      if (!nhieu && st.chon.length > 1) st.chon = st.chon.slice(0, 1);

      const dong = () => { st.mo = {}; dsMo.delete(st); };
      const tenChon = st.chon.map((m) => (ds.find((y) => y.ma === m) || {}).van_de).filter(Boolean);
      const dsVd = oXo(hopVd, st, 'vd', tenChon.join(', '), nhieu ? 'Chọn vấn đề (chọn nhiều được)' : 'Chọn vấn đề', !!st.mo.vd);
      if (dsVd) {
        ds.forEach((x) => {
          const on = st.chon.indexOf(x.ma) >= 0;
          dsVd.appendChild(opt(x.van_de, on, () => {
            if (on) {
              st.chon = st.chon.filter((m) => m !== x.ma);
              if (o.vanDe) boCum(o.vanDe, x.van_de);
            } else {
              if (!nhieu) {
                const cu = ds.find((y) => y.ma === st.chon[0]);
                if (cu && o.vanDe) boCum(o.vanDe, cu.van_de);
                st.chon = [];
              }
              st.chon.push(x.ma);
              if (o.vanDe && !coChu(o.vanDe.value, x.van_de)) themCum(o.vanDe, x.van_de, ', ');
            }
            if (!nhieu) dong();
            ve(list);
          }));
        });
        if (o.vanDe) dsVd.appendChild(opt('Khác… (tự gõ)', false, () => { dong(); ve(list); o.vanDe.focus(); }, true));
      }

      const xl = [];
      st.chon.forEach((m) => { const x = ds.find((y) => y.ma === m); (x && x.xu_ly || []).forEach((t) => { if (xl.indexOf(t) < 0) xl.push(t); }); });
      if (!xl.length) return;
      const soXl = xl.filter((t) => coChu(ta.value, t)).length;
      const dsXl = oXo(hopXl, st, 'xl', soXl ? 'Đã chọn ' + soXl + ' cách xử lý' : '', 'Chọn cách xử lý (chọn nhiều được)', !!st.mo.xl);
      if (!dsXl) return;
      xl.forEach((t) => {
        const on = coChu(ta.value, t);
        dsXl.appendChild(opt(t, on, () => { on ? boCum(ta, t) : themCum(ta, t, ' '); ve(list); }));
      });
      dsXl.appendChild(opt('Khác… (tự gõ)', false, () => { dong(); ve(list); ta.focus(); }, true));
    }

    const veLai = () => tai().then(ve);
    if (o.loai && typeof o.loai !== 'string' && !o.loai._scmNghe) {
      o.loai._scmNghe = true;
      o.loai.addEventListener('change', () => { if (ta._scm.o.loai === o.loai) { ta._scm.chon = null; tai().then(ta._scm.ve); } });
    }
    if (!ta._scmNghe) {   // gõ tay → cập nhật dấu ✓ trên nút
      ta._scmNghe = true;
      let hen = null;
      ta.addEventListener('input', () => { clearTimeout(hen); hen = setTimeout(() => tai().then(ta._scm.ve), 250); });
    }
    st.ve = ve;
    veLai();
  }

  window.SuCoMau = { tai, gan };
})();
